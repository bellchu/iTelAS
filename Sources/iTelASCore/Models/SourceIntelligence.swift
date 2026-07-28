import CryptoKit
import Foundation

public enum SourceLanguageDialect: String, Codable, Sendable {
    case rpgleFullyFree
    case rpgleColumnLimited
    case rpgleMixed
    case clle
    case cobol
    case dds
    case sql
    case plainText

    public var label: String {
        switch self {
        case .rpgleFullyFree: "RPGLE · fully free"
        case .rpgleColumnLimited: "RPGLE · column limited"
        case .rpgleMixed: "RPGLE · mixed / inferred"
        case .clle: "CLLE"
        case .cobol: "COBOL"
        case .dds: "DDS"
        case .sql: "SQL"
        case .plainText: "Plain text"
        }
    }
}

public enum SourceSymbolKind: String, CaseIterable, Codable, Sendable {
    case program
    case procedure
    case prototype
    case procedureInterface
    case dataStructure
    case variable
    case parameter
    case file
    case subroutine
    case recordFormat
    case field
    case division
    case section
    case paragraph
    case label
    case sqlObject

    public var label: String {
        switch self {
        case .program: "Program"
        case .procedure: "Procedure"
        case .prototype: "Prototype"
        case .procedureInterface: "Procedure interface"
        case .dataStructure: "Data structure"
        case .variable: "Variable"
        case .parameter: "Parameter"
        case .file: "File"
        case .subroutine: "Subroutine"
        case .recordFormat: "Record format"
        case .field: "Field"
        case .division: "Division"
        case .section: "Section"
        case .paragraph: "Paragraph"
        case .label: "Label"
        case .sqlObject: "SQL object"
        }
    }

    public var shortLabel: String {
        switch self {
        case .program: "PG"
        case .procedure: "P"
        case .prototype: "PR"
        case .procedureInterface: "PI"
        case .dataStructure: "DS"
        case .variable: "V"
        case .parameter: "PA"
        case .file: "FL"
        case .subroutine: "SR"
        case .recordFormat: "RF"
        case .field: "FD"
        case .division: "DV"
        case .section: "SC"
        case .paragraph: "¶"
        case .label: "LB"
        case .sqlObject: "SQ"
        }
    }
}

public struct SourceTextRange: Hashable, Codable, Sendable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int

    public init(startLine: Int, startColumn: Int, endLine: Int? = nil, endColumn: Int? = nil) {
        let safeStartLine = max(1, startLine)
        let safeStartColumn = max(1, startColumn)
        let safeEndLine = max(safeStartLine, endLine ?? safeStartLine)
        self.startLine = safeStartLine
        self.startColumn = safeStartColumn
        self.endLine = safeEndLine
        self.endColumn = max(safeEndLine == safeStartLine ? safeStartColumn : 1, endColumn ?? safeStartColumn)
    }

    public func utf16Range(in text: String) -> NSRange? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.indices.contains(startLine - 1),
              lines.indices.contains(endLine - 1) else { return nil }

        let startLineOffset = lines.prefix(startLine - 1).reduce(0) { $0 + $1.utf16.count + 1 }
        let endLineOffset = lines.prefix(endLine - 1).reduce(0) { $0 + $1.utf16.count + 1 }
        let startLineLength = lines[startLine - 1].utf16.count
        let endLineLength = lines[endLine - 1].utf16.count
        let start = startLineOffset + min(startLineLength, startColumn - 1)
        let end = endLineOffset + min(endLineLength, endColumn - 1)
        let available = max(0, text.utf16.count - start)
        let requestedLength = max(0, end - start)
        let length = min(available, requestedLength == 0 && available > 0 ? 1 : requestedLength)
        return NSRange(location: start, length: length)
    }
}

public struct SourceSymbol: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: SourceSymbolKind
    public let detail: String
    public let containerName: String?
    public let range: SourceTextRange

    public init(
        name: String,
        kind: SourceSymbolKind,
        detail: String,
        containerName: String? = nil,
        range: SourceTextRange
    ) {
        self.name = name
        self.kind = kind
        self.detail = detail
        self.containerName = containerName
        self.range = range
        id = "\(kind.rawValue):\(range.startLine):\(name.uppercased())"
    }
}

public enum SourceReferenceKind: String, Codable, Sendable {
    case copy
    case include
    case procedureCall
    case programCall
    case file
    case recordFormat
    case field

    public var label: String {
        switch self {
        case .copy: "COPY"
        case .include: "INCLUDE"
        case .procedureCall: "PROCEDURE CALL"
        case .programCall: "PROGRAM CALL"
        case .file: "FILE"
        case .recordFormat: "RECORD FORMAT"
        case .field: "FIELD"
        }
    }
}

public enum SourceReferenceTarget: Hashable, Codable, Sendable {
    case member(library: String?, sourceFile: String, member: String)
    case ifsPath(String)
    case object(String)
    case symbol(String)
    case unqualified(String)

    public var displayName: String {
        switch self {
        case .member(let library, let sourceFile, let member):
            if let library { return "\(library)/\(sourceFile),\(member)" }
            return "\(sourceFile),\(member)"
        case .ifsPath(let path), .object(let path), .symbol(let path), .unqualified(let path):
            return path
        }
    }
}

public enum SourceReferenceResolution: String, Codable, Sendable {
    case currentDocument
    case externalIdentity
    case contentNotLoaded

    public var label: String {
        switch self {
        case .currentDocument: "Current document"
        case .externalIdentity: "External identity"
        case .contentNotLoaded: "Content not loaded"
        }
    }
}

