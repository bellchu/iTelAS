import XCTest
@testable import iTelASCore

final class ContinuityCasebookTests: XCTestCase {
    func testCaseCollectsArtifactsAnswersReferencesAndCreatesImmutableSnapshot() throws {
        let openedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let artifact = try makeArtifact(createdAt: openedAt)
        let answer = try ContinuityAssistAnswer(
            question: "What evidence should the next operator refresh?",
            answer: "Refresh the bounded job inventory and exact object-lock sample before acting.",
            state: .complete,
            commandRisk: .readOnly,
            contextFingerprint: AIContentFingerprint.sha256("context"),
            contextItemCount: 2,
            endpointHost: "api.example.test",
            model: "test-model",
            createdAt: openedAt.addingTimeInterval(60)
        )
        let entry = try ContinuityReferenceEntry(
            locator: "runbook section 4",
            content: "Refresh read-only evidence and retain the new receipt.",
            kind: .runbook
        )
        let pack = try ContinuityReferencePack(
            kind: .runbook,
            title: "Queue wait triage",
            revision: "R-17",
            entries: [entry]
        )
        let reference = try pack.reviewing(entryIDs: [entry.id], reviewedAt: openedAt)
        var continuityCase = try makeCase(openedAt: openedAt)
        continuityCase = try continuityCase.adding(artifacts: [artifact], at: openedAt)
        continuityCase = try continuityCase.adding(answer: answer, at: openedAt)
        continuityCase = try continuityCase.adding(reference: reference, at: openedAt)

        let casebook = try ContinuityCasebook(cases: [continuityCase])
        let result = try casebook.snapshotting(
            caseID: continuityCase.id,
            at: openedAt.addingTimeInterval(120)
        )

        XCTAssertEqual(result.snapshot.caseRecord.artifacts, [artifact])
        XCTAssertEqual(result.snapshot.caseRecord.answers, [answer])
        XCTAssertEqual(result.snapshot.caseRecord.references, [reference])
        XCTAssertEqual(result.snapshot.readinessGaps, ["receiverAcknowledgement"])
        XCTAssertEqual(result.casebook.snapshots, [result.snapshot])

        let updated = try continuityCase.updatingWorkflow(
            nextAction: "A different later action",
            at: openedAt.addingTimeInterval(180)
        )
        XCTAssertNotEqual(updated.fingerprint, result.snapshot.caseRecord.fingerprint)
        XCTAssertEqual(
            result.snapshot.caseRecord.nextAction,
            "Refresh read-only job and object-lock evidence."
        )
    }

    func testDuplicateBoundsAndIncompleteAnswerStateFailClosed() throws {
        let artifact = try makeArtifact()
        var continuityCase = try makeCase()
        continuityCase = try continuityCase.adding(artifacts: [artifact])
        XCTAssertThrowsError(try continuityCase.adding(artifacts: [artifact])) { error in
            XCTAssertEqual(error as? ContinuityCasebookError, .duplicateArtifact)
        }

        XCTAssertThrowsError(
            try ContinuityAssistAnswer(
                question: "Should this partial answer be trusted?",
                answer: "Partial provider output",
                state: .stopped,
                commandRisk: .readOnly,
                contextFingerprint: nil,
                contextItemCount: 0,
                endpointHost: "api.example.test",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? ContinuityCasebookError, .incompatibleAnswerState)
        }

        let strict = ContinuityCasebookLimits(maximumArtifactsPerCase: 1)
        let second = try ContinuityArtifact(
            kind: .operatorNote,
            title: "Decision note",
            summary: "No action attempted",
            content: "The operator did not hold, release, reply, or end a job.",
            sourceReceipt: AIContentFingerprint.sha256("decision"),
            wasRedacted: false
        )
        XCTAssertThrowsError(try continuityCase.adding(artifacts: [second], limits: strict)) { error in
            XCTAssertEqual(
                error as? ContinuityCasebookError,
                .limitExceeded("artifacts", maximum: 1)
            )
        }
    }

