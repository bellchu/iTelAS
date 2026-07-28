import Foundation

/// The only database capabilities iTelAS can request from the IBM i ODBC driver.
/// General-purpose write access is intentionally not represented here.
public enum Db2AccessMode: String, Codable, CaseIterable, Sendable {
    case readOnly
    case sourceMemberRead
    case reviewedSourceMemberWrite

    public var label: String {
        switch self {
        case .readOnly: "Read only"
        case .sourceMemberRead: "Source-member read"
        case .reviewedSourceMemberWrite: "Reviewed source-member write"
        }
    }

    public var connectionTypeValue: String {
        switch self {
        case .readOnly: "2"
        case .sourceMemberRead, .reviewedSourceMemberWrite: "0"
        }
    }

    public var commitmentControlValue: String {
        switch self {
        case .readOnly, .sourceMemberRead: "1"
        case .reviewedSourceMemberWrite: "4"
        }
    }

    public var requiresExplicitTransaction: Bool {
        self == .reviewedSourceMemberWrite
    }
}

/// Non-secret connection preferences. Passwords are deliberately absent so profiles can be
/// persisted without turning preferences, exports, or crash reports into credential stores.
public struct Db2ConnectionProfile: Identifiable, Codable, Hashable, Sendable {
    public static let registeredDriverName = "IBM i Access ODBC Driver"

    public var id: UUID
    public var name: String
    public var host: String
    public var username: String
    public var environment: IBMEnvironment
    public var loginTimeoutSeconds: Int
    public var connectionTimeoutSeconds: Int

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        username: String,
        environment: IBMEnvironment = .development,
        loginTimeoutSeconds: Int = 15,
        connectionTimeoutSeconds: Int = 30
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.environment = environment
        self.loginTimeoutSeconds = loginTimeoutSeconds
        self.connectionTimeoutSeconds = connectionTimeoutSeconds
    }

    public var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public var targetLabel: String {
        normalizedName.isEmpty ? normalizedHost : normalizedName
    }

    public var validationErrors: [String] {
        var errors: [String] = []

        if normalizedName.isEmpty {
            errors.append("Connection name is required.")
        } else if normalizedName.count > 80 {
            errors.append("Connection name must be 80 characters or fewer.")
        }

        if normalizedHost.isEmpty {
            errors.append("IBM i host name or IP address is required.")
        } else if normalizedHost.count > 255 || !Self.isSafeHost(normalizedHost) {
            errors.append("Host must be one DNS name or IP address without connection-string syntax, paths, or whitespace.")
        }

        if normalizedUsername.isEmpty {
            errors.append("IBM i user profile is required.")
        } else if (try? IBMSystemObjectName(normalizedUsername)) == nil {
            errors.append("User profile must be a classic IBM i system name of 10 characters or fewer.")
        }

        if !(1...60).contains(loginTimeoutSeconds) {
            errors.append("Sign-on timeout must be between 1 and 60 seconds.")
        }
        if !(1...120).contains(connectionTimeoutSeconds) {
            errors.append("Connection timeout must be between 1 and 120 seconds.")
        }
        return errors
    }

    private static func isSafeHost(_ host: String) -> Bool {
        guard host.first != "-", !host.contains("..") else { return false }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-:[]%_"
        )
        return host.unicodeScalars.allSatisfy(allowed.contains)
            && !host.contains("/")
            && !host.contains(",")
            && !host.contains("@")
    }
}

public enum Db2ConnectionContractError: Error, Equatable, LocalizedError, Sendable {
    case invalidProfile([String])
    case invalidPassword

    public var errorDescription: String? {
        switch self {
        case .invalidProfile(let errors):
            errors.joined(separator: " ")
        case .invalidPassword:
            "The password must be 1 to 512 UTF-8 bytes and cannot contain control characters."
        }
    }
}

/// Short-lived password material. It is neither Codable nor printable.
public struct Db2Password: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    fileprivate let utf8: Data

    public init(_ value: String) throws {
        let bytes = Data(value.utf8)
        guard !bytes.isEmpty,
              bytes.count <= 512,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw Db2ConnectionContractError.invalidPassword
        }
        utf8 = bytes
    }

    public var description: String { "<redacted Db2 password>" }
    public var debugDescription: String { description }
}

public struct Db2ODBCPolicy: Equatable, Sendable {
    public enum AccessAttribute: Int, Sendable {
        case readWrite = 0
        case readOnly = 1
    }

    public let accessAttribute: AccessAttribute
    public let loginTimeoutSeconds: Int
    public let connectionTimeoutSeconds: Int
    public let autoCommit: Bool
    public let serializableIsolation: Bool

    public init(profile: Db2ConnectionProfile, accessMode: Db2AccessMode) {
        accessAttribute = accessMode == .readOnly ? .readOnly : .readWrite
        loginTimeoutSeconds = profile.loginTimeoutSeconds
        connectionTimeoutSeconds = profile.connectionTimeoutSeconds
        autoCommit = !accessMode.requiresExplicitTransaction
        serializableIsolation = accessMode.requiresExplicitTransaction
    }
}

/// A NUL-terminated UTF-8 connection string whose printable representations never expose it.
/// The transport receives a temporary pointer instead of a reusable String.
public struct Db2SensitiveConnectionString: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let nullTerminatedUTF8: Data

    fileprivate init(nullTerminatedUTF8: Data) {
        self.nullTerminatedUTF8 = nullTerminatedUTF8
    }

    public var utf8Count: Int { max(0, nullTerminatedUTF8.count - 1) }
    public var description: String { "<redacted Db2 connection string>" }
    public var debugDescription: String { description }

    public func withUnsafeCString<Result>(
        _ body: (UnsafePointer<CChar>, Int) throws -> Result
    ) rethrows -> Result {
        try nullTerminatedUTF8.withUnsafeBytes { rawBuffer in
            let pointer = rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self)
            return try body(pointer, utf8Count)
        }
    }
}

