import Foundation
import XCTest
@testable import iTelASCore

final class TerminalFlightRecorderTests: XCTestCase {
    func testEvidenceFrameClearsEveryInputFieldNonDisplayCellAndSensitiveRow() throws {
        let profileID = UUID()
        var screen = TerminalScreen(rows: 24, columns: 80)
        screen.inputInhibited = false
        let output = TerminalAttributes(foreground: .green, protected: true)
        let input = TerminalAttributes(foreground: .white, protected: false)
        let hidden = TerminalAttributes(foreground: .white, nonDisplay: true, protected: false)
        screen.write("CUSTOMER 48371", row: 2, column: 2, attributes: output)
        screen.write("VISIBLE-INPUT", row: 8, column: 12, attributes: input)
        screen.fields.append(TerminalField(start: 8 * 80 + 12, length: 18, isProtected: false))
        screen.write("HIDDEN-PASSWORD", row: 10, column: 12, attributes: hidden)
        screen.fields.append(TerminalField(
            start: 10 * 80 + 12,
            length: 18,
            isProtected: false,
            isNonDisplay: true
        ))
        screen.write("PASSWORD: HOST-SECRET", row: 14, column: 2, attributes: output)

        let frame = TerminalEvidenceFrame(
            profileID: profileID,
            profileName: "DEV",
            screen: screen
        )

        try frame.validate()
        XCTAssertTrue(frame.visibleText.contains("CUSTOMER 48371"))
        XCTAssertFalse(frame.visibleText.contains("VISIBLE-INPUT"))
        XCTAssertFalse(frame.visibleText.contains("HIDDEN-PASSWORD"))
        XCTAssertFalse(frame.visibleText.contains("HOST-SECRET"))
        XCTAssertEqual(frame.clearedInputFieldCount, 2)
        XCTAssertEqual(frame.clearedSensitiveRowCount, 1)
        XCTAssertTrue(frame.cells.allSatisfy { $0.attributes.protected && !$0.attributes.nonDisplay })
        XCTAssertTrue(frame.previewScreen.fields.isEmpty)
        XCTAssertTrue(frame.previewScreen.inputInhibited)
    }

    func testArchiveDeduplicatesNewestFramePrunesRetentionAndEnforcesBound() throws {
        let profileID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = makeFrame(
            profileID: profileID,
            title: "OLD",
            capturedAt: now.addingTimeInterval(-8 * 86_400)
        )
        let current = makeFrame(profileID: profileID, title: "CURRENT", capturedAt: now)
        let next = makeFrame(profileID: profileID, title: "NEXT", capturedAt: now.addingTimeInterval(1))
        let last = makeFrame(profileID: profileID, title: "LAST", capturedAt: now.addingTimeInterval(2))
        var archive = TerminalFlightRecorderArchive(
            policy: TerminalHistoryPolicy(retention: .sevenDays, maximumFrames: 2),
            frames: [old]
        )

        XCTAssertTrue(try archive.append(current, at: now))
        XCTAssertFalse(try archive.append(current, at: now))
        XCTAssertTrue(try archive.append(next, at: now))
        XCTAssertTrue(try archive.append(last, at: now))

        XCTAssertEqual(archive.frames.map(\.title), ["NEXT", "LAST"])
        try archive.validate()
    }

