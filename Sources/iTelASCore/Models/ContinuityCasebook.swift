import Foundation

public struct ContinuityCasebookLimits: Equatable, Sendable {
    public var maximumCases: Int
    public var maximumSnapshots: Int
    public var maximumArtifactsPerCase: Int
    public var maximumAnswersPerCase: Int
    public var maximumReferencesPerCase: Int
    public var maximumQuestionsPerCase: Int
    public var maximumReferenceEntries: Int
    public var maximumMetadataUTF8Bytes: Int
    public var maximumArtifactUTF8Bytes: Int
    public var maximumAnswerUTF8Bytes: Int
    public var maximumReferenceEntryUTF8Bytes: Int
    public var maximumReferencePackUTF8Bytes: Int
    public var maximumCasebookUTF8Bytes: Int

    public init(
        maximumCases: Int = 64,
        maximumSnapshots: Int = 256,
        maximumArtifactsPerCase: Int = 64,
        maximumAnswersPerCase: Int = 32,
        maximumReferencesPerCase: Int = 16,
        maximumQuestionsPerCase: Int = 16,
        maximumReferenceEntries: Int = 24,
        maximumMetadataUTF8Bytes: Int = 512,
        maximumArtifactUTF8Bytes: Int = 32_768,
        maximumAnswerUTF8Bytes: Int = 131_072,
        maximumReferenceEntryUTF8Bytes: Int = 32_768,
        maximumReferencePackUTF8Bytes: Int = 262_144,
        maximumCasebookUTF8Bytes: Int = 4_194_304
    ) {
        self.maximumCases = maximumCases
        self.maximumSnapshots = maximumSnapshots
        self.maximumArtifactsPerCase = maximumArtifactsPerCase
        self.maximumAnswersPerCase = maximumAnswersPerCase
        self.maximumReferencesPerCase = maximumReferencesPerCase
        self.maximumQuestionsPerCase = maximumQuestionsPerCase
        self.maximumReferenceEntries = maximumReferenceEntries
        self.maximumMetadataUTF8Bytes = maximumMetadataUTF8Bytes
        self.maximumArtifactUTF8Bytes = maximumArtifactUTF8Bytes
        self.maximumAnswerUTF8Bytes = maximumAnswerUTF8Bytes
        self.maximumReferenceEntryUTF8Bytes = maximumReferenceEntryUTF8Bytes
        self.maximumReferencePackUTF8Bytes = maximumReferencePackUTF8Bytes
        self.maximumCasebookUTF8Bytes = maximumCasebookUTF8Bytes
    }

    public static let standard = ContinuityCasebookLimits()
}

public enum ContinuityCasebookError: Error, LocalizedError, Equatable {
    case unsupportedVersion
    case invalidMetadata(String)
    case invalidContent(String)
    case invalidCaseCode
    case invalidFingerprint
    case invalidReferenceLocator
    case duplicateCase
    case duplicateArtifact
    case duplicateAnswer
    case duplicateReference
    case duplicateSnapshot
    case missingCase
    case noReferenceSelection
    case invalidReferenceSelection
    case incompatibleAnswerState
    case limitExceeded(String, maximum: Int)
    case casebookTooLarge(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "The Continuity Casebook format version is not supported."
        case .invalidMetadata(let field): "The handoff \(field) is empty, oversized, or contains unsafe control characters."
        case .invalidContent(let field): "The handoff \(field) is empty, oversized, or contains unsupported binary controls."
        case .invalidCaseCode: "Use a case code such as INC-0427, CHG-1182, BLD-0934, or XFR-0208."
        case .invalidFingerprint: "One handoff receipt does not match its exact local content."
        case .invalidReferenceLocator: "A reviewed repository locator must be a safe relative path without traversal."
        case .duplicateCase: "The Casebook already contains that case identity or code."
        case .duplicateArtifact: "That exact evidence artifact is already in the case."
        case .duplicateAnswer: "That exact Assist answer is already in the case."
        case .duplicateReference: "That exact reviewed reference is already in the case."
        case .duplicateSnapshot: "That immutable handoff snapshot already exists."
        case .missingCase: "Select a Continuity Case before adding evidence."
        case .noReferenceSelection: "Select at least one reviewed reference entry."
        case .invalidReferenceSelection: "The selected reference entry is not part of the reviewed pack."
        case .incompatibleAnswerState: "Stopped or interrupted Assist output cannot carry a completed-response risk classification."
        case .limitExceeded(let field, let maximum): "The handoff \(field) exceeds its limit of \(maximum)."
        case .casebookTooLarge(let maximum): "The local Casebook exceeds its \(maximum)-byte storage limit."
        }
    }
}