public struct Db2ConnectionPlan: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let profileID: UUID
    public let targetName: String
    public let environment: IBMEnvironment
    public let accessMode: Db2AccessMode
    public let policy: Db2ODBCPolicy
    public let connectionString: Db2SensitiveConnectionString

    public var description: String {
        "Db2 connection plan (<redacted>, \(accessMode.label.lowercased()))"
    }

    public var debugDescription: String { description }
}

public struct Db2ConnectionPlanner: Sendable {
    public init() {}

    public func plan(
        profile: Db2ConnectionProfile,
        password: Db2Password,
        accessMode: Db2AccessMode = .readOnly
    ) throws -> Db2ConnectionPlan {
        let errors = profile.validationErrors
        guard errors.isEmpty else {
            throw Db2ConnectionContractError.invalidProfile(errors)
        }

        var bytes = Data()
        Self.append("DRIVER", bracedUTF8: Data(Db2ConnectionProfile.registeredDriverName.utf8), to: &bytes)
        Self.append("SYSTEM", plain: profile.normalizedHost, to: &bytes)
        Self.append("UID", plain: profile.normalizedUsername, to: &bytes)
        Self.append("PWD", bracedUTF8: password.utf8, to: &bytes)
        Self.append("SIGNON", plain: "2", to: &bytes)
        Self.append("SSL", plain: "1", to: &bytes)
        Self.append("CONNTYPE", plain: accessMode.connectionTypeValue, to: &bytes)
        Self.append("CMT", plain: accessMode.commitmentControlValue, to: &bytes)
        Self.append("NAM", plain: "0", to: &bytes)
        Self.append("ALLOWUNSCHAR", plain: "0", to: &bytes)
        Self.append("TRANSLATE", plain: "0", to: &bytes)
        Self.append("CCSID", plain: "1208", to: &bytes)
        Self.append("UNICODESQL", plain: "1", to: &bytes)
        Self.append("XDYNAMIC", plain: "0", to: &bytes)
        Self.append("QUERYTIMEOUT", plain: "1", to: &bytes)
        Self.append("ALLOWPROCCALLS", plain: "0", to: &bytes)
        Self.append("LIBVIEW", plain: "0", to: &bytes)
        Self.append("TRACE", plain: "0", to: &bytes)
        bytes.append(0)

        return Db2ConnectionPlan(
            profileID: profile.id,
            targetName: profile.targetLabel,
            environment: profile.environment,
            accessMode: accessMode,
            policy: Db2ODBCPolicy(profile: profile, accessMode: accessMode),
            connectionString: Db2SensitiveConnectionString(nullTerminatedUTF8: bytes)
        )
    }

    private static func append(_ keyword: String, plain value: String, to bytes: inout Data) {
        bytes.append(contentsOf: keyword.utf8)
        bytes.append(61)
        bytes.append(contentsOf: value.utf8)
        bytes.append(59)
    }

    private static func append(_ keyword: String, bracedUTF8 value: Data, to bytes: inout Data) {
        bytes.append(contentsOf: keyword.utf8)
        bytes.append(61)
        bytes.append(123)
        for byte in value {
            bytes.append(byte)
            if byte == 125 { bytes.append(125) }
        }
        bytes.append(125)
        bytes.append(59)
    }
}

/// Persistable proof of the selected capability. It intentionally contains no SQL, user ID,
/// password, DSN, or connection string.
public struct Db2ConnectionReceipt: Codable, Equatable, Sendable {
    public let profileID: UUID
    public let targetName: String
    public let environment: IBMEnvironment
    public let accessMode: Db2AccessMode
    public let connectedAt: Date
    public let driverName: String
    public let tlsEnabled: Bool

    public init(
        profileID: UUID,
        targetName: String,
        environment: IBMEnvironment,
        accessMode: Db2AccessMode,
        connectedAt: Date,
        driverName: String = Db2ConnectionProfile.registeredDriverName,
        tlsEnabled: Bool = true
    ) {
        self.profileID = profileID
        self.targetName = targetName
        self.environment = environment
        self.accessMode = accessMode
        self.connectedAt = connectedAt
        self.driverName = driverName
        self.tlsEnabled = tlsEnabled
    }
}

public struct Db2DiagnosticSanitizer: Sendable {
    public static let withheldMessage = "The ODBC driver returned a sensitive diagnostic; details were withheld."

    public init() {}

    public func sanitize(_ rawMessage: String, password: Db2Password? = nil) -> String {
        var message = rawMessage
        if let password, let secret = String(data: password.utf8, encoding: .utf8), !secret.isEmpty {
            message = message.replacingOccurrences(of: secret, with: "<redacted>")
        }

        if Self.containsPasswordKeyword(message) {
            return Self.withheldMessage
        }

        message = String(message.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? Character(" ") : Character(scalar)
        })
        message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return "The ODBC driver did not provide a diagnostic message." }
        return String(message.prefix(800))
    }

    private static func containsPasswordKeyword(_ value: String) -> Bool {
        let compact = value.uppercased().replacingOccurrences(of: " ", with: "")
        return compact.contains("PWD=") || compact.contains("PASSWORD=")
    }
}
