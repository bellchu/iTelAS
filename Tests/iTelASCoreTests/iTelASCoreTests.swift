import Foundation
import XCTest
@testable import iTelASCore

final class EBCDICCodecTests: XCTestCase {
    func testCP037HelloRoundTrip() throws {
        let codec = try EBCDICCodec(ccsid: 37)
        let encoded = try codec.encode("HELLO")
        XCTAssertEqual(encoded, Data([0xC8, 0xC5, 0xD3, 0xD3, 0xD6]))
        XCTAssertEqual(try codec.decode(encoded), "HELLO")
    }

    func testUnsupportedCCSIDIsExplicit() {
        XCTAssertThrowsError(try EBCDICCodec(ccsid: 930)) { error in
            XCTAssertEqual(error as? EBCDICCodecError, .unsupportedCCSID(930))
        }
    }

    func testInternationalCCSID500RoundTrip() throws {
        let codec = try EBCDICCodec(ccsid: 500)
        let text = "HELLO £"
        XCTAssertEqual(try codec.decode(codec.encode(text)), text)
        XCTAssertTrue(EBCDICCCSIDCatalog.available.contains { $0.ccsid == 500 })
        XCTAssertEqual(EBCDICCCSIDCatalog.definition(for: 930)?.characterWidth, .mixedByte)
    }

    func testEveryAdvertisedSBCSCodecCanBeOpenedAndRoundTripsASCII() throws {
        XCTAssertEqual(EBCDICCCSIDCatalog.available.count, 16)
        for definition in EBCDICCCSIDCatalog.available {
            let codec = try EBCDICCodec(ccsid: definition.ccsid)
            XCTAssertEqual(
                try codec.decode(codec.encode("HELLO 123")),
                "HELLO 123",
                "CCSID \(definition.ccsid)"
            )
        }
    }

    func testBidirectionalCodecsAreTranscodableButNotAdvertisedAsTerminalReady() throws {
        XCTAssertEqual(EBCDICCCSIDCatalog.bidirectionalCodecOnly.map(\.ccsid), [420, 424, 918])
        XCTAssertEqual(EBCDICCCSIDCatalog.terminalReady.count, 13)
        XCTAssertFalse(EBCDICCCSIDCatalog.terminalReady.contains { $0.ccsid == 424 })

        let hebrew = "\u{05E9}\u{05DC}\u{05D5}\u{05DD}"
        let codec = try EBCDICCodec(ccsid: 424)
        XCTAssertEqual(try codec.decode(codec.encode(hebrew)), hebrew)
    }
}

final class TelnetNegotiatorTests: XCTestCase {
    func testFragmentedNegotiationAndRecordAssembly() {
        var negotiator = TelnetNegotiator()

        let first = negotiator.process(Data([0xFF, 0xFD]))
        XCTAssertTrue(first.responses.isEmpty)
        let second = negotiator.process(Data([TelnetNegotiator.Option.binary, 0x01, 0xFF]))
        XCTAssertEqual(second.responses, [Data([0xFF, 0xFB, TelnetNegotiator.Option.binary])])
        let third = negotiator.process(Data([0xFF, 0x02, 0xFF, 0xEF]))

        XCTAssertEqual(third.records, [Data([0x01, 0xFF, 0x02])])
    }

    func testTerminalTypeSubnegotiation() {
        var negotiator = TelnetNegotiator(environment: .init(terminalType: "IBM-3477-FC"))
        let result = negotiator.process(Data([0xFF, 0xFA, 24, 1, 0xFF, 0xF0]))
        XCTAssertEqual(result.responses.count, 1)
        XCTAssertTrue(result.responses[0].contains(Data("IBM-3477-FC".utf8)))
    }

    func testEnvironmentRequestFiltersVariables() {
        var negotiator = TelnetNegotiator(environment: .init(
            deviceName: "DEV400",
            keyboardType: "USB",
            codePage: "437",
            characterSet: "1212"
        ))
        let request = Data(
            [0xFF, 0xFA, TelnetNegotiator.Option.newEnvironment, 0x01, 0x03]
            + Array("DEVNAME".utf8)
            + [0xFF, 0xF0]
        )
        let result = negotiator.process(request)

        XCTAssertEqual(result.responses.count, 1)
        let responseText = String(decoding: result.responses[0], as: UTF8.self)
        XCTAssertTrue(responseText.contains("DEVNAME"))
        XCTAssertTrue(responseText.contains("DEV400"))
        XCTAssertTrue(responseText.contains("IBMSENDCONFREC"))
        XCTAssertFalse(responseText.contains("KBDTYPE"))
        XCTAssertFalse(responseText.contains("CODEPAGE"))
    }

    func testDeviceNameCollisionProducesDifferentRetry() {
        var negotiator = TelnetNegotiator(environment: .init(
            deviceName: "MYDEVICE1",
            deviceNameCandidates: ["MYDEVICE1", "MYDEVICE7"]
        ))
        let request = Data(
            [0xFF, 0xFA, TelnetNegotiator.Option.newEnvironment, 0x01, 0x03]
            + Array("DEVNAME".utf8)
            + [0xFF, 0xF0]
        )
        _ = negotiator.process(request)
        let retry = negotiator.process(request)

        XCTAssertTrue(retry.responses[0].contains(Data("MYDEVICE7".utf8)))
        XCTAssertTrue(retry.events.contains(.deviceNameRetried(
            previous: "MYDEVICE1",
            next: "MYDEVICE7",
            attempt: 1
        )))
    }

    func testTransparentModeReadinessRequiresEnhancedEnvironmentFirst() {
        var negotiator = TelnetNegotiator(environment: .init(deviceName: "DEV400"))
        let chunks: [Data] = [
            Data([0xFF, 0xFD, TelnetNegotiator.Option.newEnvironment]),
            Data([0xFF, 0xFA, TelnetNegotiator.Option.newEnvironment, 0x01, 0x00, 0x03, 0xFF, 0xF0]),
            Data([0xFF, 0xFD, TelnetNegotiator.Option.terminalType]),
            Data([0xFF, 0xFA, TelnetNegotiator.Option.terminalType, 0x01, 0xFF, 0xF0]),
            Data([0xFF, 0xFD, TelnetNegotiator.Option.binary]),
            Data([0xFF, 0xFB, TelnetNegotiator.Option.binary]),
            Data([0xFF, 0xFD, TelnetNegotiator.Option.endOfRecord]),
            Data([0xFF, 0xFB, TelnetNegotiator.Option.endOfRecord])
        ]
        let results = chunks.map { negotiator.process($0) }

        XCTAssertFalse(results.dropLast().flatMap(\.events).contains(.transparentModeReady))
        XCTAssertTrue(results.last?.events.contains(.transparentModeReady) == true)
        XCTAssertTrue(negotiator.snapshot.environmentWasSent)
        XCTAssertTrue(negotiator.snapshot.isTransparentModeReady)
    }
}

final class TN5250RecordTests: XCTestCase {
    func testRecordHeaderRoundTrip() throws {
        let original = TN5250Record(opcode: .putGet, flags: 0x0102, payload: Data([0x04, 0x40]))
        let parsed = try TN5250Record(data: original.encoded())

        XCTAssertEqual(parsed.logicalLength, 12)
        XCTAssertEqual(parsed.recordType, TN5250Record.generalDataStream)
        XCTAssertEqual(parsed.flags, 0x0102)
        XCTAssertEqual(parsed.opcode, .putGet)
        XCTAssertEqual(parsed.payload, Data([0x04, 0x40]))
    }

    func testTelnetFramingEscapesIACAndAddsEOR() {
        let framed = TN5250Record(opcode: .outputOnly, payload: Data([0xFF])).telnetFramed()
        XCTAssertTrue(framed.suffix(2).elementsEqual([0xFF, 0xEF]))
        XCTAssertEqual(framed.filter { $0 == 0xFF }.count, 3)
    }

    func testStartupRecordPreservesDataFlowHeaderAndParsesSuccess() throws {
        let prefix = "004912A090000560060020C0003D0000"
            + "C9F9F0F2"
            + "E3C1D9C7C5E34040"
            + "D7C3D7D9C9D5E3C5D940"
        let raw = Data(hexadecimal: prefix + String(repeating: "00", count: 35))
        let record = try TN5250Record(data: raw)
        let response = try TN5250StartupResponse(record: record)

        XCTAssertEqual(record.dataFlowFlags, 0x9000)
        XCTAssertTrue(record.isStartupResponse)
        XCTAssertEqual(response.responseCode, "I902")
        XCTAssertEqual(response.systemName, "TARGET")
        XCTAssertEqual(response.deviceName, "PCPRINTER")
        XCTAssertEqual(response.disposition, .success)
    }
}

final class TN5250DeviceQueryTests: XCTestCase {
    func testQueryRecognitionRequiresTheCompleteCommandAtThePayloadBoundary() {
        XCTAssertTrue(TN5250DeviceQuery.matches(TN5250DeviceQuery.command))
        XCTAssertFalse(TN5250DeviceQuery.matches(Data([0x00]) + TN5250DeviceQuery.command))
        XCTAssertFalse(TN5250DeviceQuery.matches(TN5250DeviceQuery.command + Data([0x00])))
        XCTAssertFalse(TN5250DeviceQuery.matches(Data([0x04, 0xF3, 0x00, 0x05, 0xD9, 0x70, 0x01])))
    }

    func testStandardAndWideRepliesReportConsistentDeviceIdentityAndOnlyImplementedCapabilities() {
        let standardCapabilities = TN5250DeviceCapabilities(terminalModel: .ibm3179_2)
        let standard = TN5250DeviceQuery.reply(for: standardCapabilities)
        let wideCapabilities = TN5250DeviceCapabilities(terminalModel: .ibm3477_FC)
        let wide = TN5250DeviceQuery.reply(for: wideCapabilities)

        XCTAssertEqual(standard.opcode, .noOperation)
        XCTAssertEqual(standard.payload.count, 61)
        XCTAssertEqual(standard.logicalLength, 71)
        XCTAssertEqual(Array(standard.payload[3...7]), [0x00, 0x3A, 0xD9, 0x70, 0x80])
        XCTAssertEqual(Array(standard.payload[30...36]), [0xF3, 0xF1, 0xF7, 0xF9, 0xF0, 0xF0, 0xF2])
        XCTAssertEqual(standard.payload[49], 0x62)
        XCTAssertEqual(standard.payload[50], 0x11)

        XCTAssertEqual(Array(wide.payload[30...36]), [0xF3, 0xF4, 0xF7, 0xF7, 0xC6, 0xC3, 0x40])
        XCTAssertEqual(wide.payload[49], 0x62)
        XCTAssertEqual(wide.payload[50], 0x31)
        XCTAssertEqual(wide.payload[49] & 0x18, 0, "PA keys are not currently exposed")
        XCTAssertEqual(wide.payload[49] & 0x04, 0, "Cursor Select is not currently implemented")
        XCTAssertEqual(wide.payload[52], 0, "DBCS is not currently implemented")
        XCTAssertEqual(wide.payload[53], 0, "Graphics is not currently implemented")
        XCTAssertTrue(wideCapabilities.summary.contains("IBM-3477-FC"))
    }
}

