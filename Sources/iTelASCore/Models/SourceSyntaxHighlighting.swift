import Foundation

public enum SourceHighlightKind: String, Codable, Sendable {
    case directive
    case keyword
    case declaration
    case typeName
    case builtIn
    case stringLiteral
    case number
    case comment

    public var priority: Int {
        switch self {
        case .directive: 1
        case .keyword: 2
        case .typeName: 3
        case .builtIn: 4
        case .number: 5
        case .declaration: 6
        case .stringLiteral: 7
        case .comment: 8
        }
    }
}

public struct SourceHighlightSpan: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let kind: SourceHighlightKind
    public let range: SourceTextRange

    public init(kind: SourceHighlightKind, range: SourceTextRange) {
        self.kind = kind
        self.range = range
        id = "\(kind.rawValue):\(range.startLine):\(range.startColumn):\(range.endLine):\(range.endColumn)"
    }
}

public struct SourceHighlightingResult: Equatable, Codable, Sendable {
    public let spans: [SourceHighlightSpan]
    public let wasLimited: Bool

    public init(spans: [SourceHighlightSpan], wasLimited: Bool) {
        self.spans = spans
        self.wasLimited = wasLimited
    }
}

public struct SourceSyntaxHighlighter: Sendable {
    public let limits: SourceIntelligenceLimits

    public init(limits: SourceIntelligenceLimits = SourceIntelligenceLimits()) {
        self.limits = limits
    }

    public func highlight(
        text: String,
        format: SourceFormat,
        dialect: SourceLanguageDialect,
        symbols: [SourceSymbol] = []
    ) -> SourceHighlightingResult {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        }
        guard text.lengthOfBytes(using: .utf8) <= limits.maximumUTF8Bytes,
              lines.count <= limits.maximumLines,
              !lines.contains(where: { $0.utf16.count > limits.maximumUTF16UnitsPerLine }) else {
            return SourceHighlightingResult(spans: [], wasLimited: true)
        }

        var spans: [SourceHighlightSpan] = []
        spans.reserveCapacity(min(limits.maximumHighlightSpans, lines.count * 6))
        var seenSpanIDs: Set<String> = []
        var inBlockComment = false
        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 1
            let lineSpans = Self.highlightLine(
                line,
                lineNumber: lineNumber,
                format: format,
                dialect: dialect,
                inBlockComment: &inBlockComment
            )
            for span in lineSpans {
                guard seenSpanIDs.insert(span.id).inserted else { continue }
                guard spans.count < limits.maximumHighlightSpans else {
                    return SourceHighlightingResult(spans: spans, wasLimited: true)
                }
                spans.append(span)
            }
        }

        for symbol in symbols where symbol.range.endColumn > symbol.range.startColumn {
            let span = SourceHighlightSpan(kind: .declaration, range: symbol.range)
            guard seenSpanIDs.insert(span.id).inserted else { continue }
            guard spans.count < limits.maximumHighlightSpans else {
                return SourceHighlightingResult(spans: spans, wasLimited: true)
            }
            spans.append(span)
        }

        return SourceHighlightingResult(spans: spans, wasLimited: false)
    }
}

private extension SourceSyntaxHighlighter {
    struct LanguagePalette {
        let keywords: Set<String>
        let typeNames: Set<String>
        let directives: Set<String>
        let lineComment: String?
        let supportsBlockComments: Bool
    }

