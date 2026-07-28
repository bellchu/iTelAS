import Foundation

public struct RunbookLimits: Equatable, Sendable {
    public var maximumDocumentBytes: Int
    public var maximumSteps: Int
    public var maximumParameters: Int
    public var maximumTemplateBytes: Int
    public var maximumTextCharacters: Int

    public init(
        maximumDocumentBytes: Int = 131_072,
        maximumSteps: Int = 32,
        maximumParameters: Int = 24,
        maximumTemplateBytes: Int = 4_096,
        maximumTextCharacters: Int = 512
    ) {
        self.maximumDocumentBytes = maximumDocumentBytes
        self.maximumSteps = maximumSteps
        self.maximumParameters = maximumParameters
        self.maximumTemplateBytes = maximumTemplateBytes
        self.maximumTextCharacters = maximumTextCharacters
    }

    public static let standard = RunbookLimits()
}

public enum RunbookError: Error, Equatable, LocalizedError, Sendable {
    case inputTooLarge(maximum: Int)
    case unsupportedSchema(Int)
    case malformedDocument
    case invalidIdentifier(field: String)
    case sensitiveParameter(String)
    case invalidText(field: String)
    case tooManyParameters(maximum: Int)
    case tooManySteps(maximum: Int)
    case duplicateParameter(String)
    case duplicateStep(Int)
    case nonContiguousStep(expected: Int, actual: Int)
    case invalidParameterDefinition(String)
    case missingParameter(String)
    case unexpectedParameter(String)
    case invalidParameterValue(String)
    case malformedTemplate(step: Int)
    case unknownPlaceholder(step: Int, key: String)
    case unsafeInterpolation(step: Int, key: String)
    case invalidStep(Int)
    case unsafeSQL(step: Int)
    case unsafeCL(step: Int)
    case environmentNotAllowed
    case mutationBudgetExceeded(maximum: Int, actual: Int)
    case duplicateApproval(String)
    case approvalPlanMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge(let maximum):
            "The runbook document exceeds the \(maximum)-byte local import limit."
        case .unsupportedSchema(let version):
            "Runbook schema version \(version) is not supported."
        case .malformedDocument:
            "The runbook document is not valid bounded JSON."
        case .invalidIdentifier(let field):
            "The runbook \(field) is not a valid uppercase identifier."
        case .sensitiveParameter(let key):
            "Runbook parameter \(key) appears to contain a credential or secret. Secrets are not valid runbook parameters."
        case .invalidText(let field):
            "The runbook \(field) is empty, oversized, or contains unsafe control text."
        case .tooManyParameters(let maximum):
            "The runbook contains more than \(maximum) parameters."
        case .tooManySteps(let maximum):
            "The runbook contains more than \(maximum) steps."
        case .duplicateParameter(let key):
            "Runbook parameter \(key) is defined more than once."
        case .duplicateStep(let number):
            "Runbook step \(number) is defined more than once."
        case .nonContiguousStep(let expected, let actual):
            "Runbook steps must be contiguous; expected \(expected) but found \(actual)."
        case .invalidParameterDefinition(let key):
            "Runbook parameter \(key) has an invalid type, default, or choice contract."
        case .missingParameter(let key):
            "Runbook parameter \(key) requires an exact value."
        case .unexpectedParameter(let key):
            "Runbook value \(key) has no matching parameter definition."
        case .invalidParameterValue(let key):
            "Runbook parameter \(key) does not satisfy its declared type."
        case .malformedTemplate(let step):
            "Runbook step \(step) contains malformed placeholder syntax."
        case .unknownPlaceholder(let step, let key):
            "Runbook step \(step) references undefined parameter \(key)."
        case .unsafeInterpolation(let step, let key):
            "Runbook step \(step) cannot interpolate free text from parameter \(key) into an action."
        case .invalidStep(let number):
            "Runbook step \(number) does not satisfy its type contract."
        case .unsafeSQL(let step):
            "Runbook step \(step) is not one bounded read-only SQL statement."
        case .unsafeCL(let step):
            "Runbook step \(step) contains an empty, multiline, or command-separated CL preview."
        case .environmentNotAllowed:
            "The selected environment is not allowed by this runbook blueprint."
        case .mutationBudgetExceeded(let maximum, let actual):
            "The resolved plan contains \(actual) mutating steps, exceeding its declared budget of \(maximum)."
        case .duplicateApproval(let role):
            "The runbook contains more than one local approval for \(role)."
        case .approvalPlanMismatch(let role):
            "The \(role) approval belongs to a different resolved plan fingerprint."
        }
    }
}

public struct RunbookIdentifier: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scalars = Array(value.unicodeScalars)
        let leading = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let remaining = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard (1...32).contains(scalars.count),
              let first = scalars.first,
              leading.contains(first),
              scalars.dropFirst().allSatisfy(remaining.contains) else {
            throw RunbookError.invalidIdentifier(field: "identifier")
        }
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

public struct RunbookParameterKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) throws {
        let identifier = try RunbookIdentifier(rawValue: rawValue)
        let compact = identifier.rawValue.replacingOccurrences(of: "_", with: "")
        let secretMarkers = ["PASSWORD", "PASSWD", "PWD", "APIKEY", "TOKEN", "SECRET", "CREDENTIAL"]
        guard !secretMarkers.contains(where: compact.contains) else {
            throw RunbookError.sensitiveParameter(identifier.rawValue)
        }
        self.rawValue = identifier.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

public enum RunbookParameterKind: String, Codable, CaseIterable, Sendable {
    case systemName
    case positiveInteger
    case boolean
    case choice
    case text

