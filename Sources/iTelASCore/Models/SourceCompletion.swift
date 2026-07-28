import Foundation

public enum SourceCompletionKind: String, CaseIterable, Codable, Sendable {
    case field
    case variable
    case dataStructure
    case procedure
    case prototype
    case parameter
    case file
    case recordFormat
    case keyword
    case builtIn
    case assistReview

    public var label: String {
        switch self {
        case .field: "Field"
        case .variable: "Variable"
        case .dataStructure: "Data structure"
        case .procedure: "Procedure"
        case .prototype: "Prototype"
        case .parameter: "Parameter"
        case .file: "File"
        case .recordFormat: "Record format"
        case .keyword: "Keyword"
        case .builtIn: "Built-in"
        case .assistReview: "Assist review"
        }
    }

    public var shortLabel: String {
        switch self {
        case .field: "FLD"
        case .variable: "VAR"
        case .dataStructure: "DS"
        case .procedure: "PROC"
        case .prototype: "PR"
        case .parameter: "PARM"
        case .file: "FILE"
        case .recordFormat: "FMT"
        case .keyword: "KEY"
        case .builtIn: "BIF"
        case .assistReview: "AI"
        }
    }
}

public enum SourceCompletionOrigin: String, Codable, Sendable {
    case currentDocument
    case workspaceIndex
    case languageCatalog
    case assistReview

    public var label: String {
        switch self {
        case .currentDocument: "Current document"
        case .workspaceIndex: "Reviewed workspace index"
        case .languageCatalog: "Language catalog"
        case .assistReview: "Reviewed Assist handoff"
        }
    }
}

public enum SourceCompletionAction: String, Codable, Sendable {
    case insertText
    case openAssistReview
}

public enum SourceCompletionStatus: String, Codable, Sendable {
    case ready
    case noMatches
    case suppressed
    case staleSnapshot
    case invalidCaret
    case analysisLimited
}

public struct SourceUTF16Range: Hashable, Codable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public var nsRange: NSRange { NSRange(location: location, length: length) }
}

public struct SourceCompletionItem: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let insertionText: String?
    public let kind: SourceCompletionKind
    public let detail: String
    public let origin: SourceCompletionOrigin
    public let sourceLine: Int?
    public let sourceSymbolID: String?
    public let sourceDocumentPath: String?
    public let action: SourceCompletionAction

    public init(
        label: String,
        insertionText: String?,
        kind: SourceCompletionKind,
        detail: String,
        origin: SourceCompletionOrigin,
        sourceLine: Int? = nil,
        sourceSymbolID: String? = nil,
        sourceDocumentPath: String? = nil,
        action: SourceCompletionAction
    ) {
        self.label = label
        self.insertionText = insertionText
        self.kind = kind
        self.detail = detail
        self.origin = origin
        self.sourceLine = sourceLine
        self.sourceSymbolID = sourceSymbolID
        self.sourceDocumentPath = sourceDocumentPath
        self.action = action
        id = [
            action.rawValue,
            kind.rawValue,
            label.uppercased(),
            insertionText?.uppercased() ?? "",
            sourceSymbolID ?? "",
            sourceDocumentPath?.uppercased() ?? ""
        ].joined(separator: ":")
    }
}

public struct SourceCompletionEdit: Equatable, Sendable {
    public let range: SourceUTF16Range
    public let replacement: String

    public init(range: SourceUTF16Range, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    public func applying(to text: String) throws -> SourceCompletionApplication {
        guard let range = Range(range.nsRange, in: text) else {
            throw SourceCompletionError.invalidReplacementRange
        }
        let updated = text.replacingCharacters(in: range, with: replacement)
        return SourceCompletionApplication(
            text: updated,
            cursorUTF16: self.range.location + replacement.utf16.count
        )
    }
}

public struct SourceCompletionApplication: Equatable, Sendable {
    public let text: String
    public let cursorUTF16: Int

    public init(text: String, cursorUTF16: Int) {
        self.text = text
        self.cursorUTF16 = cursorUTF16
    }
}

public enum SourceCompletionError: Error, Equatable, LocalizedError {
    case staleDocument
    case unknownItem
    case nonInsertAction
    case invalidReplacementRange

