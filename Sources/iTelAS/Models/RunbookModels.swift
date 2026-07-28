import Foundation
import iTelASCore

enum RunbookPhase: Equatable {
    case localReplay
    case draft
    case validating
    case ready
    case failed

    var label: String {
        switch self {
        case .localReplay: "LOCAL BLUEPRINT"
        case .draft: "VALIDATION STALE"
        case .validating: "VALIDATING"
        case .ready: "LOCALLY VALIDATED"
        case .failed: "BLUEPRINT BLOCKED"
        }
    }
}

enum RunbookCatalogOrigin: Equatable {
    case bundledReplay
    case localImport(fileName: String)
    case study

    var label: String {
        switch self {
        case .bundledReplay: "LOCAL REPLAY"
        case .localImport: "LOCAL IMPORT"
        case .study: "BLUEPRINT STUDY"
        }
    }
}

struct RunbookCatalogItem: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let stepCount: Int
    let status: String
    let origin: RunbookCatalogOrigin
    let blueprint: RunbookBlueprint?

    var isAvailable: Bool { blueprint != nil }
}

enum RunbookDisplayStepState: String {
    case pass = "PASS"
    case review = "REVIEW"
    case waiting = "WAITING"
    case pending = "PENDING"
    case blocked = "BLOCKED"
}

enum RunbookSamples {
    static let selectedID = "COMPILE_VERIFY"
    static let selectedStepNumber = 5
    static let capturedAt = Date(timeIntervalSince1970: 1_785_164_812)

    static func makeLibrary() -> [RunbookCatalogItem] {
        [
            RunbookCatalogItem(
                id: selectedID,
                title: "Compile & verify ORDERENTRY",
                category: "DEVELOPMENT",
                stepCount: 8,
                status: "REVIEW",
                origin: .bundledReplay,
                blueprint: makeBlueprint()
            ),
            RunbookCatalogItem(
                id: "LOCK_INCIDENT",
                title: "Resolve object-lock incident",
                category: "OPERATIONS",
                stepCount: 6,
                status: "STUDY",
                origin: .study,
                blueprint: nil
            ),
            RunbookCatalogItem(
                id: "WRITER_RECOVERY",
                title: "Restart stalled writer",
                category: "OUTPUT",
                stepCount: 7,
                status: "STUDY",
                origin: .study,
                blueprint: nil
            ),
            RunbookCatalogItem(
                id: "SPOOL_HANDOFF",
                title: "Quarter-end spool handoff",
                category: "OUTPUT",
                stepCount: 9,
                status: "STUDY",
                origin: .study,
                blueprint: nil
            ),
            RunbookCatalogItem(
                id: "PTF_READINESS",
                title: "PTF readiness sweep",
                category: "MAINTENANCE",
                stepCount: 5,
                status: "STUDY",
                origin: .study,
                blueprint: nil
            )
        ]
    }

    static func makeResolution() -> ResolvedRunbook {
        let blueprint = makeBlueprint()
        let resolver = RunbookResolver()
        let values = defaultValues(for: blueprint)
        let plan = try! resolver.resolve(
            blueprint: blueprint,
            targetName: "DEV ORION",
            environment: .development,
            values: values,
            resolvedAt: capturedAt,
            isBundledReplay: true
        )
        let developerReview = try! RunbookLocalApproval(
            role: .developer,
            reviewerAlias: "R.DIAZ",
            planFingerprint: plan.planFingerprint,
            recordedAt: capturedAt.addingTimeInterval(-420)
        )
        return try! resolver.resolve(
            blueprint: blueprint,
            targetName: "DEV ORION",
            environment: .development,
            values: values,
            approvals: [developerReview],
            resolvedAt: capturedAt,
            isBundledReplay: true
        )
    }

    static func defaultValues(for blueprint: RunbookBlueprint) -> [RunbookParameterKey: String] {
        Dictionary(uniqueKeysWithValues: blueprint.parameters.compactMap { definition in
            definition.defaultValue.map { (definition.key, $0) }
        })
    }

    static func displayState(for step: ResolvedRunbookStep) -> RunbookDisplayStepState {
        switch step.number {
        case 1...4: .pass
        case 5: .review
        case 6: .waiting
        default: .pending
        }
    }

