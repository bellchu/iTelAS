import Foundation

public enum TN5250AID: UInt8, CaseIterable, Sendable {
    case forwardEdgeTrigger = 0x50
    case enter = 0xF1
    case help = 0xF3
    case rollUp = 0xF4
    case rollDown = 0xF5
    case print = 0xF6
    case clear = 0xBD

    public static func function(_ number: Int) -> UInt8? {
        guard (1...24).contains(number) else { return nil }
        return number <= 12 ? UInt8(0x30 + number) : UInt8(0xB0 + number - 12)
    }

    public static func functionNumber(for aid: UInt8) -> Int? {
        if (0x31...0x3C).contains(aid) {
            return Int(aid - 0x30)
        }
        if (0xB1...0xBC).contains(aid) {
            return Int(aid - 0xB0) + 12
        }
        return nil
    }

    /// Read-MDT field data accompanies Forward Edge Trigger, Enter, Roll
    /// Up/Down, and unmasked command-function keys. Other AIDs carry
    /// cursor/AID state only.
    public static func carriesModifiedFields(_ aid: UInt8) -> Bool {
        aid == forwardEdgeTrigger.rawValue
            || aid == enter.rawValue
            || aid == rollUp.rawValue
            || aid == rollDown.rawValue
            || (0x31...0x3C).contains(aid)
            || (0xB1...0xBC).contains(aid)
    }
}
