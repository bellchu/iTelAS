import XCTest
@testable import iTelASCore

final class SourceWorkspaceIndexTests: XCTestCase {
    func testPathsBoundsDuplicatesAndFingerprintAreDeterministic() throws {
        XCTAssertThrowsError(
            try SourceWorkspaceFile(relativePath: "../escape.rpgle", format: .rpgle, text: "**free")
        ) { error in
            XCTAssertEqual(error as? SourceWorkspaceIndexError, .invalidRelativePath("../escape.rpgle"))
        }

        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try source("src/alpha.rpgle", "**free\ndcl-s alpha int(10);", modifiedAt: timestamp)
        let second = try source("src/beta.clle", "PGM\nENDPGM", format: .clle, modifiedAt: timestamp)
        let builder = SourceWorkspaceIndexBuilder()
        let indexA = try builder.build(rootName: "SAFE ROOT", files: [first, second], createdAt: timestamp)
        let indexB = try builder.build(
            rootName: "SAFE ROOT",
            files: [second, first],
            createdAt: timestamp.addingTimeInterval(900)
        )

        XCTAssertEqual(indexA.fingerprint, indexB.fingerprint)
        XCTAssertEqual(indexA.documents.map(\.relativePath), ["src/alpha.rpgle", "src/beta.clle"])
        XCTAssertThrowsError(try builder.build(
            rootName: "SAFE ROOT",
            files: [first, try source("SRC/ALPHA.RPGLE", "**free")]
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceIndexError, .duplicateRelativePath("SRC/ALPHA.RPGLE"))
        }

        let narrow = SourceWorkspaceIndexLimits(maximumFiles: 1)
        XCTAssertThrowsError(try SourceWorkspaceIndexBuilder(limits: narrow).build(
            rootName: "SAFE ROOT",
            files: [first, second]
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceIndexError, .tooManyFiles(1))
        }
    }

    func testIncrementalBuildReusesOnlyExactBytesAndRebuildsDependencies() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let builder = SourceWorkspaceIndexBuilder()
        let mainText = "**free\n/copy src/retired"
        let previous = try builder.build(
            rootName: "DELTA ROOT",
            files: [
                try source("src/main.rpgle", mainText, modifiedAt: timestamp),
                try source("src/beta.rpgle", "**free\ndcl-proc Beta;\nend-proc;", modifiedAt: timestamp),
                try source("src/retired.rpgle", "**free\ndcl-proc Retired;\nend-proc;", modifiedAt: timestamp)
            ],
            createdAt: timestamp
        )
        XCTAssertEqual(
            previous.outboundDependencies(for: "src/main.rpgle").first { $0.targetLabel == "src/retired" }?.resolution,
            .exact
        )

        let currentFiles = try [
            source("src/main.rpgle", mainText, modifiedAt: timestamp.addingTimeInterval(60)),
            source("src/beta.rpgle", "**free\ndcl-proc Gamma;\nend-proc;", modifiedAt: timestamp),
            source("src/added.rpgle", "**free\ndcl-proc Added;\nend-proc;", modifiedAt: timestamp)
        ]
        let result = try builder.buildIncrementally(
            rootName: "DELTA ROOT",
            files: currentFiles,
            previousIndex: previous,
            createdAt: timestamp.addingTimeInterval(120)
        )
        let repeated = try builder.buildIncrementally(
            rootName: "DELTA ROOT",
            files: Array(currentFiles.reversed()),
            previousIndex: previous,
            createdAt: timestamp.addingTimeInterval(900)
        )