    public var errorDescription: String? {
        switch self {
        case .staleDocument:
            "The source changed after completion was prepared. Request completion again."
        case .unknownItem:
            "The selected completion is no longer available."
        case .nonInsertAction:
            "This completion opens a reviewed action and does not insert source text."
        case .invalidReplacementRange:
            "The completion range is no longer valid for this source text."
        }
    }
}

public struct SourceCompletionSession: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let documentFingerprint: String
    public let format: SourceFormat
    public let caretUTF16: Int
    public let replacementRange: SourceUTF16Range
    public let prefix: String
    public let qualifier: String?
    public let items: [SourceCompletionItem]
    public let status: SourceCompletionStatus
    public let wasLimited: Bool

    public init(
        documentFingerprint: String,
        format: SourceFormat,
        caretUTF16: Int,
        replacementRange: SourceUTF16Range,
        prefix: String,
        qualifier: String?,
        items: [SourceCompletionItem],
        status: SourceCompletionStatus,
        wasLimited: Bool
    ) {
        self.documentFingerprint = documentFingerprint
        self.format = format
        self.caretUTF16 = caretUTF16
        self.replacementRange = replacementRange
        self.prefix = prefix
        self.qualifier = qualifier
        self.items = items
        self.status = status
        self.wasLimited = wasLimited
        id = [
            documentFingerprint,
            String(caretUTF16),
            String(replacementRange.location),
            String(replacementRange.length),
            qualifier?.uppercased() ?? "",
            prefix.uppercased(),
            items.map(\.id).joined(separator: "|")
        ].joined(separator: ":")
    }

    public var isPresentable: Bool { status == .ready && !items.isEmpty }
    public var shortReceipt: String { String(documentFingerprint.prefix(8)).uppercased() }
    public var boundaryLabel: String { "Local completion · no host lookup" }

    public func validatedEdit(for itemID: String, in text: String) throws -> SourceCompletionEdit {
        guard SourceIntelligenceAnalyzer.fingerprint(of: text) == documentFingerprint else {
            throw SourceCompletionError.staleDocument
        }
        guard let item = items.first(where: { $0.id == itemID }) else {
            throw SourceCompletionError.unknownItem
        }
        guard item.action == .insertText, let insertionText = item.insertionText else {
            throw SourceCompletionError.nonInsertAction
        }
        guard NSMaxRange(replacementRange.nsRange) <= text.utf16.count,
              Range(replacementRange.nsRange, in: text) != nil else {
            throw SourceCompletionError.invalidReplacementRange
        }
        return SourceCompletionEdit(range: replacementRange, replacement: insertionText)
    }
}

public struct SourceCompletionLimits: Equatable, Sendable {
    public var maximumItems: Int
    public var maximumCandidates: Int
    public var maximumPrefixUTF16Units: Int

    public init(
        maximumItems: Int = 12,
        maximumCandidates: Int = 2_048,
        maximumPrefixUTF16Units: Int = 128
    ) {
        self.maximumItems = max(1, maximumItems)
        self.maximumCandidates = max(1, maximumCandidates)
        self.maximumPrefixUTF16Units = max(1, maximumPrefixUTF16Units)
    }
}

public struct SourceCompletionEngine: Sendable {
    public let limits: SourceCompletionLimits

    public init(limits: SourceCompletionLimits = SourceCompletionLimits()) {
        self.limits = limits
    }