    static func highlightLine(
        _ line: String,
        lineNumber: Int,
        format: SourceFormat,
        dialect: SourceLanguageDialect,
        inBlockComment: inout Bool
    ) -> [SourceHighlightSpan] {
        if !inBlockComment, isWholeLineComment(line, format: format, dialect: dialect) {
            return line.isEmpty ? [] : [span(.comment, line: lineNumber, location: 0, length: line.utf16.count)]
        }

        let palette = palette(for: format)
        let source = line as NSString
        var spans: [SourceHighlightSpan] = []
        var cursor = 0

        let wholeDirectiveRange = directiveLineRange(in: line, palette: palette)
        if let directiveRange = wholeDirectiveRange {
            spans.append(span(.directive, line: lineNumber, range: directiveRange))
        }

        while cursor < source.length {
            if inBlockComment {
                let closing = source.range(
                    of: "*/",
                    options: [],
                    range: NSRange(location: cursor, length: source.length - cursor)
                )
                if closing.location == NSNotFound {
                    spans.append(span(.comment, line: lineNumber, location: cursor, length: source.length - cursor))
                    break
                }
                let length = NSMaxRange(closing) - cursor
                spans.append(span(.comment, line: lineNumber, location: cursor, length: length))
                cursor = NSMaxRange(closing)
                inBlockComment = false
                continue
            }

            if palette.supportsBlockComments,
               cursor + 1 < source.length,
               source.character(at: cursor) == 47,
               source.character(at: cursor + 1) == 42 {
                let closing = source.range(
                    of: "*/",
                    options: [],
                    range: NSRange(location: cursor + 2, length: source.length - cursor - 2)
                )
                if closing.location == NSNotFound {
                    spans.append(span(.comment, line: lineNumber, location: cursor, length: source.length - cursor))
                    inBlockComment = true
                    break
                }
                let length = NSMaxRange(closing) - cursor
                spans.append(span(.comment, line: lineNumber, location: cursor, length: length))
                cursor = NSMaxRange(closing)
                continue
            }

            if let marker = palette.lineComment,
               sourceHas(marker, at: cursor, in: source) {
                spans.append(span(.comment, line: lineNumber, location: cursor, length: source.length - cursor))
                break
            }

            let character = source.character(at: cursor)
            if character == 39 || character == 34 {
                let start = cursor
                let quote = character
                cursor += 1
                while cursor < source.length {
                    if source.character(at: cursor) == quote {
                        if cursor + 1 < source.length, source.character(at: cursor + 1) == quote {
                            cursor += 2
                            continue
                        }
                        cursor += 1
                        break
                    }
                    cursor += 1
                }
                spans.append(span(.stringLiteral, line: lineNumber, location: start, length: cursor - start))
                continue
            }

            if isASCIIDigit(character) {
                let start = cursor
                cursor += 1
                while cursor < source.length {
                    let next = source.character(at: cursor)
                    guard isASCIIDigit(next) || next == 46 else { break }
                    cursor += 1
                }
                spans.append(span(.number, line: lineNumber, location: start, length: cursor - start))
                continue
            }

            guard isWordCharacter(character) else {
                cursor += 1
                continue
            }
            let start = cursor
            cursor += 1
            while cursor < source.length, isWordCharacter(source.character(at: cursor)) {
                cursor += 1
            }
            let token = source.substring(with: NSRange(location: start, length: cursor - start))
            if let kind = classify(token, palette: palette),
               !(kind == .directive && wholeDirectiveRange != nil) {
                spans.append(span(kind, line: lineNumber, location: start, length: cursor - start))
            }
        }

        if format == .rpgle, dialect == .rpgleColumnLimited, line.utf16.count > 5 {
            spans.append(span(.keyword, line: lineNumber, location: 5, length: 1))
        }
        return spans
    }

    static func classify(_ token: String, palette: LanguagePalette) -> SourceHighlightKind? {
        let upper = token.uppercased()
        if upper.hasPrefix("/") || palette.directives.contains(upper) { return .directive }
        if upper.hasPrefix("%") || (upper.hasPrefix("*") && upper.count > 1) { return .builtIn }
        if palette.keywords.contains(upper) { return .keyword }
        if palette.typeNames.contains(upper) { return .typeName }
        return nil
    }

    static func directiveLineRange(in line: String, palette: LanguagePalette) -> NSRange? {
        let source = line as NSString
        var start = 0
        while start < source.length,
              let scalar = UnicodeScalar(source.character(at: start)),
              CharacterSet.whitespaces.contains(scalar) {
            start += 1
        }
        guard start < source.length else { return nil }
        var end = start
        while end < source.length, isWordCharacter(source.character(at: end)) { end += 1 }
        let token = source.substring(with: NSRange(location: start, length: end - start)).uppercased()
        guard token.hasPrefix("/") || palette.directives.contains(token) else { return nil }
        return NSRange(location: start, length: source.length - start)
    }

