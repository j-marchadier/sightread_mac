#if canImport(CoreMIDI)
import CoreMIDI
import Foundation
import PianissimacCore
import Observation

/// Listens to MIDI keyboards.
///
/// - Sources are rescanned whenever a device is plugged in or removed, and the chosen inputs are
///   reconnected automatically.
/// - Events are delivered on CoreMIDI's high-priority thread with their hardware timestamp,
///   through ``setEventHandler(_:)``: the handler must return quickly (start a sound, record a hit).
@MainActor
@Observable
public final class MIDIService {
    /// Every MIDI input currently known to the system.
    public private(set) var sources: [MIDISourceDescriptor] = []
    /// Inputs Pianissimac is listening to.
    public private(set) var connectedSources: [MIDISourceDescriptor] = []
    public private(set) var selection: MIDIInputSelection
    /// Last CoreMIDI error, if setting up MIDI failed.
    public private(set) var errorDescription: String?

    public var status: MIDIConnectionStatus { MIDIConnectionStatus(connected: connectedSources) }

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inputPort = MIDIPortRef()
    @ObservationIgnored private var endpoints: [Int32: MIDIEndpointRef] = [:]
    @ObservationIgnored private var connectedIDs: Set<Int32> = []
    @ObservationIgnored private let router = MIDIEventRouter()
    @ObservationIgnored private let defaults: UserDefaults
    private static let selectionKey = "midi.inputSelection"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.selectionKey),
           let saved = try? JSONDecoder().decode(MIDIInputSelection.self, from: data) {
            selection = saved
        } else {
            selection = .automatic
        }
    }

    /// Receives every decoded event on CoreMIDI's thread.
    public func setEventHandler(_ handler: (@Sendable (InputEvent) -> Void)?) {
        router.setHandler(handler)
    }

    public func start() {
        guard client == 0 else { return }
        // Both blocks run on CoreMIDI threads: `@Sendable` keeps them out of the main actor's isolation.
        var status = MIDIClientCreateWithBlock("Pianissimac" as CFString, &client) { @Sendable [weak self] notification in
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                let service = self
                Task { @MainActor in service?.refresh() }
            default:
                break
            }
        }
        guard status == noErr else {
            errorDescription = "MIDIClientCreate \(status)"
            return
        }
        let router = self.router
        status = MIDIInputPortCreateWithProtocol(client, "Pianissimac Input" as CFString, ._1_0, &inputPort) { @Sendable eventList, _ in
            router.deliver(MIDIService.decode(eventList))
        }
        guard status == noErr else {
            errorDescription = "MIDIInputPortCreate \(status)"
            return
        }
        refresh()
    }

    public func setSelection(_ newSelection: MIDIInputSelection) {
        selection = newSelection
        if let data = try? JSONEncoder().encode(newSelection) {
            defaults.set(data, forKey: Self.selectionKey)
        }
        reconnect()
    }

    /// Rescans sources and reconnects according to the selection.
    public func refresh() {
        var found: [MIDISourceDescriptor] = []
        var refs: [Int32: MIDIEndpointRef] = [:]
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            let id = Self.integerProperty(endpoint, kMIDIPropertyUniqueID)
            let descriptor = MIDISourceDescriptor(
                id: id,
                name: Self.stringProperty(endpoint, kMIDIPropertyDisplayName) ?? Self.stringProperty(endpoint, kMIDIPropertyName) ?? "MIDI \(index + 1)",
                manufacturer: Self.stringProperty(endpoint, kMIDIPropertyManufacturer),
                isOffline: Self.integerProperty(endpoint, kMIDIPropertyOffline) != 0
            )
            found.append(descriptor)
            refs[id] = endpoint
        }
        sources = found
        // Connections to vanished endpoints are dropped by CoreMIDI itself.
        connectedIDs.formIntersection(refs.keys)
        endpoints = refs
        reconnect()
    }

    private func reconnect() {
        guard inputPort != 0 else { return }
        let wanted = MIDISourcePolicy.sourcesToConnect(available: sources, selection: selection)
        let wantedIDs = Set(wanted.map(\.id))
        for id in connectedIDs.subtracting(wantedIDs) {
            if let endpoint = endpoints[id] { MIDIPortDisconnectSource(inputPort, endpoint) }
            connectedIDs.remove(id)
        }
        for source in wanted where !connectedIDs.contains(source.id) {
            guard let endpoint = endpoints[source.id] else { continue }
            if MIDIPortConnectSource(inputPort, endpoint, nil) == noErr {
                connectedIDs.insert(source.id)
            }
        }
        connectedSources = sources.filter { connectedIDs.contains($0.id) }
    }

    nonisolated static func decode(_ list: UnsafePointer<MIDIEventList>) -> [InputEvent] {
        var events: [InputEvent] = []
        for packet in list.unsafeSequence() {
            let count = min(Int(packet.pointee.wordCount), 64)
            let stamp = packet.pointee.timeStamp
            let time = stamp == 0 ? HostTime.now : HostTime.seconds(fromHostTicks: stamp)
            let words: [UInt32] = withUnsafeBytes(of: packet.pointee.words) { raw in
                Array(raw.bindMemory(to: UInt32.self).prefix(count))
            }
            events += MIDIMessageDecoder.decode(umpWords: words, time: time)
        }
        return events
    }

    private static func stringProperty(_ object: MIDIObjectRef, _ key: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, key, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func integerProperty(_ object: MIDIObjectRef, _ key: CFString) -> Int32 {
        var value: Int32 = 0
        MIDIObjectGetIntegerProperty(object, key, &value)
        return value
    }
}

/// Hands events from CoreMIDI's thread to the current handler.
final class MIDIEventRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (InputEvent) -> Void)?

    func setHandler(_ handler: (@Sendable (InputEvent) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func deliver(_ events: [InputEvent]) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else { return }
        for event in events { handler(event) }
    }
}
#endif
