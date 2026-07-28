import CryptoKit
import Foundation

public enum SSHAuthenticationMethod: String, CaseIterable, Codable, Sendable {
    case agent
    case keyFile

    public var label: String {
        switch self {
        case .agent: "SSH agent"
        case .keyFile: "Key file"
        }
    }
}

public struct SecureChannelProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var environment: IBMEnvironment
    public var authenticationMethod: SSHAuthenticationMethod
    public var privateKeyPath: String?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String = "",
        environment: IBMEnvironment = .development,
        authenticationMethod: SSHAuthenticationMethod = .agent,
        privateKeyPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.environment = environment
        self.authenticationMethod = authenticationMethod
        self.privateKeyPath = privateKeyPath
    }

    public var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var knownHostsToken: String {
        port == 22 ? normalizedHost : "[\(normalizedHost)]:\(port)"
    }

    public var targetLabel: String {
        "\(normalizedUsername)@\(normalizedHost):\(port)"
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { errors.append("Connection name is required.") }
        if trimmedName.count > 80 { errors.append("Connection name must be 80 characters or fewer.") }

        let host = normalizedHost
        if host.isEmpty {
            errors.append("Host name or IP address is required.")
        } else if host.count > 255 || !Self.isSafeHost(host) {
            errors.append("Host must be a single DNS name or IP address without options, ranges, or whitespace.")
        }

        if !(1...65_535).contains(port) {
            errors.append("SSH port must be between 1 and 65535.")
        }

        let user = normalizedUsername
        if user.isEmpty {
            errors.append("IBM i user profile is required.")
        } else if user.count > 128 || !Self.isSafeUsername(user) {
            errors.append("User profile contains unsupported characters.")
        }

        if authenticationMethod == .keyFile {
            guard let privateKeyPath, !privateKeyPath.isEmpty else {
                errors.append("Choose a private key file.")
                return errors
            }
            if !privateKeyPath.hasPrefix("/")
                || privateKeyPath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                errors.append("Private key path must be an absolute local path.")
            }
        }
        return errors
    }

    private static func isSafeHost(_ host: String) -> Bool {
        guard host.first != "-", !host.contains("..") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-:[]%_")
        return host.unicodeScalars.allSatisfy(allowed.contains)
            && !host.contains("/")
            && !host.contains(",")
            && !host.contains("@")
    }

    private static func isSafeUsername(_ username: String) -> Bool {
        guard username.first != "-" else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-$#@")
        return username.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public struct SSHHostKey: Identifiable, Hashable, Codable, Sendable {
    public let host: String
    public let port: Int
    public let algorithm: String
    public let encodedKey: String
    public let fingerprint: String

    public var id: String { "\(algorithm):\(fingerprint)" }
    public var knownHostsToken: String { port == 22 ? host : "[\(host)]:\(port)" }
    public var knownHostsEntry: String { "\(knownHostsToken) \(algorithm) \(encodedKey)" }

    public init(host: String, port: Int, algorithm: String, encodedKey: String) throws {
        guard Self.isSupportedAlgorithm(algorithm) else {
            throw SecureChannelError.unsupportedHostKeyAlgorithm(algorithm)
        }
        guard let bytes = Data(base64Encoded: encodedKey), !bytes.isEmpty else {
            throw SecureChannelError.invalidHostKey
        }
        self.host = host
        self.port = port
        self.algorithm = algorithm
        self.encodedKey = encodedKey
        let digest = SHA256.hash(data: bytes)
        let base64 = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        fingerprint = "SHA256:\(base64)"
    }

    public static func isSupportedAlgorithm(_ algorithm: String) -> Bool {
        algorithm == "ssh-ed25519"
            || algorithm.hasPrefix("ecdsa-sha2-")
            || algorithm == "ssh-rsa"
            || algorithm.hasPrefix("rsa-sha2-")
            || algorithm.hasPrefix("sk-ssh-ed25519")
            || algorithm.hasPrefix("sk-ecdsa-sha2-")
    }
}

public struct SSHHostKeyScanParser: Sendable {
    public init() {}

    public func parse(_ output: String, profile: SecureChannelProfile) throws -> [SSHHostKey] {
        guard profile.validationErrors.isEmpty else {
            throw SecureChannelError.invalidProfile(profile.validationErrors)
        }

        let acceptedTokens = Set([
            profile.normalizedHost,
            profile.knownHostsToken,
            "[\(profile.normalizedHost)]:\(profile.port)"
        ])
        var seen: Set<String> = []
        var keys: [SSHHostKey] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count == 3, acceptedTokens.contains(String(parts[0])) else { continue }
            guard let key = try? SSHHostKey(
                host: profile.normalizedHost,
                port: profile.port,
                algorithm: String(parts[1]),
                encodedKey: String(parts[2])
            ), seen.insert(key.id).inserted else { continue }
            keys.append(key)
        }

        guard !keys.isEmpty else { throw SecureChannelError.noHostKeys }
        return keys.sorted { Self.algorithmPriority($0.algorithm) < Self.algorithmPriority($1.algorithm) }
    }

    private static func algorithmPriority(_ algorithm: String) -> Int {
        if algorithm == "ssh-ed25519" { return 0 }
        if algorithm.hasPrefix("ecdsa-") || algorithm.hasPrefix("sk-") { return 1 }
        return 2
    }
}