        XCTAssertEqual(result.report.unchangedDocumentCount, 0)
        XCTAssertEqual(result.report.metadataOnlyDocumentCount, 1)
        XCTAssertEqual(result.report.reusedAnalysisCount, 1)
        XCTAssertEqual(result.report.reanalyzedDocumentCount, 1)
        XCTAssertEqual(result.report.addedDocumentCount, 1)
        XCTAssertEqual(result.report.analyzedDocumentCount, 2)
        XCTAssertEqual(result.report.removedDocumentCount, 1)
        XCTAssertEqual(result.report.inputFileCount, 3)
        XCTAssertEqual(result.report.inputUTF8ByteCount, currentFiles.reduce(0) { $0 + $1.utf8ByteCount })
        XCTAssertTrue(result.report.isIncremental)
        XCTAssertTrue(result.report.isCurrent(for: result.index))
        XCTAssertEqual(result.report.fingerprint, repeated.report.fingerprint)
        XCTAssertEqual(result.index.fingerprint, repeated.index.fingerprint)
        XCTAssertEqual(
            result.report.entries.map { "\($0.relativePath)|\($0.kind.rawValue)" },
            [
                "src/added.rpgle|\(SourceWorkspaceIndexDeltaKind.added.rawValue)",
                "src/beta.rpgle|\(SourceWorkspaceIndexDeltaKind.reanalyzed.rawValue)",
                "src/main.rpgle|\(SourceWorkspaceIndexDeltaKind.metadataOnly.rawValue)",
                "src/retired.rpgle|\(SourceWorkspaceIndexDeltaKind.removed.rawValue)"
            ]
        )
        XCTAssertEqual(
            previous.document(at: "src/main.rpgle")?.snapshot,
            result.index.document(at: "src/main.rpgle")?.snapshot
        )
        XCTAssertNotEqual(
            previous.document(at: "src/beta.rpgle")?.snapshot,
            result.index.document(at: "src/beta.rpgle")?.snapshot
        )
        XCTAssertEqual(
            result.index.outboundDependencies(for: "src/main.rpgle").first { $0.targetLabel == "src/retired" }?.resolution,
            .unresolved
        )
    }

    func testIncrementalBuildHonorsTaskCancellation() async throws {
        let builder = SourceWorkspaceIndexBuilder()
        let files = try (1...200).map { number in
            try source("src/member\(number).rpgle", "**free\ndcl-s field\(number) int(10);")
        }
        let previous = try builder.build(rootName: "DELTA CANCEL", files: files)
        let task = Task.detached {
            try builder.buildIncrementally(
                rootName: "DELTA CANCEL",
                files: files,
                previousIndex: previous
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled delta refresh must not publish a replacement index.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testIncrementalBuildKeepsLargeUnchangedWorkspaceOnTheReusePath() throws {
        let limits = SourceWorkspaceIndexLimits(maximumFiles: 1_000)
        let builder = SourceWorkspaceIndexBuilder(limits: limits)
        let files = try (1...750).map { number in
            try SourceWorkspaceFile(
                relativePath: "src/member\(number).rpgle",
                format: .rpgle,
                text: "**free\ndcl-s field\(number) int(10);",
                limits: limits
            )
        }
        let previous = try builder.build(rootName: "LARGE DELTA", files: files)
        let refreshed = try builder.buildIncrementally(
            rootName: "LARGE DELTA",
            files: Array(files.reversed()),
            previousIndex: previous
        )

        XCTAssertEqual(refreshed.report.inputFileCount, 750)
        XCTAssertEqual(refreshed.report.reusedAnalysisCount, 750)
        XCTAssertEqual(refreshed.report.analyzedDocumentCount, 0)
        XCTAssertEqual(refreshed.report.removedDocumentCount, 0)
        XCTAssertTrue(refreshed.report.entries.isEmpty)
        XCTAssertEqual(
            previous.documents.map(\.snapshot),
            refreshed.index.documents.map(\.snapshot)
        )
    }

    func testSearchCoversFilesSymbolsReferencesAndTextWithStableCaps() throws {
        let file = try source(
            "src/CalculateTax.rpgle",
            """
            **free
            dcl-pr CalculateTax packed(9:2);
              amount packed(11:2) const;
            end-pr;
            dcl-s result packed(9:2);
            result = CalculateTax(100);
            """
        )
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "SEARCH", files: [file])
        let results = try index.search("CalculateTax")
        let kinds = Set(results.map(\.kind))

        XCTAssertTrue(kinds.contains(.file))
        XCTAssertTrue(kinds.contains(.symbol))
        XCTAssertTrue(kinds.contains(.reference))
        XCTAssertTrue(kinds.contains(.text))
        XCTAssertEqual(results, try index.search("CalculateTax"))

        let cappedLimits = SourceWorkspaceIndexLimits(maximumSearchResults: 2)
        let cappedFile = try SourceWorkspaceFile(
            relativePath: "src/CalculateTax.rpgle",
            format: .rpgle,
            text: file.text,
            limits: cappedLimits
        )
        let capped = try SourceWorkspaceIndexBuilder(limits: cappedLimits)
            .build(rootName: "SEARCH", files: [cappedFile])
            .search("CalculateTax")
        XCTAssertEqual(capped.count, 2)
    }

    func testSearchReportBindsQueryIndexCoverageAndDeterministicReceipt() throws {
        let files = try [
            source(
                "src/alpha.rpgle",
                "**free\ndcl-proc CalculateTax export;\nCalculateTax();\nend-proc;"
            ),
            source("src/beta.clle", "PGM\nCALL PGM(CalculateTax)\nENDPGM", format: .clle)
        ]
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "SEARCH RECEIPT", files: files)
        let report = try index.searchReport("CalculateTax")
        let repeated = try index.searchReport("CalculateTax")

        XCTAssertEqual(report.results, try index.search("CalculateTax"))
        XCTAssertEqual(report.examinedDocumentCount, index.fileCount)
        XCTAssertEqual(report.scopeDocumentCount, index.fileCount)
        XCTAssertGreaterThan(report.examinedLineCount, 0)
        XCTAssertGreaterThanOrEqual(report.candidateCount, report.results.count)
        XCTAssertEqual(report.completion, .complete)
        XCTAssertEqual(report.fingerprint, repeated.fingerprint)
        XCTAssertTrue(report.isCurrent(for: index, query: "  CalculateTax  "))

        let changed = try SourceWorkspaceIndexBuilder().build(
            rootName: "SEARCH RECEIPT",
            files: [try source("src/alpha.rpgle", "**free\ndcl-proc DifferentName;\nend-proc;")]
        )
        XCTAssertFalse(report.isCurrent(for: changed, query: "CalculateTax"))
        XCTAssertFalse(report.isCurrent(for: index, query: "CalculateOrderTax"))
    }

    func testSearchReportDisclosesPerDocumentResultAndCandidateCaps() throws {
        let repeatedLines = (["**free"] + Array(repeating: "needle = needle + 1;", count: 8))
            .joined(separator: "\n")
        let perDocumentIndex = try SourceWorkspaceIndexBuilder().build(
            rootName: "TEXT CAP",
            files: [try source("src/repeated.rpgle", repeatedLines)]
        )
        let perDocument = try perDocumentIndex.searchReport("needle")
        XCTAssertEqual(perDocument.results.filter { $0.kind == .text }.count, 6)
        XCTAssertEqual(perDocument.completion, .perDocumentTextLimitReached)
        XCTAssertTrue(perDocument.isTruncated)

        let resultLimits = SourceWorkspaceIndexLimits(maximumSearchResults: 2)
        let resultFiles = try [SourceWorkspaceFile(
            relativePath: "src/alpha.rpgle",
            format: .rpgle,
            text: "**free\ndcl-s alpha int(10);\nalpha += 1;",
            limits: resultLimits
        )]
        let resultIndex = try SourceWorkspaceIndexBuilder(limits: resultLimits).build(
            rootName: "RESULT CAP",
            files: resultFiles
        )
        let resultReport = try resultIndex.searchReport("alpha")
        XCTAssertEqual(resultReport.results.count, 2)
        XCTAssertEqual(resultReport.resultLimit, 2)
        XCTAssertEqual(resultReport.completion, .resultLimitReached)

        let candidateLimits = SourceWorkspaceIndexLimits(maximumSearchResults: 1)
        let candidateFiles = try (1...6).map { number in
            try SourceWorkspaceFile(
                relativePath: "src/needle\(number).rpgle",
                format: .rpgle,
                text: "**free\nreturn;",
                limits: candidateLimits
            )
        }
        let candidateIndex = try SourceWorkspaceIndexBuilder(limits: candidateLimits).build(
            rootName: "CANDIDATE CAP",
            files: candidateFiles
        )
        let candidateReport = try candidateIndex.searchReport("needle")
        XCTAssertEqual(candidateReport.completion, .candidateLimitReached)
        XCTAssertLessThan(candidateReport.examinedDocumentCount, candidateReport.scopeDocumentCount)
        XCTAssertEqual(candidateReport.results.count, 1)
    }

    func testSearchReportHonorsTaskCancellation() async throws {
        let files = try (1...200).map { number in
            try source(
                "src/member\(number).rpgle",
                (["**free"] + Array(repeating: "dcl-s field\(number) int(10);", count: 40))
                    .joined(separator: "\n")
            )
        }
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "CANCELLATION", files: files)
        let task = Task.detached { try index.searchReport("missing-value") }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled workspace search must not publish a report.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testDependencyResolutionDistinguishesExactAmbiguousHostAndUnresolved() throws {
        let files = try [
            source(
                "src/main.rpgle",
                """
                **free
                /copy includes/taxrules
                /copy QRPGLESRC,MISSING
                callp CalculateTax();
                callp SharedProc();
                callp MissingProc();
                """
            ),
            source("includes/taxrules.cpy", "**free\ndcl-proc CalculateTax;\nend-proc;"),
            source("src/one.rpgle", "**free\ndcl-proc SharedProc;\nend-proc;"),
            source("src/two.rpgle", "**free\ndcl-proc SharedProc;\nend-proc;")
        ]
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "DEPENDENCIES", files: files)
        let edges = index.outboundDependencies(for: "src/main.rpgle")

        XCTAssertTrue(edges.contains {
            $0.kind == .copy && $0.targetLabel == "includes/taxrules"
                && $0.resolution == .exact && $0.targetPaths == ["includes/taxrules.cpy"]
        })
        XCTAssertTrue(edges.contains { $0.targetLabel == "CalculateTax" && $0.resolution == .exact })
        XCTAssertTrue(edges.contains { $0.targetLabel == "SharedProc" && $0.resolution == .ambiguous && $0.targetPaths.count == 2 })
        XCTAssertTrue(edges.contains { $0.targetLabel.contains("MISSING") && $0.resolution == .hostBacked })
        XCTAssertTrue(edges.contains { $0.targetLabel == "MissingProc" && $0.resolution == .unresolved })
        XCTAssertEqual(index.suggestedDependencyPaths(for: "src/main.rpgle"), [
            "includes/taxrules.cpy"
        ])
    }

    func testReviewedScopeFeedsOnlyExactSelectedFilesAndInvalidatesOnAnyChange() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let files = try [
            source("src/main.rpgle", "**free\ndcl-s localValue int(10);", modifiedAt: timestamp),
            source("src/tax.rpgle", "**free\ndcl-proc CalculateTax;\nend-proc;", modifiedAt: timestamp),
            source("src/other.rpgle", "**free\ndcl-proc UnreviewedProc;\nend-proc;", modifiedAt: timestamp)
        ]
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "REVIEW", files: files)
        let review = try ReviewedSourceDependencyScope(
            index: index,
            selectedPaths: ["src/tax.rpgle"],
            reviewedAt: timestamp
        )

        XCTAssertTrue(review.isCurrent(for: index))
        let completion = try index.reviewedCompletionSymbols(using: review)
        XCTAssertFalse(completion.isEmpty)
        XCTAssertEqual(Set(completion.map(\.relativePath)), ["src/tax.rpgle"])
        XCTAssertTrue(completion.contains { $0.symbol.name == "CalculateTax" })
        XCTAssertFalse(completion.contains { $0.symbol.name == "UnreviewedProc" })

        var changedFiles = files
        changedFiles[2] = try source(
            "src/other.rpgle",
            "**free\ndcl-proc ChangedProc;\nend-proc;",
            modifiedAt: timestamp
        )
        let changed = try SourceWorkspaceIndexBuilder().build(rootName: "REVIEW", files: changedFiles)
        XCTAssertFalse(review.isCurrent(for: changed))
        XCTAssertThrowsError(try changed.reviewedCompletionSymbols(using: review)) { error in
            XCTAssertEqual(error as? SourceWorkspaceIndexError, .staleDependencyReview)
        }
    }

    func testRenamePreviewExcludesCommentsAndStringsAndFreezesSourceDateBaselines() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let text = """
        **free
        dcl-proc CalculateTax;
          // CalculateTax is documented here
          dcl-s note varchar(30) inz('CalculateTax');
          CalculateTax();
        end-proc;
        """
        let original = try source(
            "src/tax.rpgle",
            text,
            modifiedAt: timestamp,
            sourceDate: "260727"
        )
        let index = try SourceWorkspaceIndexBuilder().build(rootName: "RENAME", files: [original])
        let plan = try index.makeRenamePlan(currentName: "CalculateTax", proposedName: "CalculateOrderTax")
        let review = try ReviewedSourceWorkspaceRename(
            index: index,
            plan: plan,
            reviewedAt: timestamp
        )

        XCTAssertEqual(plan.occurrences.map(\.line), [2, 5])
        XCTAssertEqual(plan.occurrences.map(\.utf16Length), ["CalculateTax".utf16.count, "CalculateTax".utf16.count])
        XCTAssertEqual(plan.baselines.first?.sourceDate, "260727")
        XCTAssertEqual(plan.baselines.first?.modifiedAt, timestamp)
        XCTAssertTrue(plan.isCurrent(for: index))
        XCTAssertTrue(review.isCurrent(plan: plan, index: index))
        let replacement = try index.replacementText(for: plan, relativePath: "src/tax.rpgle")
        XCTAssertTrue(replacement.contains("dcl-proc CalculateOrderTax;"))
        XCTAssertTrue(replacement.contains("CalculateOrderTax();"))
        XCTAssertTrue(replacement.contains("// CalculateTax is documented here"))
        XCTAssertTrue(replacement.contains("inz('CalculateTax')"))
        XCTAssertThrowsError(try index.makeRenamePlan(currentName: "CalculateTax", proposedName: "calculateTax")) {
            XCTAssertEqual($0 as? SourceWorkspaceIndexError, .unchangedRename)
        }
        XCTAssertThrowsError(try index.makeRenamePlan(currentName: "1INVALID", proposedName: "ValidName"))

        let changed = try SourceWorkspaceIndexBuilder().build(
            rootName: "RENAME",
            files: [try source(
                "src/tax.rpgle",
                text.replacingOccurrences(of: "end-proc;", with: "return;\nend-proc;"),
                modifiedAt: timestamp,
                sourceDate: "260727"
            )]
        )
        XCTAssertFalse(plan.isCurrent(for: changed))
        XCTAssertFalse(review.isCurrent(plan: plan, index: changed))
        XCTAssertThrowsError(try changed.replacementText(for: plan, relativePath: "src/tax.rpgle")) { error in
            XCTAssertEqual(error as? SourceWorkspaceIndexError, .staleRenamePlan)
        }

        let strictLimits = SourceWorkspaceIndexLimits(maximumRenameOccurrences: 1)
        let strictFile = try SourceWorkspaceFile(
            relativePath: "src/tax.rpgle",
            format: .rpgle,
            text: text,
            limits: strictLimits
        )
        let strictIndex = try SourceWorkspaceIndexBuilder(limits: strictLimits)
            .build(rootName: "RENAME", files: [strictFile])
        XCTAssertThrowsError(try strictIndex.makeRenamePlan(
            currentName: "CalculateTax",
            proposedName: "CalculateOrderTax"
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceIndexError, .tooManyRenameOccurrences(1))
        }

        let limitedAnalyzer = SourceIntelligenceAnalyzer(limits: SourceIntelligenceLimits(maximumLines: 1))
        let limitedIndex = try SourceWorkspaceIndexBuilder(analyzer: limitedAnalyzer)
            .build(rootName: "RENAME", files: [original])
        XCTAssertThrowsError(try limitedIndex.makeRenamePlan(
            currentName: "CalculateTax",
            proposedName: "CalculateOrderTax"
        )) { error in
            XCTAssertEqual(
                error as? SourceWorkspaceIndexError,
                .renameAnalysisLimited("src/tax.rpgle")
            )
        }
    }

    func testReviewedHostIncludeBindsOneCurrentEdgeAndRequiresAnExactLibrary() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let file = try source(
            "src/main.rpgle",
            "**free\n/copy QRPGLESRC,CUSCOPY\n",
            modifiedAt: timestamp
        )
        let index = try SourceWorkspaceIndexBuilder().build(
            rootName: "HOST REVIEW",
            files: [file],
            createdAt: timestamp
        )
        let edge = try XCTUnwrap(index.outboundDependencies(for: file.relativePath).first)

        XCTAssertThrowsError(try ReviewedSourceWorkspaceHostInclude(
            index: index,
            dependencyID: edge.id,
            reviewedAt: timestamp
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceHostIncludeError, .sourceMemberLibraryRequired)
        }

        let review = try ReviewedSourceWorkspaceHostInclude(
            index: index,
            dependencyID: edge.id,
            sourceMemberLibrary: "ARLIB",
            reviewedAt: timestamp
        )
        XCTAssertTrue(review.isCurrent(for: index))
        XCTAssertEqual(review.sourcePath, "src/main.rpgle")
        XCTAssertEqual(review.target.displayName, "ARLIB/QRPGLESRC(CUSCOPY)")
        XCTAssertEqual(review.maximumContentUTF8Bytes, index.limits.maximumFileUTF8Bytes)

        guard case .sourceMember(let identity) = review.target else {
            return XCTFail("Expected an exact source-member target")
        }
        let record = try SourceMemberRecord(
            sequence: SourceMemberSequence(hundredths: 100),
            sourceDate: SourceMemberDateCode("260727"),
            text: "dcl-pr CustomerLookup ind;"
        )
        let metadata = try SourceMemberMetadata(
            identity: identity,
            sourceType: "RPGLE",
            recordLength: 92,
            sourceTextByteLength: 80,
            ccsid: 37,
            recordCount: 1,
            fieldLayout: .standardThreeField,
            access: SourceMemberAccess(canRead: true, canWrite: false, canUpdate: false, canDelete: false),
            journalEvidence: .unverified
        )
        let snapshot = try SourceMemberSnapshot(metadata: metadata, records: [record])
        let content = try SourceWorkspaceHostIncludeContent(
            request: review,
            snapshot: snapshot,
            providerName: "NATIVE ODBC",
            targetName: "DEVELOPMENT",
            capturedAt: timestamp
        )
        XCTAssertEqual(content.target, .sourceMember(identity))
        XCTAssertEqual(content.format, .rpgle)
        XCTAssertEqual(content.remoteRevision, snapshot.revision.token)

        let changed = try SourceWorkspaceIndexBuilder().build(
            rootName: "HOST REVIEW",
            files: [try source(
                "src/main.rpgle",
                "**free\n/copy QRPGLESRC,CUSCOPY\n// changed\n",
                modifiedAt: timestamp
            )],
            createdAt: timestamp
        )
        XCTAssertFalse(review.isCurrent(for: changed))
    }

    func testHostIncludeOverlayResolvesSearchCompletionAndNeverEntersLocalRename() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let local = try source(
            "src/main.rpgle",
            """
            **free
            /include ARLIB/QRPGLESRC,CUSCOPY
            dcl-s customer like(CustomerTemplate);
            """,
            modifiedAt: timestamp
        )
        let index = try SourceWorkspaceIndexBuilder().build(
            rootName: "HOST OVERLAY",
            files: [local],
            createdAt: timestamp
        )
        let edge = try XCTUnwrap(index.outboundDependencies(for: local.relativePath).first)
        let review = try ReviewedSourceWorkspaceHostInclude(
            index: index,
            dependencyID: edge.id,
            reviewedAt: timestamp
        )
        let content = try SourceWorkspaceHostIncludeContent(
            request: review,
            actualTarget: review.target,
            providerName: "BUNDLED REPLAY",
            targetName: "LOCAL TEST",
            text: """
            dcl-ds CustomerTemplate qualified;
              customerNumber packed(9:0);
            end-ds;
            """,
            format: .rpgle,
            ccsid: 37,
            remoteRevision: "replay:cuscopy:1",
            capturedAt: timestamp
        )
        let expanded = try index.appendingHostInclude(content)

        XCTAssertEqual(expanded.localFileCount, 1)
        XCTAssertEqual(expanded.hostIncludeFileCount, 1)
        let hostDocument = try XCTUnwrap(expanded.document(at: content.overlayRelativePath))
        XCTAssertTrue(hostDocument.origin.isHostBacked)
        XCTAssertEqual(
            expanded.outboundDependencies(for: local.relativePath).first?.resolution,
            .exact
        )
        XCTAssertEqual(
            expanded.outboundDependencies(for: local.relativePath).first?.targetPaths,
            [content.overlayRelativePath]
        )
        XCTAssertTrue(try expanded.search("CustomerTemplate").contains {
            $0.kind == .symbol && $0.relativePath == content.overlayRelativePath
        })

        let completionReview = try ReviewedSourceDependencyScope(
            index: expanded,
            selectedPaths: [content.overlayRelativePath],
            reviewedAt: timestamp
        )
        XCTAssertTrue(try expanded.reviewedCompletionSymbols(using: completionReview).contains {
            $0.symbol.name == "CustomerTemplate"
        })

        let rename = try expanded.makeRenamePlan(
            currentName: "CustomerTemplate",
            proposedName: "CustomerRecord"
        )
        XCTAssertEqual(Set(rename.baselines.map(\.relativePath)), [local.relativePath])
        XCTAssertTrue(rename.occurrences.allSatisfy { $0.relativePath == local.relativePath })
        XCTAssertEqual(try expanded.removingHostIncludes().fingerprint, index.fingerprint)

        XCTAssertThrowsError(try SourceWorkspaceHostIncludeContent(
            request: review,
            actualTarget: .ifs(IFSPath("/tmp/CUSCOPY.rpgle")),
            providerName: "TEST",
            targetName: "LOCAL TEST",
            text: "**free",
            format: .rpgle,
            ccsid: 1208,
            remoteRevision: "sha256:test"
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceHostIncludeError, .targetMismatch)
        }
    }

    func testIFSHostIncludeAcceptsOnlyTheReviewedDecodedPathAndRevision() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let local = try source(
            "src/main.rpgle",
            "**free\n/copy '/home/dev/includes/customer.rpgle'\n",
            modifiedAt: timestamp
        )
        let index = try SourceWorkspaceIndexBuilder().build(
            rootName: "IFS INCLUDE",
            files: [local],
            createdAt: timestamp
        )
        let edge = try XCTUnwrap(index.outboundDependencies(for: local.relativePath).first)
        let review = try ReviewedSourceWorkspaceHostInclude(
            index: index,
            dependencyID: edge.id,
            reviewedAt: timestamp
        )
        let path = try IFSPath("/home/dev/includes/customer.rpgle")
        let metadata = IFSResourceMetadata(
            path: path,
            kind: .file,
            permissions: "-rw-r-----",
            owner: "DEV",
            group: "QPGMR",
            byteCount: 53,
            modifiedDescription: "2026-07-27 16:00"
        )
        let decoded = try IFSUTF8DocumentCodec().decode(
            data: Data("**free\ndcl-pr CustomerLookup ind;\nend-pr;\n".utf8),
            metadata: metadata
        )
        let content = try SourceWorkspaceHostIncludeContent(
            request: review,
            decodedIFS: decoded,
            providerName: "SYSTEM OPENSSH SFTP",
            targetName: "DEVELOPMENT",
            capturedAt: timestamp
        )
        let expanded = try index.appendingHostInclude(content)

        XCTAssertEqual(content.target, .ifs(path))
        XCTAssertEqual(content.remoteRevision, decoded.revision.token)
        XCTAssertEqual(content.ccsid, 1208)
        XCTAssertEqual(
            expanded.outboundDependencies(for: local.relativePath).first?.targetPaths,
            [content.overlayRelativePath]
        )
        XCTAssertEqual(expanded.outboundDependencies(for: local.relativePath).first?.resolution, .exact)
    }

    private func source(
        _ path: String,
        _ text: String,
        format: SourceFormat = .rpgle,
        modifiedAt: Date? = nil,
        sourceDate: String? = nil
    ) throws -> SourceWorkspaceFile {
        try SourceWorkspaceFile(
            relativePath: path,
            format: format,
            text: text,
            modifiedAt: modifiedAt,
            sourceDate: sourceDate
        )
    }
}
