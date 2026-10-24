#if canImport(SwiftUI)
/// Hooks for measuring drawing performance (the app's performance probe). Unset in normal use.
@MainActor
public enum RenderingDiagnostics {
    /// Called each time a falling-notes or score view draws a frame.
    public static var onDraw: (() -> Void)?
}
#endif