public struct SystemSSHCommandPlan: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let standardInput: Data?
    public let timeoutSeconds: TimeInterval

    public init(
        executable: String,
        arguments: [String],
        standardInput: Data? = nil,
        timeoutSeconds: TimeInterval = 15
    ) {
        self.executable = executable
        self.arguments = arguments
        self.standardInput = standardInput
        self.timeoutSeconds = timeoutSeconds
    }

    public static func hostKeyScan(for profile: SecureChannelProfile) throws -> Self {
        try validate(profile)
        return Self(
            executable: "/usr/bin/ssh-keyscan",
            arguments: [
                "-q", "-T", "5", "-p", String(profile.port),
                "-t", "rsa,ecdsa,ed25519", profile.normalizedHost
            ],
            timeoutSeconds: 8
        )
    }

    public static func authenticationTest(
        for profile: SecureChannelProfile,
        knownHostsFile: String
    ) throws -> Self {
        try validate(profile)
        guard knownHostsFile.hasPrefix("/") else { throw SecureChannelError.invalidKnownHostsPath }
        var arguments = commonArguments(for: profile, knownHostsFile: knownHostsFile)
        arguments.append(contentsOf: ["--", profile.normalizedHost, "true"])
        return Self(executable: "/usr/bin/ssh", arguments: arguments)
    }

    public static func sftpSubsystemProbe(
        for profile: SecureChannelProfile,
        knownHostsFile: String
    ) throws -> Self {
        try validate(profile)
        guard knownHostsFile.hasPrefix("/") else { throw SecureChannelError.invalidKnownHostsPath }
        var arguments = commonOptionArguments(for: profile, knownHostsFile: knownHostsFile)
        arguments.append(contentsOf: ["-P", String(profile.port), "-b", "-"])
        if profile.authenticationMethod == .keyFile, let path = profile.privateKeyPath {
            arguments.append(contentsOf: ["-i", path, "-o", "IdentitiesOnly=yes"])
        }
        arguments.append("\(profile.normalizedUsername)@\(profile.normalizedHost)")
        let input = Data("pwd\nquit\n".utf8)
        return Self(executable: "/usr/bin/sftp", arguments: arguments, standardInput: input)
    }

    public static func sftpBatch(
        for profile: SecureChannelProfile,
        knownHostsFile: String,
        commands: [SFTPBatchCommand],
        timeoutSeconds: TimeInterval = 30
    ) throws -> Self {
        try validate(profile)
        guard knownHostsFile.hasPrefix("/"),
              !knownHostsFile.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw SecureChannelError.invalidKnownHostsPath
        }
        var arguments = commonOptionArguments(for: profile, knownHostsFile: knownHostsFile)
        arguments.append(contentsOf: ["-P", String(profile.port), "-b", "-"])
        if profile.authenticationMethod == .keyFile, let path = profile.privateKeyPath {
            arguments.append(contentsOf: ["-i", path, "-o", "IdentitiesOnly=yes"])
        }
        arguments.append("\(profile.normalizedUsername)@\(profile.normalizedHost)")
        return Self(
            executable: "/usr/bin/sftp",
            arguments: arguments,
            standardInput: try SFTPBatchEncoder().encode(commands),
            timeoutSeconds: timeoutSeconds
        )
    }

    private static func commonArguments(
        for profile: SecureChannelProfile,
        knownHostsFile: String
    ) -> [String] {
        var arguments = commonOptionArguments(for: profile, knownHostsFile: knownHostsFile)
        arguments.append(contentsOf: ["-p", String(profile.port), "-l", profile.normalizedUsername])
        if profile.authenticationMethod == .keyFile, let path = profile.privateKeyPath {
            arguments.append(contentsOf: ["-i", path, "-o", "IdentitiesOnly=yes"])
        }
        return arguments
    }

    private static func commonOptionArguments(
        for profile: SecureChannelProfile,
        knownHostsFile: String
    ) -> [String] {
        [
            "-F", "/dev/null",
            "-o", "UserKnownHostsFile=\(knownHostsFile)",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "BatchMode=yes",
            "-o", "NumberOfPasswordPrompts=0",
            "-o", "ConnectTimeout=8",
            "-o", "ConnectionAttempts=1",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=1",
            "-o", "ClearAllForwardings=yes",
            "-o", "ForwardAgent=no",
            "-o", "ForwardX11=no",
            "-o", "PermitLocalCommand=no",
            "-o", "RequestTTY=no"
        ]
    }

    private static func validate(_ profile: SecureChannelProfile) throws {
        guard profile.validationErrors.isEmpty else {
            throw SecureChannelError.invalidProfile(profile.validationErrors)
        }
    }
}

public enum SecureChannelError: Error, Equatable, LocalizedError, Sendable {
    case invalidProfile([String])
    case invalidHostKey
    case unsupportedHostKeyAlgorithm(String)
    case noHostKeys
    case invalidKnownHostsPath
    case hostKeyChanged
    case outputLimitExceeded
    case timedOut
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidProfile(let errors): errors.joined(separator: " ")
        case .invalidHostKey: "The host key was not valid base64 key material."
        case .unsupportedHostKeyAlgorithm(let algorithm): "Unsupported host-key algorithm: \(algorithm)."
        case .noHostKeys: "The target did not present a supported SSH host key."
        case .invalidKnownHostsPath: "The managed known-hosts path is invalid."
        case .hostKeyChanged: "The pinned host key changed. Stop and verify the target independently."
        case .outputLimitExceeded: "The provider returned more diagnostic output than iTelAS allows."
        case .timedOut: "The provider operation timed out."
        case .processFailed(let message): message
        }
    }
}
