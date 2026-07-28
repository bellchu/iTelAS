import XCTest
@testable import iTelASCore

final class SourceWorkspaceCompileEvidenceTests: XCTestCase {
    private let runFingerprint = String(repeating: "a", count: 64)
    private let reviewedAt = Date(timeIntervalSince1970: 1_785_180_486)

    func testTargetReleaseEvidenceResolvesExactRelativeAndMissingContexts() throws {
        let current = try CompileTargetReleaseEvidence(
            commandText: "CRTBNDRPG OPTION(*EVENTF) TGTRLS(*CURRENT)",
            observedHostRelease: "V7R6M0"
        )
        XCTAssertEqual(current.commandToken, .current)
        XCTAssertEqual(current.effectiveTargetRelease, try IBMReleaseLevel("V7R6M0"))
        XCTAssertEqual(current.resolution, .exact)

        let previous = try CompileTargetReleaseEvidence(
            commandText: "CRTBNDRPG TGTRLS(*PRV)",
            observedHostRelease: "V7R6M0"
        )
        XCTAssertEqual(previous.commandToken, .previous)
        XCTAssertEqual(previous.effectiveTargetRelease, try IBMReleaseLevel("V7R5M0"))
        XCTAssertEqual(previous.resolution, .exact)

        let specific = try CompileTargetReleaseEvidence(commandText: "CRTSQLRPGI TGTRLS(V7R4M0)")
        XCTAssertEqual(specific.commandToken, .specific(try IBMReleaseLevel("V7R4M0")))
        XCTAssertEqual(specific.effectiveTargetRelease, try IBMReleaseLevel("V7R4M0"))
        XCTAssertEqual(specific.resolution, .exact)

        let relative = try CompileTargetReleaseEvidence(commandText: "CRTBNDRPG TGTRLS(*CURRENT)")
        XCTAssertNil(relative.effectiveTargetRelease)
        XCTAssertEqual(relative.resolution, .relative)

        let missing = try CompileTargetReleaseEvidence(commandText: "CRTBNDRPG OPTION(*EVENTF)")
        XCTAssertEqual(missing.commandToken, .notRecorded)
        XCTAssertEqual(missing.resolution, .missing)

        XCTAssertThrowsError(try CompileTargetReleaseEvidence(
            commandText: "CRTBNDRPG TGTRLS(*CURRENT) TGTRLS(V7R5M0)",
            observedHostRelease: "V7R6M0"
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceCompileEvidenceError, .conflictingTargetReleaseTokens)
        }
        XCTAssertThrowsError(try CompileTargetReleaseEvidence(commandText: "CRTBNDRPG TGTRLS(VXRYMZ)"))
    }

