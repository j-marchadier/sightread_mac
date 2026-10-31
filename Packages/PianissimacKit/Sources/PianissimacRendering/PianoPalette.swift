#if canImport(SwiftUI)
import PianissimacCore
import SwiftUI

/// Colours of the play surface, for light and dark appearance.
public struct PianoPalette: Sendable {
    public var background: Color
    public var octaveLine: Color
    public var measureLine: Color
    public var measureText: Color
    public var hitLine: Color
    public var loopFill: Color
    public var rightHand: Color
    public var rightHandOnBlack: Color
    public var leftHand: Color
    public var leftHandOnBlack: Color
    public var accompaniment: Color
    public var missed: Color
    public var noteText: Color
    public var whiteKey: Color
    public var whiteKeyBorder: Color
    public var blackKey: Color
    public var keyLabel: Color
    public var pressedKey: Color
    public var wrongKey: Color

    public static func standard(for scheme: ColorScheme) -> PianoPalette {
        let dark = scheme == .dark
        return PianoPalette(
            background: dark ? Color(red: 0.07, green: 0.075, blue: 0.09) : Color(red: 0.95, green: 0.95, blue: 0.97),
            octaveLine: dark ? .white.opacity(0.07) : .black.opacity(0.07),
            measureLine: dark ? .white.opacity(0.12) : .black.opacity(0.12),
            measureText: dark ? .white.opacity(0.45) : .black.opacity(0.45),
            hitLine: Color.accentColor,
            loopFill: Color.accentColor.opacity(dark ? 0.12 : 0.10),
            rightHand: Color(red: 0.29, green: 0.52, blue: 0.98),
            rightHandOnBlack: Color(red: 0.18, green: 0.36, blue: 0.80),
            leftHand: Color(red: 0.99, green: 0.58, blue: 0.24),
            leftHandOnBlack: Color(red: 0.84, green: 0.42, blue: 0.12),
            accompaniment: dark ? .white.opacity(0.22) : .black.opacity(0.18),
            missed: Color(white: 0.55),
            noteText: .white,
            whiteKey: Color(red: 0.99, green: 0.99, blue: 0.98),
            whiteKeyBorder: Color.black.opacity(0.25),
            blackKey: Color(red: 0.11, green: 0.11, blue: 0.13),
            keyLabel: Color.black.opacity(0.4),
            pressedKey: Color(white: 0.62),
            wrongKey: Color(red: 0.92, green: 0.23, blue: 0.23)
        )
    }

    public func color(for hand: Hand?, onBlackKey: Bool) -> Color {
        switch hand {
        case .right: onBlackKey ? rightHandOnBlack : rightHand
        case .left: onBlackKey ? leftHandOnBlack : leftHand
        case nil: accompaniment
        }
    }
}
#endif
