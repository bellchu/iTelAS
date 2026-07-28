import Foundation

public enum TN5250RecordError: Error, Equatable, LocalizedError, Sendable {
    case tooShort
    case invalidLength(expected: Int, available: Int)
    case invalidRecordType(UInt16)
    case invalidVariableHeaderLength(Int)

    public var errorDescription: String? {
        switch self {
        case .tooShort:
            "The TN5250 record is shorter than its ten-byte header."
        case .invalidLength(let expected, let available):
            "The TN5250 header declares \(expected) bytes, but only \(available) arrived."
        case .invalidRecordType(let type):
            "Unsupported TN5250 record type 0x\(String(type, radix: 16, uppercase: true))."
        case .invalidVariableHeaderLength(let length):
            "Invalid TN5250 variable header length \(length)."
        }
    }
}

public enum TN5250Opcode: UInt8, Codable, Sendable {
    case noOperation = 0x00
    case invite = 0x01
    case outputOnly = 0x02
    case putGet = 0x03
    case saveScreen = 0x04
    case restoreScreen = 0x05
    case readImmediate = 0x06
    case readScreen = 0x08
    case cancelInvite = 0x0A
    case messageLightOn = 0x0B
    case messageLightOff = 0x0C
}

public struct TN5250Record: Equatable, Sendable {
    public static let generalDataStream: UInt16 = 0x12A0

    public let logicalLength: Int
    public let recordType: UInt16
    public let dataFlowFlags: UInt16
    public let variableHeader: Data
    public let flags: UInt16
    public let opcodeByte: UInt8
    public let payload: Data

    public var opcode: TN5250Opcode? { TN5250Opcode(rawValue: opcodeByte) }

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 10 else { throw TN5250RecordError.tooShort }
        let length = Int(bytes[0]) << 8 | Int(bytes[1])
        guard length >= 10, length <= bytes.count else {
            throw TN5250RecordError.invalidLength(expected: length, available: bytes.count)
        }
        let type = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        guard type == Self.generalDataStream else {
            throw TN5250RecordError.invalidRecordType(type)
        }
        let variableLength = Int(bytes[6])
        guard variableLength >= 4, 6 + variableLength <= length else {
            throw TN5250RecordError.invalidVariableHeaderLength(variableLength)
        }
        logicalLength = length
        recordType = type
        dataFlowFlags = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        variableHeader = Data(bytes[6..<(6 + variableLength)])
        flags = UInt16(bytes[7]) << 8 | UInt16(bytes[8])
        opcodeByte = bytes[9]
        payload = Data(bytes[(6 + variableLength)..<length])
    }

    public init(
        opcode: TN5250Opcode,
        dataFlowFlags: UInt16 = 0,
        flags: UInt16 = 0,
        payload: Data = Data()
    ) {
        let variableHeader = Data([
            0x04,
            UInt8((flags >> 8) & 0xFF),
            UInt8(flags & 0xFF),
            opcode.rawValue
        ])
        logicalLength = 6 + variableHeader.count + payload.count
        recordType = Self.generalDataStream
        self.dataFlowFlags = dataFlowFlags
        self.variableHeader = variableHeader
        self.flags = flags
        opcodeByte = opcode.rawValue
        self.payload = payload
    }

    public func encoded() -> Data {
        var bytes: [UInt8] = [
            UInt8((logicalLength >> 8) & 0xFF),
            UInt8(logicalLength & 0xFF),
            0x12, 0xA0,
            UInt8((dataFlowFlags >> 8) & 0xFF),
            UInt8(dataFlowFlags & 0xFF)
        ]
        bytes.append(contentsOf: variableHeader)
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    public func telnetFramed() -> Data {
        var framed: [UInt8] = []
        for byte in encoded() {
            framed.append(byte)
            if byte == TelnetNegotiator.Byte.iac { framed.append(byte) }
        }
        framed.append(contentsOf: [TelnetNegotiator.Byte.iac, TelnetNegotiator.Byte.endOfRecord])
        return Data(framed)
    }

    public var isStartupResponse: Bool {
        dataFlowFlags & 0x8000 != 0
    }
}
