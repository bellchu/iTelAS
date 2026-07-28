import Foundation
import iTelASCore

enum AIContextMode: String, Codable, CaseIterable, Identifiable {
    case none
    case visibleScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No automatic context"
        case .visibleScreen: "Redacted visible screen"
        }
    }
}

struct AIConfiguration: Codable, Equatable {
    var isEnabled = false
    var endpoint = "https://api.openai.com/v1/chat/completions"
    var model = ""
    var contextMode: AIContextMode = .none

    var validationErrors: [String] {
        guard isEnabled else { return [] }
        var errors: [String] = []
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Model ID is required when AI Assist is enabled.")
        }
        guard let url = URL(string: endpoint), let host = url.host, !host.isEmpty else {
            errors.append("Enter a valid provider endpoint URL.")
            return errors
        }
        if url.user != nil || url.password != nil {
            errors.append("Do not embed credentials in the provider URL.")
        }
        let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
        if url.scheme?.lowercased() != "https" && !(url.scheme?.lowercased() == "http" && isLocal) {
            errors.append("Remote provider endpoints must use HTTPS.")
        }
        return errors
    }
}

enum AIConfigurationError: Error, LocalizedError {
    case invalid([String])

    var errorDescription: String? {
        switch self {
        case .invalid(let errors): errors.joined(separator: " ")
        }
    }
}

struct AssistantMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    enum CompletionState: Equatable {
        case complete
        case stopped
        case interrupted
    }

    let id: UUID
    let role: Role
    let content: String
    let commandRisk: CommandRisk?
    let completionState: CompletionState
    let provenance: AssistantResponseProvenance?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        commandRisk: CommandRisk? = nil,
        completionState: CompletionState = .complete,
        provenance: AssistantResponseProvenance? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.commandRisk = commandRisk
        self.completionState = completionState
        self.provenance = provenance
    }
}

struct AssistantResponseProvenance: Equatable {
    let question: String
    let endpointHost: String
    let model: String
    let contextFingerprint: String?
    let contextItemCount: Int
    let requestedAt: Date
}

enum AIAssistantResponsePhase: Equatable {
    case idle
    case connecting
    case streaming
    case reviewing

    var channelLabel: String {
        switch self {
        case .idle: "RESPONSE CHANNEL / CLOSED"
        case .connecting: "RESPONSE CHANNEL / OPENING"
        case .streaming: "RESPONSE CHANNEL / OPEN"
        case .reviewing: "PROPOSAL CHANNEL / VALIDATING"
        }
    }
}

enum AIReviewContextScope: String, CaseIterable, Identifiable {
    case selection
    case wholeDraft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selection: "Selection"
        case .wholeDraft: "Whole draft"
        }
    }
}

struct AIReviewDraft: Identifiable, Equatable {
    let id: UUID
    let target: AIProposalTarget
    let documentName: String
    let language: String
    let sourceText: String
    let selection: AITextSelection?
    var scope: AIReviewContextScope
    var question: String
    var includeTerminalScreen: Bool
    var terminalContextText: String?
    var terminalDocumentName: String?

    init(
        id: UUID = UUID(),
        target: AIProposalTarget,
        documentName: String,
        language: String,
        sourceText: String,
        selection: AITextSelection?,
        scope: AIReviewContextScope,
        question: String,
        includeTerminalScreen: Bool = false,
        terminalContextText: String? = nil,
        terminalDocumentName: String? = nil
    ) {
        self.id = id
        self.target = target
        self.documentName = documentName
        self.language = language
        self.sourceText = sourceText
        self.selection = selection
        self.scope = scope
        self.question = question
        self.includeTerminalScreen = includeTerminalScreen
        self.terminalContextText = terminalContextText
        self.terminalDocumentName = terminalDocumentName
    }

    var selectedScopeIsAvailable: Bool { selection != nil }

    var contextKind: AIContextKind {
        switch (target, scope) {
        case (.sourceDraft, .selection): .sourceSelection
        case (.sourceDraft, .wholeDraft): .sourceDraft
        case (.sqlDraft, .selection): .sqlSelection
        case (.sqlDraft, .wholeDraft): .sqlDraft
        }
    }

    var proposalSelection: AITextSelection? {
        scope == .selection ? selection : nil
    }
}

struct AIContextReceipt: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let endpointHost: String
    let model: String
    let conversationTurns: Int
    let question: String?
    let screenRows: Int?
    let screenColumns: Int?
    let contextBundle: AIContextBundle?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        endpointHost: String,
        model: String,
        conversationTurns: Int,
        question: String? = nil,
        screenRows: Int? = nil,
        screenColumns: Int? = nil,
        contextBundle: AIContextBundle? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.endpointHost = endpointHost
        self.model = model
        self.conversationTurns = conversationTurns
        self.question = question
        self.screenRows = screenRows
        self.screenColumns = screenColumns
        self.contextBundle = contextBundle
    }

    var redactedScreen: String? {
        contextBundle?.fragments.first(where: { $0.kind == .terminalScreen })?.content
    }

    var includesScreen: Bool { redactedScreen != nil }

    var totalContextBytes: Int { contextBundle?.totalUTF8Bytes ?? 0 }

    var bundleFingerprint: String? { contextBundle?.fingerprint }
}

struct AssistantRequestReceiptStore: Equatable {
    static let standardMaximumCount = 32

    private let maximumCount: Int
    private var messageOrder: [UUID] = []
    private var receiptsByMessageID: [UUID: AIContextReceipt] = [:]

    init(maximumCount: Int = Self.standardMaximumCount) {
        self.maximumCount = max(1, maximumCount)
    }

    var count: Int { receiptsByMessageID.count }

    func receipt(for messageID: UUID) -> AIContextReceipt? {
        receiptsByMessageID[messageID]
    }

    mutating func record(_ receipt: AIContextReceipt, for messageID: UUID) {
        if receiptsByMessageID[messageID] == nil {
            messageOrder.append(messageID)
        }
        receiptsByMessageID[messageID] = receipt

        let overflow = messageOrder.count - maximumCount
        guard overflow > 0 else { return }
        for expiredID in messageOrder.prefix(overflow) {
            receiptsByMessageID.removeValue(forKey: expiredID)
        }
        messageOrder.removeFirst(overflow)
    }

    mutating func removeAll() {
        messageOrder.removeAll(keepingCapacity: false)
        receiptsByMessageID.removeAll(keepingCapacity: false)
    }
}
