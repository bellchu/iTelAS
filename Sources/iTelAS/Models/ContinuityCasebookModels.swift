import Foundation
import iTelASCore

struct ContinuityReferenceReviewDraft: Identifiable, Equatable {
    let id = UUID()
    let sourceName: String
    let pack: ContinuityReferencePack
    var selectedEntryIDs: Set<UUID>

    init(sourceName: String, pack: ContinuityReferencePack) {
        self.sourceName = sourceName
        self.pack = pack
        selectedEntryIDs = Set(pack.entries.map(\.id))
    }
}

enum ContinuityCasebookSamples {
    static let selectedCaseID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    static func makeCasebook() -> ContinuityCasebook {
        let base = Date(timeIntervalSince1970: 1_784_980_860)
        let runbookEntry = try! ContinuityReferenceEntry(
            id: UUID(uuidString: "21111111-1111-4111-8111-111111111111")!,
            locator: "Runbook sections 2, 4, and 6",
            content: "Confirm the exact target. Refresh job and object-lock evidence. Record every unavailable source. Do not act from a stale lock sample.",
            kind: .runbook
        )
        let runbookPack = try! ContinuityReferencePack(
            kind: .runbook,
            title: "Queue wait triage",
            revision: "R-17",
            entries: [runbookEntry]
        )
        let runbook = try! runbookPack.reviewing(
            entryIDs: [runbookEntry.id],
            reviewedAt: base.addingTimeInterval(360)
        )
        let repositoryEntry = try! ContinuityReferenceEntry(
            id: UUID(uuidString: "31111111-1111-4111-8111-111111111111")!,
            locator: "orders/qrpglesrc/ARBATCH.rpgle",
            content: "dcl-pr RunSettlement extpgm('ARBATCH');\nend-pr;",
            kind: .repository
        )
        let repositoryPack = try! ContinuityReferencePack(
            kind: .repository,
            title: "orders/qrpglesrc snapshot",
            revision: "d9b4f1-local",
            entries: [repositoryEntry]
        )
        let repository = try! repositoryPack.reviewing(
            entryIDs: [repositoryEntry.id],
            reviewedAt: base.addingTimeInterval(420)
        )

        let activeArtifacts = [
            artifact(
                id: "41111111-1111-4111-8111-111111111111",
                kind: .operatorNote,
                title: "Case opened",
                summary: "Exact target DEV ORION",
                content: "ARBATCH remained waiting in QBATCH after nightly settlement.",
                receiptSeed: "case-opened",
                at: base
            ),
            artifact(
                id: "41111111-1111-4111-8111-111111111112",
                kind: .jobIncident,
                title: "Exact waiter and one holder candidate",
                summary: "23 jobs · 2 locks · 4 source receipts",
                content: "ARBATCH WAITING IN QBATCH\nQINTER CANDIDATE HOLDER FOR ARLIB/ORDERS",
                receiptSeed: "job-evidence",
                at: base.addingTimeInterval(180)
            ),
            artifact(
                id: "41111111-1111-4111-8111-111111111113",
                kind: .terminalScreen,
                title: "Queue status screen pinned redacted",
                summary: "24×80 · non-display fields removed",
                content: "QBATCH  ARBATCH  WAITING\nQINTER  ACTIVE",
                receiptSeed: "screen-evidence",
                at: base.addingTimeInterval(420),
                wasRedacted: true
            ),
            artifact(
                id: "41111111-1111-4111-8111-111111111114",
                kind: .operatorNote,
                title: "No hold, release, or reply attempted",
                summary: "Next shift should verify QINTER activity",
                content: "No host-changing action was attempted. Refresh evidence before deciding.",
                receiptSeed: "decision-note",
                at: base.addingTimeInterval(960)
            )
        ]
        let activeAnswers = [
            answer(
                id: "51111111-1111-4111-8111-111111111111",
                question: "Correlate this wait evidence and identify the smallest safe next check.",
                answer: "Correlate the exact holder candidate, then refresh the bounded job and lock samples before any operator action.",
                state: .complete,
                risk: .readOnly,
                contextSeed: "active-context",
                count: 3,
                at: base.addingTimeInterval(660)
            ),
            answer(
                id: "51111111-1111-4111-8111-111111111112",
                question: "Summarize the remaining uncertainty.",
                answer: "The sampled rows do not establish scheduler causality.",
                state: .stopped,
                risk: nil,
                contextSeed: "stopped-context",
                count: 2,
                at: base.addingTimeInterval(780)
            )
        ]
        let activeCase = try! ContinuityCase(
            id: selectedCaseID,
            code: "INC-0427",
            kind: .incident,
            title: "Why did ARBATCH remain queued after settlement?",
            target: "DEV ORION · JOBQ HOLD",
            environment: .development,
            summary: "Evidence explains the sampled wait without claiming scheduler causality.",
            artifacts: activeArtifacts,
            answers: activeAnswers,
            references: [runbook, repository],
            openQuestions: [
                "Is QBATCH max-active still one at the next sample?",
                "Does QINTER own the exact requested object then?"
            ],
            nextAction: "Refresh read-only job evidence.",
            staleBoundary: "Do not reuse the 20:44 lock sample as current state.",
            receiverAcknowledged: false,
            openedAt: base,
            updatedAt: base.addingTimeInterval(960)
        )

        let change = sampleCase(
            id: "11111111-1111-4111-8111-111111111112",
            code: "CHG-1182",
            kind: .change,
            phase: .handedOff,
            title: "ORDERSRV deployment evidence",
            target: "QA LUNAR",
            artifactTitle: "Reviewed object-impact artifact",
            artifactKind: .objectImpact,
            at: base.addingTimeInterval(-7_200),
            acknowledged: true
        )
        let build = sampleCase(
            id: "11111111-1111-4111-8111-111111111113",
            code: "BLD-0934",
            kind: .build,
            phase: .draft,
            title: "ARINQRY compile diagnostics",
            target: "DEV ORION",
            artifactTitle: "Imported EVFEVENT evidence",
            artifactKind: .compileEvidence,
            at: base.addingTimeInterval(-86_400),
            acknowledged: false
        )
        let transfer = sampleCase(
            id: "11111111-1111-4111-8111-111111111114",
            code: "XFR-0208",
            kind: .transfer,
            phase: .draft,
            title: "CUSTOMER mapping blockers",
            target: "QA LUNAR",
            artifactTitle: "CSV schema dry-run artifact",
            artifactKind: .dataTransfer,
            at: base.addingTimeInterval(-259_200),
            acknowledged: false
        )
        return try! ContinuityCasebook(cases: [activeCase, change, build, transfer])
    }