    public func complete(
        text: String,
        format: SourceFormat,
        caretUTF16: Int,
        snapshot: SourceIntelligenceSnapshot,
        workspaceSymbols: [SourceWorkspaceCompletionSymbol] = [],
        includeAssistReview: Bool = true
    ) -> SourceCompletionSession {
        let fingerprint = SourceIntelligenceAnalyzer.fingerprint(of: text)
        let emptyRange = SourceUTF16Range(location: max(0, min(caretUTF16, text.utf16.count)), length: 0)
        guard snapshot.fingerprint == fingerprint, snapshot.format == format else {
            return session(
                fingerprint: fingerprint,
                format: format,
                caret: caretUTF16,
                replacement: emptyRange,
                status: .staleSnapshot
            )
        }
        guard !snapshot.wasLimited else {
            return session(
                fingerprint: fingerprint,
                format: format,
                caret: caretUTF16,
                replacement: emptyRange,
                status: .analysisLimited
            )
        }
        guard caretUTF16 >= 0,
              caretUTF16 <= text.utf16.count,
              Self.isValidCaret(caretUTF16, in: text) else {
            return session(
                fingerprint: fingerprint,
                format: format,
                caret: caretUTF16,
                replacement: emptyRange,
                status: .invalidCaret
            )
        }
        guard !Self.isSuppressed(caretUTF16: caretUTF16, text: text, highlights: snapshot.highlights) else {
            return session(
                fingerprint: fingerprint,
                format: format,
                caret: caretUTF16,
                replacement: emptyRange,
                status: .suppressed
            )
        }

        let context = Self.context(
            text: text,
            format: format,
            caretUTF16: caretUTF16,
            maximumPrefixUTF16Units: limits.maximumPrefixUTF16Units
        )
        guard !context.wasLimited else {
            return session(
                fingerprint: fingerprint,
                format: format,
                caret: caretUTF16,
                replacement: context.replacementRange,
                prefix: context.prefix,
                qualifier: context.qualifier,
                status: .analysisLimited,
                wasLimited: true
            )
        }

        var candidates = Self.symbolCandidates(
            symbols: snapshot.symbols,
            prefix: context.prefix,
            qualifier: context.qualifier
        )
        if context.qualifier == nil {
            candidates.append(contentsOf: Self.workspaceCandidates(
                symbols: workspaceSymbols,
                prefix: context.prefix
            ))
            candidates.append(contentsOf: Self.catalogCandidates(format: format, prefix: context.prefix))
        }
        candidates.sort(by: Self.candidatePrecedes)

        var wasLimited = candidates.count > limits.maximumCandidates
        if candidates.count > limits.maximumCandidates {
            candidates.removeSubrange(limits.maximumCandidates...)
        }

        let assistSubject = includeAssistReview
            ? Self.assistSubject(prefix: context.prefix, qualifier: context.qualifier)
            : nil
        let insertLimit = assistSubject == nil ? limits.maximumItems : max(0, limits.maximumItems - 1)
        var seenInsertions: Set<String> = []
        var items: [SourceCompletionItem] = []
        items.reserveCapacity(limits.maximumItems)
        for candidate in candidates {
            let key = candidate.item.insertionText?.uppercased() ?? candidate.item.id
            guard seenInsertions.insert(key).inserted else { continue }
            guard items.count < insertLimit else {
                wasLimited = true
                break
            }
            items.append(candidate.item)
        }

        if let subject = assistSubject,
           items.count < limits.maximumItems {
            let symbol = Self.bestAssistSymbol(subject: subject, symbols: snapshot.symbols)
            items.append(SourceCompletionItem(
                label: "Ask Assist about \(subject)",
                insertionText: nil,
                kind: .assistReview,
                detail: "Opens context review · sends nothing yet",
                origin: .assistReview,
                sourceLine: symbol?.range.startLine,
                sourceSymbolID: symbol?.id,
                action: .openAssistReview
            ))
        }

        return SourceCompletionSession(
            documentFingerprint: fingerprint,
            format: format,
            caretUTF16: caretUTF16,
            replacementRange: context.replacementRange,
            prefix: context.prefix,
            qualifier: context.qualifier,
            items: items,
            status: items.isEmpty ? .noMatches : .ready,
            wasLimited: wasLimited
        )
    }
}

private extension SourceCompletionEngine {
    struct CompletionContext {
        let replacementRange: SourceUTF16Range
        let prefix: String
        let qualifier: String?
        let wasLimited: Bool
    }

    struct Candidate {
        let score: Int
        let item: SourceCompletionItem
    }

    struct CatalogEntry {
        let label: String
        let kind: SourceCompletionKind
        let detail: String
    }

    func session(
        fingerprint: String,
        format: SourceFormat,
        caret: Int,
        replacement: SourceUTF16Range,
        prefix: String = "",
        qualifier: String? = nil,
        status: SourceCompletionStatus,
        wasLimited: Bool = false
    ) -> SourceCompletionSession {
        SourceCompletionSession(
            documentFingerprint: fingerprint,
            format: format,
            caretUTF16: caret,
            replacementRange: replacement,
            prefix: prefix,
            qualifier: qualifier,
            items: [],
            status: status,
            wasLimited: wasLimited
        )
    }

