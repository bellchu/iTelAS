import Foundation

enum AIChatStreamEvent: Equatable, Sendable {
    case delta(String)
    case completed(finishReason: String?)
}

enum AIChatStreamError: Error, Equatable, LocalizedError {
    case lineTooLarge
    case eventTooLarge
    case responseTooLarge
    case malformedEvent
    case incompleteResponse

    var errorDescription: String? {
        switch self {
        case .lineTooLarge:
            "The AI provider sent an oversized streaming line."
        case .eventTooLarge:
            "The AI provider sent an oversized streaming event."
        case .responseTooLarge:
            "The AI provider response exceeded the local safety limit."
        case .malformedEvent:
            "The AI provider sent a malformed streaming event."
        case .incompleteResponse:
            "The AI provider closed the response before it completed."
        }
    }
}

struct AIChatStreamParser: Sendable {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let refusal: String?
            }

            let index: Int?
            let delta: Delta
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case index
                case delta
                case finishReason = "finish_reason"
            }
        }

        let choices: [Choice]
    }

    static let defaultMaxLineBytes = 128 * 1_024
    static let defaultMaxEventBytes = 128 * 1_024
    static let defaultMaxResponseBytes = 2 * 1_024 * 1_024

    private let maxLineBytes: Int
    private let maxEventBytes: Int
    private let maxResponseBytes: Int
    private var lineBuffer = Data()
    private var eventData = Data()
    private var hasEventDataField = false
    private var responseByteCount = 0
    private var finishReason: String?
    private var receivedDone = false
    private var emittedCompletion = false

    init(
        maxLineBytes: Int = Self.defaultMaxLineBytes,
        maxEventBytes: Int = Self.defaultMaxEventBytes,
        maxResponseBytes: Int = Self.defaultMaxResponseBytes
    ) {
        precondition(maxLineBytes > 0 && maxEventBytes > 0 && maxResponseBytes > 0)
        self.maxLineBytes = maxLineBytes
        self.maxEventBytes = maxEventBytes
        self.maxResponseBytes = maxResponseBytes
    }

    mutating func consume(_ data: Data) throws -> [AIChatStreamEvent] {
        var events: [AIChatStreamEvent] = []
        for byte in data {
            events.append(contentsOf: try consume(byte))
        }
        return events
    }

    mutating func consume(_ byte: UInt8) throws -> [AIChatStreamEvent] {
        guard !receivedDone else { return [] }
        if byte == 0x0A {
            var line = lineBuffer
            lineBuffer.removeAll(keepingCapacity: true)
            if line.last == 0x0D {
                line.removeLast()
            }
            return try consumeLine(line)
        }

        lineBuffer.append(byte)
        guard lineBuffer.count <= maxLineBytes else {
            throw AIChatStreamError.lineTooLarge
        }
        return []
    }

    mutating func finish() throws -> [AIChatStreamEvent] {
        var events: [AIChatStreamEvent] = []
        if !lineBuffer.isEmpty {
            var line = lineBuffer
            lineBuffer.removeAll(keepingCapacity: true)
            if line.last == 0x0D {
                line.removeLast()
            }
            events.append(contentsOf: try consumeLine(line))
        }
        if hasEventDataField {
            events.append(contentsOf: try dispatchEvent())
        }
        guard receivedDone || finishReason != nil else {
            throw AIChatStreamError.incompleteResponse
        }
        if !emittedCompletion {
            emittedCompletion = true
            events.append(.completed(finishReason: finishReason))
        }
        return events
    }

    private mutating func consumeLine(_ line: Data) throws -> [AIChatStreamEvent] {
        if line.isEmpty {
            return try dispatchEvent()
        }
        if line.first == 0x3A {
            return []
        }

        let dataPrefix = Data("data:".utf8)
        let bareDataField = Data("data".utf8)
        guard line.starts(with: dataPrefix) || line == bareDataField else {
            return []
        }

        var payload = line.dropFirst(line == bareDataField ? bareDataField.count : dataPrefix.count)
        if payload.first == 0x20 {
            payload = payload.dropFirst()
        }
        let separatorBytes = hasEventDataField ? 1 : 0
        guard eventData.count + separatorBytes + payload.count <= maxEventBytes else {
            throw AIChatStreamError.eventTooLarge
        }
        if hasEventDataField {
            eventData.append(0x0A)
        }
        eventData.append(contentsOf: payload)
        hasEventDataField = true
        return []
    }

    private mutating func dispatchEvent() throws -> [AIChatStreamEvent] {
        guard hasEventDataField else { return [] }
        let payload = eventData
        eventData.removeAll(keepingCapacity: true)
        hasEventDataField = false
        guard !payload.isEmpty else { return [] }

        guard let text = String(data: payload, encoding: .utf8) else {
            throw AIChatStreamError.malformedEvent
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            receivedDone = true
            emittedCompletion = true
            return [.completed(finishReason: finishReason)]
        }

        let chunk: Chunk
        do {
            chunk = try JSONDecoder().decode(Chunk.self, from: payload)
        } catch {
            throw AIChatStreamError.malformedEvent
        }

        var events: [AIChatStreamEvent] = []
        for choice in chunk.choices where (choice.index ?? 0) == 0 {
            if let reason = choice.finishReason, !reason.isEmpty {
                finishReason = reason
            }
            for segment in [choice.delta.content, choice.delta.refusal].compactMap({ $0 }) where !segment.isEmpty {
                let byteCount = segment.utf8.count
                guard responseByteCount + byteCount <= maxResponseBytes else {
                    throw AIChatStreamError.responseTooLarge
                }
                responseByteCount += byteCount
                events.append(.delta(segment))
            }
        }
        return events
    }
}
