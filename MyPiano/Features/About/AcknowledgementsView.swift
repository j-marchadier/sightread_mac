import SwiftUI

/// The "Mentions" window: renders ACKNOWLEDGEMENTS.md, bundled with the app, so the licences of the
/// built-in songs, the Leland font and the GPL inspiration ship with every copy.
struct AcknowledgementsView: View {
    private let blocks = MarkdownBlock.parse(Self.loadText())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks.indices, id: \.self) { index in
                    BlockView(block: blocks[index])
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 420, idealHeight: 640)
    }

    private static func loadText() -> String {
        guard let url = Bundle.main.url(forResource: "ACKNOWLEDGEMENTS", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }
}

/// The subset of Markdown used by ACKNOWLEDGEMENTS.md.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case table(header: [String], rows: [[String]])

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var table: [[String]] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            if let header = table.first { blocks.append(.table(header: header, rows: Array(table.dropFirst()))) }
            paragraph = []
            bullets = []
            table = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("#") {
                flush()
                let level = line.prefix { $0 == "#" }.count
                blocks.append(.heading(level: level, text: line.dropFirst(level).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("|") {
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // Skip the |---|---| separator row.
                if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { table.append(cells) }
            } else if line.hasPrefix("- ") {
                if !paragraph.isEmpty || !table.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)))
            } else if !bullets.isEmpty, rawLine.hasPrefix(" ") {
                bullets[bullets.count - 1] += " " + line
            } else {
                if !bullets.isEmpty || !table.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(level == 1 ? .largeTitle.bold() : level == 2 ? .title2.bold() : .headline)
                .padding(.top, level == 1 ? 0 : 8)
        case let .paragraph(text):
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        case let .bullets(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(items[index])).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .table(header, rows):
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        Text(inline(header[column])).font(.callout.bold())
                    }
                }
                Divider()
                ForEach(rows.indices, id: \.self) { row in
                    GridRow(alignment: .firstTextBaseline) {
                        ForEach(rows[row].indices, id: \.self) { column in
                            Text(inline(rows[row][column]))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func inline(_ text: String) -> AttributedString {
        // Angle-bracket autolinks are not part of inline Markdown: turn them into regular links.
        let source = text.replacing(#/<(https?:\/\/[^>]+)>/#) { match in "[\(match.1)](\(match.1))" }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var attributed = try? AttributedString(markdown: source, options: options) else { return AttributedString(text) }
        // Repository-relative links (e.g. LICENSE) have no meaning inside the app.
        for run in attributed.runs where run.link?.scheme == nil {
            attributed[run.range].link = nil
        }
        return attributed
    }
}
