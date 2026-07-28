import Foundation
import XCTest
@testable import iTelAS

final class AIServiceStreamingTests: XCTestCase {
    @MainActor
    func testStreamingRequestUsesSSEAndKeepsAPIKeyOutOfBody() async throws {
        let capture = RequestCapture()
        StubURLProtocol.store.install { request in
            capture.record(request)
            let body =
                "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Read\"},\"finish_reason\":null}]}\n\n" +
                "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\" only\"},\"finish_reason\":\"stop\"}]}\n\n" +
                "data: [DONE]\n\n" +
                "data: this must never be parsed\n\n"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }
        defer { StubURLProtocol.store.clear() }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        let service = AIService(session: URLSession(configuration: sessionConfiguration))
        var configuration = AIConfiguration()
        configuration.isEnabled = true
        configuration.endpoint = "https://provider.invalid/v1/chat/completions"
        configuration.model = "test-model"
        var deltas: [String] = []

        let answer = try await service.askStreaming(
            question: "Give read-only checks",
            conversation: [
                .init(role: .user, content: "Question with a stopped answer"),
                .init(role: .assistant, content: "Incomplete command", completionState: .stopped),
                .init(role: .user, content: "Completed prior question"),
                .init(role: .assistant, content: "Completed prior answer")
            ],
            contextBundle: nil,
            configuration: configuration,
            apiKey: "test-secret",
            onDelta: { deltas.append($0) }
        )

        XCTAssertEqual(answer, "Read only")
        XCTAssertEqual(deltas, ["Read", " only"])
        let request = try XCTUnwrap(capture.value)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
        let bodyData = try XCTUnwrap(capture.bodyData)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["model"] as? String, "test-model")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let contents = messages.compactMap { $0["content"] as? String }
        XCTAssertTrue(contents.contains("Completed prior question"))
        XCTAssertTrue(contents.contains("Completed prior answer"))
        XCTAssertFalse(contents.contains("Question with a stopped answer"))
        XCTAssertFalse(contents.contains("Incomplete command"))
        XCTAssertFalse(String(decoding: bodyData, as: UTF8.self).contains("test-secret"))
    }
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: URLRequest?
    private var storedBodyData: Data?

    var value: URLRequest? {
        lock.withLock { storedValue }
    }

    var bodyData: Data? {
        lock.withLock { storedBodyData }
    }

    func record(_ request: URLRequest) {
        let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        lock.withLock {
            storedValue = request
            storedBodyData = body
        }
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class URLProtocolStore: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private let lock = NSLock()
    private var handler: Handler?

    func install(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    func clear() {
        lock.withLock { handler = nil }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let handler = lock.withLock { self.handler }
        return try XCTUnwrap(handler)(request)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = URLProtocolStore()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.store.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
