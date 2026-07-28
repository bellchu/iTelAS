import CryptoKit
import Foundation

public struct AIContextLimits: Equatable, Sendable {
    public var maximumFragmentUTF8Bytes: Int
    public var maximumBundleUTF8Bytes: Int
    public var maximumFragments: Int
    public var maximumProposalUTF8Bytes: Int
    public var maximumResponseUTF8Bytes: Int

    public init(
        maximumFragmentUTF8Bytes: Int = 32_768,
        maximumBundleUTF8Bytes: Int = 48_000,
        maximumFragments: Int = 8,
        maximumProposalUTF8Bytes: Int = 65_536,
        maximumResponseUTF8Bytes: Int = 1_000_000
    ) {
        self.maximumFragmentUTF8Bytes = maximumFragmentUTF8Bytes
        self.maximumBundleUTF8Bytes = maximumBundleUTF8Bytes
        self.maximumFragments = maximumFragments
        self.maximumProposalUTF8Bytes = maximumProposalUTF8Bytes
        self.maximumResponseUTF8Bytes = maximumResponseUTF8Bytes
    }

    public static let standard = AIContextLimits()
}

public enum AIContextError: Error, LocalizedError, Equatable {
    case emptyContext
    case emptySelection
    case invalidSelection
    case invalidMetadata
    case unexpectedSelection
    case selectionRequired
    case containsNullByte
    case fragmentTooLarge(maximum: Int)
    case bundleTooLarge(maximum: Int)
    case tooManyFragments(maximum: Int)
    case duplicateKind(AIContextKind)

    public var errorDescription: String? {
        switch self {
        case .emptyContext: "The selected Assist context is empty."
        case .emptySelection: "Select at least one character or share the whole draft."
        case .invalidSelection: "The editor selection no longer matches the current draft."
        case .invalidMetadata: "The context document name or language is invalid."
        case .unexpectedSelection: "Whole-draft and terminal context cannot carry a selection range."
        case .selectionRequired: "Selection context requires an explicit editor selection."
        case .containsNullByte: "Binary or NUL-containing text cannot be shared with Assist."
        case .fragmentTooLarge(let maximum): "One context item exceeds the \(maximum)-byte limit."
        case .bundleTooLarge(let maximum): "The selected context exceeds the \(maximum)-byte request limit."
        case .tooManyFragments(let maximum): "A request can include at most \(maximum) context items."
        case .duplicateKind(let kind): "The context contains more than one \(kind.label.lowercased()) item."
        }
    }
}

public enum AIContextKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case terminalScreen
    case sourceSelection
    case sourceDraft
    case sqlSelection
    case sqlDraft
    case sqlResult
    case compileEvidence
    case jobIncident
    case spoolOutput
    case dataTransfer
    case systemHealth
    case objectImpact
    case runbook
    case authorityReview
    case reviewedReference

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .terminalScreen: "5250 screen"
        case .sourceSelection: "Source selection"
        case .sourceDraft: "Source draft"
        case .sqlSelection: "SQL selection"
        case .sqlDraft: "SQL draft"
        case .sqlResult: "Db2 result schema"
        case .compileEvidence: "Compile evidence"
        case .jobIncident: "Job incident"
        case .spoolOutput: "Spooled output"
        case .dataTransfer: "Data transfer"
        case .systemHealth: "System health"
        case .objectImpact: "Object impact"
        case .runbook: "Runbook review"
        case .authorityReview: "Authority review"
        case .reviewedReference: "Reviewed reference"
        }
    }

    public var requiresSelection: Bool {
        self == .sourceSelection || self == .sqlSelection
    }
}

public struct AITextSelection: Codable, Equatable, Sendable {
    public let locationUTF16: Int
    public let lengthUTF16: Int

    public init(locationUTF16: Int, lengthUTF16: Int) {
        self.locationUTF16 = locationUTF16
        self.lengthUTF16 = lengthUTF16
    }