public enum ContinuityCaseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case incident
    case change
    case build
    case transfer
    case general

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .incident: "Incident"
        case .change: "Change"
        case .build: "Build"
        case .transfer: "Transfer"
        case .general: "General"
        }
    }

    public var codePrefix: String {
        switch self {
        case .incident: "INC"
        case .change: "CHG"
        case .build: "BLD"
        case .transfer: "XFR"
        case .general: "WRK"
        }
    }
}

public enum ContinuityCasePhase: String, Codable, CaseIterable, Sendable {
    case draft
    case handedOff
    case reopened
    case closed

    public var label: String {
        switch self {
        case .draft: "Draft"
        case .handedOff: "Handed off"
        case .reopened: "Reopened"
        case .closed: "Closed"
        }
    }
}

public enum ContinuityArtifactKind: String, Codable, CaseIterable, Sendable {
    case operatorNote
    case terminalScreen
    case source
    case sql
    case compileEvidence
    case jobIncident
    case spoolOutput
    case dataTransfer
    case systemHealth
    case objectImpact
    case runbookReview
    case authorityReview
    case reviewedReference

    public var label: String {
        switch self {
        case .operatorNote: "Operator note"
        case .terminalScreen: "5250 snapshot"
        case .source: "Source evidence"
        case .sql: "SQL evidence"
        case .compileEvidence: "Compile evidence"
        case .jobIncident: "Job evidence"
        case .spoolOutput: "Spooled output"
        case .dataTransfer: "Transfer evidence"
        case .systemHealth: "Health evidence"
        case .objectImpact: "Impact evidence"
        case .runbookReview: "Runbook review"
        case .authorityReview: "Authority review"
        case .reviewedReference: "Reviewed reference"
        }
    }

    fileprivate init(contextKind: AIContextKind) {
        switch contextKind {
        case .terminalScreen: self = .terminalScreen
        case .sourceSelection, .sourceDraft: self = .source
        case .sqlSelection, .sqlDraft, .sqlResult: self = .sql
        case .compileEvidence: self = .compileEvidence
        case .jobIncident: self = .jobIncident
        case .spoolOutput: self = .spoolOutput
        case .dataTransfer: self = .dataTransfer
        case .systemHealth: self = .systemHealth
        case .objectImpact: self = .objectImpact
        case .runbook: self = .runbookReview
        case .authorityReview: self = .authorityReview
        case .reviewedReference: self = .reviewedReference
        }
    }
}

public struct ContinuityArtifact: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ContinuityArtifactKind
    public let title: String
    public let summary: String
    public let content: String
    public let sourceReceipt: String
    public let contentSHA256: String
    public let fingerprint: String
    public let wasRedacted: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ContinuityArtifactKind,
        title: String,
        summary: String,
        content: String,
        sourceReceipt: String,
        wasRedacted: Bool,
        createdAt: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        self.id = id
        self.kind = kind
        self.title = try ContinuityValidation.metadata(title, field: "artifact title", limits: limits)
        self.summary = try ContinuityValidation.metadata(summary, field: "artifact summary", limits: limits)
        self.content = try ContinuityValidation.content(
            content,
            field: "artifact content",
            maximum: limits.maximumArtifactUTF8Bytes
        )
        self.sourceReceipt = try ContinuityValidation.fingerprint(sourceReceipt)
        contentSHA256 = AIContentFingerprint.sha256(content)
        self.wasRedacted = wasRedacted
        self.createdAt = ContinuityValidation.millisecondDate(createdAt)
        fingerprint = Self.makeFingerprint(
            kind: kind,
            title: self.title,
            summary: self.summary,
            sourceReceipt: self.sourceReceipt,
            contentSHA256: contentSHA256,
            wasRedacted: wasRedacted
        )
    }

    public init(
        fragment: AIContextFragment,
        createdAt: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        let lineScope: String
        if let first = fragment.firstLine, let last = fragment.lastLine {
            lineScope = "Lines \(first)–\(last) · \(fragment.utf8ByteCount) UTF-8 bytes"
        } else {
            lineScope = "\(fragment.utf8ByteCount) UTF-8 bytes"
        }
        try self.init(
            kind: ContinuityArtifactKind(contextKind: fragment.kind),
            title: fragment.documentName,
            summary: "\(fragment.kind.label) · \(lineScope)",
            content: fragment.content,
            sourceReceipt: fragment.contentSHA256,
            wasRedacted: fragment.wasRedacted,
            createdAt: createdAt,
            limits: limits
        )
    }

    public func validate(limits: ContinuityCasebookLimits = .standard) throws {
        _ = try ContinuityValidation.metadata(title, field: "artifact title", limits: limits)
        _ = try ContinuityValidation.metadata(summary, field: "artifact summary", limits: limits)
        _ = try ContinuityValidation.content(
            content,
            field: "artifact content",
            maximum: limits.maximumArtifactUTF8Bytes
        )
        _ = try ContinuityValidation.fingerprint(sourceReceipt)
        guard contentSHA256 == AIContentFingerprint.sha256(content),
              fingerprint == Self.makeFingerprint(
                kind: kind,
                title: title,
                summary: summary,
                sourceReceipt: sourceReceipt,
                contentSHA256: contentSHA256,
                wasRedacted: wasRedacted
              ) else {
            throw ContinuityCasebookError.invalidFingerprint
        }
    }

    private static func makeFingerprint(
        kind: ContinuityArtifactKind,
        title: String,
        summary: String,
        sourceReceipt: String,
        contentSHA256: String,
        wasRedacted: Bool
    ) -> String {
        ContinuityValidation.framedFingerprint([
            kind.rawValue,
            title,
            summary,
            sourceReceipt,
            contentSHA256,
            wasRedacted ? "redacted" : "verbatim"
        ])
    }
}

