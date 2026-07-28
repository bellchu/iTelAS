import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class CompileLineageAppTests: XCTestCase {
    func testModelBuildsExactTargetLineageAndMessageDelta() throws {
        let model = isolatedModel(suffix: "comparison")

        model.presentCompileLineage()

        let comparison = try XCTUnwrap(model.compileLineageComparison)
        XCTAssertTrue(model.isCompileLineagePresented)
        XCTAssertEqual(model.compileLineageCurrentRun?.sequence, 184)
        XCTAssertEqual(model.compileLineageBaselineRun?.sequence, 183)
        XCTAssertEqual(comparison.runs.count, 2)
        XCTAssertEqual(comparison.trend, .regressionObserved)
        XCTAssertEqual(comparison.diagnostics.introduced.count, 5)
        XCTAssertTrue(comparison.diagnostics.resolved.isEmpty)
        XCTAssertTrue(comparison.diagnostics.persistent.isEmpty)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "target" })?.state, .exact)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "source" })?.state, .exact)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "revision" })?.state, .changed)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "command" })?.state, .exact)
        XCTAssertEqual(comparison.fields.first(where: { $0.id == "release" })?.state, .exact)
        XCTAssertTrue(model.compileLineageDiagnostic.contains(comparison.shortFingerprint))
    }

    func testSelectingSingleRunTargetRefusesFallbackBaseline() throws {
        let model = isolatedModel(suffix: "scope")
        model.presentCompileLineage()
        let serviceRun = try XCTUnwrap(model.compileRuns.first(where: { $0.sequence == 182 }))
        let unrelatedRun = try XCTUnwrap(model.compileRuns.first(where: { $0.sequence == 183 }))

        model.selectCompileLineageCurrent(serviceRun.id)

        XCTAssertEqual(model.compileLineageCurrentRun?.id, serviceRun.id)
        XCTAssertNil(model.compileLineageBaselineRunID)
        XCTAssertEqual(model.compileLineageScopedRuns.map(\.id), [serviceRun.id])
        XCTAssertNil(model.compileLineageComparison)
        XCTAssertTrue(model.compileLineageValidationMessage?.contains("at least 2") == true)

        model.selectCompileLineageBaseline(unrelatedRun.id)

        XCTAssertNil(model.compileLineageBaselineRunID)
        XCTAssertTrue(model.compileLineageDiagnostic.contains("same exact target"))
    }

    func testPinningLineageFreezesAdviceOnlyContextWithoutProviderUse() throws {
        let model = isolatedModel(suffix: "assist")
        model.presentCompileLineage()
        let comparison = try XCTUnwrap(model.compileLineageComparison)

        model.prepareCompileLineageAssist()

        let fragment = try XCTUnwrap(model.preparedAssistantContextBundle?.fragments.first)
        XCTAssertTrue(model.isAssistantVisible)
        XCTAssertTrue(model.isAIContextPreviewPresented)
        XCTAssertNotNil(model.latestAIContextReceipt)
        XCTAssertEqual(fragment.kind, .compileEvidence)
        XCTAssertEqual(fragment.language, "IBM i compile lineage")
        XCTAssertTrue(fragment.content.contains("ITELAS COMPILE LINEAGE v1"))
        XCTAssertTrue(fragment.content.contains(comparison.fingerprint))
        XCTAssertTrue(fragment.content.contains("not causal proof"))
        XCTAssertFalse(fragment.content.lowercased().contains("ctl-opt"))
        XCTAssertTrue(model.compileLineageDiagnostic.contains("pinned locally"))
    }

    func testCompileLineageBoardRendersAtNativeReviewSize() throws {
        let model = isolatedModel(suffix: "render")
        model.presentCompileLineage()
        let content = CompileLineageBoardView()
            .environment(model)
            .frame(width: 1_180, height: 760)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_180, height: 760)
        let image = try XCTUnwrap(renderer.cgImage)

        XCTAssertEqual(image.width, 1_180)
        XCTAssertEqual(image.height, 760)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_COMPILE_LINEAGE"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-compile-lineage-native.png"),
                options: .atomic
            )
        }
    }

    private func isolatedModel(suffix: String) -> AppModel {
        AppModel(
            continuityCasebookStore: ContinuityCasebookStore(
                baseDirectoryURL: temporaryDirectory(named: "\(suffix)-casebook")
            ),
            terminalFlightRecorderStore: TerminalFlightRecorderStore(
                baseDirectoryURL: temporaryDirectory(named: "\(suffix)-recorder")
            ),
            compileRecipeStore: CompileRecipeStore(
                baseDirectoryURL: temporaryDirectory(named: "\(suffix)-recipes")
            )
        )
    }

    private func temporaryDirectory(named suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-compile-lineage-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    }
}
