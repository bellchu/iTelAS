import Foundation

public struct TN5250DeviceCapabilities: Equatable, Sendable {
    public let terminalModel: TerminalModel

    public init(terminalModel: TerminalModel) {
        self.terminalModel = terminalModel
    }

    public var deviceType: String {
        switch terminalModel {
        case .ibm3179_2: "3179"
        case .ibm3477_FC: "3477"
        }
    }

    public var deviceModel: String {
        switch terminalModel {
        case .ibm3179_2: "002"
        case .ibm3477_FC: "FC "
        }
    }

    /// RFC 1205 byte 49, using IBM high-order bit numbering:
    /// limited Row 1/Column 1, Read MDT Alternate, and Move Cursor.
    public var controllerDisplayCapabilityByte: UInt8 { 0x62 }

    /// RFC 1205 byte 50: selected screen geometry plus 3179-style color.
    public var screenCapabilityByte: UInt8 {
        switch terminalModel {
        case .ibm3179_2: 0x11
        case .ibm3477_FC: 0x31
        }
    }

    public var summary: String {
        "Reported \(terminalModel.telnetName) · \(terminalModel.rows)×\(terminalModel.columns) · Row 1/Column 1 · Read MDT Alternate · Move Cursor."
    }

    fileprivate var deviceTypeEBCDIC: [UInt8] {
        switch terminalModel {
        case .ibm3179_2: [0xF3, 0xF1, 0xF7, 0xF9]
        case .ibm3477_FC: [0xF3, 0xF4, 0xF7, 0xF7]
        }
    }

    fileprivate var deviceModelEBCDIC: [UInt8] {
        switch terminalModel {
        case .ibm3179_2: [0xF0, 0xF0, 0xF2]
        case .ibm3477_FC: [0xC6, 0xC3, 0x40]
        }
    }
}

public enum TN5250DeviceQuery {
    public static let command = Data([0x04, 0xF3, 0x00, 0x05, 0xD9, 0x70, 0x00])

    /// A Query is an input command, not a byte signature that may be matched
    /// inside arbitrary WTD data. Accept only the complete RFC 1205 command.
    public static func matches(_ payload: Data) -> Bool {
        payload == command
    }

    public static func reply(for capabilities: TN5250DeviceCapabilities) -> TN5250Record {
        var payload: [UInt8] = [
            0x00, 0x00,                   // Cursor row/column
            0x88,                         // Inbound WSF AID
            0x00, 0x3A,                   // Query-reply length
            0xD9, 0x70, 0x80,             // Query class/type/reply flag
            0x06, 0x00,                   // Other 5250 emulator
            0x00, 0x01, 0x00              // iTelAS 0.1.0 code level
        ]
        payload.append(contentsOf: repeatElement(0x00, count: 16))
        payload.append(0x01)               // 5250 display/emulation
        payload.append(contentsOf: capabilities.deviceTypeEBCDIC)
        payload.append(contentsOf: capabilities.deviceModelEBCDIC)
        payload.append(contentsOf: [0x02, 0x00, 0x00]) // Standard keyboard
        payload.append(contentsOf: repeatElement(0x00, count: 4)) // No serial
        payload.append(contentsOf: [0x01, 0x00])       // 256 input fields
        payload.append(contentsOf: repeatElement(0x00, count: 3))
        payload.append(contentsOf: [
            capabilities.controllerDisplayCapabilityByte,
            capabilities.screenCapabilityByte,
            0x00,                         // Reserved
            0x00,                         // No DBCS presentation capability
            0x00                          // No graphics capability
        ])
        payload.append(contentsOf: repeatElement(0x00, count: 7))
        return TN5250Record(opcode: .noOperation, payload: Data(payload))
    }
}