    static func isWholeLineComment(
        _ line: String,
        format: SourceFormat,
        dialect: SourceLanguageDialect
    ) -> Bool {
        let characters = Array(line)
        switch format {
        case .rpgle:
            if dialect == .rpgleColumnLimited,
               characters.count > 6,
               characters[6] == "*" { return true }
            return line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        case .cobol:
            if characters.count > 6, characters[6] == "*" || characters[6] == "/" { return true }
            return line.trimmingCharacters(in: .whitespaces).hasPrefix("*>")
        case .dds:
            return characters.count > 6 && characters[6] == "*"
        case .sql:
            return line.trimmingCharacters(in: .whitespaces).hasPrefix("--")
        case .clle, .text:
            return false
        }
    }

    static func sourceHas(_ marker: String, at location: Int, in source: NSString) -> Bool {
        let markerLength = marker.utf16.count
        guard location + markerLength <= source.length else { return false }
        return source.substring(with: NSRange(location: location, length: markerLength)) == marker
    }

    static func isASCIIDigit(_ value: unichar) -> Bool {
        value >= 48 && value <= 57
    }

    static func isWordCharacter(_ value: unichar) -> Bool {
        if value >= 48 && value <= 57 { return true }
        if value >= 65 && value <= 90 { return true }
        if value >= 97 && value <= 122 { return true }
        return [35, 36, 37, 38, 42, 45, 47, 64, 95].contains(value)
    }

    static func span(
        _ kind: SourceHighlightKind,
        line: Int,
        location: Int,
        length: Int
    ) -> SourceHighlightSpan {
        span(kind, line: line, range: NSRange(location: location, length: max(1, length)))
    }

    static func span(
        _ kind: SourceHighlightKind,
        line: Int,
        range: NSRange
    ) -> SourceHighlightSpan {
        SourceHighlightSpan(
            kind: kind,
            range: SourceTextRange(
                startLine: line,
                startColumn: range.location + 1,
                endColumn: NSMaxRange(range) + 1
            )
        )
    }

    static func palette(for format: SourceFormat) -> LanguagePalette {
        switch format {
        case .rpgle:
            return LanguagePalette(
                keywords: rpgKeywords,
                typeNames: rpgTypes,
                directives: rpgDirectives,
                lineComment: "//",
                supportsBlockComments: false
            )
        case .clle:
            return LanguagePalette(
                keywords: clKeywords,
                typeNames: [],
                directives: [],
                lineComment: nil,
                supportsBlockComments: true
            )
        case .cobol:
            return LanguagePalette(
                keywords: cobolKeywords,
                typeNames: cobolTypes,
                directives: ["COPY"],
                lineComment: "*>",
                supportsBlockComments: false
            )
        case .dds:
            return LanguagePalette(
                keywords: ddsKeywords,
                typeNames: ddsTypes,
                directives: [],
                lineComment: nil,
                supportsBlockComments: false
            )
        case .sql:
            return LanguagePalette(
                keywords: sqlKeywords,
                typeNames: sqlTypes,
                directives: [],
                lineComment: "--",
                supportsBlockComments: true
            )
        case .text:
            return LanguagePalette(
                keywords: [],
                typeNames: [],
                directives: [],
                lineComment: nil,
                supportsBlockComments: false
            )
        }
    }

    static let rpgKeywords: Set<String> = [
        "CTL-OPT", "DCL-F", "DCL-S", "DCL-C", "DCL-DS", "END-DS", "DCL-PR", "END-PR",
        "DCL-PI", "END-PI", "DCL-PROC", "END-PROC", "IF", "ELSEIF", "ELSE", "ENDIF",
        "SELECT", "WHEN", "OTHER", "ENDSL", "DOW", "DOU", "ENDDO", "FOR", "ENDFOR",
        "MONITOR", "ON-ERROR", "ENDMON", "RETURN", "CHAIN", "SETLL", "SETGT", "READ", "READE",
        "READP", "READPE", "WRITE", "UPDATE", "DELETE", "EVAL", "EXSR", "BEGSR", "ENDSR",
        "CALLP", "DSPLY", "INZ", "QUALIFIED", "KEYED", "USAGE", "CONST", "OPTIONS", "LIKEDS",
        "LIKE", "EXTNAME", "EXTFLD", "OVERLAY", "DIM", "TEMPLATE", "STATIC", "EXPORT", "IMPORT"
    ]

    static let rpgTypes: Set<String> = [
        "CHAR", "VARCHAR", "PACKED", "ZONED", "INT", "UNS", "IND", "DATE", "TIME", "TIMESTAMP",
        "POINTER", "OBJECT", "GRAPH", "VARUCS2", "UCS2", "FLOAT", "BINARY"
    ]

