import Foundation

/// A MIDI input as reported by the system.
public struct MIDISourceDescriptor: Sendable, Hashable, Identifiable {
    /// Persistent identifier (CoreMIDI `kMIDIPropertyUniqueID`).
    public var id: Int32
    /// Full display name, e.g. "KL Essential 61 mk3 MIDI".
    public var name: String
    public var manufacturer: String?
    public var isOffline: Bool

    public init(id: Int32, name: String, manufacturer: String? = nil, isOffline: Bool = false) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.isOffline = isOffline
    }
}

/// Which inputs to listen to.
public enum MIDIInputSelection: Sendable, Equatable, Codable {
    /// Every keyboard port, skipping pass-through, DAW-control and virtual ports.
    case automatic
    /// Only the chosen inputs (kept even while unplugged, reconnected when they return).
    case manual(Set<Int32>)
}

public enum MIDISourcePolicy {
    /// Words marking ports that do not carry what the player plays:
    /// MIDI through ports, control-surface protocols (Mackie Control, HUI, DAW modes),
    /// Arturia's Analog Lab port and the IAC virtual bus.
    static let ignoredWords: Set<String> = ["thru", "through", "mcu", "hui", "daw", "alv", "iac", "network", "session"]

    /// `true` for ports that carry the keys and pedals of a keyboard.
    public static func isPerformancePort(_ source: MIDISourceDescriptor) -> Bool {
        let words = source.name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return !words.contains { ignoredWords.contains($0) || $0.hasSuffix("thru") }
    }

    /// Inputs to connect for a selection, among the sources currently available.
    public static func sourcesToConnect(available: [MIDISourceDescriptor], selection: MIDIInputSelection) -> [MIDISourceDescriptor] {
        let online = available.filter { !$0.isOffline }
        switch selection {
        case .automatic:
            return online.filter(isPerformancePort)
        case let .manual(ids):
            return online.filter { ids.contains($0.id) }
        }
    }
}

/// What the interface shows about the keyboard connection.
public enum MIDIConnectionStatus: Sendable, Equatable {
    case noKeyboard
    case connected(names: [String])

    public init(connected: [MIDISourceDescriptor]) {
        self = connected.isEmpty ? .noKeyboard : .connected(names: connected.map(\.name))
    }

    public var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}
