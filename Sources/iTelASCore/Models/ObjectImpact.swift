import Foundation

public struct ObjectImpactLimits: Equatable, Sendable {
    public var maximumEdgesPerSource: Int
    public var queryTimeoutSeconds: Int

    public init(maximumEdgesPerSource: Int = 100, queryTimeoutSeconds: Int = 30) {
        self.maximumEdgesPerSource = maximumEdgesPerSource
        self.queryTimeoutSeconds = queryTimeoutSeconds
    }

    public static let standard = ObjectImpactLimits()
}

public enum ObjectImpactError: Error, Equatable, LocalizedError, Sendable {
    case duplicateColumn(source: String, column: String)
    case missingColumn(source: String, column: String)
    case malformedRow(source: String, index: Int)
    case tooManyRows(source: String, maximum: Int)
    case unexpectedRowCount(source: String, expectedAtMost: Int, actual: Int)
    case truncatedSingleton(source: String)
    case identityMismatch(source: String)
    case invalidValue(source: String, index: Int, column: String)
    case invalidText(source: String, index: Int, column: String)

    public var errorDescription: String? {
        switch self {
        case .duplicateColumn(let source, let column):
            "The \(source) result contains an ambiguous duplicate \(column) column."
        case .missingColumn(let source, let column):
            "The \(source) result does not contain the required \(column) column."
        case .malformedRow(let source, let index):
            "The \(source) result row \(index) does not match its column layout."
        case .tooManyRows(let source, let maximum):
            "The \(source) result exceeds the \(maximum)-row evidence limit."
        case .unexpectedRowCount(let source, let expectedAtMost, let actual):
            "The \(source) result returned \(actual) rows; at most \(expectedAtMost) were expected."
        case .truncatedSingleton(let source):
            "The exact-object \(source) result reached its transport bound and is ambiguous."
        case .identityMismatch(let source):
            "The \(source) result did not describe the requested exact object identity."
        case .invalidValue(let source, let index, let column):
            "The \(source) result row \(index) contains an invalid \(column) value."
        case .invalidText(let source, let index, let column):
            "The \(source) result row \(index) contains unsafe or oversized \(column) text."
        }
    }
}

public enum IBMObjectType: String, CaseIterable, Codable, Identifiable, Sendable {
    case program = "*PGM"
    case serviceProgram = "*SRVPGM"
    case module = "*MODULE"
    case file = "*FILE"
    case bindingDirectory = "*BNDDIR"
    case command = "*CMD"
    case dataArea = "*DTAARA"
    case dataQueue = "*DTAQ"
    case jobQueue = "*JOBQ"
    case outputQueue = "*OUTQ"
    case journal = "*JRN"
    case journalReceiver = "*JRNRCV"

    public var id: String { rawValue }
}

public struct IBMObjectIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let library: IBMSystemObjectName
    public let name: IBMSystemObjectName
    public let type: IBMObjectType

    public init(library: String, name: String, type: IBMObjectType) throws {
        self.library = try IBMSystemObjectName(library)
        self.name = try IBMSystemObjectName(name)
        self.type = type
    }

    public init(library: IBMSystemObjectName, name: IBMSystemObjectName, type: IBMObjectType) {
        self.library = library
        self.name = name
        self.type = type
    }

    public var description: String { "\(library.value)/\(name.value) \(type.rawValue)" }
}

public struct ObjectImpactNode: Hashable, Sendable, Identifiable {
    public let library: String
    public let name: String
    public let type: String

    public var id: String { "\(library)\u{1F}\(name)\u{1F}\(type)" }
    public var qualifiedName: String { "\(library)/\(name)" }
    public var label: String { "\(qualifiedName) \(type)" }

    public init(library: String, name: String, type: String) throws {
        self.library = try Self.validated(library, maximum: 128)
        self.name = try Self.validated(name, maximum: 128)
        self.type = try Self.validated(type, maximum: 32)
    }

    public init(_ identity: IBMObjectIdentity) {
        library = identity.library.value
        name = identity.name.value
        type = identity.type.rawValue
    }

    private static func validated(_ value: String, maximum: Int) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maximum,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ObjectImpactError.invalidText(source: "OBJECT IDENTITY", index: 1, column: "IDENTITY")
        }
        return trimmed
    }
}

public struct ObjectImpactMetadata: Equatable, Sendable {
    public let identity: IBMObjectIdentity
    public let owner: String?
    public let attribute: String?
    public let text: String?
    public let sizeBytes: Int64?
    public let createdAt: Date?
    public let changedAt: Date?
    public let lastUsedAt: Date?
    public let sourceLibrary: String?
    public let sourceFile: String?
    public let sourceMember: String?
    public let sourceChangedAt: Date?
    public let sqlObjectType: String?

