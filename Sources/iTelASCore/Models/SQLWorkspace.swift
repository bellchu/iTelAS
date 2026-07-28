import Foundation

public enum SQLStatementClass: String, Equatable, Sendable {
    case readOnly
    case dataChange
    case definition
    case administrative
    case unknown

    public var label: String {
        switch self {
        case .readOnly: "Read only"
        case .dataChange: "Data change"
        case .definition: "Definition change"
        case .administrative: "Administrative"
        case .unknown: "Unknown"
        }
    }
}

public struct SQLStatementAnalysis: Equatable, Sendable {
    public let statementClass: SQLStatementClass
    public let statementCount: Int
    public let leadingKeyword: String?
    public let explicitRowLimit: Int?
    public let containsUpdatableCursor: Bool

    public init(
        statementClass: SQLStatementClass,
        statementCount: Int,
        leadingKeyword: String?,
        explicitRowLimit: Int?,
        containsUpdatableCursor: Bool
    ) {
        self.statementClass = statementClass
        self.statementCount = statementCount
        self.leadingKeyword = leadingKeyword
        self.explicitRowLimit = explicitRowLimit
        self.containsUpdatableCursor = containsUpdatableCursor
    }

    public var isSingleReadOnlyStatement: Bool {
        statementCount == 1 && statementClass == .readOnly && !containsUpdatableCursor
    }
}

public struct SQLStatementAnalyzer: Sendable {
    public init() {}

    public func analyze(_ sql: String) -> SQLStatementAnalysis {
        let sanitized = Self.sanitized(sql).uppercased()
        let statements = sanitized
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let tokens = Self.tokens(in: sanitized)
        let leadingKeyword = tokens.first
        let containsUpdatableCursor = Self.containsWordSequence(["FOR", "UPDATE"], in: tokens)
        let statementClass = Self.classify(
            leadingKeyword: leadingKeyword,
            tokens: tokens,
            containsUpdatableCursor: containsUpdatableCursor
        )

        return SQLStatementAnalysis(
            statementClass: statementClass,
            statementCount: statements.count,
            leadingKeyword: leadingKeyword,
            explicitRowLimit: Self.explicitRowLimit(in: sanitized),
            containsUpdatableCursor: containsUpdatableCursor
        )
    }

    private static func classify(
        leadingKeyword: String?,
        tokens: [String],
        containsUpdatableCursor: Bool
    ) -> SQLStatementClass {
        guard let leadingKeyword else { return .unknown }

        let dataChange = Set(["INSERT", "UPDATE", "DELETE", "MERGE", "REPLACE"])
        let definition = Set(["CREATE", "ALTER", "DROP", "TRUNCATE", "RENAME", "COMMENT", "LABEL"])
        let administrative = Set([
            "CALL", "SET", "GRANT", "REVOKE", "COMMIT", "ROLLBACK", "SAVEPOINT",
            "BEGIN", "DECLARE", "PREPARE", "EXECUTE", "CONNECT", "DISCONNECT", "EXPLAIN"
        ])

        if tokens.contains(where: dataChange.contains) || containsUpdatableCursor { return .dataChange }
        if tokens.contains(where: definition.contains) { return .definition }
        if administrative.contains(leadingKeyword) { return .administrative }

        switch leadingKeyword {
        case "SELECT", "VALUES":
            return .readOnly
        case "WITH":
            return tokens.contains("SELECT") || tokens.contains("VALUES") ? .readOnly : .unknown
        default:
            return .unknown
        }
    }

