import Foundation
import XCTest
@testable import iTelASCore

final class RunbookTests: XCTestCase {
    func testParameterKeysNormalizeAndRejectCredentialSurfaces() throws {
        XCTAssertEqual(try RunbookParameterKey(rawValue: "target_library").rawValue, "TARGET_LIBRARY")
        XCTAssertThrowsError(try RunbookParameterKey(rawValue: "1TARGET"))
        XCTAssertThrowsError(try RunbookParameterKey(rawValue: "API_TOKEN")) { error in
            XCTAssertEqual(error as? RunbookError, .sensitiveParameter("API_TOKEN"))
        }
        XCTAssertThrowsError(try RunbookParameterKey(rawValue: "db_password"))
    }

    func testParameterTypesNormalizeExactValuesAndRejectInjection() throws {
        let systemName = try definition("TARGET_LIBRARY", .systemName)
        XCTAssertEqual(try systemName.normalized("arlib"), "ARLIB")
        XCTAssertThrowsError(try systemName.normalized("ARLIB) DLTLIB(QTEMP"))

        let choice = try definition("REPLACE_OBJECT", .choice, allowedValues: ["*NO", "*YES"])
        XCTAssertEqual(try choice.normalized("*no"), "*NO")
        XCTAssertThrowsError(try choice.normalized("*NO); DLTLIB X"))

        let integer = try definition("ROW_LIMIT", .positiveInteger)
        XCTAssertEqual(try integer.normalized("100"), "100")
        XCTAssertThrowsError(try integer.normalized("0100"))
        XCTAssertThrowsError(try integer.normalized("0"))

        let freeText = try definition("CHANGE_NOTE", .text)
        XCTAssertThrowsError(try freeText.normalized("reviewed\nExecutable: YES"))
    }

    func testBlueprintRejectsDuplicateNoncontiguousUnknownAndFreeTextPlaceholders() throws {
        let first = try definition("TARGET_LIBRARY", .systemName)
        XCTAssertThrowsError(try blueprint(parameters: [first, first])) { error in
            XCTAssertEqual(error as? RunbookError, .duplicateParameter("TARGET_LIBRARY"))
        }

        var steps = try validSteps()
        steps[1] = try RunbookStep(number: 9, kind: .operatorNote, title: "Gap", detail: "Invalid sequence")
        XCTAssertThrowsError(try blueprint(steps: steps))

        let unknown = try RunbookStep(
            number: 1,
            kind: .clPreview,
            title: "Unknown value",
            detail: "Must fail",
            template: "DSPJOB JOB({{MISSING}})"
        )
        XCTAssertThrowsError(try blueprint(steps: [unknown])) { error in
            XCTAssertEqual(error as? RunbookError, .unknownPlaceholder(step: 1, key: "MISSING"))
        }

        let note = try definition("CHANGE_NOTE", .text)
        let unsafe = try RunbookStep(
            number: 1,
            kind: .clPreview,
            title: "Unsafe interpolation",
            detail: "Free text cannot enter an action",
            template: "DSPJOB JOB({{CHANGE_NOTE}})"
        )
        XCTAssertThrowsError(try blueprint(parameters: [note], steps: [unsafe])) { error in
            XCTAssertEqual(error as? RunbookError, .unsafeInterpolation(step: 1, key: "CHANGE_NOTE"))
        }

        let byteBoundedLimits = RunbookLimits(
            maximumDocumentBytes: 131_072,
            maximumSteps: 32,
            maximumParameters: 24,
            maximumTemplateBytes: 5,
            maximumTextCharacters: 512
        )
        XCTAssertThrowsError(try RunbookStep(
            number: 1,
            kind: .clPreview,
            title: "Byte cap",
            detail: "UTF-8 bytes, not scalar count",
            template: "ééé",
            limits: byteBoundedLimits
        ))
    }

    func testResolutionIsDeterministicTypedAndNeverExecutable() throws {
        let blueprint = try blueprint()
        let first = try resolve(blueprint)
        let second = try resolve(blueprint)

        XCTAssertEqual(first.planFingerprint, second.planFingerprint)
        XCTAssertEqual(first.steps.count, 8)
        XCTAssertEqual(first.steps[2].risk, .readOnly)
        XCTAssertTrue(first.steps[2].resolvedAction?.contains("'ARLIB'") == true)
        XCTAssertEqual(first.steps[4].risk, .mutating)
        XCTAssertEqual(first.steps[4].resolvedAction, "CRTBNDRPG PGM(ARLIB/ORDERENTRY) SRCFILE(ARLIB/QRPGLESRC) SRCMBR(ORDERENTRY) REPLACE(*NO)")
        XCTAssertEqual(first.assessment.mutatingStepCount, 1)
        XCTAssertEqual(first.assessment.verdict, "REVIEW REQUIRED")
        XCTAssertFalse(first.assessment.isExecutable)
        XCTAssertTrue(first.assessment.issueCodes.contains("EXECUTION_CONNECTOR_UNAVAILABLE"))
    }