    public init(
        identity: IBMObjectIdentity,
        owner: String?,
        attribute: String?,
        text: String?,
        sizeBytes: Int64?,
        createdAt: Date?,
        changedAt: Date?,
        lastUsedAt: Date?,
        sourceLibrary: String?,
        sourceFile: String?,
        sourceMember: String?,
        sourceChangedAt: Date?,
        sqlObjectType: String?
    ) {
        self.identity = identity
        self.owner = owner
        self.attribute = attribute
        self.text = text
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.changedAt = changedAt
        self.lastUsedAt = lastUsedAt
        self.sourceLibrary = sourceLibrary
        self.sourceFile = sourceFile
        self.sourceMember = sourceMember
        self.sourceChangedAt = sourceChangedAt
        self.sqlObjectType = sqlObjectType
    }
}

public enum ObjectImpactEvidenceClass: String, CaseIterable, Sendable {
    case bound
    case catalog
    case candidate

    public var label: String { rawValue.uppercased() }
}

public enum ObjectImpactEdgeDirection: String, Sendable {
    case incoming
    case outgoing

    public var label: String { rawValue.uppercased() }
}

public enum ObjectImpactEvidenceSource: String, CaseIterable, Sendable {
    case objectStatistics = "OBJECT_STATISTICS"
    case boundServiceProgramInfo = "BOUND_SRVPGM_INFO"
    case boundModuleInfo = "BOUND_MODULE_INFO"
    case bindingDirectoryInfo = "BINDING_DIRECTORY_INFO"
    case sysroutines = "SYSROUTINES"
    case sysviewdep = "SYSVIEWDEP"
    case programReferences = "PROGRAM_REFERENCES"

    public static let liveSQLSources: [Self] = [
        .objectStatistics,
        .boundServiceProgramInfo,
        .boundModuleInfo,
        .bindingDirectoryInfo,
        .sysroutines,
        .sysviewdep
    ]
}

public struct ObjectImpactEdge: Equatable, Sendable, Identifiable {
    public let direction: ObjectImpactEdgeDirection
    public let from: ObjectImpactNode
    public let to: ObjectImpactNode
    public let evidenceClass: ObjectImpactEvidenceClass
    public let source: ObjectImpactEvidenceSource
    public let detail: String?

    public var id: String {
        [direction.rawValue, from.id, to.id, evidenceClass.rawValue, source.rawValue, detail ?? ""]
            .joined(separator: "\u{1E}")
    }

    public init(
        direction: ObjectImpactEdgeDirection,
        from: ObjectImpactNode,
        to: ObjectImpactNode,
        evidenceClass: ObjectImpactEvidenceClass,
        source: ObjectImpactEvidenceSource,
        detail: String? = nil
    ) {
        self.direction = direction
        self.from = from
        self.to = to
        self.evidenceClass = evidenceClass
        self.source = source
        self.detail = detail
    }
}

public enum ObjectImpactEvidenceOutcome: Equatable, Sendable {
    case collected
    case unavailable(String)

    public var isCollected: Bool {
        if case .collected = self { return true }
        return false
    }
}

public struct ObjectImpactEvidenceReceipt: Equatable, Sendable, Identifiable {
    public let source: ObjectImpactEvidenceSource
    public let rowCount: Int
    public let boundWasReached: Bool
    public let elapsedMilliseconds: Int?
    public let queryFingerprint: String
    public let outcome: ObjectImpactEvidenceOutcome

    public var id: ObjectImpactEvidenceSource { source }

    public init(
        source: ObjectImpactEvidenceSource,
        rowCount: Int,
        boundWasReached: Bool,
        elapsedMilliseconds: Int?,
        queryFingerprint: String,
        outcome: ObjectImpactEvidenceOutcome
    ) {
        self.source = source
        self.rowCount = rowCount
        self.boundWasReached = boundWasReached
        self.elapsedMilliseconds = elapsedMilliseconds
        self.queryFingerprint = queryFingerprint
        self.outcome = outcome
    }
}

public struct ObjectImpactSnapshot: Equatable, Sendable {
    public let targetName: String
    public let target: IBMObjectIdentity
    public let capturedAt: Date
    public let metadata: ObjectImpactMetadata?
    public let edges: [ObjectImpactEdge]
    public let receipts: [ObjectImpactEvidenceReceipt]
    public let isBundledReplay: Bool

    public init(
        targetName: String,
        target: IBMObjectIdentity,
        capturedAt: Date,
        metadata: ObjectImpactMetadata?,
        edges: [ObjectImpactEdge],
        receipts: [ObjectImpactEvidenceReceipt],
        isBundledReplay: Bool = false
    ) {
        self.targetName = targetName
        self.target = target
        self.capturedAt = capturedAt
        self.metadata = metadata
        var uniqueEdges: [String: ObjectImpactEdge] = [:]
        for edge in edges { uniqueEdges[edge.id] = edge }
        self.edges = Array(uniqueEdges.values).sorted {
            if $0.direction != $1.direction { return $0.direction.rawValue < $1.direction.rawValue }
            if $0.evidenceClass != $1.evidenceClass { return $0.evidenceClass.rawValue < $1.evidenceClass.rawValue }
            return $0.id < $1.id
        }
        self.receipts = receipts.sorted {
            let order = ObjectImpactEvidenceSource.allCases
            return (order.firstIndex(of: $0.source) ?? order.endIndex)
                < (order.firstIndex(of: $1.source) ?? order.endIndex)
        }
        self.isBundledReplay = isBundledReplay
    }