    func testMacroReviewFreezesExactContentAndAnyEditMakesItStale() throws {
        let frame = makeFrame(profileID: UUID(), title: "COMMAND ENTRY")
        var macro = ReviewedTerminalMacro(
            name: "Inspect batch",
            steps: [
                ReviewedTerminalMacroStep(
                    name: "Match baseline",
                    action: .matchFrame(fingerprint: frame.screenFingerprint)
                ),
                ReviewedTerminalMacroStep(
                    name: "Stage command",
                    action: .stageReadOnlyCommand("WRKACTJOB SBS(QBATCH)")
                ),
                ReviewedTerminalMacroStep(
                    name: "Send Enter",
                    action: .sendAID(TN5250AID.enter.rawValue)
                )
            ]
        )

        try macro.attestReview(by: "OPERATOR A", at: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(macro.isReviewCurrent)
        let reviewedFingerprint = macro.reviewFingerprint

        macro.steps[1].action = .stageReadOnlyCommand("WRKACTJOB SBS(QINTER)")

        XCTAssertFalse(macro.isReviewCurrent)
        XCTAssertEqual(reviewedFingerprint?.count, 64)
        XCTAssertThrowsError(try macro.validate()) { error in
            XCTAssertEqual(error as? TerminalFlightRecorderError, .staleMacroReview)
        }
    }

    func testMacroRejectsSecretsUnsupportedAIDsAndUnboundedRoutes() throws {
        let secret = ReviewedTerminalMacro(
            name: "Unsafe",
            steps: [ReviewedTerminalMacroStep(
                name: "Secret",
                action: .stageReadOnlyCommand("CHGUSRPRF PASSWORD=HIDDEN")
            )]
        )
        XCTAssertThrowsError(try secret.validate()) { error in
            XCTAssertEqual(error as? TerminalFlightRecorderError, .commandMayContainSecret)
        }

        let unsupported = ReviewedTerminalMacro(
            name: "Unsupported",
            steps: [ReviewedTerminalMacroStep(name: "Unknown", action: .sendAID(0x00))]
        )
        XCTAssertThrowsError(try unsupported.validate()) { error in
            XCTAssertEqual(error as? TerminalFlightRecorderError, .invalidMacroStep)
        }

        let oversized = ReviewedTerminalMacro(
            name: "Too many",
            steps: (0...TerminalFlightRecorderLimits.standard.maximumStepsPerMacro).map { index in
                ReviewedTerminalMacroStep(name: "Step \(index)", action: .bookmark)
            }
        )
        XCTAssertThrowsError(try oversized.validate()) { error in
            XCTAssertEqual(
                error as? TerminalFlightRecorderError,
                .tooManySteps(maximum: TerminalFlightRecorderLimits.standard.maximumStepsPerMacro)
            )
        }
    }

    func testReceiptAndArchiveRoundTripRetainTamperEvidence() throws {
        let frame = makeFrame(profileID: UUID(), title: "COMMAND ENTRY")
        var macro = ReviewedTerminalMacro(
            name: "Evidence route",
            steps: [ReviewedTerminalMacroStep(
                name: "Match",
                action: .matchFrame(fingerprint: frame.screenFingerprint)
            )]
        )
        try macro.attestReview(by: "LOCAL OPERATOR")
        let receipt = TerminalMacroStepReceipt(
            macroID: macro.id,
            macroFingerprint: macro.contentFingerprint,
            stepID: macro.steps[0].id,
            stepOrdinal: 1,
            actionLabel: "MATCH",
            expectedScreenFingerprint: frame.screenFingerprint,
            observedScreenFingerprint: frame.screenFingerprint,
            outcome: .passed,
            detail: "Exact redacted screen matched."
        )
        let archive = TerminalFlightRecorderArchive(frames: [frame], macros: [macro], receipts: [receipt])
        try archive.validate()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(archive)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(TerminalFlightRecorderArchive.self, from: data)

        XCTAssertEqual(decoded, archive)
        try decoded.validate()

        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let tampered = json.replacingOccurrences(
            of: frame.screenFingerprint,
            with: String(repeating: "0", count: 64)
        )
        let tamperedArchive = try decoder.decode(
            TerminalFlightRecorderArchive.self,
            from: try XCTUnwrap(tampered.data(using: .utf8))
        )
        XCTAssertThrowsError(try tamperedArchive.validate())
    }

    private func makeFrame(
        profileID: UUID,
        title: String,
        capturedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> TerminalEvidenceFrame {
        var screen = TerminalScreen(rows: 24, columns: 80)
        screen.inputInhibited = false
        screen.write(
            title,
            row: 1,
            column: 2,
            attributes: TerminalAttributes(foreground: .turquoise, protected: true)
        )
        return TerminalEvidenceFrame(
            capturedAt: capturedAt,
            profileID: profileID,
            profileName: "DEV",
            screen: screen
        )
    }
}