final class TN5250DataStreamParserTests: XCTestCase {
    func testClearWriteToDisplayAndSetBufferAddress() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen(rows: 27, columns: 132)
        let payload = Data([
            0x04, 0x40,
            0x04, 0x11, 0x00, 0x08,
            0x11, 0x01, 0x01,
            0xC8, 0xC5, 0xD3, 0xD3, 0xD6
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

        XCTAssertEqual(screen.rows, 24)
        XCTAssertEqual(screen.columns, 80)
        XCTAssertEqual(String(screen.rowText(0).prefix(5)), "HELLO")
        XCTAssertFalse(screen.inputInhibited)
    }

    func testAlternateClearCreatesExact27By132PresentationSpace() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x20,
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x1B, 0x82,
            0xC5, 0xD5, 0xC4
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: payload), to: &screen)

        XCTAssertEqual(screen.rows, 27)
        XCTAssertEqual(screen.columns, 132)
        XCTAssertEqual(screen.cells.count, 3_564)
        XCTAssertEqual(String(screen.rowText(26).suffix(3)), "END")
    }

    func testStartOfFieldCreatesEditableNonDisplayField() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x40,
            0x04, 0x11, 0x00, 0x08,
            0x11, 0x02, 0x0A,
            0x1D, 0x40, 0x00, 0x27, 0x00, 0x08,
            0x13, 0x02, 0x0B
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

        XCTAssertEqual(screen.fields.count, 1)
        XCTAssertEqual(screen.fields[0].start, 90)
        XCTAssertEqual(screen.fields[0].length, 8)
        XCTAssertFalse(screen.fields[0].isProtected)
        XCTAssertTrue(screen.fields[0].isNonDisplay)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 1, column: 10, isVisible: true))

        XCTAssertTrue(screen.replaceCharacter("A"))
        XCTAssertTrue(screen.fields[0].modified)
        XCTAssertFalse(screen.visibleText().contains("A"))
    }

    func testPutGetFallsBackToFirstEditableFieldWithoutInsertCursorOrder() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x40,
            0x04, 0x11, 0x00, 0x08,
            0x11, 0x05, 0x12,
            0x1D, 0x40, 0x00, 0x27, 0x00, 0x08
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

        XCTAssertEqual(screen.fields.first?.start, 338)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 4, column: 18, isVisible: true))
    }

    func testExplicitInsertCursorOrderWinsOverFallback() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x40,
            0x04, 0x11, 0x00, 0x08,
            0x11, 0x02, 0x0A,
            0x1D, 0x40, 0x00, 0x27, 0x00, 0x08,
            0x11, 0x06, 0x0A,
            0x1D, 0x40, 0x00, 0x27, 0x00, 0x08,
            0x13, 0x06, 0x0B
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

        XCTAssertEqual(screen.cursor, TerminalCursor(row: 5, column: 10, isVisible: true))
    }

    func testStandaloneAttributeOccupiesAHiddenScreenPosition() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([0x04, 0x11, 0x00, 0x00, 0x11, 0x01, 0x01, 0x22, 0xC8])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: payload), to: &screen)

        XCTAssertEqual(screen.cells[0].character, " ")
        XCTAssertEqual(screen.cells[1].character, "H")
        XCTAssertEqual(screen.cells[1].attributes.foreground, .white)
    }

    func testWriteToDisplayResetsTheDisplayAddress() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([0x04, 0x11, 0x00, 0x00, 0x11, 0x02, 0x02, 0xE7])
            ),
            to: &screen
        )
        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([0x04, 0x11, 0x00, 0x00, 0xC1])
            ),
            to: &screen
        )

        XCTAssertEqual(screen.cells[0].character, "A")
        XCTAssertEqual(screen.cells[81].character, "X")
    }

    func testRepeatToAddressWritesThroughTheInclusiveTarget() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x01, 0x4F,
            0x02, 0x02, 0x02, 0xC1
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: payload), to: &screen)

        XCTAssertEqual(String(screen.cells[78...81].map(\.character)), "AAAA")
        XCTAssertEqual(screen.cells[77].character, " ")
        XCTAssertEqual(screen.cells[82].character, " ")
    }

    func testRepeatAtTheLastScreenCellDoesNotWrapFollowingDataToTheOrigin() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x18, 0x50,
            0x02, 0x18, 0x50, 0xC1,
            0xC2
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: payload), to: &screen)

        XCTAssertEqual(screen.cells[screen.cells.count - 1].character, "A")
        XCTAssertEqual(screen.cells[0].character, " ")
    }

    func testTruncatedTransparentDataDoesNotPartiallyWrite() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.write("SAFE", row: 0, column: 0)
        let unchanged = screen

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x11, 0x01, 0x05,
                    0x10, 0x00, 0x03,
                    0xC1, 0xC2
                ])
            ),
            to: &screen
        )

        XCTAssertEqual(screen, unchanged)
    }

    func testPutGetDoesNotOverrideAHostKeyboardLock() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x02, 0x0A,
            0x1D, 0x40, 0x00, 0x27, 0x00, 0x08
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

        XCTAssertTrue(screen.inputInhibited)
        XCTAssertEqual(screen.cursor, TerminalCursor())
    }

    func testReadMDTAlternateControlUnlocksKeyboardAfterPartialHostUpdate() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 4, isProtected: false)]
        screen.moveCursor(row: 0, column: 10)
        screen.inputInhibited = true
        let payload = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x01, 0x01,
            0xC5, 0xD9, 0xD9,
            0x04, 0x82, 0x00, 0x08
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

        XCTAssertEqual(screen.readMode, .modifiedFieldsAlternate)
        XCTAssertFalse(screen.inputInhibited)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 10))
    }

    func testSecondControlAppliesCursorMessageBlinkAndAlarmAfterOrders() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.moveCursor(row: 0, column: 7)
        let setPayload = Data([
            0x04, 0x11, 0x00, 0x5D,
            0x13, 0x02, 0x03
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: setPayload), to: &screen)

        XCTAssertFalse(screen.inputInhibited)
        XCTAssertEqual(screen.cursor.row, 0)
        XCTAssertEqual(screen.cursor.column, 7)
        XCTAssertTrue(screen.cursor.isBlinking)
        XCTAssertTrue(screen.messageWaiting)
        XCTAssertEqual(screen.audibleAlarmSequence, 1)

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([0x04, 0x11, 0x00, 0x22])
            ),
            to: &screen
        )

        XCTAssertFalse(screen.cursor.isBlinking)
        XCTAssertFalse(screen.messageWaiting)
        XCTAssertEqual(screen.audibleAlarmSequence, 1)
    }

    func testInsertCursorDoesNotMoveAnAlreadyUnlockedWorkstation() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.inputInhibited = false
        screen.moveCursor(row: 0, column: 7)

        parser.apply(
            TN5250Record(
                opcode: .putGet,
                payload: Data([0x04, 0x11, 0x00, 0x08, 0x13, 0x02, 0x03])
            ),
            to: &screen
        )

        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 7))
    }

    func testFirstControlClearsModifiedNonbypassFieldsAndResetsTheirMDTs() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.inputInhibited = false
        screen.fields = [
            TerminalField(start: 10, length: 3, isProtected: false, modified: true),
            TerminalField(start: 20, length: 3, isProtected: true, modified: true)
        ]
        screen.write("ABC", row: 0, column: 10, attributes: TerminalAttributes(protected: false))
        screen.write("XYZ", row: 0, column: 20, attributes: TerminalAttributes(protected: true))

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([0x04, 0x11, 0xC0, 0x00])
            ),
            to: &screen
        )

        XCTAssertEqual(String(screen.cells[10...12].map(\.character)), "   ")
        XCTAssertEqual(String(screen.cells[20...22].map(\.character)), "XYZ")
        XCTAssertFalse(screen.fields[0].modified)
        XCTAssertTrue(screen.fields[1].modified)
        XCTAssertTrue(screen.inputInhibited)
    }

    func testMalformedEraseToAddressDoesNotErasePresentationData() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.write("SAFE", row: 0, column: 0)

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x11, 0x01, 0x01,
                    0x03, 0x01, 0x04, 0x00, 0xC1
                ])
            ),
            to: &screen
        )

        XCTAssertEqual(String(screen.rowText(0).prefix(4)), "SAFE")

        let unchanged = screen
        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x12, 0x01, 0x7F,
                    0xC1
                ])
            ),
            to: &screen
        )
        XCTAssertEqual(screen, unchanged)
    }

    func testWriteExtendedPrimaryOverridesPresentationWithoutAdvancingAddress() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x11, 0x00, 0x00,
            0x12, 0x01, 0x9F,
            0xC1,
            0x12, 0x01, 0x80,
            0xC2
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: payload), to: &screen)

        XCTAssertEqual(screen.cells[0].character, "A")
        XCTAssertTrue(screen.cells[0].attributes.columnSeparator)
        XCTAssertTrue(screen.cells[0].attributes.blink)
        XCTAssertTrue(screen.cells[0].attributes.underline)
        XCTAssertTrue(screen.cells[0].attributes.highIntensity)
        XCTAssertTrue(screen.cells[0].attributes.reverse)
        XCTAssertEqual(screen.cells[1].character, "B")
        XCTAssertFalse(screen.cells[1].attributes.columnSeparator)
        XCTAssertFalse(screen.cells[1].attributes.blink)
        XCTAssertFalse(screen.cells[1].attributes.underline)
        XCTAssertFalse(screen.cells[1].attributes.highIntensity)
        XCTAssertFalse(screen.cells[1].attributes.reverse)
    }

    func testWriteExtendedForegroundColorMapsEveryDocumentedValue() throws {
        let expected: [UInt8: TerminalColor] = [
            0x80: .green,
            0x81: .black,
            0x82: .blue, 0x83: .blue,
            0x84: .green, 0x85: .green,
            0x86: .turquoise, 0x87: .turquoise,
            0x88: .red, 0x89: .red,
            0x8A: .pink, 0x8B: .pink,
            0x8C: .yellow, 0x8D: .yellow,
            0x8E: .white, 0x8F: .white
        ]

        for value in UInt8(0x80)...UInt8(0x8F) {
            var parser = try TN5250DataStreamParser(ccsid: 37)
            var screen = TerminalScreen()
            parser.apply(
                TN5250Record(
                    opcode: .outputOnly,
                    payload: Data([0x04, 0x11, 0x00, 0x00, 0x12, 0x03, value, 0xC1])
                ),
                to: &screen
            )

            XCTAssertEqual(screen.cells[0].character, "A")
            XCTAssertEqual(screen.cells[0].attributes.foreground, expected[value], "WEA color \(value)")
        }
    }

    func testNullExtendedAttributeRemovesTheMarkerAndContinuesThePriorValue() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x12, 0x03, 0x88,
                    0xC1, 0xC2,
                    0x12, 0x03, 0x82,
                    0xC3, 0xC4
                ])
            ),
            to: &screen
        )
        XCTAssertEqual(screen.cells[0].attributes.foreground, .red)
        XCTAssertEqual(screen.cells[2].attributes.foreground, .blue)

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x11, 0x01, 0x03,
                    0x12, 0x03, 0x00
                ])
            ),
            to: &screen
        )

        XCTAssertEqual(String(screen.cells[0...3].map(\.character)), "ABCD")
        XCTAssertEqual(screen.cells[2].attributes.foreground, .red)
        XCTAssertEqual(screen.cells[3].attributes.foreground, .red)
    }

    func testEraseToAddressClearsOnlySelectedLayerAndAdvancesAddress() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x12, 0x03, 0x88,
                    0xC1, 0xC2,
                    0x12, 0x03, 0x82,
                    0xC3, 0xC4,
                    0x12, 0x03, 0x84,
                    0xC5
                ])
            ),
            to: &screen
        )

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x11, 0x01, 0x03,
                    0x03, 0x01, 0x04, 0x02, 0x03,
                    0xE9
                ])
            ),
            to: &screen
        )

        XCTAssertEqual(String(screen.cells[0...4].map(\.character)), "ABCDZ")
        XCTAssertEqual(screen.cells[2].attributes.foreground, .red)
        XCTAssertEqual(screen.cells[3].attributes.foreground, .red)
        XCTAssertEqual(screen.cells[4].attributes.foreground, .green)
    }

    func testEraseToAddressAllClearsDisplayAndSupportedExtendedLayers() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x12, 0x01, 0x9F,
                    0x12, 0x03, 0x88,
                    0xC1, 0xC2, 0xC3
                ])
            ),
            to: &screen
        )

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x03, 0x01, 0x03, 0x02, 0xFF
                ])
            ),
            to: &screen
        )

        XCTAssertEqual(String(screen.cells[0...2].map(\.character)), "   ")
        for position in 0...2 {
            XCTAssertEqual(screen.cells[position].attributes.foreground, .green)
            XCTAssertFalse(screen.cells[position].attributes.blink)
            XCTAssertFalse(screen.cells[position].attributes.reverse)
            XCTAssertFalse(screen.cells[position].attributes.highIntensity)
        }
    }

    func testEraseDisplayPreservesNonDisplayInputFieldProtection() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        parser.apply(
            TN5250Record(
                opcode: .putGet,
                payload: Data([
                    0x04, 0x40,
                    0x04, 0x11, 0x00, 0x08,
                    0x11, 0x02, 0x0A,
                    0x1D, 0x40, 0x00, 0x27, 0x00, 0x08,
                    0x13, 0x02, 0x0B
                ])
            ),
            to: &screen
        )

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x11, 0x02, 0x0B,
                    0x03, 0x02, 0x12, 0x02, 0x00
                ])
            ),
            to: &screen
        )

        XCTAssertEqual(screen.fields.count, 1)
        XCTAssertTrue(screen.cells[90].attributes.nonDisplay)
        XCTAssertFalse(screen.cells[90].attributes.protected)
        XCTAssertTrue(screen.replaceCharacter("A"))
        XCTAssertFalse(screen.visibleText().contains("A"))
    }

    func testLegacyTerminalAttributesDefaultHighIntensityOff() throws {
        let encoded = Data(
            #"{"foreground":"green","reverse":false,"underline":false,"blink":false,"columnSeparator":false,"nonDisplay":false,"protected":true}"#.utf8
        )

        let attributes = try JSONDecoder().decode(TerminalAttributes.self, from: encoded)

        XCTAssertFalse(attributes.highIntensity)
    }

    func testScreenAttributeTableMatchesDocumentedColorDisplayValues() {
        let reverse: Set<UInt8> = [
            0x21, 0x23, 0x25, 0x29, 0x2B, 0x2D,
            0x31, 0x33, 0x35, 0x39, 0x3B, 0x3D
        ]
        let underline: Set<UInt8> = [
            0x24, 0x25, 0x26, 0x2C, 0x2D, 0x2E,
            0x34, 0x35, 0x36, 0x3C, 0x3D, 0x3E
        ]
        let blink: Set<UInt8> = [0x2A, 0x2B, 0x2E]
        let separators: Set<UInt8> = [0x30, 0x31, 0x32, 0x33]
        let nonDisplay: Set<UInt8> = [0x27, 0x2F, 0x37, 0x3F]
        let colors: [UInt8: TerminalColor] = [
            0x20: .green, 0x21: .green, 0x24: .green, 0x25: .green,
            0x22: .white, 0x23: .white, 0x26: .white,
            0x28: .red, 0x29: .red, 0x2A: .red, 0x2B: .red,
            0x2C: .red, 0x2D: .red, 0x2E: .red,
            0x30: .turquoise, 0x31: .turquoise, 0x34: .turquoise, 0x35: .turquoise,
            0x32: .yellow, 0x33: .yellow, 0x36: .yellow,
            0x38: .pink, 0x39: .pink, 0x3C: .pink, 0x3D: .pink,
            0x3A: .blue, 0x3B: .blue, 0x3E: .blue
        ]

        for byte in UInt8(0x20)...UInt8(0x3F) {
            let attributes = TN5250DataStreamParser.attributes(for: byte)
            XCTAssertEqual(attributes.reverse, reverse.contains(byte), "attribute \(byte)")
            XCTAssertEqual(attributes.underline, underline.contains(byte), "attribute \(byte)")
            XCTAssertEqual(attributes.blink, blink.contains(byte), "attribute \(byte)")
            XCTAssertEqual(attributes.columnSeparator, separators.contains(byte), "attribute \(byte)")
            XCTAssertEqual(attributes.nonDisplay, nonDisplay.contains(byte), "attribute \(byte)")
            if let color = colors[byte] {
                XCTAssertEqual(attributes.foreground, color, "attribute \(byte)")
            }
        }
    }

    func testInviteRestoresInputOnlyAfterCancelInvite() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 3, isProtected: false)]

        parser.apply(TN5250Record(opcode: .cancelInvite), to: &screen)
        XCTAssertTrue(screen.inputInhibited)

        parser.apply(TN5250Record(opcode: .invite), to: &screen)
        XCTAssertFalse(screen.inputInhibited)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 10))
    }

    func testHostReadCommandsSelectExactInputFormattingMode() throws {
        let cases: [(UInt8, TerminalReadMode)] = [
            (0x42, .inputFields),
            (0x52, .modifiedFields),
            (0x82, .modifiedFieldsAlternate)
        ]
        for (command, expectedMode) in cases {
            var parser = try TN5250DataStreamParser(ccsid: 37)
            var screen = TerminalScreen()

            parser.apply(
                TN5250Record(opcode: .invite, payload: Data([0x04, command, 0x00, 0x08])),
                to: &screen
            )

            XCTAssertEqual(screen.readMode, expectedMode, "command 0x\(String(command, radix: 16))")
            XCTAssertFalse(screen.inputInhibited)
        }
    }

    func testStartOfHeaderDecodesReadResequencingAndFunctionKeyDataSwitches() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 2, isProtected: false)]
        let maskedHeader = Data([
            0x04, 0x11, 0x00, 0x00,
            0x01, 0x07,
            0x00, 0x00, 0x02, 0x18,
            0x80, 0x01, 0x01
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: maskedHeader), to: &screen)

        XCTAssertTrue(screen.fields.isEmpty)
        XCTAssertEqual(screen.readResequenceStartField, 2)
        XCTAssertFalse(screen.functionKeyCarriesFieldData(24))
        XCTAssertFalse(screen.functionKeyCarriesFieldData(9))
        XCTAssertFalse(screen.functionKeyCarriesFieldData(1))
        XCTAssertTrue(screen.functionKeyCarriesFieldData(23))
        XCTAssertTrue(screen.functionKeyCarriesFieldData(8))
        XCTAssertFalse(screen.aidCarriesFieldData(try XCTUnwrap(TN5250AID.function(1))))
        XCTAssertTrue(screen.aidCarriesFieldData(TN5250AID.enter.rawValue))

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x01, 0x06,
                    0x00, 0x00, 0x00, 0x18, 0xFF, 0xFF
                ])
            ),
            to: &screen
        )

        XCTAssertEqual(screen.readResequenceStartField, 0)
        XCTAssertTrue((1...24).allSatisfy(screen.functionKeyCarriesFieldData))
    }

    func testTransparentFCWPreservesRawBytesAndUsesInboundTransparentDataOnRead() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x11, 0x00, 0x08,
            0x11, 0x02, 0x0A,
            0x1D, 0x48, 0x00, 0x84, 0x00, 0x20, 0x00, 0x04,
            0x10, 0x00, 0x04, 0x00, 0xC1, 0x00, 0xC2
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

        let field = try XCTUnwrap(screen.fields.first)
        XCTAssertTrue(field.isTransparent)
        XCTAssertTrue(field.modified)
        XCTAssertEqual(screen.cells[90...93].map(\.isNull), [true, false, true, false])
        XCTAssertEqual(screen.cells[90...93].map(\.inputByteOverride), [0x00, 0xC1, 0x00, 0xC2])
        XCTAssertEqual(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen),
            Data([0x02, 0x0B, 0xF1, 0x11, 0x02, 0x0B, 0x10, 0x00, 0x04, 0x00, 0xC1, 0x00, 0xC2])
        )
    }

    func testStartOfFieldDecodesEveryDocumentedInputTypeAndFlag() throws {
        for (rawType, expectedType) in TerminalFieldInputType.allCases.enumerated() {
            var parser = try TN5250DataStreamParser(ccsid: 37)
            var screen = TerminalScreen()
            let ffw1 = UInt8(0x58 | rawType)
            let payload = Data([
                0x04, 0x40,
                0x04, 0x11, 0x00, 0x08,
                0x11, 0x02, 0x0A,
                0x1D, ffw1, 0xED, 0x20, 0x00, 0x04
            ])

            parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

            let field = try XCTUnwrap(screen.fields.first)
            XCTAssertEqual(field.inputType, expectedType)
            XCTAssertTrue(field.allowsDuplication)
            XCTAssertTrue(field.autoEnter)
            XCTAssertTrue(field.requiresFieldExit)
            XCTAssertTrue(field.isMonocase)
            XCTAssertTrue(field.requiresInput)
            XCTAssertEqual(field.adjustment, .centerZeroFill)
            XCTAssertTrue(field.modified)
            XCTAssertFalse(field.isProtected)
        }
    }

    func testStartOfFieldSuppliesEndingAttributeWithoutConsumingFieldData() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x02, 0x0A,
            0x1D, 0x40, 0x00, 0x22, 0x00, 0x04,
            0xC1, 0xC2, 0xC3, 0xC4
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: payload), to: &screen)

        XCTAssertEqual(screen.fields.first?.start, 90)
        XCTAssertEqual(String(screen.cells[90...93].map(\.character)), "ABCD")
        XCTAssertEqual(screen.cells[90].attributes.foreground, .white)
        XCTAssertTrue(screen.cells[89].attributes.nonDisplay)
        XCTAssertTrue(screen.cells[94].attributes.nonDisplay)
        XCTAssertEqual(screen.cells[94].character, " ")
    }

    func testFieldBufferPreservesHostNullVersusEBCDICBlank() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x02, 0x0A,
            0x1D, 0x40, 0x00, 0x20, 0x00, 0x04,
            0xC1, 0x00, 0x40, 0xC2
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: payload), to: &screen)

        XCTAssertEqual(String(screen.cells[90...93].map(\.character)), "A  B")
        XCTAssertEqual(screen.cells[90...93].map(\.isNull), [false, true, false, false])
    }

    func testRowOneColumnZeroSBADefinesAFieldAtTheFirstScreenPosition() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x40,
            0x04, 0x11, 0x00, 0x08,
            0x11, 0x01, 0x00,
            0x1D, 0x40, 0x00, 0x20, 0x00, 0x04,
            0xC1, 0xC2, 0xC3, 0xC4
        ])

        parser.apply(TN5250Record(opcode: .putGet, payload: payload), to: &screen)

        XCTAssertEqual(screen.fields.first?.start, 0)
        XCTAssertEqual(screen.fields.first?.length, 4)
        XCTAssertEqual(String(screen.cells[0...3].map(\.character)), "ABCD")
        XCTAssertFalse(screen.cells[0].attributes.nonDisplay)
        XCTAssertTrue(screen.cells[4].attributes.nonDisplay)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 0))
        XCTAssertFalse(screen.inputInhibited)
    }

    func testFieldRedefinitionPreservesOriginalLengthAndEndingAttribute() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let initial = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x02, 0x0A,
            0x1D, 0x40, 0x00, 0x20, 0x00, 0x04,
            0xC1, 0xC2, 0xC3, 0xC4
        ])
        let redefinition = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x02, 0x0A,
            0x1D, 0x43, 0x00, 0x22, 0x00, 0x02
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: initial), to: &screen)
        let originalID = try XCTUnwrap(screen.fields.first?.id)
        parser.apply(TN5250Record(opcode: .outputOnly, payload: redefinition), to: &screen)

        let field = try XCTUnwrap(screen.fields.first)
        XCTAssertEqual(field.id, originalID)
        XCTAssertEqual(field.length, 4)
        XCTAssertEqual(field.inputType, .numericOnly)
        XCTAssertEqual(screen.cells[90].attributes.foreground, .white)
        XCTAssertTrue(screen.cells[94].attributes.nonDisplay)
    }

    func testFieldRedefinitionIgnoresReplacementControlWords() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let initial = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x02, 0x0A,
            0x1D, 0x48, 0x00,
            0x80, 0x03,
            0x84, 0x00,
            0x20, 0x00, 0x04
        ])
        let redefinition = Data([
            0x04, 0x11, 0x00, 0x00,
            0x11, 0x02, 0x0A,
            0x1D, 0x40, 0x00,
            0x80, 0xFF,
            0x22, 0x00, 0x02
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: initial), to: &screen)
        parser.apply(TN5250Record(opcode: .outputOnly, payload: redefinition), to: &screen)

        let field = try XCTUnwrap(screen.fields.first)
        XCTAssertTrue(field.isEntryField)
        XCTAssertEqual(field.readResequenceNextField, 3)
        XCTAssertTrue(field.isTransparent)
        XCTAssertEqual(field.length, 4)
    }

    func testInvalidAddressesAndBackwardRepeatFailWithoutScreenMutation() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        screen.write("SAFE", row: 0, column: 0)

        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([0x04, 0x11, 0x00, 0x00, 0x11, 0x00, 0x01, 0xE9])
            ),
            to: &screen
        )
        parser.apply(
            TN5250Record(
                opcode: .outputOnly,
                payload: Data([
                    0x04, 0x11, 0x00, 0x00,
                    0x11, 0x01, 0x05,
                    0x02, 0x01, 0x03, 0xE9
                ])
            ),
            to: &screen
        )

        XCTAssertEqual(String(screen.rowText(0).prefix(4)), "SAFE")
        XCTAssertEqual(screen.cells[4].character, " ")
    }

    func testMoveCursorIsDeferredUnconditionalAndDoesNotReplaceHomeAddress() throws {
        var parser = try TN5250DataStreamParser(ccsid: 37)
        var screen = TerminalScreen()
        let payload = Data([
            0x04, 0x11, 0x00, 0x40,
            0x13, 0x02, 0x03,
            0x14, 0x03, 0x04
        ])

        parser.apply(TN5250Record(opcode: .outputOnly, payload: payload), to: &screen)

        XCTAssertTrue(screen.inputInhibited)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 2, column: 3))
        XCTAssertEqual(screen.homeCursorPosition, 82)
        XCTAssertTrue(screen.moveToStartOfInputField())
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 1, column: 2))
    }

    func testLegacyCursorCodingDefaultsBlinkStateOff() throws {
        let encoded = Data(#"{"row":4,"column":12,"isVisible":true}"#.utf8)

        let cursor = try JSONDecoder().decode(TerminalCursor.self, from: encoded)

        XCTAssertEqual(cursor, TerminalCursor(row: 4, column: 12))
    }
}

final class TN5250InputEncoderTests: XCTestCase {
    func testModifiedFieldIsSentWithPutGetPayloadShape() throws {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 90, length: 8, isProtected: false)]
        screen.moveCursor(row: 1, column: 10)
        XCTAssertTrue(screen.replaceCharacter("A"))

        let payload = try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen)

        XCTAssertEqual(payload, Data([0x02, 0x0C, 0xF1, 0x11, 0x02, 0x0B, 0xC1]))
    }

    func testReadMDTFormattingConvertsEmbeddedNullsButPreservesTypedTrailingBlank() throws {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 4, isProtected: false)]
        screen.moveCursor(row: 0, column: 10)
        XCTAssertTrue(screen.replaceCharacter("A"))
        screen.moveCursor(row: 0, column: 12)
        XCTAssertTrue(screen.replaceCharacter(" "))

        let payload = try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen)

        XCTAssertEqual(payload, Data([0x01, 0x0E, 0xF1, 0x11, 0x01, 0x0B, 0xC1, 0x40, 0x40]))
    }

    func testAIDWithoutReadMDTDoesNotReturnModifiedFields() throws {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 4, isProtected: false)]
        screen.moveCursor(row: 0, column: 10)
        XCTAssertTrue(screen.replaceCharacter("A"))

        let payload = try TN5250InputEncoder.payload(aid: TN5250AID.help.rawValue, screen: screen)

        XCTAssertEqual(payload, Data([0x01, 0x0C, 0xF3]))
    }

    func testMaskedFunctionKeyReturnsCursorAndAIDWithoutFieldData() throws {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 2, isProtected: false, modified: true)]
        screen.write("A", row: 0, column: 10, attributes: TerminalAttributes(protected: false))
        screen.functionKeyDataInclusionMask &= ~UInt32(1)

        XCTAssertEqual(
            try TN5250InputEncoder.payload(
                aid: try XCTUnwrap(TN5250AID.function(1)),
                screen: screen
            ),
            Data([0x01, 0x01, 0x31])
        )
        XCTAssertEqual(
            try TN5250InputEncoder.payload(
                aid: try XCTUnwrap(TN5250AID.function(2)),
                screen: screen
            ),
            Data([0x01, 0x01, 0x32, 0x11, 0x01, 0x0B, 0xC1])
        )
    }

    func testReadResequencingCountsBypassEntriesAndExcludesOutputFields() throws {
        var screen = TerminalScreen()
        screen.readResequenceStartField = 2
        screen.fields = [
            TerminalField(
                start: 5,
                length: 2,
                isProtected: true,
                isEntryField: false,
                modified: true
            ),
            TerminalField(
                start: 10,
                length: 2,
                isProtected: true,
                readResequenceNextField: 3,
                modified: true
            ),
            TerminalField(
                start: 20,
                length: 2,
                isProtected: false,
                readResequenceNextField: 1,
                modified: true
            ),
            TerminalField(
                start: 30,
                length: 2,
                isProtected: false,
                readResequenceNextField: 0xFF,
                modified: true
            )
        ]
        screen.write("B", row: 0, column: 20, attributes: TerminalAttributes(protected: false))
        screen.write("C", row: 0, column: 30, attributes: TerminalAttributes(protected: false))

        XCTAssertEqual(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen),
            Data([
                0x01, 0x01, 0xF1,
                0x11, 0x01, 0x15, 0xC2,
                0x11, 0x01, 0x1F, 0xC3
            ])
        )
    }

    func testReadInputUsesGlobalMasterMDTBeforeApplyingResequencedFieldOrder() throws {
        var screen = TerminalScreen()
        screen.readMode = .inputFields
        screen.readResequenceStartField = 1
        screen.fields = [
            TerminalField(
                start: 10,
                length: 2,
                isProtected: false,
                readResequenceNextField: 0xFF
            ),
            TerminalField(start: 20, length: 2, isProtected: false, modified: true)
        ]
        screen.write("A", row: 0, column: 10, attributes: TerminalAttributes(protected: false))

        XCTAssertEqual(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen),
            Data([0x01, 0x01, 0xF1, 0xC1, 0x40])
        )
    }

    func testInvalidReadResequencingChainsFailClosed() throws {
        var screen = TerminalScreen()
        screen.fields = [
            TerminalField(
                start: 10,
                length: 2,
                isProtected: false,
                readResequenceNextField: 2,
                modified: true
            ),
            TerminalField(
                start: 20,
                length: 2,
                isProtected: false,
                readResequenceNextField: 1,
                modified: true
            )
        ]

        screen.readResequenceStartField = 3
        XCTAssertThrowsError(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen)
        ) { error in
            XCTAssertEqual(error as? TN5250InputEncoderError, .invalidReadResequenceStart(3))
        }

        screen.readResequenceStartField = 1
        screen.fields[0].readResequenceNextField = 3
        XCTAssertThrowsError(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen)
        ) { error in
            XCTAssertEqual(
                error as? TN5250InputEncoderError,
                .invalidReadResequenceTarget(field: 1, target: 3)
            )
        }

        screen.fields[0].readResequenceNextField = 2
        XCTAssertThrowsError(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen)
        ) { error in
            XCTAssertEqual(error as? TN5250InputEncoderError, .closedReadResequenceLoop(field: 1))
        }

        screen.fields[0].readResequenceNextField = nil
        screen.fields[1].readResequenceNextField = nil
        XCTAssertThrowsError(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen)
        ) { error in
            XCTAssertEqual(
                error as? TN5250InputEncoderError,
                .missingReadResequenceTerminator(field: 2)
            )
        }
    }

    func testDupAndNegativeSignedNumericUseWorkstationBytes() throws {
        var dupScreen = TerminalScreen()
        dupScreen.fields = [TerminalField(
            start: 10,
            length: 4,
            isProtected: false,
            allowsDuplication: true
        )]
        dupScreen.moveCursor(row: 0, column: 10)
        XCTAssertTrue(dupScreen.replaceCharacter("A"))
        XCTAssertEqual(dupScreen.duplicateCurrentField(), .advanced)
        XCTAssertEqual(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: dupScreen),
            Data([0x01, 0x0B, 0xF1, 0x11, 0x01, 0x0B, 0xC1, 0x1C, 0x1C, 0x1C])
        )

        var signedScreen = TerminalScreen()
        signedScreen.fields = [TerminalField(
            start: 20,
            length: 4,
            isProtected: false,
            inputType: .signedNumeric
        )]
        signedScreen.moveCursor(row: 0, column: 20)
        XCTAssertTrue(signedScreen.replaceCharacter("1"))
        XCTAssertTrue(signedScreen.replaceCharacter("2"))
        XCTAssertEqual(signedScreen.performFieldExit(.negative), .advanced)
        XCTAssertEqual(String(signedScreen.cells[20...23].map(\.character)), " 12-")
        XCTAssertEqual(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: signedScreen),
            Data([0x01, 0x15, 0xF1, 0x11, 0x01, 0x15, 0x40, 0xF1, 0xD2])
        )
    }

    func testReadMDTAlternatePreservesLeadingAndEmbeddedNullsButStripsTrailingNulls() throws {
        var screen = TerminalScreen()
        screen.readMode = .modifiedFieldsAlternate
        screen.fields = [TerminalField(start: 10, length: 4, isProtected: false, modified: true)]
        screen.write("\0A\0\0", row: 0, column: 10, attributes: TerminalAttributes(protected: false))

        XCTAssertEqual(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen),
            Data([0x01, 0x01, 0xF1, 0x11, 0x01, 0x0B, 0x00, 0xC1])
        )
    }

    func testReadInputReturnsEveryInputFieldWithoutAddressesWhenMasterMDTIsSet() throws {
        var screen = TerminalScreen()
        screen.readMode = .inputFields
        screen.fields = [
            TerminalField(start: 10, length: 3, isProtected: false, modified: true),
            TerminalField(start: 20, length: 2, isProtected: false, isTransparent: true)
        ]
        screen.write("A", row: 0, column: 10, attributes: TerminalAttributes(protected: false))
        screen.write("B", row: 0, column: 21, attributes: TerminalAttributes(protected: false))

        XCTAssertEqual(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen),
            Data([0x01, 0x01, 0xF1, 0xC1, 0x40, 0x40, 0x00, 0xC2])
        )

        screen.fields[0].modified = false
        XCTAssertEqual(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen),
            Data([0x01, 0x01, 0xF1])
        )
    }

    func testSignedTransparentFieldFailsClosed() {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(
            start: 10,
            length: 3,
            isProtected: false,
            inputType: .signedNumeric,
            isTransparent: true,
            modified: true
        )]

        XCTAssertThrowsError(
            try TN5250InputEncoder.payload(aid: TN5250AID.enter.rawValue, screen: screen)
        ) { error in
            XCTAssertEqual(error as? TN5250InputEncoderError, .signedTransparentField(1))
        }
    }
}

