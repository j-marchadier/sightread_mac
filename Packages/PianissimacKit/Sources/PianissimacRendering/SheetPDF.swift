#if canImport(SwiftUI)
import CoreGraphics
import Foundation
import PianissimacCore
import SwiftUI

/// Lays a score out on printed pages, like the full-page view without the cursor, and renders it as a PDF.
@MainActor
public enum SheetPDF {
    /// A4 portrait, in points.
    public static let a4 = CGSize(width: 595.28, height: 841.89)

    /// - Parameters:
    ///   - title: Printed at the top of the first page, with `subtitle` (the composer) under it.
    ///   - pageLabel: Footer of each page, from its number and the page count (both from 1).
    public static func render(
        scene: SheetScene, title: String, subtitle: String?, pageSize: CGSize = a4,
        pageLabel: (Int, Int) -> String
    ) -> Data {
        let margin: CGFloat = 40
        let titleHeight: CGFloat = subtitle == nil ? 52 : 74
        let footerHeight: CGFloat = 22
        var printScene = scene
        printScene.activeHands = [.left, .right]
        let geometry = PageGeometry(
            scene: printScene, size: CGSize(width: pageSize.width - margin * 2, height: pageSize.height),
            palette: SheetPalette.standard(for: .light), staffSpace: 5.5
        )

        // Split the lines over the pages; the first page also holds the title.
        let systems = geometry.layout.systems
        var pages: [Range<Int>] = []
        var next = 0
        while next < systems.count || pages.isEmpty {
            let available = pageSize.height - margin * 2 - footerHeight - (pages.isEmpty ? titleHeight : 0)
            let count = max(1, Int(available / geometry.systemHeight))
            let end = min(systems.count, next + count)
            pages.append(next..<end)
            next = end
        }

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }
        for (index, range) in pages.enumerated() {
            let page = SheetPrintedPage(
                geometry: geometry, systems: range,
                title: index == 0 ? title : nil, subtitle: index == 0 ? subtitle : nil,
                titleHeight: titleHeight, footer: pageLabel(index + 1, pages.count), footerHeight: footerHeight,
                margin: margin
            )
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }
}

/// One printed page: optional title block, lines of music, page footer.
private struct SheetPrintedPage: View {
    let geometry: PageGeometry
    let systems: Range<Int>
    let title: String?
    let subtitle: String?
    let titleHeight: CGFloat
    let footer: String
    let footerHeight: CGFloat
    let margin: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                VStack(spacing: 4) {
                    Text(title).font(.system(size: 22, weight: .semibold, design: .serif))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 13, design: .serif)).foregroundStyle(Color(white: 0.3))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: titleHeight, alignment: .top)
            }
            Canvas { context, _ in
                // A time before the song: no cursor, no faded notes.
                let frame = FallingNotesFrame(time: -1)
                for (row, index) in systems.enumerated() {
                    var line = context
                    line.translateBy(x: 0, y: CGFloat(row) * geometry.systemHeight)
                    geometry.renderer.drawSystem(geometry.layout.systems[index], isFirst: index == 0, in: &line, frame: frame)
                }
            }
            .frame(height: CGFloat(systems.count) * geometry.systemHeight)
            Spacer(minLength: 0)
            Text(footer)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.45))
                .frame(height: footerHeight, alignment: .bottom)
        }
        .foregroundStyle(Color(white: 0.08))
        .padding(margin)
        .background(Color.white)
    }
}
#endif
