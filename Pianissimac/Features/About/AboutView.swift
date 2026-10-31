import AppKit
import SwiftUI

/// The "About Pianissimac" window: icon, version and copyright, with a link to the acknowledgements.
struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var version: String { info["CFBundleShortVersionString"] as? String ?? "—" }
    private var build: String { info["CFBundleVersion"] as? String ?? "—" }
    private var copyright: String { info["NSHumanReadableCopyright"] as? String ?? "" }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            Text("Pianissimac").font(.largeTitle.bold())
            Text("Version \(version) (\(build))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Apprenez le piano avec votre clavier MIDI : notes qui tombent, partitions, doigtés et exercices, entièrement hors ligne.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Button("Mentions et licences…") { openWindow(id: WindowID.acknowledgements) }
                .buttonStyle(.glass)
                .tint(.clear)
                .padding(.top, 4)
            Text(copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(width: 380)
    }
}