    func testMatcherRanksLocalMemberAndIFSIdentitiesWithoutReadingAHost() throws {
        let localIndex = try makeIndex([
            ("qrpglesrc/orderentry.rpgle", "**free\nreturn;")
        ])
        let memberFile = CompileEvidenceSourceFile(
            processorSequence: 1,
            fileIdentifier: "001",
            path: "ARLIB/QRPGLESRC(ORDERENTRY)"
        )
        let localCandidate = try XCTUnwrap(
            SourceWorkspaceCompileEvidenceMatcher().candidates(for: memberFile, in: localIndex).first
        )
        XCTAssertEqual(localCandidate.documentPath, "qrpglesrc/orderentry.rpgle")
        XCTAssertEqual(localCandidate.basis, .exactBaseName)

        let memberBase = try makeIndex([
            ("src/main.rpgle", "**free\n/include ARLIB/QRPGLESRC,ORDERENTRY")
        ])
        let memberEdge = try XCTUnwrap(memberBase.outboundDependencies(for: "src/main.rpgle").first)
        let memberReview = try ReviewedSourceWorkspaceHostInclude(
            index: memberBase,
            dependencyID: memberEdge.id,
            reviewedAt: reviewedAt
        )
        let memberContent = try SourceWorkspaceHostIncludeContent(
            request: memberReview,
            actualTarget: memberReview.target,
            providerName: "LOCAL FIXTURE",
            targetName: "REPLAY",
            text: "**free\nreturn;",
            format: .rpgle,
            ccsid: 37,
            remoteRevision: "fixture:member:1",
            capturedAt: reviewedAt
        )
        let memberIndex = try memberBase.appendingHostInclude(memberContent)
        let memberCandidate = try XCTUnwrap(
            SourceWorkspaceCompileEvidenceMatcher().candidates(for: memberFile, in: memberIndex).first
        )
        XCTAssertEqual(memberCandidate.documentPath, memberContent.overlayRelativePath)
        XCTAssertEqual(memberCandidate.basis, .exactHostIdentity)
        XCTAssertEqual(memberCandidate.rank, 0)

        let ifsPath = "/home/dev/includes/orderentry.rpgle"
        let ifsBase = try makeIndex([
            ("src/main.rpgle", "**free\n/copy '\(ifsPath)'")
        ])
        let ifsEdge = try XCTUnwrap(ifsBase.outboundDependencies(for: "src/main.rpgle").first)
        let ifsReview = try ReviewedSourceWorkspaceHostInclude(
            index: ifsBase,
            dependencyID: ifsEdge.id,
            reviewedAt: reviewedAt
        )
        let ifsContent = try SourceWorkspaceHostIncludeContent(
            request: ifsReview,
            actualTarget: ifsReview.target,
            providerName: "LOCAL FIXTURE",
            targetName: "REPLAY",
            text: "**free\nreturn;",
            format: .rpgle,
            ccsid: 1208,
            remoteRevision: "fixture:ifs:1",
            capturedAt: reviewedAt
        )
        let ifsIndex = try ifsBase.appendingHostInclude(ifsContent)
        let ifsFile = CompileEvidenceSourceFile(
            processorSequence: 1,
            fileIdentifier: "001",
            path: ifsPath
        )
        let ifsCandidate = try XCTUnwrap(
            SourceWorkspaceCompileEvidenceMatcher().candidates(for: ifsFile, in: ifsIndex).first
        )
        XCTAssertEqual(ifsCandidate.documentPath, ifsContent.overlayRelativePath)
        XCTAssertEqual(ifsCandidate.basis, .exactIFSIdentity)
        XCTAssertEqual(ifsCandidate.rank, 0)
    }