    public var incomingEdges: [ObjectImpactEdge] { edges.filter { $0.direction == .incoming } }
    public var outgoingEdges: [ObjectImpactEdge] { edges.filter { $0.direction == .outgoing } }
    public var gaps: [ObjectImpactEvidenceReceipt] { receipts.filter { !$0.outcome.isCollected } }
    public var assessment: ObjectImpactAssessment { ObjectImpactAssessment(snapshot: self) }
}

public struct ObjectImpactAssessment: Equatable, Sendable {
    public let incomingCount: Int
    public let outgoingCount: Int
    public let boundCount: Int
    public let catalogCount: Int
    public let candidateCount: Int
    public let gapCount: Int
    public let boundReachedCount: Int
    public let verdict: String
    public let method: String

    public init(snapshot: ObjectImpactSnapshot) {
        incomingCount = snapshot.incomingEdges.count
        outgoingCount = snapshot.outgoingEdges.count
        boundCount = snapshot.edges.filter { $0.evidenceClass == .bound }.count
        catalogCount = snapshot.edges.filter { $0.evidenceClass == .catalog }.count
        candidateCount = snapshot.edges.filter { $0.evidenceClass == .candidate }.count
        gapCount = snapshot.gaps.count
        boundReachedCount = snapshot.receipts.filter(\.boundWasReached).count
        verdict = "REVIEW REQUIRED"
        method = "Direct, bounded evidence only. BOUND is executable binding evidence; CATALOG is a catalog registration or dependency; CANDIDATE is not proof of use. Returned endpoint tokens are preserved exactly, including unresolved *LIBL references. Missing rows never prove absence because authority and collection bounds can hide relationships. No runtime frequency, transitive reachability, or safe-change conclusion is inferred."
    }
}

public struct ObjectImpactSQLPlanner: Sendable {
    public let target: IBMObjectIdentity
    public let limits: ObjectImpactLimits

    public init(target: IBMObjectIdentity, limits: ObjectImpactLimits = .standard) {
        self.target = target
        self.limits = limits
    }

    public var objectStatistics: SQLExecutionRequest {
        request("""
        SELECT OBJNAME,
               OBJTYPE,
               OBJLIB,
               OBJOWNER,
               OBJATTRIBUTE,
               OBJTEXT,
               OBJSIZE,
               OBJCREATED,
               CHANGE_TIMESTAMP,
               LAST_USED_TIMESTAMP,
               SOURCE_LIBRARY,
               SOURCE_FILE,
               SOURCE_MEMBER,
               SOURCE_TIMESTAMP,
               SQL_OBJECT_TYPE
          FROM TABLE(QSYS2.OBJECT_STATISTICS(
                   '\(library)', '\(target.type.rawValue)', '\(name)'
               )) AS O
         FETCH FIRST 2 ROWS ONLY
        """, maximumRows: 1)
    }

    public var boundServicePrograms: SQLExecutionRequest {
        let consumerGuard = target.type == .program || target.type == .serviceProgram ? "1 = 1" : "1 = 0"
        let inboundGuard = target.type == .serviceProgram ? "1 = 1" : "1 = 0"
        return request("""
        SELECT 'OUTGOING' AS EDGE_DIRECTION,
               PROGRAM_LIBRARY AS FROM_LIBRARY,
               PROGRAM_NAME AS FROM_NAME,
               OBJECT_TYPE AS FROM_TYPE,
               BOUND_SERVICE_PROGRAM_LIBRARY AS TO_LIBRARY,
               BOUND_SERVICE_PROGRAM AS TO_NAME,
               '*SRVPGM' AS TO_TYPE,
               BOUND_SERVICE_PROGRAM_ACTIVATION AS ACTIVATION
          FROM QSYS2.BOUND_SRVPGM_INFO
         WHERE \(consumerGuard)
           AND PROGRAM_LIBRARY = '\(library)'
           AND PROGRAM_NAME = '\(name)'
        UNION ALL
        SELECT 'INCOMING' AS EDGE_DIRECTION,
               PROGRAM_LIBRARY AS FROM_LIBRARY,
               PROGRAM_NAME AS FROM_NAME,
               OBJECT_TYPE AS FROM_TYPE,
               BOUND_SERVICE_PROGRAM_LIBRARY AS TO_LIBRARY,
               BOUND_SERVICE_PROGRAM AS TO_NAME,
               '*SRVPGM' AS TO_TYPE,
               BOUND_SERVICE_PROGRAM_ACTIVATION AS ACTIVATION
          FROM QSYS2.BOUND_SRVPGM_INFO
         WHERE \(inboundGuard)
           AND BOUND_SERVICE_PROGRAM_LIBRARY = '\(library)'
           AND BOUND_SERVICE_PROGRAM = '\(name)'
         ORDER BY 1, 2, 3, 5, 6
         FETCH FIRST \(limits.maximumEdgesPerSource + 1) ROWS ONLY
        """)
    }