public struct SourceReference: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let kind: SourceReferenceKind
    public let target: SourceReferenceTarget
    public let resolution: SourceReferenceResolution
    public let range: SourceTextRange

    public init(
        kind: SourceReferenceKind,
        target: SourceReferenceTarget,
        resolution: SourceReferenceResolution,
        range: SourceTextRange
    ) {
        self.kind = kind
        self.target = target
        self.resolution = resolution
        self.range = range
        id = "\(kind.rawValue):\(range.startLine):\(target.displayName.uppercased())"
    }
}

public enum SourceLocalCheckSeverity: String, Codable, Sendable {
    case information
    case advisory
    case warning

    public var label: String { rawValue.uppercased() }
}

public enum SourceLocalCheckKind: String, Codable, Sendable {
    case unmatchedTerminator
    case incompleteStructure
    case analysisLimit
    case languageBoundary
}

public struct SourceLocalCheck: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let kind: SourceLocalCheckKind
    public let severity: SourceLocalCheckSeverity
    public let message: String
    public let range: SourceTextRange

    public init(
        kind: SourceLocalCheckKind,
        severity: SourceLocalCheckSeverity,
        message: String,
        range: SourceTextRange
    ) {
        self.kind = kind
        self.severity = severity
        self.message = message
        self.range = range
        id = "\(kind.rawValue):\(range.startLine):\(message)"
    }
}

public struct SourceIntelligenceSnapshot: Equatable, Codable, Sendable {
    public let format: SourceFormat
    public let dialect: SourceLanguageDialect
    public let fingerprint: String
    public let analyzedLineCount: Int
    public let wasLimited: Bool
    public let symbols: [SourceSymbol]
    public let references: [SourceReference]
    public let checks: [SourceLocalCheck]
    public let highlights: [SourceHighlightSpan]
    public let highlightingWasLimited: Bool
    public let limitations: [String]

    public init(
        format: SourceFormat,
        dialect: SourceLanguageDialect,
        fingerprint: String,
        analyzedLineCount: Int,
        wasLimited: Bool,
        symbols: [SourceSymbol],
        references: [SourceReference],
        checks: [SourceLocalCheck],
        highlights: [SourceHighlightSpan],
        highlightingWasLimited: Bool,
        limitations: [String]
    ) {
        self.format = format
        self.dialect = dialect
        self.fingerprint = fingerprint
        self.analyzedLineCount = analyzedLineCount
        self.wasLimited = wasLimited
        self.symbols = symbols
        self.references = references
        self.checks = checks
        self.highlights = highlights
        self.highlightingWasLimited = highlightingWasLimited
        self.limitations = limitations
    }

    public var boundaryLabel: String { "Local heuristic · not a compiler result" }
    public var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }
}

public struct SourceIntelligenceLimits: Equatable, Sendable {
    public var maximumUTF8Bytes: Int
    public var maximumLines: Int
    public var maximumUTF16UnitsPerLine: Int
    public var maximumHighlightSpans: Int

    public init(
        maximumUTF8Bytes: Int = 2 * 1_024 * 1_024,
        maximumLines: Int = 25_000,
        maximumUTF16UnitsPerLine: Int = 65_536,
        maximumHighlightSpans: Int = 100_000
    ) {
        self.maximumUTF8Bytes = max(1, maximumUTF8Bytes)
        self.maximumLines = max(1, maximumLines)
        self.maximumUTF16UnitsPerLine = max(1, maximumUTF16UnitsPerLine)
        self.maximumHighlightSpans = max(1, maximumHighlightSpans)
    }
}

public struct SourceNavigationRequest: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let range: SourceTextRange

    public init(id: UUID = UUID(), range: SourceTextRange) {
        self.id = id
        self.range = range
    }
}

public struct SourceIntelligenceAnalyzer: Sendable {
    public let limits: SourceIntelligenceLimits

    public init(limits: SourceIntelligenceLimits = SourceIntelligenceLimits()) {
        self.limits = limits
    }

    public static func fingerprint(of text: String) -> String {
        fingerprint(text)
    }

    public func analyze(_ document: SourceDocument) -> SourceIntelligenceSnapshot {
        analyze(text: document.text, format: document.format, documentName: document.identity.displayName)
    }

    public func analyze(text: String, format: SourceFormat, documentName: String = "SOURCE") -> SourceIntelligenceSnapshot {
        let fingerprint = Self.fingerprint(text)
        let dialect = Self.detectDialect(text: text, format: format)
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        }
        let byteCount = text.lengthOfBytes(using: .utf8)
        let overlongLine = rawLines.firstIndex { $0.utf16.count > limits.maximumUTF16UnitsPerLine }
        let limitMessage: String?
        if byteCount > limits.maximumUTF8Bytes {
            limitMessage = "Local analysis skipped because the draft exceeds the \(limits.maximumUTF8Bytes)-byte limit."
        } else if rawLines.count > limits.maximumLines {
            limitMessage = "Local analysis skipped because the draft exceeds the \(limits.maximumLines)-line limit."
        } else if let overlongLine {
            limitMessage = "Local analysis skipped because line \(overlongLine + 1) exceeds the per-line limit."
        } else {
            limitMessage = nil
        }

        if let limitMessage {
            return SourceIntelligenceSnapshot(
                format: format,
                dialect: dialect,
                fingerprint: fingerprint,
                analyzedLineCount: 0,
                wasLimited: true,
                symbols: [],
                references: [],
                checks: [SourceLocalCheck(
                    kind: .analysisLimit,
                    severity: .warning,
                    message: limitMessage,
                    range: SourceTextRange(startLine: 1, startColumn: 1)
                )],
                highlights: [],
                highlightingWasLimited: true,
                limitations: Self.limitations(for: format)
            )
        }