    func testExactReviewBindsIndexRunRevisionReleaseAndNavigation() throws {
        let index = try makeIndex([
            ("qrpglesrc/orderentry.rpgle", "**free\ndcl-s customerNo packed(9:0);\nreturn;")
        ])
        let document = try XCTUnwrap(index.document(at: "qrpglesrc/orderentry.rpgle"))
        let evidence = makeEvidence(
            path: "ARLIB/QRPGLESRC(ORDERENTRY)",
            diagnostics: [
                diagnostic(path: "ARLIB/QRPGLESRC(ORDERENTRY)", line: 2, column: 7),
                diagnostic(path: "ARLIB/QRPGLESRC(ORDERENTRY)", line: 0, column: 0, messageID: "RNS9308")
            ]
        )
        let fileID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: try XCTUnwrap(evidence.sourceFiles.first))
        let release = try CompileTargetReleaseEvidence(
            commandText: "CRTBNDRPG OPTION(*EVENTF) TGTRLS(*CURRENT)",
            observedHostRelease: "V7R6M0"
        )
        let review = try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: evidence,
            compileRunFingerprint: runFingerprint,
            releaseEvidence: release,
            selectedMappings: [fileID: document.relativePath],
            sourceFingerprintsByFileID: [fileID: document.contentFingerprint],
            reviewedAt: reviewedAt
        )

        XCTAssertEqual(review.indexFingerprint, index.fingerprint)
        XCTAssertEqual(review.evidenceFingerprint, evidence.fingerprint)
        XCTAssertEqual(review.releaseEvidence.effectiveTargetRelease, try IBMReleaseLevel("V7R6M0"))
        XCTAssertEqual(review.mappings.first?.basis, .exactBaseName)
        XCTAssertEqual(review.mappings.first?.revisionState, .exact)
        XCTAssertEqual(review.diagnostics.count, 1)
        XCTAssertEqual(review.diagnostics.first?.navigationState, .exact)
        XCTAssertEqual(review.unlinkedDiagnosticCount, 1)
        XCTAssertEqual(review.exactNavigationCount, 1)
        XCTAssertTrue(review.isCurrent(for: index, compileRunFingerprint: runFingerprint))
        XCTAssertFalse(review.isCurrent(for: index, compileRunFingerprint: String(repeating: "b", count: 64)))

        let changed = try makeIndex([
            ("qrpglesrc/orderentry.rpgle", "**free\ndcl-s customerID packed(9:0);\nreturn;")
        ])
        XCTAssertFalse(review.isCurrent(for: changed, compileRunFingerprint: runFingerprint))
    }

    func testMissingAndDifferentSourceRevisionsRemainVisibleButDoNotNavigate() throws {
        let index = try makeIndex([
            ("qrpglesrc/orderentry.rpgle", "**free\ndcl-s customerNo packed(9:0);\nreturn;")
        ])
        let document = try XCTUnwrap(index.document(at: "qrpglesrc/orderentry.rpgle"))
        let evidence = makeEvidence(
            path: "ARLIB/QRPGLESRC(ORDERENTRY)",
            diagnostics: [diagnostic(path: "ARLIB/QRPGLESRC(ORDERENTRY)", line: 2, column: 7)]
        )
        let fileID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: try XCTUnwrap(evidence.sourceFiles.first))
        let release = try CompileTargetReleaseEvidence(commandText: "CRTBNDRPG TGTRLS(V7R6M0)")

        let missing = try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: evidence,
            compileRunFingerprint: runFingerprint,
            releaseEvidence: release,
            selectedMappings: [fileID: document.relativePath],
            reviewedAt: reviewedAt
        )
        XCTAssertEqual(missing.mappings.first?.revisionState, .notRecorded)
        XCTAssertEqual(missing.diagnostics.first?.navigationState, .revisionNotRecorded)
        XCTAssertEqual(missing.blockedNavigationCount, 1)

        let different = try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: evidence,
            compileRunFingerprint: runFingerprint,
            releaseEvidence: release,
            selectedMappings: [fileID: document.relativePath],
            sourceFingerprintsByFileID: [fileID: String(repeating: "b", count: 64)],
            reviewedAt: reviewedAt
        )
        XCTAssertEqual(different.mappings.first?.revisionState, .different)
        XCTAssertEqual(different.diagnostics.first?.navigationState, .revisionDifferent)
        XCTAssertEqual(different.diagnostics.count, 1)
    }

    func testExpansionAndOutOfBoundsCoordinatesBlockNavigationConservatively() throws {
        let index = try makeIndex([
            ("qrpglesrc/orderentry.rpgle", "**free\ndcl-s customerNo packed(9:0);\nreturn;")
        ])
        let document = try XCTUnwrap(index.document(at: "qrpglesrc/orderentry.rpgle"))
        let path = "ARLIB/QRPGLESRC(ORDERENTRY)"
        let release = try CompileTargetReleaseEvidence(commandText: "CRTBNDRPG TGTRLS(V7R6M0)")

        let expandedEvidence = makeEvidence(
            path: path,
            diagnostics: [diagnostic(path: path, line: 2, column: 7)],
            expansionRecordCount: 1
        )
        let expandedID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: try XCTUnwrap(expandedEvidence.sourceFiles.first))
        let expanded = try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: expandedEvidence,
            compileRunFingerprint: runFingerprint,
            releaseEvidence: release,
            selectedMappings: [expandedID: document.relativePath],
            sourceFingerprintsByFileID: [expandedID: document.contentFingerprint],
            reviewedAt: reviewedAt
        )
        XCTAssertEqual(expanded.diagnostics.first?.navigationState, .expansionMappingUnavailable)
        XCTAssertEqual(expanded.expansionRecordCount, 1)

        let invalidRangeEvidence = makeEvidence(
            path: path,
            diagnostics: [
                diagnostic(path: path, line: 99, column: 1),
                diagnostic(path: path, line: 2, column: 99)
            ]
        )
        let invalidRangeID = SourceWorkspaceCompileEvidenceMatcher.fileID(
            for: try XCTUnwrap(invalidRangeEvidence.sourceFiles.first)
        )
        let invalidRange = try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: invalidRangeEvidence,
            compileRunFingerprint: runFingerprint,
            releaseEvidence: release,
            selectedMappings: [invalidRangeID: document.relativePath],
            sourceFingerprintsByFileID: [invalidRangeID: document.contentFingerprint],
            reviewedAt: reviewedAt
        )
        XCTAssertEqual(invalidRange.diagnostics.count, 2)
        XCTAssertTrue(invalidRange.diagnostics.allSatisfy {
            $0.navigationState == .sourceRangeOutOfBounds
        })
    }

    func testReviewRejectsInvalidRunMappingDuplicatesAndReviewer() throws {
        let index = try makeIndex([
            ("qrpglesrc/orderentry.rpgle", "**free\nreturn;")
        ])
        let evidence = makeEvidence(
            sourceFiles: [
                CompileEvidenceSourceFile(processorSequence: 1, fileIdentifier: "001", path: "ARLIB/QRPGLESRC(ORDERENTRY)"),
                CompileEvidenceSourceFile(processorSequence: 1, fileIdentifier: "002", path: "ARLIB/QRPGLESRC(OTHER)")
            ],
            diagnostics: []
        )
        let release = try CompileTargetReleaseEvidence(commandText: "CRTBNDRPG TGTRLS(V7R6M0)")
        let document = try XCTUnwrap(index.documents.first)
        let firstID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: evidence.sourceFiles[0])
        let secondID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: evidence.sourceFiles[1])

        XCTAssertThrowsError(try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: evidence,
            compileRunFingerprint: "not-a-digest",
            releaseEvidence: release,
            selectedMappings: [firstID: document.relativePath]
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceCompileEvidenceError, .invalidRunFingerprint)
        }
        XCTAssertThrowsError(try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: evidence,
            compileRunFingerprint: runFingerprint,
            releaseEvidence: release,
            selectedMappings: [:]
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceCompileEvidenceError, .invalidMapping)
        }
        XCTAssertThrowsError(try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: evidence,
            compileRunFingerprint: runFingerprint,
            releaseEvidence: release,
            selectedMappings: [firstID: document.relativePath, secondID: document.relativePath]
        )) { error in
            XCTAssertEqual(
                error as? SourceWorkspaceCompileEvidenceError,
                .duplicateMappingTarget(document.relativePath)
            )
        }
        XCTAssertThrowsError(try ReviewedSourceWorkspaceCompileEvidence(
            index: index,
            evidence: evidence,
            compileRunFingerprint: runFingerprint,
            releaseEvidence: release,
            selectedMappings: [firstID: document.relativePath],
            reviewedBy: "\n"
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceCompileEvidenceError, .invalidReviewer)
        }
    }

    private func makeIndex(_ files: [(String, String)]) throws -> SourceWorkspaceIndex {
        try SourceWorkspaceIndexBuilder().build(
            rootName: "COMPILE EVIDENCE",
            files: try files.map {
                try SourceWorkspaceFile(
                    relativePath: $0.0,
                    format: .rpgle,
                    text: $0.1,
                    modifiedAt: reviewedAt,
                    sourceDate: "260727"
                )
            },
            createdAt: reviewedAt
        )
    }

    private func makeEvidence(
        path: String,
        diagnostics: [CompileDiagnostic],
        expansionRecordCount: Int = 0
    ) -> CompileEvidenceParseResult {
        makeEvidence(
            sourceFiles: [CompileEvidenceSourceFile(
                processorSequence: 1,
                fileIdentifier: "001",
                path: path
            )],
            diagnostics: diagnostics,
            expansionRecordCount: expansionRecordCount
        )
    }

    private func makeEvidence(
        sourceFiles: [CompileEvidenceSourceFile],
        diagnostics: [CompileDiagnostic],
        expansionRecordCount: Int = 0
    ) -> CompileEvidenceParseResult {
        let identity = sourceFiles.map(\.id).joined(separator: "|")
        let messages = diagnostics.map(\.id).joined(separator: "|")
        return CompileEvidenceParseResult(
            timestamp: "20260727174200",
            sourceFiles: sourceFiles,
            diagnostics: diagnostics,
            recordCount: sourceFiles.count + diagnostics.count + expansionRecordCount,
            expansionRecordCount: expansionRecordCount,
            unknownRecordCount: 0,
            unresolvedFileReferenceCount: diagnostics.filter { $0.filePath == nil }.count,
            fingerprint: AIContentFingerprint.sha256("\(identity)|\(messages)|\(expansionRecordCount)")
        )
    }

    private func diagnostic(
        path: String?,
        line: Int,
        column: Int,
        messageID: String = "RNF7030"
    ) -> CompileDiagnostic {
        CompileDiagnostic(
            recordIndex: line + column + 1,
            processorSequence: 1,
            fileIdentifier: path == nil ? "0" : "001",
            filePath: path,
            startLine: line,
            endLine: line,
            startColumn: column,
            endColumn: max(column, column + 3),
            messageID: messageID,
            severityLetter: line == 0 ? "T" : "S",
            severity: line == 0 ? 50 : 30,
            message: line == 0 ? "Compilation stopped." : "Name or indicator is not defined."
        )
    }
}
