import Foundation

public struct CompileLineageLimits: Equatable, Sendable {
    public let maximumRuns: Int
    public let maximumTotalDiagnostics: Int
    public let maximumFieldUTF8Bytes: Int

    public init(
        maximumRuns: Int = 32,
        maximumTotalDiagnostics: Int = 20_000,
        maximumFieldUTF8Bytes: Int = 4_096
    ) {
        self.maximumRuns = min(max(2, maximumRuns), 128)
        self.maximumTotalDiagnostics = min(max(100, maximumTotalDiagnostics), 100_000)
        self.maximumFieldUTF8Bytes = min(max(256, maximumFieldUTF8Bytes), 16_384)
    }

    public static let standard = CompileLineageLimits()
}

public enum CompileLineageError: Error, Equatable, LocalizedError, Sendable {
    case insufficientRuns(minimum: Int)
    case tooManyRuns(maximum: Int)
    case tooManyDiagnostics(maximum: Int)
    case duplicateRunFingerprint
    case missingSelectedRun
    case identicalSelection
    case targetScopeMismatch(expected: String, received: String)
    case invalidField(String)
    case fieldTooLarge(field: String, maximum: Int)
    case invalidFingerprint(field: String)
    case invalidSeverity(Int)
    case severityMismatch(expected: Int, received: Int)

    public var errorDescription: String? {
        switch self {
        case .insufficientRuns(let minimum):
            "Compile lineage needs at least \(minimum) retained runs for one exact target."
        case .tooManyRuns(let maximum):
            "Compile lineage accepts at most \(maximum) retained runs at once."
        case .tooManyDiagnostics(let maximum):
            "The selected lineage exceeds the \(maximum)-diagnostic comparison boundary."
        case .duplicateRunFingerprint:
            "Compile lineage refuses duplicate run fingerprints."
        case .missingSelectedRun:
            "The selected baseline or current run is not in this lineage."
        case .identicalSelection:
            "Baseline and current must be two different retained runs."
        case .targetScopeMismatch(let expected, let received):
            "Compile lineage is bound to \(expected); \(received) belongs to another target."
        case .invalidField(let field):
            "Compile lineage contains an invalid or empty \(field)."
        case .fieldTooLarge(let field, let maximum):
            "Compile lineage \(field) exceeds the \(maximum)-byte boundary."
        case .invalidFingerprint(let field):
            "Compile lineage \(field) must be an exact SHA-256 fingerprint."
        case .invalidSeverity(let severity):
            "Compiler severity \(severity) is outside the supported 0 through 99 range."
        case .severityMismatch(let expected, let received):
            "Maximum severity \(received) does not match the retained diagnostic maximum \(expected)."
        }
    }
}

public enum CompileLineageOutcome: String, Equatable, Sendable {
    case passed
    case failed
    case evidenceOnly

    public var label: String {
        switch self {
        case .passed: "PASSED"
        case .failed: "FAILED"
        case .evidenceOnly: "EVIDENCE ONLY"
        }
    }
}

public enum CompileLineageObjectResult: String, Equatable, Sendable {
    case changed
    case unchanged
    case unrecorded

    public var label: String {
        switch self {
        case .changed: "CHANGED"
        case .unchanged: "UNCHANGED"
        case .unrecorded: "UNRECORDED"
        }
    }
}

public enum CompileLineageDeltaState: String, Equatable, Sendable {
    case exact
    case changed
    case relative
    case unavailable

    public var label: String { rawValue.uppercased() }
}

public enum CompileLineageTrend: String, Equatable, Sendable {
    case regressionObserved
    case recoveryObserved
    case outcomeChanged
    case outcomeStable
    case outcomeUnverified

    public var label: String {
        switch self {
        case .regressionObserved: "REGRESSION OBSERVED"
        case .recoveryObserved: "RECOVERY OBSERVED"
        case .outcomeChanged: "OUTCOME CHANGED"
        case .outcomeStable: "OUTCOME STABLE"
        case .outcomeUnverified: "OUTCOME UNVERIFIED"
        }
    }
}

public struct CompileLineageDiagnosticIdentity: Identifiable, Hashable, Sendable {
    public let messageID: String
    public let severity: Int
    public let sourceIdentity: String
    public let startLine: Int
    public let startColumn: Int

