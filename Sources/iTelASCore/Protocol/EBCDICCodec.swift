import Darwin
import Foundation

public enum EBCDICCodecError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedCCSID(Int)
    case decodingFailed
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedCCSID(let ccsid):
            "CCSID \(ccsid) is not available in the native codec yet."
        case .decodingFailed:
            "The IBM i byte sequence could not be decoded."
        case .encodingFailed:
            "The text contains characters that cannot be represented by the selected CCSID."
        }
    }
}

public enum EBCDICCharacterWidth: String, Codable, Sendable {
    case singleByte
    case mixedByte
}

public struct EBCDICCCSIDDefinition: Identifiable, Equatable, Sendable {
    public let id: Int
    public let region: String
    public let iconvName: String?
    public let characterWidth: EBCDICCharacterWidth
    public let requiresBidirectionalLayout: Bool

    public var ccsid: Int { id }
    public var isAvailable: Bool { iconvName != nil && characterWidth == .singleByte }
    /// True only when the terminal can honor the complete presentation contract, not merely
    /// transcode bytes. Bidirectional sessions also require field direction, cursor reversal,
    /// language-layer state, and screen-reverse behavior.
    public var isTerminalReady: Bool { isAvailable && !requiresBidirectionalLayout }
    public var pickerLabel: String { "\(ccsid) · \(region)" }

    public init(
        ccsid: Int,
        region: String,
        iconvName: String?,
        characterWidth: EBCDICCharacterWidth = .singleByte,
        requiresBidirectionalLayout: Bool = false
    ) {
        id = ccsid
        self.region = region
        self.iconvName = iconvName
        self.characterWidth = characterWidth
        self.requiresBidirectionalLayout = requiresBidirectionalLayout
    }
}

public enum EBCDICCCSIDCatalog {
    public static let all: [EBCDICCCSIDDefinition] = [
        .init(ccsid: 37, region: "US / Canada", iconvName: "IBM037"),
        .init(ccsid: 277, region: "Denmark / Norway", iconvName: "IBM277"),
        .init(ccsid: 278, region: "Finland / Sweden", iconvName: "IBM278"),
        .init(ccsid: 280, region: "Italy", iconvName: "IBM280"),
        .init(ccsid: 284, region: "Spain / Latin America", iconvName: "IBM284"),
        .init(ccsid: 285, region: "United Kingdom", iconvName: "IBM285"),
        .init(ccsid: 290, region: "Japanese Katakana SBCS", iconvName: "IBM290"),
        .init(ccsid: 297, region: "France", iconvName: "IBM297"),
        .init(ccsid: 420, region: "Arabic SBCS", iconvName: "IBM420", requiresBidirectionalLayout: true),
        .init(ccsid: 424, region: "Hebrew SBCS", iconvName: "IBM424", requiresBidirectionalLayout: true),
        .init(ccsid: 500, region: "International", iconvName: "IBM500"),
        .init(ccsid: 870, region: "Central Europe", iconvName: "IBM870"),
        .init(ccsid: 871, region: "Iceland", iconvName: "IBM871"),
        .init(ccsid: 880, region: "Cyrillic", iconvName: "IBM880"),
        .init(ccsid: 905, region: "Turkey", iconvName: "IBM905"),
        .init(ccsid: 918, region: "Urdu SBCS", iconvName: "IBM918", requiresBidirectionalLayout: true),
        .init(ccsid: 930, region: "Japanese mixed-byte", iconvName: nil, characterWidth: .mixedByte),
        .init(ccsid: 933, region: "Korean mixed-byte", iconvName: nil, characterWidth: .mixedByte),
        .init(ccsid: 935, region: "Simplified Chinese mixed-byte", iconvName: nil, characterWidth: .mixedByte),
        .init(ccsid: 937, region: "Traditional Chinese mixed-byte", iconvName: nil, characterWidth: .mixedByte),
        .init(ccsid: 939, region: "Japanese Latin mixed-byte", iconvName: nil, characterWidth: .mixedByte)
    ]

    public static var available: [EBCDICCCSIDDefinition] {
        all.filter(\.isAvailable)
    }

    public static var terminalReady: [EBCDICCCSIDDefinition] {
        all.filter(\.isTerminalReady)
    }

    public static var bidirectionalCodecOnly: [EBCDICCCSIDDefinition] {
        all.filter { $0.isAvailable && $0.requiresBidirectionalLayout }
    }

    public static var plannedMixedByte: [EBCDICCCSIDDefinition] {
        all.filter { $0.characterWidth == .mixedByte }
    }

    public static func definition(for ccsid: Int) -> EBCDICCCSIDDefinition? {
        all.first { $0.ccsid == ccsid }
    }
}

public struct EBCDICCodec: Sendable {
    public let ccsid: Int
    public let definition: EBCDICCCSIDDefinition
    private let iconvName: String

    public init(ccsid: Int = 37) throws {
        guard let definition = EBCDICCCSIDCatalog.definition(for: ccsid),
              definition.isAvailable,
              let iconvName = definition.iconvName else {
            throw EBCDICCodecError.unsupportedCCSID(ccsid)
        }
        self.ccsid = ccsid
        self.definition = definition
        self.iconvName = iconvName
    }

    public func decode(_ data: Data) throws -> String {
        let utf8 = try transcode(data, from: iconvName, to: "UTF-8", failure: .decodingFailed)
        guard let decoded = String(data: utf8, encoding: .utf8) else {
            throw EBCDICCodecError.decodingFailed
        }
        return decoded
    }

    public func decode(byte: UInt8) -> Character {
        let string = (try? decode(Data([byte]))) ?? "�"
        return string.first ?? " "
    }

    public func encode(_ string: String) throws -> Data {
        guard let utf8 = string.data(using: .utf8) else {
            throw EBCDICCodecError.encodingFailed
        }
        return try transcode(utf8, from: "UTF-8", to: iconvName, failure: .encodingFailed)
    }

    private func transcode(
        _ data: Data,
        from sourceEncoding: String,
        to destinationEncoding: String,
        failure: EBCDICCodecError
    ) throws -> Data {
        guard !data.isEmpty else { return Data() }
        let converter = iconv_open(destinationEncoding, sourceEncoding)
        guard converter != iconv_t(bitPattern: -1) else { throw failure }
        defer { iconv_close(converter) }

        var input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: max(64, data.count * 8 + 16))
        let converted: Data = try input.withUnsafeMutableBytes { inputBuffer in
            try output.withUnsafeMutableBytes { outputBuffer in
                var inputPointer: UnsafeMutablePointer<CChar>? = inputBuffer.baseAddress?.assumingMemoryBound(to: CChar.self)
                var outputPointer: UnsafeMutablePointer<CChar>? = outputBuffer.baseAddress?.assumingMemoryBound(to: CChar.self)
                guard inputPointer != nil, outputPointer != nil else {
                    throw failure
                }
                var inputRemaining = inputBuffer.count
                var outputRemaining = outputBuffer.count
                let result = iconv(
                    converter,
                    &inputPointer,
                    &inputRemaining,
                    &outputPointer,
                    &outputRemaining
                )
                guard result != size_t.max, inputRemaining == 0 else { throw failure }
                guard let baseAddress = outputBuffer.baseAddress else { return Data() }
                return Data(bytes: baseAddress, count: outputBuffer.count - outputRemaining)
            }
        }
        return converted
    }
}