    private static func explicitRowLimit(in sql: String) -> Int? {
        let patterns = [
            #"\bFETCH\s+(?:FIRST|NEXT)\s+(\d+)\s+ROWS?\s+ONLY\b"#,
            #"\bLIMIT\s+(\d+)\b"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: sql,
                    range: NSRange(sql.startIndex..., in: sql)
                  ),
                  let range = Range(match.range(at: 1), in: sql),
                  let value = Int(sql[range]) else { continue }
            return value
        }
        return nil
    }

    private static func containsWordSequence(_ sequence: [String], in tokens: [String]) -> Bool {
        guard tokens.count >= sequence.count else { return false }
        for index in 0...(tokens.count - sequence.count) {
            if Array(tokens[index..<(index + sequence.count)]) == sequence { return true }
        }
        return false
    }

    private static func tokens(in sql: String) -> [String] {
        sql.split { character in
            !(character.isLetter || character.isNumber || character == "_")
        }
        .map(String.init)
    }

    private static func sanitized(_ sql: String) -> String {
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

public struct SQLQueryPolicy: Equatable, Sendable {
    public var maximumRows: Int
    public var timeoutSeconds: Int
    public var requiresSingleStatement: Bool
    public var requiresReadOnlySyntax: Bool

    public init(
        maximumRows: Int = 500,
        timeoutSeconds: Int = 30,
        requiresSingleStatement: Bool = true,
        requiresReadOnlySyntax: Bool = true
    ) {
        self.maximumRows = maximumRows
        self.timeoutSeconds = timeoutSeconds
        self.requiresSingleStatement = requiresSingleStatement
        self.requiresReadOnlySyntax = requiresReadOnlySyntax
    }

    public static let safeDefault = SQLQueryPolicy()
}

public enum SQLPreflightCheckKind: String, CaseIterable, Sendable {
    case oneStatement
    case readOnlySyntax
    case rowLimit
    case providerConnected
    case targetSelected
    case nonProductionTarget
    case timeout

    public var label: String {
        switch self {
        case .oneStatement: "One statement"
        case .readOnlySyntax: "Read-only syntax"
        case .rowLimit: "Row limit"
        case .providerConnected: "Provider connected"
        case .targetSelected: "Target selected"
        case .nonProductionTarget: "Target is non-PROD"
        case .timeout: "Time limit"
        }
    }
}

public enum SQLPreflightState: String, Equatable, Sendable {
    case ready
    case waiting
    case blocked
}

public struct SQLPreflightCheck: Equatable, Sendable, Identifiable {
    public let kind: SQLPreflightCheckKind
    public let state: SQLPreflightState
    public let detail: String

    public var id: SQLPreflightCheckKind { kind }

    public init(kind: SQLPreflightCheckKind, state: SQLPreflightState, detail: String) {
        self.kind = kind
        self.state = state
        self.detail = detail
    }
}

public struct SQLExecutionContext: Equatable, Sendable {
    public var providerConnected: Bool
    public var targetName: String?
    public var environment: IBMEnvironment?

    public init(
        providerConnected: Bool,
        targetName: String? = nil,
        environment: IBMEnvironment? = nil
    ) {
        self.providerConnected = providerConnected
        self.targetName = targetName
        self.environment = environment
    }
}

public struct SQLExecutionPreflight: Equatable, Sendable {
    public let analysis: SQLStatementAnalysis
    public let checks: [SQLPreflightCheck]

    public init(
        sql: String,
        policy: SQLQueryPolicy = .safeDefault,
        context: SQLExecutionContext,
        analyzer: SQLStatementAnalyzer = SQLStatementAnalyzer()
    ) {
        analysis = analyzer.analyze(sql)
        let rowLimitDetail: String = if let explicit = analysis.explicitRowLimit {
            explicit <= policy.maximumRows
                ? "The query caps output at \(explicit) row(s)."
                : "The provider must cap \(explicit) requested rows to \(policy.maximumRows)."
        } else {
            "The provider must enforce a \(policy.maximumRows)-row maximum."
        }

        let environmentState: SQLPreflightState = switch context.environment {
        case .production: .blocked
        case .development, .qualityAssurance, .staging: .ready
        case nil: .waiting
        }
        let environmentDetail: String = switch context.environment {
        case .production: "Production execution requires a separate reviewed workflow."
        case .development, .qualityAssurance, .staging: "The selected environment is not production."
        case nil: "Select a target environment."
        }

        checks = [
            SQLPreflightCheck(
                kind: .oneStatement,
                state: !policy.requiresSingleStatement || analysis.statementCount == 1 ? .ready : .blocked,
                detail: analysis.statementCount == 1
                    ? "Exactly one statement was found."
                    : "Found \(analysis.statementCount) statements; split the script before execution."
            ),
            SQLPreflightCheck(
                kind: .readOnlySyntax,
                state: !policy.requiresReadOnlySyntax || analysis.isSingleReadOnlyStatement ? .ready : .blocked,
                detail: analysis.isSingleReadOnlyStatement
                    ? "The statement has read-only syntax."
                    : "Statement class: \(analysis.statementClass.label)."
            ),
            SQLPreflightCheck(
                kind: .rowLimit,
                state: policy.maximumRows > 0 ? .ready : .blocked,
                detail: rowLimitDetail
            ),
            SQLPreflightCheck(
                kind: .providerConnected,
                state: context.providerConnected ? .ready : .blocked,
                detail: context.providerConnected ? "The Db2 provider is available." : "Connect a trusted Db2 provider."
            ),
            SQLPreflightCheck(
                kind: .targetSelected,
                state: context.targetName?.isEmpty == false ? .ready : .waiting,
                detail: context.targetName ?? "Select a target system before execution."
            ),
            SQLPreflightCheck(
                kind: .nonProductionTarget,
                state: environmentState,
                detail: environmentDetail
            ),
            SQLPreflightCheck(
                kind: .timeout,
                state: policy.timeoutSeconds > 0 ? .ready : .blocked,
                detail: "The provider must stop after \(policy.timeoutSeconds) seconds."
            )
        ]
    }

    public var isReady: Bool { checks.allSatisfy { $0.state == .ready } }
}

public struct IBMServiceQuery: Hashable, Sendable, Identifiable {
    public enum Category: String, CaseIterable, Sendable {
        case jobs = "Jobs"
        case locks = "Locks"
        case output = "Output"
        case system = "System"
    }

    public let id: String
    public let title: String
    public let serviceName: String
    public let category: Category
    public let summary: String
    public let sql: String

    public init(
        id: String,
        title: String,
        serviceName: String,
        category: Category,
        summary: String,
        sql: String
    ) {
        self.id = id
        self.title = title
        self.serviceName = serviceName
        self.category = category
        self.summary = summary
        self.sql = sql
    }
}

public enum IBMIServicesCatalog {
    public static let queries: [IBMServiceQuery] = [
        IBMServiceQuery(
            id: "active-jobs-cpu",
            title: "Active jobs by CPU",
            serviceName: "QSYS2.ACTIVE_JOB_INFO",
            category: .jobs,
            summary: "CPU, temporary storage, and current SQL context.",
            sql: """
            SELECT JOB_NAME,
                   AUTHORIZATION_NAME,
                   ELAPSED_CPU_PERCENTAGE,
                   TEMPORARY_STORAGE,
                   SQL_STATEMENT_TEXT
              FROM TABLE(QSYS2.ACTIVE_JOB_INFO(
                     DETAILED_INFO => 'ALL')) AS JOBS
             WHERE JOB_TYPE <> 'SYS'
             ORDER BY ELAPSED_CPU_PERCENTAGE DESC
             FETCH FIRST 500 ROWS ONLY;
            """
        ),
        IBMServiceQuery(
            id: "object-locks",
            title: "Object lock holders",
            serviceName: "QSYS2.OBJECT_LOCK_INFO",
            category: .locks,
            summary: "Objects, members, holder jobs, and lock states.",
            sql: """
            SELECT SYSTEM_OBJECT_SCHEMA,
                   SYSTEM_OBJECT_NAME,
                   SYSTEM_TABLE_MEMBER,
                   OBJECT_TYPE,
                   JOB_NAME,
                   LOCK_STATE
              FROM QSYS2.OBJECT_LOCK_INFO
             ORDER BY SYSTEM_OBJECT_SCHEMA, SYSTEM_OBJECT_NAME
             FETCH FIRST 500 ROWS ONLY;
            """
        ),
        IBMServiceQuery(
            id: "ifs-object-locks",
            title: "IFS object locks",
            serviceName: "QSYS2.IFS_OBJECT_LOCK_INFO",
            category: .locks,
            summary: "Jobs holding references or locks on one IFS path.",
            sql: """
            SELECT PATH_NAME,
                   JOB_NAME,
                   RO_COUNT,
                   WO_COUNT,
                   RW_COUNT,
                   SHARE_NONE_COUNT
              FROM TABLE(QSYS2.IFS_OBJECT_LOCK_INFO(
                     PATH_NAME => '/path/to/object',
                     IGNORE_ERRORS => 'YES')) AS LOCKS
             FETCH FIRST 500 ROWS ONLY;
            """
        ),
        IBMServiceQuery(
            id: "spooled-output",
            title: "Spooled output",
            serviceName: "QSYS2.OUTPUT_QUEUE_ENTRIES",
            category: .output,
            summary: "Spooled files in a named output queue.",
            sql: """
            SELECT CREATE_TIMESTAMP,
                   SPOOLED_FILE_NAME,
                   USER_NAME,
                   USER_DATA,
                   STATUS
              FROM TABLE(QSYS2.OUTPUT_QUEUE_ENTRIES(
                     '*LIBL', 'QEZJOBLOG', 'NO')) AS OUTPUT
             ORDER BY CREATE_TIMESTAMP DESC
             FETCH FIRST 500 ROWS ONLY;
            """
        ),
        IBMServiceQuery(
            id: "system-status",
            title: "System status",
            serviceName: "QSYS2.SYSTEM_STATUS_INFO",
            category: .system,
            summary: "Partition CPU, job, storage, and system status.",
            sql: """
            SELECT *
              FROM QSYS2.SYSTEM_STATUS_INFO
             FETCH FIRST 1 ROW ONLY;
            """
        ),
        IBMServiceQuery(
            id: "asp-capacity",
            title: "ASP capacity",
            serviceName: "QSYS2.ASP_INFO",
            category: .system,
            summary: "ASP status, capacity, and mirroring metadata.",
            sql: """
            SELECT *
              FROM QSYS2.ASP_INFO
             ORDER BY ASP_NUMBER
             FETCH FIRST 100 ROWS ONLY;
            """
        )
    ]
}

public enum SQLValue: Equatable, Sendable {
    case null
    case string(String)
    case integer(Int64)
    case decimal(String)
    case date(Date)
    case timestamp(Date)
    case boolean(Bool)
    case binary(Data)
}

public struct SQLColumn: Equatable, Sendable {
    public let name: String
    public let databaseType: String
    public let isNullable: Bool
    public let ccsid: Int?

    public init(name: String, databaseType: String, isNullable: Bool, ccsid: Int? = nil) {
        self.name = name
        self.databaseType = databaseType
        self.isNullable = isNullable
        self.ccsid = ccsid
    }
}

public struct SQLResult: Equatable, Sendable {
    public let columns: [SQLColumn]
    public let rows: [[SQLValue]]
    public let targetName: String
    public let startedAt: Date
    public let elapsedMilliseconds: Int
    public let wasTruncated: Bool

    public init(
        columns: [SQLColumn],
        rows: [[SQLValue]],
        targetName: String,
        startedAt: Date,
        elapsedMilliseconds: Int,
        wasTruncated: Bool
    ) {
        self.columns = columns
        self.rows = rows
        self.targetName = targetName
        self.startedAt = startedAt
        self.elapsedMilliseconds = elapsedMilliseconds
        self.wasTruncated = wasTruncated
    }
}

public struct SQLExecutionRequest: Equatable, Sendable {
    public let sql: String
    public let maximumRows: Int
    public let timeoutSeconds: Int
    public let readOnly: Bool

    public init(sql: String, maximumRows: Int, timeoutSeconds: Int, readOnly: Bool) {
        self.sql = sql
        self.maximumRows = maximumRows
        self.timeoutSeconds = timeoutSeconds
        self.readOnly = readOnly
    }
}

public protocol DatabaseProvider: Sendable {
    var providerName: String { get }
    var targetName: String { get }
    var environment: IBMEnvironment { get }
    func execute(_ request: SQLExecutionRequest) async throws -> SQLResult
}