final class TerminalScreenEditingTests: XCTestCase {
    func testInteractiveTypingAdvancesOrRequestsAutoEnterAtFieldEnd() {
        var screen = TerminalScreen()
        screen.fields = [
            TerminalField(start: 10, length: 2, isProtected: false),
            TerminalField(start: 20, length: 2, isProtected: false, autoEnter: true)
        ]
        screen.moveCursor(row: 0, column: 10)

        XCTAssertEqual(screen.typeCharacter("A"), .accepted)
        XCTAssertEqual(screen.typeCharacter("B"), .advanced)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 20))
        XCTAssertEqual(screen.typeCharacter("1"), .accepted)
        XCTAssertEqual(screen.typeCharacter("2"), .autoEnter)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 21))
    }

    func testFieldExitRequiredWaitsAtFieldEndAndEnterSatisfiesNondataKey() {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(
            start: 10,
            length: 2,
            isProtected: false,
            requiresFieldExit: true
        )]
        screen.moveCursor(row: 0, column: 10)

        XCTAssertEqual(screen.typeCharacter("A"), .accepted)
        XCTAssertEqual(screen.typeCharacter("B"), .accepted)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 11))
        XCTAssertTrue(screen.fields[0].isFieldExitPending)
        XCTAssertEqual(screen.prepareForAID(TN5250AID.enter.rawValue), .ready)
        XCTAssertFalse(screen.fields[0].isFieldExitPending)
    }

    func testRightAdjustFinalizesOnlyWithFieldExitAndBlocksDirectEnter() {
        var screen = TerminalScreen()
        screen.fields = [
            TerminalField(
                start: 10,
                length: 5,
                isProtected: false,
                inputType: .digitsOnly,
                adjustment: .centerZeroFill
            ),
            TerminalField(start: 30, length: 2, isProtected: false)
        ]
        screen.moveCursor(row: 0, column: 10)

        XCTAssertEqual(screen.typeCharacter("1"), .accepted)
        XCTAssertEqual(screen.typeCharacter("2"), .accepted)
        XCTAssertEqual(
            screen.prepareForAID(TN5250AID.enter.rawValue),
            .rejected(.fieldExitRequired(field: 1))
        )
        XCTAssertEqual(screen.performFieldExit(.neutral), .advanced)
        XCTAssertEqual(String(screen.cells[10...14].map(\.character)), "00012")
        XCTAssertTrue(screen.cells[10...14].allSatisfy { !$0.isNull })
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 30))
    }

    func testMandatoryEntryAndMandatoryFillBlockInvalidExitWithoutMutation() {
        var mandatoryEntry = TerminalScreen()
        mandatoryEntry.fields = [TerminalField(
            start: 10,
            length: 3,
            isProtected: false,
            requiresInput: true
        )]
        mandatoryEntry.moveCursor(row: 0, column: 10)
        XCTAssertEqual(
            mandatoryEntry.prepareForAID(TN5250AID.enter.rawValue),
            .rejected(.mandatoryEntry(field: 1))
        )
        XCTAssertEqual(
            mandatoryEntry.performFieldExit(.neutral),
            .rejected(.mandatoryEntry(field: 1))
        )

        var mandatoryFill = TerminalScreen()
        mandatoryFill.fields = [
            TerminalField(
                start: 20,
                length: 3,
                isProtected: false,
                adjustment: .mandatoryFill
            ),
            TerminalField(start: 30, length: 2, isProtected: false)
        ]
        mandatoryFill.moveCursor(row: 0, column: 20)
        XCTAssertEqual(mandatoryFill.typeCharacter("1"), .accepted)
        let beforeExit = mandatoryFill
        XCTAssertFalse(mandatoryFill.moveToNextInputField())
        XCTAssertEqual(mandatoryFill, beforeExit)
        XCTAssertEqual(
            mandatoryFill.prepareForAID(TN5250AID.enter.rawValue),
            .rejected(.mandatoryFill(field: 1))
        )
        XCTAssertEqual(
            mandatoryFill.performFieldExit(.neutral),
            .rejected(.mandatoryFill(field: 1))
        )
        XCTAssertEqual(mandatoryFill, beforeExit)

        XCTAssertEqual(mandatoryFill.typeCharacter("2"), .accepted)
        XCTAssertEqual(mandatoryFill.typeCharacter("3"), .advanced)
        XCTAssertEqual(mandatoryFill.cursor, TerminalCursor(row: 0, column: 30))
    }

    func testMaskedFunctionKeySkipsFieldValidationWhileEnterStillEnforcesIt() throws {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(
            start: 10,
            length: 3,
            isProtected: false,
            requiresInput: true
        )]
        screen.functionKeyDataInclusionMask &= ~UInt32(1)

        XCTAssertEqual(
            screen.prepareForAID(try XCTUnwrap(TN5250AID.function(1))),
            .ready
        )
        XCTAssertEqual(
            screen.prepareForAID(TN5250AID.enter.rawValue),
            .rejected(.mandatoryEntry(field: 1))
        )
    }

    func testDupRequiresFFWPermissionAndFillsRemainingBufferWithDupBytes() {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 4, isProtected: false)]
        screen.moveCursor(row: 0, column: 10)
        XCTAssertEqual(
            screen.duplicateCurrentField(),
            .rejected(.duplicationNotAllowed(field: 1))
        )

        screen.fields[0].allowsDuplication = true
        XCTAssertEqual(screen.typeCharacter("A"), .accepted)
        XCTAssertEqual(screen.duplicateCurrentField(), .advanced)
        XCTAssertEqual(String(screen.cells[10...13].map(\.character)), "A***")
        XCTAssertEqual(screen.cells[11...13].map(\.inputByteOverride), [0x1C, 0x1C, 0x1C])
    }

    func testTabCyclesOnlyThroughEditableFields() {
        var screen = TerminalScreen()
        screen.fields = [
            TerminalField(start: 10, length: 4, isProtected: false),
            TerminalField(start: 20, length: 4, isProtected: true),
            TerminalField(start: 30, length: 4, isProtected: false)
        ]
        screen.moveCursor(row: 0, column: 10)

        XCTAssertTrue(screen.moveToNextInputField())
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 30, isVisible: true))
        XCTAssertTrue(screen.moveToNextInputField())
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 10, isVisible: true))
    }

    func testDeleteBackwardStaysInsideFieldAndMarksItModified() {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 4, isProtected: false)]
        screen.write("ABCD", row: 0, column: 10)
        screen.moveCursor(row: 0, column: 12)

        XCTAssertTrue(screen.deleteBackward())
        XCTAssertEqual(screen.cells[11].character, " ")
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 11, isVisible: true))
        XCTAssertTrue(screen.fields[0].modified)

        screen.moveCursor(row: 0, column: 10)
        XCTAssertTrue(screen.deleteBackward())
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 10, isVisible: true))
        XCTAssertEqual(screen.cells[9].character, " ")
    }

    func testFieldExitErasesRemainderAndAdvances() {
        var screen = TerminalScreen()
        screen.fields = [
            TerminalField(start: 10, length: 5, isProtected: false),
            TerminalField(start: 30, length: 4, isProtected: false)
        ]
        screen.write("ABCDE", row: 0, column: 10)
        screen.moveCursor(row: 0, column: 12)

        XCTAssertTrue(screen.fieldExit())

        XCTAssertEqual(String(screen.cells[10...14].map(\.character)), "AB   ")
        XCTAssertTrue(screen.fields[0].modified)
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 30, isVisible: true))
    }

    func testDeleteCharacterShiftsWithinField() {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 5, isProtected: false)]
        screen.write("ABCDE", row: 0, column: 10)
        screen.moveCursor(row: 0, column: 12)

        XCTAssertTrue(screen.deleteCharacter())

        XCTAssertEqual(String(screen.cells[10...14].map(\.character)), "ABDE ")
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 12, isVisible: true))
    }

    func testInsertModeShiftsRightAndRejectsFullField() {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 5, isProtected: false)]
        screen.write("AB  ", row: 0, column: 10)
        screen.moveCursor(row: 0, column: 11)

        XCTAssertTrue(screen.replaceCharacter("X", insertMode: true))
        XCTAssertEqual(String(screen.cells[10...14].map(\.character)), "AXB  ")

        screen.write("ABCDE", row: 0, column: 10)
        screen.moveCursor(row: 0, column: 12)
        XCTAssertFalse(screen.replaceCharacter("X", insertMode: true))
        XCTAssertEqual(String(screen.cells[10...14].map(\.character)), "ABCDE")
    }

    func testPasteFlowsAcrossFieldsAndHonorsNumericOnly() {
        var screen = TerminalScreen()
        screen.fields = [
            TerminalField(start: 10, length: 3, isProtected: false),
            TerminalField(start: 20, length: 3, isProtected: false, isNumericOnly: true)
        ]
        screen.moveCursor(row: 0, column: 10)

        let result = screen.pasteText("ABC\t1X2")

        XCTAssertEqual(result, TerminalPasteResult(insertedCharacters: 5, skippedCharacters: 1, fieldsTouched: 2))
        XCTAssertEqual(String(screen.cells[10...12].map(\.character)), "ABC")
        XCTAssertEqual(String(screen.cells[20...22].map(\.character)), "12 ")
    }

    func testMousePositionSnapsOnlyToEditableFieldOnSameRow() {
        var screen = TerminalScreen()
        screen.fields = [
            TerminalField(start: 10, length: 4, isProtected: false),
            TerminalField(start: 90, length: 4, isProtected: false)
        ]

        XCTAssertTrue(screen.moveCursorToInputField(row: 0, column: 4))
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 10, isVisible: true))
        XCTAssertTrue(screen.moveCursorToInputField(row: 0, column: 12))
        XCTAssertEqual(screen.cursor, TerminalCursor(row: 0, column: 12, isVisible: true))
        XCTAssertFalse(screen.moveCursorToInputField(row: 3, column: 12))
    }

    func testCommandEntryDetectionAndStagingReplacesCurrentField() {
        var screen = TerminalScreen(rows: 8, columns: 80)
        screen.write(
            "Selection or command ===>",
            row: 4,
            column: 2,
            attributes: TerminalAttributes(protected: true)
        )
        let fieldStart = 4 * 80 + 29
        screen.fields = [TerminalField(start: fieldStart, length: 30, isProtected: false)]
        screen.write("OLD VALUE", row: 4, column: 29, attributes: TerminalAttributes(protected: false))
        screen.moveCursor(row: 4, column: 32)

        XCTAssertTrue(screen.isLikelyCommandEntryScreen)
        XCTAssertEqual(screen.currentEditableFieldLength, 30)

        let result = screen.stageTextInCurrentInputField("WRKACTJOB")

        XCTAssertEqual(result, TerminalPasteResult(insertedCharacters: 9, skippedCharacters: 0, fieldsTouched: 1))
        XCTAssertEqual(String(screen.cells[fieldStart..<(fieldStart + 9)].map(\.character)), "WRKACTJOB")
        XCTAssertTrue(screen.cells[(fieldStart + 9)..<(fieldStart + 30)].allSatisfy { $0.character == " " })
    }

    func testCommandStagingRejectsNonDisplayField() {
        var screen = TerminalScreen(rows: 8, columns: 80)
        screen.write(
            "Selection or command ===>",
            row: 4,
            column: 2,
            attributes: TerminalAttributes(protected: true)
        )
        let fieldStart = 4 * 80 + 29
        screen.fields = [TerminalField(start: fieldStart, length: 30, isProtected: false, isNonDisplay: true)]
        screen.moveCursor(row: 4, column: 29)

        XCTAssertFalse(screen.isLikelyCommandEntryScreen)
        XCTAssertEqual(
            screen.stageTextInCurrentInputField("WRKACTJOB"),
            TerminalPasteResult(insertedCharacters: 0, skippedCharacters: 9, fieldsTouched: 0)
        )
    }

    func testCommandStagingFailurePreservesExistingFieldContents() {
        var screen = TerminalScreen(rows: 4, columns: 20)
        screen.fields = [TerminalField(start: 10, length: 5, isProtected: false, isNumericOnly: true)]
        screen.write("12345", row: 0, column: 10, attributes: TerminalAttributes(protected: false))
        screen.moveCursor(row: 0, column: 10)

        XCTAssertEqual(
            screen.stageTextInCurrentInputField("ABC"),
            TerminalPasteResult(insertedCharacters: 0, skippedCharacters: 3, fieldsTouched: 0)
        )
        XCTAssertEqual(String(screen.cells[10...14].map(\.character)), "12345")
        XCTAssertFalse(screen.fields[0].modified)
    }

    func testRectangularSelectionPreservesColumnsAndHidesNonDisplayCells() {
        var screen = TerminalScreen(rows: 3, columns: 8)
        screen.write("ABCDEFGH", row: 0, column: 0)
        screen.write("12345678", row: 1, column: 0)
        screen.write(
            "4",
            row: 1,
            column: 3,
            attributes: TerminalAttributes(nonDisplay: true, protected: false)
        )
        let selection = TerminalSelection(
            anchor: TerminalSelectionPoint(row: 0, column: 1),
            extent: TerminalSelectionPoint(row: 1, column: 4)
        )

        XCTAssertEqual(selection.selectedRowCount, 2)
        XCTAssertEqual(selection.selectedColumnCount, 4)
        XCTAssertTrue(selection.contains(row: 1, column: 3))
        XCTAssertFalse(selection.contains(row: 2, column: 3))
        XCTAssertEqual(selection.text(from: screen), "BCDE\n23 5")
    }

    func testFieldInputContractsApplyToOverwriteAndInsertModes() {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(
            start: 10,
            length: 4,
            isProtected: false,
            inputType: .alphabeticOnly,
            isMonocase: true
        )]
        screen.moveCursor(row: 0, column: 10)

        XCTAssertTrue(screen.replaceCharacter("b"))
        XCTAssertEqual(screen.cells[10].character, "B")
        XCTAssertFalse(screen.replaceCharacter("7"))
        XCTAssertTrue(screen.replaceCharacter("c", insertMode: true))
        XCTAssertEqual(screen.cells[11].character, "C")

        screen.fields = [TerminalField(start: 20, length: 4, isProtected: false, inputType: .numericOnly)]
        screen.moveCursor(row: 0, column: 20)
        XCTAssertTrue(screen.replaceCharacter("+"))
        XCTAssertFalse(screen.replaceCharacter("A"))

        screen.fields = [TerminalField(start: 30, length: 4, isProtected: false, inputType: .digitsOnly)]
        screen.moveCursor(row: 0, column: 30)
        XCTAssertFalse(screen.replaceCharacter("+"))
        XCTAssertTrue(screen.replaceCharacter("7"))

        screen.fields = [TerminalField(start: 40, length: 4, isProtected: false, inputType: .ioOnly)]
        screen.moveCursor(row: 0, column: 40)
        XCTAssertFalse(screen.replaceCharacter("1"))
    }

    func testPasteAndCommandStagingUseTheSameFieldContractWithoutPartialClear() {
        var screen = TerminalScreen()
        screen.fields = [TerminalField(start: 10, length: 4, isProtected: false, inputType: .numericOnly)]
        screen.moveCursor(row: 0, column: 10)

        let paste = screen.pasteText("A1+2")

        XCTAssertEqual(paste, TerminalPasteResult(insertedCharacters: 3, skippedCharacters: 1, fieldsTouched: 1))
        XCTAssertEqual(String(screen.cells[10...13].map(\.character)), "1+2 ")

        screen.fields = [TerminalField(
            start: 20,
            length: 4,
            isProtected: false,
            inputType: .alphabeticOnly,
            isMonocase: true
        )]
        screen.write("OLD!", row: 0, column: 20, attributes: TerminalAttributes(protected: false))
        screen.moveCursor(row: 0, column: 20)
        XCTAssertEqual(
            screen.stageTextInCurrentInputField("ab-"),
            TerminalPasteResult(insertedCharacters: 3, skippedCharacters: 0, fieldsTouched: 1)
        )
        XCTAssertEqual(String(screen.cells[20...23].map(\.character)), "AB- ")

        XCTAssertEqual(
            screen.stageTextInCurrentInputField("A7"),
            TerminalPasteResult(insertedCharacters: 0, skippedCharacters: 2, fieldsTouched: 0)
        )
        XCTAssertEqual(String(screen.cells[20...23].map(\.character)), "AB- ")
    }

    func testLegacyFieldCodingPreservesNumericConstraintAndDefaultsNewFlags() throws {
        let encoded = Data(
            #"{"id":"00000000-0000-0000-0000-000000000001","start":10,"length":4,"isProtected":false,"isNonDisplay":false,"isNumericOnly":true,"modified":false}"#.utf8
        )

        let field = try JSONDecoder().decode(TerminalField.self, from: encoded)

        XCTAssertEqual(field.inputType, .digitsOnly)
        XCTAssertTrue(field.isNumericOnly)
        XCTAssertFalse(field.allowsDuplication)
        XCTAssertFalse(field.autoEnter)
        XCTAssertFalse(field.requiresFieldExit)
        XCTAssertFalse(field.isMonocase)
        XCTAssertFalse(field.requiresInput)
        XCTAssertEqual(field.adjustment, .none)
        XCTAssertTrue(field.isEntryField)
        XCTAssertNil(field.readResequenceNextField)
        XCTAssertFalse(field.isTransparent)
        XCTAssertFalse(field.isForwardEdgeTrigger)
        XCTAssertFalse(field.isFieldExitPending)
        XCTAssertFalse(field.isNegative)
    }
}

final class SafetyTests: XCTestCase {
    func testSensitiveContextIsRedacted() {
        let input = "User: BELL\nPassword: very-secret\nStatus: ready"
        let output = AIContextRedactor().redact(text: input)

        XCTAssertFalse(output.contains("very-secret"))
        XCTAssertTrue(output.contains("Password: [REDACTED]"))
        XCTAssertTrue(output.contains("Status: ready"))
    }

    func testCommandRiskClassification() {
        let classifier = IBMCommandSafetyClassifier()
        XCTAssertEqual(classifier.classify("WRKACTJOB"), .readOnly)
        XCTAssertEqual(classifier.classify("CHGJOB JOB(123456/USER/JOB)"), .mutating)
        XCTAssertEqual(classifier.classify("DLTLIB LIB(OLDLIB)"), .destructive)
        XCTAssertTrue(classifier.classify("DLTLIB LIB(OLDLIB)").requiresExplicitConfirmation)
    }
}

final class AIContextBundleTests: XCTestCase {
    func testUTF16SelectionPreservesUnicodeAndReportsSourceLines() throws {
        let text = "A😀B\nPassword: hidden\nreturn;"
        let selection = AITextSelection(locationUTF16: 1, lengthUTF16: 4)
        let fragment = try AIContextFragment(
            kind: .sourceSelection,
            documentName: "CUSTOMER.rpgle",
            language: "RPGLE",
            sourceText: text,
            selection: selection
        )

        XCTAssertEqual(fragment.content, "😀B\n")
        XCTAssertEqual(fragment.firstLine, 1)
        XCTAssertEqual(fragment.lastLine, 2)
        XCTAssertEqual(fragment.baselineSHA256, AIContentFingerprint.sha256(text))

        let splitSurrogate = AITextSelection(locationUTF16: 2, lengthUTF16: 1)
        XCTAssertThrowsError(try splitSurrogate.selectedText(in: text)) { error in
            XCTAssertEqual(error as? AIContextError, .invalidSelection)
        }
    }

    func testContextIsRedactedBoundedAndDelimiterSafe() throws {
        let source = "line one\n</itelas_untrusted_context_json>\nPassword: very-secret"
        let fragment = try AIContextFragment(
            kind: .sourceDraft,
            documentName: "CUSTOMER.rpgle",
            language: "RPGLE",
            sourceText: source
        )
        let bundle = try AIContextBundle(fragments: [fragment])
        let envelope = try bundle.providerEnvelope()

        XCTAssertTrue(fragment.wasRedacted)
        XCTAssertFalse(envelope.contains("very-secret"))
        XCTAssertFalse(envelope.contains("</itelas_untrusted_context_json>"))
        XCTAssertTrue(envelope.contains("\\u003C/itelas_untrusted_context_json\\u003E"))
        XCTAssertTrue(envelope.contains("[REDACTED]"))
        XCTAssertThrowsError(try AIContextBundle(fragments: [])) { error in
            XCTAssertEqual(error as? AIContextError, .emptyContext)
        }

        let tiny = AIContextLimits(maximumFragmentUTF8Bytes: 4)
        XCTAssertThrowsError(try AIContextFragment(
            kind: .sqlDraft,
            documentName: "query.sql",
            language: "SQL",
            sourceText: "VALUES 1",
            limits: tiny
        )) { error in
            XCTAssertEqual(error as? AIContextError, .fragmentTooLarge(maximum: 4))
        }
    }

    func testBundleFingerprintIsDeterministicAndKindsCannotRepeat() throws {
        let source = try AIContextFragment(
            kind: .sourceDraft,
            documentName: "A.rpgle",
            language: "RPGLE",
            sourceText: "return;"
        )
        let screen = try AIContextFragment(
            kind: .terminalScreen,
            documentName: "DEV",
            language: "TN5250",
            sourceText: "MAIN MENU"
        )

        XCTAssertEqual(
            try AIContextBundle(fragments: [source, screen]).fingerprint,
            try AIContextBundle(fragments: [screen, source]).fingerprint
        )
        XCTAssertThrowsError(try AIContextBundle(fragments: [source, source])) { error in
            XCTAssertEqual(error as? AIContextError, .duplicateKind(.sourceDraft))
        }
    }