    func testSQLStepRejectsMutationEvenWhenDeclaredAsRead() throws {
        let step = try RunbookStep(
            number: 1,
            kind: .sqlRead,
            title: "Forged read",
            detail: "Must remain blocked",
            template: "DELETE FROM {{TARGET_LIBRARY}}/ORDERS",
            maximumRows: 10,
            timeoutSeconds: 5
        )
        let blueprint = try blueprint(steps: [step], mutationBudget: 0)
        XCTAssertThrowsError(try resolve(blueprint)) { error in
            XCTAssertEqual(error as? RunbookError, .unsafeSQL(step: 1))
        }
    }

    func testCLPreviewRejectsCommandSeparatorsAndHonorsMutationBudget() throws {
        let separated = try RunbookStep(
            number: 1,
            kind: .clPreview,
            title: "Separated command",
            detail: "Must remain blocked",
            template: "DSPJOB JOB({{MEMBER}}); DLTLIB LIB(QTEMP)"
        )
        XCTAssertThrowsError(try resolve(try blueprint(steps: [separated], mutationBudget: 1))) { error in
            XCTAssertEqual(error as? RunbookError, .unsafeCL(step: 1))
        }

        XCTAssertThrowsError(try resolve(try blueprint(mutationBudget: 0))) { error in
            XCTAssertEqual(error as? RunbookError, .mutationBudgetExceeded(maximum: 0, actual: 1))
        }
    }