    public init(
        messageID: String,
        severity: Int,
        sourceIdentity: String,
        startLine: Int,
        startColumn: Int,
        limits: CompileLineageLimits = .standard
    ) throws {
        guard (0...99).contains(severity) else {
            throw CompileLineageError.invalidSeverity(severity)
        }
        guard startLine >= 0, startColumn >= 0 else {
            throw CompileLineageError.invalidField("diagnostic coordinates")
        }
        self.messageID = try Self.checked(
            messageID.uppercased(),
            field: "message identity",
            limits: limits
        )
        self.severity = severity
        self.sourceIdentity = try Self.checked(
            sourceIdentity,
            field: "diagnostic source identity",
            limits: limits,
            permitsEmpty: true
        )
        self.startLine = startLine
        self.startColumn = startColumn
    }

    public var id: String { fingerprint }

    public var fingerprint: String {
        AIContentFingerprint.sha256(Self.framed([
            "itelas-compile-diagnostic-identity-v1",
            messageID,
            String(severity),
            sourceIdentity,
            String(startLine),
            String(startColumn)
        ]))
    }

    public var locationLabel: String {
        guard !sourceIdentity.isEmpty else {
            return startLine > 0 ? "line \(startLine)" : "unlocated"
        }
        return startLine > 0
            ? "\(sourceIdentity):\(startLine):\(startColumn)"
            : sourceIdentity
    }

    fileprivate static func checked(
        _ rawValue: String,
        field: String,
        limits: CompileLineageLimits,
        permitsEmpty: Bool = false
    ) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard permitsEmpty || !value.isEmpty else {
            throw CompileLineageError.invalidField(field)
        }
        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CompileLineageError.invalidField(field)
        }
        guard value.lengthOfBytes(using: .utf8) <= limits.maximumFieldUTF8Bytes else {
            throw CompileLineageError.fieldTooLarge(
                field: field,
                maximum: limits.maximumFieldUTF8Bytes
            )
        }
        return value
    }

    fileprivate static func framed(_ fields: [String]) -> String {
        fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
}

public struct CompileLineageRunEvidence: Identifiable, Equatable, Sendable {
    public let fingerprint: String
    public let sequence: Int?
    public let objectIdentity: String
    public let sourceIdentity: String
    public let sourceRevision: String?
    public let toolchainIdentity: String
    public let commandFingerprint: String
    public let eventEvidenceFingerprint: String
    public let eventFileIdentity: String
    public let targetReleaseToken: String?
    public let observedHostRelease: String?
    public let jobIdentity: String
    public let outcome: CompileLineageOutcome
    public let objectResult: CompileLineageObjectResult
    public let maximumSeverity: Int
    public let diagnostics: [CompileLineageDiagnosticIdentity]

    public init(
        fingerprint: String,
        sequence: Int?,
        objectIdentity: String,
        sourceIdentity: String,
        sourceRevision: String?,
        toolchainIdentity: String,
        commandFingerprint: String,
        eventEvidenceFingerprint: String,
        eventFileIdentity: String,
        targetReleaseToken: String?,
        observedHostRelease: String?,
        jobIdentity: String,
        outcome: CompileLineageOutcome,
        objectResult: CompileLineageObjectResult,
        maximumSeverity: Int,
        diagnostics: [CompileLineageDiagnosticIdentity],
        limits: CompileLineageLimits = .standard
    ) throws {
        guard (0...99).contains(maximumSeverity) else {
            throw CompileLineageError.invalidSeverity(maximumSeverity)
        }
        guard diagnostics.count <= limits.maximumTotalDiagnostics else {
            throw CompileLineageError.tooManyDiagnostics(maximum: limits.maximumTotalDiagnostics)
        }
        let diagnosticMaximum = diagnostics.map(\.severity).max() ?? 0
        guard diagnosticMaximum == maximumSeverity else {
            throw CompileLineageError.severityMismatch(
                expected: diagnosticMaximum,
                received: maximumSeverity
            )
        }

        self.fingerprint = try Self.sha256(fingerprint, field: "run fingerprint")
        self.sequence = sequence
        self.objectIdentity = try CompileLineageDiagnosticIdentity.checked(
            objectIdentity,
            field: "target identity",
            limits: limits
        )
        self.sourceIdentity = try CompileLineageDiagnosticIdentity.checked(
            sourceIdentity,
            field: "source identity",
            limits: limits
        )
        self.sourceRevision = try sourceRevision.map {
            try Self.sha256($0, field: "source revision")
        }
        self.toolchainIdentity = try CompileLineageDiagnosticIdentity.checked(
            toolchainIdentity,
            field: "toolchain identity",
            limits: limits
        )
        self.commandFingerprint = try Self.sha256(commandFingerprint, field: "command fingerprint")
        self.eventEvidenceFingerprint = try Self.sha256(
            eventEvidenceFingerprint,
            field: "event evidence fingerprint"
        )
        self.eventFileIdentity = try CompileLineageDiagnosticIdentity.checked(
            eventFileIdentity,
            field: "event-file identity",
            limits: limits
        )
        self.targetReleaseToken = try targetReleaseToken.map {
            try CompileLineageDiagnosticIdentity.checked(
                $0.uppercased(),
                field: "target-release token",
                limits: limits
            )
        }
        self.observedHostRelease = try observedHostRelease.map {
            try CompileLineageDiagnosticIdentity.checked(
                $0.uppercased(),
                field: "observed host release",
                limits: limits
            )
        }
        self.jobIdentity = try CompileLineageDiagnosticIdentity.checked(
            jobIdentity,
            field: "job identity",
            limits: limits
        )
        self.outcome = outcome
        self.objectResult = objectResult
        self.maximumSeverity = maximumSeverity
        self.diagnostics = Array(Set(diagnostics)).sorted(by: Self.diagnosticOrder)
    }