    public var boundModules: SQLExecutionRequest {
        let consumerGuard = target.type == .program || target.type == .serviceProgram ? "1 = 1" : "1 = 0"
        return request("""
        SELECT 'OUTGOING' AS EDGE_DIRECTION,
               PROGRAM_LIBRARY AS FROM_LIBRARY,
               PROGRAM_NAME AS FROM_NAME,
               OBJECT_TYPE AS FROM_TYPE,
               COALESCE(BOUND_MODULE_LIBRARY, '*INTERNAL') AS TO_LIBRARY,
               BOUND_MODULE AS TO_NAME,
               '*MODULE' AS TO_TYPE,
               MODULE_ATTRIBUTE,
               SOURCE_FILE_LIBRARY,
               SOURCE_FILE,
               SOURCE_FILE_MEMBER,
               SOURCE_STREAM_FILE_PATH,
               MODULE_CREATE_TIMESTAMP,
               SOURCE_CHANGE_TIMESTAMP
          FROM QSYS2.BOUND_MODULE_INFO
         WHERE \(consumerGuard)
           AND PROGRAM_LIBRARY = '\(library)'
           AND PROGRAM_NAME = '\(name)'
         ORDER BY BOUND_MODULE_LIBRARY, BOUND_MODULE
         FETCH FIRST \(limits.maximumEdgesPerSource + 1) ROWS ONLY
        """)
    }

    public var bindingDirectories: SQLExecutionRequest {
        request("""
        SELECT 'INCOMING' AS EDGE_DIRECTION,
               BINDING_DIRECTORY_LIBRARY AS FROM_LIBRARY,
               BINDING_DIRECTORY AS FROM_NAME,
               '*BNDDIR' AS FROM_TYPE,
               ENTRY_LIBRARY AS TO_LIBRARY,
               ENTRY AS TO_NAME,
               ENTRY_TYPE AS TO_TYPE,
               ENTRY_ACTIVATION
          FROM QSYS2.BINDING_DIRECTORY_INFO
         WHERE ENTRY_LIBRARY = '\(library)'
           AND ENTRY = '\(name)'
           AND ENTRY_TYPE = '\(target.type.rawValue)'
         ORDER BY BINDING_DIRECTORY_LIBRARY, BINDING_DIRECTORY
         FETCH FIRST \(limits.maximumEdgesPerSource + 1) ROWS ONLY
        """)
    }

    public var sqlRoutines: SQLExecutionRequest {
        let executableGuard = target.type == .program || target.type == .serviceProgram ? "1 = 1" : "1 = 0"
        return request("""
        SELECT 'INCOMING' AS EDGE_DIRECTION,
               ROUTINE_SCHEMA AS FROM_LIBRARY,
               ROUTINE_NAME AS FROM_NAME,
               ROUTINE_TYPE AS FROM_TYPE,
               '\(library)' AS TO_LIBRARY,
               '\(name)' AS TO_NAME,
               '\(target.type.rawValue)' AS TO_TYPE,
               EXTERNAL_NAME,
               EXTERNAL_LANGUAGE,
               SQL_DATA_ACCESS
          FROM QSYS2.SYSROUTINES
         WHERE ROUTINE_BODY = 'EXTERNAL'
           AND \(executableGuard)
           AND (UPPER(EXTERNAL_NAME) = '\(library)/\(name)'
                OR UPPER(EXTERNAL_NAME) LIKE '\(library)/\(name)(%')
         ORDER BY ROUTINE_SCHEMA, ROUTINE_NAME
         FETCH FIRST \(limits.maximumEdgesPerSource + 1) ROWS ONLY
        """)
    }

    public var viewDependencies: SQLExecutionRequest {
        let fileGuard = target.type == .file ? "1 = 1" : "1 = 0"
        return request("""
        SELECT 'INCOMING' AS EDGE_DIRECTION,
               SYSTEM_VIEW_SCHEMA AS FROM_LIBRARY,
               SYSTEM_VIEW_NAME AS FROM_NAME,
               '*FILE' AS FROM_TYPE,
               '\(library)' AS TO_LIBRARY,
               '\(name)' AS TO_NAME,
               '*FILE' AS TO_TYPE,
               VIEW_SCHEMA,
               VIEW_NAME,
               OBJECT_TYPE
          FROM QSYS2.SYSVIEWDEP
         WHERE \(fileGuard)
           AND SYSTEM_TABLE_SCHEMA = '\(library)'
           AND SYSTEM_TABLE_NAME = '\(name)'
        UNION ALL
        SELECT 'OUTGOING' AS EDGE_DIRECTION,
               '\(library)' AS FROM_LIBRARY,
               '\(name)' AS FROM_NAME,
               '*FILE' AS FROM_TYPE,
               COALESCE(SYSTEM_TABLE_SCHEMA, OBJECT_SCHEMA) AS TO_LIBRARY,
               COALESCE(SYSTEM_TABLE_NAME, OBJECT_NAME) AS TO_NAME,
               OBJECT_TYPE AS TO_TYPE,
               VIEW_SCHEMA,
               VIEW_NAME,
               OBJECT_TYPE
          FROM QSYS2.SYSVIEWDEP
         WHERE \(fileGuard)
           AND SYSTEM_VIEW_SCHEMA = '\(library)'
           AND SYSTEM_VIEW_NAME = '\(name)'
         ORDER BY 1, 2, 3, 5, 6
         FETCH FIRST \(limits.maximumEdgesPerSource + 1) ROWS ONLY
        """)
    }

