import XCTest
@testable import iTelASCore

final class SourceIntelligenceTests: XCTestCase {
    private let analyzer = SourceIntelligenceAnalyzer()

    func testFullyFreeMarkerMustBeFirstPhysicalLine() {
        let fullyFree = analyzer.analyze(
            text: "**free\ndcl-s value int(10);",
            format: .rpgle,
            documentName: "SAMPLE.rpgle"
        )
        let misplaced = analyzer.analyze(
            text: "\n**free\ndcl-s value int(10);",
            format: .rpgle,
            documentName: "SAMPLE.rpgle"
        )

        XCTAssertEqual(fullyFree.dialect, .rpgleFullyFree)
        XCTAssertNotEqual(misplaced.dialect, .rpgleFullyFree)
    }

    func testRPGOutlineFindsFileStructuresPrototypeProcedureAndParameters() {
        let source = """
        **free
        dcl-f CUSTMAST keyed usage(*input);
        dcl-ds customer qualified;
          number packed(9:0);
          name varchar(80);
        end-ds;
        dcl-pr FindCustomer ind;
          customerNumber packed(9:0) const;
        end-pr;
        dcl-proc LoadCustomer;
          dcl-pi *n ind;
            customerNumber packed(9:0) const;
          end-pi;
          return FindCustomer(customerNumber);
        end-proc;
        """

        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "CUSTSRV.rpgle")

        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .program && $0.name == "CUSTSRV" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .file && $0.name == "CUSTMAST" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .dataStructure && $0.name == "customer" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .field && $0.name == "number" && $0.containerName == "customer" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .prototype && $0.name == "FindCustomer" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .procedure && $0.name == "LoadCustomer" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .parameter && $0.name == "customerNumber" })
        XCTAssertTrue(snapshot.references.contains {
            $0.kind == .procedureCall && $0.target == .symbol("FindCustomer") && $0.resolution == .currentDocument
        })
        XCTAssertTrue(snapshot.checks.isEmpty)
    }

    func testRPGCopyAndIncludeTargetsStayTypedAndExternal() {
        let source = """
        **free
        /copy DEVLIB/QRPGLESRC,CUSCOPY
        /include '/includes/audittypes.rpgleinc'
        """

        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "CUSTSRV.rpgle")

        XCTAssertEqual(snapshot.references.count, 2)
        XCTAssertEqual(
            snapshot.references[0].target,
            .member(library: "DEVLIB", sourceFile: "QRPGLESRC", member: "CUSCOPY")
        )
        XCTAssertEqual(snapshot.references[0].resolution, .contentNotLoaded)
        XCTAssertEqual(snapshot.references[1].target, .ifsPath("/includes/audittypes.rpgleinc"))
        XCTAssertEqual(snapshot.references[1].resolution, .contentNotLoaded)
    }

    func testRPGStructuralChecksAreLocalAndLineSpecific() {
        let snapshot = analyzer.analyze(
            text: "**free\ndcl-proc LoadCustomer;\ndcl-pi *n ind;\nend-pi;",
            format: .rpgle,
            documentName: "CUSTSRV.rpgle"
        )

        XCTAssertEqual(snapshot.checks.count, 1)
        XCTAssertEqual(snapshot.checks[0].kind, .incompleteStructure)
        XCTAssertEqual(snapshot.checks[0].range.startLine, 2)
        XCTAssertTrue(snapshot.checks[0].message.contains("END-PROC"))
        XCTAssertEqual(snapshot.boundaryLabel, "Local heuristic · not a compiler result")
        XCTAssertTrue(snapshot.limitations[0].contains("not IBM compiler diagnostics"))
    }

    func testRPGPrototypeAndImplementationMayShareANameWithoutDuplicateCallScanning() {
        let source = """
        **free
        dcl-pr Work ind;
          value int(10) const;
        end-pr;
        dcl-proc Work;
          dcl-pi *n ind;
            value int(10) const;
          end-pi;
          dsply ('Work( is text');
          return Work (value);
        end-proc;
        """

        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "WORKER.rpgle")
        let calls = snapshot.references.filter { $0.kind == .procedureCall && $0.target == .symbol("Work") }

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].range.startLine, 10)
    }

    func testRPGCommentsAndQuotedSlashesDoNotCreateDeclarations() {
        let source = """
        **free
        // dcl-proc Fabricated;
        dcl-s url varchar(100) inz('https://example.test/dcl-proc');
        /* dcl-pr NotParsed ind; */
        """

        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "SAFE.rpgle")

        XCTAssertFalse(snapshot.symbols.contains { $0.name == "Fabricated" || $0.name == "NotParsed" })
        XCTAssertTrue(snapshot.symbols.contains { $0.name == "url" && $0.kind == .variable })
    }

    func testColumnLimitedRPGFindsFixedDefinitionAndFile() {
        let source = """
             FCUSTMAST  IF   E           K DISK
             DCustomer        S             10A
        """
        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "FIXED.rpgle")

        XCTAssertEqual(snapshot.dialect, .rpgleColumnLimited)
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .file && $0.name == "CUSTMAST" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .variable && $0.name == "Customer" })
    }

    func testCLOutlineAndCallsIgnoreBlockComments() {
        let source = """
        PGM
        DCL VAR(&CUSTNO) TYPE(*DEC) LEN(9 0)
        DCLF FILE(DEVLIB/CUSTDSPF)
        /* CALL PGM(BADLIB/BADPGM) */
        CALL PGM(DEVLIB/CUSTSRV)
        CALLPRC PRC(LoadCustomer)
        CLEANUP: RETURN
        ENDPGM
        """
        let snapshot = analyzer.analyze(text: source, format: .clle, documentName: "CUSTCTL.clle")

        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .program && $0.name == "CUSTCTL" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .variable && $0.name == "&CUSTNO" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .file && $0.name == "CUSTDSPF" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .label && $0.name == "CLEANUP" })
        XCTAssertTrue(snapshot.references.contains { $0.target == .object("DEVLIB/CUSTSRV") })
        XCTAssertTrue(snapshot.references.contains { $0.target == .symbol("LoadCustomer") })
        XCTAssertFalse(snapshot.references.contains { $0.target.displayName.contains("BAD") })
        XCTAssertTrue(snapshot.checks.isEmpty)
    }

    func testCOBOLOutlineFindsProgramSectionsDataAndCalls() {
        let source = """
              IDENTIFICATION DIVISION.
              PROGRAM-ID. CUSTBATCH.
              DATA DIVISION.
              WORKING-STORAGE SECTION.
              01 CUSTOMER-RECORD.
                 05 CUSTOMER-NUMBER PIC 9(9).
              PROCEDURE DIVISION.
              MAIN-PARAGRAPH.
                  COPY CUSTCOPY.
                  CALL 'CUSTSRV'.
                  GOBACK.
        """
        let snapshot = analyzer.analyze(text: source, format: .cobol, documentName: "CUSTBATCH.cblle")

        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .program && $0.name == "CUSTBATCH" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .section && $0.name == "WORKING-STORAGE" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .field && $0.name == "CUSTOMER-RECORD" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .paragraph && $0.name == "MAIN-PARAGRAPH" })
        XCTAssertTrue(snapshot.references.contains { $0.kind == .copy && $0.target == .unqualified("CUSTCOPY") })
        XCTAssertTrue(snapshot.references.contains { $0.kind == .programCall && $0.target == .object("CUSTSRV") })
    }

    func testDDSOutlineFindsFormatsFieldsAndExternalReferences() {
        let source = """
             A          R CUSTREC
             A            CUSTNO        9P 0
             A            CUSTNAME     50A
             A          K CUSTNO
             A          PFILE(DEVLIB/CUSTBASE)
             A            STATUS         R  REFFLD(STATUS DEVLIB/CUSTREF)
        """
        let snapshot = analyzer.analyze(text: source, format: .dds, documentName: "CUSTDSPF.dspf")

        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .recordFormat && $0.name == "CUSTREC" })
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .field && $0.name == "CUSTNO" && $0.containerName == "CUSTREC" })
        XCTAssertTrue(
            snapshot.references.contains { $0.kind == .file && $0.target == .object("DEVLIB/CUSTBASE") },
            "Unexpected references: \(snapshot.references)"
        )
        XCTAssertTrue(snapshot.references.contains { $0.kind == .field && $0.target == .unqualified("STATUS DEVLIB/CUSTREF") })
    }

    func testSQLBoundaryPointsToDb2Studio() {
        let snapshot = analyzer.analyze(
            text: "CREATE PROCEDURE DEVLIB.CUSTSRV() LANGUAGE SQL BEGIN END;",
            format: .sql,
            documentName: "CUSTSRV.sql"
        )

        XCTAssertEqual(snapshot.dialect, .sql)
        XCTAssertTrue(snapshot.symbols.contains { $0.kind == .sqlObject && $0.name == "DEVLIB.CUSTSRV" })
        XCTAssertEqual(snapshot.checks.first?.kind, .languageBoundary)
        XCTAssertTrue(snapshot.checks.first?.message.contains("Db2 SQL Studio") == true)
    }

    func testAnalysisLimitsSkipParsingWithoutLosingStableReceipt() {
        let bounded = SourceIntelligenceAnalyzer(limits: SourceIntelligenceLimits(
            maximumUTF8Bytes: 12,
            maximumLines: 10,
            maximumUTF16UnitsPerLine: 100
        ))
        let text = "**free\ndcl-s customerNumber int(10);"
        let first = bounded.analyze(text: text, format: .rpgle, documentName: "LIMIT.rpgle")
        let second = bounded.analyze(text: text, format: .rpgle, documentName: "LIMIT.rpgle")

        XCTAssertTrue(first.wasLimited)
        XCTAssertEqual(first.analyzedLineCount, 0)
        XCTAssertTrue(first.symbols.isEmpty)
        XCTAssertEqual(first.checks.first?.kind, .analysisLimit)
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.fingerprint.count, 64)
    }

    func testFingerprintChangesWithTextAndIdentifiersNeverContainControls() {
        let first = analyzer.analyze(text: "**free\ndcl-s good int(10);", format: .rpgle, documentName: "SAFE.rpgle")
        let second = analyzer.analyze(text: "**free\ndcl-s better int(10);", format: .rpgle, documentName: "SAFE.rpgle")
        let controls = analyzer.analyze(text: "**free\ndcl-s bad\u{0001}name int(10);", format: .rpgle, documentName: "SAFE.rpgle")

        XCTAssertNotEqual(first.fingerprint, second.fingerprint)
        XCTAssertFalse(controls.symbols.contains { $0.name.contains("\u{0001}") })
    }

    func testSourceRangeConvertsOneBasedCoordinatesToExactUTF16Selection() {
        let text = "alpha\nemoji 😀 value\nomega"
        let range = SourceTextRange(startLine: 2, startColumn: 7, endColumn: 9)

        let selection = range.utf16Range(in: text)

        XCTAssertEqual(selection, NSRange(location: 12, length: 2))
        XCTAssertEqual((text as NSString).substring(with: selection!), "😀")
        XCTAssertNil(SourceTextRange(startLine: 9, startColumn: 1).utf16Range(in: text))
    }

    func testRPGHighlightingSeparatesDirectivesDeclarationsTypesLiteralsBuiltInsAndComments() {
        let source = """
        **free
        /copy DEVLIB/QRPGLESRC,CUSCOPY
        dcl-s endpoint varchar(80) inz('https://example.test/a');
        dcl-proc LoadCustomer;
          if %found(CUSTMAST);
            dsply ('ready'); // operator trace
          endif;
        end-proc;
        """
        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "CUSTSRV.rpgle")
        let repeatedSnapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "CUSTSRV.rpgle")

        XCTAssertEqual(
            highlightedText(.directive, in: snapshot, source: source),
            ["**free", "/copy DEVLIB/QRPGLESRC,CUSCOPY"]
        )
        XCTAssertTrue(highlightedText(.keyword, in: snapshot, source: source).contains("dcl-proc"))
        XCTAssertTrue(highlightedText(.declaration, in: snapshot, source: source).contains("LoadCustomer"))
        XCTAssertTrue(highlightedText(.typeName, in: snapshot, source: source).contains("varchar"))
        XCTAssertTrue(highlightedText(.builtIn, in: snapshot, source: source).contains("%found"))
        XCTAssertTrue(highlightedText(.stringLiteral, in: snapshot, source: source).contains("'https://example.test/a'"))
        XCTAssertEqual(highlightedText(.comment, in: snapshot, source: source), ["// operator trace"])
        XCTAssertFalse(snapshot.highlightingWasLimited)
        XCTAssertEqual(snapshot.highlights, repeatedSnapshot.highlights)
    }

    func testCLBlockCommentsRemainCommentsAcrossLines() {
        let source = """
        PGM
        /* CALL PGM(BADPGM)
           DCL VAR(&BAD) TYPE(*CHAR) */
        DCL VAR(&GOOD) TYPE(*CHAR)
        ENDPGM
        """
        let snapshot = analyzer.analyze(text: source, format: .clle, documentName: "CONTROL.clle")
        let comments = highlightedText(.comment, in: snapshot, source: source)

        XCTAssertEqual(comments.count, 2)
        XCTAssertTrue(comments[0].contains("BADPGM"))
        XCTAssertTrue(comments[1].contains("&BAD"))
        XCTAssertTrue(highlightedText(.keyword, in: snapshot, source: source).contains("DCL"))
        XCTAssertTrue(highlightedText(.declaration, in: snapshot, source: source).contains("&GOOD"))
    }

    func testCOBOLDDSAndSQLHighlightTheirOwnVocabulary() {
        let cobol = "       PROCEDURE DIVISION.\n       MAIN-PARA.\n           CALL 'CUSTSRV'."
        let cobolSnapshot = analyzer.analyze(text: cobol, format: .cobol, documentName: "BATCH.cblle")
        XCTAssertTrue(highlightedText(.keyword, in: cobolSnapshot, source: cobol).contains("PROCEDURE"))
        XCTAssertTrue(highlightedText(.declaration, in: cobolSnapshot, source: cobol).contains("MAIN-PARA"))
        XCTAssertTrue(highlightedText(.stringLiteral, in: cobolSnapshot, source: cobol).contains("'CUSTSRV'"))

        let dds = "     A          R CUSTREC\n     A            CUSTNO        9P 0"
        let ddsSnapshot = analyzer.analyze(text: dds, format: .dds, documentName: "CUSTDSPF.dspf")
        XCTAssertTrue(highlightedText(.keyword, in: ddsSnapshot, source: dds).contains("R"))
        XCTAssertTrue(highlightedText(.declaration, in: ddsSnapshot, source: dds).contains("CUSTREC"))
        XCTAssertTrue(highlightedText(.number, in: ddsSnapshot, source: dds).contains("9"))

        let sql = "SELECT CUSTOMER_NUMBER FROM DEVLIB.CUSTOMER WHERE STATUS = 'A' -- active only"
        let sqlSnapshot = analyzer.analyze(text: sql, format: .sql, documentName: "query.sql")
        XCTAssertTrue(highlightedText(.keyword, in: sqlSnapshot, source: sql).contains("SELECT"))
        XCTAssertTrue(highlightedText(.keyword, in: sqlSnapshot, source: sql).contains("WHERE"))
        XCTAssertTrue(highlightedText(.stringLiteral, in: sqlSnapshot, source: sql).contains("'A'"))
        XCTAssertEqual(highlightedText(.comment, in: sqlSnapshot, source: sql), ["-- active only"])
    }

    func testSQLBlockCommentCanCloseBeforeCodeOnALineStartingWithLineCommentMarker() {
        let source = """
        /* maintenance note
        -- still inside block */ SELECT CUSTOMER_NUMBER FROM DEVLIB.CUSTOMER
        """
        let snapshot = analyzer.analyze(text: source, format: .sql, documentName: "query.sql")

        XCTAssertEqual(
            highlightedText(.comment, in: snapshot, source: source),
            ["/* maintenance note", "-- still inside block */"]
        )
        XCTAssertTrue(highlightedText(.keyword, in: snapshot, source: source).contains("SELECT"))
    }

    func testHighlightCapIsExplicitAndEveryReturnedSpanIsInBounds() {
        let source = "**free\ndcl-s one int(10);\ndcl-s two varchar(20);"
        let highlighter = SourceSyntaxHighlighter(limits: SourceIntelligenceLimits(
            maximumUTF8Bytes: 1_024,
            maximumLines: 10,
            maximumUTF16UnitsPerLine: 100,
            maximumHighlightSpans: 3
        ))
        let result = highlighter.highlight(
            text: source,
            format: .rpgle,
            dialect: .rpgleFullyFree,
            symbols: []
        )

        XCTAssertTrue(result.wasLimited)
        XCTAssertEqual(result.spans.count, 3)
        for span in result.spans {
            let range = span.range.utf16Range(in: source)
            XCTAssertNotNil(range)
            XCTAssertLessThanOrEqual(NSMaxRange(range!), source.utf16.count)
        }
    }

    private func highlightedText(
        _ kind: SourceHighlightKind,
        in snapshot: SourceIntelligenceSnapshot,
        source: String
    ) -> [String] {
        snapshot.highlights.compactMap { span in
            guard span.kind == kind,
                  let range = span.range.utf16Range(in: source) else { return nil }
            return (source as NSString).substring(with: range)
        }
    }
}
