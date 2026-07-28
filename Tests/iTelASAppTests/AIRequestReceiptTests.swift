import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class AIRequestReceiptTests: XCTestCase {
    func testSequentialAnswersRetainDistinctImmutableReceipts() throws {
        let firstMessageID = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
        let secondMessageID = UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!
        let first = try makeReceipt(
            question: "Explain CPF2105.",
            sourceText: "MSGID CPF2105\nLIBRARY ARLIB"
        )
        let second = try makeReceipt(
            question: "Check the active job.",
            sourceText: "JOB QPADEV0002\nSTATUS ACTIVE"
        )
        var store = AssistantRequestReceiptStore()

        store.record(first, for: firstMessageID)
        store.record(second, for: secondMessageID)

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.receipt(for: firstMessageID), first)
        XCTAssertEqual(store.receipt(for: secondMessageID), second)
        XCTAssertNotEqual(
            store.receipt(for: firstMessageID)?.bundleFingerprint,
            store.receipt(for: secondMessageID)?.bundleFingerprint
        )
    }

    func testReceiptStoreDropsOnlyTheOldestEntryAtItsBound() throws {
        let messageIDs = (0..<3).map { _ in UUID() }
        var store = AssistantRequestReceiptStore(maximumCount: 2)
        for (index, messageID) in messageIDs.enumerated() {
            store.record(
                try makeReceipt(
                    question: "Question \(index)",
                    sourceText: "Evidence \(index)"
                ),
                for: messageID
            )
        }

        XCTAssertEqual(store.count, 2)
        XCTAssertNil(store.receipt(for: messageIDs[0]))
        XCTAssertEqual(store.receipt(for: messageIDs[1])?.question, "Question 1")
        XCTAssertEqual(store.receipt(for: messageIDs[2])?.question, "Question 2")

        let model = AppModel()
        var answers: [AssistantMessage] = []
        for index in 0...AssistantRequestReceiptStore.standardMaximumCount {
            let receipt = try makeReceipt(
                question: "Bounded question \(index)",
                sourceText: "Bounded evidence \(index)"
            )
            let answer = AssistantMessage(
                role: .assistant,
                content: "Bounded answer \(index)",
                provenance: makeProvenance(for: receipt)
            )
            answers.append(answer)
            model.assistantRequestReceipts.record(receipt, for: answer.id)
        }
        model.assistantMessages = answers

        XCTAssertTrue(model.isAssistantRequestReceiptExpired(for: answers[0]))
        XCTAssertNil(model.assistantRequestReceipt(for: answers[0]))
        XCTAssertFalse(model.isAssistantRequestReceiptExpired(for: answers[1]))
        XCTAssertNotNil(model.assistantRequestReceipt(for: try XCTUnwrap(answers.last)))
    }

    func testStoppedAnswerCanOpenItsReceiptAndNewChatClearsIt() throws {
        let model = AppModel()
        let message = AssistantMessage(
            role: .assistant,
            content: "Response stopped after the read-only checks.",
            completionState: .stopped
        )
        let receipt = try makeReceipt(
            question: "Give read-only checks.",
            sourceText: "CURRENT SCREEN\nPASSWORD: hidden-value"
        )
        model.assistantMessages = [message]
        model.assistantRequestReceipts.record(receipt, for: message.id)

        model.presentAssistantRequestReceipt(for: message)

        XCTAssertEqual(model.assistantRequestReceipt(for: message), receipt)
        XCTAssertEqual(model.selectedAssistantRequestReceipt, receipt)
        XCTAssertTrue(receipt.contextBundle?.fragments.first?.wasRedacted == true)

        model.clearAssistantConversation()

        XCTAssertTrue(model.assistantMessages.isEmpty)
        XCTAssertEqual(model.assistantRequestReceipts.count, 0)
        XCTAssertNil(model.selectedAssistantRequestReceipt)
    }

    func testImmutableReceiptViewRendersAtNativeSheetSize() throws {
        let model = AppModel()
        let receipt = try makeReceipt(
            question: "Explain CPF2105 and list read-only checks before changing the library list.",
            sourceText: "DISPLAY Work with Objects\nMSGID CPF2105\nLIBRARY PASSWORD: hidden-value"
        )
        let content = AIContextPreviewView(receipt: receipt)
            .environment(model)
            .frame(width: 1_260, height: 790)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_260, height: 790)

        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_260)
        XCTAssertEqual(image.height, 790)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_AI_RECEIPT"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_260, height: 790)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-assistant-request-receipt-native.png"),
                options: .atomic
            )
        }
    }

    func testAnswerReceiptActionRendersAtAssistantPanelWidth() throws {
        let model = AppModel()
        let answer = AssistantMessage(
            role: .assistant,
            content: "CPF2105 means the requested object was not found. Capture the qualified name and job before changing the library list.",
            commandRisk: .readOnly,
            provenance: AssistantResponseProvenance(
                question: "Explain CPF2105.",
                endpointHost: "provider.example",
                model: "configured-model",
                contextFingerprint: "receipt-fingerprint",
                contextItemCount: 1,
                requestedAt: Date(timeIntervalSince1970: 1_785_000_000)
            )
        )
        let receipt = try makeReceipt(
            question: "Explain CPF2105.",
            sourceText: "MSGID CPF2105\nLIBRARY ARLIB"
        )
        let expiredAnswer = AssistantMessage(
            role: .assistant,
            content: "An older answer remains readable after its bounded receipt rolls off.",
            provenance: makeProvenance(for: receipt)
        )
        model.assistantMessages = [
            .init(role: .user, content: "Explain CPF2105."),
            expiredAnswer,
            .init(role: .user, content: "Give the smallest safe next check."),
            answer
        ]
        model.assistantRequestReceipts.record(receipt, for: answer.id)
        let content = AIAssistantView()
            .environment(model)
            .frame(width: 366, height: 790)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 366, height: 790)

        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 366)
        XCTAssertEqual(image.height, 790)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_AI_RECEIPT"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 366, height: 790)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-assistant-receipt-action-native.png"),
                options: .atomic
            )
        }
    }

    private func makeReceipt(question: String, sourceText: String) throws -> AIContextReceipt {
        let fragment = try AIContextFragment(
            kind: .terminalScreen,
            documentName: "DEV400",
            language: "TN5250",
            sourceText: sourceText
        )
        return AIContextReceipt(
            createdAt: Date(timeIntervalSince1970: 1_785_000_000),
            endpointHost: "provider.example",
            model: "configured-model",
            conversationTurns: 2,
            question: question,
            screenRows: 24,
            screenColumns: 80,
            contextBundle: try AIContextBundle(fragments: [fragment])
        )
    }

    private func makeProvenance(for receipt: AIContextReceipt) -> AssistantResponseProvenance {
        AssistantResponseProvenance(
            question: receipt.question ?? "",
            endpointHost: receipt.endpointHost,
            model: receipt.model,
            contextFingerprint: receipt.bundleFingerprint,
            contextItemCount: receipt.contextBundle?.fragments.count ?? 0,
            requestedAt: receipt.createdAt
        )
    }
}