public enum ContinuityAnswerState: String, Codable, CaseIterable, Sendable {
    case complete
    case stopped
    case interrupted

    public var label: String { rawValue.uppercased() }
}

public struct ContinuityAssistAnswer: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let question: String
    public let answer: String
    public let state: ContinuityAnswerState
    public let commandRisk: CommandRisk?
    public let contextFingerprint: String?
    public let contextItemCount: Int
    public let endpointHost: String
    public let model: String
    public let answerSHA256: String
    public let fingerprint: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        state: ContinuityAnswerState,
        commandRisk: CommandRisk?,
        contextFingerprint: String?,
        contextItemCount: Int,
        endpointHost: String,
        model: String,
        createdAt: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        self.id = id
        self.question = try ContinuityValidation.content(
            question,
            field: "Assist question",
            maximum: limits.maximumArtifactUTF8Bytes
        )
        self.answer = try ContinuityValidation.content(
            answer,
            field: "Assist answer",
            maximum: limits.maximumAnswerUTF8Bytes
        )
        guard state == .complete || commandRisk == nil else {
            throw ContinuityCasebookError.incompatibleAnswerState
        }
        self.state = state
        self.commandRisk = commandRisk
        if let contextFingerprint {
            self.contextFingerprint = try ContinuityValidation.fingerprint(contextFingerprint)
            guard contextItemCount > 0, contextItemCount <= AIContextLimits.standard.maximumFragments else {
                throw ContinuityCasebookError.limitExceeded(
                    "context item count",
                    maximum: AIContextLimits.standard.maximumFragments
                )
            }
        } else {
            guard contextItemCount == 0 else {
                throw ContinuityCasebookError.invalidFingerprint
            }
            self.contextFingerprint = nil
        }
        self.contextItemCount = contextItemCount
        self.endpointHost = try ContinuityValidation.metadata(endpointHost, field: "provider host", limits: limits)
        self.model = try ContinuityValidation.metadata(model, field: "provider model", limits: limits)
        answerSHA256 = AIContentFingerprint.sha256(answer)
        self.createdAt = ContinuityValidation.millisecondDate(createdAt)
        fingerprint = Self.makeFingerprint(
            question: self.question,
            answerSHA256: answerSHA256,
            state: state,
            commandRisk: commandRisk,
            contextFingerprint: self.contextFingerprint,
            contextItemCount: contextItemCount,
            endpointHost: self.endpointHost,
            model: self.model
        )
    }

    public func validate(limits: ContinuityCasebookLimits = .standard) throws {
        _ = try ContinuityValidation.content(
            question,
            field: "Assist question",
            maximum: limits.maximumArtifactUTF8Bytes
        )
        _ = try ContinuityValidation.content(
            answer,
            field: "Assist answer",
            maximum: limits.maximumAnswerUTF8Bytes
        )
        guard state == .complete || commandRisk == nil else {
            throw ContinuityCasebookError.incompatibleAnswerState
        }
        if let contextFingerprint {
            _ = try ContinuityValidation.fingerprint(contextFingerprint)
            guard contextItemCount > 0, contextItemCount <= AIContextLimits.standard.maximumFragments else {
                throw ContinuityCasebookError.invalidFingerprint
            }
        } else if contextItemCount != 0 {
            throw ContinuityCasebookError.invalidFingerprint
        }
        _ = try ContinuityValidation.metadata(endpointHost, field: "provider host", limits: limits)
        _ = try ContinuityValidation.metadata(model, field: "provider model", limits: limits)
        guard answerSHA256 == AIContentFingerprint.sha256(answer),
              fingerprint == Self.makeFingerprint(
                question: question,
                answerSHA256: answerSHA256,
                state: state,
                commandRisk: commandRisk,
                contextFingerprint: contextFingerprint,
                contextItemCount: contextItemCount,
                endpointHost: endpointHost,
                model: model
              ) else {
            throw ContinuityCasebookError.invalidFingerprint
        }
    }

    private static func makeFingerprint(
        question: String,
        answerSHA256: String,
        state: ContinuityAnswerState,
        commandRisk: CommandRisk?,
        contextFingerprint: String?,
        contextItemCount: Int,
        endpointHost: String,
        model: String
    ) -> String {
        ContinuityValidation.framedFingerprint([
            AIContentFingerprint.sha256(question),
            answerSHA256,
            state.rawValue,
            commandRisk?.rawValue ?? "none",
            contextFingerprint ?? "none",
            String(contextItemCount),
            endpointHost,
            model
        ])
    }
}