    public var id: String { fingerprint }
    public var displaySequence: String { sequence.map { "#\($0)" } ?? "IMPORT" }
    public var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }

    private static func sha256(_ rawValue: String, field: String) throws -> String {
        let value = rawValue.lowercased()
        guard value.count == 64,
              value.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else {
            throw CompileLineageError.invalidFingerprint(field: field)
        }
        return value
    }

    fileprivate static func diagnosticOrder(
        _ lhs: CompileLineageDiagnosticIdentity,
        _ rhs: CompileLineageDiagnosticIdentity
    ) -> Bool {
        if lhs.messageID != rhs.messageID { return lhs.messageID < rhs.messageID }
        if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
        if lhs.sourceIdentity != rhs.sourceIdentity { return lhs.sourceIdentity < rhs.sourceIdentity }
        if lhs.startLine != rhs.startLine { return lhs.startLine < rhs.startLine }
        return lhs.startColumn < rhs.startColumn
    }
}

public struct CompileLineageFieldDelta: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let baselineValue: String
    public let currentValue: String
    public let state: CompileLineageDeltaState
}

public struct CompileLineageDiagnosticDelta: Equatable, Sendable {
    public let introduced: [CompileLineageDiagnosticIdentity]
    public let resolved: [CompileLineageDiagnosticIdentity]
    public let persistent: [CompileLineageDiagnosticIdentity]
}

public struct CompileLineageComparison: Equatable, Sendable {
    public let runs: [CompileLineageRunEvidence]
    public let baseline: CompileLineageRunEvidence
    public let current: CompileLineageRunEvidence
    public let fields: [CompileLineageFieldDelta]
    public let diagnostics: CompileLineageDiagnosticDelta
    public let trend: CompileLineageTrend
    public let fingerprint: String

    public init(
        runs: [CompileLineageRunEvidence],
        baselineFingerprint: String,
        currentFingerprint: String,
        limits: CompileLineageLimits = .standard
    ) throws {
        guard runs.count >= 2 else {
            throw CompileLineageError.insufficientRuns(minimum: 2)
        }
        guard runs.count <= limits.maximumRuns else {
            throw CompileLineageError.tooManyRuns(maximum: limits.maximumRuns)
        }
        guard runs.reduce(0, { $0 + $1.diagnostics.count }) <= limits.maximumTotalDiagnostics else {
            throw CompileLineageError.tooManyDiagnostics(maximum: limits.maximumTotalDiagnostics)
        }
        guard Set(runs.map(\.fingerprint)).count == runs.count else {
            throw CompileLineageError.duplicateRunFingerprint
        }
        guard baselineFingerprint != currentFingerprint else {
            throw CompileLineageError.identicalSelection
        }
        guard let baseline = runs.first(where: { $0.fingerprint == baselineFingerprint }),
              let current = runs.first(where: { $0.fingerprint == currentFingerprint }) else {
            throw CompileLineageError.missingSelectedRun
        }
        for run in runs where run.objectIdentity != current.objectIdentity {
            throw CompileLineageError.targetScopeMismatch(
                expected: current.objectIdentity,
                received: run.objectIdentity
            )
        }

        let orderedRuns = runs.sorted(by: Self.runOrder)
        let fields = Self.makeFields(baseline: baseline, current: current)
        let diagnostics = Self.makeDiagnosticDelta(baseline: baseline, current: current)
        let trend = Self.makeTrend(baseline: baseline.outcome, current: current.outcome)
        let receiptFields = [
            "itelas-compile-lineage-v1",
            current.objectIdentity,
            baseline.fingerprint,
            current.fingerprint
        ] + orderedRuns.map(\.fingerprint)

        self.runs = orderedRuns
        self.baseline = baseline
        self.current = current
        self.fields = fields
        self.diagnostics = diagnostics
        self.trend = trend
        self.fingerprint = AIContentFingerprint.sha256(
            CompileLineageDiagnosticIdentity.framed(receiptFields)
        )
    }