    func testApprovalsArePlanBoundLocalAttestationsAndCannotUnlockExecution() throws {
        let blueprint = try blueprint()
        let plan = try resolve(blueprint)
        let developer = try RunbookLocalApproval(
            role: .developer,
            reviewerAlias: "R.DIAZ",
            planFingerprint: plan.planFingerprint,
            recordedAt: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertFalse(developer.identityWasCryptographicallyVerified)

        let wrong = try RunbookLocalApproval(
            role: .operations,
            reviewerAlias: "M.CHEN",
            planFingerprint: String(repeating: "0", count: 64),
            recordedAt: Date(timeIntervalSince1970: 1_010)
        )
        XCTAssertThrowsError(try resolve(blueprint, approvals: [developer, wrong])) { error in
            XCTAssertEqual(error as? RunbookError, .approvalPlanMismatch("OPERATIONS"))
        }

        let operations = try RunbookLocalApproval(
            role: .operations,
            reviewerAlias: "M.CHEN",
            planFingerprint: plan.planFingerprint,
            recordedAt: Date(timeIntervalSince1970: 1_010)
        )
        let reviewed = try resolve(
            blueprint,
            operatorReason: "Reviewed change ticket CHG-41.",
            approvals: [developer, operations]
        )
        XCTAssertTrue(reviewed.assessment.missingApprovalRoles.isEmpty)
        XCTAssertFalse(reviewed.assessment.isExecutable)
        XCTAssertEqual(reviewed.assessment.checks.first(where: { $0.kind == .executionConnector })?.state, .blocked)

        var alteredSteps = try validSteps()
        alteredSteps[0] = try RunbookStep(
            number: 1,
            kind: .assertion,
            title: "Bind exact target",
            detail: "A materially changed precondition under the same imported revision.",
            evidence: [try evidence(.planFingerprint, "Canonical resolved plan")]
        )
        let alteredBlueprint = try self.blueprint(steps: alteredSteps)
        XCTAssertNotEqual(try resolve(alteredBlueprint).planFingerprint, plan.planFingerprint)
        XCTAssertThrowsError(try resolve(alteredBlueprint, approvals: [developer]))
    }

    func testDestructiveAndUnknownPreviewsRemainBlocked() throws {
        let destructive = try RunbookStep(
            number: 1,
            kind: .clPreview,
            title: "Delete library preview",
            detail: "Local classification only",
            template: "DLTLIB LIB({{TARGET_LIBRARY}})",
            evidence: [try evidence(.commandPreview, "Exact destructive preview")]
        )
        let destructiveRun = try resolve(try blueprint(steps: [destructive], mutationBudget: 1))
        XCTAssertEqual(destructiveRun.steps[0].risk, .destructive)
        XCTAssertTrue(destructiveRun.assessment.issueCodes.contains("DESTRUCTIVE_PREVIEW_BLOCKED"))

        let unknown = try RunbookStep(
            number: 1,
            kind: .clPreview,
            title: "Unknown command preview",
            detail: "Local classification only",
            template: "XUNKNOWN VALUE({{TARGET_LIBRARY}})"
        )
        let unknownRun = try resolve(try blueprint(steps: [unknown], mutationBudget: 0))
        XCTAssertEqual(unknownRun.steps[0].risk, .unknown)
        XCTAssertTrue(unknownRun.assessment.issueCodes.contains("UNKNOWN_ACTION_BLOCKED"))
    }

    func testArtifactIncludesExactPreviewAndExplicitLimitations() throws {
        let runbook = try resolve(
            try blueprint(),
            operatorReason: "Reviewed change ticket CHG-41."
        )
        let artifact = RunbookArtifactBuilder().build(runbook)

        XCTAssertTrue(artifact.contains("COMPILE_VERIFY revision 12"))
        XCTAssertTrue(artifact.contains("CRTBNDRPG PGM(ARLIB/ORDERENTRY)"))
        XCTAssertTrue(artifact.contains("EXECUTION_CONNECTOR_UNAVAILABLE"))
        XCTAssertTrue(artifact.contains("Operator reason: Reviewed change ticket CHG-41."))
        XCTAssertTrue(artifact.contains("No host action"))
        XCTAssertTrue(artifact.contains("not authenticated signatures"))
        XCTAssertFalse(artifact.contains("Executable: YES"))
    }

    func testAssistContextWithholdsIdentitiesValuesCommandsActorsAndFingerprints() throws {
        let blueprint = try blueprint()
        let base = try resolve(blueprint, targetName: "PRIVATE-ORION")
        let approval = try RunbookLocalApproval(
            role: .developer,
            reviewerAlias: "PRIVATE-ACTOR",
            planFingerprint: base.planFingerprint,
            recordedAt: Date(timeIntervalSince1970: 1_000)
        )
        let runbook = try resolve(blueprint, targetName: "PRIVATE-ORION", approvals: [approval])
        let context = RunbookAssistContextBuilder().build(runbook)

        for withheld in ["PRIVATE-ORION", "ARLIB", "ORDERENTRY", "CRTBNDRPG", "R.DIAZ", "PRIVATE-ACTOR", runbook.planFingerprint] {
            XCTAssertFalse(context.contains(withheld))
        }
        XCTAssertTrue(context.contains("STEP-005: CL REVIEW · risk MUTATING"))
        XCTAssertTrue(context.contains("APPROVAL_MISSING"))
        XCTAssertTrue(context.contains("Advice only"))
        XCTAssertEqual(AIContextKind.runbook.label, "Runbook review")
        XCTAssertFalse(AIContextKind.runbook.requiresSelection)
    }

    func testCodecRoundTripsValidatedBlueprintAndEnforcesBounds() throws {
        let blueprint = try blueprint()
        let codec = RunbookBlueprintCodec()
        let data = try codec.encode(blueprint)
        XCTAssertEqual(try codec.decode(data), blueprint)
        XCTAssertThrowsError(try codec.decode(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? RunbookError, .malformedDocument)
        }

        let tiny = RunbookBlueprintCodec(limits: .init(
            maximumDocumentBytes: 10,
            maximumSteps: 32,
            maximumParameters: 24,
            maximumTemplateBytes: 4_096,
            maximumTextCharacters: 512
        ))
        XCTAssertThrowsError(try tiny.decode(Data(repeating: 65, count: 11))) { error in
            XCTAssertEqual(error as? RunbookError, .inputTooLarge(maximum: 10))
        }
    }

    private func resolve(
        _ blueprint: RunbookBlueprint,
        targetName: String = "DEV ORION",
        operatorReason: String? = nil,
        approvals: [RunbookLocalApproval] = []
    ) throws -> ResolvedRunbook {
        try RunbookResolver().resolve(
            blueprint: blueprint,
            targetName: targetName,
            environment: .development,
            values: values,
            operatorReason: operatorReason,
            approvals: approvals,
            resolvedAt: Date(timeIntervalSince1970: 1_785_164_812),
            isBundledReplay: true
        )
    }

    private func blueprint(
        parameters: [RunbookParameterDefinition]? = nil,
        steps: [RunbookStep]? = nil,
        mutationBudget: Int = 1
    ) throws -> RunbookBlueprint {
        try RunbookBlueprint(
            id: RunbookIdentifier(rawValue: "COMPILE_VERIFY"),
            revision: 12,
            name: "Compile and verify ORDERENTRY",
            summary: "Resolve one bounded compile preview, require review, and declare exact post-action evidence.",
            ownerAlias: "R.DIAZ",
            allowedEnvironments: [.development, .qualityAssurance],
            mutationBudget: mutationBudget,
            parameters: try parameters ?? validParameters(),
            steps: try steps ?? validSteps()
        )
    }

    private func validParameters() throws -> [RunbookParameterDefinition] {
        [
            try definition("TARGET_LIBRARY", .systemName, defaultValue: "ARLIB"),
            try definition("SOURCE_FILE", .systemName, defaultValue: "QRPGLESRC"),
            try definition("MEMBER", .systemName, defaultValue: "ORDERENTRY"),
            try definition("REPLACE_OBJECT", .choice, allowedValues: ["*NO", "*YES"], defaultValue: "*NO")
        ]
    }

    private var values: [RunbookParameterKey: String] {
        [
            try! RunbookParameterKey(rawValue: "TARGET_LIBRARY"): "ARLIB",
            try! RunbookParameterKey(rawValue: "SOURCE_FILE"): "QRPGLESRC",
            try! RunbookParameterKey(rawValue: "MEMBER"): "ORDERENTRY",
            try! RunbookParameterKey(rawValue: "REPLACE_OBJECT"): "*NO"
        ]
    }

    private func validSteps() throws -> [RunbookStep] {
        [
            try RunbookStep(
                number: 1,
                kind: .assertion,
                title: "Bind exact target",
                detail: "Require DEV ORION and exact library identity.",
                evidence: [try evidence(.planFingerprint, "Canonical resolved plan")]
            ),
            try RunbookStep(
                number: 2,
                kind: .evidenceCapture,
                title: "Confirm source revision",
                detail: "Retain the exact member baseline before review.",
                evidence: [try evidence(.sourceBaseline, "Exact source member SHA-256")]
            ),
            try RunbookStep(
                number: 3,
                kind: .sqlRead,
                title: "Check object locks",
                detail: "Collect bounded lock evidence for the exact target.",
                template: "SELECT OBJECT_NAME FROM TABLE(QSYS2.OBJECT_LOCK_INFO(OBJECT_SCHEMA => '{{TARGET_LIBRARY}}', OBJECT_NAME => '{{MEMBER}}')) X FETCH FIRST 100 ROWS ONLY",
                maximumRows: 100,
                timeoutSeconds: 30,
                evidence: [try evidence(.queryReceipt, "Object-lock query receipt")]
            ),
            try RunbookStep(
                number: 4,
                kind: .sqlRead,
                title: "Confirm no inquiries",
                detail: "Collect bounded QSYSOPR inquiry evidence.",
                template: "SELECT MESSAGE_ID FROM QSYS2.MESSAGE_QUEUE_INFO WHERE MESSAGE_QUEUE_LIBRARY = 'QSYS' AND MESSAGE_QUEUE_NAME = 'QSYSOPR' FETCH FIRST 100 ROWS ONLY",
                maximumRows: 100,
                timeoutSeconds: 30,
                evidence: [try evidence(.queryReceipt, "QSYSOPR inquiry receipt")]
            ),
            try RunbookStep(
                number: 5,
                kind: .clPreview,
                title: "Prepare compile",
                detail: "Resolve the exact command without submitting it.",
                template: "CRTBNDRPG PGM({{TARGET_LIBRARY}}/{{MEMBER}}) SRCFILE({{TARGET_LIBRARY}}/{{SOURCE_FILE}}) SRCMBR({{MEMBER}}) REPLACE({{REPLACE_OBJECT}})",
                evidence: [try evidence(.commandPreview, "Exact resolved CL preview")]
            ),
            try RunbookStep(
                number: 6,
                kind: .approvalGate,
                title: "Two-person approval",
                detail: "Require developer and operations local review records.",
                approvalRoles: [.developer, .operations]
            ),
            try RunbookStep(
                number: 7,
                kind: .evidenceCapture,
                title: "Capture compile evidence",
                detail: "Require compiler event and exact job-log evidence.",
                evidence: [
                    try evidence(.eventFile, "EVFEVENT records"),
                    try evidence(.jobLog, "Exact compile job log")
                ]
            ),
            try RunbookStep(
                number: 8,
                kind: .assertion,
                title: "Verify object signature",
                detail: "Compare exact object identity and build evidence.",
                evidence: [try evidence(.objectSignature, "Exact object build signature")]
            )
        ]
    }

    private func definition(
        _ key: String,
        _ kind: RunbookParameterKind,
        allowedValues: [String] = [],
        defaultValue: String? = nil
    ) throws -> RunbookParameterDefinition {
        try RunbookParameterDefinition(
            key: RunbookParameterKey(rawValue: key),
            label: key.replacingOccurrences(of: "_", with: " ").capitalized,
            kind: kind,
            allowedValues: allowedValues,
            defaultValue: defaultValue
        )
    }

    private func evidence(_ kind: RunbookEvidenceKind, _ label: String) throws -> RunbookEvidenceRequirement {
        try RunbookEvidenceRequirement(kind: kind, label: label)
    }
}