        let result: AnalysisResult
        switch format {
        case .rpgle:
            result = Self.analyzeRPG(lines: rawLines, documentName: documentName, dialect: dialect)
        case .clle:
            result = Self.analyzeCL(lines: rawLines, documentName: documentName)
        case .cobol:
            result = Self.analyzeCOBOL(lines: rawLines, documentName: documentName)
        case .dds:
            result = Self.analyzeDDS(lines: rawLines)
        case .sql:
            result = Self.analyzeSQL(lines: rawLines)
        case .text:
            result = AnalysisResult()
        }

        let symbols = Self.deduplicated(result.symbols)
        let references = Self.deduplicated(result.references)
        let checks = Self.deduplicated(result.checks)
        let highlighting = SourceSyntaxHighlighter(limits: limits).highlight(
            text: text,
            format: format,
            dialect: dialect,
            symbols: symbols
        )
        return SourceIntelligenceSnapshot(
            format: format,
            dialect: dialect,
            fingerprint: fingerprint,
            analyzedLineCount: rawLines.count,
            wasLimited: false,
            symbols: symbols,
            references: references,
            checks: checks,
            highlights: highlighting.spans,
            highlightingWasLimited: highlighting.wasLimited,
            limitations: Self.limitations(for: format)
        )
    }
}

private extension SourceIntelligenceAnalyzer {
    struct AnalysisResult {
        var symbols: [SourceSymbol] = []
        var references: [SourceReference] = []
        var checks: [SourceLocalCheck] = []
    }

    enum BlockKind: String {
        case procedure = "procedure"
        case prototype = "prototype"
        case interface = "procedure interface"
        case dataStructure = "data structure"
        case subroutine = "subroutine"
        case program = "program"

        var terminator: String {
            switch self {
            case .procedure: "END-PROC"
            case .prototype: "END-PR"
            case .interface: "END-PI"
            case .dataStructure: "END-DS"
            case .subroutine: "ENDSR / ENDSUBR"
            case .program: "ENDPGM"
            }
        }
    }

    struct OpenBlock {
        let kind: BlockKind
        let name: String
        let line: Int
    }

    static func detectDialect(text: String, format: SourceFormat) -> SourceLanguageDialect {
        switch format {
        case .rpgle:
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let first = lines.first?
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if first == "**FREE" { return .rpgleFullyFree }
            let hasFixedSpecifications = lines.contains { line in
                guard line.count > 5 else { return false }
                let characters = Array(line)
                let prefixLooksColumnar = characters.prefix(5).allSatisfy { $0.isWhitespace || $0.isNumber }
                return prefixLooksColumnar && "HFDICOP".contains(characters[5].uppercased())
            }
            return hasFixedSpecifications ? .rpgleColumnLimited : .rpgleMixed
        case .clle: return .clle
        case .cobol: return .cobol
        case .dds: return .dds
        case .sql: return .sql
        case .text: return .plainText
        }
    }

    static func analyzeRPG(
        lines: [String],
        documentName: String,
        dialect: SourceLanguageDialect
    ) -> AnalysisResult {
        var result = AnalysisResult()
        var blocks: [OpenBlock] = []
        let programName = baseDocumentName(documentName)
        if let programName = safeSymbolName(programName) {
            result.symbols.append(symbol(programName, .program, "Main procedure", line: 1, in: lines.first ?? ""))
        }

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let fixedSpec = fixedSpecification(in: rawLine)
            if dialect == .rpgleColumnLimited, let fixedSpec {
                analyzeFixedRPGLine(
                    rawLine,
                    specification: fixedSpec,
                    lineNumber: lineNumber,
                    result: &result,
                    blocks: &blocks
                )
            }

            let code = stripRPGComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty, code.uppercased() != "**FREE" else { continue }

            if let directive = RPGDirective.parse(code) {
                let target = parseIncludeTarget(directive.target)
                result.references.append(SourceReference(
                    kind: directive.kind,
                    target: target,
                    resolution: .contentNotLoaded,
                    range: sourceRange(for: directive.target, in: rawLine, line: lineNumber)
                ))
                continue
            }

            if let name = token(after: "dcl-proc", in: code) {
                appendSymbol(name, kind: .procedure, detail: "Procedure", line: lineNumber, rawLine: rawLine, to: &result)
                blocks.append(OpenBlock(kind: .procedure, name: name, line: lineNumber))
                continue
            }
            if starts(with: "end-proc", code) {
                close(.procedure, at: lineNumber, rawLine: rawLine, blocks: &blocks, checks: &result.checks)
                continue
            }
            if let name = token(after: "dcl-pr", in: code) {
                appendSymbol(name, kind: .prototype, detail: boundedDetail(after: name, in: code), line: lineNumber, rawLine: rawLine, to: &result)
                blocks.append(OpenBlock(kind: .prototype, name: name, line: lineNumber))
                continue
            }
            if starts(with: "end-pr", code) {
                close(.prototype, at: lineNumber, rawLine: rawLine, blocks: &blocks, checks: &result.checks)
                continue
            }
            if let name = token(after: "dcl-pi", in: code) {
                if name != "*n" {
                    appendSymbol(name, kind: .procedureInterface, detail: boundedDetail(after: name, in: code), line: lineNumber, rawLine: rawLine, to: &result)
                }
                blocks.append(OpenBlock(kind: .interface, name: name, line: lineNumber))
                continue
            }
            if starts(with: "end-pi", code) {
                close(.interface, at: lineNumber, rawLine: rawLine, blocks: &blocks, checks: &result.checks)
                continue
            }
            if let name = token(after: "dcl-ds", in: code) {
                appendSymbol(name, kind: .dataStructure, detail: boundedDetail(after: name, in: code), line: lineNumber, rawLine: rawLine, to: &result)
                blocks.append(OpenBlock(kind: .dataStructure, name: name, line: lineNumber))
                continue
            }
            if starts(with: "end-ds", code) {
                close(.dataStructure, at: lineNumber, rawLine: rawLine, blocks: &blocks, checks: &result.checks)
                continue
            }
            if let name = token(after: "dcl-f", in: code) {
                appendSymbol(name, kind: .file, detail: boundedDetail(after: name, in: code), line: lineNumber, rawLine: rawLine, to: &result)
                continue
            }
            if let name = token(after: "dcl-s", in: code) ?? token(after: "dcl-c", in: code) {
                appendSymbol(name, kind: .variable, detail: boundedDetail(after: name, in: code), line: lineNumber, rawLine: rawLine, to: &result)
                continue
            }
            if let name = token(after: "begsr", in: code) {
                appendSymbol(name, kind: .subroutine, detail: "Subroutine", line: lineNumber, rawLine: rawLine, to: &result)
                blocks.append(OpenBlock(kind: .subroutine, name: name, line: lineNumber))
                continue
            }
            if starts(with: "endsr", code) {
                close(.subroutine, at: lineNumber, rawLine: rawLine, blocks: &blocks, checks: &result.checks)
                continue
            }

            if let container = blocks.last(where: { $0.kind == .prototype || $0.kind == .interface || $0.kind == .dataStructure }),
               let candidate = firstToken(in: code),
               !reservedRPGWords.contains(candidate.lowercased()) {
                let kind: SourceSymbolKind = container.kind == .dataStructure ? .field : .parameter
                appendSymbol(
                    candidate,
                    kind: kind,
                    detail: boundedDetail(after: candidate, in: code),
                    containerName: container.name,
                    line: lineNumber,
                    rawLine: rawLine,
                    to: &result
                )
            }

            if let target = token(after: "callp", in: code) {
                result.references.append(reference(.procedureCall, target: .symbol(target), line: lineNumber, rawLine: rawLine))
            }
            if let target = token(after: "exsr", in: code) {
                result.references.append(reference(.procedureCall, target: .symbol(target), line: lineNumber, rawLine: rawLine))
            }
        }

