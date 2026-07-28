import Foundation

public enum SourceFormat: String, CaseIterable, Codable, Sendable {
    case rpgle = "RPGLE"
    case clle = "CLLE"
    case cobol = "COBOL"
    case dds = "DDS"
    case sql = "SQL"
    case text = "TEXT"
}

public enum SourceLineEnding: String, CaseIterable, Codable, Sendable {
    case lf = "LF"
    case crlf = "CRLF"
}

public enum SourceDatePolicy: String, CaseIterable, Codable, Sendable {
    case preserve
    case replaceWithCurrentDate
    case clear

    public var label: String {
        switch self {
        case .preserve: "Preserve on write"
        case .replaceWithCurrentDate: "Use current date"
        case .clear: "Clear source dates"
        }
    }
}

public enum SourceIdentity: Hashable, Codable, Sendable {
    case localScratch(name: String)
    case member(library: String, sourceFile: String, member: String, sourceType: String)
    case ifs(path: String)

    public var displayName: String {
        switch self {
        case .localScratch(let name): name
        case .member(_, _, let member, let sourceType): "\(member).\(sourceType.lowercased())"
        case .ifs(let path): URL(fileURLWithPath: path).lastPathComponent
        }
    }

    public var hostLocation: String? {
        switch self {
        case .localScratch:
            nil
        case .member(let library, let sourceFile, let member, _):
            "\(library.uppercased())/\(sourceFile.uppercased())(\(member.uppercased()))"
        case .ifs(let path):
            path
        }
    }

    public var isHostBacked: Bool { hostLocation != nil }
}

public struct SourceDocument: Equatable, Sendable {
    public var identity: SourceIdentity
    public var format: SourceFormat
    public var ccsid: Int?
    public var sourceDatePolicy: SourceDatePolicy
    public var lineEnding: SourceLineEnding
    public var originalText: String
    public var text: String
    public var remoteRevision: String?

    public init(
        identity: SourceIdentity,
        format: SourceFormat,
        ccsid: Int? = nil,
        sourceDatePolicy: SourceDatePolicy = .preserve,
        lineEnding: SourceLineEnding = .lf,
        originalText: String,
        text: String? = nil,
        remoteRevision: String? = nil
    ) {
        self.identity = identity
        self.format = format
        self.ccsid = ccsid
        self.sourceDatePolicy = sourceDatePolicy
        self.lineEnding = lineEnding
        self.originalText = originalText
        self.text = text ?? originalText
        self.remoteRevision = remoteRevision
    }

    public var isDirty: Bool { text != originalText }
    public var lineCount: Int { Self.lines(in: text).count }
    public var utf8ByteCount: Int { text.lengthOfBytes(using: .utf8) }

    public var delta: SourceDelta {
        let before = Self.lines(in: originalText)
        let after = Self.lines(in: text)
        let sharedCount = min(before.count, after.count)
        let modified = (0..<sharedCount).reduce(into: 0) { count, index in
            if before[index] != after[index] { count += 1 }
        }
        return SourceDelta(
            added: max(0, after.count - before.count),
            modified: modified,
            removed: max(0, before.count - after.count)
        )
    }

    private static func lines(in text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }
}

public struct SourceDelta: Equatable, Sendable {
    public let added: Int
    public let modified: Int
    public let removed: Int

    public init(added: Int, modified: Int, removed: Int) {
        self.added = added
        self.modified = modified
        self.removed = removed
    }

    public var totalChanges: Int { added + modified + removed }
}

public enum SourcePreflightState: String, Equatable, Sendable {
    case ready
    case waiting
    case blocked
}

public enum SourcePreflightCheckKind: String, CaseIterable, Sendable {
    case providerConnected
    case hostTargetAssigned
    case targetStillCurrent
    case ccsidRoundTrip
    case sourceDatePolicy
    case remoteContentCompared

    public var label: String {
        switch self {
        case .providerConnected: "Provider connected"
        case .hostTargetAssigned: "Host target assigned"
        case .targetStillCurrent: "Target still current"
        case .ccsidRoundTrip: "CCSID round-trip"
        case .sourceDatePolicy: "Source-date policy"
        case .remoteContentCompared: "Remote content compared"
        }
    }
}