public enum ContinuityReferenceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case runbook
    case repository

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

public struct ContinuityReferenceEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let locator: String
    public let content: String
    public let contentSHA256: String

    public init(
        id: UUID = UUID(),
        locator: String,
        content: String,
        kind: ContinuityReferenceKind,
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        self.id = id
        self.locator = try ContinuityValidation.referenceLocator(locator, kind: kind, limits: limits)
        self.content = try ContinuityValidation.content(
            content,
            field: "reference entry",
            maximum: limits.maximumReferenceEntryUTF8Bytes
        )
        contentSHA256 = AIContentFingerprint.sha256(content)
    }

    public func validate(
        kind: ContinuityReferenceKind,
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        _ = try ContinuityValidation.referenceLocator(locator, kind: kind, limits: limits)
        _ = try ContinuityValidation.content(
            content,
            field: "reference entry",
            maximum: limits.maximumReferenceEntryUTF8Bytes
        )
        guard contentSHA256 == AIContentFingerprint.sha256(content) else {
            throw ContinuityCasebookError.invalidFingerprint
        }
    }
}

public struct ContinuityReferencePack: Equatable, Sendable {
    public let version: Int
    public let kind: ContinuityReferenceKind
    public let title: String
    public let revision: String
    public let entries: [ContinuityReferenceEntry]
    public let fingerprint: String

    public init(
        version: Int = 1,
        kind: ContinuityReferenceKind,
        title: String,
        revision: String,
        entries: [ContinuityReferenceEntry],
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        guard version == 1 else { throw ContinuityCasebookError.unsupportedVersion }
        guard !entries.isEmpty else { throw ContinuityCasebookError.invalidContent("reference entries") }
        guard entries.count <= limits.maximumReferenceEntries else {
            throw ContinuityCasebookError.limitExceeded(
                "reference entries",
                maximum: limits.maximumReferenceEntries
            )
        }
        var ids = Set<UUID>()
        for entry in entries {
            try entry.validate(kind: kind, limits: limits)
            guard ids.insert(entry.id).inserted else {
                throw ContinuityCasebookError.invalidReferenceSelection
            }
        }
        self.version = version
        self.kind = kind
        self.title = try ContinuityValidation.metadata(title, field: "reference title", limits: limits)
        self.revision = try ContinuityValidation.metadata(revision, field: "reference revision", limits: limits)
        self.entries = entries
        fingerprint = Self.makeFingerprint(
            kind: kind,
            title: self.title,
            revision: self.revision,
            entries: entries
        )
    }

    public func reviewing(
        entryIDs: Set<UUID>,
        reviewedAt: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws -> ContinuityReviewedReference {
        guard !entryIDs.isEmpty else { throw ContinuityCasebookError.noReferenceSelection }
        let selected = entries.filter { entryIDs.contains($0.id) }
        guard selected.count == entryIDs.count else {
            throw ContinuityCasebookError.invalidReferenceSelection
        }
        return try ContinuityReviewedReference(
            kind: kind,
            title: title,
            revision: revision,
            entries: selected,
            sourcePackFingerprint: fingerprint,
            reviewedAt: reviewedAt,
            limits: limits
        )
    }

    private static func makeFingerprint(
        kind: ContinuityReferenceKind,
        title: String,
        revision: String,
        entries: [ContinuityReferenceEntry]
    ) -> String {
        ContinuityValidation.framedFingerprint(
            [kind.rawValue, title, revision]
                + entries.map { "\($0.locator)|\($0.contentSHA256)" }
        )
    }
}

public struct ContinuityReferencePackCodec: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        limits: ContinuityCasebookLimits = .standard
    ) throws -> ContinuityReferencePack {
        guard data.count <= limits.maximumReferencePackUTF8Bytes else {
            throw ContinuityCasebookError.limitExceeded(
                "reference pack bytes",
                maximum: limits.maximumReferencePackUTF8Bytes
            )
        }
        let decoded = try JSONDecoder().decode(ImportPack.self, from: data)
        let entries = try decoded.entries.map { entry in
            try ContinuityReferenceEntry(
                id: entry.id ?? UUID(),
                locator: entry.locator,
                content: entry.content,
                kind: decoded.kind,
                limits: limits
            )
        }
        return try ContinuityReferencePack(
            version: decoded.version,
            kind: decoded.kind,
            title: decoded.title,
            revision: decoded.revision,
            entries: entries,
            limits: limits
        )
    }

    private struct ImportPack: Decodable {
        let version: Int
        let kind: ContinuityReferenceKind
        let title: String
        let revision: String
        let entries: [ImportEntry]
    }

    private struct ImportEntry: Decodable {
        let id: UUID?
        let locator: String
        let content: String
    }
}