    public var label: String {
        switch self {
        case .systemName: "SYSTEM NAME"
        case .positiveInteger: "INTEGER"
        case .boolean: "BOOLEAN"
        case .choice: "CHOICE"
        case .text: "TEXT"
        }
    }
}

public struct RunbookParameterDefinition: Equatable, Sendable, Identifiable {
    public let key: RunbookParameterKey
    public let label: String
    public let kind: RunbookParameterKind
    public let required: Bool
    public let allowedValues: [String]
    public let defaultValue: String?

    public var id: RunbookParameterKey { key }

    public init(
        key: RunbookParameterKey,
        label: String,
        kind: RunbookParameterKind,
        required: Bool = true,
        allowedValues: [String] = [],
        defaultValue: String? = nil,
        limits: RunbookLimits = .standard
    ) throws {
        self.key = key
        self.label = try RunbookValidation.text(label, field: "parameter label", maximum: 80)
        self.kind = kind
        self.required = required
        self.allowedValues = allowedValues
        self.defaultValue = defaultValue

        guard allowedValues.count <= 32,
              (kind == .choice) == !allowedValues.isEmpty,
              Set(allowedValues.map { $0.uppercased() }).count == allowedValues.count else {
            throw RunbookError.invalidParameterDefinition(key.rawValue)
        }
        for choice in allowedValues {
            guard Self.isSafeChoice(choice) else {
                throw RunbookError.invalidParameterDefinition(key.rawValue)
            }
        }
        if let defaultValue {
            _ = try normalized(defaultValue, limits: limits)
        }
    }