    static func makeBlueprint() -> RunbookBlueprint {
        let parameters = [
            parameter("TARGET_LIBRARY", "Target library", .systemName, defaultValue: "ARLIB"),
            parameter("SOURCE_FILE", "Source file", .systemName, defaultValue: "QRPGLESRC"),
            parameter("MEMBER", "Source member", .systemName, defaultValue: "ORDERENTRY"),
            parameter(
                "REPLACE_OBJECT",
                "Replace existing object",
                .choice,
                allowedValues: ["*NO", "*YES"],
                defaultValue: "*NO"
            )
        ]
        let steps = [
            step(
                1,
                .assertion,
                "Bind exact target",
                "Require DEV ORION and ARLIB; never resolve through *LIBL.",
                evidence: [evidence(.planFingerprint, "Canonical resolved plan")]
            ),
            step(
                2,
                .evidenceCapture,
                "Confirm source revision",
                "Retain the exact QRPGLESRC(ORDERENTRY) baseline before review.",
                evidence: [evidence(.sourceBaseline, "Exact source-member SHA-256")]
            ),
            step(
                3,
                .sqlRead,
                "Check object locks",
                "Collect a bounded exact-object lock receipt.",
                template: "SELECT OBJECT_NAME FROM TABLE(QSYS2.OBJECT_LOCK_INFO(OBJECT_SCHEMA => '{{TARGET_LIBRARY}}', OBJECT_NAME => '{{MEMBER}}')) X FETCH FIRST 100 ROWS ONLY",
                maximumRows: 100,
                timeoutSeconds: 30,
                evidence: [evidence(.queryReceipt, "Object-lock query receipt")]
            ),
            step(
                4,
                .sqlRead,
                "Confirm no inquiries",
                "Collect a bounded QSYSOPR inquiry receipt.",
                template: "SELECT MESSAGE_ID FROM QSYS2.MESSAGE_QUEUE_INFO WHERE MESSAGE_QUEUE_LIBRARY = 'QSYS' AND MESSAGE_QUEUE_NAME = 'QSYSOPR' FETCH FIRST 100 ROWS ONLY",
                maximumRows: 100,
                timeoutSeconds: 30,
                evidence: [evidence(.queryReceipt, "QSYSOPR inquiry receipt")]
            ),
            step(
                5,
                .clPreview,
                "Prepare compile",
                "Resolve one exact mutating command preview without submitting it.",
                template: "CRTBNDRPG PGM({{TARGET_LIBRARY}}/{{MEMBER}}) SRCFILE({{TARGET_LIBRARY}}/{{SOURCE_FILE}}) SRCMBR({{MEMBER}}) REPLACE({{REPLACE_OBJECT}})",
                evidence: [evidence(.commandPreview, "Exact resolved CL preview")]
            ),
            step(
                6,
                .approvalGate,
                "Two-person approval",
                "Require developer and operations local review attestations.",
                approvalRoles: [.developer, .operations]
            ),
            step(
                7,
                .evidenceCapture,
                "Capture compile evidence",
                "Require EVFEVENT records and the exact compile job log.",
                evidence: [
                    evidence(.eventFile, "EVFEVENT records"),
                    evidence(.jobLog, "Exact compile job log")
                ]
            ),
            step(
                8,
                .assertion,
                "Verify object signature",
                "Compare exact object identity and build evidence.",
                evidence: [evidence(.objectSignature, "Exact object build signature")]
            )
        ]
        return try! RunbookBlueprint(
            id: RunbookIdentifier(rawValue: selectedID),
            revision: 12,
            name: "Compile & verify ORDERENTRY",
            summary: "Resolve one bounded compile preview, require independent review, and declare exact post-action evidence.",
            ownerAlias: "R.DIAZ",
            allowedEnvironments: [.development, .qualityAssurance],
            mutationBudget: 1,
            parameters: parameters,
            steps: steps
        )
    }

    private static func parameter(
        _ key: String,
        _ label: String,
        _ kind: RunbookParameterKind,
        allowedValues: [String] = [],
        defaultValue: String? = nil
    ) -> RunbookParameterDefinition {
        try! RunbookParameterDefinition(
            key: RunbookParameterKey(rawValue: key),
            label: label,
            kind: kind,
            allowedValues: allowedValues,
            defaultValue: defaultValue
        )
    }

    private static func step(
        _ number: Int,
        _ kind: RunbookStepKind,
        _ title: String,
        _ detail: String,
        template: String? = nil,
        maximumRows: Int? = nil,
        timeoutSeconds: Int? = nil,
        approvalRoles: [RunbookApprovalRole] = [],
        evidence: [RunbookEvidenceRequirement] = []
    ) -> RunbookStep {
        try! RunbookStep(
            number: number,
            kind: kind,
            title: title,
            detail: detail,
            template: template,
            maximumRows: maximumRows,
            timeoutSeconds: timeoutSeconds,
            approvalRoles: approvalRoles,
            evidence: evidence
        )
    }

    private static func evidence(_ kind: RunbookEvidenceKind, _ label: String) -> RunbookEvidenceRequirement {
        try! RunbookEvidenceRequirement(kind: kind, label: label)
    }
}
