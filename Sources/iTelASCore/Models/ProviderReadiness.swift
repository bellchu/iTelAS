import Foundation

public enum ProviderRuntimeComponentID: String, CaseIterable, Codable, Sendable {
    case architecture
    case ssh
    case sshKeyscan
    case sftp
    case unixODBC
    case ibmIODBC
    case openSSL
}

public enum ProviderRuntimeState: String, Codable, Sendable {
    case ready
    case missing
}

public struct ProviderRuntimeEvidence: Identifiable, Equatable, Codable, Sendable {
    public let id: ProviderRuntimeComponentID
    public let title: String
    public let purpose: String
    public let state: ProviderRuntimeState
    public let evidence: String
    public let resolvedPath: String?

    public init(
        id: ProviderRuntimeComponentID,
        title: String,
        purpose: String,
        state: ProviderRuntimeState,
        evidence: String,
        resolvedPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.state = state
        self.evidence = evidence
        self.resolvedPath = resolvedPath
    }
}

public struct ProviderRuntimeSnapshot: Equatable, Codable, Sendable {
    public let architecture: String
    public let capturedAt: Date
    public let evidence: [ProviderRuntimeEvidence]

    public init(
        architecture: String,
        capturedAt: Date = Date(),
        evidence: [ProviderRuntimeEvidence]
    ) {
        self.architecture = architecture
        self.capturedAt = capturedAt
        self.evidence = evidence
    }

    public func component(_ id: ProviderRuntimeComponentID) -> ProviderRuntimeEvidence {
        evidence.first(where: { $0.id == id })
            ?? ProviderRuntimeEvidence(
                id: id,
                title: id.rawValue,
                purpose: "Runtime prerequisite",
                state: .missing,
                evidence: "No evidence was collected."
            )
    }

    public var sshReady: Bool {
        component(.ssh).state == .ready && component(.sshKeyscan).state == .ready
    }

    public var sftpReady: Bool {
        component(.sftp).state == .ready
    }

    public var secureDb2PrerequisitesReady: Bool {
        component(.architecture).state == .ready
            && component(.unixODBC).state == .ready
            && component(.ibmIODBC).state == .ready
            && component(.openSSL).state == .ready
    }

    public var readyCount: Int {
        evidence.count(where: { $0.state == .ready })
    }
}

public struct ProviderRuntimeProbe: Sendable {
    public static let sshCandidates = ["/usr/bin/ssh"]
    public static let sshKeyscanCandidates = ["/usr/bin/ssh-keyscan"]
    public static let sftpCandidates = ["/usr/bin/sftp"]
    public static let unixODBCExecutableCandidates = [
        "/opt/homebrew/bin/odbcinst",
        "/usr/local/bin/odbcinst"
    ]
    public static let unixODBCLibraryCandidates = [
        "/opt/homebrew/lib/libodbc.dylib",
        "/usr/local/lib/libodbc.dylib"
    ]
    public static let ibmIODBCCandidates = [
        "/Library/IBMiAccess/register_driver",
        "/Library/IBMiAccess/lib/libcwbodbc.dylib"
    ]
    public static let openSSLCandidates = [
        "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib",
        "/opt/homebrew/lib/libssl.3.dylib",
        "/usr/local/opt/openssl@3/lib/libssl.3.dylib",
        "/usr/local/lib/libssl.3.dylib"
    ]

    public init() {}

    public func inspect(
        architecture: String,
        capturedAt: Date = Date(),
        fileExists: (String) -> Bool,
        isExecutable: (String) -> Bool
    ) -> ProviderRuntimeSnapshot {
        let ssh = firstMatch(Self.sshCandidates, predicate: isExecutable)
        let sshKeyscan = firstMatch(Self.sshKeyscanCandidates, predicate: isExecutable)
        let sftp = firstMatch(Self.sftpCandidates, predicate: isExecutable)
        let odbcExecutable = firstMatch(Self.unixODBCExecutableCandidates, predicate: isExecutable)
        let odbcLibrary = firstMatch(Self.unixODBCLibraryCandidates, predicate: fileExists)
        let unixODBC = odbcExecutable ?? odbcLibrary
        let ibmIODBC = firstMatch(Self.ibmIODBCCandidates, predicate: fileExists)
        let openSSL = firstMatch(Self.openSSLCandidates, predicate: fileExists)

        return ProviderRuntimeSnapshot(
            architecture: architecture,
            capturedAt: capturedAt,
            evidence: [
                ProviderRuntimeEvidence(
                    id: .architecture,
                    title: "Local architecture",
                    purpose: "Native provider loading",
                    state: architecture == "arm64" ? .ready : .missing,
                    evidence: architecture == "arm64" ? "Apple Silicon process" : "Requires arm64",
                    resolvedPath: nil
                ),
                evidence(
                    id: .ssh,
                    title: "SSH runtime",
                    purpose: "PASE commands and diagnostics",
                    path: ssh,
                    missing: "System OpenSSH was not found."
                ),
                evidence(
                    id: .sshKeyscan,
                    title: "SSH host-key scanner",
                    purpose: "Known-host trust preflight",
                    path: sshKeyscan,
                    missing: "The system ssh-keyscan utility was not found."
                ),
                evidence(
                    id: .sftp,
                    title: "SFTP runtime",
                    purpose: "IFS stream-file transport",
                    path: sftp,
                    missing: "System SFTP was not found."
                ),
                evidence(
                    id: .unixODBC,
                    title: "unixODBC manager",
                    purpose: "ODBC driver management",
                    path: unixODBC,
                    missing: "Install unixODBC before registering the IBM driver."
                ),
                evidence(
                    id: .ibmIODBC,
                    title: "IBM i ODBC driver",
                    purpose: "Native Db2 for i connectivity",
                    path: ibmIODBC,
                    missing: "Install the IBM ACS macOS Application Package."
                ),
                evidence(
                    id: .openSSL,
                    title: "OpenSSL runtime",
                    purpose: "TLS for the IBM i ODBC driver",
                    path: openSSL,
                    missing: "Install OpenSSL 3 before enabling Db2 TLS."
                )
            ]
        )
    }

    public func inspectLocalMachine(
        fileManager: FileManager = .default,
        capturedAt: Date = Date()
    ) -> ProviderRuntimeSnapshot {
        inspect(
            architecture: Self.currentArchitecture,
            capturedAt: capturedAt,
            fileExists: fileManager.fileExists(atPath:),
            isExecutable: fileManager.isExecutableFile(atPath:)
        )
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private func firstMatch(
        _ candidates: [String],
        predicate: (String) -> Bool
    ) -> String? {
        candidates.first(where: predicate)
    }

    private func evidence(
        id: ProviderRuntimeComponentID,
        title: String,
        purpose: String,
        path: String?,
        missing: String
    ) -> ProviderRuntimeEvidence {
        ProviderRuntimeEvidence(
            id: id,
            title: title,
            purpose: purpose,
            state: path == nil ? .missing : .ready,
            evidence: path == nil ? missing : "Detected locally",
            resolvedPath: path
        )
    }
}
