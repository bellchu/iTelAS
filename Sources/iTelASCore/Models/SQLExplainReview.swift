import Foundation

public enum SQLExplainStageKind: String, CaseIterable, Sendable, Identifiable {
    case source
    case join
    case filter
    case grouping
    case ordering
    case limit
    case projection

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .source: "Source"
        case .join: "Join"
        case .filter: "Filter"
        case .grouping: "Group"
        case .ordering: "Order"
        case .limit: "Limit"
        case .projection: "Return"
        }
    }
}

public struct SQLExplainStage: Equatable, Sendable, Identifiable {
    public let position: Int
    public let kind: SQLExplainStageKind
    public let title: String
    public let detail: String
    public let evidence: String

    public var id: String { "\(position)-\(kind.rawValue)" }

    public init(
        position: Int,
        kind: SQLExplainStageKind,
        title: String,
        detail: String,
        evidence: String
    ) {
        self.position = position
        self.kind = kind
        self.title = title
        self.detail = detail
        self.evidence = evidence
    }
}

public enum SQLExplainFindingSeverity: String, CaseIterable, Sendable, Identifiable {
    case ready
    case review
    case note

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ready: "READY"
        case .review: "REVIEW"
        case .note: "NOTE"
        }
    }
}

public struct SQLExplainFinding: Equatable, Sendable, Identifiable {
    public let position: Int
    public let severity: SQLExplainFindingSeverity
    public let title: String
    public let detail: String

    public var id: String { "\(position)-\(severity.rawValue)-\(title)" }

    public init(
        position: Int,
        severity: SQLExplainFindingSeverity,
        title: String,
        detail: String
    ) {
        self.position = position
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

public enum SQLExplainReviewError: Error, Equatable, LocalizedError, Sendable {
    case emptyQuery
    case queryTooLarge(maximum: Int)
    case nullByte
    case requiresSingleStatement(found: Int)
    case requiresReadOnlySyntax(SQLStatementClass)

    public var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Enter one SQL statement before opening the local review."
        case .queryTooLarge(let maximum):
            "The SQL draft exceeds the \(maximum)-byte local review limit."
        case .nullByte:
            "Binary or NUL-containing SQL cannot enter the local review."
        case .requiresSingleStatement(let found):
            "The local review accepts exactly one statement; found \(found)."
        case .requiresReadOnlySyntax(let statementClass):
            "The local review accepts read-only SQL only; statement class: \(statementClass.label)."
        }
    }
}

public struct SQLExplainReview: Equatable, Sendable, Identifiable {
    public static let boundary = "No SQL ran. This is a local static syntax review, not a Db2 optimizer explain, row estimate, access path, index recommendation, or provider receipt."

    public let fingerprint: String
    public let analysis: SQLStatementAnalysis
    public let sourceReferences: [String]
    public let stages: [SQLExplainStage]
    public let findings: [SQLExplainFinding]
    public let queryUTF8ByteCount: Int
    public let providerRowCap: Int

    public var id: String { fingerprint }

    public var shortFingerprint: String {
        "\(fingerprint.prefix(8))…\(fingerprint.suffix(4))".uppercased()
    }

    public init(
        fingerprint: String,
        analysis: SQLStatementAnalysis,
        sourceReferences: [String],
        stages: [SQLExplainStage],
        findings: [SQLExplainFinding],
        queryUTF8ByteCount: Int,
        providerRowCap: Int
    ) {
        self.fingerprint = fingerprint
        self.analysis = analysis
        self.sourceReferences = sourceReferences
        self.stages = stages
        self.findings = findings
        self.queryUTF8ByteCount = queryUTF8ByteCount
        self.providerRowCap = providerRowCap
    }

    public func summaryText() -> String {
        let sourceText = sourceReferences.isEmpty ? "unresolved" : sourceReferences.joined(separator: ",")
        let stageText = stages.map { "\($0.position).\($0.kind.rawValue)" }.joined(separator: ",")
        let findingText = findings.map { "\($0.severity.rawValue):\($0.title)" }.joined(separator: " | ")
        return [
            "ITELAS DB2 LOCAL STATIC REVIEW v1",
            "review-sha256=\(fingerprint)",
            "statement-class=\(analysis.statementClass.rawValue)",
            "statement-count=\(analysis.statementCount)",
            "source-references=\(sourceText)",
            "stages=\(stageText)",
            "provider-row-cap=\(providerRowCap)",
            "findings=\(findingText)",
            "boundary=\(Self.boundary)"
        ].joined(separator: "\n")
    }
}

public struct SQLExplainReviewBuilder: Sendable {
    public let maximumQueryUTF8Bytes: Int

    public init(maximumQueryUTF8Bytes: Int = 65_536) {
        self.maximumQueryUTF8Bytes = maximumQueryUTF8Bytes
    }