    public var liveRequests: [(ObjectImpactEvidenceSource, SQLExecutionRequest)] {
        [
            (.objectStatistics, objectStatistics),
            (.boundServiceProgramInfo, boundServicePrograms),
            (.boundModuleInfo, boundModules),
            (.bindingDirectoryInfo, bindingDirectories),
            (.sysroutines, sqlRoutines),
            (.sysviewdep, viewDependencies)
        ]
    }

    private var library: String { target.library.value }
    private var name: String { target.name.value }

    private func request(_ sql: String, maximumRows: Int? = nil) -> SQLExecutionRequest {
        SQLExecutionRequest(
            sql: sql,
            maximumRows: maximumRows ?? limits.maximumEdgesPerSource,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }
}

public struct ObjectImpactSQLDecoder: Sendable {
    public let limits: ObjectImpactLimits

    public init(limits: ObjectImpactLimits = .standard) {
        self.limits = limits
    }

    public func decodeMetadata(_ result: SQLResult, target: IBMObjectIdentity) throws -> ObjectImpactMetadata? {
        let source = ObjectImpactEvidenceSource.objectStatistics.rawValue
        let required = [
            "OBJNAME", "OBJTYPE", "OBJLIB", "OBJOWNER", "OBJATTRIBUTE", "OBJTEXT", "OBJSIZE",
            "OBJCREATED", "CHANGE_TIMESTAMP", "LAST_USED_TIMESTAMP", "SOURCE_LIBRARY", "SOURCE_FILE",
            "SOURCE_MEMBER", "SOURCE_TIMESTAMP", "SQL_OBJECT_TYPE"
        ]
        try validate(result, source: source, required: required, maximumRows: 1)
        guard !result.wasTruncated else { throw ObjectImpactError.truncatedSingleton(source: source) }
        guard result.rows.count <= 1 else {
            throw ObjectImpactError.unexpectedRowCount(source: source, expectedAtMost: 1, actual: result.rows.count)
        }
        guard !result.rows.isEmpty else { return nil }
        let row = try ImpactSQLRow(result: result, source: source, rowIndex: 1)
        let returnedType = normalizeObjectType(try row.requiredText("OBJTYPE", maximum: 8))
        guard try row.requiredText("OBJLIB", maximum: 10).uppercased() == target.library.value,
              try row.requiredText("OBJNAME", maximum: 10).uppercased() == target.name.value,
              returnedType == target.type.rawValue else {
            throw ObjectImpactError.identityMismatch(source: source)
        }
        let size = try row.optionalInt64("OBJSIZE")
        if let size, size < 0 {
            throw ObjectImpactError.invalidValue(source: source, index: 1, column: "OBJSIZE")
        }
        return ObjectImpactMetadata(
            identity: target,
            owner: try row.optionalText("OBJOWNER", maximum: 10),
            attribute: try row.optionalText("OBJATTRIBUTE", maximum: 10),
            text: try row.optionalText("OBJTEXT", maximum: 50),
            sizeBytes: size,
            createdAt: try row.optionalDate("OBJCREATED"),
            changedAt: try row.optionalDate("CHANGE_TIMESTAMP"),
            lastUsedAt: try row.optionalDate("LAST_USED_TIMESTAMP"),
            sourceLibrary: try row.optionalText("SOURCE_LIBRARY", maximum: 10),
            sourceFile: try row.optionalText("SOURCE_FILE", maximum: 10),
            sourceMember: try row.optionalText("SOURCE_MEMBER", maximum: 10),
            sourceChangedAt: try row.optionalDate("SOURCE_TIMESTAMP"),
            sqlObjectType: try row.optionalText("SQL_OBJECT_TYPE", maximum: 24)
        )
    }

    public func decodeBoundServicePrograms(_ result: SQLResult) throws -> [ObjectImpactEdge] {
        try decodeEdges(
            result,
            source: .boundServiceProgramInfo,
            evidenceClass: .bound,
            requiredDetailColumns: ["ACTIVATION"]
        ) { row in
            try row.optionalText("ACTIVATION", maximum: 10)
        }
    }