        var callableNames: [String: String] = [:]
        for symbol in result.symbols where symbol.kind == .procedure || symbol.kind == .prototype {
            callableNames[symbol.name.lowercased(), default: symbol.name] = symbol.name
        }
        for (offset, rawLine) in lines.enumerated() {
            let code = stripRPGComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !starts(with: "dcl-proc", code),
                  !starts(with: "dcl-pr", code),
                  !starts(with: "callp", code) else { continue }
            for calledName in invokedIdentifiers(in: code) {
                guard let name = callableNames[calledName.lowercased()] else { continue }
                result.references.append(reference(.procedureCall, target: .symbol(name), line: offset + 1, rawLine: rawLine, resolution: .currentDocument))
            }
        }

        finishOpenBlocks(blocks, checks: &result.checks)
        return result
    }

    static func analyzeFixedRPGLine(
        _ line: String,
        specification: Character,
        lineNumber: Int,
        result: inout AnalysisResult,
        blocks: inout [OpenBlock]
    ) {
        let remainder = String(line.dropFirst(min(6, line.count))).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return }
        switch specification.uppercased() {
        case "F":
            if let name = firstToken(in: remainder) {
                appendSymbol(name, kind: .file, detail: "Fixed-format file specification", line: lineNumber, rawLine: line, to: &result)
            }
        case "D":
            if let name = firstToken(in: remainder) {
                appendSymbol(name, kind: .variable, detail: "Fixed-format definition", line: lineNumber, rawLine: line, to: &result)
            }
        case "P":
            guard let name = firstToken(in: remainder) else { return }
            let upper = remainder.uppercased()
            if upper.split(whereSeparator: { $0.isWhitespace }).contains("B") {
                appendSymbol(name, kind: .procedure, detail: "Fixed-format procedure", line: lineNumber, rawLine: line, to: &result)
                blocks.append(OpenBlock(kind: .procedure, name: name, line: lineNumber))
            } else if upper.split(whereSeparator: { $0.isWhitespace }).contains("E") {
                close(.procedure, at: lineNumber, rawLine: line, blocks: &blocks, checks: &result.checks)
            }
        case "C":
            let upper = remainder.uppercased()
            if let range = upper.range(of: "EXSR"),
               let target = firstToken(in: String(remainder[range.upperBound...])) {
                result.references.append(reference(.procedureCall, target: .symbol(target), line: lineNumber, rawLine: line))
            }
        default:
            break
        }
    }

    static func analyzeCL(lines: [String], documentName: String) -> AnalysisResult {
        var result = AnalysisResult()
        var blocks: [OpenBlock] = []
        var inComment = false
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            var code = stripBlockComments(rawLine, inComment: &inComment).trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty else { continue }
            if let colon = code.firstIndex(of: ":") {
                let label = String(code[..<colon]).trimmingCharacters(in: .whitespaces)
                appendSymbol(label, kind: .label, detail: "CL label", line: lineNumber, rawLine: rawLine, to: &result)
                code = String(code[code.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }

            if starts(with: "pgm", code) {
                let name = argumentValue("PGM", in: code) ?? baseDocumentName(documentName)
                appendSymbol(name, kind: .program, detail: "CL program", line: lineNumber, rawLine: rawLine, to: &result)
                blocks.append(OpenBlock(kind: .program, name: name, line: lineNumber))
            } else if starts(with: "endpgm", code) {
                close(.program, at: lineNumber, rawLine: rawLine, blocks: &blocks, checks: &result.checks)
            } else if starts(with: "dclf", code), let file = argumentValue("FILE", in: code) {
                appendSymbol(lastQualifiedPart(file), kind: .file, detail: file, line: lineNumber, rawLine: rawLine, to: &result)
                result.references.append(reference(.file, target: .object(file), line: lineNumber, rawLine: rawLine))
            } else if starts(with: "dcl", code), let variable = argumentValue("VAR", in: code) {
                appendSymbol(variable, kind: .variable, detail: argumentValue("TYPE", in: code) ?? "CL variable", line: lineNumber, rawLine: rawLine, to: &result)
            } else if starts(with: "callprc", code), let procedure = argumentValue("PRC", in: code) {
                result.references.append(reference(.procedureCall, target: .symbol(procedure), line: lineNumber, rawLine: rawLine))
            } else if starts(with: "call", code), let program = argumentValue("PGM", in: code) {
                result.references.append(reference(.programCall, target: .object(program), line: lineNumber, rawLine: rawLine))
            } else if starts(with: "subr", code) {
                let name = argumentValue("SUBR", in: code) ?? token(after: "subr", in: code) ?? "SUBROUTINE"
                appendSymbol(name, kind: .subroutine, detail: "CL subroutine", line: lineNumber, rawLine: rawLine, to: &result)
                blocks.append(OpenBlock(kind: .subroutine, name: name, line: lineNumber))
            } else if starts(with: "endsubr", code) {
                close(.subroutine, at: lineNumber, rawLine: rawLine, blocks: &blocks, checks: &result.checks)
            }
        }
        finishOpenBlocks(blocks, checks: &result.checks)
        return result
    }

    static func analyzeCOBOL(lines: [String], documentName: String) -> AnalysisResult {
        var result = AnalysisResult()
        var inProcedureDivision = false
        var currentContainer: String?
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            guard !isCOBOLComment(rawLine) else { continue }
            let code = stripCOBOLInlineComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty else { continue }
            let upper = code.uppercased()

            if upper.hasPrefix("PROGRAM-ID.") {
                let rawName = String(code.dropFirst("PROGRAM-ID.".count))
                let name = firstToken(in: rawName) ?? baseDocumentName(documentName)
                appendSymbol(name, kind: .program, detail: "COBOL program", line: lineNumber, rawLine: rawLine, to: &result)
                currentContainer = name
                continue
            }
            if upper.hasSuffix(" DIVISION.") {
                let name = String(code.dropLast(" DIVISION.".count)).trimmingCharacters(in: .whitespaces)
                appendSymbol(name, kind: .division, detail: "COBOL division", line: lineNumber, rawLine: rawLine, to: &result)
                currentContainer = name
                inProcedureDivision = upper == "PROCEDURE DIVISION."
                continue
            }
            if upper.hasSuffix(" SECTION.") {
                let name = String(code.dropLast(" SECTION.".count)).trimmingCharacters(in: .whitespaces)
                appendSymbol(name, kind: .section, detail: "COBOL section", containerName: currentContainer, line: lineNumber, rawLine: rawLine, to: &result)
                currentContainer = name
                continue
            }
            let tokens = sourceTokens(code)
            if tokens.count >= 2, tokens[0].count == 2, Int(tokens[0]) != nil {
                appendSymbol(tokens[1], kind: .field, detail: "Level \(tokens[0]) data item", containerName: currentContainer, line: lineNumber, rawLine: rawLine, to: &result)
                continue
            }
            if upper.hasPrefix("COPY "), let name = tokens.dropFirst().first {
                result.references.append(reference(.copy, target: .unqualified(name), line: lineNumber, rawLine: rawLine))
                continue
            }
            if upper.hasPrefix("CALL "), let target = quotedValue(after: "CALL", in: code) ?? tokens.dropFirst().first {
                result.references.append(reference(.programCall, target: .object(target), line: lineNumber, rawLine: rawLine))
                continue
            }
            if inProcedureDivision,
               tokens.count == 1,
               code.hasSuffix("."),
               !cobolParagraphExclusions.contains(tokens[0].uppercased()) {
                appendSymbol(tokens[0], kind: .paragraph, detail: "COBOL paragraph", containerName: currentContainer, line: lineNumber, rawLine: rawLine, to: &result)
            }
        }
        return result
    }

    static func analyzeDDS(lines: [String]) -> AnalysisResult {
        var result = AnalysisResult()
        var currentRecord: String?
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            guard !isDDSComment(rawLine) else { continue }
            if let file = argumentValue("PFILE", in: rawLine) ?? argumentValue("REF", in: rawLine) {
                result.references.append(reference(.file, target: .object(file), line: lineNumber, rawLine: rawLine))
            }
            if let referenced = argumentValue("REFFLD", in: rawLine) {
                result.references.append(reference(.field, target: .unqualified(referenced), line: lineNumber, rawLine: rawLine))
            }
            var tokens = sourceTokens(rawLine)
            guard !tokens.isEmpty else { continue }
            if tokens.first?.uppercased() == "A" { tokens.removeFirst() }
            guard !tokens.isEmpty else { continue }
            if tokens[0].uppercased() == "R", tokens.count > 1 {
                currentRecord = tokens[1]
                appendSymbol(tokens[1], kind: .recordFormat, detail: "DDS record format", line: lineNumber, rawLine: rawLine, to: &result)
            } else if tokens[0].uppercased() == "K", tokens.count > 1 {
                result.references.append(reference(.field, target: .symbol(tokens[1]), line: lineNumber, rawLine: rawLine, resolution: .currentDocument))
            } else if !tokens[0].contains("("), !ddsKeywords.contains(tokens[0].uppercased()) {
                appendSymbol(tokens[0], kind: .field, detail: "DDS field", containerName: currentRecord, line: lineNumber, rawLine: rawLine, to: &result)
            }

        }
        return result
    }

    static func analyzeSQL(lines: [String]) -> AnalysisResult {
        var result = AnalysisResult()
        let objectKinds = ["PROCEDURE", "FUNCTION", "VIEW", "TABLE", "TRIGGER", "INDEX"]
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let code = stripSQLComment(rawLine).trimmingCharacters(in: .whitespaces)
            let tokens = sourceTokens(code)
            guard !tokens.isEmpty else { continue }
            let upper = tokens.map { $0.uppercased() }
            if upper.first == "CREATE" {
                if let kind = objectKinds.first(where: { upper.contains($0) }),
                   let name = sqlIdentifier(after: kind, in: code) {
                    result.symbols.append(SourceSymbol(
                        name: name,
                        kind: .sqlObject,
                        detail: kind,
                        range: sourceRange(for: name, in: rawLine, line: lineNumber)
                    ))
                }
            } else if upper.first == "CALL", tokens.count > 1 {
                result.references.append(reference(.procedureCall, target: .object(tokens[1]), line: lineNumber, rawLine: rawLine))
            }
        }
        result.checks.append(SourceLocalCheck(
            kind: .languageBoundary,
            severity: .information,
            message: "This outline is local only; use Db2 SQL Studio for statement policy and execution evidence.",
            range: SourceTextRange(startLine: 1, startColumn: 1)
        ))
        return result
    }

    struct RPGDirective {
        let kind: SourceReferenceKind
        let target: String

        static func parse(_ code: String) -> RPGDirective? {
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            let pair: (SourceReferenceKind, String)
            if upper.hasPrefix("/COPY") {
                pair = (.copy, String(trimmed.dropFirst(5)))
            } else if upper.hasPrefix("/INCLUDE") {
                pair = (.include, String(trimmed.dropFirst(8)))
            } else {
                return nil
            }
            let target = pair.1.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { return nil }
            return RPGDirective(kind: pair.0, target: target)
        }
    }

    static func parseIncludeTarget(_ rawValue: String) -> SourceReferenceTarget {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if (value.hasPrefix("'") && value.hasSuffix("'")) || (value.hasPrefix("\"") && value.hasSuffix("\"")) {
            value = String(value.dropFirst().dropLast())
        }
        value = bounded(value, maximum: 256)
        if value.hasPrefix("/") { return .ifsPath(value) }

        let commaParts = value.split(separator: ",", maxSplits: 1).map(String.init)
        if commaParts.count == 2 {
            let qualifiedFile = commaParts[0].split(separator: "/", maxSplits: 1).map(String.init)
            if qualifiedFile.count == 2 {
                return .member(
                    library: cleanReferencePart(qualifiedFile[0]),
                    sourceFile: cleanReferencePart(qualifiedFile[1]),
                    member: cleanReferencePart(commaParts[1])
                )
            }
            return .member(
                library: nil,
                sourceFile: cleanReferencePart(commaParts[0]),
                member: cleanReferencePart(commaParts[1])
            )
        }

        if let opening = value.firstIndex(of: "("), value.hasSuffix(")") {
            let filePart = String(value[..<opening])
            let member = String(value[value.index(after: opening)..<value.index(before: value.endIndex)])
            let qualifiedFile = filePart.split(separator: "/", maxSplits: 1).map(String.init)
            if qualifiedFile.count == 2 {
                return .member(
                    library: cleanReferencePart(qualifiedFile[0]),
                    sourceFile: cleanReferencePart(qualifiedFile[1]),
                    member: cleanReferencePart(member)
                )
            }
        }
        return .unqualified(cleanReferencePart(value))
    }

    static func appendSymbol(
        _ rawName: String,
        kind: SourceSymbolKind,
        detail: String,
        containerName: String? = nil,
        line: Int,
        rawLine: String,
        to result: inout AnalysisResult
    ) {
        guard let name = safeSymbolName(rawName) else { return }
        result.symbols.append(symbol(
            name,
            kind,
            detail,
            containerName: containerName,
            line: line,
            in: rawLine
        ))
    }

    static func symbol(
        _ name: String,
        _ kind: SourceSymbolKind,
        _ detail: String,
        containerName: String? = nil,
        line: Int,
        in rawLine: String
    ) -> SourceSymbol {
        SourceSymbol(
            name: name,
            kind: kind,
            detail: bounded(detail.isEmpty ? kind.label : detail, maximum: 120),
            containerName: containerName.flatMap(safeSymbolName),
            range: sourceRange(for: name, in: rawLine, line: line)
        )
    }

    static func reference(
        _ kind: SourceReferenceKind,
        target: SourceReferenceTarget,
        line: Int,
        rawLine: String,
        resolution: SourceReferenceResolution = .externalIdentity
    ) -> SourceReference {
        SourceReference(
            kind: kind,
            target: target,
            resolution: resolution,
            range: sourceRange(for: target.displayName, in: rawLine, line: line)
        )
    }

    static func close(
        _ kind: BlockKind,
        at line: Int,
        rawLine: String,
        blocks: inout [OpenBlock],
        checks: inout [SourceLocalCheck]
    ) {
        guard let index = blocks.lastIndex(where: { $0.kind == kind }) else {
            checks.append(SourceLocalCheck(
                kind: .unmatchedTerminator,
                severity: .advisory,
                message: "\(kind.terminator) has no matching local declaration.",
                range: sourceRange(for: kind.terminator, in: rawLine, line: line)
            ))
            return
        }
        blocks.remove(at: index)
    }

    static func finishOpenBlocks(_ blocks: [OpenBlock], checks: inout [SourceLocalCheck]) {
        for block in blocks {
            checks.append(SourceLocalCheck(
                kind: .incompleteStructure,
                severity: .advisory,
                message: "\(block.name) has no matching \(block.kind.terminator) in this draft.",
                range: SourceTextRange(startLine: block.line, startColumn: 1)
            ))
        }
    }

    static func starts(with keyword: String, _ code: String) -> Bool {
        let lower = code.lowercased()
        let keyword = keyword.lowercased()
        return lower == keyword
            || lower.hasPrefix(keyword + " ")
            || lower.hasPrefix(keyword + ";")
            || lower.hasPrefix(keyword + "(")
    }

    static func token(after keyword: String, in code: String) -> String? {
        let lower = code.lowercased()
        let keyword = keyword.lowercased()
        guard lower.hasPrefix(keyword), lower.count >= keyword.count else { return nil }
        let boundary = lower.index(lower.startIndex, offsetBy: keyword.count)
        if boundary < lower.endIndex {
            let character = lower[boundary]
            guard character.isWhitespace || character == "(" else { return nil }
        }
        let remainder = String(code.dropFirst(keyword.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return firstToken(in: remainder)
    }

    static func firstToken(in value: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ";(),.='\""))
        guard let token = value.components(separatedBy: separators).first(where: { !$0.isEmpty }) else { return nil }
        return safeSymbolName(token)
    }

    static func sourceTokens(_ value: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ";,.='\""))
        return value.components(separatedBy: separators).compactMap(safeSymbolName)
    }

    static func safeSymbolName(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";,.()'\"")))
        guard !trimmed.isEmpty, trimmed.utf8.count <= 128 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_#$@&*-%"))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return trimmed
    }

    static func cleanReferencePart(_ rawValue: String) -> String {
        let cleaned = rawValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";()'\"")))
        return bounded(cleaned, maximum: 128)
    }

    static func boundedDetail(after name: String, in code: String) -> String {
        guard let range = code.range(of: name, options: [.caseInsensitive]) else { return "Declaration" }
        let remainder = code[range.upperBound...]
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";")))
        return remainder.isEmpty ? "Declaration" : bounded(remainder, maximum: 120)
    }

    static func bounded(_ value: String, maximum: Int) -> String {
        let sanitized = String(value.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 || scalar == "\t"
        })
        guard sanitized.count > maximum else { return sanitized }
        return String(sanitized.prefix(maximum - 1)) + "…"
    }

    static func sourceRange(for token: String, in lineText: String, line: Int) -> SourceTextRange {
        let range = (lineText as NSString).range(of: token, options: [.caseInsensitive])
        guard range.location != NSNotFound else {
            return SourceTextRange(startLine: line, startColumn: 1)
        }
        return SourceTextRange(
            startLine: line,
            startColumn: range.location + 1,
            endColumn: range.location + max(1, range.length) + 1
        )
    }

    static func argumentValue(_ name: String, in line: String) -> String? {
        let source = line as NSString
        let marker = "\(name)("
        let markerRange = source.range(of: marker, options: [.caseInsensitive])
        guard markerRange.location != NSNotFound else { return nil }
        let start = NSMaxRange(markerRange)
        var cursor = start
        var depth = 1
        var quote: unichar?
        while cursor < source.length {
            let character = source.character(at: cursor)
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == 39 || character == 34 {
                quote = character
            } else if character == 40 {
                depth += 1
            } else if character == 41 {
                depth -= 1
                if depth == 0 {
                    let raw = source.substring(with: NSRange(location: start, length: cursor - start))
                    let value = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"")))
                    return value.isEmpty ? nil : bounded(value, maximum: 256)
                }
            }
            cursor += 1
        }
        return nil
    }

    static func invokedIdentifiers(in line: String) -> [String] {
        let source = line as NSString
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_#$@&*-%"))
        var results: [String] = []
        var cursor = 0
        var quote: unichar?
        while cursor < source.length {
            let character = source.character(at: cursor)
            if let activeQuote = quote {
                if character == activeQuote {
                    if cursor + 1 < source.length, source.character(at: cursor + 1) == activeQuote {
                        cursor += 2
                        continue
                    }
                    quote = nil
                }
                cursor += 1
                continue
            }
            if character == 39 || character == 34 {
                quote = character
                cursor += 1
                continue
            }
            guard let scalar = UnicodeScalar(character), allowed.contains(scalar) else {
                cursor += 1
                continue
            }
            let start = cursor
            cursor += 1
            while cursor < source.length,
                  let scalar = UnicodeScalar(source.character(at: cursor)),
                  allowed.contains(scalar) {
                cursor += 1
            }
            let identifier = source.substring(with: NSRange(location: start, length: cursor - start))
            while cursor < source.length,
                  let scalar = UnicodeScalar(source.character(at: cursor)),
                  CharacterSet.whitespaces.contains(scalar) {
                cursor += 1
            }
            if cursor < source.length,
               source.character(at: cursor) == 40,
               safeSymbolName(identifier) != nil {
                results.append(identifier)
            }
        }
        return results
    }

    static func sqlIdentifier(after keyword: String, in line: String) -> String? {
        let source = line as NSString
        let keywordRange = source.range(of: keyword, options: [.caseInsensitive])
        guard keywordRange.location != NSNotFound else { return nil }
        let remainder = source.substring(from: NSMaxRange(keywordRange)).trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_#$@./"))
        let identifier = String(remainder.unicodeScalars.prefix(while: allowed.contains))
        guard !identifier.isEmpty, identifier.utf8.count <= 256 else { return nil }
        return identifier
    }

    static func quotedValue(after keyword: String, in line: String) -> String? {
        let source = line as NSString
        let keywordRange = source.range(of: keyword, options: [.caseInsensitive, .anchored])
        guard keywordRange.location != NSNotFound else { return nil }
        var cursor = NSMaxRange(keywordRange)
        while cursor < source.length, CharacterSet.whitespaces.contains(UnicodeScalar(source.character(at: cursor))!) {
            cursor += 1
        }
        guard cursor < source.length else { return nil }
        let quote = source.character(at: cursor)
        guard quote == 39 || quote == 34 else { return nil }
        let start = cursor + 1
        cursor = start
        while cursor < source.length {
            if source.character(at: cursor) == quote {
                let value = source.substring(with: NSRange(location: start, length: cursor - start))
                return safeSymbolName(value)
            }
            cursor += 1
        }
        return nil
    }

    static func stripRPGComment(_ line: String) -> String {
        stripInlineComment(line, marker: "//")
    }

    static func stripCOBOLInlineComment(_ line: String) -> String {
        stripInlineComment(line, marker: "*>")
    }

    static func stripSQLComment(_ line: String) -> String {
        stripInlineComment(line, marker: "--")
    }

    static func stripInlineComment(_ line: String, marker: String) -> String {
        let source = line as NSString
        let markerUnits = Array(marker.utf16)
        guard markerUnits.count == 2 else { return line }
        var cursor = 0
        var quote: unichar?
        while cursor + 1 < source.length {
            let character = source.character(at: cursor)
            if let activeQuote = quote {
                if character == activeQuote {
                    if cursor + 1 < source.length, source.character(at: cursor + 1) == activeQuote {
                        cursor += 2
                        continue
                    }
                    quote = nil
                }
            } else if character == 39 || character == 34 {
                quote = character
            } else if character == markerUnits[0], source.character(at: cursor + 1) == markerUnits[1] {
                return source.substring(to: cursor)
            }
            cursor += 1
        }
        return line
    }

    static func stripBlockComments(_ line: String, inComment: inout Bool) -> String {
        let source = line as NSString
        var output = ""
        var cursor = 0
        while cursor < source.length {
            if inComment {
                let closing = source.range(of: "*/", options: [], range: NSRange(location: cursor, length: source.length - cursor))
                guard closing.location != NSNotFound else { return output }
                cursor = NSMaxRange(closing)
                inComment = false
            } else {
                let opening = source.range(of: "/*", options: [], range: NSRange(location: cursor, length: source.length - cursor))
                if opening.location == NSNotFound {
                    output += source.substring(from: cursor)
                    break
                }
                output += source.substring(with: NSRange(location: cursor, length: opening.location - cursor))
                cursor = NSMaxRange(opening)
                inComment = true
            }
        }
        return output
    }

    static func fixedSpecification(in line: String) -> Character? {
        guard line.count > 5 else { return nil }
        return Array(line)[5]
    }

    static func isCOBOLComment(_ line: String) -> Bool {
        let characters = Array(line)
        if characters.count > 6, characters[6] == "*" || characters[6] == "/" { return true }
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("*>")
    }

    static func isDDSComment(_ line: String) -> Bool {
        let characters = Array(line)
        return characters.count > 6 && characters[6] == "*"
    }

    static func baseDocumentName(_ value: String) -> String {
        let last = value.split(separator: "/").last.map(String.init) ?? value
        let withoutMemberSyntax: String
        if let opening = last.lastIndex(of: "("), let closing = last.lastIndex(of: ")"), opening < closing {
            withoutMemberSyntax = String(last[last.index(after: opening)..<closing])
        } else {
            withoutMemberSyntax = last
        }
        return withoutMemberSyntax.split(separator: ".").first.map(String.init) ?? withoutMemberSyntax
    }

    static func lastQualifiedPart(_ value: String) -> String {
        value.split(separator: "/").last.map(String.init) ?? value
    }

    static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func deduplicated<T: Identifiable & Hashable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var seen: Set<T.ID> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    static func limitations(for format: SourceFormat) -> [String] {
        let shared = "Local structure and reference hints are not IBM compiler diagnostics."
        switch format {
        case .rpgle:
            return [shared, "Conditional compilation, expanded /COPY content, templates, and compiler directives require Compile Evidence."]
        case .clle:
            return [shared, "Command validity, prompt metadata, substitutions, and adopted authority require IBM i evidence."]
        case .cobol:
            return [shared, "Dialect-specific syntax, COPY expansion, and compiler listings require Compile Evidence."]
        case .dds:
            return [shared, "Referenced formats, field inheritance, and generated objects require host catalog or compiler evidence."]
        case .sql:
            return [shared, "Use Db2 SQL Studio for policy analysis, plans, and execution evidence."]
        case .text:
            return ["Plain text has no local language model. No compiler result is implied."]
        }
    }

    static let reservedRPGWords: Set<String> = [
        "if", "elseif", "else", "endif", "select", "when", "other", "endsl", "for", "endfor",
        "dow", "dou", "enddo", "return", "monitor", "on-error", "endmon", "chain", "setll", "read",
        "write", "update", "delete", "eval", "callp", "exsr"
    ]

    static let cobolParagraphExclusions: Set<String> = [
        "ELSE", "END-IF", "END-PERFORM", "END-EVALUATE", "STOP", "GOBACK", "EXIT"
    ]

    static let ddsKeywords: Set<String> = [
        "A", "R", "K", "PFILE", "REF", "REFFLD", "TEXT", "COLHDG", "ALIAS", "UNIQUE", "JFILE", "JOIN"
    ]
}
