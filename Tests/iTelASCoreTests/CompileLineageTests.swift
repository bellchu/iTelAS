import XCTest
@testable import iTelASCore

final class CompileLineageTests: XCTestCase {
    func testComparisonBindsExactTargetAndClassifiesRegressionDeterministically() throws {
        let introduced = try diagnostic("RNF7030", severity: 30, line: 42)
        let baseline = try run(
            sequence: 183,
            outcome: .passed,
            objectResult: .changed,
            revisionSeed: "baseline"
        )
        let current = try run(
            sequence: 184,
            outcome: .failed,
            objectResult: .unchanged,
            revisionSeed: "current",
            diagnostics: [introduced]
        )

        let comparison = try CompileLineageComparison(
            runs: [baseline, current],
            baselineFingerprint: baseline.fingerprint,
            currentFingerprint: current.fingerprint
        )
        let reordered = try CompileLineageComparison(
            runs: [current, baseline],
            baselineFingerprint: baseline.fingerprint,
            currentFingerprint: current.fingerprint
        )

        XCTAssertEqual(comparison.trend, .regressionObserved)
        XCTAssertEqual(comparison.diagnostics.introduced, [introduced])
        XCTAssertTrue(comparison.diagnostics.resolved.isEmpty)
        XCTAssertTrue(comparison.diagnostics.persistent.isEmpty)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "target" })?.state, .exact)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "revision" })?.state, .changed)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "command" })?.state, .exact)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "release" })?.state, .exact)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "object" })?.state, .changed)
        XCTAssertEqual(comparison.fingerprint, reordered.fingerprint)
        XCTAssertEqual(comparison.runs.map(\.sequence), [184, 183])
    }

    func testDiagnosticDeltaUsesExactMessageSeverityAndLocationIdentity() throws {
        let resolved = try diagnostic("RNF1001", severity: 20, line: 7)
        let persistent = try diagnostic("RNF2002", severity: 30, line: 12)
        let introduced = try diagnostic("RNF3003", severity: 20, line: 18)
        let baseline = try run(
            sequence: 10,
            outcome: .failed,
            objectResult: .unchanged,
            revisionSeed: "same",
            diagnostics: [resolved, persistent]
        )
        let current = try run(
            sequence: 11,
            outcome: .failed,
            objectResult: .unchanged,
            revisionSeed: "same",
            diagnostics: [persistent, introduced, persistent]
        )

        let comparison = try CompileLineageComparison(
            runs: [baseline, current],
            baselineFingerprint: baseline.fingerprint,
            currentFingerprint: current.fingerprint
        )

        XCTAssertEqual(comparison.diagnostics.introduced, [introduced])
        XCTAssertEqual(comparison.diagnostics.resolved, [resolved])
        XCTAssertEqual(comparison.diagnostics.persistent, [persistent])
        XCTAssertEqual(comparison.trend, .outcomeStable)
        XCTAssertEqual(current.diagnostics.count, 2)
    }

    func testRelativeReleaseAndUnrecordedEvidenceStayVisible() throws {
        let baseline = try run(
            sequence: 1,
            outcome: .evidenceOnly,
            objectResult: .unrecorded,
            revisionSeed: nil,
            targetRelease: "*CURRENT",
            observedRelease: nil
        )
        let current = try run(
            sequence: 2,
            outcome: .failed,
            objectResult: .unchanged,
            revisionSeed: "current",
            targetRelease: "*CURRENT",
            observedRelease: nil,
            diagnostics: [try diagnostic("RNS9308", severity: 50, line: 0)]
        )

        let comparison = try CompileLineageComparison(
            runs: [baseline, current],
            baselineFingerprint: baseline.fingerprint,
            currentFingerprint: current.fingerprint
        )

        XCTAssertEqual(comparison.trend, .outcomeUnverified)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "release" })?.state, .relative)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "revision" })?.state, .unavailable)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "object" })?.state, .unavailable)
        XCTAssertTrue(comparison.assistContextText(maximumDiagnostics: 1).contains("not causal proof"))
        XCTAssertFalse(comparison.assistContextText(maximumDiagnostics: 1).contains("source body"))
    }

    func testComparisonRefusesScopeDuplicatesSelectionAndBounds() throws {
        let first = try run(
            sequence: 1,
            outcome: .passed,
            objectResult: .changed,
            revisionSeed: "one"
        )
        let otherTarget = try run(
            sequence: 2,
            objectIdentity: "ARLIB/OTHER · *PGM",
            outcome: .passed,
            objectResult: .changed,
            revisionSeed: "two"
        )

        XCTAssertThrowsError(try CompileLineageComparison(
            runs: [first, otherTarget],
            baselineFingerprint: first.fingerprint,
            currentFingerprint: otherTarget.fingerprint
        )) { error in
            guard case .targetScopeMismatch = error as? CompileLineageError else {
                return XCTFail("Expected exact-target refusal, received \(error)")
            }
        }
        XCTAssertThrowsError(try CompileLineageComparison(
            runs: [first, first],
            baselineFingerprint: first.fingerprint,
            currentFingerprint: otherTarget.fingerprint
        )) { error in
            XCTAssertEqual(error as? CompileLineageError, .duplicateRunFingerprint)
        }
        XCTAssertThrowsError(try CompileLineageComparison(
            runs: [first, otherTarget],
            baselineFingerprint: first.fingerprint,
            currentFingerprint: first.fingerprint
        )) { error in
            XCTAssertEqual(error as? CompileLineageError, .identicalSelection)
        }
        let bounded = CompileLineageLimits(maximumRuns: 2)
        let third = try run(
            sequence: 3,
            outcome: .passed,
            objectResult: .changed,
            revisionSeed: "three"
        )
        XCTAssertThrowsError(try CompileLineageComparison(
            runs: [first, third, try run(
                sequence: 4,
                outcome: .passed,
                objectResult: .changed,
                revisionSeed: "four"
            )],
            baselineFingerprint: first.fingerprint,
            currentFingerprint: third.fingerprint,
            limits: bounded
        )) { error in
            XCTAssertEqual(error as? CompileLineageError, .tooManyRuns(maximum: 2))
        }
    }

    private func diagnostic(
        _ messageID: String,
        severity: Int,
        line: Int
    ) throws -> CompileLineageDiagnosticIdentity {
        try CompileLineageDiagnosticIdentity(
            messageID: messageID,
            severity: severity,
            sourceIdentity: "ARLIB/QRPGLESRC(ORDERENTRY)",
            startLine: line,
            startColumn: line > 0 ? 5 : 0
        )
    }

    private func run(
        sequence: Int,
        objectIdentity: String = "ARLIB/ORDERENTRY · *PGM",
        outcome: CompileLineageOutcome,
        objectResult: CompileLineageObjectResult,
        revisionSeed: String?,
        targetRelease: String? = "*CURRENT",
        observedRelease: String? = "V7R6M0",
        diagnostics: [CompileLineageDiagnosticIdentity] = []
    ) throws -> CompileLineageRunEvidence {
        try CompileLineageRunEvidence(
            fingerprint: AIContentFingerprint.sha256("run-\(sequence)-\(objectIdentity)"),
            sequence: sequence,
            objectIdentity: objectIdentity,
            sourceIdentity: "ARLIB/QRPGLESRC(ORDERENTRY)",
            sourceRevision: revisionSeed.map(AIContentFingerprint.sha256),
            toolchainIdentity: "CRTBNDRPG",
            commandFingerprint: AIContentFingerprint.sha256("same-command"),
            eventEvidenceFingerprint: AIContentFingerprint.sha256("event-\(sequence)"),
            eventFileIdentity: "ARLIB/EVFEVENT(ORDERENTRY)",
            targetReleaseToken: targetRelease,
            observedHostRelease: observedRelease,
            jobIdentity: "847\(sequence)/DEVUSER/ITELASBLD",
            outcome: outcome,
            objectResult: objectResult,
            maximumSeverity: diagnostics.map(\.severity).max() ?? 0,
            diagnostics: diagnostics
        )
    }
}
