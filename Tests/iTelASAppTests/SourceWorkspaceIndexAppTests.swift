import AppKit
import CoreServices
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class SourceWorkspaceIndexAppTests: XCTestCase {
    func testDriftMonitorMapsOnlySafeRecursiveSourceSignals() throws {
        let root = "/tmp/itelas-drift-root"
        let prefix = root + "/"
        let modifiedFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile
        )
        let observation = try XCTUnwrap(SourceWorkspaceDriftMonitor.observation(
            absolutePath: root + "/src/order.rpgle",
            rootPath: root,
            rootPathPrefix: prefix,
            flags: modifiedFlags,
            eventID: 41
        ))
        XCTAssertEqual(observation.relativePath, "src/order.rpgle")
        XCTAssertEqual(observation.kinds, [.modified])
        XCTAssertNil(SourceWorkspaceDriftMonitor.observation(
            absolutePath: root + "/src/readme.md",
            rootPath: root,
            rootPathPrefix: prefix,
            flags: modifiedFlags,
            eventID: 42
        ))
        XCTAssertNil(SourceWorkspaceDriftMonitor.observation(
            absolutePath: root + "/.git/config",
            rootPath: root,
            rootPathPrefix: prefix,
            flags: modifiedFlags,
            eventID: 43
        ))

        let droppedFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagMustScanSubDirs
        )
        let rootObservation = try XCTUnwrap(SourceWorkspaceDriftMonitor.observation(
            absolutePath: root,
            rootPath: root,
            rootPathPrefix: prefix,
            flags: droppedFlags,
            eventID: 44
        ))
        XCTAssertNil(rootObservation.relativePath)
        XCTAssertTrue(rootObservation.kinds.contains(.rescanRequired))
    }

    func testPendingDriftRevokesEveryIndexBoundGateWithoutReadingSource() throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        let occurrence = try XCTUnwrap(model.sourceWorkspaceIndex.search("CalculateTax").first {
            $0.kind == .symbol
        })
        XCTAssertTrue(model.openSourceWorkspaceResult(occurrence))
        model.sourceWorkspaceRenameCurrentName = "CalculateTax"
        model.sourceWorkspaceRenameProposedName = "CalculateOrderTax"
        model.prepareSourceWorkspaceRenamePlan()
        model.presentSourceWorkspaceRenameReview()
        XCTAssertTrue(model.sourceWorkspaceDependencyReviewIsCurrent)
        XCTAssertTrue(model.sourceWorkspaceRenameReviewIsCurrent)
        XCTAssertTrue(model.openedSourceWorkspaceSnapshotIsCurrent)

        model.sourceWorkspaceDriftPhase = .watching
        let signal = try SourceWorkspaceDriftObservation(
            relativePath: occurrence.relativePath,
            kinds: [.modified],
            rawEventCount: 2,
            eventID: 501
        )
        model.recordSourceWorkspaceDrift([signal])

        XCTAssertEqual(model.sourceWorkspaceDriftPhase, .pending)
        XCTAssertTrue(model.sourceWorkspaceHasPendingDrift)
        XCTAssertFalse(model.sourceWorkspaceEvidenceIsCurrent)
        XCTAssertFalse(model.sourceWorkspaceDependencyReviewIsCurrent)
        XCTAssertFalse(model.sourceWorkspaceRenameReviewIsCurrent)
        XCTAssertFalse(model.openedSourceWorkspaceSnapshotIsCurrent)
        XCTAssertTrue(model.reviewedSourceWorkspaceCompletionSymbols.isEmpty)
        XCTAssertFalse(model.openSourceWorkspaceResult(occurrence))
        XCTAssertEqual(model.sourceWorkspaceDriftReceipt?.rawEventCount, 2)
        XCTAssertEqual(model.sourceWorkspaceDriftReceipt?.entries.first?.relativePath, occurrence.relativePath)
    }

    func testRecursiveDriftPauseManualVerificationAndAutomaticRefresh() async throws {
        let root = temporaryDirectory(named: "drift-lifecycle")
        let nested = root.appendingPathComponent("src", isDirectory: true)
        let sourceURL = nested.appendingPathComponent("order.rpgle")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "**free\ndcl-s stage int(10) inz(1);".write(to: sourceURL, atomically: true, encoding: .utf8)
        let model = AppModel()
        defer {
            model.restoreSourceWorkspaceIndexReplay()
            try? FileManager.default.removeItem(at: root)
        }

        model.scanSourceWorkspace(at: root)
        try await waitUntil {
            model.sourceWorkspaceIndexPhase == .ready && model.sourceWorkspaceEvidenceIsCurrent
        }
        model.setSourceWorkspaceAutoRefreshEnabled(false)
        try "**free\ndcl-s stage int(10) inz(2);".write(to: sourceURL, atomically: true, encoding: .utf8)
        try await waitUntil { model.sourceWorkspaceHasPendingDrift }
        XCTAssertEqual(model.sourceWorkspaceIndex.document(at: "src/order.rpgle")?.text.contains("inz(2)"), false)
        XCTAssertTrue(model.sourceWorkspaceDriftDiagnostic.contains("No source byte was read"))

        model.verifySourceWorkspaceDriftNow()
        try await waitUntil {
            model.sourceWorkspaceEvidenceIsCurrent
                && model.sourceWorkspaceIndex.document(at: "src/order.rpgle")?.text.contains("inz(2)") == true
        }

        model.setSourceWorkspaceAutoRefreshEnabled(true)
        model.pauseSourceWorkspaceDriftMonitoring()
        XCTAssertEqual(model.sourceWorkspaceDriftPhase, .paused)
        XCTAssertFalse(model.sourceWorkspaceEvidenceIsCurrent)
        try "**free\ndcl-s stage int(10) inz(3);".write(to: sourceURL, atomically: true, encoding: .utf8)
        model.resumeSourceWorkspaceDriftMonitoring()
        try await waitUntil {
            model.sourceWorkspaceEvidenceIsCurrent
                && model.sourceWorkspaceIndex.document(at: "src/order.rpgle")?.text.contains("inz(3)") == true
        }
        XCTAssertNil(model.sourceWorkspaceDriftReceipt)
        XCTAssertEqual(model.sourceWorkspaceDriftPhase, .watching)
    }

    func testScannerIndexesOnlyBoundedRegularUTF8SourcesAndRejectsSymlinkRoot() throws {
        let root = temporaryDirectory(named: "scan")
        let outside = temporaryDirectory(named: "outside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "**free\ndcl-s amount packed(9:2);".write(
            to: root.appendingPathComponent("src/order.rpgle"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0x50, 0x47, 0x4D, 0x00, 0x45]).write(to: root.appendingPathComponent("binary.clle"))
        try Data(repeating: 0x41, count: 96).write(to: root.appendingPathComponent("large.sql"))
        try "ignored".write(
            to: root.appendingPathComponent("notes.md"),
            atomically: true,
            encoding: .utf8
        )
        try "**free\ndcl-s escaped int(10);".write(
            to: outside.appendingPathComponent("outside.rpgle"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.rpgle"),
            withDestinationURL: outside.appendingPathComponent("outside.rpgle")
        )

        let limits = SourceWorkspaceIndexLimits(
            maximumFileUTF8Bytes: 64,
            maximumTotalUTF8Bytes: 256
        )
        let result = try SourceWorkspaceIndexService(limits: limits).scan(rootURL: root)

        XCTAssertEqual(result.index.documents.map(\.relativePath), ["src/order.rpgle"])
        XCTAssertEqual(Set(result.index.skippedFiles.map(\.relativePath)), [
            "binary.clle", "large.sql", "linked.rpgle"
        ])
        XCTAssertTrue(result.index.skippedFiles.contains { $0.reason.contains("UTF-8") })
        XCTAssertTrue(result.index.skippedFiles.contains { $0.reason.contains("64-byte") })
        XCTAssertTrue(result.index.skippedFiles.contains { $0.reason.contains("Symbolic links") })
        XCTAssertFalse(result.index.documents.contains { $0.text.contains("escaped") })

        let linkedRoot = temporaryDirectory(named: "root-link")
        defer { try? FileManager.default.removeItem(at: linkedRoot) }
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
        XCTAssertThrowsError(try SourceWorkspaceIndexService(limits: limits).scan(rootURL: linkedRoot)) { error in
            XCTAssertTrue(error is LocalSourceWorkspaceScanError)
        }
    }

    func testScannerDeltaRefreshReusesOnlyExactSourceAnalysis() throws {
        let root = temporaryDirectory(named: "delta-scan")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let metadataURL = root.appendingPathComponent("metadata.rpgle")
        let changedURL = root.appendingPathComponent("changed.rpgle")
        let retiredURL = root.appendingPathComponent("retired.rpgle")
        try "**free\ndcl-proc Metadata;\nend-proc;".write(to: metadataURL, atomically: true, encoding: .utf8)
        try "**free\ndcl-proc Before;\nend-proc;".write(to: changedURL, atomically: true, encoding: .utf8)
        try "**free\ndcl-proc Retired;\nend-proc;".write(to: retiredURL, atomically: true, encoding: .utf8)

        let service = SourceWorkspaceIndexService()
        let initial = try service.scan(rootURL: root)
        XCTAssertFalse(initial.buildReport.isIncremental)
        XCTAssertEqual(initial.buildReport.analyzedDocumentCount, 3)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: metadataURL.path
        )
        try "**free\ndcl-proc After;\nend-proc;".write(to: changedURL, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: retiredURL)
        try "**free\ndcl-proc Added;\nend-proc;".write(
            to: root.appendingPathComponent("added.rpgle"),
            atomically: true,
            encoding: .utf8
        )

        let refreshed = try service.scan(rootURL: root, previousIndex: initial.index)
        XCTAssertTrue(refreshed.buildReport.isIncremental)
        XCTAssertEqual(refreshed.buildReport.previousIndexFingerprint, initial.index.fingerprint)
        XCTAssertTrue(refreshed.buildReport.isCurrent(for: refreshed.index))
        XCTAssertEqual(refreshed.buildReport.metadataOnlyDocumentCount, 1)
        XCTAssertEqual(refreshed.buildReport.reusedAnalysisCount, 1)
        XCTAssertEqual(refreshed.buildReport.reanalyzedDocumentCount, 1)
        XCTAssertEqual(refreshed.buildReport.addedDocumentCount, 1)
        XCTAssertEqual(refreshed.buildReport.removedDocumentCount, 1)
        XCTAssertEqual(
            initial.index.document(at: "metadata.rpgle")?.snapshot,
            refreshed.index.document(at: "metadata.rpgle")?.snapshot
        )
        XCTAssertNotEqual(
            initial.index.document(at: "changed.rpgle")?.snapshot,
            refreshed.index.document(at: "changed.rpgle")?.snapshot
        )
    }

    func testReviewedReplaySymbolsEnterCompletionAndSelectionChangesRevokeThem() throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        model.sourceDocument = SourceDocument(
            identity: .localScratch(name: "TEST.rpgle"),
            format: .rpgle,
            originalText: "**free\nCalcul"
        )
        model.reanalyzeSource()
        model.requestSourceCompletion(caretUTF16: model.sourceDocument.text.utf16.count)

        let reviewedItems = try XCTUnwrap(model.sourceCompletionSession).items.filter {
            $0.origin == .workspaceIndex
        }
        XCTAssertTrue(reviewedItems.contains {
            $0.label == "CalculateTax"
                && $0.sourceDocumentPath.map(SourceWorkspaceIndexSamples.reviewedScope.selectedPaths.contains) == true
        })
        XCTAssertTrue(model.sourceWorkspaceDependencyReviewIsCurrent)

        let occurrence = try XCTUnwrap(model.sourceWorkspaceIndex.search("CalculateTax").first {
            $0.kind == .symbol
        })
        XCTAssertTrue(model.openSourceWorkspaceResult(occurrence))
        XCTAssertEqual(model.openedSourceWorkspaceSnapshotPath, occurrence.relativePath)
        XCTAssertEqual(model.sourceDocument.text, model.sourceWorkspaceIndex.document(at: occurrence.relativePath)?.text)
        XCTAssertEqual(model.sourceNavigationRequest?.range.startLine, occurrence.line)
        let readOnlyText = model.sourceDocument.text
        model.updateSourceText(readOnlyText + "\n// blocked")
        XCTAssertEqual(model.sourceDocument.text, readOnlyText)
        model.returnToLocalSourceScratch()
        XCTAssertNil(model.openedSourceWorkspaceSnapshotPath)

        model.toggleSourceWorkspaceDependency("sql/order_audit.sql")
        XCTAssertNil(model.sourceWorkspaceDependencyReview)
        model.requestSourceCompletion(caretUTF16: model.sourceDocument.text.utf16.count)
        XCTAssertFalse((model.sourceCompletionSession?.items ?? []).contains { $0.origin == .workspaceIndex })

        model.sourceWorkspaceRenameCurrentName = "CalculateTax"
        model.sourceWorkspaceRenameProposedName = "CalculateOrderTax"
        model.prepareSourceWorkspaceRenamePlan()
        let plan = try XCTUnwrap(model.sourceWorkspaceRenamePlan)
        XCTAssertTrue(plan.isCurrent(for: model.sourceWorkspaceIndex))
        XCTAssertTrue(plan.baselines.contains { $0.sourceDate != nil })
    }

    func testResponsiveWorkspaceSearchDebouncesAndPublishesOnlyTheNewestReceipt() async throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        try await waitUntil {
            model.sourceWorkspaceSearchPhase == .ready
                && model.sourceWorkspaceSearchReportIsCurrent
        }

        let indexFingerprint = model.sourceWorkspaceIndex.fingerprint
        model.updateSourceWorkspaceSearchQuery("CalculateTax")
        XCTAssertEqual(model.sourceWorkspaceSearchPhase, .searching)
        model.updateSourceWorkspaceSearchQuery("OrderTotal")
        XCTAssertEqual(model.sourceWorkspaceSearchPhase, .searching)
        XCTAssertTrue(model.sourceWorkspaceSearchResults.isEmpty)
        XCTAssertNil(model.currentSourceWorkspaceSearchReport)

        try await waitUntil {
            model.sourceWorkspaceSearchPhase == .ready
                && model.sourceWorkspaceSearchReportIsCurrent
        }
        let report = try XCTUnwrap(model.sourceWorkspaceSearchReport)
        XCTAssertEqual(report.query, "OrderTotal")
        XCTAssertEqual(report.indexFingerprint, indexFingerprint)
        XCTAssertFalse(report.results.isEmpty)
        XCTAssertEqual(model.sourceWorkspaceSearchResults, report.results)
        XCTAssertNotNil(model.sourceWorkspaceSearchDurationMilliseconds)
        XCTAssertTrue(model.sourceWorkspaceSearchStatusLabel.contains("MS"))

        model.updateSourceWorkspaceSearchQuery("query-that-will-be-cancelled")
        XCTAssertEqual(model.sourceWorkspaceSearchPhase, .searching)
        model.cancelSourceWorkspaceSearch()
        XCTAssertEqual(model.sourceWorkspaceSearchPhase, .idle)
        XCTAssertFalse(model.sourceWorkspaceSearchReportIsCurrent)
        XCTAssertTrue(model.sourceWorkspaceSearchResults.isEmpty)
        XCTAssertNil(model.currentSourceWorkspaceSearchReport)
        XCTAssertEqual(model.sourceWorkspaceIndex.fingerprint, indexFingerprint)
    }

    func testAppModelPublishesOnlyTheCurrentDeltaRefreshReceipt() async throws {
        let root = temporaryDirectory(named: "delta-model")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stableURL = root.appendingPathComponent("stable.rpgle")
        let changedURL = root.appendingPathComponent("changed.rpgle")
        try "**free\ndcl-proc Stable;\nend-proc;".write(to: stableURL, atomically: true, encoding: .utf8)
        try "**free\ndcl-proc Before;\nend-proc;".write(to: changedURL, atomically: true, encoding: .utf8)

        let model = AppModel()
        model.scanSourceWorkspace(at: root)
        try await waitUntil {
            model.sourceWorkspaceIndexPhase == .ready
                && model.currentSourceWorkspaceIndexBuildReport != nil
        }
        let initialFingerprint = model.sourceWorkspaceIndex.fingerprint
        XCTAssertFalse(try XCTUnwrap(model.currentSourceWorkspaceIndexBuildReport).isIncremental)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: stableURL.path
        )
        try "**free\ndcl-proc After;\nend-proc;".write(to: changedURL, atomically: true, encoding: .utf8)
        model.refreshSourceWorkspaceIndex()
        try await waitUntil {
            model.sourceWorkspaceIndexPhase == .ready
                && model.currentSourceWorkspaceIndexBuildReport?.previousIndexFingerprint == initialFingerprint
        }

        let report = try XCTUnwrap(model.currentSourceWorkspaceIndexBuildReport)
        XCTAssertTrue(report.isIncremental)
        XCTAssertEqual(report.metadataOnlyDocumentCount, 1)
        XCTAssertEqual(report.reanalyzedDocumentCount, 1)
        XCTAssertEqual(report.reusedAnalysisCount, 1)
        XCTAssertEqual(report.analyzedDocumentCount, 1)
        XCTAssertTrue(model.sourceWorkspaceIndexRefreshStatusLabel.contains("REUSED"))
        XCTAssertTrue(model.sourceWorkspaceIndexRefreshReceiptLabel.contains(report.shortFingerprint))
        XCTAssertNotNil(model.sourceWorkspaceIndexDurationMilliseconds)
    }

    func testReviewedRenameAppliesExactBatchAndPreservesExcludedTextAndPermissions() throws {
        let root = temporaryDirectory(named: "rename-apply")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let firstURL = sourceDirectory.appendingPathComponent("tax.rpgle")
        let secondURL = sourceDirectory.appendingPathComponent("order.rpgle")
        let first = """
        **free
        dcl-proc CalculateTax;
          // CalculateTax remains documentation
          dcl-s label varchar(40) inz('CalculateTax');
          CalculateTax();
        end-proc;
        """
        let second = "**free\ndcl-s total packed(11:2);\ntotal = CalculateTax();\n"
        try first.write(to: firstURL, atomically: true, encoding: .utf8)
        try second.write(to: secondURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: firstURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secondURL.path)

        let service = SourceWorkspaceIndexService()
        let scan = try service.scan(rootURL: root)
        let plan = try scan.index.makeRenamePlan(
            currentName: "CalculateTax",
            proposedName: "CalculateOrderTax"
        )
        let review = try ReviewedSourceWorkspaceRename(index: scan.index, plan: plan)
        let receipt = try service.applyReviewedRename(
            rootURL: root,
            index: scan.index,
            plan: plan,
            review: review
        )

        let appliedFirst = try String(contentsOf: firstURL, encoding: .utf8)
        let appliedSecond = try String(contentsOf: secondURL, encoding: .utf8)
        XCTAssertTrue(appliedFirst.contains("dcl-proc CalculateOrderTax;"))
        XCTAssertTrue(appliedFirst.contains("CalculateOrderTax();"))
        XCTAssertTrue(appliedFirst.contains("// CalculateTax remains documentation"))
        XCTAssertTrue(appliedFirst.contains("inz('CalculateTax')"))
        XCTAssertTrue(appliedSecond.contains("CalculateOrderTax()"))
        XCTAssertEqual(receipt.changedPaths, ["src/order.rpgle", "src/tax.rpgle"])
        XCTAssertEqual(receipt.replacementCount, 3)
        XCTAssertEqual(receipt.resultContentFingerprints.count, 2)
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: firstURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o640
        )
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: secondURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertFalse(plan.isCurrent(for: try service.scan(rootURL: root).index))
    }

    func testReviewedRenameRefusesChangedOrSymbolicTargetsBeforeWriting() throws {
        let root = temporaryDirectory(named: "rename-refuse")
        let outside = temporaryDirectory(named: "rename-outside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let firstURL = root.appendingPathComponent("first.rpgle")
        let secondURL = root.appendingPathComponent("second.rpgle")
        let first = "**free\nCalculateTax();\n"
        let second = "**free\nCalculateTax();\n"
        try first.write(to: firstURL, atomically: true, encoding: .utf8)
        try second.write(to: secondURL, atomically: true, encoding: .utf8)

        let service = SourceWorkspaceIndexService()
        let scan = try service.scan(rootURL: root)
        let plan = try scan.index.makeRenamePlan(currentName: "CalculateTax", proposedName: "CalculateOrderTax")
        let review = try ReviewedSourceWorkspaceRename(index: scan.index, plan: plan)
        try (second + "// changed\n").write(to: secondURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.applyReviewedRename(
            rootURL: root,
            index: scan.index,
            plan: plan,
            review: review
        )) { error in
            XCTAssertEqual(error as? LocalSourceWorkspaceRenameError, .baselineChanged("second.rpgle"))
        }
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), first)

        try second.write(to: secondURL, atomically: true, encoding: .utf8)
        let fresh = try service.scan(rootURL: root)
        let freshPlan = try fresh.index.makeRenamePlan(currentName: "CalculateTax", proposedName: "CalculateOrderTax")
        let freshReview = try ReviewedSourceWorkspaceRename(index: fresh.index, plan: freshPlan)
        let outsideURL = outside.appendingPathComponent("outside.rpgle")
        try second.write(to: outsideURL, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: secondURL)
        try FileManager.default.createSymbolicLink(at: secondURL, withDestinationURL: outsideURL)
        XCTAssertThrowsError(try service.applyReviewedRename(
            rootURL: root,
            index: fresh.index,
            plan: freshPlan,
            review: freshReview
        )) { error in
            XCTAssertEqual(error as? LocalSourceWorkspaceRenameError, .unsafeTarget("second.rpgle"))
        }
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), first)
        XCTAssertEqual(try String(contentsOf: outsideURL, encoding: .utf8), second)
    }

    func testReviewedRenameRollsBackCommittedFilesAfterInjectedFailure() throws {
        let root = temporaryDirectory(named: "rename-rollback")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstURL = root.appendingPathComponent("first.rpgle")
        let secondURL = root.appendingPathComponent("second.rpgle")
        let first = "**free\nCalculateTax();\n"
        let second = "**free\ndcl-s result int(10);\nresult = CalculateTax();\n"
        try first.write(to: firstURL, atomically: true, encoding: .utf8)
        try second.write(to: secondURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: firstURL.path)

        let service = SourceWorkspaceIndexService()
        let scan = try service.scan(rootURL: root)
        let plan = try scan.index.makeRenamePlan(currentName: "CalculateTax", proposedName: "CalculateOrderTax")
        let review = try ReviewedSourceWorkspaceRename(index: scan.index, plan: plan)

        XCTAssertThrowsError(try service.applyReviewedRename(
            rootURL: root,
            index: scan.index,
            plan: plan,
            review: review,
            control: SourceWorkspaceRenameApplyControl(failAfterCommittedFileCount: 1)
        )) { error in
            guard case .applyFailed(_, let recovery) = error as? LocalSourceWorkspaceRenameError else {
                return XCTFail("Expected a rollback-aware application failure")
            }
            XCTAssertTrue(recovery.isComplete)
            XCTAssertEqual(recovery.restoredPaths, ["first.rpgle"])
            XCTAssertTrue(recovery.unresolvedPaths.isEmpty)
        }
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), first)
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), second)
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: firstURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o640
        )
        XCTAssertTrue(plan.isCurrent(for: try service.scan(rootURL: root).index))
    }

    func testAppModelRequiresAttestationThenAppliesAndRescansReviewedRename() async throws {
        let root = temporaryDirectory(named: "rename-model")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("order.rpgle")
        try "**free\ndcl-proc CalculateTax;\nCalculateTax();\nend-proc;\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )

        let model = AppModel()
        model.scanSourceWorkspace(at: root)
        try await waitUntil { model.sourceWorkspaceIndexPhase == .ready }
        XCTAssertNotEqual(model.sourceWorkspaceDriftPhase, .failed, model.sourceWorkspaceDriftDiagnostic)
        try await waitUntil { model.sourceWorkspaceEvidenceIsCurrent }
        model.sourceWorkspaceRenameCurrentName = "CalculateTax"
        model.sourceWorkspaceRenameProposedName = "CalculateOrderTax"
        model.prepareSourceWorkspaceRenamePlan()
        model.presentSourceWorkspaceRenameReview()

        XCTAssertTrue(model.sourceWorkspaceRenameReviewIsCurrent)
        XCTAssertFalse(model.sourceWorkspaceRenameCanApply)
        model.sourceWorkspaceRenameAttested = true
        XCTAssertTrue(model.sourceWorkspaceRenameCanApply)
        model.applyReviewedSourceWorkspaceRename()
        try await waitUntil {
            model.sourceWorkspaceRenameApplyPhase == .applied
                || model.sourceWorkspaceRenameApplyPhase == .failed
        }

        XCTAssertEqual(model.sourceWorkspaceRenameApplyPhase, .applied)
        XCTAssertNil(model.sourceWorkspaceRenamePlan)
        XCTAssertNil(model.sourceWorkspaceRenameReview)
        XCTAssertFalse(model.isSourceWorkspaceRenameReviewPresented)
        XCTAssertEqual(model.sourceWorkspaceRenameApplyReceipt?.replacementCount, 2)
        XCTAssertTrue(try String(contentsOf: sourceURL, encoding: .utf8).contains("CalculateOrderTax"))
        XCTAssertEqual(model.sourceWorkspaceIndex.documents.first?.text, try String(contentsOf: sourceURL, encoding: .utf8))
    }

    func testReviewedHostIncludeReplayRequiresAttestationAndInstallsExactOverlay() throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        model.selectSourceWorkspaceDocument("qrpglesrc/orderentry.rpgle")
        let candidate = try XCTUnwrap(model.selectedSourceWorkspaceHostIncludeCandidate)
        XCTAssertEqual(candidate.resolution, .hostBacked)

        model.presentSourceWorkspaceHostIncludeReview(candidate.id)
        XCTAssertTrue(model.sourceWorkspaceHostIncludeReviewIsCurrent)
        XCTAssertEqual(model.sourceWorkspaceHostIncludePhase, .reviewReady)
        XCTAssertFalse(model.sourceWorkspaceHostIncludeCanRead)
        XCTAssertTrue(model.isSourceWorkspaceHostIncludeReviewPresented)

        let reviewContent = SourceWorkspaceHostIncludeReviewView()
            .environment(model)
            .frame(width: 1_180, height: 760)
        let renderer = ImageRenderer(content: reviewContent)
        renderer.proposedSize = ProposedViewSize(width: 1_180, height: 760)
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_180)
        XCTAssertEqual(image.height, 760)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_ATLAS"] == "1" {
            let host = NSHostingView(rootView: reviewContent)
            host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-host-include-review-native.png"),
                options: .atomic
            )
        }

        model.sourceWorkspaceHostIncludeAttested = true
        XCTAssertTrue(model.sourceWorkspaceHostIncludeCanRead)
        model.readReviewedSourceWorkspaceHostInclude()

        let content = try XCTUnwrap(model.sourceWorkspaceHostIncludeContent)
        XCTAssertEqual(model.sourceWorkspaceHostIncludePhase, .installed)
        XCTAssertEqual(model.sourceWorkspaceIndex.hostIncludeFileCount, 1)
        XCTAssertFalse(model.isSourceWorkspaceHostIncludeReviewPresented)
        XCTAssertNil(model.sourceWorkspaceHostIncludeReview)
        XCTAssertTrue(model.sourceWorkspaceIndex.document(at: content.overlayRelativePath)?.origin.isHostBacked == true)
        XCTAssertEqual(
            model.sourceWorkspaceIndex.outboundDependencies(for: "qrpglesrc/orderentry.rpgle")
                .first(where: { $0.targetLabel == candidate.targetLabel })?.resolution,
            .exact
        )
        XCTAssertTrue(try model.sourceWorkspaceIndex.search("CustomerTemplate").contains {
            $0.relativePath == content.overlayRelativePath && $0.kind == .symbol
        })

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_ATLAS"] == "1" {
            let atlas = SourceCrossReferenceAtlasView()
                .environment(model)
                .frame(width: 1_360, height: 840)
            let host = NSHostingView(rootView: atlas)
            host.frame = CGRect(x: 0, y: 0, width: 1_360, height: 840)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-source-atlas-host-overlay-native.png"),
                options: .atomic
            )
        }

        model.sourceWorkspaceDependencySelection = [content.overlayRelativePath]
        model.attestSourceWorkspaceDependencies()
        XCTAssertTrue(model.reviewedSourceWorkspaceCompletionSymbols.contains {
            $0.symbol.name == "CustomerTemplate"
        })

        model.removeSourceWorkspaceHostIncludes()
        XCTAssertEqual(model.sourceWorkspaceIndex.hostIncludeFileCount, 0)
        XCTAssertNil(model.sourceWorkspaceHostIncludeContent)
        XCTAssertEqual(model.selectedSourceWorkspaceHostIncludeCandidate?.resolution, .hostBacked)
    }

    func testCompilerEvidenceBridgeRequiresReviewThenOpensOnlyExactSnapshotCoordinates() throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        model.selectSourceWorkspaceDocument("qrpglesrc/orderentry.rpgle")
        model.presentSourceWorkspaceCompileEvidence()

        let review = try XCTUnwrap(model.sourceWorkspaceCompileReview)
        XCTAssertTrue(model.sourceWorkspaceCompileReviewIsCurrent)
        XCTAssertTrue(model.isSourceWorkspaceCompileEvidencePresented)
        XCTAssertEqual(review.mappings.count, 1)
        XCTAssertEqual(review.mappings.first?.documentPath, "qrpglesrc/orderentry.rpgle")
        XCTAssertEqual(review.mappings.first?.revisionState, .exact)
        XCTAssertEqual(review.releaseEvidence.effectiveTargetRelease, try IBMReleaseLevel("V7R6M0"))
        XCTAssertEqual(review.diagnostics.count, 4)
        XCTAssertEqual(review.exactNavigationCount, 3)
        XCTAssertEqual(review.blockedNavigationCount, 1)
        XCTAssertEqual(review.unlinkedDiagnosticCount, 1)
        XCTAssertFalse(model.sourceWorkspaceCompileCanAttach)

        model.attachReviewedSourceWorkspaceCompileEvidence()
        XCTAssertNil(model.sourceWorkspaceCompileAttachment)
        model.sourceWorkspaceCompileAttested = true
        XCTAssertTrue(model.sourceWorkspaceCompileCanAttach)
        model.attachReviewedSourceWorkspaceCompileEvidence()

        XCTAssertTrue(model.sourceWorkspaceCompileAttachmentIsCurrent)
        XCTAssertEqual(model.sourceWorkspaceCompileStatusLabel, "ATTACHED")
        XCTAssertEqual(model.sourceWorkspaceCompileDiagnosticsForSelectedDocument.count, 4)
        XCTAssertNil(model.sourceWorkspaceHostIncludeContent)

        let exact = try XCTUnwrap(model.sourceWorkspaceCompileAttachment?.diagnostics.first(where: \.canNavigate))
        XCTAssertTrue(model.openSourceWorkspaceCompileDiagnostic(exact.id))
        XCTAssertEqual(model.openedSourceWorkspaceSnapshotPath, exact.documentPath)
        XCTAssertEqual(model.sourceNavigationRequest?.range.startLine, exact.range.startLine)
        XCTAssertFalse(model.isSourceWorkspaceCompileEvidencePresented)

        let retainedText = model.sourceDocument.text
        model.updateSourceText(retainedText + "\n// blocked")
        XCTAssertEqual(model.sourceDocument.text, retainedText)
    }

    func testCompilerEvidenceBridgeMarksAChangedCompileRevisionAsNonNavigable() throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        let passedRun = try XCTUnwrap(model.compileRuns.first(where: { $0.sequence == 183 }))
        model.selectSourceWorkspaceCompileRun(passedRun.id)

        let review = try XCTUnwrap(model.sourceWorkspaceCompileReview)
        XCTAssertTrue(model.sourceWorkspaceCompileReviewIsCurrent)
        XCTAssertEqual(review.mappings.first?.revisionState, .different)
        XCTAssertTrue(review.diagnostics.isEmpty)
        XCTAssertEqual(review.exactNavigationCount, 0)
        XCTAssertFalse(model.sourceWorkspaceCompileAttachmentIsCurrent)
    }

    func testIncludeNavigatorStagesOnlyExactCurrentClosureAndDriftRevokesIt() throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        model.selectSourceWorkspaceDocument("qrpglesrc/orderentry.rpgle")

        let chain = try XCTUnwrap(model.currentSourceWorkspaceIncludeChain)
        XCTAssertEqual(chain.documents.map(\.relativePath), [
            "qrpglesrc/orderentry.rpgle",
            "includes/taxrules.cpy"
        ])
        XCTAssertEqual(chain.directives.count, 2)
        XCTAssertEqual(chain.boundaries.map(\.kind), [.hostContentNotLoaded])
        model.presentSourceWorkspaceIncludeChain()
        XCTAssertTrue(model.isSourceWorkspaceIncludeChainPresented)

        model.useSourceWorkspaceIncludeClosure()
        XCTAssertEqual(model.sourceWorkspaceDependencySelection, Set(chain.exactDocumentPaths))
        XCTAssertNil(model.sourceWorkspaceDependencyReview)

        model.sourceWorkspaceDriftPhase = .watching
        model.recordSourceWorkspaceDrift([
            try SourceWorkspaceDriftObservation(
                relativePath: "qrpglesrc/orderentry.rpgle",
                kinds: [.modified],
                eventID: 811
            )
        ])
        XCTAssertNil(model.currentSourceWorkspaceIncludeChain)
        XCTAssertEqual(model.sourceWorkspaceIncludeChainStatusLabel, "FROZEN · VERIFY FIRST")
    }

    func testIncludeNavigatorRendersAtNativeReviewSize() throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        model.selectSourceWorkspaceDocument("qrpglesrc/orderentry.rpgle")
        let content = SourceWorkspaceIncludeChainView()
            .environment(model)
            .frame(width: 1_180, height: 760)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_180, height: 760)
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_180)
        XCTAssertEqual(image.height, 760)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_ATLAS"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-source-include-chain-native.png"),
                options: .atomic
            )
        }
    }

    func testCompilerEvidenceBridgeRendersAtNativeReviewSize() throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        model.presentSourceWorkspaceCompileEvidence()
        let content = SourceWorkspaceCompilerEvidenceView()
            .environment(model)
            .frame(width: 1_180, height: 760)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_180, height: 760)
        let image = try XCTUnwrap(renderer.cgImage)

        XCTAssertEqual(image.width, 1_180)
        XCTAssertEqual(image.height, 760)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_COMPILE_BRIDGE"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-source-compile-bridge-native.png"),
                options: .atomic
            )
        }
    }

    func testSourceAtlasRendersAtNativeWorkbenchSize() async throws {
        let model = AppModel()
        model.restoreSourceWorkspaceIndexReplay()
        try await waitUntil {
            model.sourceWorkspaceSearchPhase == .ready
                && model.sourceWorkspaceSearchReportIsCurrent
        }
        let content = SourceCrossReferenceAtlasView()
            .environment(model)
            .frame(width: 1_360, height: 840)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_360, height: 840)

        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_360)
        XCTAssertEqual(image.height, 840)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_ATLAS"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_360, height: 840)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-source-cross-reference-atlas-native.png"),
                options: .atomic
            )
        }

        let refreshReceiptContent = SourceWorkspaceIndexRefreshReceiptView()
            .environment(model)
            .frame(width: 1_080, height: 720)
        let refreshReceiptRenderer = ImageRenderer(content: refreshReceiptContent)
        refreshReceiptRenderer.proposedSize = ProposedViewSize(width: 1_080, height: 720)
        let refreshReceiptImage = try XCTUnwrap(refreshReceiptRenderer.cgImage)
        XCTAssertEqual(refreshReceiptImage.width, 1_080)
        XCTAssertEqual(refreshReceiptImage.height, 720)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_ATLAS"] == "1" {
            let receiptHost = NSHostingView(rootView: refreshReceiptContent)
            receiptHost.frame = CGRect(x: 0, y: 0, width: 1_080, height: 720)
            receiptHost.layoutSubtreeIfNeeded()
            receiptHost.displayIfNeeded()
            let representation = try XCTUnwrap(
                receiptHost.bitmapImageRepForCachingDisplay(in: receiptHost.bounds)
            )
            receiptHost.cacheDisplay(in: receiptHost.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-source-index-refresh-receipt-native.png"),
                options: .atomic
            )
        }

        let occurrence = try XCTUnwrap(model.sourceWorkspaceIndex.search("CalculateTax").first {
            $0.kind == .symbol
        })
        XCTAssertTrue(model.openSourceWorkspaceResult(occurrence))
        let snapshotContent = SourceWorkspaceView()
            .environment(model)
            .frame(width: 1_360, height: 840)
        let snapshotRenderer = ImageRenderer(content: snapshotContent)
        snapshotRenderer.proposedSize = ProposedViewSize(width: 1_360, height: 840)
        let snapshotImage = try XCTUnwrap(snapshotRenderer.cgImage)
        XCTAssertEqual(snapshotImage.width, 1_360)
        XCTAssertEqual(snapshotImage.height, 840)

        let snapshotHost = NSHostingView(rootView: snapshotContent)
        snapshotHost.frame = CGRect(x: 0, y: 0, width: 1_360, height: 840)
        snapshotHost.layoutSubtreeIfNeeded()
        snapshotHost.displayIfNeeded()
        let editor = try XCTUnwrap(
            descendantTextViews(in: snapshotHost).first(where: { $0.string == model.sourceDocument.text })
        )
        XCTAssertFalse(editor.isEditable)
        XCTAssertEqual(editor.accessibilityLabel(), "Read-only indexed source snapshot")
        XCTAssertEqual(editor.enclosingScrollView?.documentVisibleRect.minX ?? -1, 0, accuracy: 0.5)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_ATLAS"] == "1" {
            let representation = try XCTUnwrap(
                snapshotHost.bitmapImageRepForCachingDisplay(in: snapshotHost.bounds)
            )
            snapshotHost.cacheDisplay(in: snapshotHost.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-source-index-snapshot-native.png"),
                options: .atomic
            )
        }

        model.restoreSourceWorkspaceIndexReplay()
        model.presentSourceWorkspaceRenameReview()
        XCTAssertTrue(model.sourceWorkspaceRenameReviewIsCurrent)
        XCTAssertFalse(model.sourceWorkspaceRenameCanApply)
        let reviewContent = SourceWorkspaceRenameReviewView()
            .environment(model)
            .frame(width: 1_180, height: 760)
        let reviewRenderer = ImageRenderer(content: reviewContent)
        reviewRenderer.proposedSize = ProposedViewSize(width: 1_180, height: 760)
        let reviewImage = try XCTUnwrap(reviewRenderer.cgImage)
        XCTAssertEqual(reviewImage.width, 1_180)
        XCTAssertEqual(reviewImage.height, 760)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_ATLAS"] == "1" {
            let reviewHost = NSHostingView(rootView: reviewContent)
            reviewHost.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            reviewHost.layoutSubtreeIfNeeded()
            reviewHost.displayIfNeeded()
            let representation = try XCTUnwrap(reviewHost.bitmapImageRepForCachingDisplay(in: reviewHost.bounds))
            reviewHost.cacheDisplay(in: reviewHost.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-reviewed-rename-native.png"),
                options: .atomic
            )
        }

        model.sourceWorkspaceDriftPhase = .pending
        model.sourceWorkspaceDriftReceipt = SourceWorkspaceDriftSamples.receipt
        let driftContent = SourceWorkspaceDriftReceiptView()
            .environment(model)
            .frame(width: 1_080, height: 720)
        let driftRenderer = ImageRenderer(content: driftContent)
        driftRenderer.proposedSize = ProposedViewSize(width: 1_080, height: 720)
        let driftImage = try XCTUnwrap(driftRenderer.cgImage)
        XCTAssertEqual(driftImage.width, 1_080)
        XCTAssertEqual(driftImage.height, 720)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SOURCE_ATLAS"] == "1" {
            let driftHost = NSHostingView(rootView: driftContent)
            driftHost.frame = CGRect(x: 0, y: 0, width: 1_080, height: 720)
            driftHost.layoutSubtreeIfNeeded()
            driftHost.displayIfNeeded()
            let representation = try XCTUnwrap(driftHost.bitmapImageRepForCachingDisplay(in: driftHost.bounds))
            driftHost.cacheDisplay(in: driftHost.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-source-workspace-drift-native.png"),
                options: .atomic
            )
        }
    }

    private func temporaryDirectory(named suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-source-atlas-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    }

    private func descendantTextViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(descendantTextViews)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for AppModel state", file: file, line: line)
    }
}