    public var shortFingerprint: String { String(fingerprint.prefix(12)).uppercased() }
    public var exactFieldCount: Int { fields.count(where: { $0.state == .exact }) }
    public var changedFieldCount: Int { fields.count(where: { $0.state == .changed }) }
    public var relativeFieldCount: Int { fields.count(where: { $0.state == .relative }) }
    public var unavailableFieldCount: Int { fields.count(where: { $0.state == .unavailable }) }

    public func assistContextText(maximumDiagnostics: Int = 60) -> String {
        let limit = min(max(1, maximumDiagnostics), 200)
        var lines = [
            "ITELAS COMPILE LINEAGE v1",
            "TARGET: \(current.objectIdentity)",
            "BASELINE: \(baseline.displaySequence) · \(baseline.fingerprint)",
            "CURRENT: \(current.displaySequence) · \(current.fingerprint)",
            "TREND: \(trend.label)",
            "COMPARISON SHA-256: \(fingerprint)",
            "FIELD DELTAS:"
        ]
        lines.append(contentsOf: fields.map {
            "[\($0.state.label)] \($0.label): \($0.baselineValue) -> \($0.currentValue)"
        })
        lines.append("MESSAGE DELTA:")
        let groups: [(String, [CompileLineageDiagnosticIdentity])] = [
            ("INTRODUCED", diagnostics.introduced),
            ("RESOLVED", diagnostics.resolved),
            ("PERSISTENT", diagnostics.persistent)
        ]
        var emitted = 0
        for (label, items) in groups {
            for item in items where emitted < limit {
                lines.append("[\(label)] \(item.messageID) · severity \(item.severity) · \(item.locationLabel)")
                emitted += 1
            }
        }
        let total = groups.reduce(0) { $0 + $1.1.count }
        if total > emitted {
            lines.append("[\(total - emitted) additional diagnostic identities omitted by local cap]")
        }
        lines.append("BOUNDARY: This is retained local evidence and deterministic delta analysis, not causal proof, a complete job log, an authority result, a compile, or runtime verification.")
        return lines.joined(separator: "\n")
    }

    private static func makeFields(
        baseline: CompileLineageRunEvidence,
        current: CompileLineageRunEvidence
    ) -> [CompileLineageFieldDelta] {
        [
            exactField("target", "Target identity", baseline.objectIdentity, current.objectIdentity),
            exactField("source", "Source identity", baseline.sourceIdentity, current.sourceIdentity),
            optionalField(
                "revision",
                "Source revision",
                baseline.sourceRevision,
                current.sourceRevision
            ),
            exactField("toolchain", "Toolchain", baseline.toolchainIdentity, current.toolchainIdentity),
            exactField("command", "Compiler command", baseline.commandFingerprint, current.commandFingerprint),
            releaseField(baseline: baseline, current: current),
            exactField("outcome", "Compile outcome", baseline.outcome.label, current.outcome.label),
            optionalStateField(
                "object",
                "Object result",
                baseline.objectResult.label,
                current.objectResult.label,
                baselineUnavailable: baseline.objectResult == .unrecorded,
                currentUnavailable: current.objectResult == .unrecorded
            ),
            exactField(
                "severity",
                "Maximum severity",
                String(baseline.maximumSeverity),
                String(current.maximumSeverity)
            ),
            exactField(
                "event-file",
                "Event-file identity",
                baseline.eventFileIdentity,
                current.eventFileIdentity
            ),
            exactField(
                "event-receipt",
                "Event evidence",
                baseline.eventEvidenceFingerprint,
                current.eventEvidenceFingerprint
            ),
            exactField("job", "Job identity", baseline.jobIdentity, current.jobIdentity)
        ]
    }

