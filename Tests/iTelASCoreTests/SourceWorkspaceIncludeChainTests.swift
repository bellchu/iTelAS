import XCTest
@testable import iTelASCore

final class SourceWorkspaceIncludeChainTests: XCTestCase {
    func testRecursiveClosureTracksExactSharedRoutesDeterministically() throws {
        let files = try [
            source("src/root.rpgle", """
            **free
            /copy includes/alpha
            /include includes/beta
            """),
            source("includes/alpha.cpy", """
            **free
            /include common/decimal
            """),
            source("includes/beta.cpy", """
            **free
            /copy common/decimal
            """),
            source("common/decimal.cpy", "**free\ndcl-c Scale 2;")
        ]
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "INCLUDE MAP", files: files)

        let first = try index.includeChain(for: "src/root.rpgle")
        let second = try index.includeChain(for: "SRC/ROOT.RPGLE")

        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.completion, .exact)
        XCTAssertEqual(first.documents.map(\.relativePath), [
            "src/root.rpgle",
            "includes/alpha.cpy",
            "includes/beta.cpy",
            "common/decimal.cpy"
        ])
        XCTAssertEqual(first.documents.map(\.depth), [0, 1, 1, 2])
        XCTAssertEqual(first.directives.map(\.resolution), [.exact, .exact, .exact, .shared])
        XCTAssertEqual(first.maximumDepthObserved, 2)
        XCTAssertTrue(first.boundaries.isEmpty)
        XCTAssertTrue(first.isCurrent(for: index, rootPath: "src/root.rpgle"))
    }

    func testCycleAmbiguityAndHostContentRemainVisibleBoundaries() throws {
        let files = try [
            source("src/root.rpgle", """
            **free
            /copy includes/alpha
            /copy QRPGLESRC,MISSING
            /copy shared
            """),
            source("includes/alpha.cpy", "**free\n/copy src/root"),
            source("one/shared.cpy", "**free\ndcl-c One 1;"),
            source("two/shared.cpy", "**free\ndcl-c Two 2;")
        ]
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "BOUNDARIES", files: files)

        let chain = try index.includeChain(for: "src/root.rpgle")

        XCTAssertEqual(chain.completion, .boundariesVisible)
        XCTAssertEqual(Set(chain.boundaries.map(\.kind)), [
            .cycle, .hostContentNotLoaded, .ambiguous
        ])
        XCTAssertTrue(chain.directives.contains {
            $0.resolution == .cycle
                && $0.routePaths == ["src/root.rpgle", "includes/alpha.cpy", "src/root.rpgle"]
        })
        XCTAssertTrue(chain.boundaries.contains {
            $0.kind == .ambiguous && $0.candidatePaths.count == 2
        })
        XCTAssertTrue(chain.boundaries.contains {
            $0.kind == .hostContentNotLoaded && $0.targetLabel.contains("MISSING")
        })
        XCTAssertEqual(chain.exactDocumentPaths, ["src/root.rpgle", "includes/alpha.cpy"])
    }

    func testTraversalCapsFailClosedWithoutExpandingUnreviewedDocuments() throws {
        let files = try [
            source("src/root.rpgle", """
            **free
            /copy includes/alpha
            /copy includes/beta
            """),
            source("includes/alpha.cpy", "**free\n/copy common/gamma"),
            source("includes/beta.cpy", "**free\ndcl-c Beta 2;"),
            source("common/gamma.cpy", "**free\ndcl-c Gamma 3;")
        ]
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "LIMITS", files: files)

        let documentLimited = try index.includeChain(
            for: "src/root.rpgle",
            limits: SourceWorkspaceIncludeChainLimits(maximumDocuments: 1)
        )
        XCTAssertEqual(documentLimited.documents.map(\.relativePath), ["src/root.rpgle"])
        XCTAssertEqual(documentLimited.directives.map(\.resolution), [.documentLimit, .documentLimit])
        XCTAssertEqual(documentLimited.completion, .traversalLimitReached)

        let directiveLimited = try index.includeChain(
            for: "src/root.rpgle",
            limits: SourceWorkspaceIncludeChainLimits(maximumDirectives: 1)
        )
        XCTAssertEqual(directiveLimited.directives.count, 1)
        XCTAssertEqual(directiveLimited.boundaries.last?.kind, .directiveLimit)
        XCTAssertEqual(directiveLimited.completion, .traversalLimitReached)

        let depthLimited = try index.includeChain(
            for: "src/root.rpgle",
            limits: SourceWorkspaceIncludeChainLimits(maximumDepth: 1)
        )
        XCTAssertTrue(depthLimited.boundaries.contains { $0.kind == .depthLimit })
        XCTAssertFalse(depthLimited.documents.contains { $0.relativePath == "common/gamma.cpy" })
        XCTAssertEqual(depthLimited.completion, .traversalLimitReached)
    }

    func testChainBecomesStaleWhenAnyIndexedEvidenceChanges() throws {
        let files = try [
            source("src/root.rpgle", "**free\n/copy includes/alpha"),
            source("includes/alpha.cpy", "**free\ndcl-c Alpha 1;"),
            source("src/unrelated.rpgle", "**free\ndcl-s Value int(10);")
        ]
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "CURRENT", files: files)
        let chain = try index.includeChain(for: "src/root.rpgle")
        var changed = files
        changed[2] = try source("src/unrelated.rpgle", "**free\ndcl-s Changed int(10);")
        let refreshed = try SourceWorkspaceIndexBuilder().build(rootName: "CURRENT", files: changed)

        XCTAssertTrue(chain.isCurrent(for: index))
        XCTAssertFalse(chain.isCurrent(for: refreshed))
    }

    private func source(_ relativePath: String, _ text: String) throws -> SourceWorkspaceFile {
        try SourceWorkspaceFile(
            relativePath: relativePath,
            format: .rpgle,
            text: text,
            modifiedAt: Date(timeIntervalSince1970: 1_785_180_486)
        )
    }
}
