import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class ContinuityCasebookAppTests: XCTestCase {
    func testPermissionRestrictedStoreRoundTripsAndRejectsSymlinkFiles() throws {
        let base = temporaryDirectory(named: "store")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ContinuityCasebookStore(baseDirectoryURL: base)
        let casebook = ContinuityCasebookSamples.makeCasebook()

        try store.write(casebook)

        XCTAssertEqual(try store.read(), casebook)
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: base.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(directoryMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: store.fileURL.path
        )
        XCTAssertThrowsError(try store.read())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: store.fileURL.path
        )

        let linkedBase = temporaryDirectory(named: "symlink")
        defer { try? FileManager.default.removeItem(at: linkedBase) }
        let linkedStore = ContinuityCasebookStore(baseDirectoryURL: linkedBase)
        try FileManager.default.createDirectory(
            at: linkedBase,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createSymbolicLink(
            at: linkedStore.fileURL,
            withDestinationURL: store.fileURL
        )
        XCTAssertThrowsError(try linkedStore.read())

        let parentLink = temporaryDirectory(named: "parent-link")
        defer { try? FileManager.default.removeItem(at: parentLink) }
        try FileManager.default.createSymbolicLink(
            at: parentLink,
            withDestinationURL: base
        )
        XCTAssertThrowsError(
            try ContinuityCasebookStore(baseDirectoryURL: parentLink).read()
        )
    }

    func testModelCapturesExactCurrentContextIntoDurableCase() throws {
        let base = temporaryDirectory(named: "capture")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ContinuityCasebookStore(baseDirectoryURL: base)
        let model = AppModel(continuityCasebookStore: store)
        let fragment = try AIContextFragment(
            kind: .jobIncident,
            documentName: "INC-0427-job.txt",
            language: "IBM i incident evidence",
            sourceText: "ARBATCH WAITING\nPASSWORD: local-test-value"
        )
        model.preparedAssistantContextBundle = try AIContextBundle(fragments: [fragment])
        model.preparedAssistantContextLabel = "Reviewed queue evidence"

        model.capturePreparedAssistantContextInCasebook()

        XCTAssertFalse(model.continuityCasebookUsesReplay)
        let artifact = try XCTUnwrap(model.selectedContinuityCase?.artifacts.first)
        XCTAssertEqual(artifact.content, fragment.content)
        XCTAssertEqual(artifact.sourceReceipt, fragment.contentSHA256)
        XCTAssertTrue(artifact.wasRedacted)
        XCTAssertEqual(try store.read(), model.continuityCasebook)
    }

    func testModelRecordsAnswerWithCompletionAndRequestProvenance() throws {
        let base = temporaryDirectory(named: "ledger")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ContinuityCasebookStore(baseDirectoryURL: base)
        let model = AppModel(continuityCasebookStore: store)
        let requestedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let contextFingerprint = AIContentFingerprint.sha256("reviewed-context")
        let message = AssistantMessage(
            id: UUID(uuidString: "81111111-1111-4111-8111-111111111111")!,
            role: .assistant,
            content: "Refresh the exact job and lock samples before acting.",
            commandRisk: .readOnly,
            provenance: AssistantResponseProvenance(
                question: "What is the smallest safe next check?",
                endpointHost: "provider.example",
                model: "configured-model",
                contextFingerprint: contextFingerprint,
                contextItemCount: 2,
                requestedAt: requestedAt
            )
        )

        model.recordAssistantMessageInCasebook(message)

        let answer = try XCTUnwrap(model.selectedContinuityCase?.answers.first)
        XCTAssertEqual(answer.id, message.id)
        XCTAssertEqual(answer.state, .complete)
        XCTAssertEqual(answer.commandRisk, .readOnly)
        XCTAssertEqual(answer.contextFingerprint, contextFingerprint)
        XCTAssertEqual(answer.contextItemCount, 2)
        XCTAssertEqual(answer.createdAt, requestedAt)
        XCTAssertTrue(model.isAssistantMessageRecorded(message))
        XCTAssertEqual(try store.read(), model.continuityCasebook)
    }

    func testReviewedReferenceRequiresExplicitEntryAndPinsAdviceOnlyContext() throws {
        let base = temporaryDirectory(named: "reference")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ContinuityCasebookStore(baseDirectoryURL: base)
        let model = AppModel(continuityCasebookStore: store)
        let continuityCase = try XCTUnwrap(model.selectedContinuityCase)
        let reference = try XCTUnwrap(continuityCase.references.first)
        let entry = try XCTUnwrap(reference.entries.first)

        model.prepareContinuityReferenceForAssist(
            referenceID: reference.id,
            entryID: entry.id
        )

        let fragment = try XCTUnwrap(model.preparedAssistantContextBundle?.fragments.last)
        XCTAssertEqual(fragment.kind, .reviewedReference)
        XCTAssertEqual(fragment.content, entry.content)
        XCTAssertEqual(fragment.contentSHA256, entry.contentSHA256)
        XCTAssertTrue(model.isAIContextPreviewPresented)
        XCTAssertTrue(model.isAssistantVisible)
        XCTAssertTrue(model.assistantInput.contains("advice-only"))
    }

    func testCasebookWorkspaceRendersAtNativeWorkbenchSize() throws {
        let base = temporaryDirectory(named: "render")
        defer { try? FileManager.default.removeItem(at: base) }
        let model = AppModel(continuityCasebookStore: ContinuityCasebookStore(baseDirectoryURL: base))
        let content = ContinuityCasebookView()
            .environment(model)
            .frame(width: 1_360, height: 840)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_360, height: 840)

        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_360)
        XCTAssertEqual(image.height, 840)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_CASEBOOK"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_360, height: 840)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(
                host.bitmapImageRepForCachingDisplay(in: host.bounds)
            )
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(
                representation.representation(using: .png, properties: [:])
            )
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-continuity-casebook-native.png"),
                options: .atomic
            )
        }
    }

    private func temporaryDirectory(named suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-casebook-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    }
}
