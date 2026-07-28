import XCTest
@testable import iTelASCore

final class TerminalForwardEdgeTriggerTests: XCTestCase {
    func testParserRetainsForwardEdgeTriggerAndItOverridesAutoEnterAtFieldEdge() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()

        parser.apply(
            TN5250Record(
                opcode: .putGet,
                payload: Data([
                    0x04, 0x11, 0x00, 0x08,
                    0x11, 0x01, 0x0B,
                    // FFW Auto Enter plus X'8501' Forward Edge Trigger.
                    0x1D, 0x48, 0x80, 0x85, 0x01, 0x20, 0x00, 0x02
                ])
            ),
            to: &screen
        )

        let field = try XCTUnwrap(screen.fields.first)
        XCTAssertTrue(field.autoEnter)
        XCTAssertTrue(field.isForwardEdgeTrigger)
        XCTAssertTrue(screen.typeCharacter("A").wasAccepted)
        XCTAssertEqual(screen.typeCharacter("B"), .forwardEdgeTrigger)
    }

    func testRedefinitionPreservesForwardEdgeTriggerFCW() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()

        parser.apply(
            TN5250Record(
                opcode: .putGet,
                payload: Data([
                    0x04, 0x11, 0x00, 0x08,
                    0x11, 0x01, 0x0B,
                    0x1D, 0x48, 0x00, 0x85, 0x01, 0x20, 0x00, 0x02
                ])
            ),
            to: &screen
        )
        XCTAssertTrue(try XCTUnwrap(screen.fields.first).isForwardEdgeTrigger)

        // A redefinition changes the FFW but, per the current parser contract,
        // does not replace the already-recorded FCW set or declared field length.
        parser.apply(
            TN5250Record(
                opcode: .putGet,
                payload: Data([
                    0x04, 0x11, 0x00, 0x08,
                    0x11, 0x01, 0x0B,
                    0x1D, 0x48, 0x20, 0x20, 0x00, 0x7F
                ])
            ),
            to: &screen
        )

        let field = try XCTUnwrap(screen.fields.first)
        XCTAssertEqual(field.length, 2)
        XCTAssertTrue(field.isForwardEdgeTrigger)
    }

    func testEverySupportedFieldExitRouteReturnsForwardEdgeTrigger() {
        var typed = makeForwardEdgeScreen(length: 2)
        XCTAssertEqual(typed.typeCharacter("A"), .accepted)
        XCTAssertEqual(typed.typeCharacter("B"), .forwardEdgeTrigger)

        var neutral = makeForwardEdgeScreen()
        XCTAssertEqual(neutral.performFieldExit(.neutral), .forwardEdgeTrigger)

        var positive = makeForwardEdgeScreen(inputType: .numericOnly)
        XCTAssertEqual(positive.performFieldExit(.positive), .forwardEdgeTrigger)

        // A three-character signed field leaves one data position after typing,
        // so Field - exercises the explicit exit route instead of edge completion.
        var negative = makeForwardEdgeScreen(inputType: .signedNumeric, length: 3)
        XCTAssertEqual(negative.typeCharacter("7"), .accepted)
        XCTAssertEqual(negative.performFieldExit(.negative), .forwardEdgeTrigger)

        var dup = makeForwardEdgeScreen(allowsDuplication: true)
        XCTAssertEqual(dup.duplicateCurrentField(), .forwardEdgeTrigger)
    }

    func testForwardEdgeAIDCarriesModifiedFieldsAndEncodesExactly() throws {
        var screen = makeForwardEdgeScreen(length: 2)
        XCTAssertEqual(screen.typeCharacter("A"), .accepted)
        XCTAssertEqual(screen.typeCharacter("B"), .forwardEdgeTrigger)

        XCTAssertTrue(TN5250AID.carriesModifiedFields(TN5250AID.forwardEdgeTrigger.rawValue))
        XCTAssertTrue(screen.aidCarriesFieldData(TN5250AID.forwardEdgeTrigger.rawValue))
        XCTAssertEqual(
            try TN5250InputEncoder.payload(
                aid: TN5250AID.forwardEdgeTrigger.rawValue,
                screen: screen
            ),
            Data([0x01, 0x0C, 0x50, 0x11, 0x01, 0x0B, 0xC1, 0xC2])
        )
    }

    func testPasteMutatesFETFieldWithoutProducingAnAIDResult() {
        var screen = makeForwardEdgeScreen(length: 2)
        screen.inputInhibited = false

        let result = screen.pasteText("AB")

        XCTAssertEqual(result, TerminalPasteResult(insertedCharacters: 2, skippedCharacters: 0, fieldsTouched: 1))
        XCTAssertEqual(String(screen.cells[10...11].map(\.character)), "AB")
        XCTAssertFalse(screen.inputInhibited)
        XCTAssertTrue(screen.isCurrentInputFieldForwardEdgeTrigger)

        var crossingScreen = TerminalScreen()
        crossingScreen.fields = [
            TerminalField(start: 10, length: 1, isProtected: false, isForwardEdgeTrigger: true),
            TerminalField(start: 20, length: 2, isProtected: false)
        ]
        crossingScreen.moveCursor(row: 0, column: 10)

        XCTAssertEqual(
            crossingScreen.pasteText("AB"),
            TerminalPasteResult(insertedCharacters: 1, skippedCharacters: 1, fieldsTouched: 1)
        )
        XCTAssertEqual(crossingScreen.cells[10].character, "A")
        XCTAssertTrue(crossingScreen.cells[20].isNull)
        XCTAssertEqual(crossingScreen.cursor, TerminalCursor(row: 0, column: 10))
        XCTAssertTrue(crossingScreen.isCurrentInputFieldForwardEdgeTrigger)
    }

    func testForwardEdgeAIDUsesEnterLikeMandatoryValidation() {
        var screen = TerminalScreen()
        screen.fields = [
            TerminalField(start: 10, length: 1, isProtected: false, requiresInput: true),
            TerminalField(start: 20, length: 1, isProtected: false, isForwardEdgeTrigger: true)
        ]
        screen.moveCursor(row: 0, column: 20)

        XCTAssertEqual(screen.typeCharacter("A"), .forwardEdgeTrigger)
        XCTAssertEqual(
            screen.prepareForAID(TN5250AID.forwardEdgeTrigger.rawValue),
            .rejected(.mandatoryEntry(field: 1))
        )
    }

    private func makeForwardEdgeScreen(
        inputType: TerminalFieldInputType = .alphabeticShift,
        length: Int = 1,
        allowsDuplication: Bool = false
    ) -> TerminalScreen {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(
            start: 10,
            length: length,
            isProtected: false,
            inputType: inputType,
            allowsDuplication: allowsDuplication,
            isForwardEdgeTrigger: true
        )]
        screen.moveCursor(row: 0, column: 10)
        return screen
    }
}