    public func decodeBoundModules(_ result: SQLResult) throws -> [ObjectImpactEdge] {
        try decodeEdges(
            result,
            source: .boundModuleInfo,
            evidenceClass: .bound,
            requiredDetailColumns: [
                "MODULE_ATTRIBUTE", "SOURCE_FILE_LIBRARY", "SOURCE_FILE", "SOURCE_FILE_MEMBER",
                "SOURCE_STREAM_FILE_PATH", "MODULE_CREATE_TIMESTAMP", "SOURCE_CHANGE_TIMESTAMP"
            ]
        ) { row in
            let attribute = try row.optionalText("MODULE_ATTRIBUTE", maximum: 10)
            let sourceLibrary = try row.optionalText("SOURCE_FILE_LIBRARY", maximum: 10)
            let sourceFile = try row.optionalText("SOURCE_FILE", maximum: 10)
            let sourceMember = try row.optionalText("SOURCE_FILE_MEMBER", maximum: 10)
            let streamFile = try row.optionalText("SOURCE_STREAM_FILE_PATH", maximum: 5_000)
            let sourceLabel: String? = if let sourceLibrary, let sourceFile, let sourceMember {
                "\(sourceLibrary)/\(sourceFile)(\(sourceMember))"
            } else {
                streamFile
            }
            return [attribute, sourceLabel].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        }
    }

    public func decodeBindingDirectories(_ result: SQLResult) throws -> [ObjectImpactEdge] {
        try decodeEdges(
            result,
            source: .bindingDirectoryInfo,
            evidenceClass: .candidate,
            requiredDetailColumns: ["ENTRY_ACTIVATION"]
        ) { row in
            let activation = try row.optionalText("ENTRY_ACTIVATION", maximum: 10)
            return ["Build-time candidate", activation].compactMap { $0 }.joined(separator: " · ")
        }
    }

    public func decodeSQLRoutines(_ result: SQLResult) throws -> [ObjectImpactEdge] {
        try decodeEdges(
            result,
            source: .sysroutines,
            evidenceClass: .catalog,
            requiredDetailColumns: ["EXTERNAL_NAME", "EXTERNAL_LANGUAGE", "SQL_DATA_ACCESS"]
        ) { row in
            let language = try row.optionalText("EXTERNAL_LANGUAGE", maximum: 8)
            let access = try row.optionalText("SQL_DATA_ACCESS", maximum: 8)
            _ = try row.optionalText("EXTERNAL_NAME", maximum: 279)
            return [language, access].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        }
    }

    public func decodeViewDependencies(_ result: SQLResult) throws -> [ObjectImpactEdge] {
        try decodeEdges(
            result,
            source: .sysviewdep,
            evidenceClass: .catalog,
            requiredDetailColumns: ["VIEW_SCHEMA", "VIEW_NAME", "OBJECT_TYPE"]
        ) { row in
            let viewSchema = try row.requiredText("VIEW_SCHEMA", maximum: 128)
            let viewName = try row.requiredText("VIEW_NAME", maximum: 128)
            let type = try row.requiredText("OBJECT_TYPE", maximum: 24)
            return "\(viewSchema)/\(viewName) · \(type)"
        }
    }

    private func decodeEdges(
        _ result: SQLResult,
        source: ObjectImpactEvidenceSource,
        evidenceClass: ObjectImpactEvidenceClass,
        requiredDetailColumns: [String],
        detail: (ImpactSQLRow) throws -> String?
    ) throws -> [ObjectImpactEdge] {
        let common = [
            "EDGE_DIRECTION", "FROM_LIBRARY", "FROM_NAME", "FROM_TYPE",
            "TO_LIBRARY", "TO_NAME", "TO_TYPE"
        ]
        try validate(
            result,
            source: source.rawValue,
            required: common + requiredDetailColumns,
            maximumRows: limits.maximumEdgesPerSource
        )
        return try result.rows.indices.map { offset in
            let row = try ImpactSQLRow(result: result, source: source.rawValue, rowIndex: offset + 1)
            let directionText = try row.requiredText("EDGE_DIRECTION", maximum: 8).uppercased()
            let direction: ObjectImpactEdgeDirection
            switch directionText {
            case "INCOMING": direction = .incoming
            case "OUTGOING": direction = .outgoing
            default:
                throw ObjectImpactError.invalidValue(
                    source: source.rawValue,
                    index: offset + 1,
                    column: "EDGE_DIRECTION"
                )
            }
            let from = try ObjectImpactNode(
                library: row.requiredText("FROM_LIBRARY", maximum: 128),
                name: row.requiredText("FROM_NAME", maximum: 128),
                type: row.requiredText("FROM_TYPE", maximum: 32)
            )
            let to = try ObjectImpactNode(
                library: row.requiredText("TO_LIBRARY", maximum: 128),
                name: row.requiredText("TO_NAME", maximum: 128),
                type: row.requiredText("TO_TYPE", maximum: 32)
            )
            return ObjectImpactEdge(
                direction: direction,
                from: from,
                to: to,
                evidenceClass: evidenceClass,
                source: source,
                detail: try detail(row)
            )
        }
    }