    public func normalized(_ value: String, limits: RunbookLimits = .standard) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= limits.maximumTextCharacters,
              !RunbookValidation.hasUnsafeControls(trimmed) else {
            throw RunbookError.invalidParameterValue(key.rawValue)
        }
        switch kind {
        case .systemName:
            return try IBMSystemObjectName(trimmed).value
        case .positiveInteger:
            guard let number = Int(trimmed), (1...999_999_999).contains(number), String(number) == trimmed else {
                throw RunbookError.invalidParameterValue(key.rawValue)
            }
            return String(number)
        case .boolean:
            let upper = trimmed.uppercased()
            guard ["YES", "NO"].contains(upper) else {
                throw RunbookError.invalidParameterValue(key.rawValue)
            }
            return upper
        case .choice:
            guard let exact = allowedValues.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                throw RunbookError.invalidParameterValue(key.rawValue)
            }
            return exact.uppercased()
        case .text:
            return trimmed
        }
    }

    private static func isSafeChoice(_ value: String) -> Bool {
        let upper = value.uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_*#$@.-")
        return (1...32).contains(upper.unicodeScalars.count)
            && upper.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public enum RunbookStepKind: String, Codable, CaseIterable, Sendable {
    case assertion
    case sqlRead
    case clPreview
    case approvalGate
    case evidenceCapture
    case operatorNote

    public var label: String {
        switch self {
        case .assertion: "ASSERT"
        case .sqlRead: "SQL READ"
        case .clPreview: "CL REVIEW"
        case .approvalGate: "GATE"
        case .evidenceCapture: "EVIDENCE"
        case .operatorNote: "NOTE"
        }
    }
}

public enum RunbookApprovalRole: String, Codable, CaseIterable, Sendable {
    case developer
    case operations
    case security
    case owner

    public var label: String { rawValue.uppercased() }
}

public enum RunbookEvidenceKind: String, Codable, CaseIterable, Sendable {
    case planFingerprint
    case sourceBaseline
    case queryReceipt
    case commandPreview
    case eventFile
    case jobLog
    case objectSignature
    case operatorNote

    public var label: String {
        switch self {
        case .planFingerprint: "PLAN FINGERPRINT"
        case .sourceBaseline: "SOURCE BASELINE"
        case .queryReceipt: "QUERY RECEIPT"
        case .commandPreview: "COMMAND PREVIEW"
        case .eventFile: "EVENT FILE"
        case .jobLog: "JOB LOG"
        case .objectSignature: "OBJECT SIGNATURE"
        case .operatorNote: "OPERATOR NOTE"
        }
    }
}

public struct RunbookEvidenceRequirement: Equatable, Sendable, Identifiable {
    public let kind: RunbookEvidenceKind
    public let label: String
    public let required: Bool

    public var id: String { "\(kind.rawValue)\u{1F}\(label)" }

    public init(kind: RunbookEvidenceKind, label: String, required: Bool = true) throws {
        self.kind = kind
        self.label = try RunbookValidation.text(label, field: "evidence label", maximum: 96)
        self.required = required
    }
}

public struct RunbookStep: Equatable, Sendable, Identifiable {
    public let number: Int
    public let kind: RunbookStepKind
    public let title: String
    public let detail: String
    public let template: String?
    public let maximumRows: Int?
    public let timeoutSeconds: Int?
    public let approvalRoles: [RunbookApprovalRole]
    public let evidence: [RunbookEvidenceRequirement]

    public var id: Int { number }
    public var stopsOnFailure: Bool { true }

    public init(
        number: Int,
        kind: RunbookStepKind,
        title: String,
        detail: String,
        template: String? = nil,
        maximumRows: Int? = nil,
        timeoutSeconds: Int? = nil,
        approvalRoles: [RunbookApprovalRole] = [],
        evidence: [RunbookEvidenceRequirement] = [],
        limits: RunbookLimits = .standard
    ) throws {
        guard number > 0 else { throw RunbookError.invalidStep(number) }
        self.number = number
        self.kind = kind
        self.title = try RunbookValidation.text(title, field: "step \(number) title", maximum: 120)
        self.detail = try RunbookValidation.text(detail, field: "step \(number) detail", maximum: limits.maximumTextCharacters)
        self.template = try template.map {
            let validated = try RunbookValidation.text(
                $0,
                field: "step \(number) template",
                maximum: limits.maximumTemplateBytes,
                trim: false,
                allowLayoutWhitespace: true
            )
            guard validated.utf8.count <= limits.maximumTemplateBytes else {
                throw RunbookError.invalidText(field: "step \(number) template")
            }
            return validated
        }
        self.maximumRows = maximumRows
        self.timeoutSeconds = timeoutSeconds
        self.approvalRoles = approvalRoles
        self.evidence = evidence

        let rolesAreUnique = Set(approvalRoles).count == approvalRoles.count
        let evidenceIsUnique = Set(evidence.map(\.id)).count == evidence.count
        guard rolesAreUnique, evidenceIsUnique else { throw RunbookError.invalidStep(number) }

        switch kind {
        case .sqlRead:
            guard self.template != nil,
                  let maximumRows, (1...250).contains(maximumRows),
                  let timeoutSeconds, (1...30).contains(timeoutSeconds),
                  approvalRoles.isEmpty else {
                throw RunbookError.invalidStep(number)
            }
        case .clPreview:
            guard self.template != nil,
                  maximumRows == nil,
                  timeoutSeconds == nil,
                  approvalRoles.isEmpty else {
                throw RunbookError.invalidStep(number)
            }
        case .approvalGate:
            guard self.template == nil,
                  maximumRows == nil,
                  timeoutSeconds == nil,
                  !approvalRoles.isEmpty else {
                throw RunbookError.invalidStep(number)
            }
        case .assertion, .evidenceCapture, .operatorNote:
            guard self.template == nil,
                  maximumRows == nil,
                  timeoutSeconds == nil,
                  approvalRoles.isEmpty else {
                throw RunbookError.invalidStep(number)
            }
        }
    }
}

public struct RunbookBlueprint: Equatable, Sendable, Identifiable {
    public let id: RunbookIdentifier
    public let revision: Int
    public let name: String
    public let summary: String
    public let ownerAlias: String
    public let allowedEnvironments: [IBMEnvironment]
    public let mutationBudget: Int
    public let parameters: [RunbookParameterDefinition]
    public let steps: [RunbookStep]

    public init(
        id: RunbookIdentifier,
        revision: Int,
        name: String,
        summary: String,
        ownerAlias: String,
        allowedEnvironments: [IBMEnvironment],
        mutationBudget: Int,
        parameters: [RunbookParameterDefinition],
        steps: [RunbookStep],
        limits: RunbookLimits = .standard
    ) throws {
        guard revision > 0, mutationBudget >= 0 else { throw RunbookError.invalidIdentifier(field: "revision") }
        guard !allowedEnvironments.isEmpty, Set(allowedEnvironments).count == allowedEnvironments.count else {
            throw RunbookError.environmentNotAllowed
        }
        guard parameters.count <= limits.maximumParameters else {
            throw RunbookError.tooManyParameters(maximum: limits.maximumParameters)
        }
        guard !steps.isEmpty, steps.count <= limits.maximumSteps else {
            throw RunbookError.tooManySteps(maximum: limits.maximumSteps)
        }

        let duplicateParameter = Dictionary(grouping: parameters, by: \.key).first { $0.value.count > 1 }?.key
        if let duplicateParameter { throw RunbookError.duplicateParameter(duplicateParameter.rawValue) }
        let duplicateStep = Dictionary(grouping: steps, by: \.number).first { $0.value.count > 1 }?.key
        if let duplicateStep { throw RunbookError.duplicateStep(duplicateStep) }

        let orderedSteps = steps.sorted { $0.number < $1.number }
        for (offset, step) in orderedSteps.enumerated() where step.number != offset + 1 {
            throw RunbookError.nonContiguousStep(expected: offset + 1, actual: step.number)
        }

        let definitions = Dictionary(uniqueKeysWithValues: parameters.map { ($0.key, $0) })
        for step in orderedSteps {
            guard let template = step.template else { continue }
            let placeholders = try RunbookTemplateEngine().placeholders(in: template, step: step.number)
            for key in placeholders {
                guard let definition = definitions[key] else {
                    throw RunbookError.unknownPlaceholder(step: step.number, key: key.rawValue)
                }
                if definition.kind == .text {
                    throw RunbookError.unsafeInterpolation(step: step.number, key: key.rawValue)
                }
            }
        }

        self.id = id
        self.revision = revision
        self.name = try RunbookValidation.text(name, field: "name", maximum: 120)
        self.summary = try RunbookValidation.text(summary, field: "summary", maximum: limits.maximumTextCharacters)
        self.ownerAlias = try RunbookValidation.text(ownerAlias, field: "owner alias", maximum: 64)
        self.allowedEnvironments = allowedEnvironments
        self.mutationBudget = mutationBudget
        self.parameters = parameters
        self.steps = orderedSteps
    }
}

public enum RunbookRisk: String, Codable, CaseIterable, Sendable {
    case none
    case readOnly
    case mutating
    case destructive
    case unknown

    public var label: String {
        switch self {
        case .none: "LOCAL"
        case .readOnly: "READ ONLY"
        case .mutating: "MUTATING"
        case .destructive: "DESTRUCTIVE"
        case .unknown: "UNKNOWN"
        }
    }
}

public struct ResolvedRunbookStep: Equatable, Sendable, Identifiable {
    public let number: Int
    public let kind: RunbookStepKind
    public let title: String
    public let detail: String
    public let resolvedAction: String?
    public let risk: RunbookRisk
    public let maximumRows: Int?
    public let timeoutSeconds: Int?
    public let approvalRoles: [RunbookApprovalRole]
    public let evidence: [RunbookEvidenceRequirement]

    public var id: Int { number }
}

public struct RunbookLocalApproval: Equatable, Sendable, Identifiable {
    public let role: RunbookApprovalRole
    public let reviewerAlias: String
    public let planFingerprint: String
    public let recordedAt: Date

    public var id: RunbookApprovalRole { role }
    public var identityWasCryptographicallyVerified: Bool { false }

    public init(
        role: RunbookApprovalRole,
        reviewerAlias: String,
        planFingerprint: String,
        recordedAt: Date
    ) throws {
        self.role = role
        self.reviewerAlias = try RunbookValidation.text(reviewerAlias, field: "reviewer alias", maximum: 64)
        guard planFingerprint.count == 64,
              planFingerprint.unicodeScalars.allSatisfy(CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains) else {
            throw RunbookError.invalidText(field: "approval fingerprint")
        }
        self.planFingerprint = planFingerprint.lowercased()
        self.recordedAt = recordedAt
    }
}

public enum RunbookCheckState: String, Sendable {
    case pass
    case review
    case blocked

    public var label: String { rawValue.uppercased() }
}

public enum RunbookCheckKind: String, CaseIterable, Sendable {
    case environment
    case typedParameters
    case actionClassification
    case mutationReason
    case approvals
    case evidenceContract
    case executionConnector

    public var label: String {
        switch self {
        case .environment: "Exact environment"
        case .typedParameters: "Typed substitutions"
        case .actionClassification: "Action classification"
        case .mutationReason: "Mutation consent"
        case .approvals: "Approval policy"
        case .evidenceContract: "Evidence contract"
        case .executionConnector: "Execution connector"
        }
    }
}

public struct RunbookCheck: Equatable, Sendable, Identifiable {
    public let kind: RunbookCheckKind
    public let state: RunbookCheckState
    public let code: String
    public let detail: String

    public var id: RunbookCheckKind { kind }
}

public struct RunbookAssessment: Equatable, Sendable {
    public let verdict: String
    public let checks: [RunbookCheck]
    public let mutatingStepCount: Int
    public let destructiveStepCount: Int
    public let missingApprovalRoles: [RunbookApprovalRole]

    public var isExecutable: Bool { false }
    public var openCheckCount: Int { checks.filter { $0.state != .pass }.count }
    public var issueCodes: [String] { checks.filter { $0.state != .pass }.map(\.code) }
}

public struct ResolvedRunbook: Equatable, Sendable {
    public let blueprint: RunbookBlueprint
    public let targetName: String
    public let environment: IBMEnvironment
    public let parameterValues: [RunbookParameterKey: String]
    public let steps: [ResolvedRunbookStep]
    public let planFingerprint: String
    public let operatorReason: String?
    public let approvals: [RunbookLocalApproval]
    public let assessment: RunbookAssessment
    public let resolvedAt: Date
    public let isBundledReplay: Bool
}

public struct RunbookResolver: Sendable {
    private let limits: RunbookLimits

    public init(limits: RunbookLimits = .standard) {
        self.limits = limits
    }

    public func resolve(
        blueprint: RunbookBlueprint,
        targetName: String,
        environment: IBMEnvironment,
        values: [RunbookParameterKey: String],
        operatorReason: String? = nil,
        approvals: [RunbookLocalApproval] = [],
        resolvedAt: Date = Date(),
        isBundledReplay: Bool = false
    ) throws -> ResolvedRunbook {
        guard blueprint.allowedEnvironments.contains(environment) else {
            throw RunbookError.environmentNotAllowed
        }
        let safeTarget = try RunbookValidation.text(targetName, field: "target name", maximum: 120)
        let definitions = Dictionary(uniqueKeysWithValues: blueprint.parameters.map { ($0.key, $0) })
        for key in values.keys where definitions[key] == nil {
            throw RunbookError.unexpectedParameter(key.rawValue)
        }

        var normalized: [RunbookParameterKey: String] = [:]
        for definition in blueprint.parameters {
            let supplied = values[definition.key] ?? definition.defaultValue
            guard let supplied else {
                if definition.required { throw RunbookError.missingParameter(definition.key.rawValue) }
                continue
            }
            normalized[definition.key] = try definition.normalized(supplied, limits: limits)
        }

        let engine = RunbookTemplateEngine()
        var resolvedSteps: [ResolvedRunbookStep] = []
        for step in blueprint.steps {
            let action = try step.template.map {
                try engine.resolve($0, step: step.number, definitions: definitions, values: normalized)
            }
            let risk: RunbookRisk
            switch step.kind {
            case .sqlRead:
                guard let action,
                      SQLStatementAnalyzer().analyze(action).isSingleReadOnlyStatement,
                      let maximumRows = step.maximumRows,
                      (1...250).contains(maximumRows),
                      let timeoutSeconds = step.timeoutSeconds,
                      (1...30).contains(timeoutSeconds) else {
                    throw RunbookError.unsafeSQL(step: step.number)
                }
                risk = .readOnly
            case .clPreview:
                guard let action,
                      !action.contains(";"),
                      !action.contains("\n"),
                      !action.contains("\r") else {
                    throw RunbookError.unsafeCL(step: step.number)
                }
                risk = Self.risk(for: IBMCommandSafetyClassifier().classify(action))
            case .assertion, .approvalGate, .evidenceCapture, .operatorNote:
                risk = .none
            }
            resolvedSteps.append(ResolvedRunbookStep(
                number: step.number,
                kind: step.kind,
                title: step.title,
                detail: step.detail,
                resolvedAction: action,
                risk: risk,
                maximumRows: step.maximumRows,
                timeoutSeconds: step.timeoutSeconds,
                approvalRoles: step.approvalRoles,
                evidence: step.evidence
            ))
        }

        let mutatingCount = resolvedSteps.filter { $0.risk == .mutating || $0.risk == .destructive }.count
        guard mutatingCount <= blueprint.mutationBudget else {
            throw RunbookError.mutationBudgetExceeded(maximum: blueprint.mutationBudget, actual: mutatingCount)
        }
        let fingerprint = Self.fingerprint(
            blueprint: blueprint,
            targetName: safeTarget,
            environment: environment,
            values: normalized,
            steps: resolvedSteps
        )

        if let duplicate = Dictionary(grouping: approvals, by: \.role).first(where: { $0.value.count > 1 })?.key {
            throw RunbookError.duplicateApproval(duplicate.label)
        }
        for approval in approvals where approval.planFingerprint != fingerprint {
            throw RunbookError.approvalPlanMismatch(approval.role.label)
        }

        let reason = try operatorReason.map {
            try RunbookValidation.text($0, field: "operator reason", maximum: 240)
        }
        let assessment = Self.assess(
            blueprint: blueprint,
            environment: environment,
            steps: resolvedSteps,
            reason: reason,
            approvals: approvals
        )
        return ResolvedRunbook(
            blueprint: blueprint,
            targetName: safeTarget,
            environment: environment,
            parameterValues: normalized,
            steps: resolvedSteps,
            planFingerprint: fingerprint,
            operatorReason: reason,
            approvals: approvals.sorted { $0.role.rawValue < $1.role.rawValue },
            assessment: assessment,
            resolvedAt: resolvedAt,
            isBundledReplay: isBundledReplay
        )
    }

    private static func risk(for commandRisk: CommandRisk) -> RunbookRisk {
        switch commandRisk {
        case .readOnly: .readOnly
        case .mutating: .mutating
        case .destructive: .destructive
        case .unknown: .unknown
        }
    }

    private static func fingerprint(
        blueprint: RunbookBlueprint,
        targetName: String,
        environment: IBMEnvironment,
        values: [RunbookParameterKey: String],
        steps: [ResolvedRunbookStep]
    ) -> String {
        var canonical = "RUNBOOK-PLAN-V2"
        func appendRecord(_ tag: String, _ fields: [String]) {
            canonical.append("\n")
            canonical.append(tag)
            for field in fields {
                canonical.append("|")
                canonical.append(String(field.utf8.count))
                canonical.append(":")
                canonical.append(field)
            }
        }

        appendRecord("BLUEPRINT", [
            blueprint.id.rawValue,
            String(blueprint.revision),
            blueprint.name,
            blueprint.summary,
            blueprint.ownerAlias,
            blueprint.allowedEnvironments.map(\.rawValue).sorted().joined(separator: ","),
            String(blueprint.mutationBudget)
        ])
        appendRecord("TARGET", [targetName, environment.rawValue])
        for definition in blueprint.parameters {
            appendRecord("PARAMETER", [
                definition.key.rawValue,
                definition.label,
                definition.kind.rawValue,
                String(definition.required),
                definition.allowedValues.joined(separator: ","),
                values[definition.key] ?? "<OMITTED>"
            ])
        }
        for step in steps {
            appendRecord("STEP", [
                String(step.number),
                step.kind.rawValue,
                step.title,
                step.detail,
                step.risk.rawValue,
                step.resolvedAction ?? "<LOCAL>",
                step.maximumRows.map(String.init) ?? "<NONE>",
                step.timeoutSeconds.map(String.init) ?? "<NONE>"
            ])
            for evidence in step.evidence {
                appendRecord("EVIDENCE", [
                    String(step.number),
                    evidence.kind.rawValue,
                    evidence.label,
                    String(evidence.required)
                ])
            }
            appendRecord("APPROVAL-ROLES", [
                String(step.number),
                step.approvalRoles.map(\.rawValue).sorted().joined(separator: ",")
            ])
        }
        return AIContentFingerprint.sha256(canonical)
    }

    private static func assess(
        blueprint: RunbookBlueprint,
        environment: IBMEnvironment,
        steps: [ResolvedRunbookStep],
        reason: String?,
        approvals: [RunbookLocalApproval]
    ) -> RunbookAssessment {
        let mutating = steps.filter { $0.risk == .mutating || $0.risk == .destructive }
        let destructive = steps.filter { $0.risk == .destructive }
        let unknown = steps.filter { $0.risk == .unknown }
        let requiredRoles = Set(steps.flatMap(\.approvalRoles))
        let approvedRoles = Set(approvals.map(\.role))
        let missingRoles = requiredRoles.subtracting(approvedRoles).sorted { $0.rawValue < $1.rawValue }
        let requiredEvidence = steps.flatMap(\.evidence).filter(\.required)
        let evidenceKinds = Set(requiredEvidence.map(\.kind))
        let mutationHasPreview = mutating.isEmpty || evidenceKinds.contains(.commandPreview)
        let mutationHasFollowUp = mutating.isEmpty || evidenceKinds.contains(.eventFile)
            || evidenceKinds.contains(.jobLog)
            || evidenceKinds.contains(.objectSignature)

        var checks: [RunbookCheck] = []
        checks.append(RunbookCheck(
            kind: .environment,
            state: environment == .production ? .review : .pass,
            code: environment == .production ? "PRODUCTION_REVIEW_REQUIRED" : "EXACT_NONPRODUCTION_TARGET",
            detail: environment == .production
                ? "Production remains a separate reviewed boundary; this local plan cannot execute."
                : "The selected environment is exact, allowed, and non-production."
        ))
        checks.append(RunbookCheck(
            kind: .typedParameters,
            state: .pass,
            code: "TYPED_VALUES_VALID",
            detail: "All \(blueprint.parameters.count) supplied values satisfy their declared types; no secret parameter type exists."
        ))
        let riskState: RunbookCheckState = !destructive.isEmpty || !unknown.isEmpty ? .blocked : (mutating.isEmpty ? .pass : .review)
        checks.append(RunbookCheck(
            kind: .actionClassification,
            state: riskState,
            code: !destructive.isEmpty ? "DESTRUCTIVE_PREVIEW_BLOCKED" : !unknown.isEmpty ? "UNKNOWN_ACTION_BLOCKED" : mutating.isEmpty ? "READ_ONLY_OR_LOCAL" : "MUTATION_REVIEW_REQUIRED",
            detail: "Resolved actions contain \(mutating.count) mutating, \(destructive.count) destructive, and \(unknown.count) unknown step(s)."
        ))
        checks.append(RunbookCheck(
            kind: .mutationReason,
            state: mutating.isEmpty || reason != nil ? .pass : .review,
            code: mutating.isEmpty || reason != nil ? "MUTATION_REASON_SATISFIED" : "MUTATION_REASON_MISSING",
            detail: mutating.isEmpty ? "The plan contains no mutating action preview." : (reason == nil ? "Record an operator reason before any future execution review." : "A bounded operator reason is attached to this plan.")
        ))
        checks.append(RunbookCheck(
            kind: .approvals,
            state: missingRoles.isEmpty ? .pass : .review,
            code: missingRoles.isEmpty ? "LOCAL_APPROVALS_RECORDED" : "APPROVAL_MISSING",
            detail: missingRoles.isEmpty
                ? "All declared local review roles are recorded; reviewer identity is not cryptographically verified."
                : "Missing local review role(s): \(missingRoles.map(\.label).joined(separator: ", "))."
        ))
        checks.append(RunbookCheck(
            kind: .evidenceContract,
            state: mutationHasPreview && mutationHasFollowUp ? .pass : .review,
            code: mutationHasPreview && mutationHasFollowUp ? "EVIDENCE_CONTRACT_DECLARED" : "EVIDENCE_CONTRACT_INCOMPLETE",
            detail: "The blueprint declares \(requiredEvidence.count) required evidence receipt(s); declaration is not collection."
        ))
        checks.append(RunbookCheck(
            kind: .executionConnector,
            state: .blocked,
            code: "EXECUTION_CONNECTOR_UNAVAILABLE",
            detail: "This milestone has no runbook executor, scheduler, remote runner, command submitter, or automatic resume path."
        ))
        return RunbookAssessment(
            verdict: "REVIEW REQUIRED",
            checks: checks,
            mutatingStepCount: mutating.count,
            destructiveStepCount: destructive.count,
            missingApprovalRoles: missingRoles
        )
    }
}

public struct RunbookArtifactBuilder: Sendable {
    public init() {}

    public func build(_ runbook: ResolvedRunbook) -> String {
        var lines = [
            "iTelAS RUNBOOK REVIEW ARTIFACT",
            "Blueprint: \(runbook.blueprint.id.rawValue) revision \(runbook.blueprint.revision)",
            "Name: \(runbook.blueprint.name)",
            "Owner alias: \(runbook.blueprint.ownerAlias)",
            "Target: \(runbook.targetName)",
            "Environment: \(runbook.environment.label)",
            "Plan SHA-256: \(runbook.planFingerprint)",
            "Verdict: \(runbook.assessment.verdict)",
            "Executable: NO",
            "Operator reason: \(runbook.operatorReason ?? "NOT RECORDED")",
            "",
            "PARAMETERS"
        ]
        for definition in runbook.blueprint.parameters {
            lines.append("\(definition.key.rawValue) [\(definition.kind.label)]: \(runbook.parameterValues[definition.key] ?? "OMITTED")")
        }
        lines.append("")
        lines.append("RESOLVED STEPS")
        for step in runbook.steps {
            lines.append("\(String(format: "%02d", step.number)) [\(step.kind.label)] [\(step.risk.label)] \(step.title)")
            if let action = step.resolvedAction {
                lines.append("  PREVIEW:")
                for line in action.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("    | \(line)")
                }
            }
            if let maximumRows = step.maximumRows, let timeoutSeconds = step.timeoutSeconds {
                lines.append("  BOUNDS: \(maximumRows) rows / \(timeoutSeconds) seconds")
            }
            for evidence in step.evidence {
                lines.append("  EVIDENCE \(evidence.required ? "REQUIRED" : "OPTIONAL"): \(evidence.kind.label) — \(evidence.label)")
            }
        }
        lines.append("")
        lines.append("PREFLIGHT CHECKS")
        for check in runbook.assessment.checks {
            lines.append("[\(check.state.label)] \(check.code) — \(check.detail)")
        }
        lines.append("")
        lines.append("LOCAL REVIEW ATTESTATIONS")
        if runbook.approvals.isEmpty {
            lines.append("NONE")
        } else {
            for approval in runbook.approvals {
                lines.append("\(approval.role.label): \(approval.reviewerAlias) — local record only; identity not cryptographically verified")
            }
        }
        lines.append("")
        lines.append("LIMITATIONS")
        lines.append("- No host action, command submission, SQL execution, scheduling, or automatic resume occurred.")
        lines.append("- Local validation is not proof of authority, current target state, rollback success, or execution success.")
        lines.append("- Approval records are local attestations, not authenticated signatures.")
        lines.append("- Evidence requirements describe what must be collected; this artifact does not fabricate those receipts.")
        return lines.joined(separator: "\n")
    }
}