public struct ContinuityReviewedReference: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ContinuityReferenceKind
    public let title: String
    public let revision: String
    public let entries: [ContinuityReferenceEntry]
    public let sourcePackFingerprint: String
    public let fingerprint: String
    public let reviewedAt: Date

    public init(
        id: UUID = UUID(),
        kind: ContinuityReferenceKind,
        title: String,
        revision: String,
        entries: [ContinuityReferenceEntry],
        sourcePackFingerprint: String,
        reviewedAt: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        guard !entries.isEmpty else { throw ContinuityCasebookError.noReferenceSelection }
        guard entries.count <= limits.maximumReferenceEntries else {
            throw ContinuityCasebookError.limitExceeded(
                "reviewed reference entries",
                maximum: limits.maximumReferenceEntries
            )
        }
        self.id = id
        self.kind = kind
        self.title = try ContinuityValidation.metadata(title, field: "reference title", limits: limits)
        self.revision = try ContinuityValidation.metadata(revision, field: "reference revision", limits: limits)
        self.entries = entries
        self.sourcePackFingerprint = try ContinuityValidation.fingerprint(sourcePackFingerprint)
        self.reviewedAt = ContinuityValidation.millisecondDate(reviewedAt)
        for entry in entries { try entry.validate(kind: kind, limits: limits) }
        fingerprint = Self.makeFingerprint(
            kind: kind,
            title: self.title,
            revision: self.revision,
            entries: entries,
            sourcePackFingerprint: self.sourcePackFingerprint
        )
    }

    public func validate(limits: ContinuityCasebookLimits = .standard) throws {
        guard !entries.isEmpty, entries.count <= limits.maximumReferenceEntries else {
            throw ContinuityCasebookError.noReferenceSelection
        }
        _ = try ContinuityValidation.metadata(title, field: "reference title", limits: limits)
        _ = try ContinuityValidation.metadata(revision, field: "reference revision", limits: limits)
        _ = try ContinuityValidation.fingerprint(sourcePackFingerprint)
        for entry in entries { try entry.validate(kind: kind, limits: limits) }
        guard fingerprint == Self.makeFingerprint(
            kind: kind,
            title: title,
            revision: revision,
            entries: entries,
            sourcePackFingerprint: sourcePackFingerprint
        ) else {
            throw ContinuityCasebookError.invalidFingerprint
        }
    }

    private static func makeFingerprint(
        kind: ContinuityReferenceKind,
        title: String,
        revision: String,
        entries: [ContinuityReferenceEntry],
        sourcePackFingerprint: String
    ) -> String {
        ContinuityValidation.framedFingerprint(
            [kind.rawValue, title, revision, sourcePackFingerprint]
                + entries.map { "\($0.locator)|\($0.contentSHA256)" }
        )
    }
}

