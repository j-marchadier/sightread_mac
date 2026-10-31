#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// Reports trackpad and mouse-wheel scrolling over a SwiftUI view without blocking clicks.
struct ScrollWheelReader: NSViewRepresentable {
    let onScroll: @MainActor (Double) -> Void
    let onEnded: @MainActor () -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: ScrollWheelView, context: Context) {
        view.onScroll = onScroll
        view.onEnded = onEnded
    }
}

final class ScrollWheelView: NSView {
    var onScroll: (@MainActor (Double) -> Void)?
    var onEnded: (@MainActor () -> Void)?

    /// Only scroll events stop here; clicks and drags reach the SwiftUI view underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        onScroll?(delta)
        let gestureEnded = event.phase == .ended || event.phase == .cancelled
        let momentumEnded = event.momentumPhase == .ended
        let discreteWheel = event.phase.isEmpty && event.momentumPhase.isEmpty
        if (gestureEnded && event.momentumPhase.isEmpty) || momentumEnded || discreteWheel {
            onEnded?()
        }
    }
}
#endif