    public func stringRange(in text: String) throws -> Range<String.Index> {
        guard locationUTF16 >= 0, lengthUTF16 > 0 else {
            throw lengthUTF16 == 0 ? AIContextError.emptySelection : AIContextError.invalidSelection
        }
        let utf16Count = text.utf16.count
        guard locationUTF16 <= utf16Count,
              lengthUTF16 <= utf16Count - locationUTF16 else {
            throw AIContextError.invalidSelection
        }
        let utf16 = text.utf16
        let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: locationUTF16)
        let upperUTF16 = utf16.index(lowerUTF16, offsetBy: lengthUTF16)
        guard let lower = String.Index(lowerUTF16, within: text),
              let upper = String.Index(upperUTF16, within: text) else {
            throw AIContextError.invalidSelection
        }
        return lower..<upper
    }

    public func selectedText(in text: String) throws -> String {
        String(text[try stringRange(in: text)])
    }
}

public struct AIContextFragment: Encodable, Equatable, Identifiable, Sendable {
    public var id: AIContextKind { kind }
    public let kind: AIContextKind
    public let documentName: String
    public let language: String
    public let content: String
    public let selection: AITextSelection?
    public let firstLine: Int?
    public let lastLine: Int?
    public let baselineSHA256: String
    public let contentSHA256: String
    public let utf8ByteCount: Int
    public let wasRedacted: Bool

    public init(
        kind: AIContextKind,
        documentName: String,
        language: String,
        sourceText: String,
        selection: AITextSelection? = nil,
        redactor: AIContextRedactor = AIContextRedactor(),
        limits: AIContextLimits = .standard
    ) throws {
        let normalizedName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidMetadata(normalizedName), Self.isValidMetadata(normalizedLanguage) else {
            throw AIContextError.invalidMetadata
        }
        guard !sourceText.contains("\0") else { throw AIContextError.containsNullByte }
        if kind.requiresSelection, selection == nil { throw AIContextError.selectionRequired }
        if !kind.requiresSelection, selection != nil { throw AIContextError.unexpectedSelection }

        let rawContent: String
        let firstLine: Int?
        let lastLine: Int?
        if let selection {
            let range = try selection.stringRange(in: sourceText)
            rawContent = String(sourceText[range])
            let prefix = sourceText[..<range.lowerBound]
            let start = prefix.reduce(into: 1) { line, character in
                if character == "\n" { line += 1 }
            }
            firstLine = start
            lastLine = start + rawContent.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
        } else {
            rawContent = sourceText
            firstLine = nil
            lastLine = nil
        }

        guard !rawContent.isEmpty else { throw AIContextError.emptyContext }
        let redactedContent = redactor.redact(text: rawContent)
        guard !redactedContent.contains("\0") else { throw AIContextError.containsNullByte }
        let byteCount = redactedContent.lengthOfBytes(using: .utf8)
        guard byteCount <= limits.maximumFragmentUTF8Bytes else {
            throw AIContextError.fragmentTooLarge(maximum: limits.maximumFragmentUTF8Bytes)
        }

        self.kind = kind
        self.documentName = normalizedName
        self.language = normalizedLanguage
        content = redactedContent
        self.selection = selection
        self.firstLine = firstLine
        self.lastLine = lastLine
        baselineSHA256 = AIContentFingerprint.sha256(sourceText)
        contentSHA256 = AIContentFingerprint.sha256(redactedContent)
        utf8ByteCount = byteCount
        wasRedacted = redactedContent != rawContent
    }

    private static func isValidMetadata(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 256
            && value.unicodeScalars.allSatisfy { scalar in
                !CharacterSet.controlCharacters.contains(scalar)
            }
    }
}

public struct AIContextBundle: Equatable, Sendable {
    public let fragments: [AIContextFragment]
    public let totalUTF8Bytes: Int
    public let fingerprint: String

    public init(
        fragments: [AIContextFragment],
        limits: AIContextLimits = .standard
    ) throws {
        guard !fragments.isEmpty else { throw AIContextError.emptyContext }
        guard fragments.count <= limits.maximumFragments else {
            throw AIContextError.tooManyFragments(maximum: limits.maximumFragments)
        }
        var seen = Set<AIContextKind>()
        for fragment in fragments where !seen.insert(fragment.kind).inserted {
            throw AIContextError.duplicateKind(fragment.kind)
        }
        let total = fragments.reduce(into: 0) { $0 += $1.utf8ByteCount }
        guard total <= limits.maximumBundleUTF8Bytes else {
            throw AIContextError.bundleTooLarge(maximum: limits.maximumBundleUTF8Bytes)
        }
        self.fragments = fragments
        totalUTF8Bytes = total
        fingerprint = AIContentFingerprint.sha256(Self.canonicalBytes(for: fragments))
    }