public struct ContinuityCase: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let code: String
    public let kind: ContinuityCaseKind
    public private(set) var phase: ContinuityCasePhase
    public private(set) var title: String
    public private(set) var target: String
    public let environment: IBMEnvironment
    public private(set) var summary: String
    public private(set) var artifacts: [ContinuityArtifact]
    public private(set) var answers: [ContinuityAssistAnswer]
    public private(set) var references: [ContinuityReviewedReference]
    public private(set) var openQuestions: [String]
    public private(set) var nextAction: String
    public private(set) var staleBoundary: String
    public private(set) var receiverAcknowledged: Bool
    public let openedAt: Date
    public private(set) var updatedAt: Date

    public init(
        id: UUID = UUID(),
        code: String,
        kind: ContinuityCaseKind,
        phase: ContinuityCasePhase = .draft,
        title: String,
        target: String,
        environment: IBMEnvironment,
        summary: String,
        artifacts: [ContinuityArtifact] = [],
        answers: [ContinuityAssistAnswer] = [],
        references: [ContinuityReviewedReference] = [],
        openQuestions: [String] = [],
        nextAction: String,
        staleBoundary: String,
        receiverAcknowledged: Bool = false,
        openedAt: Date = Date(),
        updatedAt: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        self.id = id
        self.code = code.uppercased()
        self.kind = kind
        self.phase = phase
        self.title = title
        self.target = target
        self.environment = environment
        self.summary = summary
        self.artifacts = artifacts
        self.answers = answers
        self.references = references
        self.openQuestions = openQuestions
        self.nextAction = nextAction
        self.staleBoundary = staleBoundary
        self.receiverAcknowledged = receiverAcknowledged
        self.openedAt = ContinuityValidation.millisecondDate(openedAt)
        self.updatedAt = ContinuityValidation.millisecondDate(updatedAt)
        try validate(limits: limits)
    }

    public var fingerprint: String {
        ContinuityValidation.codableFingerprint(self)
    }

    public var readinessGaps: [String] {
        var gaps: [String] = []
        if artifacts.isEmpty { gaps.append("evidenceArtifacts") }
        if nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { gaps.append("nextAction") }
        if staleBoundary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { gaps.append("staleBoundary") }
        if !receiverAcknowledged { gaps.append("receiverAcknowledgement") }
        return gaps
    }

    public func adding(
        artifacts newArtifacts: [ContinuityArtifact],
        at date: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws -> ContinuityCase {
        var copy = self
        var fingerprints = Set(copy.artifacts.map(\.fingerprint))
        for artifact in newArtifacts {
            try artifact.validate(limits: limits)
            guard fingerprints.insert(artifact.fingerprint).inserted else {
                throw ContinuityCasebookError.duplicateArtifact
            }
            copy.artifacts.append(artifact)
        }
        copy.updatedAt = ContinuityValidation.millisecondDate(date)
        try copy.validate(limits: limits)
        return copy
    }

    public func adding(
        answer: ContinuityAssistAnswer,
        at date: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws -> ContinuityCase {
        try answer.validate(limits: limits)
        guard !answers.contains(where: { $0.fingerprint == answer.fingerprint }) else {
            throw ContinuityCasebookError.duplicateAnswer
        }
        var copy = self
        copy.answers.append(answer)
        copy.updatedAt = ContinuityValidation.millisecondDate(date)
        try copy.validate(limits: limits)
        return copy
    }

    public func adding(
        reference: ContinuityReviewedReference,
        at date: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws -> ContinuityCase {
        try reference.validate(limits: limits)
        guard !references.contains(where: { $0.fingerprint == reference.fingerprint }) else {
            throw ContinuityCasebookError.duplicateReference
        }
        var copy = self
        copy.references.append(reference)
        copy.updatedAt = ContinuityValidation.millisecondDate(date)
        try copy.validate(limits: limits)
        return copy
    }

    public func updatingWorkflow(
        title: String? = nil,
        summary: String? = nil,
        openQuestions: [String]? = nil,
        nextAction: String? = nil,
        staleBoundary: String? = nil,
        receiverAcknowledged: Bool? = nil,
        phase: ContinuityCasePhase? = nil,
        at date: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws -> ContinuityCase {
        var copy = self
        if let title { copy.title = title }
        if let summary { copy.summary = summary }
        if let openQuestions { copy.openQuestions = openQuestions }
        if let nextAction { copy.nextAction = nextAction }
        if let staleBoundary { copy.staleBoundary = staleBoundary }
        if let receiverAcknowledged { copy.receiverAcknowledged = receiverAcknowledged }
        if let phase { copy.phase = phase }
        copy.updatedAt = ContinuityValidation.millisecondDate(date)
        try copy.validate(limits: limits)
        return copy
    }

    public func validate(limits: ContinuityCasebookLimits = .standard) throws {
        guard Self.isValidCode(code, kind: kind) else {
            throw ContinuityCasebookError.invalidCaseCode
        }
        _ = try ContinuityValidation.metadata(title, field: "case title", limits: limits)
        _ = try ContinuityValidation.metadata(target, field: "case target", limits: limits)
        _ = try ContinuityValidation.content(
            summary,
            field: "case summary",
            maximum: limits.maximumArtifactUTF8Bytes
        )
        guard artifacts.count <= limits.maximumArtifactsPerCase else {
            throw ContinuityCasebookError.limitExceeded(
                "artifacts",
                maximum: limits.maximumArtifactsPerCase
            )
        }
        guard answers.count <= limits.maximumAnswersPerCase else {
            throw ContinuityCasebookError.limitExceeded(
                "Assist answers",
                maximum: limits.maximumAnswersPerCase
            )
        }
        guard references.count <= limits.maximumReferencesPerCase else {
            throw ContinuityCasebookError.limitExceeded(
                "reviewed references",
                maximum: limits.maximumReferencesPerCase
            )
        }
        guard openQuestions.count <= limits.maximumQuestionsPerCase else {
            throw ContinuityCasebookError.limitExceeded(
                "open questions",
                maximum: limits.maximumQuestionsPerCase
            )
        }
        var artifactFingerprints = Set<String>()
        for artifact in artifacts {
            try artifact.validate(limits: limits)
            guard artifactFingerprints.insert(artifact.fingerprint).inserted else {
                throw ContinuityCasebookError.duplicateArtifact
            }
        }
        var answerFingerprints = Set<String>()
        for answer in answers {
            try answer.validate(limits: limits)
            guard answerFingerprints.insert(answer.fingerprint).inserted else {
                throw ContinuityCasebookError.duplicateAnswer
            }
        }
        var referenceFingerprints = Set<String>()
        for reference in references {
            try reference.validate(limits: limits)
            guard referenceFingerprints.insert(reference.fingerprint).inserted else {
                throw ContinuityCasebookError.duplicateReference
            }
        }
        for question in openQuestions {
            _ = try ContinuityValidation.metadata(question, field: "open question", limits: limits)
        }
        if !nextAction.isEmpty {
            _ = try ContinuityValidation.content(
                nextAction,
                field: "next action",
                maximum: limits.maximumArtifactUTF8Bytes
            )
        }
        if !staleBoundary.isEmpty {
            _ = try ContinuityValidation.content(
                staleBoundary,
                field: "stale evidence boundary",
                maximum: limits.maximumArtifactUTF8Bytes
            )
        }
    }

    private static func isValidCode(_ code: String, kind: ContinuityCaseKind) -> Bool {
        let components = code.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0] == Substring(kind.codePrefix),
              components[1].count == 4,
              components[1].allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }
}

public struct ContinuityHandoffSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let caseRecord: ContinuityCase
    public let createdAt: Date
    public let readinessGaps: [String]
    public let fingerprint: String

    public init(
        id: UUID = UUID(),
        caseRecord: ContinuityCase,
        createdAt: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        try caseRecord.validate(limits: limits)
        self.id = id
        self.caseRecord = caseRecord
        let normalizedCreatedAt = ContinuityValidation.millisecondDate(createdAt)
        self.createdAt = normalizedCreatedAt
        readinessGaps = caseRecord.readinessGaps
        fingerprint = Self.makeFingerprint(
            id: id,
            caseRecord: caseRecord,
            createdAt: normalizedCreatedAt,
            readinessGaps: readinessGaps
        )
    }

    public func validate(limits: ContinuityCasebookLimits = .standard) throws {
        try caseRecord.validate(limits: limits)
        guard readinessGaps == caseRecord.readinessGaps,
              fingerprint == Self.makeFingerprint(
                id: id,
                caseRecord: caseRecord,
                createdAt: createdAt,
                readinessGaps: readinessGaps
              ) else {
            throw ContinuityCasebookError.invalidFingerprint
        }
    }

    private static func makeFingerprint(
        id: UUID,
        caseRecord: ContinuityCase,
        createdAt: Date,
        readinessGaps: [String]
    ) -> String {
        ContinuityValidation.framedFingerprint([
            id.uuidString.lowercased(),
            caseRecord.fingerprint,
            String(createdAt.timeIntervalSince1970),
            readinessGaps.joined(separator: ",")
        ])
    }
}

public struct ContinuityCasebook: Codable, Equatable, Sendable {
    public let version: Int
    public private(set) var cases: [ContinuityCase]
    public private(set) var snapshots: [ContinuityHandoffSnapshot]

    public init(
        version: Int = 1,
        cases: [ContinuityCase] = [],
        snapshots: [ContinuityHandoffSnapshot] = [],
        limits: ContinuityCasebookLimits = .standard
    ) throws {
        self.version = version
        self.cases = cases
        self.snapshots = snapshots
        try validate(limits: limits)
    }

    public static let empty = try! ContinuityCasebook()

    public func adding(
        _ continuityCase: ContinuityCase,
        limits: ContinuityCasebookLimits = .standard
    ) throws -> ContinuityCasebook {
        guard !cases.contains(where: { $0.id == continuityCase.id || $0.code == continuityCase.code }) else {
            throw ContinuityCasebookError.duplicateCase
        }
        var copy = self
        copy.cases.insert(continuityCase, at: 0)
        try copy.validate(limits: limits)
        return copy
    }

    public func replacing(
        _ continuityCase: ContinuityCase,
        limits: ContinuityCasebookLimits = .standard
    ) throws -> ContinuityCasebook {
        guard let index = cases.firstIndex(where: { $0.id == continuityCase.id }) else {
            throw ContinuityCasebookError.missingCase
        }
        guard !cases.enumerated().contains(where: { $0.offset != index && $0.element.code == continuityCase.code }) else {
            throw ContinuityCasebookError.duplicateCase
        }
        var copy = self
        copy.cases[index] = continuityCase
        try copy.validate(limits: limits)
        return copy
    }

    public func snapshotting(
        caseID: UUID,
        at date: Date = Date(),
        limits: ContinuityCasebookLimits = .standard
    ) throws -> (casebook: ContinuityCasebook, snapshot: ContinuityHandoffSnapshot) {
        guard let continuityCase = cases.first(where: { $0.id == caseID }) else {
            throw ContinuityCasebookError.missingCase
        }
        let snapshot = try ContinuityHandoffSnapshot(
            caseRecord: continuityCase,
            createdAt: date,
            limits: limits
        )
        var copy = self
        copy.snapshots.insert(snapshot, at: 0)
        try copy.validate(limits: limits)
        return (copy, snapshot)
    }

    public func validate(limits: ContinuityCasebookLimits = .standard) throws {
        guard version == 1 else { throw ContinuityCasebookError.unsupportedVersion }
        guard cases.count <= limits.maximumCases else {
            throw ContinuityCasebookError.limitExceeded("cases", maximum: limits.maximumCases)
        }
        guard snapshots.count <= limits.maximumSnapshots else {
            throw ContinuityCasebookError.limitExceeded("snapshots", maximum: limits.maximumSnapshots)
        }
        var caseIDs = Set<UUID>()
        var caseCodes = Set<String>()
        for continuityCase in cases {
            try continuityCase.validate(limits: limits)
            guard caseIDs.insert(continuityCase.id).inserted,
                  caseCodes.insert(continuityCase.code).inserted else {
                throw ContinuityCasebookError.duplicateCase
            }
        }
        var snapshotIDs = Set<UUID>()
        var snapshotFingerprints = Set<String>()
        for snapshot in snapshots {
            try snapshot.validate(limits: limits)
            guard snapshotIDs.insert(snapshot.id).inserted,
                  snapshotFingerprints.insert(snapshot.fingerprint).inserted else {
                throw ContinuityCasebookError.duplicateSnapshot
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let byteCount = (try? encoder.encode(self).count) ?? limits.maximumCasebookUTF8Bytes + 1
        guard byteCount <= limits.maximumCasebookUTF8Bytes else {
            throw ContinuityCasebookError.casebookTooLarge(maximum: limits.maximumCasebookUTF8Bytes)
        }
    }
}

private enum ContinuityValidation {
    static func millisecondDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000).rounded() / 1_000)
    }

    static func metadata(
        _ value: String,
        field: String,
        limits: ContinuityCasebookLimits
    ) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.utf8.count <= limits.maximumMetadataUTF8Bytes,
              normalized.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ContinuityCasebookError.invalidMetadata(field)
        }
        return normalized
    }

    static func content(_ value: String, field: String, maximum: Int) throws -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximum,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
              }) else {
            throw ContinuityCasebookError.invalidContent(field)
        }
        return value
    }

    static func fingerprint(_ value: String) throws -> String {
        let normalized = value.lowercased()
        guard normalized.count == 64,
              normalized.unicodeScalars.allSatisfy({ scalar in
                  ("0"..."9").contains(Character(String(scalar)))
                    || ("a"..."f").contains(Character(String(scalar)))
              }) else {
            throw ContinuityCasebookError.invalidFingerprint
        }
        return normalized
    }

    static func referenceLocator(
        _ value: String,
        kind: ContinuityReferenceKind,
        limits: ContinuityCasebookLimits
    ) throws -> String {
        let normalized = try metadata(value, field: "reference locator", limits: limits)
        guard kind == .repository else { return normalized }
        guard !normalized.hasPrefix("/"),
              !normalized.contains("\\"),
              !normalized.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }) else {
            throw ContinuityCasebookError.invalidReferenceLocator
        }
        return normalized
    }

    static func framedFingerprint(_ values: [String]) -> String {
        AIContentFingerprint.sha256(
            values.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        )
    }

    static func codableFingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return AIContentFingerprint.sha256((try? encoder.encode(value)) ?? Data())
    }
}