    public func build(
        sql: String,
        policy: SQLQueryPolicy = .safeDefault,
        analyzer: SQLStatementAnalyzer = SQLStatementAnalyzer()
    ) throws -> SQLExplainReview {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SQLExplainReviewError.emptyQuery }
        guard !sql.contains("\0") else { throw SQLExplainReviewError.nullByte }
        let queryUTF8ByteCount = sql.lengthOfBytes(using: .utf8)
        guard queryUTF8ByteCount <= maximumQueryUTF8Bytes else {
            throw SQLExplainReviewError.queryTooLarge(maximum: maximumQueryUTF8Bytes)
        }

        let analysis = analyzer.analyze(sql)
        guard analysis.statementCount == 1 else {
            throw SQLExplainReviewError.requiresSingleStatement(found: analysis.statementCount)
        }
        guard analysis.isSingleReadOnlyStatement else {
            throw SQLExplainReviewError.requiresReadOnlySyntax(analysis.statementClass)
        }

        let lexicon = SQLExplainLexicon(sql)
        let sources = lexicon.sourceReferences
        let stages = makeStages(analysis: analysis, sources: sources, lexicon: lexicon, policy: policy)
        let findings = makeFindings(analysis: analysis, sources: sources, lexicon: lexicon, policy: policy)
        return SQLExplainReview(
            fingerprint: AIContentFingerprint.sha256(sql),
            analysis: analysis,
            sourceReferences: sources,
            stages: stages,
            findings: findings,
            queryUTF8ByteCount: queryUTF8ByteCount,
            providerRowCap: policy.maximumRows
        )
    }

    private func makeStages(
        analysis: SQLStatementAnalysis,
        sources: [String],
        lexicon: SQLExplainLexicon,
        policy: SQLQueryPolicy
    ) -> [SQLExplainStage] {
        var stages: [(SQLExplainStageKind, String, String, String)] = []
        let sourceDetail = sources.isEmpty
            ? "No simple FROM or JOIN object was identified in local syntax."
            : "\(sources.count) local source reference\(sources.count == 1 ? "" : "s") identified."
        stages.append((.source, "Read source", sourceDetail, sources.isEmpty ? "FROM/JOIN unresolved" : sources.joined(separator: " · ")))

        if lexicon.joinCount > 0 {
            stages.append((
                .join,
                "Combine rows",
                "\(lexicon.joinCount) explicit JOIN clause\(lexicon.joinCount == 1 ? "" : "s") found.",
                "JOIN"
            ))
        }
        if lexicon.contains("WHERE") {
            stages.append((.filter, "Apply filter", "A WHERE predicate is present.", "WHERE"))
        }
        if lexicon.containsSequence(["GROUP", "BY"]) || lexicon.contains("HAVING") {
            stages.append((.grouping, "Aggregate rows", "Grouping or HAVING syntax is present.", "GROUP BY / HAVING"))
        }
        if lexicon.containsSequence(["ORDER", "BY"]) {
            stages.append((.ordering, "Order result", "An ORDER BY clause is present.", "ORDER BY"))
        }

        if let explicitLimit = analysis.explicitRowLimit {
            stages.append((
                .limit,
                "Bound output",
                "The statement requests at most \(explicitLimit) row\(explicitLimit == 1 ? "" : "s").",
                "FETCH/LIMIT \(explicitLimit)"
            ))
        } else {
            stages.append((
                .limit,
                "Provider cap",
                "A live execution would enforce the configured \(policy.maximumRows)-row ceiling.",
                "provider cap"
            ))
        }

        stages.append((.projection, "Return columns", "Projection remains a local syntax observation.", "SELECT / VALUES"))
        return stages.enumerated().map { index, stage in
            SQLExplainStage(
                position: index + 1,
                kind: stage.0,
                title: stage.1,
                detail: stage.2,
                evidence: stage.3
            )
        }
    }

    private func makeFindings(
        analysis: SQLStatementAnalysis,
        sources: [String],
        lexicon: SQLExplainLexicon,
        policy: SQLQueryPolicy
    ) -> [SQLExplainFinding] {
        var findings: [(SQLExplainFindingSeverity, String, String)] = []
        findings.append((.ready, "Read-only syntax", "One read-only statement passed the local syntax gate."))

        if sources.isEmpty {
            findings.append((.review, "Source not resolved", "A CTE, derived table, table function, or quoted identifier may hide the underlying object. Confirm it with host optimizer evidence."))
        } else {
            findings.append((.note, "Source references", "The review found \(sources.count) local source reference\(sources.count == 1 ? "" : "s"); aliases and runtime resolution remain unverified."))
        }

        if lexicon.selectsWildcard {
            findings.append((.review, "Wildcard projection", "SELECT * can widen the returned row at runtime. This local review cannot measure row width or column selectivity."))
        }
        if lexicon.joinCount > 0 {
            findings.append((.review, "Join access path unknown", "Join predicates are visible, but join order, cardinality, indexes, and optimizer choices require a provider-backed explain."))
        }
        if lexicon.containsSequence(["ORDER", "BY"]), analysis.explicitRowLimit == nil {
            findings.append((.review, "Unbounded sort surface", "ORDER BY is present without an explicit FETCH or LIMIT. A live execution still uses the configured \(policy.maximumRows)-row cap."))
        }
        if analysis.explicitRowLimit == nil {
            findings.append((.note, "Execution cap is external", "The configured \(policy.maximumRows)-row limit belongs to the execution gate; this review does not rewrite SQL."))
        } else if let explicitLimit = analysis.explicitRowLimit, explicitLimit > policy.maximumRows {
            findings.append((.review, "Requested limit exceeds policy", "The SQL requests \(explicitLimit) rows; a live provider must enforce the tighter \(policy.maximumRows)-row cap."))
        }
        if !lexicon.contains("WHERE") && !sources.isEmpty {
            findings.append((.note, "No WHERE predicate", "No WHERE keyword was found. This is not proof of a full scan; host statistics and access paths are unavailable locally."))
        }
        findings.append((.note, "Boundary", SQLExplainReview.boundary))

        return findings.enumerated().map { index, finding in
            SQLExplainFinding(
                position: index + 1,
                severity: finding.0,
                title: finding.1,
                detail: finding.2
            )
        }
    }
}