    public func providerEnvelope() throws -> String {
        struct Envelope: Encodable {
            let version: Int
            let fragments: [AIContextFragment]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Envelope(version: 1, fragments: fragments))
        guard var json = String(data: data, encoding: .utf8) else {
            throw AIContextError.emptyContext
        }
        json = json
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
        return json
    }

    private static func canonicalBytes(for fragments: [AIContextFragment]) -> String {
        fragments
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
            .map { fragment in
                [
                    fragment.kind.rawValue,
                    fragment.documentName,
                    fragment.language,
                    fragment.selection.map {
                        "\($0.locationUTF16):\($0.lengthUTF16)"
                    } ?? "none",
                    fragment.baselineSHA256,
                    fragment.contentSHA256,
                    String(fragment.utf8ByteCount),
                    fragment.wasRedacted ? "redacted" : "verbatim"
                ]
                .map { "\($0.utf8.count):\($0)" }
                .joined(separator: "|")
            }
            .joined(separator: "\n")
    }
}

public enum AIProposalTarget: String, Codable, CaseIterable, Sendable {
    case sourceDraft
    case sqlDraft

    public var label: String {
        switch self {
        case .sourceDraft: "Local source draft"
        case .sqlDraft: "Local SQL draft"
        }
    }
}

public struct AIProposalContract: Equatable, Sendable {
    public let target: AIProposalTarget
    public let documentName: String
    public let baselineSHA256: String
    public let selection: AITextSelection?

    public init(
        target: AIProposalTarget,
        documentName: String,
        baselineSHA256: String,
        selection: AITextSelection?
    ) {
        self.target = target
        self.documentName = documentName
        self.baselineSHA256 = baselineSHA256
        self.selection = selection
    }

    public var providerInstruction: String {
        let selectionJSON: String
        if let selection {
            selectionJSON = "{\"locationUTF16\":\(selection.locationUTF16),\"lengthUTF16\":\(selection.lengthUTF16)}"
        } else {
            selectionJSON = "null"
        }
        return """
        If and only if a concrete local edit is useful, append exactly one proposal block after the explanation:
        <itelas-proposal>
        {"version":1,"target":"\(target.rawValue)","documentName":"\(Self.escapeJSONString(documentName))","baselineSHA256":"\(baselineSHA256)","selection":\(selectionJSON),"replacement":"replace this placeholder with the exact replacement text"}
        </itelas-proposal>
        Copy target, documentName, baselineSHA256, and selection exactly. The replacement is for the selected range when selection is present; otherwise it replaces the whole local draft. Do not emit a proposal block for advice-only answers. Never emit commands or host-write instructions as a proposal.
        """
    }

    private static func escapeJSONString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
    }
}

public enum AIProposalError: Error, LocalizedError, Equatable {
    case responseTooLarge(maximum: Int)
    case malformedEnvelope
    case unsupportedVersion
    case invalidDocument
    case invalidBaseline
    case invalidSelection
    case proposalTooLarge(maximum: Int)
    case containsNullByte
    case emptyWholeDraftReplacement
    case contractMismatch
    case documentMismatch
    case baselineMismatch

    public var errorDescription: String? {
        switch self {
        case .responseTooLarge(let maximum): "The Assist response exceeds the \(maximum)-byte review limit."
        case .malformedEnvelope: "The Assist proposal envelope is malformed or ambiguous."
        case .unsupportedVersion: "The Assist proposal uses an unsupported format version."
        case .invalidDocument: "The Assist proposal does not identify a valid reviewed document."
        case .invalidBaseline: "The Assist proposal does not identify a valid draft baseline."
        case .invalidSelection: "The Assist proposal selection is invalid."
        case .proposalTooLarge(let maximum): "The proposed replacement exceeds the \(maximum)-byte limit."
        case .containsNullByte: "Binary or NUL-containing proposal text is blocked."
        case .emptyWholeDraftReplacement: "A proposal cannot erase the entire draft."
        case .contractMismatch: "The Assist proposal changed its reviewed target, document, baseline, or selection contract."
        case .documentMismatch: "The local editor is showing a different document than the reviewed proposal."
        case .baselineMismatch: "The local draft changed after the proposal was created. Review again from the new baseline."
        }
    }
}

public struct AIEditProposal: Equatable, Sendable {
    public let target: AIProposalTarget
    public let documentName: String
    public let baselineSHA256: String
    public let selection: AITextSelection?
    public let replacement: String