    private func validate(
        _ result: SQLResult,
        source: String,
        required: [String],
        maximumRows: Int
    ) throws {
        var seen = Set<String>()
        for column in result.columns {
            let normalized = column.name.uppercased()
            guard seen.insert(normalized).inserted else {
                throw ObjectImpactError.duplicateColumn(source: source, column: normalized)
            }
        }
        for column in required where !seen.contains(column) {
            throw ObjectImpactError.missingColumn(source: source, column: column)
        }
        guard result.rows.count <= maximumRows else {
            throw ObjectImpactError.tooManyRows(source: source, maximum: maximumRows)
        }
        for (offset, row) in result.rows.enumerated() where row.count != result.columns.count {
            throw ObjectImpactError.malformedRow(source: source, index: offset + 1)
        }
    }

    private func normalizeObjectType(_ value: String) -> String {
        let upper = value.uppercased()
        return upper.hasPrefix("*") ? upper : "*\(upper)"
    }
}

public struct ObjectImpactArtifactBuilder: Sendable {
    public init() {}

    public func build(snapshot: ObjectImpactSnapshot) -> String {
        let timestamp = snapshot.capturedAt.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: false)
        )
        var lines = [
            "iTelAS DEPENDENCY AND IMPACT EVIDENCE",
            "Target system: \(snapshot.targetName)",
            "Object: \(snapshot.target.description)",
            "Captured: \(timestamp)",
            "Mode: \(snapshot.isBundledReplay ? "LOCAL REPLAY" : "LIVE READ-ONLY")",
            "Verdict: \(snapshot.assessment.verdict)",
            "",
            "ASSESSMENT",
            snapshot.assessment.method,
            "Incoming edges: \(snapshot.assessment.incomingCount)",
            "Outgoing edges: \(snapshot.assessment.outgoingCount)",
            "Executable bindings: \(snapshot.assessment.boundCount)",
            "Catalog relationships: \(snapshot.assessment.catalogCount)",
            "Build candidates: \(snapshot.assessment.candidateCount)",
            "Evidence gaps: \(snapshot.assessment.gapCount)",
            "Sources at bound: \(snapshot.assessment.boundReachedCount)",
            "",
            "OBJECT METADATA"
        ]
        if let metadata = snapshot.metadata {
            lines += [
                "Owner: \(metadata.owner ?? "UNAVAILABLE")",
                "Attribute: \(metadata.attribute ?? "UNAVAILABLE")",
                "Text: \(metadata.text ?? "UNAVAILABLE")",
                "Size bytes: \(metadata.sizeBytes.map(String.init) ?? "UNAVAILABLE")",
                "Source: \(sourceLabel(metadata) ?? "UNAVAILABLE")"
            ]
        } else {
            lines.append("Exact object metadata unavailable. This is not proof the object is absent.")
        }
        lines += ["", "DIRECT EVIDENCE EDGES"]
        if snapshot.edges.isEmpty {
            lines.append("No edges were returned within the collected evidence. This is not proof of no dependencies.")
        } else {
            for edge in snapshot.edges {
                lines.append(
                    "[\(edge.evidenceClass.label)] [\(edge.direction.label)] \(edge.from.label) -> \(edge.to.label) · \(edge.source.rawValue)\(edge.detail.map { " · \($0)" } ?? "")"
                )
            }
        }
        lines += ["", "EVIDENCE RECEIPTS"]
        for receipt in snapshot.receipts {
            let outcome = switch receipt.outcome {
            case .collected: "COLLECTED"
            case .unavailable(let reason): "UNAVAILABLE · \(reason)"
            }
            lines.append(
                "\(receipt.source.rawValue): \(outcome) · rows \(receipt.rowCount) · bound \(receipt.boundWasReached ? "REACHED" : "NOT REACHED") · query \(receipt.queryFingerprint)"
            )
        }
        lines += [
            "",
            "BOUNDARIES",
            "No host writes were requested by this collection.",
            "Missing rows never prove absence; object and catalog authorities can suppress evidence.",
            "Binding-directory entries are candidates, not proof that a program consumed the entry.",
            "No runtime call frequency, transitive reachability, or safe-change conclusion is claimed.",
            "Program-reference coverage is unavailable because DSPPGMREF output would create a host object in this read-only milestone."
        ]
        return lines.joined(separator: "\n")
    }

    private func sourceLabel(_ metadata: ObjectImpactMetadata) -> String? {
        if let library = metadata.sourceLibrary,
           let file = metadata.sourceFile,
           let member = metadata.sourceMember {
            return "\(library)/\(file)(\(member))"
        }
        return nil
    }
}

public struct ObjectImpactAssistContextBuilder: Sendable {
    public init() {}

