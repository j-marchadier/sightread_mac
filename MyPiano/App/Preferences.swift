import Foundation
import MyPianoCore

/// Keys of the app-wide preferences (UserDefaults, edited in the Settings window).
enum PreferenceKey {
    static let noteNaming = "display.noteNaming"
    static let visualization = "display.visualization"
    static let fullKeyboard = "display.fullKeyboard"
    static let showsNoteNames = "display.showsNoteNames"
    static let coloredNotes = "display.coloredNotes"
    static let fallingSpeed = "display.fallingSpeed"
    static let fingering = "display.fingering"
    static let defaultMode = "practice.defaultMode"
    static let waitTolerance = "practice.waitTolerance"
    static let countdown = "practice.countdown"
    static let wrongNoteSound = "practice.wrongNoteSound"
    static let metronomeVolume = "practice.metronomeVolume"
    static let computerKeyboardPiano = "input.computerKeyboardPiano"
    static let masterVolume = "audio.masterVolume"
    static let playerVolume = "audio.playerVolume"
    static let songVolume = "audio.songVolume"
    static let onboardingDone = "onboarding.done"
}

/// Typed access to the preferences, with defaults.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    static var noteNaming: NoteNamingStyle {
        NoteNamingStyle(rawValue: defaults.string(forKey: PreferenceKey.noteNaming) ?? "") ?? .solfege
    }

    static var display: DisplayOptions {
        var options = DisplayOptions()
        options.visualization = Visualization(rawValue: defaults.string(forKey: PreferenceKey.visualization) ?? "") ?? .fallingNotes
        options.fullKeyboard = defaults.object(forKey: PreferenceKey.fullKeyboard) as? Bool ?? true
        options.showsNoteNames = defaults.bool(forKey: PreferenceKey.showsNoteNames)
        options.coloredNotes = defaults.bool(forKey: PreferenceKey.coloredNotes)
        options.naming = noteNaming
        let speed = defaults.double(forKey: PreferenceKey.fallingSpeed)
        options.pointsPerSecond = speed > 0 ? speed : 220
        options.fingering = FingeringDisplay(rawValue: defaults.string(forKey: PreferenceKey.fingering) ?? "") ?? .all
        return options
    }

    static func save(_ display: DisplayOptions) {
        defaults.set(display.visualization.rawValue, forKey: PreferenceKey.visualization)
        defaults.set(display.fullKeyboard, forKey: PreferenceKey.fullKeyboard)
        defaults.set(display.showsNoteNames, forKey: PreferenceKey.showsNoteNames)
        defaults.set(display.coloredNotes, forKey: PreferenceKey.coloredNotes)
        defaults.set(display.naming.rawValue, forKey: PreferenceKey.noteNaming)
        defaults.set(display.pointsPerSecond, forKey: PreferenceKey.fallingSpeed)
        defaults.set(display.fingering.rawValue, forKey: PreferenceKey.fingering)
    }

    /// Settings for a song practised for the first time.
    static func newSongSettings(handAssignment: HandAssignment) -> PracticeSettings {
        var settings = PracticeSettings(handAssignment: handAssignment)
        settings.mode = PracticeMode(rawValue: defaults.string(forKey: PreferenceKey.defaultMode) ?? "") ?? .learn
        if defaults.object(forKey: PreferenceKey.waitTolerance) != nil {
            settings.waitTolerance = defaults.double(forKey: PreferenceKey.waitTolerance)
        }
        settings.countdownEnabled = defaults.object(forKey: PreferenceKey.countdown) as? Bool ?? true
        settings.wrongNoteSound = defaults.bool(forKey: PreferenceKey.wrongNoteSound)
        if defaults.object(forKey: PreferenceKey.metronomeVolume) != nil {
            settings.metronome.volume = Float(defaults.double(forKey: PreferenceKey.metronomeVolume))
        }
        return settings
    }

    static var computerKeyboardPiano: Bool { defaults.bool(forKey: PreferenceKey.computerKeyboardPiano) }

    static func volume(_ key: String) -> Float {
        defaults.object(forKey: key) == nil ? 1 : Float(defaults.double(forKey: key))
    }

    static func setVolume(_ volume: Float, _ key: String) {
        defaults.set(Double(volume), forKey: key)
    }
}
