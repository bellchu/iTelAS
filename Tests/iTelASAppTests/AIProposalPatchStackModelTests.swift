import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class AIProposalPatchStackModelTests: XCTestCase {
    func testModelQueuesCompatibleHunksAndBuildsOneAtomicPreview() throws {
        let model = try makePopulatedModel()

        XCTAssertEqual(model.aiProposalPatchStack.count, 2)
        XCTAssertEqual(model.selectedAIProposalPatchIDs.count, 2)
        XCTAssertEqual(model.aiProposalPatchPreview?.revisedText, "ALPHA beta GAMMA_VALUE\n")
        XCTAssertFalse(model.aiProposalPatchWasApplied)
        XCTAssertEqual(model.sourceDocument.text, "alpha beta gamma\n")
    }

    func testPatchStackWorkspaceRendersAtItsNativeSheetSize() throws {
        let model = try makePopulatedModel()
        let content = AIProposalPatchStackView()
            .environment(model)
            .frame(width: 1_320, height: 820)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_320, height: 820)

        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_320)
        XCTAssertEqual(image.height, 820)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_PATCH_STACK"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_320, height: 820)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(
                host.bitmapImageRepForCachingDisplay(in: host.bounds)
            )
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(
                representation.representation(using: .png, properties: [:])
            )
            try data.write(to: URL(
                fileURLWithPath: "/tmp/itelas-proposal-patch-stack-native.png"
            ), options: .atomic)
        }
    }

    private func makePopulatedModel() throws -> AppModel {
        let model = AppModel()
        let source = "alpha beta gamma\n"
        model.sourceDocument = SourceDocument(
            identity: .localScratch(name: "PATCHSTACK.rpgle"),
            format: .rpgle,
            sourceDatePolicy: .preserve,
            originalText: source
        )
        let baseline = AIContentFingerprint.sha256(source)
        let first = try AIEditProposal(
            target: .sourceDraft,
            documentName: "PATCHSTACK.rpgle",
            baselineSHA256: baseline,
            selection: AITextSelection(locationUTF16: 0, lengthUTF16: 5),
            replacement: "ALPHA"
        )
        let second = try AIEditProposal(
            target: .sourceDraft,
            documentName: "PATCHSTACK.rpgle",
            baselineSHA256: baseline,
            selection: AITextSelection(locationUTF16: 11, lengthUTF16: 5),
            replacement: "GAMMA_VALUE"
        )

        model.latestAIEditProposal = first
        model.latestAIProposalExplanation = "Normalize the first token."
        model.queueLatestAIProposal()
        model.latestAIEditProposal = second
        model.latestAIProposalExplanation = "Expand the final token."
        model.queueLatestAIProposal()
        return model
    }
}