    public func build(snapshot: ObjectImpactSnapshot, includeIdentifiers: Bool = false) -> String {
        let targetNode = ObjectImpactNode(snapshot.target)
        let related = Set(snapshot.edges.flatMap { [$0.from, $0.to] })
            .filter { $0.id != targetNode.id }
            .sorted { $0.id < $1.id }
        let aliases = Dictionary(uniqueKeysWithValues: related.enumerated().map { offset, node in
            (node.id, "OBJECT-\(String(format: "%03d", offset + 1))")
        })
        func label(_ node: ObjectImpactNode) -> String {
            if includeIdentifiers { return node.label }
            if node.id == targetNode.id { return "FOCUS-OBJECT \(node.type)" }
            return "\(aliases[node.id] ?? "RELATED-OBJECT") \(node.type)"
        }

        var lines = [
            "IBM i dependency and impact evidence",
            "Target system identity: \(includeIdentifiers ? snapshot.targetName : "WITHHELD")",
            "Focus object: \(includeIdentifiers ? snapshot.target.description : "WITHHELD · \(snapshot.target.type.rawValue)")",
            "Collection mode: \(snapshot.isBundledReplay ? "LOCAL REPLAY" : "LIVE READ-ONLY")",
            "Verdict: REVIEW REQUIRED",
            "Method: \(snapshot.assessment.method)",
            "Counts: incoming \(snapshot.assessment.incomingCount), outgoing \(snapshot.assessment.outgoingCount), bound \(snapshot.assessment.boundCount), catalog \(snapshot.assessment.catalogCount), candidate \(snapshot.assessment.candidateCount), gaps \(snapshot.assessment.gapCount).",
            "Edges:"
        ]
        if snapshot.edges.isEmpty {
            lines.append("- No edges returned; do not interpret this as proof of no dependencies.")
        } else {
            for edge in snapshot.edges {
                lines.append(
                    "- \(label(edge.from)) -> \(label(edge.to)) [\(edge.direction.label), \(edge.evidenceClass.label), \(edge.source.rawValue)]"
                )
            }
        }
        lines.append("Receipts:")
        for receipt in snapshot.receipts {
            lines.append(
                "- \(receipt.source.rawValue): \(receipt.outcome.isCollected ? "COLLECTED" : "UNAVAILABLE"), rows \(receipt.rowCount), bound \(receipt.boundWasReached ? "REACHED" : "NOT REACHED")"
            )
        }
        lines += [
            "Privacy: host, owner, source location, object descriptions, query text, fingerprints, and unavailable-reason details are omitted unless identifiers are explicitly included.",
            "Instruction: separate observed edges from inference, preserve evidence classes, identify gaps, and propose read-only verification steps only."
        ]
        return lines.joined(separator: "\n")
    }
}

private struct ImpactSQLRow {
    let result: SQLResult
    let source: String
    let rowIndex: Int
    let indexes: [String: Int]

    init(result: SQLResult, source: String, rowIndex: Int) throws {
        guard result.rows.indices.contains(rowIndex - 1),
              result.rows[rowIndex - 1].count == result.columns.count else {
            throw ObjectImpactError.malformedRow(source: source, index: rowIndex)
        }
        self.result = result
        self.source = source
        self.rowIndex = rowIndex
        indexes = Dictionary(uniqueKeysWithValues: result.columns.enumerated().map {
            ($0.element.name.uppercased(), $0.offset)
        })
    }

    func requiredText(_ column: String, maximum: Int) throws -> String {
        guard let value = try optionalText(column, maximum: maximum), !value.isEmpty else {
            throw ObjectImpactError.invalidValue(source: source, index: rowIndex, column: column)
        }
        return value
    }

    func optionalText(_ column: String, maximum: Int) throws -> String? {
        let value = try value(column)
        let text: String
        switch value {
        case .null: return nil
        case .string(let string): text = string
        case .integer(let integer): text = String(integer)
        case .decimal(let decimal): text = decimal
        case .boolean(let boolean): text = boolean ? "true" : "false"
        default:
            throw ObjectImpactError.invalidValue(source: source, index: rowIndex, column: column)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maximum,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ObjectImpactError.invalidText(source: source, index: rowIndex, column: column)
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    func optionalInt64(_ column: String) throws -> Int64? {
        switch try value(column) {
        case .null: return nil
        case .integer(let value): return value
        case .decimal(let value), .string(let value):
            guard let parsed = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ObjectImpactError.invalidValue(source: source, index: rowIndex, column: column)
            }
            return parsed
        default:
            throw ObjectImpactError.invalidValue(source: source, index: rowIndex, column: column)
        }
    }

    func optionalDate(_ column: String) throws -> Date? {
        switch try value(column) {
        case .null: return nil
        case .date(let value), .timestamp(let value): return value
        default:
            throw ObjectImpactError.invalidValue(source: source, index: rowIndex, column: column)
        }
    }

    private func value(_ column: String) throws -> SQLValue {
        guard let index = indexes[column.uppercased()] else {
            throw ObjectImpactError.missingColumn(source: source, column: column.uppercased())
        }
        return result.rows[rowIndex - 1][index]
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
