#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import QuartzCore
import SwiftUI

/// Rebuilds its content exactly once per refresh of the screen showing it.
///
/// `TimelineView(.animation)` re-evaluates its content on every render pass of the window, and the
/// window renders more often than the screen refreshes (layout of the toolbar, glass, controls…),
/// so a `Canvas` inside it drew two or three times per displayed frame. Here the content depends on a
/// counter advanced by the screen's display link: extra render passes reuse the last frame.
public struct DisplayTicker<Content: View>: View {
    /// Target presentation time of the frame being prepared.
    @State private var frameTime: CFTimeInterval = 0
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        TickedContent(frameTime: frameTime, content: content)
            .equatable()
            .background(DisplayLinkView { time in
                // Several links may fire for the same refresh: only a new frame time rebuilds the content.
                if time != frameTime { frameTime = time }
            })
    }
}

/// Re-evaluated only when `frameTime` changes.
private struct TickedContent<Content: View>: View, Equatable {
    let frameTime: CFTimeInterval
    let content: () -> Content

    var body: some View { content() }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.frameTime == rhs.frameTime }
}

/// An invisible view whose display link calls `onFrame` with each frame's target time, at the refresh
/// rate of its screen.
private struct DisplayLinkView: NSViewRepresentable {
    let onFrame: @MainActor (CFTimeInterval) -> Void

    func makeNSView(context: Context) -> LinkView {
        let view = LinkView()
        view.onFrame = onFrame
        return view
    }

    func updateNSView(_ view: LinkView, context: Context) {
        view.onFrame = onFrame
    }

    static func dismantleNSView(_ view: LinkView, coordinator: ()) {
        view.stop()
    }

    final class LinkView: NSView {
        var onFrame: (@MainActor (CFTimeInterval) -> Void)?
        private var link: CADisplayLink?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            // Follows the window to whichever screen it is on, at that screen's rate.
            let link = displayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            onFrame?(link.targetTimestamp)
        }
    }
}
#endif
