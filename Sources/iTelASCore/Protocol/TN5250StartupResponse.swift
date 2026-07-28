import Foundation

public enum TN5250StartupDisposition: String, Equatable, Sendable {
    case success
    case warning
    case retryableDeviceName
    case failure
}

public enum TN5250StartupResponseError: Error, Equatable, LocalizedError, Sendable {
    case notStartupResponse
    case malformed

    public var errorDescription: String? {
        switch self {
        case .notStartupResponse:
            "The TN5250 record is not an RFC 4777 startup response."
        case .malformed:
            "The RFC 4777 startup response is incomplete."
        }
    }
}

public struct TN5250StartupResponse: Equatable, Sendable {
    public let responseCode: String
    public let systemName: String
    public let deviceName: String
    public let disposition: TN5250StartupDisposition
    public let message: String
    public let diagnosticData: Data

    public init(record: TN5250Record) throws {
        guard record.isStartupResponse else { throw TN5250StartupResponseError.notStartupResponse }
        let bytes = [UInt8](record.payload)
        guard bytes.count >= 9 else { throw TN5250StartupResponseError.malformed }
        let codec = try EBCDICCodec(ccsid: 37)
        responseCode = try Self.decodeField(bytes[5..<9], codec: codec)
        systemName = bytes.count >= 17 ? try Self.decodeField(bytes[9..<17], codec: codec) : ""
        deviceName = bytes.count >= 27 ? try Self.decodeField(bytes[17..<27], codec: codec) : ""
        diagnosticData = bytes.count > 27 ? Data(bytes[27...]) : Data()
        disposition = Self.disposition(for: responseCode)
        message = Self.description(for: responseCode)
    }

    private static func decodeField(
        _ bytes: ArraySlice<UInt8>,
        codec: EBCDICCodec
    ) throws -> String {
        let decoded = try codec.decode(Data(bytes))
        return decoded
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func disposition(for code: String) -> TN5250StartupDisposition {
        switch code.uppercased() {
        case "I902": .success
        case "I901", "I906": .warning
        case "8902": .retryableDeviceName
        default: .failure
        }
    }

    private static func description(for code: String) -> String {
        switch code.uppercased() {
        case "I901": "Session started with fewer device capabilities than requested."
        case "I902": "IBM i virtual device session started successfully."
        case "I906": "Automatic sign-on was unavailable; the host will show its sign-on screen."
        case "2702": "The requested device description was not found."
        case "2703": "The controller description was not found."
        case "2777": "The requested device description is damaged."
        case "8901": "The requested device is not varied on."
        case "8902": "The requested device is already in use."
        case "8903": "The requested device is not valid for this session."
        case "8906": "IBM i could not initiate the virtual device session."
        case "8907": "The virtual device session failed."
        case "8910": "The controller is not valid for this session."
        case "8916": "IBM i could not find a matching device."
        case "8917": "The user is not authorized to the requested device."
        case "8918": "The session job was canceled."
        case "8920": "The requested object is partially damaged."
        case "8921": "A communications error occurred while starting the session."
        case "8922": "IBM i received a negative response while starting the session."
        case "0001": "IBM i reported a startup or authentication system error."
        case "0002": "The supplied user profile is unknown."
        case "0003": "The supplied user profile is disabled."
        case "0004": "The supplied password, passphrase, or token is invalid."
        case "0005": "The supplied password, passphrase, or token is expired."
        case "0006": "The password format is not accepted by this IBM i release."
        case "0008": "Another invalid password attempt could revoke the user profile."
        default: "IBM i returned startup response \(code)."
        }
    }
}