    public init(
        target: AIProposalTarget,
        documentName: String,
        baselineSHA256: String,
        selection: AITextSelection?,
        replacement: String,
        limits: AIContextLimits = .standard
    ) throws {
        let normalizedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocumentName.isEmpty,
              normalizedDocumentName.utf8.count <= 256,
              normalizedDocumentName.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw AIProposalError.invalidDocument
        }
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        guard baselineSHA256.count == 64,
              baselineSHA256.unicodeScalars.allSatisfy(hex.contains) else {
            throw AIProposalError.invalidBaseline
        }
        if let selection {
            guard selection.locationUTF16 >= 0, selection.lengthUTF16 > 0 else {
                throw AIProposalError.invalidSelection
            }
        } else if replacement.isEmpty {
            throw AIProposalError.emptyWholeDraftReplacement
        }
        guard !replacement.contains("\0") else { throw AIProposalError.containsNullByte }
        guard replacement.lengthOfBytes(using: .utf8) <= limits.maximumProposalUTF8Bytes else {
            throw AIProposalError.proposalTooLarge(maximum: limits.maximumProposalUTF8Bytes)
        }
        self.target = target
        self.documentName = normalizedDocumentName
        self.baselineSHA256 = baselineSHA256
        self.selection = selection
        self.replacement = replacement
    }

    public func applying(to currentText: String, documentName: String) throws -> String {
        guard documentName == self.documentName else {
            throw AIProposalError.documentMismatch
        }
        guard AIContentFingerprint.sha256(currentText) == baselineSHA256 else {
            throw AIProposalError.baselineMismatch
        }
        guard let selection else { return replacement }
        let range: Range<String.Index>
        do {
            range = try selection.stringRange(in: currentText)
        } catch {
            throw AIProposalError.invalidSelection
        }
        var updated = currentText
        updated.replaceSubrange(range, with: replacement)
        return updated
    }
}

public struct AIParsedAssistantResponse: Equatable, Sendable {
    public let explanation: String
    public let proposal: AIEditProposal?

    public init(explanation: String, proposal: AIEditProposal?) {
        self.explanation = explanation
        self.proposal = proposal
    }
}

public struct AIProposalParser: Sendable {
    private struct WireProposal: Decodable {
        let version: Int
        let target: AIProposalTarget
        let documentName: String
        let baselineSHA256: String
        let selection: AITextSelection?
        let replacement: String
    }

    public init() {}

    public func parse(
        _ response: String,
        limits: AIContextLimits = .standard
    ) throws -> AIParsedAssistantResponse {
        guard response.lengthOfBytes(using: .utf8) <= limits.maximumResponseUTF8Bytes else {
            throw AIProposalError.responseTooLarge(maximum: limits.maximumResponseUTF8Bytes)
        }
        let opening = "<itelas-proposal>"
        let closing = "</itelas-proposal>"
        let openingCount = response.components(separatedBy: opening).count - 1
        let closingCount = response.components(separatedBy: closing).count - 1
        if openingCount == 0, closingCount == 0 {
            return AIParsedAssistantResponse(
                explanation: response.trimmingCharacters(in: .whitespacesAndNewlines),
                proposal: nil
            )
        }
        guard openingCount == 1, closingCount == 1,
              let openingRange = response.range(of: opening),
              let closingRange = response.range(of: closing),
              openingRange.upperBound <= closingRange.lowerBound else {
            throw AIProposalError.malformedEnvelope
        }

        let payload = response[openingRange.upperBound..<closingRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8),
              let wire = try? JSONDecoder().decode(WireProposal.self, from: data) else {
            throw AIProposalError.malformedEnvelope
        }
        guard wire.version == 1 else { throw AIProposalError.unsupportedVersion }
        let proposal = try AIEditProposal(
            target: wire.target,
            documentName: wire.documentName,
            baselineSHA256: wire.baselineSHA256,
            selection: wire.selection,
            replacement: wire.replacement,
            limits: limits
        )
        let explanation = String(response[..<openingRange.lowerBound])
            + String(response[closingRange.upperBound...])
        return AIParsedAssistantResponse(
            explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines),
            proposal: proposal
        )
    }
}

public enum AIContentFingerprint {
    public static func sha256(_ text: String) -> String {
        sha256(Data(text.utf8))
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