public struct SourcePreflightCheck: Equatable, Sendable, Identifiable {
    public let kind: SourcePreflightCheckKind
    public let state: SourcePreflightState
    public let detail: String

    public var id: SourcePreflightCheckKind { kind }

    public init(kind: SourcePreflightCheckKind, state: SourcePreflightState, detail: String) {
        self.kind = kind
        self.state = state
        self.detail = detail
    }
}

public struct SourceWritePreflightContext: Equatable, Sendable {
    public var providerConnected: Bool
    public var targetStillCurrent: Bool?
    public var ccsidRoundTripSucceeded: Bool?
    public var remoteContentCompared: Bool

    public init(
        providerConnected: Bool,
        targetStillCurrent: Bool? = nil,
        ccsidRoundTripSucceeded: Bool? = nil,
        remoteContentCompared: Bool = false
    ) {
        self.providerConnected = providerConnected
        self.targetStillCurrent = targetStillCurrent
        self.ccsidRoundTripSucceeded = ccsidRoundTripSucceeded
        self.remoteContentCompared = remoteContentCompared
    }
}

public struct SourceWritePreflight: Equatable, Sendable {
    public let checks: [SourcePreflightCheck]

    public init(document: SourceDocument, context: SourceWritePreflightContext) {
        checks = [
            SourcePreflightCheck(
                kind: .providerConnected,
                state: context.providerConnected ? .ready : .blocked,
                detail: context.providerConnected ? "Provider is available." : "Connect a source provider."
            ),
            SourcePreflightCheck(
                kind: .hostTargetAssigned,
                state: document.identity.isHostBacked ? .ready : .blocked,
                detail: document.identity.hostLocation ?? "Map the scratch document to a member or IFS path."
            ),
            SourcePreflightCheck(
                kind: .targetStillCurrent,
                state: Self.optionalState(context.targetStillCurrent),
                detail: Self.optionalDetail(
                    context.targetStillCurrent,
                    waiting: "Load the current remote revision before writing.",
                    failure: "The remote revision changed; compare again."
                )
            ),
            SourcePreflightCheck(
                kind: .ccsidRoundTrip,
                state: document.ccsid == nil ? .waiting : Self.optionalState(context.ccsidRoundTripSucceeded),
                detail: document.ccsid == nil
                    ? "Choose the host CCSID before conversion."
                    : Self.optionalDetail(
                        context.ccsidRoundTripSucceeded,
                        waiting: "Validate every character against CCSID \(document.ccsid ?? 0).",
                        failure: "The draft cannot round-trip through CCSID \(document.ccsid ?? 0)."
                    )
            ),
            SourcePreflightCheck(
                kind: .sourceDatePolicy,
                state: .ready,
                detail: document.sourceDatePolicy.label
            ),
            SourcePreflightCheck(
                kind: .remoteContentCompared,
                state: context.remoteContentCompared ? .ready : .waiting,
                detail: context.remoteContentCompared
                    ? "The write plan includes a current remote comparison."
                    : "Compare the draft with current host content."
            )
        ]
    }

    public var isReady: Bool { checks.allSatisfy { $0.state == .ready } }

    private static func optionalState(_ value: Bool?) -> SourcePreflightState {
        switch value {
        case true: .ready
        case false: .blocked
        case nil: .waiting
        }
    }

    private static func optionalDetail(_ value: Bool?, waiting: String, failure: String) -> String {
        switch value {
        case true: "Validated."
        case false: failure
        case nil: waiting
        }
    }
}

public struct SourceResource: Hashable, Sendable, Identifiable {
    public let identity: SourceIdentity
    public let displayName: String
    public let isContainer: Bool

    public var id: SourceIdentity { identity }

    public init(identity: SourceIdentity, displayName: String, isContainer: Bool = false) {
        self.identity = identity
        self.displayName = displayName
        self.isContainer = isContainer
    }
}

public protocol SourceProvider: Sendable {
    var providerName: String { get }
    func listChildren(of identity: SourceIdentity?) async throws -> [SourceResource]
    func read(_ identity: SourceIdentity) async throws -> SourceDocument
    func write(_ document: SourceDocument, expectedRemoteRevision: String) async throws -> SourceDocument
}