    static let rpgDirectives: Set<String> = [
        "**FREE", "/COPY", "/INCLUDE", "/FREE", "/END-FREE", "/IF", "/ELSEIF", "/ELSE", "/ENDIF",
        "/DEFINE", "/UNDEFINE", "/EOF"
    ]

    static let clKeywords: Set<String> = [
        "PGM", "ENDPGM", "DCL", "DCLF", "CHGVAR", "IF", "THEN", "ELSE", "DO", "ENDDO", "CALL",
        "CALLPRC", "MONMSG", "SNDPGMMSG", "RCVMSG", "RETURN", "GOTO", "SUBR", "ENDSUBR", "OVRDBF",
        "DLTOVR", "CPYF", "SBMJOB", "RTVJOBA", "RTVSYSVAL", "CHKOBJ", "PARM"
    ]

    static let cobolKeywords: Set<String> = [
        "IDENTIFICATION", "ENVIRONMENT", "DATA", "PROCEDURE", "DIVISION", "SECTION", "PROGRAM-ID",
        "WORKING-STORAGE", "LINKAGE", "FILE", "FD", "SELECT", "ASSIGN", "COPY", "CALL", "PERFORM",
        "THRU", "UNTIL", "VARYING", "IF", "ELSE", "END-IF", "EVALUATE", "WHEN", "END-EVALUATE",
        "MOVE", "COMPUTE", "ADD", "SUBTRACT", "MULTIPLY", "DIVIDE", "DISPLAY", "ACCEPT", "OPEN",
        "CLOSE", "READ", "WRITE", "REWRITE", "DELETE", "START", "GOBACK", "STOP", "RUN", "EXIT"
    ]

    static let cobolTypes: Set<String> = [
        "PIC", "PICTURE", "COMP", "COMP-1", "COMP-2", "COMP-3", "COMP-4", "BINARY", "PACKED-DECIMAL",
        "DISPLAY", "NATIONAL", "POINTER", "INDEX"
    ]

    static let ddsKeywords: Set<String> = [
        "A", "R", "K", "PFILE", "REF", "REFFLD", "TEXT", "COLHDG", "ALIAS", "UNIQUE", "JFILE",
        "JOIN", "JFLD", "S", "O", "I", "COMP", "VALUES", "CHECK", "EDTCDE", "EDTWRD", "DSPATR",
        "COLOR", "OVERLAY", "WINDOW", "SFL", "SFLCTL", "SFLDSP", "SFLPAG", "SFLCLR"
    ]

    static let ddsTypes: Set<String> = [
        "A", "B", "F", "H", "L", "P", "S", "T", "Z", "5", "9"
    ]

    static let sqlKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "ON", "GROUP",
        "BY", "HAVING", "ORDER", "FETCH", "FIRST", "ROWS", "ONLY", "WITH", "AS", "DISTINCT", "UNION",
        "ALL", "EXCEPT", "INTERSECT", "VALUES", "INSERT", "INTO", "UPDATE", "DELETE", "MERGE", "CREATE",
        "ALTER", "DROP", "PROCEDURE", "FUNCTION", "VIEW", "TABLE", "TRIGGER", "INDEX", "CALL", "BEGIN",
        "END", "DECLARE", "SET", "IF", "THEN", "ELSE", "CASE", "WHEN", "RETURN", "LANGUAGE", "SQL",
        "RESULT", "SETS", "READS", "MODIFIES", "CONTAINS", "CURRENT", "DATE", "TIME", "TIMESTAMP",
        "NULL", "IS", "NOT", "AND", "OR", "IN", "EXISTS", "BETWEEN", "LIKE", "ESCAPE"
    ]

    static let sqlTypes: Set<String> = [
        "CHAR", "VARCHAR", "CLOB", "GRAPHIC", "VARGRAPHIC", "DBCLOB", "SMALLINT", "INTEGER", "BIGINT",
        "DECIMAL", "NUMERIC", "REAL", "DOUBLE", "DECFLOAT", "DATE", "TIME", "TIMESTAMP", "BOOLEAN",
        "BINARY", "VARBINARY", "BLOB", "XML"
    ]
}