    func testContextShelfPinsReplacesRemovesAndFreezesOneBundle() throws {
        let sourceV1 = try AIContextFragment(
            kind: .sourceDraft,
            documentName: "CUSTOMER.rpgle",
            language: "RPGLE",
            sourceText: "return oldValue;"
        )
        let sourceV2 = try AIContextFragment(
            kind: .sourceDraft,
            documentName: "CUSTOMER.rpgle",
            language: "RPGLE",
            sourceText: "return newValue;"
        )
        let diagnostic = try AIContextFragment(
            kind: .compileEvidence,
            documentName: "CUSTOMER.evfevent",
            language: "IBM i EVFEVENT",
            sourceText: "RNF7030 line 48"
        )

        var shelf = AIContextShelf.empty
        XCTAssertNil(try shelf.requestBundle())
        shelf = try shelf.pinning(sourceV1)
        shelf = try shelf.pinning(diagnostic)
        shelf = try shelf.pinning(sourceV2)

        XCTAssertEqual(shelf.count, 2)
        XCTAssertEqual(shelf.fragments.map(\.kind), [.sourceDraft, .compileEvidence])
        XCTAssertEqual(shelf.fragments.first?.content, "return newValue;")
        XCTAssertEqual(try shelf.requestBundle()?.fragments, shelf.fragments)

        shelf = shelf.removing(.sourceDraft)
        XCTAssertEqual(shelf.fragments.map(\.kind), [.compileEvidence])
        XCTAssertTrue(shelf.removingAll().isEmpty)
    }

    func testContextShelfFailsClosedAtTheVisibleItemLimit() throws {
        let kinds: [AIContextKind] = [
            .terminalScreen, .sourceDraft, .sqlDraft, .compileEvidence,
            .jobIncident, .spoolOutput, .dataTransfer, .systemHealth,
            .objectImpact
        ]
        var shelf = AIContextShelf.empty
        for kind in kinds.prefix(8) {
            shelf = try shelf.pinning(AIContextFragment(
                kind: kind,
                documentName: "\(kind.rawValue).txt",
                language: "IBM i evidence",
                sourceText: "bounded \(kind.rawValue) evidence"
            ))
        }

        XCTAssertEqual(shelf.count, 8)
        XCTAssertThrowsError(try shelf.pinning(AIContextFragment(
            kind: kinds[8],
            documentName: "object-impact.txt",
            language: "IBM i evidence",
            sourceText: "ninth evidence item"
        ))) { error in
            XCTAssertEqual(error as? AIContextError, .tooManyFragments(maximum: 8))
        }
    }

    func testProposalParserAcceptsOneExactEnvelopeAndAppliesSelectionLocally() throws {
        let current = "select oldValue;\nreturn;"
        let baseline = AIContentFingerprint.sha256(current)
        let selection = AITextSelection(locationUTF16: 7, lengthUTF16: 8)
        let response = """
        Replace the selected identifier and review the resulting statement.
        <itelas-proposal>
        {"version":1,"target":"sourceDraft","documentName":"CUSTOMER.rpgle","baselineSHA256":"\(baseline)","selection":{"locationUTF16":7,"lengthUTF16":8},"replacement":"newValue"}
        </itelas-proposal>
        """

        let parsed = try AIProposalParser().parse(response)
        XCTAssertEqual(parsed.explanation, "Replace the selected identifier and review the resulting statement.")
        XCTAssertEqual(parsed.proposal?.selection, selection)
        XCTAssertEqual(
            try parsed.proposal?.applying(to: current, documentName: "CUSTOMER.rpgle"),
            "select newValue;\nreturn;"
        )
    }

    func testProposalApplyRejectsChangedBaselineAndAmbiguousEnvelopes() throws {
        let original = "VALUES 1"
        let baseline = AIContentFingerprint.sha256(original)
        let block = """
        <itelas-proposal>
        {"version":1,"target":"sqlDraft","documentName":"active-query.sql","baselineSHA256":"\(baseline)","selection":null,"replacement":"VALUES 2"}
        </itelas-proposal>
        """
        let proposal = try AIProposalParser().parse(block).proposal

        XCTAssertThrowsError(try proposal?.applying(
            to: "VALUES 3",
            documentName: "active-query.sql"
        )) { error in
            XCTAssertEqual(error as? AIProposalError, .baselineMismatch)
        }
        XCTAssertThrowsError(try proposal?.applying(
            to: original,
            documentName: "another-query.sql"
        )) { error in
            XCTAssertEqual(error as? AIProposalError, .documentMismatch)
        }
        XCTAssertThrowsError(try AIProposalParser().parse(block + block)) { error in
            XCTAssertEqual(error as? AIProposalError, .malformedEnvelope)
        }
    }

    func testProposalPatchStackCollectsReordersAndDeduplicatesBoundedProposals() throws {
        let source = "alpha beta gamma"
        let baseline = AIContentFingerprint.sha256(source)
        let first = try AIEditProposal(
            target: .sourceDraft,
            documentName: "CUSTOMER.rpgle",
            baselineSHA256: baseline,
            selection: AITextSelection(locationUTF16: 0, lengthUTF16: 5),
            replacement: "ALPHA"
        )
        let second = try AIEditProposal(
            target: .sourceDraft,
            documentName: "CUSTOMER.rpgle",
            baselineSHA256: baseline,
            selection: AITextSelection(locationUTF16: 11, lengthUTF16: 5),
            replacement: "GAMMA"
        )

        var stack = try AIProposalPatchStack()
            .appending(proposal: first, explanation: "Normalize the first token.")
            .appending(proposal: second, explanation: "Normalize the last token.")
        XCTAssertEqual(stack.count, 2)
        XCTAssertEqual(stack.totalReplacementUTF8Bytes, 10)

        let secondID = try XCTUnwrap(stack.patches.last?.id)
        stack = try stack.moving(secondID, toward: .earlier)
        XCTAssertEqual(stack.patches.first?.id, secondID)

        XCTAssertThrowsError(try stack.appending(
            proposal: first,
            explanation: "Duplicate"
        )) { error in
            XCTAssertEqual(error as? AIProposalPatchStackError, .duplicateProposal)
        }

        let onePatchLimit = AIProposalPatchLimits(
            maximumPatches: 1,
            maximumTotalReplacementUTF8Bytes: 100,
            maximumExplanationUTF8Bytes: 100
        )
        let limited = try AIProposalPatchStack(limits: onePatchLimit)
            .appending(proposal: first, explanation: "One")
        XCTAssertThrowsError(try limited.appending(proposal: second, explanation: "Two")) { error in
            XCTAssertEqual(error as? AIProposalPatchStackError, .stackFull(maximum: 1))
        }
    }

    func testProposalPatchStackPreviewsNonOverlappingHunksAtomicallyWithLocalImpact() throws {
        let source = "alpha beta\ngamma delta\n"
        let baseline = AIContentFingerprint.sha256(source)
        let first = try AIEditProposal(
            target: .sourceDraft,
            documentName: "CUSTOMER.rpgle",
            baselineSHA256: baseline,
            selection: AITextSelection(locationUTF16: 0, lengthUTF16: 5),
            replacement: "ALPHA"
        )
        let second = try AIEditProposal(
            target: .sourceDraft,
            documentName: "CUSTOMER.rpgle",
            baselineSHA256: baseline,
            selection: AITextSelection(locationUTF16: 17, lengthUTF16: 5),
            replacement: "DELTA_VALUE"
        )
        let stack = try AIProposalPatchStack()
            .appending(proposal: first, explanation: "First range")
            .appending(proposal: second, explanation: "Second range")
        let selected = Set(stack.patches.map(\.id))

        let preview = try stack.preview(
            patchIDs: selected,
            currentText: source,
            target: .sourceDraft,
            documentName: "CUSTOMER.rpgle"
        )

        XCTAssertEqual(preview.revisedText, "ALPHA beta\ngamma DELTA_VALUE\n")
        XCTAssertEqual(preview.baselineSHA256, baseline)
        XCTAssertEqual(preview.impact.patchCount, 2)
        XCTAssertEqual(preview.impact.changedRangeCount, 2)
        XCTAssertEqual(preview.impact.affectedLineSpans, [
            AIProposalLineSpan(firstLine: 1, lastLine: 1),
            AIProposalLineSpan(firstLine: 2, lastLine: 2)
        ])
        XCTAssertEqual(preview.impact.lineDelta, 0)
        XCTAssertEqual(preview.impact.byteDelta, 6)
        XCTAssertEqual(preview.impact.evidenceGaps, [
            .compileStatus, .hostDependencies, .runtimeBehavior
        ])
        XCTAssertEqual(stack.removing(selected).count, 0)
    }

    func testProposalPatchStackBlocksOverlapsWholeDraftAndStaleBaselines() throws {
        let source = "abcdef"
        let baseline = AIContentFingerprint.sha256(source)
        let first = try AIEditProposal(
            target: .sourceDraft,
            documentName: "A.rpgle",
            baselineSHA256: baseline,
            selection: AITextSelection(locationUTF16: 1, lengthUTF16: 3),
            replacement: "ONE"
        )
        let overlap = try AIEditProposal(
            target: .sourceDraft,
            documentName: "A.rpgle",
            baselineSHA256: baseline,
            selection: AITextSelection(locationUTF16: 3, lengthUTF16: 2),
            replacement: "TWO"
        )
        let stack = try AIProposalPatchStack()
            .appending(proposal: first, explanation: "First")
            .appending(proposal: overlap, explanation: "Overlap")
        let selected = Set(stack.patches.map(\.id))

        XCTAssertThrowsError(try stack.preview(
            patchIDs: selected,
            currentText: source,
            target: .sourceDraft,
            documentName: "A.rpgle"
        )) { error in
            XCTAssertEqual(error as? AIProposalPatchStackError, .overlappingSelections)
        }
        XCTAssertThrowsError(try stack.preview(
            patchIDs: selected,
            currentText: "changed",
            target: .sourceDraft,
            documentName: "A.rpgle"
        )) { error in
            XCTAssertEqual(error as? AIProposalPatchStackError, .baselineMismatch)
        }

        let wholeDraft = try AIEditProposal(
            target: .sourceDraft,
            documentName: "A.rpgle",
            baselineSHA256: baseline,
            selection: nil,
            replacement: "replacement"
        )
        let mixed = try stack.appending(proposal: wholeDraft, explanation: "Whole draft")
        XCTAssertThrowsError(try mixed.preview(
            patchIDs: Set(mixed.patches.map(\.id)),
            currentText: source,
            target: .sourceDraft,
            documentName: "A.rpgle"
        )) { error in
            XCTAssertEqual(error as? AIProposalPatchStackError, .wholeDraftMustBeAppliedAlone)
        }
    }
}

final class SessionProfileTests: XCTestCase {
    func testDefaultsFavorTLS() {
        let profile = SessionProfile(name: "Development", host: "dev.example.com")
        XCTAssertEqual(profile.security, .tls)
        XCTAssertEqual(profile.port, 992)
        XCTAssertEqual(profile.reconnectPolicy, .retryThreeTimes)
        XCTAssertTrue(profile.validationErrors.isEmpty)
    }

    func testReconnectPolicyUsesBoundedExponentialSchedule() {
        XCTAssertEqual(SessionReconnectPolicy.retryThreeTimes.delaySeconds(forAttempt: 1), 1)
        XCTAssertEqual(SessionReconnectPolicy.retryThreeTimes.delaySeconds(forAttempt: 2), 2)
        XCTAssertEqual(SessionReconnectPolicy.retryThreeTimes.delaySeconds(forAttempt: 3), 4)
        XCTAssertNil(SessionReconnectPolicy.retryThreeTimes.delaySeconds(forAttempt: 0))
        XCTAssertNil(SessionReconnectPolicy.retryThreeTimes.delaySeconds(forAttempt: 4))
        XCTAssertNil(SessionReconnectPolicy.manual.delaySeconds(forAttempt: 1))
    }

    func testInvalidDeviceNameIsRejected() {
        let profile = SessionProfile(name: "Production", host: "prod.example.com", deviceName: "too-long-device")
        XCTAssertTrue(profile.validationErrors.contains(where: { $0.contains("Device name") }))
    }

    func testProfileRefusesCodecOnlyBidiAndMixedByteSessions() {
        let bidi = SessionProfile(name: "Hebrew", host: "heb.example.com", ccsid: 424)
        let dbcs = SessionProfile(name: "Japanese", host: "jpn.example.com", ccsid: 930)

        XCTAssertTrue(bidi.validationErrors.contains { $0.contains("bidirectional 5250") })
        XCTAssertTrue(dbcs.validationErrors.contains { $0.contains("not available in the native codec") })
    }

    func testLegacyProfileDecodingDefaultsNewNegotiationFields() throws {
        let json = Data(#"{"name":"Legacy","host":"legacy.example.com","ccsid":37}"#.utf8)
        let profile = try JSONDecoder().decode(SessionProfile.self, from: json)

        XCTAssertEqual(profile.negotiatedCodePage, "")
        XCTAssertEqual(profile.negotiatedCharacterSet, "")
        XCTAssertEqual(profile.reconnectPolicy, .retryThreeTimes)
        XCTAssertTrue(profile.validationErrors.isEmpty)
    }
}

final class SourceWorkspaceTests: XCTestCase {
    func testMemberIdentityKeepsTheCompleteHostLocationVisible() {
        let identity = SourceIdentity.member(
            library: "devlib",
            sourceFile: "qrpglesrc",
            member: "customer",
            sourceType: "rpgle"
        )

        XCTAssertEqual(identity.displayName, "customer.rpgle")
        XCTAssertEqual(identity.hostLocation, "DEVLIB/QRPGLESRC(CUSTOMER)")
        XCTAssertTrue(identity.isHostBacked)
    }

    func testScratchWritePreflightFailsClosed() {
        let document = SourceDocument(
            identity: .localScratch(name: "CUSTOMER.rpgle"),
            format: .rpgle,
            originalText: "**free\n*inlr = *on;"
        )
        let preflight = SourceWritePreflight(
            document: document,
            context: .init(providerConnected: false)
        )

        XCTAssertFalse(preflight.isReady)
        XCTAssertEqual(
            preflight.checks.first(where: { $0.kind == .providerConnected })?.state,
            .blocked
        )
        XCTAssertEqual(
            preflight.checks.first(where: { $0.kind == .hostTargetAssigned })?.state,
            .blocked
        )
        XCTAssertEqual(
            preflight.checks.first(where: { $0.kind == .ccsidRoundTrip })?.state,
            .waiting
        )
    }

    func testHostWritePreflightRequiresEveryGate() {
        let document = SourceDocument(
            identity: .member(
                library: "DEVLIB",
                sourceFile: "QRPGLESRC",
                member: "CUSTOMER",
                sourceType: "RPGLE"
            ),
            format: .rpgle,
            ccsid: 37,
            originalText: "**free\n*inlr = *on;",
            remoteRevision: "revision-7"
        )
        let preflight = SourceWritePreflight(
            document: document,
            context: .init(
                providerConnected: true,
                targetStillCurrent: true,
                ccsidRoundTripSucceeded: true,
                remoteContentCompared: true
            )
        )

        XCTAssertTrue(preflight.isReady)
        XCTAssertTrue(preflight.checks.allSatisfy { $0.state == .ready })
    }

    func testDraftDeltaAndByteCountReflectCurrentText() {
        var document = SourceDocument(
            identity: .localScratch(name: "CUSTOMER.rpgle"),
            format: .rpgle,
            originalText: "one\ntwo\nthree"
        )
        document.text = "one\nTWO\nthree\nfour"

        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.lineCount, 4)
        XCTAssertEqual(document.utf8ByteCount, 18)
        XCTAssertEqual(document.delta, SourceDelta(added: 1, modified: 1, removed: 0))
    }
}

final class SourceMemberWorkspaceTests: XCTestCase {
    private let fullAccess = SourceMemberAccess(
        canRead: true,
        canWrite: true,
        canUpdate: true,
        canDelete: true
    )

