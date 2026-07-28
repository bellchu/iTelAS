import Foundation
import XCTest
@testable import iTelASCore

final class SourceCompletionTests: XCTestCase {
    private let analyzer = SourceIntelligenceAnalyzer()
    private let engine = SourceCompletionEngine()

    func testQualifiedRPGCompletionReplacesOnlyTheFieldPrefix() throws {
        let source = """
        **free
        dcl-ds customer qualified;
          number packed(9:0);
          name varchar(80);
        end-ds;
        customer.na
        """
        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "CUSTSRV.rpgle")
        let session = engine.complete(
            text: source,
            format: .rpgle,
            caretUTF16: source.utf16.count,
            snapshot: snapshot
        )

        XCTAssertEqual(session.status, .ready)
        XCTAssertEqual(session.qualifier, "customer")
        XCTAssertEqual(session.prefix, "na")
        XCTAssertEqual(session.replacementRange.length, 2)
        XCTAssertEqual(session.items.first?.label, "name")

        let edit = try session.validatedEdit(for: session.items[0].id, in: source)
        let application = try edit.applying(to: source)
        XCTAssertTrue(application.text.hasSuffix("customer.name"))
        XCTAssertEqual(application.cursorUTF16, application.text.utf16.count)
    }

    func testQualifiedRPGCompletionRanksDeclaredFieldsThenRelatedSymbols() {
        let source = """
        **free
        dcl-ds customer qualified;
          number packed(9:0);
          name varchar(80);
        end-ds;
        dcl-pr FindCustomer ind;
        end-pr;
        customer.
        """
        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "CUSTSRV.rpgle")
        let session = engine.complete(
            text: source,
            format: .rpgle,
            caretUTF16: source.utf16.count,
            snapshot: snapshot
        )

        XCTAssertEqual(session.items.prefix(4).map(\.label), ["number", "name", "customer", "FindCustomer"])
        XCTAssertEqual(session.items[0].kind, .field)
        XCTAssertEqual(session.items[0].sourceLine, 3)
        XCTAssertEqual(session.items.last?.action, .openAssistReview)
        XCTAssertEqual(session.boundaryLabel, "Local completion · no host lookup")
    }

    func testCurrentDocumentSymbolsRankAheadOfLanguageCatalog() {
        let source = "**free\ndcl-s returnCode int(10);\nret"
        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "RETURNER.rpgle")
        let session = engine.complete(
            text: source,
            format: .rpgle,
            caretUTF16: source.utf16.count,
            snapshot: snapshot
        )

        XCTAssertEqual(session.items.first?.label, "returnCode")
        XCTAssertEqual(session.items.first?.origin, .currentDocument)
        XCTAssertTrue(session.items.contains { $0.label == "return" && $0.origin == .languageCatalog })
        XCTAssertEqual(session.replacementRange, SourceUTF16Range(location: source.utf16.count - 3, length: 3))
    }

    func testCompletionIsSuppressedInsideStringAndCommentEvidence() {
        let stringSource = "**free\ndsply ('customer.na');"
        let stringSnapshot = analyzer.analyze(text: stringSource, format: .rpgle, documentName: "SAFE.rpgle")
        let stringLocation = (stringSource as NSString).range(of: "customer.na").location + 6
        let stringSession = engine.complete(
            text: stringSource,
            format: .rpgle,
            caretUTF16: stringLocation,
            snapshot: stringSnapshot
        )

        let commentSource = "**free\n// customer.na"
        let commentSnapshot = analyzer.analyze(text: commentSource, format: .rpgle, documentName: "SAFE.rpgle")
        let commentSession = engine.complete(
            text: commentSource,
            format: .rpgle,
            caretUTF16: commentSource.utf16.count,
            snapshot: commentSnapshot
        )

        XCTAssertEqual(stringSession.status, .suppressed)
        XCTAssertTrue(stringSession.items.isEmpty)
        XCTAssertEqual(commentSession.status, .suppressed)
        XCTAssertTrue(commentSession.items.isEmpty)
    }

    func testStaleSnapshotAndInvalidUnicodeCaretFailClosed() {
        let original = "**free\ndcl-s customer int(10);"
        let snapshot = analyzer.analyze(text: original, format: .rpgle, documentName: "SAFE.rpgle")
        let stale = engine.complete(
            text: original + "\ncustomer",
            format: .rpgle,
            caretUTF16: original.utf16.count,
            snapshot: snapshot
        )

        let emoji = "😀"
        let emojiSnapshot = analyzer.analyze(text: emoji, format: .text, documentName: "note.txt")
        let invalidCaret = engine.complete(
            text: emoji,
            format: .text,
            caretUTF16: 1,
            snapshot: emojiSnapshot
        )

        XCTAssertEqual(stale.status, .staleSnapshot)
        XCTAssertEqual(invalidCaret.status, .invalidCaret)
    }

    func testCandidateAndItemCapsAreDeterministicAndExplicit() {
        let source = "**free\ndcl-s alpha int(10);\ndcl-s beta int(10);\ndcl-s gamma int(10);\n"
        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "BOUNDED.rpgle")
        let bounded = SourceCompletionEngine(limits: SourceCompletionLimits(
            maximumItems: 2,
            maximumCandidates: 2,
            maximumPrefixUTF16Units: 32
        ))

        let first = bounded.complete(
            text: source,
            format: .rpgle,
            caretUTF16: source.utf16.count,
            snapshot: snapshot,
            includeAssistReview: false
        )
        let second = bounded.complete(
            text: source,
            format: .rpgle,
            caretUTF16: source.utf16.count,
            snapshot: snapshot,
            includeAssistReview: false
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.items.count, 2)
        XCTAssertTrue(first.wasLimited)
    }

    func testOversizedPrefixIsRefusedWithoutScanningPastItsBound() {
        let source = "**free\n" + String(repeating: "a", count: 12)
        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "BOUNDED.rpgle")
        let bounded = SourceCompletionEngine(limits: SourceCompletionLimits(
            maximumItems: 8,
            maximumCandidates: 32,
            maximumPrefixUTF16Units: 8
        ))
        let session = bounded.complete(
            text: source,
            format: .rpgle,
            caretUTF16: source.utf16.count,
            snapshot: snapshot
        )

        XCTAssertEqual(session.status, .analysisLimited)
        XCTAssertTrue(session.wasLimited)
        XCTAssertTrue(session.items.isEmpty)
    }

    func testAssistCompletionNeverProducesAnInsertEditAndStaleApplyIsRejected() throws {
        let source = "**free\ndcl-ds customer qualified;\n  number packed(9:0);\nend-ds;\ncustomer."
        let snapshot = analyzer.analyze(text: source, format: .rpgle, documentName: "CUSTSRV.rpgle")
        let session = engine.complete(
            text: source,
            format: .rpgle,
            caretUTF16: source.utf16.count,
            snapshot: snapshot
        )
        let assist = try XCTUnwrap(session.items.first(where: { $0.action == .openAssistReview }))
        let insert = try XCTUnwrap(session.items.first(where: { $0.action == .insertText }))

        XCTAssertNotNil(assist.sourceSymbolID)
        XCTAssertThrowsError(try session.validatedEdit(for: assist.id, in: source)) { error in
            XCTAssertEqual(error as? SourceCompletionError, .nonInsertAction)
        }
        XCTAssertThrowsError(try session.validatedEdit(for: insert.id, in: source + " ")) { error in
            XCTAssertEqual(error as? SourceCompletionError, .staleDocument)
        }
    }
}