    static func context(
        text: String,
        format: SourceFormat,
        caretUTF16: Int,
        maximumPrefixUTF16Units: Int
    ) -> CompletionContext {
        let source = text as NSString
        let precedingRange = NSRange(location: 0, length: caretUTF16)
        let lastNewline = source.range(of: "\n", options: .backwards, range: precedingRange)
        let lineStart = lastNewline.location == NSNotFound ? 0 : NSMaxRange(lastNewline)
        var prefixStart = caretUTF16
        while prefixStart > lineStart,
              isIdentifierCharacter(source.character(at: prefixStart - 1), format: format) {
            prefixStart -= 1
            if caretUTF16 - prefixStart > maximumPrefixUTF16Units {
                return CompletionContext(
                    replacementRange: SourceUTF16Range(location: prefixStart, length: caretUTF16 - prefixStart),
                    prefix: "",
                    qualifier: nil,
                    wasLimited: true
                )
            }
        }

        let prefixRange = NSRange(location: prefixStart, length: caretUTF16 - prefixStart)
        let prefix = source.substring(with: prefixRange)
        var qualifier: String?
        if prefixStart > lineStart, source.character(at: prefixStart - 1) == 46 {
            let qualifierEnd = prefixStart - 1
            var qualifierStart = qualifierEnd
            while qualifierStart > lineStart,
                  isIdentifierCharacter(source.character(at: qualifierStart - 1), format: format) {
                qualifierStart -= 1
                if qualifierEnd - qualifierStart > maximumPrefixUTF16Units {
                    return CompletionContext(
                        replacementRange: SourceUTF16Range(location: prefixStart, length: prefixRange.length),
                        prefix: prefix,
                        qualifier: nil,
                        wasLimited: true
                    )
                }
            }
            if qualifierStart < qualifierEnd {
                qualifier = source.substring(with: NSRange(
                    location: qualifierStart,
                    length: qualifierEnd - qualifierStart
                ))
            }
        }
        return CompletionContext(
            replacementRange: SourceUTF16Range(location: prefixStart, length: prefixRange.length),
            prefix: prefix,
            qualifier: qualifier,
            wasLimited: false
        )
    }

    static func isSuppressed(
        caretUTF16: Int,
        text: String,
        highlights: [SourceHighlightSpan]
    ) -> Bool {
        highlights.contains { highlight in
            guard highlight.kind == .comment || highlight.kind == .stringLiteral,
                  let range = highlight.range.utf16Range(in: text) else { return false }
            return caretUTF16 > range.location && caretUTF16 <= NSMaxRange(range)
        }
    }

    static func symbolCandidates(
        symbols: [SourceSymbol],
        prefix: String,
        qualifier: String?
    ) -> [Candidate] {
        symbols.compactMap { symbol in
            let score: Int
            if let qualifier {
                if symbol.kind == .field,
                   symbol.containerName?.caseInsensitiveCompare(qualifier) == .orderedSame {
                    guard let match = matchScore(label: symbol.name, prefix: prefix) else { return nil }
                    score = match
                } else if symbol.name.caseInsensitiveCompare(qualifier) == .orderedSame {
                    score = 60
                } else if symbol.name.localizedCaseInsensitiveContains(qualifier) {
                    score = 70
                } else {
                    return nil
                }
            } else {
                guard let match = matchScore(label: symbol.name, prefix: prefix) else { return nil }
                score = match
            }
            return Candidate(score: score, item: item(for: symbol))
        }
    }

    static func catalogCandidates(format: SourceFormat, prefix: String) -> [Candidate] {
        catalog(for: format).compactMap { entry in
            guard let match = matchScore(label: entry.label, prefix: prefix) else { return nil }
            return Candidate(
                score: 100 + match,
                item: SourceCompletionItem(
                    label: entry.label,
                    insertionText: entry.label,
                    kind: entry.kind,
                    detail: entry.detail,
                    origin: .languageCatalog,
                    action: .insertText
                )
            )
        }
    }