public struct RunbookAssistContextBuilder: Sendable {
    public init() {}

    public func build(_ runbook: ResolvedRunbook) -> String {
        var lines = [
            "ITELAS RUNBOOK REVIEW CONTEXT",
            "Blueprint identity: WITHHELD",
            "Target identity: WITHHELD",
            "Environment class: \(runbook.environment == .production ? "PRODUCTION" : "NON-PRODUCTION")",
            "Typed parameter values: \(runbook.parameterValues.count) WITHHELD",
            "Resolved command and SQL text: WITHHELD",
            "Owner and reviewer identities: WITHHELD",
            "Fingerprints and timestamps: WITHHELD",
            "",
            "STEP CONTRACT"
        ]
        for step in runbook.steps {
            let evidenceKinds = step.evidence.map { $0.kind.label }.joined(separator: ", ")
            lines.append("STEP-\(String(format: "%03d", step.number)): \(step.kind.label) · risk \(step.risk.label) · required evidence \(evidenceKinds.isEmpty ? "NONE" : evidenceKinds)")
        }
        lines.append("")
        lines.append("OPEN CHECKS")
        for check in runbook.assessment.checks where check.state != .pass {
            lines.append("\(check.code): \(check.kind.label)")
        }
        lines.append("")
        lines.append("BOUNDARY")
        lines.append("Advice only. Do not infer authority, approval, current host state, rollback success, or permission to execute.")
        lines.append("iTelAS cannot execute, approve, schedule, or resume this runbook.")
        return lines.joined(separator: "\n")
    }
}