    private static func artifact(
        id: String,
        kind: ContinuityArtifactKind,
        title: String,
        summary: String,
        content: String,
        receiptSeed: String,
        at: Date,
        wasRedacted: Bool = false
    ) -> ContinuityArtifact {
        try! ContinuityArtifact(
            id: UUID(uuidString: id)!,
            kind: kind,
            title: title,
            summary: summary,
            content: content,
            sourceReceipt: AIContentFingerprint.sha256(receiptSeed),
            wasRedacted: wasRedacted,
            createdAt: at
        )
    }

    private static func answer(
        id: String,
        question: String,
        answer: String,
        state: ContinuityAnswerState,
        risk: CommandRisk?,
        contextSeed: String,
        count: Int,
        at: Date
    ) -> ContinuityAssistAnswer {
        try! ContinuityAssistAnswer(
            id: UUID(uuidString: id)!,
            question: question,
            answer: answer,
            state: state,
            commandRisk: risk,
            contextFingerprint: AIContentFingerprint.sha256(contextSeed),
            contextItemCount: count,
            endpointHost: "provider.example",
            model: "configured-model",
            createdAt: at
        )
    }

    private static func sampleCase(
        id: String,
        code: String,
        kind: ContinuityCaseKind,
        phase: ContinuityCasePhase,
        title: String,
        target: String,
        artifactTitle: String,
        artifactKind: ContinuityArtifactKind,
        at: Date,
        acknowledged: Bool
    ) -> ContinuityCase {
        let artifact = try! ContinuityArtifact(
            kind: artifactKind,
            title: artifactTitle,
            summary: "Deterministic local replay evidence",
            content: "This bounded local replay stands in for host-qualified evidence.",
            sourceReceipt: AIContentFingerprint.sha256(code),
            wasRedacted: false,
            createdAt: at
        )
        return try! ContinuityCase(
            id: UUID(uuidString: id)!,
            code: code,
            kind: kind,
            phase: phase,
            title: title,
            target: target,
            environment: target.hasPrefix("QA") ? .qualityAssurance : .development,
            summary: "A bounded local continuity example.",
            artifacts: [artifact],
            openQuestions: acknowledged ? [] : ["Refresh the relevant evidence before relying on this case."],
            nextAction: "Review the exact local artifact.",
            staleBoundary: "The bundled replay is not current host state.",
            receiverAcknowledged: acknowledged,
            openedAt: at,
            updatedAt: at
        )
    }
}