    static func workspaceCandidates(
        symbols: [SourceWorkspaceCompletionSymbol],
        prefix: String
    ) -> [Candidate] {
        symbols.compactMap { indexed in
            guard let match = matchScore(label: indexed.symbol.name, prefix: prefix) else { return nil }
            let symbol = indexed.symbol
            let containerDetail = symbol.containerName.map { " · \($0)" } ?? ""
            return Candidate(
                score: 50 + match,
                item: SourceCompletionItem(
                    label: symbol.name,
                    insertionText: symbol.name,
                    kind: completionKind(for: symbol.kind),
                    detail: "\(indexed.relativePath) · \(symbol.detail)\(containerDetail)",
                    origin: .workspaceIndex,
                    sourceLine: symbol.range.startLine,
                    sourceSymbolID: indexed.id,
                    sourceDocumentPath: indexed.relativePath,
                    action: .insertText
                )
            )
        }
    }

    static func item(for symbol: SourceSymbol) -> SourceCompletionItem {
        let kind = completionKind(for: symbol.kind)
        let containerDetail = symbol.containerName.map { " · \($0)" } ?? ""
        return SourceCompletionItem(
            label: symbol.name,
            insertionText: symbol.name,
            kind: kind,
            detail: "\(symbol.detail)\(containerDetail)",
            origin: .currentDocument,
            sourceLine: symbol.range.startLine,
            sourceSymbolID: symbol.id,
            action: .insertText
        )
    }

    static func completionKind(for kind: SourceSymbolKind) -> SourceCompletionKind {
        switch kind {
        case .field: .field
        case .variable: .variable
        case .dataStructure: .dataStructure
        case .procedure, .subroutine, .paragraph, .label, .program, .section, .division, .sqlObject: .procedure
        case .prototype, .procedureInterface: .prototype
        case .parameter: .parameter
        case .file: .file
        case .recordFormat: .recordFormat
        }
    }

    static func matchScore(label: String, prefix: String) -> Int? {
        let normalizedLabel = label.uppercased()
        let normalizedPrefix = prefix.uppercased()
        if normalizedPrefix.isEmpty { return 40 }
        if normalizedLabel == normalizedPrefix { return 0 }
        if normalizedLabel.hasPrefix(normalizedPrefix) { return 10 }
        let components = normalizedLabel.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
        if components.contains(where: { $0.hasPrefix(normalizedPrefix) }) { return 20 }
        if normalizedLabel.contains(normalizedPrefix) { return 30 }
        return nil
    }