public struct RunbookBlueprintCodec: Sendable {
    private let limits: RunbookLimits

    public init(limits: RunbookLimits = .standard) {
        self.limits = limits
    }

    public func decode(_ data: Data) throws -> RunbookBlueprint {
        guard data.count <= limits.maximumDocumentBytes else {
            throw RunbookError.inputTooLarge(maximum: limits.maximumDocumentBytes)
        }
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw RunbookError.malformedDocument
        }
        guard document.schemaVersion == 1 else {
            throw RunbookError.unsupportedSchema(document.schemaVersion)
        }
        do {
            let parameters = try document.parameters.map { dto in
                try RunbookParameterDefinition(
                    key: RunbookParameterKey(rawValue: dto.key),
                    label: dto.label,
                    kind: dto.kind,
                    required: dto.required,
                    allowedValues: dto.allowedValues,
                    defaultValue: dto.defaultValue,
                    limits: limits
                )
            }
            let steps = try document.steps.map { dto in
                try RunbookStep(
                    number: dto.number,
                    kind: dto.kind,
                    title: dto.title,
                    detail: dto.detail,
                    template: dto.template,
                    maximumRows: dto.maximumRows,
                    timeoutSeconds: dto.timeoutSeconds,
                    approvalRoles: dto.approvalRoles,
                    evidence: try dto.evidence.map {
                        try RunbookEvidenceRequirement(kind: $0.kind, label: $0.label, required: $0.required)
                    },
                    limits: limits
                )
            }
            return try RunbookBlueprint(
                id: RunbookIdentifier(rawValue: document.id),
                revision: document.revision,
                name: document.name,
                summary: document.summary,
                ownerAlias: document.ownerAlias,
                allowedEnvironments: document.allowedEnvironments,
                mutationBudget: document.mutationBudget,
                parameters: parameters,
                steps: steps,
                limits: limits
            )
        } catch let error as RunbookError {
            throw error
        } catch {
            throw RunbookError.malformedDocument
        }
    }

    public func encode(_ blueprint: RunbookBlueprint) throws -> Data {
        let document = Document(
            schemaVersion: 1,
            id: blueprint.id.rawValue,
            revision: blueprint.revision,
            name: blueprint.name,
            summary: blueprint.summary,
            ownerAlias: blueprint.ownerAlias,
            allowedEnvironments: blueprint.allowedEnvironments,
            mutationBudget: blueprint.mutationBudget,
            parameters: blueprint.parameters.map {
                ParameterDTO(
                    key: $0.key.rawValue,
                    label: $0.label,
                    kind: $0.kind,
                    required: $0.required,
                    allowedValues: $0.allowedValues,
                    defaultValue: $0.defaultValue
                )
            },
            steps: blueprint.steps.map {
                StepDTO(
                    number: $0.number,
                    kind: $0.kind,
                    title: $0.title,
                    detail: $0.detail,
                    template: $0.template,
                    maximumRows: $0.maximumRows,
                    timeoutSeconds: $0.timeoutSeconds,
                    approvalRoles: $0.approvalRoles,
                    evidence: $0.evidence.map { EvidenceDTO(kind: $0.kind, label: $0.label, required: $0.required) }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= limits.maximumDocumentBytes else {
            throw RunbookError.inputTooLarge(maximum: limits.maximumDocumentBytes)
        }
        return data
    }

    private struct Document: Codable {
        let schemaVersion: Int
        let id: String
        let revision: Int
        let name: String
        let summary: String
        let ownerAlias: String
        let allowedEnvironments: [IBMEnvironment]
        let mutationBudget: Int
        let parameters: [ParameterDTO]
        let steps: [StepDTO]
    }

    private struct ParameterDTO: Codable {
        let key: String
        let label: String
        let kind: RunbookParameterKind
        let required: Bool
        let allowedValues: [String]
        let defaultValue: String?
    }

    private struct StepDTO: Codable {
        let number: Int
        let kind: RunbookStepKind
        let title: String
        let detail: String
        let template: String?
        let maximumRows: Int?
        let timeoutSeconds: Int?
        let approvalRoles: [RunbookApprovalRole]
        let evidence: [EvidenceDTO]
    }

    private struct EvidenceDTO: Codable {
        let kind: RunbookEvidenceKind
        let label: String
        let required: Bool
    }
}

private struct RunbookTemplateEngine: Sendable {
    func placeholders(in template: String, step: Int) throws -> [RunbookParameterKey] {
        var keys: [RunbookParameterKey] = []
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{" {
                let next = template.index(after: cursor)
                guard next < template.endIndex, template[next] == "{" else {
                    throw RunbookError.malformedTemplate(step: step)
                }
                let contentStart = template.index(after: next)
                guard let close = template[contentStart...].range(of: "}}") else {
                    throw RunbookError.malformedTemplate(step: step)
                }
                let rawKey = String(template[contentStart..<close.lowerBound])
                guard !rawKey.contains("{") && !rawKey.contains("}") else {
                    throw RunbookError.malformedTemplate(step: step)
                }
                do {
                    let key = try RunbookParameterKey(rawValue: rawKey)
                    guard rawKey == key.rawValue else {
                        throw RunbookError.malformedTemplate(step: step)
                    }
                    keys.append(key)
                } catch {
                    throw RunbookError.malformedTemplate(step: step)
                }
                cursor = close.upperBound
            } else if template[cursor] == "}" {
                throw RunbookError.malformedTemplate(step: step)
            } else {
                cursor = template.index(after: cursor)
            }
        }
        return keys
    }

    func resolve(
        _ template: String,
        step: Int,
        definitions: [RunbookParameterKey: RunbookParameterDefinition],
        values: [RunbookParameterKey: String]
    ) throws -> String {
        let keys = try placeholders(in: template, step: step)
        var result = template
        for key in keys {
            guard let definition = definitions[key] else {
                throw RunbookError.unknownPlaceholder(step: step, key: key.rawValue)
            }
            guard definition.kind != .text else {
                throw RunbookError.unsafeInterpolation(step: step, key: key.rawValue)
            }
            guard let value = values[key] else {
                throw RunbookError.missingParameter(key.rawValue)
            }
            result = result.replacingOccurrences(of: "{{\(key.rawValue)}}", with: value)
        }
        guard !result.contains("{{"), !result.contains("}}") else {
            throw RunbookError.malformedTemplate(step: step)
        }
        return result
    }
}

private enum RunbookValidation {
    static func text(
        _ value: String,
        field: String,
        maximum: Int,
        trim: Bool = true,
        allowLayoutWhitespace: Bool = false
    ) throws -> String {
        let candidate = trim ? value.trimmingCharacters(in: .whitespacesAndNewlines) : value
        guard !candidate.isEmpty,
              candidate.count <= maximum,
              !hasUnsafeControls(candidate, allowLayoutWhitespace: allowLayoutWhitespace) else {
            throw RunbookError.invalidText(field: field)
        }
        return candidate
    }

    static func hasUnsafeControls(_ value: String, allowLayoutWhitespace: Bool = false) -> Bool {
        value.unicodeScalars.contains { scalar in
            guard CharacterSet.controlCharacters.contains(scalar) else { return false }
            return !allowLayoutWhitespace || (scalar.value != 10 && scalar.value != 9)
        }
    }
}