private struct SQLExplainLexicon: Sendable {
    let sanitized: String
    let tokens: [String]
    let sourceReferences: [String]

    init(_ sql: String) {
        sanitized = Self.sanitize(sql)
        tokens = Self.tokens(in: sanitized)
        sourceReferences = Self.sourceReferences(in: sanitized)
    }

    var joinCount: Int { tokens.filter { $0 == "JOIN" }.count }

    var selectsWildcard: Bool {
        guard let select = tokens.firstIndex(of: "SELECT") else { return false }
        var candidate = tokens.index(after: select)
        if candidate < tokens.endIndex, tokens[candidate] == "DISTINCT" {
            candidate = tokens.index(after: candidate)
        }
        return candidate < tokens.endIndex && tokens[candidate] == "*"
    }

    func contains(_ token: String) -> Bool { tokens.contains(token) }

    func containsSequence(_ sequence: [String]) -> Bool {
        guard tokens.count >= sequence.count else { return false }
        for index in 0...(tokens.count - sequence.count) {
            if Array(tokens[index..<(index + sequence.count)]) == sequence { return true }
        }
        return false
    }

    private static func tokens(in sql: String) -> [String] {
        sql.uppercased().split { character in
            !(character.isLetter || character.isNumber || character == "_" || character == "*")
        }
        .map(String.init)
    }

    private static func sourceReferences(in sql: String) -> [String] {
        let pattern = #"\b(?:FROM|JOIN)\s+(?:TABLE\s*\(\s*)?([A-Za-z_#$@][A-Za-z0-9_#$@]*(?:\s*\.\s*[A-Za-z_#$@][A-Za-z0-9_#$@]*){0,2})"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(sql.startIndex..., in: sql)
        var seen = Set<String>()
        var values: [String] = []
        for match in expression.matches(in: sql, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: sql) else { continue }
            let normalized = sql[valueRange]
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
            if seen.insert(normalized).inserted {
                values.append(normalized)
            }
        }
        return values
    }

    private static func sanitize(_ sql: String) -> String {
        enum State {
            case normal
            case singleQuote
            case doubleQuote
            case lineComment
            case blockComment
        }

        let characters = Array(sql)
        var state = State.normal
        var output = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            switch state {
            case .normal:
                if character == "'" {
                    state = .singleQuote
                    output.append(" ")
                } else if character == "\"" {
                    state = .doubleQuote
                    output.append(" ")
                } else if character == "-", next == "-" {
                    state = .lineComment
                    output.append(" ")
                    index += 1
                } else if character == "/", next == "*" {
                    state = .blockComment
                    output.append(" ")
                    index += 1
                } else {
                    output.append(character)
                }
            case .singleQuote:
                if character == "'", next == "'" {
                    output.append("  ")
                    index += 1
                } else if character == "'" {
                    state = .normal
                    output.append(" ")
                } else {
                    output.append(character == "\n" ? "\n" : " ")
                }
            case .doubleQuote:
                if character == "\"", next == "\"" {
                    output.append("  ")
                    index += 1
                } else if character == "\"" {
                    state = .normal
                    output.append(" ")
                } else {
                    output.append(character == "\n" ? "\n" : " ")
                }
            case .lineComment:
                if character == "\n" {
                    state = .normal
                    output.append("\n")
                } else {
                    output.append(" ")
                }
            case .blockComment:
                if character == "*", next == "/" {
                    state = .normal
                    output.append("  ")
                    index += 1
                } else {
                    output.append(character == "\n" ? "\n" : " ")
                }
            }
            index += 1
        }
        return output
    }
}