    func testReferencePackCodecRequiresSafeReviewedSelection() throws {
        let json = """
        {
          "version": 1,
          "kind": "repository",
          "title": "Order service review snapshot",
          "revision": "commit-8b917c",
          "entries": [
            {"locator":"src/ORDERS.rpgle","content":"ctl-opt option(*srcstmt);"},
            {"locator":"src/ORDERH.dspf","content":"A          R ORDERFMT"}
          ]
        }
        """
        let pack = try ContinuityReferencePackCodec().decode(Data(json.utf8))
        XCTAssertEqual(pack.entries.count, 2)
        XCTAssertThrowsError(try pack.reviewing(entryIDs: [])) { error in
            XCTAssertEqual(error as? ContinuityCasebookError, .noReferenceSelection)
        }
        let reviewed = try pack.reviewing(entryIDs: [pack.entries[1].id])
        XCTAssertEqual(reviewed.entries.map(\.locator), ["src/ORDERH.dspf"])
        XCTAssertEqual(reviewed.sourcePackFingerprint, pack.fingerprint)

        let traversal = json.replacingOccurrences(
            of: "src/ORDERS.rpgle",
            with: "../ORDERS.rpgle"
        )
        XCTAssertThrowsError(try ContinuityReferencePackCodec().decode(Data(traversal.utf8))) { error in
            XCTAssertEqual(error as? ContinuityCasebookError, .invalidReferenceLocator)
        }
    }

    func testRoundTripValidationDetectsTamperedArtifactContent() throws {
        let artifact = try makeArtifact()
        let continuityCase = try makeCase().adding(artifacts: [artifact])
        let casebook = try ContinuityCasebook(cases: [continuityCase])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(casebook)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(ContinuityCasebook.self, from: data)
        XCTAssertNoThrow(try decoded.validate())

        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let tampered = text.replacingOccurrences(of: "QBATCH", with: "QINTER")
        let tamperedBook = try decoder.decode(
            ContinuityCasebook.self,
            from: Data(tampered.utf8)
        )
        XCTAssertThrowsError(try tamperedBook.validate()) { error in
            XCTAssertEqual(error as? ContinuityCasebookError, .invalidFingerprint)
        }
    }

    func testContextFragmentBecomesExactRedactedArtifact() throws {
        let fragment = try AIContextFragment(
            kind: .jobIncident,
            documentName: "INC-0427-job.txt",
            language: "IBM i incident evidence",
            sourceText: "JOB ARBATCH WAITING\nPASSWORD: should-not-leave\nLOCK ARLIB/ORDERS"
        )
        let artifact = try ContinuityArtifact(fragment: fragment)
        XCTAssertEqual(artifact.kind, .jobIncident)
        XCTAssertEqual(artifact.content, fragment.content)
        XCTAssertTrue(artifact.wasRedacted)
        XCTAssertFalse(artifact.content.contains("should-not-leave"))
        XCTAssertEqual(artifact.sourceReceipt, fragment.contentSHA256)
        XCTAssertNoThrow(try artifact.validate())
    }

    private func makeArtifact(createdAt: Date = Date()) throws -> ContinuityArtifact {
        try ContinuityArtifact(
            kind: .jobIncident,
            title: "INC-0427 job evidence",
            summary: "Exact waiter and one holder candidate",
            content: "ARBATCH WAITING IN QBATCH\nARHOLDER CANDIDATE FOR ARLIB/ORDERS",
            sourceReceipt: AIContentFingerprint.sha256("job-receipt"),
            wasRedacted: false,
            createdAt: createdAt
        )
    }

    private func makeCase(openedAt: Date = Date()) throws -> ContinuityCase {
        try ContinuityCase(
            code: "INC-0427",
            kind: .incident,
            title: "ARBATCH remained queued after settlement",
            target: "DEV ORION",
            environment: .development,
            summary: "Explain the observed wait without claiming scheduler causality.",
            openQuestions: ["Is QBATCH max-active still one at the next sample?"],
            nextAction: "Refresh read-only job and object-lock evidence.",
            staleBoundary: "Do not reuse the 20:44 lock sample as current state.",
            openedAt: openedAt,
            updatedAt: openedAt
        )
    }
}