    private static func exactField(
        _ id: String,
        _ label: String,
        _ baseline: String,
        _ current: String
    ) -> CompileLineageFieldDelta {
        CompileLineageFieldDelta(
            id: id,
            label: label,
            baselineValue: baseline,
            currentValue: current,
            state: baseline == current ? .exact : .changed
        )
    }

    private static func optionalField(
        _ id: String,
        _ label: String,
        _ baseline: String?,
        _ current: String?,
        baselineDisplay: String? = nil,
        currentDisplay: String? = nil
    ) -> CompileLineageFieldDelta {
        let baselineValue = baselineDisplay ?? baseline ?? "UNRECORDED"
        let currentValue = currentDisplay ?? current ?? "UNRECORDED"
        let state: CompileLineageDeltaState = if baseline == nil || current == nil {
            .unavailable
        } else if baseline == current {
            .exact
        } else {
            .changed
        }
        return CompileLineageFieldDelta(
            id: id,
            label: label,
            baselineValue: baselineValue,
            currentValue: currentValue,
            state: state
        )
    }

    private static func optionalStateField(
        _ id: String,
        _ label: String,
        _ baseline: String,
        _ current: String,
        baselineUnavailable: Bool,
        currentUnavailable: Bool
    ) -> CompileLineageFieldDelta {
        CompileLineageFieldDelta(
            id: id,
            label: label,
            baselineValue: baseline,
            currentValue: current,
            state: baselineUnavailable || currentUnavailable
                ? .unavailable
                : (baseline == current ? .exact : .changed)
        )
    }

    private static func releaseField(
        baseline: CompileLineageRunEvidence,
        current: CompileLineageRunEvidence
    ) -> CompileLineageFieldDelta {
        let baselineToken = baseline.targetReleaseToken
        let currentToken = current.targetReleaseToken
        let baselineValue = releaseDisplay(run: baseline)
        let currentValue = releaseDisplay(run: current)
        let state: CompileLineageDeltaState
        if baselineToken == nil || currentToken == nil {
            state = .unavailable
        } else if baselineToken != currentToken {
            state = .changed
        } else if baselineToken == "*CURRENT" || baselineToken == "*PRV" {
            if let baselineRelease = baseline.observedHostRelease,
               let currentRelease = current.observedHostRelease {
                state = baselineRelease == currentRelease ? .exact : .changed
            } else {
                state = .relative
            }
        } else {
            state = .exact
        }
        return CompileLineageFieldDelta(
            id: "release",
            label: "Target release",
            baselineValue: baselineValue,
            currentValue: currentValue,
            state: state
        )
    }

    private static func releaseDisplay(run: CompileLineageRunEvidence) -> String {
        guard let token = run.targetReleaseToken else { return "UNRECORDED" }
        return run.observedHostRelease.map { "\(token) · \($0)" } ?? token
    }

    private static func makeDiagnosticDelta(
        baseline: CompileLineageRunEvidence,
        current: CompileLineageRunEvidence
    ) -> CompileLineageDiagnosticDelta {
        let baselineSet = Set(baseline.diagnostics)
        let currentSet = Set(current.diagnostics)
        return CompileLineageDiagnosticDelta(
            introduced: currentSet.subtracting(baselineSet).sorted(by: CompileLineageRunEvidence.diagnosticOrder),
            resolved: baselineSet.subtracting(currentSet).sorted(by: CompileLineageRunEvidence.diagnosticOrder),
            persistent: baselineSet.intersection(currentSet).sorted(by: CompileLineageRunEvidence.diagnosticOrder)
        )
    }

    private static func makeTrend(
        baseline: CompileLineageOutcome,
        current: CompileLineageOutcome
    ) -> CompileLineageTrend {
        if baseline == .evidenceOnly || current == .evidenceOnly { return .outcomeUnverified }
        if baseline == .passed, current == .failed { return .regressionObserved }
        if baseline == .failed, current == .passed { return .recoveryObserved }
        return baseline == current ? .outcomeStable : .outcomeChanged
    }

    private static func runOrder(
        _ lhs: CompileLineageRunEvidence,
        _ rhs: CompileLineageRunEvidence
    ) -> Bool {
        switch (lhs.sequence, rhs.sequence) {
        case let (left?, right?) where left != right: return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.fingerprint < rhs.fingerprint
        }
    }
}
