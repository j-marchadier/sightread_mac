import AppKit

/// Receives files opened from the Finder ("Open With", double-click) or dropped on the Dock icon.
/// Files arriving before the app is ready are kept until a handler is installed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pending: [URL] = []

    var openHandler: (([URL]) -> Void)? {
        didSet {
            guard let openHandler, !pending.isEmpty else { return }
            let urls = pending
            pending.removeAll()
            openHandler(urls)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openHandler { openHandler(urls) } else { pending += urls }
    }
}
