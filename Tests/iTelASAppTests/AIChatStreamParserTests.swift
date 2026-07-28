import Foundation
import XCTest
@testable import iTelAS

final class AIChatStreamParserTests: XCTestCase {
    func testFragmentedCRLFStreamEmitsTextAndCompletion() throws {
        let source =
            "data: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\r\n\r\n" +
            "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"CPF\"},\"finish_reason\":null}]}\r\n\r\n" +
            "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"2105\"},\"finish_reason\":\"stop\"}]}\r\n\r\n" +
            "data: [DONE]\r\n\r\n"
        var parser = AIChatStreamParser()
        let events = try consumeFragmented(Data(source.utf8), parser: &parser)

        XCTAssertEqual(events, [
            .delta("CPF"),
            .delta("2105"),
            .completed(finishReason: "stop")
        ])
        XCTAssertTrue(try parser.finish().isEmpty)
    }

    func testCommentsMetadataAndMultilineDataAreHandledAsSSE() throws {
        let source = """
        : provider heartbeat
        event: message
        id: 42
        data: {"choices":[
        data: {"index":0,"delta":{"content":"read only"},"finish_reason":"stop"}
        data: ]}

        """
        var parser = AIChatStreamParser()
        var events = try parser.consume(Data(source.utf8))
        events.append(contentsOf: try parser.finish())

        XCTAssertEqual(events, [
            .delta("read only"),
            .completed(finishReason: "stop")
        ])
    }

    func testRefusalTextIsSurfacedWithoutAcceptingOtherChoices() throws {
        let source = """
        data: {"choices":[{"index":1,"delta":{"content":"ignore"},"finish_reason":null},{"index":0,"delta":{"refusal":"I cannot help with that."},"finish_reason":"stop"}]}

        data: [DONE]

        """
        var parser = AIChatStreamParser()
        var events = try parser.consume(Data(source.utf8))
        events.append(contentsOf: try parser.finish())

        XCTAssertEqual(events, [
            .delta("I cannot help with that."),
            .completed(finishReason: "stop")
        ])
    }

    func testMalformedJSONFailsClosed() throws {
        var parser = AIChatStreamParser()
        XCTAssertThrowsError(try parser.consume(Data("data: {not-json}\n\n".utf8))) { error in
            XCTAssertEqual(error as? AIChatStreamError, .malformedEvent)
        }
    }

    func testIncompleteResponseFailsWithoutDoneOrFinishReason() throws {
        let source = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}\n\n"
        var parser = AIChatStreamParser()
        XCTAssertEqual(try parser.consume(Data(source.utf8)), [.delta("partial")])
        XCTAssertThrowsError(try parser.finish()) { error in
            XCTAssertEqual(error as? AIChatStreamError, .incompleteResponse)
        }
    }

    func testLineEventAndResponseLimitsAreIndependent() throws {
        var lineParser = AIChatStreamParser(maxLineBytes: 8)
        XCTAssertThrowsError(try lineParser.consume(Data("data: 123".utf8))) { error in
            XCTAssertEqual(error as? AIChatStreamError, .lineTooLarge)
        }

        var eventParser = AIChatStreamParser(maxLineBytes: 64, maxEventBytes: 8)
        XCTAssertThrowsError(try eventParser.consume(Data("data: 12345\ndata: 6789\n".utf8))) { error in
            XCTAssertEqual(error as? AIChatStreamError, .eventTooLarge)
        }

        let responseSource = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"12345\"},\"finish_reason\":\"stop\"}]}\n\n"
        var responseParser = AIChatStreamParser(maxResponseBytes: 4)
        XCTAssertThrowsError(try responseParser.consume(Data(responseSource.utf8))) { error in
            XCTAssertEqual(error as? AIChatStreamError, .responseTooLarge)
        }
    }

    func testBytesAfterDoneCannotBecomeAssistantOutput() throws {
        let source = """
        data: {"choices":[{"index":0,"delta":{"content":"safe"},"finish_reason":"stop"}]}

        data: [DONE]

        data: {"choices":[{"index":0,"delta":{"content":"ignored"},"finish_reason":null}]}

        """
        var parser = AIChatStreamParser()
        var events = try parser.consume(Data(source.utf8))
        events.append(contentsOf: try parser.finish())

        XCTAssertEqual(events, [
            .delta("safe"),
            .completed(finishReason: "stop")
        ])
    }

    private func consumeFragmented(
        _ data: Data,
        parser: inout AIChatStreamParser
    ) throws -> [AIChatStreamEvent] {
        let chunkSizes = [1, 2, 5, 3, 11, 7]
        var offset = 0
        var chunkIndex = 0
        var events: [AIChatStreamEvent] = []
        while offset < data.count {
            let size = min(chunkSizes[chunkIndex % chunkSizes.count], data.count - offset)
            events.append(contentsOf: try parser.consume(data.subdata(in: offset..<(offset + size))))
            offset += size
            chunkIndex += 1
        }
        return events
    }
}