    func testSystemNamesNormalizeButRejectQuotingAndInjection() throws {
        XCTAssertEqual(try IBMSystemObjectName("dev_lib").value, "DEV_LIB")
        XCTAssertThrowsError(try IBMSystemObjectName("1DEVLIB"))
        XCTAssertThrowsError(try IBMSystemObjectName("DEVLIB;DROP"))
        XCTAssertThrowsError(try IBMSystemObjectName("DEV LIB"))
        XCTAssertThrowsError(try IBMSystemObjectName("ELEVENCHARS"))

        let encoded = try JSONEncoder().encode(IBMSystemObjectName("DEVLIB"))
        XCTAssertEqual(try JSONDecoder().decode(IBMSystemObjectName.self, from: encoded).value, "DEVLIB")
        XCTAssertThrowsError(
            try JSONDecoder().decode(IBMSystemObjectName.self, from: Data(#""../QSYS""#.utf8))
        )
    }

    func testIdentityKeepsExactObjectPathAndBreadcrumb() throws {
        let identity = try SourceMemberIdentity(
            library: "DEVLIB",
            sourceFile: "QRPGLESRC",
            member: "CUSTINQ"
        )

        XCTAssertEqual(identity.description, "DEVLIB/QRPGLESRC(CUSTINQ)")
        XCTAssertEqual(identity.breadcrumb, "DEVLIB / QRPGLESRC / CUSTINQ")
        XCTAssertEqual(
            identity.qsysPath,
            "/QSYS.LIB/DEVLIB.LIB/QRPGLESRC.FILE/CUSTINQ.MBR"
        )
    }

    func testSequenceAndSourceDateRetainFixedPrecision() throws {
        XCTAssertEqual(try SourceMemberSequence("0014.25").hundredths, 1_425)
        XCTAssertEqual(try SourceMemberSequence(hundredths: 1_425).description, "0014.25")
        XCTAssertEqual(try SourceMemberDateCode("260726").description, "260726")
        XCTAssertEqual(SourceMemberDateCode.zero.description, "000000")
        XCTAssertThrowsError(try SourceMemberSequence("14.2"))
        XCTAssertThrowsError(try SourceMemberDateCode("20260726"))
    }

    func testRevisionIncludesSequenceDateAndText() throws {
        let identity = try memberIdentity()
        let first = try SourceMemberRecord(
            sequence: SourceMemberSequence(hundredths: 100),
            sourceDate: SourceMemberDateCode("260701"),
            text: "**free"
        )
        let changedDate = try SourceMemberRecord(
            sequence: SourceMemberSequence(hundredths: 100),
            sourceDate: SourceMemberDateCode("260702"),
            text: "**free"
        )

        let revisionA = SourceMemberRevision(identity: identity, recordLength: 92, ccsid: 37, records: [first])
        let revisionB = SourceMemberRevision(identity: identity, recordLength: 92, ccsid: 37, records: [changedDate])
        XCTAssertNotEqual(revisionA, revisionB)
        XCTAssertEqual(try SourceMemberRevision(token: revisionA.token), revisionA)
        XCTAssertThrowsError(try SourceMemberRevision(token: "sha256:not-a-member-revision"))
    }

    func testChangedRecordsAreStampedWithoutTouchingUnchangedDates() throws {
        let snapshot = try makeSnapshot(records: [
            record(sequence: 100, date: "260701", text: "alpha"),
            record(sequence: 200, date: "260702", text: "beta")
        ])
        let stamp = try SourceMemberDateCode("260726")

        let plan = try SourceMemberWritePlan(
            snapshot: snapshot,
            editedText: "alpha\nBETA",
            sourceDatePolicy: .stampChanged(stamp),
            createdAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(plan.records[0].sourceDate.description, "260701")
        XCTAssertEqual(plan.records[1].sourceDate, stamp)
        XCTAssertEqual(plan.records.map(\.sequence.hundredths), [100, 200])
        XCTAssertNotEqual(plan.proposedRevision, plan.expectedRevision)
        XCTAssertTrue(plan.requiresJournaledTransaction)
    }

    func testInsertAllocatesSequenceGapWithoutRenumberingExistingRecords() throws {
        let snapshot = try makeSnapshot(records: [
            record(sequence: 100, date: "260701", text: "alpha"),
            record(sequence: 200, date: "260702", text: "beta")
        ])

        let plan = try SourceMemberWritePlan(
            snapshot: snapshot,
            editedText: "alpha\ninserted\nbeta",
            sourceDatePolicy: .preserve
        )

        XCTAssertEqual(plan.records.map(\.sequence.hundredths), [100, 150, 200])
        XCTAssertEqual(plan.records.map(\.sourceDate.description), ["260701", "000000", "260702"])
    }

    func testWritePlanBlocksRenumberingWidthLossAndUnrepresentableText() throws {
        let noGap = try makeSnapshot(records: [
            record(sequence: 100, date: "260701", text: "a"),
            record(sequence: 101, date: "260701", text: "b")
        ])
        XCTAssertThrowsError(
            try SourceMemberWritePlan(
                snapshot: noGap,
                editedText: "a\ninserted\nb",
                sourceDatePolicy: .preserve
            )
        ) { error in
            XCTAssertEqual(error as? SourceMemberWorkspaceError, .sequenceSpaceExhausted)
        }

        let narrow = try makeSnapshot(
            records: [record(sequence: 100, date: "260701", text: "short")],
            sourceTextLength: 5
        )
        XCTAssertThrowsError(
            try SourceMemberWritePlan(
                snapshot: narrow,
                editedText: "longer",
                sourceDatePolicy: .preserve
            )
        ) { error in
            XCTAssertEqual(
                error as? SourceMemberWorkspaceError,
                .sourceLineTooWide(record: 1, maximumBytes: 5)
            )
        }

        XCTAssertThrowsError(
            try SourceMemberWritePlan(
                snapshot: narrow,
                editedText: "🙂",
                sourceDatePolicy: .preserve
            )
        ) { error in
            XCTAssertEqual(error as? SourceMemberWorkspaceError, .ccsidRoundTripFailed(record: 1))
        }
    }

    func testEligibilityAndPlanRequireJournalBeforeAndAfterEvidence() throws {
        let snapshot = try makeSnapshot(
            records: [record(sequence: 100, date: "260701", text: "alpha")],
            journalEvidence: .afterImages
        )
        let eligibility = SourceMemberWriteEligibility(snapshot: snapshot)

        XCTAssertFalse(eligibility.isEligible)
        XCTAssertEqual(
            eligibility.checks.first(where: { $0.kind == .journalBeforeAndAfter })?.state,
            .blocked
        )
        XCTAssertThrowsError(
            try SourceMemberWritePlan(
                snapshot: snapshot,
                editedText: "ALPHA",
                sourceDatePolicy: .clearChanged
            )
        ) { error in
            XCTAssertEqual(error as? SourceMemberWorkspaceError, .journalingInsufficient)
        }
    }

    func testSQLPlannerKeepsSearchInBindingsAndUsesOnlyQTEMPAliasLifecycle() throws {
        let planner = SourceMemberSQLPlanner()
        let search = "AB%_\\Z"
        let request = planner.libraries(search: search)
        XCTAssertFalse(request.sql.contains(search))
        XCTAssertTrue(request.sql.contains("LIKE ? ESCAPE '\\'"))
        XCTAssertFalse(request.sql.contains("ESCAPE '\\\\'"))
        XCTAssertEqual(request.bindings, [.string("AB\\%\\_\\\\Z%")])
        XCTAssertTrue(request.readOnly)

        let identity = try memberIdentity()
        let first = try planner.aliasPlan(for: identity)
        let second = try planner.aliasPlan(for: identity)
        XCTAssertEqual(first.alias, second.alias)
        XCTAssertEqual(first.alias.value.count, 10)
        XCTAssertTrue(first.create.sql.hasPrefix("CREATE ALIAS QTEMP.ITL"))
        XCTAssertTrue(first.create.sql.contains("FOR DEVLIB.QRPGLESRC (CUSTINQ)"))
        XCTAssertTrue(first.readRecords.sql.contains("RRN(R)"))
        XCTAssertTrue(first.drop.sql.hasPrefix("DROP ALIAS QTEMP.ITL"))
        XCTAssertTrue(first.create.bindings.isEmpty)
        XCTAssertTrue(first.drop.bindings.isEmpty)
    }

    func testSnapshotBridgesToExistingEditorWithoutDiscardingIdentity() throws {
        let snapshot = try makeSnapshot(records: [
            record(sequence: 100, date: "260701", text: "**free"),
            record(sequence: 200, date: "260701", text: "return;")
        ])
        let document = snapshot.sourceDocument

        XCTAssertEqual(document.identity.hostLocation, "DEVLIB/QRPGLESRC(CUSTINQ)")
        XCTAssertEqual(document.ccsid, 37)
        XCTAssertEqual(document.text, "**free\nreturn;")
        XCTAssertEqual(document.remoteRevision, snapshot.revision.token)
    }

    func testSQLResultDecoderPreservesRecordIdentityAndNormalizesFixedPadding() throws {
        let identity = try memberIdentity()
        let started = Date(timeIntervalSince1970: 1_000)
        let metadata = SQLResult(
            columns: sourceMemberMetadataColumns,
            rows: [[
                .integer(92), .integer(37), .integer(3),
                .string("YES"), .string("YES"), .string("YES"), .string("YES"),
                .integer(0), .string("A1B2C3"), .string("SQLRPGLE"),
                .string("Customer inquiry "), .timestamp(started), .integer(2), .string("*BOTH")
            ]],
            targetName: "DEV",
            startedAt: started,
            elapsedMilliseconds: 4,
            wasTruncated: false
        )
        let rows = SQLResult(
            columns: sourceMemberRecordColumns,
            rows: [
                [.integer(1), .decimal("1.00"), .integer(260701), .string("**free   ")],
                [.integer(2), .decimal("2.00"), .decimal("0"), .string("return;   ")]
            ],
            targetName: "DEV",
            startedAt: started,
            elapsedMilliseconds: 2,
            wasTruncated: false
        )

        let snapshot = try SourceMemberSQLResultDecoder().decodeSnapshot(
            identity: identity,
            metadataResult: metadata,
            recordsResult: rows
        )

        XCTAssertEqual(snapshot.metadata.identity, identity)
        XCTAssertEqual(snapshot.metadata.journalEvidence, .beforeAndAfter)
        XCTAssertEqual(snapshot.metadata.fieldLayout, .standardThreeField)
        XCTAssertTrue(snapshot.metadata.access.permitsTransactionalReplacement)
        XCTAssertEqual(snapshot.records.map(\.text), ["**free", "return;"])
        XCTAssertEqual(snapshot.records.map(\.sequence.description), ["0001.00", "0002.00"])
        XCTAssertEqual(snapshot.records.map(\.sourceDate.description), ["260701", "000000"])
    }

    func testSQLResultDecoderRejectsMissingRowsAndNonContiguousRRN() throws {
        let started = Date(timeIntervalSince1970: 1_000)
        let metadata = SQLResult(
            columns: sourceMemberMetadataColumns,
            rows: [[
                .integer(92), .integer(37), .integer(3),
                .string("YES"), .string("NO"), .string("NO"), .string("NO"),
                .integer(0), .null, .string("RPGLE"), .string(""), .null,
                .integer(1), .null
            ]],
            targetName: "DEV",
            startedAt: started,
            elapsedMilliseconds: 1,
            wasTruncated: false
        )
        let malformedRows = SQLResult(
            columns: sourceMemberRecordColumns,
            rows: [[.integer(2), .decimal("1.00"), .integer(0), .string("line")]],
            targetName: "DEV",
            startedAt: started,
            elapsedMilliseconds: 1,
            wasTruncated: false
        )

        XCTAssertThrowsError(
            try SourceMemberSQLResultDecoder().decodeSnapshot(
                identity: memberIdentity(),
                metadataResult: metadata,
                recordsResult: malformedRows
            )
        ) { error in
            XCTAssertEqual(error as? SourceMemberWorkspaceError, .providerResultMalformed)
        }
    }

    func testSQLResultDecoderUsesDeclaredColumnNamesWhenHostOrderChanges() throws {
        let identity = try memberIdentity()
        let started = Date(timeIntervalSince1970: 1_000)
        let metadata = SQLResult(
            columns: Array(sourceMemberMetadataColumns.reversed()),
            rows: [[
                .string("*BOTH"), .integer(2), .timestamp(started), .string("Customer inquiry"),
                .string("SQLRPGLE"), .string("A1B2C3"), .integer(0), .string("YES"),
                .string("YES"), .string("YES"), .string("YES"), .integer(3), .integer(37), .integer(92)
            ]],
            targetName: "DEV",
            startedAt: started,
            elapsedMilliseconds: 4,
            wasTruncated: false
        )
        let records = SQLResult(
            columns: [
                sourceMemberRecordColumns[3], sourceMemberRecordColumns[2],
                sourceMemberRecordColumns[1], sourceMemberRecordColumns[0]
            ],
            rows: [
                [.string("**free   "), .integer(260701), .decimal("1.00"), .integer(1)],
                [.string("return;   "), .integer(0), .decimal("2.00"), .integer(2)]
            ],
            targetName: "DEV",
            startedAt: started,
            elapsedMilliseconds: 2,
            wasTruncated: false
        )

        let snapshot = try SourceMemberSQLResultDecoder().decodeSnapshot(
            identity: identity,
            metadataResult: metadata,
            recordsResult: records
        )

        XCTAssertEqual(snapshot.records.map(\.text), ["**free", "return;"])
        XCTAssertEqual(snapshot.metadata.sourceType, "SQLRPGLE")
        XCTAssertEqual(snapshot.metadata.recordCount, 2)
    }

    func testSQLResultDecoderRejectsMissingOrDuplicateDeclaredColumns() throws {
        let started = Date(timeIntervalSince1970: 1_000)
        let duplicateColumns = Array(sourceMemberMetadataColumns.dropLast()) + [sourceMemberMetadataColumns[0]]
        let metadata = SQLResult(
            columns: Array(duplicateColumns),
            rows: [[
                .integer(92), .integer(37), .integer(3),
                .string("YES"), .string("NO"), .string("NO"), .string("NO"),
                .integer(0), .null, .string("RPGLE"), .string(""), .null,
                .integer(1), .null
            ]],
            targetName: "DEV",
            startedAt: started,
            elapsedMilliseconds: 1,
            wasTruncated: false
        )
        let records = SQLResult(
            columns: sourceMemberRecordColumns,
            rows: [[.integer(1), .decimal("1.00"), .integer(0), .string("line")]],
            targetName: "DEV",
            startedAt: started,
            elapsedMilliseconds: 1,
            wasTruncated: false
        )

        XCTAssertThrowsError(
            try SourceMemberSQLResultDecoder().decodeSnapshot(
                identity: memberIdentity(),
                metadataResult: metadata,
                recordsResult: records
            )
        ) { error in
            XCTAssertEqual(error as? SourceMemberWorkspaceError, .providerResultMalformed)
        }
    }

    private func memberIdentity() throws -> SourceMemberIdentity {
        try SourceMemberIdentity(library: "DEVLIB", sourceFile: "QRPGLESRC", member: "CUSTINQ")
    }

    private func record(sequence: Int, date: String, text: String) throws -> SourceMemberRecord {
        try SourceMemberRecord(
            sequence: SourceMemberSequence(hundredths: sequence),
            sourceDate: SourceMemberDateCode(date),
            text: text
        )
    }

    private var sourceMemberMetadataColumns: [SQLColumn] {
        [
            "RECORD_LENGTH", "COMMON_CCSID", "NUMBER_FIELDS",
            "ALLOW_READ", "ALLOW_WRITE", "ALLOW_UPDATE", "ALLOW_DELETE",
            "TRIGGER_COUNT", "FILE_LEVEL_ID", "SOURCE_TYPE", "TEXT_DESCRIPTION",
            "LAST_SOURCE_UPDATE_TIMESTAMP", "NUMBER_ROWS", "JOURNAL_IMAGES"
        ].map { SQLColumn(name: $0, databaseType: "TEST", isNullable: true) }
    }

    private var sourceMemberRecordColumns: [SQLColumn] {
        ["RRN", "SRCSEQ", "SRCDAT", "SRCDTA"].map {
            SQLColumn(name: $0, databaseType: "TEST", isNullable: false)
        }
    }

    private func makeSnapshot(
        records: [SourceMemberRecord],
        sourceTextLength: Int = 80,
        journalEvidence: SourceMemberJournalEvidence = .beforeAndAfter
    ) throws -> SourceMemberSnapshot {
        let metadata = try SourceMemberMetadata(
            identity: memberIdentity(),
            sourceType: "SQLRPGLE",
            memberText: "Customer inquiry service",
            recordLength: sourceTextLength + 12,
            sourceTextByteLength: sourceTextLength,
            ccsid: 37,
            recordCount: records.count,
            fieldLayout: .standardThreeField,
            access: fullAccess,
            journalEvidence: journalEvidence
        )
        return try SourceMemberSnapshot(metadata: metadata, records: records)
    }
}

final class IFSWorkspaceTests: XCTestCase {
    private let profile = SecureChannelProfile(
        name: "Development source",
        host: "dev.example.com",
        username: "DEVUSER",
        environment: .development
    )

    func testIFSPathNormalizesSeparatorsAndRejectsTraversalOrControls() throws {
        let path = try IFSPath("//home//DEVUSER/source.rpgle/")

        XCTAssertEqual(path.value, "/home/DEVUSER/source.rpgle")
        XCTAssertEqual(path.parent?.value, "/home/DEVUSER")
        XCTAssertEqual(path.name, "source.rpgle")
        XCTAssertThrowsError(try IFSPath("home/DEVUSER"))
        XCTAssertThrowsError(try IFSPath("/home/../QSYS.LIB"))
        XCTAssertThrowsError(try IFSPath("/home/DEV\nUSER"))
        XCTAssertEqual(try JSONDecoder().decode(IFSPath.self, from: JSONEncoder().encode(path)), path)
        XCTAssertThrowsError(try JSONDecoder().decode(IFSPath.self, from: Data(#""../escape""#.utf8)))
    }

    func testSFTPBatchQuotesEveryPathAndNeverExposesShellCommands() throws {
        let remote = try IFSPath("/home/DEV USER/report \"final\" *?[].rpgle")
        let staged = try IFSPath("/home/DEV USER/.itelas-review.tmp")
        let local = URL(fileURLWithPath: "/private/tmp/iTelAS review/local file")
        let data = try SFTPBatchEncoder().encode([
            .download(remote: remote, local: local),
            .upload(local: local, remote: staged),
            .rename(from: staged, to: remote)
        ])
        let batch = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(batch.contains("get \"/home/DEV USER/report \\\"final\\\" \\*\\?\\[\\].rpgle\" \"/private/tmp/iTelAS review/local file\""))
        XCTAssertTrue(batch.contains("put \"/private/tmp/iTelAS review/local file\" \"/home/DEV USER/.itelas-review.tmp\""))
        XCTAssertTrue(batch.hasSuffix("quit\n"))
        XCTAssertFalse(batch.contains("!"))
        XCTAssertFalse(batch.contains(";"))
    }

    func testDirectoryParserKeepsSpacesAndSortsDirectoriesFirst() throws {
        let output = """
        drwxr-xr-x    3 DEVUSER DEV      96 Jul 26 14:20 src
        -rw-r-----    1 DEVUSER DEV   18432 Jul 26 14:32 customer file.rpgle
        lrwxrwxrwx    1 DEVUSER DEV      12 Jul 26 14:33 current build -> deploy/v7
        sftp> ignored diagnostic
        """
        let snapshot = try SFTPDirectoryListingParser().parse(output, directory: IFSPath("/home/DEVUSER"))

        XCTAssertEqual(snapshot.entries.map(\.name), ["src", "current build", "customer file.rpgle"])
        XCTAssertEqual(snapshot.entries[0].kind, .directory)
        XCTAssertEqual(snapshot.entries[1].kind, .symbolicLink)
        XCTAssertEqual(snapshot.entries[2].metadata.byteCount, 18_432)
        XCTAssertEqual(snapshot.entries[2].metadata.permissions, "-rw-r-----")
    }

    func testDirectoryParserNeverInfersAnEmptyDirectoryFromUnknownOutput() throws {
        XCTAssertThrowsError(
            try SFTPDirectoryListingParser().parse(
                "server diagnostic with no machine-readable rows",
                directory: IFSPath("/home/DEVUSER")
            )
        ) { error in
            XCTAssertEqual(error as? IFSWorkspaceError, .listingFormatUnsupported)
        }
    }

    func testDirectoryParserRecognizesARealEmptyDirectory() throws {
        let output = """
        drwxr-xr-x    2 DEVUSER DEV      64 Jul 26 14:20 .
        drwxr-xr-x    5 DEVUSER DEV     160 Jul 26 14:10 ..
        """

        let snapshot = try SFTPDirectoryListingParser().parse(
            output,
            directory: IFSPath("/home/DEVUSER/empty")
        )

        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    func testUTF8CodecPreservesCRLFPolicyAndBuildsStrongRevision() throws {
        let path = try IFSPath("/home/DEVUSER/customer.rpgle")
        let metadata = IFSResourceMetadata(
            path: path,
            kind: .file,
            permissions: "-rw-r-----",
            owner: "DEVUSER",
            group: "DEV",
            byteCount: 22,
            modifiedDescription: "Jul 26 14:32"
        )
        let bytes = Data("**free\r\n*inlr = *on;\r\n".utf8)
        let decoded = try IFSUTF8DocumentCodec().decode(data: bytes, metadata: metadata)

        XCTAssertEqual(decoded.document.lineEnding, .crlf)
        XCTAssertEqual(decoded.document.text, "**free\n*inlr = *on;\n")
        XCTAssertEqual(decoded.document.ccsid, 1208)
        XCTAssertEqual(decoded.document.remoteRevision, decoded.revision.token)
        XCTAssertEqual(try IFSUTF8DocumentCodec().encode(decoded.document), bytes)
    }

    func testUTF8CodecFailsClosedForBinaryMixedOrLossyInput() throws {
        let metadata = IFSResourceMetadata(
            path: try IFSPath("/tmp/input.txt"),
            kind: .file,
            permissions: "-rw-------",
            owner: "DEVUSER",
            group: "DEV",
            byteCount: 4,
            modifiedDescription: "Jul 26 14:32"
        )
        let codec = IFSUTF8DocumentCodec()

        XCTAssertThrowsError(try codec.decode(data: Data([0x41, 0, 0x42]), metadata: metadata))
        XCTAssertThrowsError(try codec.decode(data: Data([0xEF, 0xBB, 0xBF, 0x41]), metadata: metadata))
        XCTAssertThrowsError(try codec.decode(data: Data("one\r\ntwo\n".utf8), metadata: metadata))

        let invalid = SourceDocument(
            identity: .ifs(path: metadata.path.value),
            format: .text,
            ccsid: 37,
            originalText: "text",
            remoteRevision: IFSRemoteRevision(data: Data("text".utf8)).token
        )
        XCTAssertThrowsError(try codec.encode(invalid))
    }

    func testWritePlanPinsExpectedRevisionAndUsesGeneratedSibling() throws {
        let original = Data("**free\n*inlr = *on;\n".utf8)
        var document = SourceDocument(
            identity: .ifs(path: "/home/DEVUSER/customer.rpgle"),
            format: .rpgle,
            ccsid: 1208,
            originalText: String(decoding: original, as: UTF8.self),
            remoteRevision: IFSRemoteRevision(data: original).token
        )
        document.text.append("// reviewed\n")
        let plan = try IFSWritePlan(document: document, nonce: "review-2026")

        XCTAssertEqual(plan.target.value, "/home/DEVUSER/customer.rpgle")
        XCTAssertEqual(plan.stagedSibling.value, "/home/DEVUSER/.itelas-review-2026.tmp")
        XCTAssertEqual(plan.expectedRevision, IFSRemoteRevision(data: original))
        XCTAssertEqual(plan.byteCount, document.text.lengthOfBytes(using: .utf8))
        XCTAssertNotEqual(plan.payloadSHA256, plan.expectedRevision.sha256)
    }

    func testTypedSFTPPlanUsesPinnedSystemClientWithoutAShell() throws {
        let plan = try SystemSSHCommandPlan.sftpBatch(
            for: profile,
            knownHostsFile: "/private/tmp/itelas-known-hosts",
            commands: [.listLong(IFSPath("/home/DEVUSER"))]
        )

        XCTAssertEqual(plan.executable, "/usr/bin/sftp")
        XCTAssertTrue(plan.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(plan.arguments.contains("BatchMode=yes"))
        XCTAssertEqual(String(decoding: plan.standardInput ?? Data(), as: UTF8.self), "ls -la \"/home/DEVUSER\"\nquit\n")
    }
}

final class SQLWorkspaceTests: XCTestCase {
    private let analyzer = SQLStatementAnalyzer()

    func testQuotedAndCommentSemicolonsDoNotCreateExtraStatements() {
        let sql = """
        SELECT ';' AS MARKER
          FROM SYSIBM.SYSDUMMY1 -- a comment ; is not a statement
         FETCH FIRST 1 ROW ONLY;
        """
        let analysis = analyzer.analyze(sql)

        XCTAssertEqual(analysis.statementCount, 1)
        XCTAssertEqual(analysis.statementClass, .readOnly)
        XCTAssertEqual(analysis.explicitRowLimit, 1)
        XCTAssertTrue(analysis.isSingleReadOnlyStatement)
    }

    func testMultipleStatementsAndDataChangesFailReadOnlyClassification() {
        let analysis = analyzer.analyze(
            "SELECT * FROM QSYS2.SYSTEM_STATUS_INFO; DELETE FROM DEVLIB.WORK;"
        )

        XCTAssertEqual(analysis.statementCount, 2)
        XCTAssertEqual(analysis.statementClass, .dataChange)
        XCTAssertFalse(analysis.isSingleReadOnlyStatement)
    }

    func testReadOnlyCTEIsAcceptedButDataChangeTableExpressionIsBlocked() {
        let cte = analyzer.analyze(
            "WITH JOBS AS (SELECT JOB_NAME FROM TABLE(QSYS2.ACTIVE_JOB_INFO())) SELECT * FROM JOBS"
        )
        let dataChange = analyzer.analyze(
            "SELECT * FROM FINAL TABLE (INSERT INTO DEVLIB.WORK VALUES (1))"
        )

        XCTAssertEqual(cte.statementClass, .readOnly)
        XCTAssertTrue(cte.isSingleReadOnlyStatement)
        XCTAssertEqual(dataChange.statementClass, .dataChange)
        XCTAssertFalse(dataChange.isSingleReadOnlyStatement)
    }

    func testEveryIBMServiceTemplateIsSingleReadOnlyAndBounded() {
        XCTAssertEqual(IBMIServicesCatalog.queries.count, 6)
        for query in IBMIServicesCatalog.queries {
            let analysis = analyzer.analyze(query.sql)
            XCTAssertTrue(analysis.isSingleReadOnlyStatement, query.title)
            XCTAssertNotNil(analysis.explicitRowLimit, query.title)
            XCTAssertLessThanOrEqual(analysis.explicitRowLimit ?? .max, 500, query.title)
        }
    }

    func testOfflineAndProductionTargetsFailClosed() {
        let sql = IBMIServicesCatalog.queries[0].sql
        let offline = SQLExecutionPreflight(
            sql: sql,
            context: SQLExecutionContext(providerConnected: false)
        )
        let production = SQLExecutionPreflight(
            sql: sql,
            context: SQLExecutionContext(
                providerConnected: true,
                targetName: "PROD",
                environment: .production
            )
        )

        XCTAssertFalse(offline.isReady)
        XCTAssertEqual(
            offline.checks.first(where: { $0.kind == .providerConnected })?.state,
            .blocked
        )
        XCTAssertFalse(production.isReady)
        XCTAssertEqual(
            production.checks.first(where: { $0.kind == .nonProductionTarget })?.state,
            .blocked
        )
    }

    func testConnectedDevelopmentTargetPassesEveryDefaultGate() {
        let preflight = SQLExecutionPreflight(
            sql: IBMIServicesCatalog.queries[0].sql,
            context: SQLExecutionContext(
                providerConnected: true,
                targetName: "DEV",
                environment: .development
            )
        )

        XCTAssertTrue(preflight.isReady)
        XCTAssertTrue(preflight.checks.allSatisfy { $0.state == .ready })
    }
}

final class ProviderRuntimeProbeTests: XCTestCase {
    private let probe = ProviderRuntimeProbe()

    func testSystemSSHCanBeReadyWhileSecureDb2PrerequisitesFailClosed() {
        let files = Set(["/usr/bin/ssh", "/usr/bin/ssh-keyscan", "/usr/bin/sftp"])
        let snapshot = probe.inspect(
            architecture: "arm64",
            capturedAt: Date(timeIntervalSince1970: 1_000),
            fileExists: files.contains,
            isExecutable: files.contains
        )

        XCTAssertTrue(snapshot.sshReady)
        XCTAssertTrue(snapshot.sftpReady)
        XCTAssertFalse(snapshot.secureDb2PrerequisitesReady)
        XCTAssertEqual(snapshot.component(.unixODBC).state, .missing)
        XCTAssertEqual(snapshot.component(.ibmIODBC).state, .missing)
    }

    func testSecureDb2ReadinessRequiresArchitectureManagerDriverAndTLSRuntime() {
        let files = Set([
            "/opt/homebrew/bin/odbcinst",
            "/Library/IBMiAccess/register_driver",
            "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib"
        ])
        let ready = probe.inspect(
            architecture: "arm64",
            fileExists: files.contains,
            isExecutable: files.contains
        )
        let translated = probe.inspect(
            architecture: "x86_64",
            fileExists: files.contains,
            isExecutable: files.contains
        )

        XCTAssertTrue(ready.secureDb2PrerequisitesReady)
        XCTAssertFalse(translated.secureDb2PrerequisitesReady)
    }

    func testDiscoveryUsesOnlyFixedNonCredentialPaths() {
        let candidates = ProviderRuntimeProbe.sshCandidates
            + ProviderRuntimeProbe.sshKeyscanCandidates
            + ProviderRuntimeProbe.sftpCandidates
            + ProviderRuntimeProbe.unixODBCExecutableCandidates
            + ProviderRuntimeProbe.unixODBCLibraryCandidates
            + ProviderRuntimeProbe.ibmIODBCCandidates
            + ProviderRuntimeProbe.openSSLCandidates

        XCTAssertTrue(candidates.allSatisfy { $0.hasPrefix("/") })
        XCTAssertFalse(candidates.contains(where: { $0.localizedCaseInsensitiveContains("secret") }))
        XCTAssertFalse(candidates.contains(where: { $0.localizedCaseInsensitiveContains("devenv") }))
        XCTAssertFalse(candidates.contains(where: { $0.localizedCaseInsensitiveContains("credential") }))
    }
}

final class Db2ConnectionContractTests: XCTestCase {
    private let profile = Db2ConnectionProfile(
        id: UUID(uuidString: "1F6E852D-873D-49CA-BAD3-AC112F32F56D")!,
        name: "Development partition",
        host: "dev400.example.com",
        username: "devuser",
        environment: .development,
        loginTimeoutSeconds: 12,
        connectionTimeoutSeconds: 24
    )

    func testProfileNormalizesUserAndRejectsConnectionStringInjection() throws {
        XCTAssertEqual(profile.normalizedUsername, "DEVUSER")
        XCTAssertTrue(profile.validationErrors.isEmpty)

        let injectedHost = Db2ConnectionProfile(
            name: "Bad",
            host: "host;SSL=0",
            username: "DEVUSER"
        )
        let injectedUser = Db2ConnectionProfile(
            name: "Bad",
            host: "dev400.example.com",
            username: "USER;PWD=X"
        )
        let unboundedTimeout = Db2ConnectionProfile(
            name: "Bad",
            host: "dev400.example.com",
            username: "DEVUSER",
            connectionTimeoutSeconds: 121
        )

        XCTAssertFalse(injectedHost.validationErrors.isEmpty)
        XCTAssertFalse(injectedUser.validationErrors.isEmpty)
        XCTAssertFalse(unboundedTimeout.validationErrors.isEmpty)
        XCTAssertThrowsError(
            try Db2ConnectionPlanner().plan(
                profile: injectedHost,
                password: Db2Password("not-a-real-password")
            )
        )
    }

    func testProfileSerializationContainsNoPasswordSurface() throws {
        let encoded = try JSONEncoder().encode(profile)
        let json = String(decoding: encoded, as: UTF8.self).uppercased()

        XCTAssertFalse(json.contains("PASSWORD"))
        XCTAssertFalse(json.contains("PWD"))
        XCTAssertFalse(json.contains("SECRET"))
        XCTAssertEqual(try JSONDecoder().decode(Db2ConnectionProfile.self, from: encoded), profile)
    }

    func testReadOnlyPlanPinsTLSDriverAndLeastPrivilegeKeywords() throws {
        let secret = "p;ass}word"
        let password = try Db2Password(secret)
        let plan = try Db2ConnectionPlanner().plan(profile: profile, password: password)
        let raw = plan.connectionString.withUnsafeCString { pointer, _ in String(cString: pointer) }

        XCTAssertEqual(plan.accessMode, .readOnly)
        XCTAssertEqual(plan.policy.accessAttribute, .readOnly)
        XCTAssertTrue(plan.policy.autoCommit)
        XCTAssertFalse(plan.policy.serializableIsolation)
        XCTAssertEqual(plan.policy.loginTimeoutSeconds, 12)
        XCTAssertEqual(plan.policy.connectionTimeoutSeconds, 24)
        XCTAssertTrue(raw.contains("DRIVER={IBM i Access ODBC Driver};"))
        XCTAssertTrue(raw.contains("SYSTEM=dev400.example.com;"))
        XCTAssertTrue(raw.contains("UID=DEVUSER;"))
        XCTAssertTrue(raw.contains("PWD={p;ass}}word};"))
        XCTAssertTrue(raw.contains("SIGNON=2;SSL=1;CONNTYPE=2;CMT=1;"))
        XCTAssertTrue(raw.contains("NAM=0;ALLOWUNSCHAR=0;TRANSLATE=0;CCSID=1208;UNICODESQL=1;"))
        XCTAssertTrue(raw.contains("XDYNAMIC=0;QUERYTIMEOUT=1;ALLOWPROCCALLS=0;LIBVIEW=0;TRACE=0;"))
        XCTAssertFalse(raw.contains("SSL=0"))
        XCTAssertFalse(String(describing: password).contains(secret))
        XCTAssertFalse(String(reflecting: password).contains(secret))
        XCTAssertFalse(String(describing: plan).contains(secret))
        XCTAssertFalse(String(reflecting: plan).contains(secret))
        XCTAssertEqual(String(describing: plan.connectionString), "<redacted Db2 connection string>")
    }

    func testReviewedSourceMemberPlanIsSerializableAndNeverGeneralAutocommitWrite() throws {
        let plan = try Db2ConnectionPlanner().plan(
            profile: profile,
            password: Db2Password("not-a-real-password"),
            accessMode: .reviewedSourceMemberWrite
        )
        let raw = plan.connectionString.withUnsafeCString { pointer, _ in String(cString: pointer) }

        XCTAssertEqual(plan.policy.accessAttribute, .readWrite)
        XCTAssertFalse(plan.policy.autoCommit)
        XCTAssertTrue(plan.policy.serializableIsolation)
        XCTAssertTrue(plan.accessMode.requiresExplicitTransaction)
        XCTAssertTrue(raw.contains("CONNTYPE=0;CMT=4;"))
        XCTAssertFalse(Db2AccessMode.allCases.contains { $0.rawValue == "readWrite" })
    }

    func testSourceMemberReadAllowsOnlyTheTemporaryAliasCapabilityAtTheDriverBoundary() throws {
        let plan = try Db2ConnectionPlanner().plan(
            profile: profile,
            password: Db2Password("not-a-real-password"),
            accessMode: .sourceMemberRead
        )
        let raw = plan.connectionString.withUnsafeCString { pointer, _ in String(cString: pointer) }

        XCTAssertEqual(plan.policy.accessAttribute, .readWrite)
        XCTAssertTrue(plan.policy.autoCommit)
        XCTAssertFalse(plan.policy.serializableIsolation)
        XCTAssertTrue(raw.contains("CONNTYPE=0;CMT=1;"))
        XCTAssertFalse(plan.accessMode.requiresExplicitTransaction)
    }

    func testReceiptIsSafeToPersist() throws {
        let receipt = Db2ConnectionReceipt(
            profileID: profile.id,
            targetName: profile.targetLabel,
            environment: profile.environment,
            accessMode: .readOnly,
            connectedAt: Date(timeIntervalSince1970: 1_000)
        )
        let encoded = try JSONEncoder().encode(receipt)
        let json = String(decoding: encoded, as: UTF8.self).uppercased()

        XCTAssertFalse(json.contains(profile.normalizedUsername))
        XCTAssertFalse(json.contains("PWD"))
        XCTAssertFalse(json.contains("SELECT"))
        XCTAssertTrue(receipt.tlsEnabled)
    }

    func testDiagnosticsWithholdConnectionStringsAndRedactExactSecret() throws {
        let password = try Db2Password("highly-sensitive-value")
        let sanitizer = Db2DiagnosticSanitizer()

        XCTAssertEqual(
            sanitizer.sanitize(
                "Login failed for PWD={highly-sensitive-value};SYSTEM=host",
                password: password
            ),
            Db2DiagnosticSanitizer.withheldMessage
        )
        let safe = sanitizer.sanitize(
            "Authentication rejected highly-sensitive-value\nRetry later",
            password: password
        )
        XCTAssertFalse(safe.contains("highly-sensitive-value"))
        XCTAssertFalse(safe.contains("\n"))
        XCTAssertTrue(safe.contains("<redacted>"))
    }

    func testPasswordRejectsEmptyOversizedAndControlCharacters() {
        XCTAssertThrowsError(try Db2Password(""))
        XCTAssertThrowsError(try Db2Password(String(repeating: "x", count: 513)))
        XCTAssertThrowsError(try Db2Password("line\nbreak"))
    }
}

final class Db2OperationAuthorizationTests: XCTestCase {
    func testInteractiveSQLRequiresReadOnlyConnectionAndBoundedSingleSelect() throws {
        let request = SQLExecutionRequest(
            sql: "SELECT * FROM QSYS2.SYSTEM_STATUS_INFO FETCH FIRST 1 ROW ONLY",
            maximumRows: 1,
            timeoutSeconds: 20,
            readOnly: true
        )
        XCTAssertNoThrow(try Db2OperationAuthorizer(accessMode: .readOnly).authorizeInteractiveSQL(request))
        XCTAssertThrowsError(
            try Db2OperationAuthorizer(accessMode: .sourceMemberRead).authorizeInteractiveSQL(request)
        )
        XCTAssertThrowsError(
            try Db2OperationAuthorizer(accessMode: .readOnly).authorizeInteractiveSQL(
                SQLExecutionRequest(
                    sql: "SELECT * FROM DEVLIB.WORK; DELETE FROM DEVLIB.WORK",
                    maximumRows: 100,
                    timeoutSeconds: 20,
                    readOnly: true
                )
            )
        )
    }

    func testSourceQueriesRejectForgedMutationAndReadOnlyDriverCapability() throws {
        let valid = SourceMemberSQLPlanner().libraries()
        XCTAssertNoThrow(
            try Db2OperationAuthorizer(accessMode: .sourceMemberRead).authorizeSourceQuery(valid)
        )
        XCTAssertThrowsError(
            try Db2OperationAuthorizer(accessMode: .readOnly).authorizeSourceQuery(valid)
        )
        XCTAssertThrowsError(
            try Db2OperationAuthorizer(accessMode: .sourceMemberRead).authorizeSourceQuery(
                SourceMemberSQLRequest(
                    purpose: .listLibraries,
                    sql: "DELETE FROM DEVLIB.WORK",
                    maximumRows: 1,
                    readOnly: true
                )
            )
        )
    }

    func testReadMemberAcceptsOnlyTheExactGeneratedMetadataAndAliasLifecycle() throws {
        let identity = try SourceMemberIdentity(
            library: "DEVLIB",
            sourceFile: "QRPGLESRC",
            member: "CUSTINQ"
        )
        let planner = SourceMemberSQLPlanner()
        let metadata = planner.metadata(for: identity)
        let alias = try planner.aliasPlan(for: identity)
        let authorizer = Db2OperationAuthorizer(accessMode: .sourceMemberRead)

        XCTAssertNoThrow(
            try authorizer.authorizeReadMember(
                identity: identity,
                metadata: metadata,
                aliasPlan: alias
            )
        )
        XCTAssertThrowsError(
            try authorizer.authorizeReadMember(
                identity: identity,
                metadata: SourceMemberSQLRequest(
                    purpose: .readMetadata,
                    sql: metadata.sql + " ",
                    bindings: metadata.bindings,
                    maximumRows: metadata.maximumRows,
                    timeoutSeconds: metadata.timeoutSeconds,
                    readOnly: true
                ),
                aliasPlan: alias
            )
        )
    }
}

final class Db2ODBCTransportBoundaryTests: XCTestCase {
    func testMissingRuntimeFailsBeforeAnyDriverOrHostOperation() async throws {
        let profile = Db2ConnectionProfile(
            name: "Offline development",
            host: "dev400.example.com",
            username: "DEVUSER"
        )
        let missingRuntime = ProviderRuntimeProbe().inspect(
            architecture: "arm64",
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        let transport = Db2ODBCTransport(
            profile: profile,
            accessMode: .readOnly,
            runtimeSnapshot: missingRuntime
        )

        do {
            _ = try await transport.connect(password: Db2Password("not-a-real-password"))
            XCTFail("The transport must fail closed when its local runtime is absent.")
        } catch {
            XCTAssertEqual(error as? Db2ODBCTransportError, .prerequisitesMissing)
        }
        let isConnected = await transport.isConnected
        let receipt = await transport.receipt
        XCTAssertFalse(isConnected)
        XCTAssertNil(receipt)
    }
}

final class SecureChannelTests: XCTestCase {
    private let validProfile = SecureChannelProfile(
        name: "Development source",
        host: "pub400.com",
        username: "DEVUSER",
        environment: .development
    )

    func testProfileRejectsOptionInjectionRangesAndUnsafeUsernames() {
        let option = SecureChannelProfile(name: "Bad", host: "-oProxyCommand=bad", username: "USER")
        let range = SecureChannelProfile(name: "Bad", host: "10.0.0.0/24", username: "USER")
        let user = SecureChannelProfile(name: "Bad", host: "example.com", username: "-oBad")

        XCTAssertFalse(option.validationErrors.isEmpty)
        XCTAssertFalse(range.validationErrors.isEmpty)
        XCTAssertFalse(user.validationErrors.isEmpty)
    }

    func testKeyscanParserKeepsOnlyTheExpectedHostAndComputesSHA256() throws {
        let output = """
        # pub400.com:22 SSH-2.0-test
        attacker.example ssh-ed25519 aG9zdC1rZXk=
        pub400.com ssh-dss aG9zdC1rZXk=
        pub400.com ssh-ed25519 aG9zdC1rZXk=
        """

        let keys = try SSHHostKeyScanParser().parse(output, profile: validProfile)

        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].algorithm, "ssh-ed25519")
        XCTAssertEqual(keys[0].fingerprint, "SHA256:CfEOS9w3pHE4KlqjcQFwWyWMmyRvvPoehydyMhTxpzg")
        XCTAssertEqual(keys[0].knownHostsEntry, "pub400.com ssh-ed25519 aG9zdC1rZXk=")
    }

    func testSystemSSHPlanFailsClosedAndNeverUsesAShell() throws {
        let plan = try SystemSSHCommandPlan.authenticationTest(
            for: validProfile,
            knownHostsFile: "/private/tmp/itelas-known-hosts"
        )

        XCTAssertEqual(plan.executable, "/usr/bin/ssh")
        XCTAssertTrue(plan.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(plan.arguments.contains("BatchMode=yes"))
        XCTAssertTrue(plan.arguments.contains("ClearAllForwardings=yes"))
        XCTAssertTrue(plan.arguments.contains("ForwardAgent=no"))
        XCTAssertEqual(plan.arguments.suffix(3), ["--", "pub400.com", "true"])
        XCTAssertFalse(plan.arguments.contains(where: { $0.contains("devenv") || $0.contains("password") }))
    }

    func testSFTPProbeUsesAFixedBatchWithoutShellEscapes() throws {
        let plan = try SystemSSHCommandPlan.sftpSubsystemProbe(
            for: validProfile,
            knownHostsFile: "/private/tmp/itelas-known-hosts"
        )

        XCTAssertEqual(String(decoding: plan.standardInput ?? Data(), as: UTF8.self), "pwd\nquit\n")
        XCTAssertFalse(String(decoding: plan.standardInput ?? Data(), as: UTF8.self).contains("!"))
    }

    func testManagedKnownHostsPinIsIdempotentAndPermissionRestricted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-known-hosts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("known_hosts")
        let store = ManagedKnownHostsStore(fileURL: url)
        let key = try SSHHostKey(
            host: "pub400.com",
            port: 22,
            algorithm: "ssh-ed25519",
            encodedKey: "aG9zdC1rZXk="
        )

        try store.pin(key)
        try store.pin(key)

        XCTAssertEqual(try store.pinState(for: key), .pinned)
        XCTAssertEqual(try store.readEntries(), [key.knownHostsEntry])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testManagedKnownHostsRefusesChangedKeyForSameAlgorithm() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-changed-host-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ManagedKnownHostsStore(fileURL: directory.appendingPathComponent("known_hosts"))
        let first = try SSHHostKey(host: "pub400.com", port: 22, algorithm: "ssh-ed25519", encodedKey: "aG9zdC1rZXk=")
        let changed = try SSHHostKey(host: "pub400.com", port: 22, algorithm: "ssh-ed25519", encodedKey: "Y2hhbmdlZA==")
        try store.pin(first)

        XCTAssertEqual(try store.pinState(for: changed), .changed)
        XCTAssertThrowsError(try store.pin(changed)) { error in
            XCTAssertEqual(error as? SecureChannelError, .hostKeyChanged)
        }
    }
}

final class CompileEvidenceTests: XCTestCase {
    func testEVFEVENTParserPreservesExactIdentityAndDiagnosticCoordinates() throws {
        let evidence = """
        TIMESTAMP  0 20260727094218
        PROCESSOR  0 000 1
        FILEID     0 001 000000 026 DEVLIB/QRPGLESRC(ORDENTRY) 20260727094155 0
        ERROR      0 001 1 000042 000042 019 000042 028 RNF7030 S 30 046 Name or indicator CUSTOMERNO is not defined.
        ERROR      0 001 0 000000 000000 000 000000 000 RNS9308 T 50 057 Compilation stopped. Severity 30 errors found in program.
        FILEEND    0 001 000098
        """

        let result = try EVFEVENTParser().parse(text: evidence)

        XCTAssertEqual(result.timestamp, "20260727094218")
        XCTAssertEqual(result.sourceFiles.map(\.path), ["DEVLIB/QRPGLESRC(ORDENTRY)"])
        XCTAssertEqual(result.diagnostics.count, 2)
        XCTAssertEqual(result.diagnostics[0].messageID, "RNF7030")
        XCTAssertEqual(result.diagnostics[0].startLine, 42)
        XCTAssertEqual(result.diagnostics[0].startColumn, 19)
        XCTAssertEqual(result.diagnostics[0].endColumn, 28)
        XCTAssertEqual(result.diagnostics[0].band, .severe)
        XCTAssertEqual(result.unresolvedFileReferenceCount, 0)
        XCTAssertEqual(result.fingerprint.count, 64)
    }

    func testEVFEVENTParserReassemblesBoundedFileIdentityContinuations() throws {
        let first = "/home/dev/with"
        let rest = " spaces/very-long-name.rpgle"
        let path = first + rest
        let evidence = """
        PROCESSOR  0 000 1
        FILEID     0 001 000000 \(String(format: "%03d", path.count)) \(first)
        FILEIDCONT 0 001 000000 000 \(rest) 20260727094155 0
        ERROR      0 001 1 000007 000007 002 000007 008 RNF5377 E 20 038 The end of the expression is expected.
        FILEEND    0 001 000010
        """

        let result = try EVFEVENTParser().parse(text: evidence)

        XCTAssertEqual(result.sourceFiles.count, 1)
        XCTAssertEqual(result.diagnostics.count, 1)
        XCTAssertEqual(result.sourceFiles.first?.path, path)
        XCTAssertEqual(result.diagnostics.first?.filePath, path)
    }

    func testEVFEVENTParserReportsExpansionEvidenceWithoutClaimingMappedSource() throws {
        let evidence = """
        PROCESSOR  0 999 1
        FILEID     0 999 000000 024 QTEMP/QSQLPRE(ORDENTRY) 20260727094155 0
        FILEID     0 001 000000 026 DEVLIB/QRPGLESRC(ORDENTRY) 20260727094155 0
        EXPANSION  0 001 000000 000000 999 000011 000040
        FILEEND    0 001 000098
        FILEEND    0 999 000112
        """

        let result = try EVFEVENTParser().parse(text: evidence)

        XCTAssertEqual(result.expansionRecordCount, 1)
        XCTAssertTrue(result.hasExpansionMappings)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func testCompileEvidenceAnalysisLabelsRankingAsInference() throws {
        let evidence = """
        PROCESSOR  0 000 1
        FILEID     0 001 000000 026 DEVLIB/QRPGLESRC(ORDENTRY) 20260727094155 0
        ERROR      0 001 1 000042 000042 019 000042 028 RNF7030 S 30 046 Name or indicator CUSTOMERNO is not defined.
        ERROR      0 001 1 000043 000043 001 000043 005 RNF7503 S 30 045 Expression contains an operand that is not valid.
        ERROR      0 001 1 000070 000070 014 000070 019 RNF7031 I 00 047 The name or indicator UNUSED is not referenced.
        FILEEND    0 001 000098
        """
        let result = try EVFEVENTParser().parse(text: evidence)

        let analysis = CompileEvidenceAnalysis(result: result)

        XCTAssertEqual(analysis.primaryDiagnostic?.messageID, "RNF7030")
        XCTAssertEqual(analysis.relatedDiagnostics.map(\.messageID), ["RNF7503"])
        XCTAssertEqual(analysis.informationalDiagnostics.map(\.messageID), ["RNF7031"])
        XCTAssertEqual(analysis.confidence, .medium)
        XCTAssertTrue(analysis.selectionBasis.contains("triage lead"))
        XCTAssertTrue(analysis.selectionBasis.contains("not proof"))
    }

    func testEVFEVENTParserRejectsInvalidContinuationAndInputCaps() {
        XCTAssertThrowsError(try EVFEVENTParser().parse(text: "FILEIDCONT 0 001 000000 000 orphan")) { error in
            XCTAssertEqual(error as? CompileEvidenceError, .invalidFileContinuation(index: 1))
        }

        let parser = EVFEVENTParser(limits: .init(maximumUTF8Bytes: 8))
        XCTAssertThrowsError(try parser.parse(text: "PROCESSOR  0 000 1")) { error in
            XCTAssertEqual(error as? CompileEvidenceError, .inputTooLarge(maximum: 8))
        }
    }
}

final class JobIncidentTests: XCTestCase {
    private let decoder = JobIncidentSQLDecoder()

    func testQualifiedJobNameRequiresASCIINumberAndClassicSystemNames() throws {
        let job = try IBMQualifiedJobName("847216/devuser/itelasbld")

        XCTAssertEqual(job.rawValue, "847216/DEVUSER/ITELASBLD")
        XCTAssertEqual(job.number, "847216")
        XCTAssertThrowsError(try IBMQualifiedJobName("１２３４５６/DEVUSER/ITELASBLD"))
        XCTAssertThrowsError(try IBMQualifiedJobName("847216/DEVUßER/ITELASBLD"))
        XCTAssertThrowsError(try IBMQualifiedJobName("847216/1EVUSER/ITELASBLD"))
        XCTAssertThrowsError(try IBMQualifiedJobName("847216/DEVUSER/NAME;DROP"))
        XCTAssertThrowsError(try IBMQualifiedJobName("847216/DEVUSER"))
    }

    func testEveryGeneratedQueryIsSingleReadOnlyBoundedAndAuthorized() throws {
        let limits = JobIncidentLimits.standard
        let planner = JobIncidentSQLPlanner(limits: limits)
        let selected = try IBMQualifiedJobName("847216/DEVUSER/ITELASBLD")
        let requests = [
            planner.jobInventory,
            planner.objectLocks,
            planner.jobLog(for: selected),
            planner.operatorInquiries
        ]

        XCTAssertEqual(requests.map(\.maximumRows), [250, 500, 500, 100])
        for request in requests {
            let analysis = SQLStatementAnalyzer().analyze(request.sql)
            XCTAssertTrue(request.readOnly)
            XCTAssertEqual(request.timeoutSeconds, 30)
            XCTAssertTrue(analysis.isSingleReadOnlyStatement, request.sql)
            XCTAssertEqual(analysis.explicitRowLimit, request.maximumRows)
            XCTAssertNoThrow(
                try Db2OperationAuthorizer(accessMode: .readOnly).authorizeInteractiveSQL(request)
            )
        }
        XCTAssertTrue(planner.jobInventory.sql.contains("JOB_TYPE IS NULL"))
        XCTAssertTrue(planner.jobLog(for: selected).sql.contains("'847216/DEVUSER/ITELASBLD'"))
        XCTAssertTrue(planner.jobLog(for: selected).sql.contains("MESSAGE_ORDER => 'DESCENDING'"))
        XCTAssertTrue(planner.jobLog(for: selected).sql.contains("MESSAGE_LIMIT => 500"))
    }

    func testJobDecoderUsesColumnNamesAndBuildsExactQueueSummary() throws {
        let capturedAt = Date(timeIntervalSince1970: 2_000)
        let columns = [
            "JOB_QUEUE_NAME", "JOB_NAME", "OUTPUT_QUEUE_NAME", "JOB_STATUS",
            "JOB_INFORMATION", "JOB_TYPE_ENHANCED", "JOB_SUBSYSTEM", "JOB_TYPE",
            "JOB_QUEUE_LIBRARY", "JOB_QUEUE_STATUS", "JOB_QUEUE_PRIORITY",
            "JOB_QUEUE_TIME", "JOB_LOG_PENDING", "OUTPUT_QUEUE_LIBRARY"
        ]
        let result = sqlResult(columns: columns, rows: [
            [
                .string("DEVJOBQ"), .string("847216/DEVUSER/ITELASBLD"), .string("QPRINT"), .string("JOBQ"),
                .string("YES"), .string("BATCH"), .string("QBATCH"), .string("BATCH"),
                .string("DEVLIB"), .string("HELD"), .integer(2), .timestamp(capturedAt), .string("YES"), .string("QGPL")
            ],
            [
                .string("DEVJOBQ"), .string("847217/DEVUSER/ORDNIGHT"), .string("QPRINT"), .string("JOBQ"),
                .string("YES"), .string("SCHEDULED BATCH"), .string("QBATCH"), .string("BATCH"),
                .string("DEVLIB"), .string("SCHEDULED"), .integer(3), .timestamp(capturedAt.addingTimeInterval(60)), .string("NO"), .string("QGPL")
            ],
            [
                .null, .string("847218/DEVUSER/HIDDENJOB"), .null, .null,
                .string("NO"), .null, .null, .null,
                .null, .null, .null, .null, .null, .null
            ]
        ])

        let jobs = try decoder.decodeJobs(result)
        let snapshot = JobIncidentSnapshot(
            targetName: "DEV",
            capturedAt: capturedAt,
            jobs: jobs,
            locks: [],
            jobLogMessages: [],
            operatorMessages: [],
            receipts: []
        )

        XCTAssertEqual(jobs.map(\.status), [.jobQueue, .jobQueue, .unavailable])
        XCTAssertEqual(jobs[0].jobQueue?.id, "DEVLIB/DEVJOBQ")
        XCTAssertTrue(jobs[0].jobLogPending)
        XCTAssertEqual(snapshot.queueSummaries.count, 1)
        XCTAssertEqual(snapshot.queueSummaries[0].queuedCount, 2)
        XCTAssertEqual(snapshot.queueSummaries[0].heldCount, 1)
        XCTAssertEqual(snapshot.queueSummaries[0].scheduledCount, 1)
        XCTAssertEqual(snapshot.queueSummaries[0].oldestQueueTime, capturedAt)
    }

    func testDecoderRejectsDuplicateMissingMalformedAndOverCapResults() {
        let duplicate = sqlResult(columns: ["JOB_NAME", "job_name"], rows: [])
        XCTAssertThrowsError(try decoder.decodeJobs(duplicate)) { error in
            XCTAssertEqual(error as? JobIncidentError, .duplicateColumn(surface: "JOB_INFO", column: "JOB_NAME"))
        }

        let missing = sqlResult(
            columns: ["JOB_NAME"],
            rows: [[.string("847216/DEVUSER/ITELASBLD")]]
        )
        XCTAssertThrowsError(try decoder.decodeJobs(missing)) { error in
            XCTAssertEqual(error as? JobIncidentError, .missingColumn(surface: "JOB_INFO", column: "JOB_INFORMATION"))
        }

        let malformed = sqlResult(
            columns: ["JOB_NAME", "JOB_INFORMATION"],
            rows: [
                [.string("847216/DEVUSER/ITELASBLD"), .string("NO")],
                [.string("847217/DEVUSER/ORDNIGHT")]
            ]
        )
        XCTAssertThrowsError(try decoder.decodeJobs(malformed)) { error in
            XCTAssertEqual(error as? JobIncidentError, .malformedRow(surface: "JOB_INFO", index: 2))
        }

        let cappedDecoder = JobIncidentSQLDecoder(limits: .init(maximumJobs: 1))
        let overCap = sqlResult(columns: [], rows: [[], []])
        XCTAssertThrowsError(try cappedDecoder.decodeJobs(overCap)) { error in
            XCTAssertEqual(error as? JobIncidentError, .tooManyRows(surface: "JOB_INFO", maximum: 1))
        }
    }

    func testAnalysisCorrelatesOnlyExactObjectHolderCandidatesWithoutClaimingCause() throws {
        let waiter = try IBMQualifiedJobName("847216/DEVUSER/ITELASBLD")
        let holder = try IBMQualifiedJobName("847118/OPSUSR/ORDWRITER")
        let other = try IBMQualifiedJobName("847301/DEVUSER/QZDASOINIT")
        let selected = JobInventoryRecord(
            qualifiedName: waiter,
            informationAvailable: true,
            status: .active
        )
        let object = try IBMObjectLockIdentity(
            library: IBMSystemObjectName("DEVLIB"),
            object: IBMSystemObjectName("ORDHDR"),
            objectType: "*FILE"
        )
        let unrelated = try IBMObjectLockIdentity(
            library: IBMSystemObjectName("DEVLIB"),
            object: IBMSystemObjectName("CUSTMAST"),
            objectType: "*FILE"
        )
        let snapshot = JobIncidentSnapshot(
            targetName: "DEV",
            capturedAt: Date(timeIntervalSince1970: 3_000),
            jobs: [selected],
            locks: [
                JobLockRecord(rowIndex: 1, object: object, job: waiter, status: .waiting, state: "*EXCLRD", scope: "JOB"),
                JobLockRecord(rowIndex: 2, object: object, job: holder, status: .held, state: "*EXCLRD", scope: "JOB"),
                JobLockRecord(rowIndex: 3, object: unrelated, job: other, status: .held, state: "*SHRRD", scope: "THREAD")
            ],
            jobLogMessages: [],
            operatorMessages: [],
            receipts: []
        )

        let analysis = JobIncidentAnalysis(snapshot: snapshot, selectedJob: selected)

        XCTAssertEqual(analysis.waitingLocks.count, 1)
        XCTAssertEqual(analysis.holderCandidates.count, 1)
        XCTAssertEqual(analysis.holderCandidates.first?.holder.job, holder)
        XCTAssertEqual(analysis.confidence, .high)
        XCTAssertTrue(analysis.relationshipBasis.contains("exact object identity"))
        XCTAssertTrue(analysis.relationshipBasis.contains("not scheduler-causality proof"))
    }

    func testMessageDecodersPreserveTextAndSelectLatestInquiryAsTriageLead() throws {
        let job = try IBMQualifiedJobName("847216/DEVUSER/ITELASBLD")
        let firstTime = Date(timeIntervalSince1970: 4_000)
        let jobLog = sqlResult(
            columns: [
                "ORDINAL_POSITION", "MESSAGE_ID", "MESSAGE_TYPE", "SEVERITY",
                "MESSAGE_TIMESTAMP", "MESSAGE_TEXT", "MESSAGE_SECOND_LEVEL_TEXT",
                "FROM_PROGRAM", "FROM_MODULE", "FROM_PROCEDURE", "QUALIFIED_JOB_NAME"
            ],
            rows: [
                [.integer(10), .string("CPF0001"), .string("ESCAPE"), .integer(50), .timestamp(firstTime), .string("Higher severity"), .string("Review first"), .string("PGM1"), .string("MOD1"), .string("proc1"), .string(job.rawValue)],
                [.integer(11), .string("CPA0002"), .string("INQUIRY"), .integer(20), .timestamp(firstTime.addingTimeInterval(5)), .string("  Preserve leading spaces"), .string("Line one\nLine two"), .string("PGM1"), .string("MOD1"), .string("proc1"), .string(job.rawValue)]
            ]
        )
        let messages = try decoder.decodeJobLog(jobLog)
        let operatorResult = sqlResult(
            columns: [
                "MESSAGE_ID", "MESSAGE_TYPE", "SEVERITY", "MESSAGE_TIMESTAMP",
                "MESSAGE_TEXT", "MESSAGE_SECOND_LEVEL_TEXT", "FROM_USER", "FROM_JOB", "FROM_PROGRAM"
            ],
            rows: [
                [.string("CPA0002"), .string("INQUIRY"), .integer(20), .timestamp(firstTime.addingTimeInterval(5)), .string("Reply required"), .string("Review state"), .string("DEVUSER"), .string(job.rawValue), .string("PGM1")],
                [.string("CPA0003"), .string("INQUIRY"), .integer(10), .timestamp(firstTime), .string("Other job"), .null, .string("OPSUSR"), .string("847118/OPSUSR/ORDWRITER"), .string("PGM2")]
            ]
        )
        let operatorMessages = try decoder.decodeOperatorMessages(operatorResult)
        let selected = JobInventoryRecord(
            qualifiedName: job,
            informationAvailable: true,
            status: .active
        )
        let snapshot = JobIncidentSnapshot(
            targetName: "DEV",
            capturedAt: firstTime.addingTimeInterval(10),
            jobs: [selected],
            locks: [],
            jobLogMessages: messages,
            operatorMessages: operatorMessages,
            receipts: []
        )
        let analysis = JobIncidentAnalysis(snapshot: snapshot, selectedJob: selected)

        XCTAssertEqual(messages[1].text, "  Preserve leading spaces")
        XCTAssertEqual(messages[1].secondLevelText, "Line one\nLine two")
        XCTAssertEqual(analysis.selectedMessage?.messageID, "CPA0002")
        XCTAssertTrue(analysis.messageSelectionBasis.contains("triage choice"))
        XCTAssertEqual(analysis.relatedOperatorMessages.map(\.messageID), ["CPA0002"])
    }

    func testMessageBoundsControlsAndIncidentAssistContextKindFailClosed() throws {
        let job = try IBMQualifiedJobName("847216/DEVUSER/ITELASBLD")
        let columns = [
            "ORDINAL_POSITION", "MESSAGE_ID", "MESSAGE_TYPE", "SEVERITY",
            "MESSAGE_TIMESTAMP", "MESSAGE_TEXT", "MESSAGE_SECOND_LEVEL_TEXT",
            "FROM_PROGRAM", "FROM_MODULE", "FROM_PROCEDURE", "QUALIFIED_JOB_NAME"
        ]
        let boundedDecoder = JobIncidentSQLDecoder(limits: .init(maximumMessageCharacters: 4))
        let oversized = sqlResult(columns: columns, rows: [[
            .integer(1), .string("CPF0001"), .string("DIAGNOSTIC"), .integer(10), .null,
            .string("12345"), .null, .null, .null, .null, .string(job.rawValue)
        ]])
        XCTAssertThrowsError(try boundedDecoder.decodeJobLog(oversized)) { error in
            XCTAssertEqual(
                error as? JobIncidentError,
                .textTooLarge(surface: "JOBLOG_INFO", index: 1, column: "MESSAGE_TEXT", maximum: 4)
            )
        }

        let control = sqlResult(columns: columns, rows: [[
            .integer(1), .string("CPF0001"), .string("DIAGNOSTIC"), .integer(10), .null,
            .string("bad\u{0007}text"), .null, .null, .null, .null, .string(job.rawValue)
        ]])
        XCTAssertThrowsError(try decoder.decodeJobLog(control)) { error in
            XCTAssertEqual(error as? JobIncidentError, .invalidValue(surface: "JOBLOG_INFO", index: 1, column: "MESSAGE_TEXT"))
        }

        XCTAssertEqual(AIContextKind.jobIncident.label, "Job incident")
        XCTAssertFalse(AIContextKind.jobIncident.requiresSelection)
        XCTAssertNoThrow(try AIContextFragment(
            kind: .jobIncident,
            documentName: "incident.txt",
            language: "IBM i incident evidence",
            sourceText: "Read-only evidence; correlation is not causality."
        ))
    }

    private func sqlResult(columns: [String], rows: [[SQLValue]]) -> SQLResult {
        SQLResult(
            columns: columns.map {
                SQLColumn(name: $0, databaseType: "VARCHAR", isNullable: true)
            },
            rows: rows,
            targetName: "DEV",
            startedAt: Date(timeIntervalSince1970: 1_000),
            elapsedMilliseconds: 12,
            wasTruncated: false
        )
    }
}

final class SpooledOutputTests: XCTestCase {
    private let decoder = SpooledOutputSQLDecoder()

    func testExactIdentityRequiresValidatedASCIIJobFileAndPositiveNumber() throws {
        let identity = try SpooledFileIdentity(
            job: IBMQualifiedJobName("084219/batch/arpost"),
            file: IBMSystemObjectName("qpjoblog"),
            number: 184,
            system: IBMSystemObjectName("dev01")
        )

        XCTAssertEqual(identity.id, "DEV01:084219/BATCH/ARPOST:QPJOBLOG:184")
        XCTAssertEqual(identity.description, "084219/BATCH/ARPOST · QPJOBLOG #184")
        XCTAssertThrowsError(try SpooledFileIdentity(
            job: IBMQualifiedJobName("084219/BATCH/ARPOST"),
            file: IBMSystemObjectName("QPJOBLOG"),
            number: 0
        )) { error in
            XCTAssertEqual(error as? SpooledOutputError, .invalidSpooledFileNumber)
        }
        XCTAssertThrowsError(try IBMQualifiedJobName("０８４２１９/BATCH/ARPOST"))
        XCTAssertThrowsError(try IBMSystemObjectName("QPJOB;DROP"))
    }

    func testGeneratedRequestsAreSingleReadOnlyBoundedAndExplicit() throws {
        let limits = SpooledOutputLimits.standard
        let planner = SpooledOutputSQLPlanner(limits: limits)
        let identity = try SpooledFileIdentity(
            job: IBMQualifiedJobName("084219/BATCH/ARPOST"),
            file: IBMSystemObjectName("QPJOBLOG"),
            number: 184,
            system: IBMSystemObjectName("DEV01")
        )
        let requests = [planner.inventory, planner.outputQueues, planner.preview(identity)]

        XCTAssertEqual(requests.map(\.maximumRows), [250, 100, 2_000])
        for request in requests {
            let analysis = SQLStatementAnalyzer().analyze(request.sql)
            XCTAssertTrue(request.readOnly)
            XCTAssertEqual(request.timeoutSeconds, 30)
            XCTAssertTrue(analysis.isSingleReadOnlyStatement, request.sql)
            XCTAssertEqual(analysis.explicitRowLimit, request.maximumRows)
            XCTAssertNoThrow(
                try Db2OperationAuthorizer(accessMode: .readOnly).authorizeInteractiveSQL(request)
            )
        }
        XCTAssertTrue(planner.inventory.sql.contains("QSYS2.SPOOLED_FILE_INFO"))
        XCTAssertTrue(planner.inventory.sql.contains("USER_NAME => '*ALL'"))
        XCTAssertTrue(planner.outputQueues.sql.contains("QSYS2.OUTPUT_QUEUE_INFO"))
        XCTAssertTrue(planner.preview(identity).sql.contains("SYSTOOLS.SPOOLED_FILE_DATA"))
        XCTAssertTrue(planner.preview(identity).sql.contains("JOB_NAME => '084219/BATCH/ARPOST'"))
        XCTAssertTrue(planner.preview(identity).sql.contains("SPOOLED_FILE_NUMBER => 184"))
        XCTAssertTrue(planner.preview(identity).sql.contains("IGNORE_ERRORS => 'NO'"))
    }

    func testInventoryDecoderUsesColumnNamesAndPreservesExactMetadata() throws {
        let created = Date(timeIntervalSince1970: 5_000)
        let result = sqlResult(columns: [
            "STATUS", "SPOOLED_FILE_NUMBER", "SPOOLED_FILE_NAME", "QUALIFIED_JOB_NAME",
            "OUTPUT_QUEUE", "OUTPUT_QUEUE_LIBRARY", "OUTPUT_PRIORITY", "CREATION_TIMESTAMP",
            "USER_DATA", "SIZE", "TOTAL_PAGES", "COPIES", "FILE_AVAILABLE", "FORM_TYPE",
            "ASP_NUMBER", "SYSTEM", "INTERNET_PRINT_PROTOCOL_JOB_ID"
        ], rows: [[
            .string("READY"), .integer(184), .string("QPJOBLOG"), .string("084219/BATCH/ARPOST"),
            .string("QPRINT"), .string("QGPL"), .integer(5), .timestamp(created),
            .string("ARPOST"), .integer(129_024), .integer(6), .integer(1), .string("*IMMED"), .string("*STD"),
            .integer(1), .string("DEV01"), .integer(778)
        ]])

        let files = try decoder.decodeInventory(result)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].identity.id, "DEV01:084219/BATCH/ARPOST:QPJOBLOG:184")
        XCTAssertEqual(files[0].status, .ready)
        XCTAssertEqual(files[0].outputQueue?.id, "QGPL/QPRINT")
        XCTAssertEqual(files[0].creationTimestamp, created)
        XCTAssertEqual(files[0].sizeBytes, 129_024)
        XCTAssertEqual(files[0].totalPages, 6)
        XCTAssertEqual(files[0].availability, .immediate)
        XCTAssertTrue(files[0].isContentAvailable)
    }

    func testQueueDecoderPreservesWriterAndAuthoritySignals() throws {
        let result = sqlResult(columns: [
            "TEXT_DESCRIPTION", "WRITER_TYPE", "WRITER_JOB_STATUS", "WRITER_JOB_NAME",
            "OUTPUT_QUEUE_STATUS", "AUTHORITY_TO_CHECK", "OPERATOR_CONTROLLED", "DISPLAY_ANY_FILE",
            "ORDER_OF_FILES", "PRINTER_DEVICE_NAME", "NUMBER_OF_WRITERS", "NUMBER_OF_FILES",
            "OUTPUT_QUEUE_LIBRARY_NAME", "OUTPUT_QUEUE_NAME"
        ], rows: [[
            .string("Primary output"), .string("PRINTER"), .string("STR"), .string("084155/QSPLJOB/PRT01"),
            .string("RELEASED"), .string("*OWNER"), .string("*YES"), .string("*OWNER"),
            .string("*FIFO"), .string("PRT01"), .integer(2), .integer(41),
            .string("QGPL"), .string("QPRINT")
        ]])

        let queues = try decoder.decodeQueues(result)

        XCTAssertEqual(queues.count, 1)
        XCTAssertEqual(queues[0].identity.id, "QGPL/QPRINT")
        XCTAssertEqual(queues[0].status, .released)
        XCTAssertEqual(queues[0].writerJob?.rawValue, "084155/QSPLJOB/PRT01")
        XCTAssertEqual(queues[0].writerJobStatus, "STR")
        XCTAssertEqual(queues[0].writerType, "PRINTER")
        XCTAssertTrue(queues[0].operatorControlled)
        XCTAssertEqual(queues[0].displayAnyFile, "*OWNER")

        let invalid = sqlResult(columns: result.columns.map(\.name), rows: [[
            .string("Primary output"), .string("PRINTER"), .string("BAD"), .string("084155/QSPLJOB/PRT01"),
            .string("RELEASED"), .string("*OWNER"), .string("*YES"), .string("*OWNER"),
            .string("*FIFO"), .string("PRT01"), .integer(2), .integer(41),
            .string("QGPL"), .string("QPRINT")
        ]])
        XCTAssertThrowsError(try decoder.decodeQueues(invalid)) { error in
            XCTAssertEqual(error as? SpooledOutputError, .invalidValue(surface: "OUTPUT_QUEUE_INFO", index: 1, column: "WRITER_JOB_STATUS"))
        }
    }

    func testPreviewPreservesRecordTextOrderAndRejectsAmbiguity() throws {
        let identity = try SpooledFileIdentity(
            job: IBMQualifiedJobName("084219/BATCH/ARPOST"),
            file: IBMSystemObjectName("QPJOBLOG"),
            number: 184
        )
        let result = sqlResult(columns: ["SPOOLED_DATA", "ORDINAL_POSITION"], rows: [
            [.string("third"), .integer(3)],
            [.string("  first with leading spaces"), .integer(1)],
            [.string("second   "), .integer(2)]
        ])

        let preview = try decoder.decodePreview(result, identity: identity)

        XCTAssertEqual(preview.records.map(\.ordinalPosition), [1, 2, 3])
        XCTAssertEqual(preview.records[0].text, "  first with leading spaces")
        XCTAssertEqual(preview.records[1].text, "second   ")
        XCTAssertTrue(preview.isComplete)
        XCTAssertEqual(preview.contentFingerprint.count, 64)

        let duplicate = sqlResult(columns: ["ORDINAL_POSITION", "SPOOLED_DATA"], rows: [
            [.integer(1), .string("one")], [.integer(1), .string("again")]
        ])
        XCTAssertThrowsError(try decoder.decodePreview(duplicate, identity: identity)) { error in
            XCTAssertEqual(error as? SpooledOutputError, .duplicatePreviewOrdinal(1))
        }

        let control = sqlResult(columns: ["ORDINAL_POSITION", "SPOOLED_DATA"], rows: [
            [.integer(1), .string("bad\u{0007}record")]
        ])
        XCTAssertThrowsError(try decoder.decodePreview(control, identity: identity)) { error in
            XCTAssertEqual(error as? SpooledOutputError, .invalidValue(surface: "SPOOLED_FILE_DATA", index: 1, column: "SPOOLED_DATA"))
        }

        let bounded = SpooledOutputSQLDecoder(limits: .init(maximumPreviewRecords: 1))
        XCTAssertThrowsError(try bounded.decodePreview(duplicate, identity: identity)) { error in
            XCTAssertEqual(error as? SpooledOutputError, .tooManyRows(surface: "SPOOLED_FILE_DATA", maximum: 1))
        }
    }

    func testLocalComparisonKeepsBothExactIdentitiesAndStatesItsLimits() throws {
        let currentIdentity = try SpooledFileIdentity(
            job: IBMQualifiedJobName("084219/BATCH/ARPOST"),
            file: IBMSystemObjectName("QPJOBLOG"),
            number: 184
        )
        let baselineIdentity = try SpooledFileIdentity(
            job: IBMQualifiedJobName("083912/BATCH/ARPOST"),
            file: IBMSystemObjectName("QPJOBLOG"),
            number: 179
        )
        let baseline = SpooledTextPreview(
            identity: baselineIdentity,
            targetName: "DEV",
            capturedAt: Date(timeIntervalSince1970: 5_000),
            records: [
                SpooledTextRecord(ordinalPosition: 1, text: "header"),
                SpooledTextRecord(ordinalPosition: 2, text: "old")
            ],
            isComplete: true
        )
        let current = SpooledTextPreview(
            identity: currentIdentity,
            targetName: "DEV",
            capturedAt: Date(timeIntervalSince1970: 6_000),
            records: [
                SpooledTextRecord(ordinalPosition: 1, text: "header"),
                SpooledTextRecord(ordinalPosition: 2, text: "new"),
                SpooledTextRecord(ordinalPosition: 3, text: "tail")
            ],
            isComplete: true
        )

        let comparison = try SpooledTextComparison(baseline: baseline, current: current)

        XCTAssertEqual(comparison.baselineIdentity, baselineIdentity)
        XCTAssertEqual(comparison.currentIdentity, currentIdentity)
        XCTAssertEqual(comparison.changedOrdinalCount, 1)
        XCTAssertEqual(comparison.addedRecordCount, 1)
        XCTAssertEqual(comparison.removedRecordCount, 0)
        XCTAssertEqual(comparison.firstDifferenceOrdinal, 2)
        XCTAssertTrue(comparison.comparisonBasis.contains("does not prove report lineage"))
        XCTAssertTrue(comparison.comparisonBasis.contains("AFP/IPDS"))

        let other = SpooledTextPreview(
            identity: try SpooledFileIdentity(
                job: currentIdentity.job,
                file: IBMSystemObjectName("QSYSPRT"),
                number: 185
            ),
            targetName: "DEV",
            capturedAt: Date(),
            records: [],
            isComplete: true
        )
        XCTAssertThrowsError(try SpooledTextComparison(baseline: baseline, current: other)) { error in
            XCTAssertEqual(error as? SpooledOutputError, .comparisonFileMismatch)
        }
    }

    func testDecoderStructureBoundsAndAssistKindFailClosed() throws {
        let duplicate = sqlResult(columns: ["STATUS", "status"], rows: [])
        XCTAssertThrowsError(try decoder.decodeInventory(duplicate)) { error in
            XCTAssertEqual(error as? SpooledOutputError, .duplicateColumn(surface: "SPOOLED_FILE_INFO", column: "STATUS"))
        }

        let missing = sqlResult(columns: ["SPOOLED_FILE_NAME"], rows: [[.string("QPJOBLOG")]])
        XCTAssertThrowsError(try decoder.decodeInventory(missing)) { error in
            XCTAssertEqual(error as? SpooledOutputError, .missingColumn(surface: "SPOOLED_FILE_INFO", column: "SPOOLED_FILE_NUMBER"))
        }

        let malformed = sqlResult(
            columns: ["SPOOLED_FILE_NAME", "SPOOLED_FILE_NUMBER"],
            rows: [[.string("QPJOBLOG"), .integer(184)], [.string("QSYSPRT")]]
        )
        XCTAssertThrowsError(try decoder.decodeInventory(malformed)) { error in
            XCTAssertEqual(error as? SpooledOutputError, .malformedRow(surface: "SPOOLED_FILE_INFO", index: 2))
        }

        let capped = SpooledOutputSQLDecoder(limits: .init(maximumInventoryRows: 1))
        XCTAssertThrowsError(try capped.decodeInventory(sqlResult(columns: [], rows: [[], []]))) { error in
            XCTAssertEqual(error as? SpooledOutputError, .tooManyRows(surface: "SPOOLED_FILE_INFO", maximum: 1))
        }

        XCTAssertEqual(AIContextKind.spoolOutput.label, "Spooled output")
        XCTAssertFalse(AIContextKind.spoolOutput.requiresSelection)
        XCTAssertNoThrow(try AIContextFragment(
            kind: .spoolOutput,
            documentName: "QPJOBLOG-184.txt",
            language: "IBM i spooled-output evidence",
            sourceText: "Ordered text records only; no page-layout fidelity claim."
        ))
    }

    private func sqlResult(columns: [String], rows: [[SQLValue]]) -> SQLResult {
        SQLResult(
            columns: columns.map {
                SQLColumn(name: $0, databaseType: "VARCHAR", isNullable: true)
            },
            rows: rows,
            targetName: "DEV",
            startedAt: Date(timeIntervalSince1970: 1_000),
            elapsedMilliseconds: 12,
            wasTruncated: false
        )
    }
}

final class DataTransferTests: XCTestCase {
    func testDelimitedProfilerPreservesQuotesEmbeddedRecordsAndLeadingZeros() throws {
        let csv = "A,B,C\r\n000184,\"Acme, Inc.\",\"line 1\r\nline 2\"\r\n000185,Beta,plain"
        let artifact = try DelimitedTextProfiler().parse(Data(csv.utf8), fileName: "customers.csv")

        XCTAssertEqual(artifact.rowCount, 2)
        XCTAssertEqual(artifact.headers, ["A", "B", "C"])
        XCTAssertEqual(artifact.rows[0], ["000184", "Acme, Inc.", "line 1\r\nline 2"])
        XCTAssertEqual(artifact.columns[0].inferredKind, .text)
        XCTAssertTrue(artifact.columns[0].hasLeadingZeroRisk)
        XCTAssertEqual(artifact.columns[1].sampleValues.first, "Acme, Inc.")
        XCTAssertEqual(artifact.sha256, AIContentFingerprint.sha256(Data(csv.utf8)))
    }

    func testDelimitedProfilerRejectsAmbiguousStructureControlsAndBounds() throws {
        XCTAssertThrowsError(try DelimitedTextProfiler().parse(
            Data("A,A\n1,2".utf8),
            fileName: "duplicate.csv"
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .duplicateHeader("A"))
        }

        XCTAssertThrowsError(try DelimitedTextProfiler().parse(
            Data("A,B\n1".utf8),
            fileName: "short.csv"
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .inconsistentColumnCount(row: 2, expected: 2, actual: 1))
        }

        XCTAssertThrowsError(try DelimitedTextProfiler().parse(
            Data("A\n\"unterminated".utf8),
            fileName: "quote.csv"
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .unterminatedQuotedField(row: 2, column: 1))
        }

        XCTAssertThrowsError(try DelimitedTextProfiler().parse(
            Data([0x41, 0x0A, 0x00]),
            fileName: "control.csv"
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .sourceContainsControl)
        }

        let bounded = DelimitedTextProfiler(limits: .init(maximumRows: 1))
        XCTAssertThrowsError(try bounded.parse(Data("A\n1\n2".utf8), fileName: "rows.csv")) { error in
            XCTAssertEqual(error as? DataTransferError, .tooManyRows(maximum: 1))
        }
    }

    func testSchemaRequestIsSingleReadOnlyBoundedAndUsesValidatedSystemNames() throws {
        let table = IBMTableIdentity(
            library: try IBMSystemObjectName("ARLIB"),
            table: try IBMSystemObjectName("CUSTOMER")
        )
        let request = TransferSchemaSQLPlanner().targetSchema(table)
        let analysis = SQLStatementAnalyzer().analyze(request.sql)

        XCTAssertTrue(request.readOnly)
        XCTAssertEqual(request.maximumRows, 256)
        XCTAssertEqual(request.timeoutSeconds, 30)
        XCTAssertTrue(analysis.isSingleReadOnlyStatement)
        XCTAssertEqual(analysis.explicitRowLimit, 257)
        XCTAssertTrue(request.sql.contains("FETCH FIRST 257 ROWS ONLY"))
        XCTAssertTrue(request.sql.contains("FROM QSYS2.SYSCOLUMNS2"))
        XCTAssertTrue(request.sql.contains("SYSTEM_TABLE_SCHEMA = 'ARLIB'"))
        XCTAssertTrue(request.sql.contains("SYSTEM_TABLE_NAME = 'CUSTOMER'"))
        XCTAssertNoThrow(try Db2OperationAuthorizer(accessMode: .readOnly).authorizeInteractiveSQL(request))
        XCTAssertThrowsError(try IBMSystemObjectName("A' OR 1=1"))
    }

    func testSchemaDecoderUsesColumnNamesAndPreservesTransferAttributes() throws {
        let table = IBMTableIdentity(
            library: try IBMSystemObjectName("ARLIB"),
            table: try IBMSystemObjectName("CUSTOMER")
        )
        let request = TransferSchemaSQLPlanner().targetSchema(table)
        let columns = schemaColumns.reversed()
        let valuesByColumn: [String: SQLValue] = [
            "COLUMN_NAME": .string("BALANCE"),
            "SYSTEM_COLUMN_NAME": .string("BALANCE"),
            "ORDINAL_POSITION": .integer(3),
            "DATA_TYPE": .string("DECIMAL"),
            "LENGTH": .integer(11),
            "NUMERIC_SCALE": .integer(2),
            "IS_NULLABLE": .string("N"),
            "IS_UPDATABLE": .string("Y"),
            "HAS_DEFAULT": .string("N"),
            "CCSID": .null,
            "IS_IDENTITY": .string("NO"),
            "IDENTITY_GENERATION": .null,
            "HIDDEN": .string("N"),
            "HAS_FLDPROC": .string("N"),
            "DATE_FORMAT": .null,
            "DATE_SEPARATOR": .null
        ]
        let result = sqlResult(
            columns: Array(columns),
            rows: [columns.map { valuesByColumn[$0]! }]
        )
        let snapshot = try TransferSchemaSQLDecoder().decode(result, table: table, request: request)

        XCTAssertEqual(snapshot.table, table)
        XCTAssertEqual(snapshot.columns.count, 1)
        XCTAssertEqual(snapshot.columns[0].name, "BALANCE")
        XCTAssertEqual(snapshot.columns[0].typeDisplay, "DECIMAL(11,2)")
        XCTAssertFalse(snapshot.columns[0].isNullable)
        XCTAssertTrue(snapshot.columns[0].isUpdatable)
        XCTAssertEqual(snapshot.queryFingerprint, AIContentFingerprint.sha256(request.sql))
        XCTAssertNotEqual(snapshot.schemaFingerprint, snapshot.queryFingerprint)
    }

    func testSchemaDecoderRejectsDuplicateMissingMalformedTruncatedAndDuplicateOrdinals() throws {
        let table = IBMTableIdentity(
            library: try IBMSystemObjectName("ARLIB"),
            table: try IBMSystemObjectName("CUSTOMER")
        )
        let request = TransferSchemaSQLPlanner().targetSchema(table)

        XCTAssertThrowsError(try TransferSchemaSQLDecoder().decode(
            sqlResult(columns: ["COLUMN_NAME", "column_name"], rows: []),
            table: table,
            request: request
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .duplicateColumn(surface: "SYSCOLUMNS2", column: "COLUMN_NAME"))
        }

        XCTAssertThrowsError(try TransferSchemaSQLDecoder().decode(
            sqlResult(columns: ["COLUMN_NAME"], rows: []),
            table: table,
            request: request
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .missingColumn(surface: "SYSCOLUMNS2", column: "SYSTEM_COLUMN_NAME"))
        }

        XCTAssertThrowsError(try TransferSchemaSQLDecoder().decode(
            sqlResult(columns: schemaColumns, rows: [Array(repeating: .null, count: schemaColumns.count - 1)]),
            table: table,
            request: request
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .malformedRow(surface: "SYSCOLUMNS2", index: 0))
        }

        XCTAssertThrowsError(try TransferSchemaSQLDecoder().decode(
            sqlResult(columns: schemaColumns, rows: [], wasTruncated: true),
            table: table,
            request: request
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .schemaTruncated)
        }

        let first = schemaRow(name: "A", ordinal: 1, type: "CHAR", length: 4, scale: nil, ccsid: 37)
        let second = schemaRow(name: "B", ordinal: 1, type: "CHAR", length: 4, scale: nil, ccsid: 37)
        XCTAssertThrowsError(try TransferSchemaSQLDecoder().decode(
            sqlResult(columns: schemaColumns, rows: [first, second]),
            table: table,
            request: request
        )) { error in
            XCTAssertEqual(error as? DataTransferError, .duplicateOrdinal(1))
        }
    }

    func testAnalyzerBlocksAmbiguousDateAndCCSIDLossButKeepsLeadingZeros() throws {
        let csv = "CUSTOMER_NO,CUSTOMER_NAME,BALANCE,POSTAL_CODE,SHIP_DATE,NOTE,ACTIVE\n000184,Acme North,1284.50,00121,07/31/26,Expedite 📦,Y\n000185,Beta,20.00,00122,2026-07-30,Standard,N"
        let source = try DelimitedTextProfiler().parse(Data(csv.utf8), fileName: "customers.csv")
        let target = try customerTarget()
        let report = TransferSchemaAnalyzer().validate(source: source, target: target)

        XCTAssertEqual(report.blockerCount, 2)
        XCTAssertEqual(report.warningCount, 1)
        XCTAssertFalse(report.isMappingValid)
        XCTAssertFalse(report.hostWriteAvailable)
        XCTAssertEqual(report.mappings.first?.source.inferredKind, .text)
        XCTAssertEqual(report.mappings.first?.verdict, .ready)
        XCTAssertTrue(report.issues.contains { $0.code == .ambiguousDate && $0.rowNumber == 2 })
        XCTAssertTrue(report.issues.contains { $0.code == .unrepresentableText && $0.rowNumber == 2 })
        XCTAssertTrue(report.issues.contains { $0.code == .domainEvidenceMissing && $0.severity == .warning })
        XCTAssertEqual(report.receipts.last?.source, .writeExecution)
        XCTAssertFalse(report.receipts.last!.outcome.isCollected)
        XCTAssertEqual(report.receipts[1].fingerprint, target.schemaFingerprint)
    }

    func testAnalyzerRejectsTruncationDecimalOverflowAndMissingRequiredTarget() throws {
        let source = try DelimitedTextProfiler().parse(
            Data("A,B\nTOOLONG,123.456".utf8),
            fileName: "unsafe.csv"
        )
        let table = IBMTableIdentity(
            library: try IBMSystemObjectName("DEV"),
            table: try IBMSystemObjectName("TARGET")
        )
        let target = TransferTargetSnapshot(
            targetName: "DEV",
            table: table,
            capturedAt: Date(),
            columns: [
                try TransferTargetColumn(name: "A", ordinalPosition: 1, dataType: "CHAR", length: 3, isNullable: false, ccsid: 37),
                try TransferTargetColumn(name: "B", ordinalPosition: 2, dataType: "DECIMAL", length: 5, numericScale: 2, isNullable: false),
                try TransferTargetColumn(name: "C", ordinalPosition: 3, dataType: "INTEGER", length: 4, isNullable: false)
            ],
            queryFingerprint: "schema"
        )
        let report = TransferSchemaAnalyzer().validate(source: source, target: target)

        XCTAssertTrue(report.issues.contains { $0.code == .truncation })
        XCTAssertTrue(report.issues.contains { $0.code == .decimalOverflow })
        XCTAssertTrue(report.issues.contains { $0.code == .requiredTargetMissingSource })
        XCTAssertEqual(report.blockerCount, 3)
    }

    func testAnalyzerBlocksBlankScalarRulesAndLeadingZeroNumericLoss() throws {
        let source = try DelimitedTextProfiler().parse(
            Data("CODE,AMOUNT,SHIP_DATE\n0007,,".utf8),
            fileName: "rules.csv"
        )
        let table = IBMTableIdentity(
            library: try IBMSystemObjectName("DEV"),
            table: try IBMSystemObjectName("TARGET")
        )
        let target = TransferTargetSnapshot(
            targetName: "DEV",
            table: table,
            capturedAt: Date(),
            columns: [
                try TransferTargetColumn(name: "CODE", ordinalPosition: 1, dataType: "INTEGER", length: 4, isNullable: false),
                try TransferTargetColumn(name: "AMOUNT", ordinalPosition: 2, dataType: "DECIMAL", length: 9, numericScale: 2, isNullable: true),
                try TransferTargetColumn(name: "SHIP_DATE", ordinalPosition: 3, dataType: "DATE", length: 4, isNullable: true)
            ],
            queryFingerprint: "schema-query"
        )
        let report = TransferSchemaAnalyzer().validate(source: source, target: target)

        XCTAssertTrue(report.issues.contains { $0.code == .leadingZeroLoss && $0.sourceHeader == "CODE" })
        XCTAssertEqual(report.issues.filter { $0.code == .blankRequiresRule }.count, 2)
        XCTAssertEqual(report.blockerCount, 3)
        XCTAssertFalse(report.isMappingValid)
    }

    func testAnalyzerRejectsCalendarNormalizedDatesButAcceptsRealLeapDay() throws {
        let table = IBMTableIdentity(
            library: try IBMSystemObjectName("DEV"),
            table: try IBMSystemObjectName("TARGET")
        )
        let target = TransferTargetSnapshot(
            targetName: "DEV",
            table: table,
            capturedAt: Date(),
            columns: [
                try TransferTargetColumn(name: "SHIP_DATE", ordinalPosition: 1, dataType: "DATE", length: 4, isNullable: false)
            ],
            queryFingerprint: "schema-query"
        )

        for value in ["2026-02-29", "2026-04-31", "2026-13-01"] {
            let source = try DelimitedTextProfiler().parse(
                Data("SHIP_DATE\n\(value)".utf8),
                fileName: "dates.csv"
            )
            let report = TransferSchemaAnalyzer().validate(source: source, target: target)
            XCTAssertTrue(report.issues.contains { $0.code == .ambiguousDate }, value)
        }

        let leapSource = try DelimitedTextProfiler().parse(
            Data("SHIP_DATE\n2024-02-29".utf8),
            fileName: "leap.csv"
        )
        let leapReport = TransferSchemaAnalyzer().validate(source: leapSource, target: target)
        XCTAssertFalse(leapReport.issues.contains { $0.code == .ambiguousDate })
        XCTAssertTrue(leapReport.isMappingValid)
    }

    func testDataTransferAssistKindIsAdviceOnlyAndNeedsNoSelection() throws {
        XCTAssertEqual(AIContextKind.dataTransfer.label, "Data transfer")
        XCTAssertFalse(AIContextKind.dataTransfer.requiresSelection)
        XCTAssertNoThrow(try AIContextFragment(
            kind: .dataTransfer,
            documentName: "customers-transfer-validation.txt",
            language: "IBM i data-transfer validation evidence",
            sourceText: "Metadata only; no source cell values and no host write capability."
        ))
    }

    private var schemaColumns: [String] {
        [
            "COLUMN_NAME", "SYSTEM_COLUMN_NAME", "ORDINAL_POSITION", "DATA_TYPE", "LENGTH",
            "NUMERIC_SCALE", "IS_NULLABLE", "IS_UPDATABLE", "HAS_DEFAULT", "CCSID",
            "IS_IDENTITY", "IDENTITY_GENERATION", "HIDDEN", "HAS_FLDPROC", "DATE_FORMAT",
            "DATE_SEPARATOR"
        ]
    }

    private func customerTarget() throws -> TransferTargetSnapshot {
        let table = IBMTableIdentity(
            library: try IBMSystemObjectName("ARLIB"),
            table: try IBMSystemObjectName("CUSTOMER")
        )
        return TransferTargetSnapshot(
            targetName: "DEV",
            table: table,
            capturedAt: Date(),
            columns: [
                try TransferTargetColumn(name: "CUSTOMER_NO", ordinalPosition: 1, dataType: "CHAR", length: 6, isNullable: false, ccsid: 37),
                try TransferTargetColumn(name: "CUSTOMER_NAME", ordinalPosition: 2, dataType: "VARCHAR", length: 40, isNullable: false, ccsid: 37),
                try TransferTargetColumn(name: "BALANCE", ordinalPosition: 3, dataType: "DECIMAL", length: 11, numericScale: 2, isNullable: false),
                try TransferTargetColumn(name: "POSTAL_CODE", ordinalPosition: 4, dataType: "CHAR", length: 5, isNullable: false, ccsid: 37),
                try TransferTargetColumn(name: "SHIP_DATE", ordinalPosition: 5, dataType: "DATE", length: 4, isNullable: false),
                try TransferTargetColumn(name: "NOTE", ordinalPosition: 6, dataType: "VARCHAR", length: 80, isNullable: true, ccsid: 37),
                try TransferTargetColumn(name: "ACTIVE", ordinalPosition: 7, dataType: "CHAR", length: 1, isNullable: false, ccsid: 37)
            ],
            queryFingerprint: "schema"
        )
    }

    private func schemaRow(
        name: String,
        ordinal: Int,
        type: String,
        length: Int,
        scale: Int?,
        ccsid: Int?
    ) -> [SQLValue] {
        [
            .string(name), .string(name), .integer(Int64(ordinal)), .string(type), .integer(Int64(length)),
            scale.map { .integer(Int64($0)) } ?? .null,
            .string("N"), .string("Y"), .string("N"),
            ccsid.map { .integer(Int64($0)) } ?? .null,
            .string("NO"), .null, .string("N"), .string("N"), .null, .null
        ]
    }

    private func sqlResult(
        columns: [String],
        rows: [[SQLValue]],
        wasTruncated: Bool = false
    ) -> SQLResult {
        SQLResult(
            columns: columns.map { SQLColumn(name: $0, databaseType: "VARCHAR", isNullable: true) },
            rows: rows,
            targetName: "DEV",
            startedAt: Date(timeIntervalSince1970: 1_000),
            elapsedMilliseconds: 12,
            wasTruncated: wasTruncated
        )
    }
}

private extension Data {
    init(hexadecimal: String) {
        var bytes: [UInt8] = []
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2)
            bytes.append(UInt8(hexadecimal[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