    static func candidatePrecedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        let lhsKindRank = kindRank(lhs.item.kind)
        let rhsKindRank = kindRank(rhs.item.kind)
        if lhsKindRank != rhsKindRank { return lhsKindRank < rhsKindRank }
        if let lhsLine = lhs.item.sourceLine,
           let rhsLine = rhs.item.sourceLine,
           lhsLine != rhsLine {
            return lhsLine < rhsLine
        }
        let labelOrder = lhs.item.label.localizedCaseInsensitiveCompare(rhs.item.label)
        if labelOrder != .orderedSame { return labelOrder == .orderedAscending }
        if lhs.item.kind.rawValue != rhs.item.kind.rawValue {
            return lhs.item.kind.rawValue < rhs.item.kind.rawValue
        }
        return lhs.item.id < rhs.item.id
    }

    static func kindRank(_ kind: SourceCompletionKind) -> Int {
        switch kind {
        case .field: 0
        case .variable: 1
        case .parameter: 2
        case .dataStructure: 3
        case .prototype: 4
        case .procedure: 5
        case .file: 6
        case .recordFormat: 7
        case .keyword: 8
        case .builtIn: 9
        case .assistReview: 10
        }
    }

    static func assistSubject(prefix: String, qualifier: String?) -> String? {
        if let qualifier, !qualifier.isEmpty { return qualifier }
        return prefix.isEmpty ? nil : prefix
    }

    static func bestAssistSymbol(subject: String, symbols: [SourceSymbol]) -> SourceSymbol? {
        symbols.first(where: { $0.name.caseInsensitiveCompare(subject) == .orderedSame })
            ?? symbols.first(where: { $0.name.localizedCaseInsensitiveContains(subject) })
    }

    static func isIdentifierCharacter(_ unit: unichar, format: SourceFormat) -> Bool {
        if unit >= 48 && unit <= 57 { return true }
        if unit >= 65 && unit <= 90 { return true }
        if unit >= 97 && unit <= 122 { return true }
        switch unit {
        case 35, 36, 64, 95:
            return true
        case 37, 38, 42:
            return format == .rpgle || format == .clle
        case 45:
            return format == .cobol || format == .rpgle || format == .clle
        default:
            return false
        }
    }

    static func isValidCaret(_ offset: Int, in text: String) -> Bool {
        guard offset >= 0, offset <= text.utf16.count else { return false }
        let utf16 = text.utf16
        let index = utf16.index(utf16.startIndex, offsetBy: offset)
        return index.samePosition(in: text) != nil
    }

    static func catalog(for format: SourceFormat) -> [CatalogEntry] {
        switch format {
        case .rpgle:
            return entries(rpgKeywords, kind: .keyword, detail: "RPG operation or declaration")
                + entries(rpgBuiltIns, kind: .builtIn, detail: "RPG built-in function or special value")
        case .clle:
            return entries(clKeywords, kind: .keyword, detail: "CL command or control keyword")
                + entries(clBuiltIns, kind: .builtIn, detail: "CL special value")
        case .cobol:
            return entries(cobolKeywords, kind: .keyword, detail: "COBOL keyword")
        case .dds:
            return entries(ddsKeywords, kind: .keyword, detail: "DDS keyword")
        case .sql:
            return entries(sqlKeywords, kind: .keyword, detail: "Db2 for i SQL keyword")
        case .text:
            return []
        }
    }

    static func entries(
        _ labels: [String],
        kind: SourceCompletionKind,
        detail: String
    ) -> [CatalogEntry] {
        labels.map { CatalogEntry(label: $0, kind: kind, detail: detail) }
    }

    static let rpgKeywords = [
        "ctl-opt", "dcl-c", "dcl-ds", "dcl-f", "dcl-pi", "dcl-pr", "dcl-proc", "dcl-s",
        "delete", "dow", "dou", "else", "elseif", "end-ds", "enddo", "endfor", "endif",
        "endmon", "end-pi", "end-pr", "end-proc", "endsl", "endsr", "eval", "exsr", "for",
        "if", "monitor", "on-error", "other", "read", "reade", "return", "select", "setll",
        "update", "when", "write"
    ]

    static let rpgBuiltIns = [
        "%addr", "%char", "%date", "%dec", "%dech", "%diff", "%eof", "%equal", "%error",
        "%fields", "%found", "%int", "%len", "%lookup", "%open", "%parms", "%rem", "%scan",
        "%size", "%subst", "%timestamp", "%trim", "%triml", "%trimr", "%xlate", "*blanks",
        "*hival", "*inlr", "*loval", "*off", "*on", "*zeros"
    ]

    static let clKeywords = [
        "CALL", "CALLPRC", "CHGVAR", "DCL", "DCLF", "DO", "ELSE", "ENDDO", "ENDPGM", "IF",
        "MONMSG", "PGM", "RCVMSG", "RETURN", "SNDPGMMSG", "THEN"
    ]

    static let clBuiltIns = ["*ALL", "*CHAR", "*DEC", "*NO", "*NONE", "*YES"]

    static let cobolKeywords = [
        "CALL", "CLOSE", "COMPUTE", "COPY", "DATA", "DISPLAY", "DIVISION", "ELSE", "END-IF",
        "EVALUATE", "GOBACK", "IDENTIFICATION", "IF", "MOVE", "OPEN", "PERFORM", "PROCEDURE",
        "PROGRAM-ID", "READ", "SECTION", "STOP", "WHEN", "WORKING-STORAGE", "WRITE"
    ]

    static let ddsKeywords = [
        "ALIAS", "ALTNAME", "COMP", "DSPATR", "EDTCDE", "EDTWRD", "JDFTVAL", "JOIN", "K",
        "PFILE", "R", "REFFLD", "RENAME", "TEXT", "UNIQUE", "VALUES"
    ]

    static let sqlKeywords = [
        "AND", "AS", "BEGIN", "CALL", "CASE", "CREATE", "DELETE", "ELSE", "END", "FETCH",
        "FROM", "FULL", "FUNCTION", "GROUP", "HAVING", "INNER", "INSERT", "INTO", "JOIN", "LEFT",
        "MERGE", "ORDER", "PROCEDURE", "RIGHT", "SELECT", "SET", "TABLE", "THEN", "TRIGGER",
        "UNION", "UPDATE", "VALUES", "VIEW", "WHEN", "WHERE", "WITH"
    ]
}
