import Foundation

public struct JobIncidentLimits: Equatable, Sendable {
    public var maximumJobs: Int
    public var maximumLocks: Int
    public var maximumJobLogMessages: Int
    public var maximumOperatorMessages: Int
    public var maximumMessageCharacters: Int
    public var maximumSecondLevelCharacters: Int
    public var queryTimeoutSeconds: Int

    public init(
        maximumJobs: Int = 250,
        maximumLocks: Int = 500,
        maximumJobLogMessages: Int = 500,
        maximumOperatorMessages: Int = 100,
        maximumMessageCharacters: Int = 1_024,
        maximumSecondLevelCharacters: Int = 4_096,
        queryTimeoutSeconds: Int = 30
    ) {
        self.maximumJobs = maximumJobs
        self.maximumLocks = maximumLocks
        self.maximumJobLogMessages = maximumJobLogMessages
        self.maximumOperatorMessages = maximumOperatorMessages
        self.maximumMessageCharacters = maximumMessageCharacters
        self.maximumSecondLevelCharacters = maximumSecondLevelCharacters
        self.queryTimeoutSeconds = queryTimeoutSeconds
    }

    public static let standard = JobIncidentLimits()
}

public enum JobIncidentError: Error, Equatable, LocalizedError, Sendable {
    case invalidQualifiedJobName(String)
    case invalidSystemName(field: String)
    case invalidObjectType
    case tooManyRows(surface: String, maximum: Int)
    case duplicateColumn(surface: String, column: String)
    case missingColumn(surface: String, column: String)
    case malformedRow(surface: String, index: Int)
    case invalidValue(surface: String, index: Int, column: String)
    case textTooLarge(surface: String, index: Int, column: String, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidQualifiedJobName:
            "The qualified job name must be NUMBER/USER/JOB with exact IBM system-name bounds."
        case .invalidSystemName(let field):
            "The \(field) value is not a valid bounded IBM system name."
        case .invalidObjectType:
            "The object type is not a valid bounded IBM object type."
        case .tooManyRows(let surface, let maximum):
            "The \(surface) result exceeds the \(maximum)-row evidence limit."
        case .duplicateColumn(let surface, let column):
            "The \(surface) result contains an ambiguous duplicate \(column) column."
        case .missingColumn(let surface, let column):
            "The \(surface) result does not contain the required \(column) column."
        case .malformedRow(let surface, let index):
            "The \(surface) result row \(index) does not match its column layout."
        case .invalidValue(let surface, let index, let column):
            "The \(surface) result row \(index) contains an invalid \(column) value."
        case .textTooLarge(let surface, let index, let column, let maximum):
            "The \(surface) result row \(index) \(column) text exceeds \(maximum) characters."
        }
    }
}

public struct IBMQualifiedJobName: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public let number: String
    public let user: String
    public let name: String

    public var description: String { rawValue }

    public init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.allSatisfy({ scalar in
            (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value)
                || [35, 36, 47, 64, 95].contains(scalar.value)
        }) else {
            throw JobIncidentError.invalidQualifiedJobName(value)
        }
        let normalized = trimmed.uppercased()
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            throw JobIncidentError.invalidQualifiedJobName(value)
        }
        let number = String(components[0])
        let user = String(components[1])
        let name = String(components[2])
        guard number.count == 6,
              number.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              Self.isSystemName(user),
              Self.isSystemName(name) else {
            throw JobIncidentError.invalidQualifiedJobName(value)
        }
        rawValue = "\(number)/\(user)/\(name)"
        self.number = number
        self.user = user
        self.name = name
    }

    public init?(rawValue: String) {
        guard let value = try? Self(rawValue) else { return nil }
        self = value
    }

    private static func isSystemName(_ value: String) -> Bool {
        guard (1...10).contains(value.count) else { return false }
        let scalars = Array(value.unicodeScalars)
        guard let first = scalars.first,
              (65...90).contains(first.value) || [35, 36, 64, 95].contains(first.value) else {
            return false
        }
        return scalars.dropFirst().allSatisfy {
            (65...90).contains($0.value)
                || (48...57).contains($0.value)
                || [35, 36, 64, 95].contains($0.value)
        }
    }
}

public struct IBMObjectLockIdentity: Hashable, Sendable, Identifiable {
    public let library: IBMSystemObjectName
    public let object: IBMSystemObjectName
    public let member: IBMSystemObjectName?
    public let objectType: String

    public var id: String {
        "\(library.value)/\(object.value)/\(member?.value ?? "-")/\(objectType)"
    }

    public var displayName: String {
        let base = "\(library.value)/\(object.value)"
        return member.map { "\(base)(\($0.value)) · \(objectType)" } ?? "\(base) · \(objectType)"
    }

    public init(
        library: IBMSystemObjectName,
        object: IBMSystemObjectName,
        member: IBMSystemObjectName? = nil,
        objectType: String
    ) throws {
        let normalizedType = objectType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_*$#@")
        guard (1...10).contains(normalizedType.count),
              normalizedType.unicodeScalars.allSatisfy(allowed.contains) else {
            throw JobIncidentError.invalidObjectType
        }
        self.library = library
        self.object = object
        self.member = member
        self.objectType = normalizedType
    }
}

public struct IBMQueueIdentity: Hashable, Sendable, Identifiable {
    public let library: IBMSystemObjectName
    public let name: IBMSystemObjectName
    public var id: String { "\(library.value)/\(name.value)" }

    public init(library: IBMSystemObjectName, name: IBMSystemObjectName) {
        self.library = library
        self.name = name
    }
}

public enum JobInventoryStatus: String, Equatable, Sendable {
    case active = "ACTIVE"
    case jobQueue = "JOBQ"
    case outputQueue = "OUTQ"
    case unavailable = "UNAVAILABLE"

    public var label: String {
        switch self {
        case .active: "Active"
        case .jobQueue: "Job queue"
        case .outputQueue: "Output queue"
        case .unavailable: "Unavailable"
        }
    }
}

public struct JobInventoryRecord: Equatable, Sendable, Identifiable {
    public let qualifiedName: IBMQualifiedJobName
    public let informationAvailable: Bool
    public let status: JobInventoryStatus
    public let type: String?
    public let enhancedType: String?
    public let subsystem: IBMSystemObjectName?
    public let jobQueue: IBMQueueIdentity?
    public let jobQueueStatus: String?
    public let jobQueuePriority: Int?
    public let jobQueueTime: Date?
    public let jobLogPending: Bool
    public let outputQueue: IBMQueueIdentity?

    public var id: IBMQualifiedJobName { qualifiedName }

    public init(
        qualifiedName: IBMQualifiedJobName,
        informationAvailable: Bool,
        status: JobInventoryStatus,
        type: String? = nil,
        enhancedType: String? = nil,
        subsystem: IBMSystemObjectName? = nil,
        jobQueue: IBMQueueIdentity? = nil,
        jobQueueStatus: String? = nil,
        jobQueuePriority: Int? = nil,
        jobQueueTime: Date? = nil,
        jobLogPending: Bool = false,
        outputQueue: IBMQueueIdentity? = nil
    ) {
        self.qualifiedName = qualifiedName
        self.informationAvailable = informationAvailable
        self.status = status
        self.type = type
        self.enhancedType = enhancedType
        self.subsystem = subsystem
        self.jobQueue = jobQueue
        self.jobQueueStatus = jobQueueStatus
        self.jobQueuePriority = jobQueuePriority
        self.jobQueueTime = jobQueueTime
        self.jobLogPending = jobLogPending
        self.outputQueue = outputQueue
    }
}

public enum JobLockStatus: String, Equatable, Sendable {
    case held = "HELD"
    case requested = "REQUESTED"
    case waiting = "WAITING"
}

public struct JobLockRecord: Equatable, Sendable, Identifiable {
    public let rowIndex: Int
    public let object: IBMObjectLockIdentity
    public let job: IBMQualifiedJobName
    public let status: JobLockStatus
    public let state: String
    public let scope: String
    public let threadID: Int64?
    public let programLibrary: IBMSystemObjectName?
    public let program: IBMSystemObjectName?
    public let module: IBMSystemObjectName?
    public let procedure: String?
    public let statementID: String?

    public var id: String {
        "\(rowIndex):\(object.id):\(job.rawValue):\(status.rawValue):\(threadID.map(String.init) ?? "-")"
    }

    public init(
        rowIndex: Int,
        object: IBMObjectLockIdentity,
        job: IBMQualifiedJobName,
        status: JobLockStatus,
        state: String,
        scope: String,
        threadID: Int64? = nil,
        programLibrary: IBMSystemObjectName? = nil,
        program: IBMSystemObjectName? = nil,
        module: IBMSystemObjectName? = nil,
        procedure: String? = nil,
        statementID: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.object = object
        self.job = job
        self.status = status
        self.state = state
        self.scope = scope
        self.threadID = threadID
        self.programLibrary = programLibrary
        self.program = program
        self.module = module
        self.procedure = procedure
        self.statementID = statementID
    }
}

public struct JobLogMessage: Equatable, Sendable, Identifiable {
    public let ordinalPosition: Int
    public let messageID: String?
    public let type: String
    public let severity: Int
    public let timestamp: Date?
    public let text: String?
    public let secondLevelText: String?
    public let fromProgram: String?
    public let fromModule: String?
    public let fromProcedure: String?
    public let qualifiedJobName: IBMQualifiedJobName

    public var id: String { "\(qualifiedJobName.rawValue):\(ordinalPosition)" }
    public var isInquiry: Bool { type == "INQUIRY" }

    public init(
        ordinalPosition: Int,
        messageID: String?,
        type: String,
        severity: Int,
        timestamp: Date?,
        text: String?,
        secondLevelText: String?,
        fromProgram: String? = nil,
        fromModule: String? = nil,
        fromProcedure: String? = nil,
        qualifiedJobName: IBMQualifiedJobName
    ) {
        self.ordinalPosition = ordinalPosition
        self.messageID = messageID
        self.type = type
        self.severity = severity
        self.timestamp = timestamp
        self.text = text
        self.secondLevelText = secondLevelText
        self.fromProgram = fromProgram
        self.fromModule = fromModule
        self.fromProcedure = fromProcedure
        self.qualifiedJobName = qualifiedJobName
    }
}

public struct OperatorMessageRecord: Equatable, Sendable, Identifiable {
    public let rowIndex: Int
    public let messageID: String?
    public let type: String
    public let severity: Int
    public let timestamp: Date?
    public let text: String?
    public let secondLevelText: String?
    public let fromUser: String?
    public let fromJob: IBMQualifiedJobName?
    public let fromProgram: String?

    public var id: String {
        "\(rowIndex):\(messageID ?? "-"):\(timestamp?.timeIntervalSince1970 ?? 0)"
    }

    public init(
        rowIndex: Int,
        messageID: String?,
        type: String,
        severity: Int,
        timestamp: Date?,
        text: String?,
        secondLevelText: String?,
        fromUser: String? = nil,
        fromJob: IBMQualifiedJobName? = nil,
        fromProgram: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.messageID = messageID
        self.type = type
        self.severity = severity
        self.timestamp = timestamp
        self.text = text
        self.secondLevelText = secondLevelText
        self.fromUser = fromUser
        self.fromJob = fromJob
        self.fromProgram = fromProgram
    }
}

public enum JobIncidentEvidenceSource: String, CaseIterable, Sendable {
    case jobInfo = "JOB_INFO"
    case objectLockInfo = "OBJECT_LOCK_INFO"
    case joblogInfo = "JOBLOG_INFO"
    case messageQueueInfo = "MESSAGE_QUEUE_INFO"
}

public enum JobIncidentEvidenceOutcome: Equatable, Sendable {
    case collected
    case unavailable(String)

    public var isCollected: Bool {
        if case .collected = self { return true }
        return false
    }
}

public struct JobIncidentEvidenceReceipt: Equatable, Sendable, Identifiable {
    public let source: JobIncidentEvidenceSource
    public let rowCount: Int
    public let wasTruncated: Bool
    public let queryFingerprint: String
    public let outcome: JobIncidentEvidenceOutcome

    public var id: JobIncidentEvidenceSource { source }

    public init(
        source: JobIncidentEvidenceSource,
        rowCount: Int,
        wasTruncated: Bool,
        queryFingerprint: String,
        outcome: JobIncidentEvidenceOutcome
    ) {
        self.source = source
        self.rowCount = rowCount
        self.wasTruncated = wasTruncated
        self.queryFingerprint = queryFingerprint
        self.outcome = outcome
    }
}

public struct JobIncidentSnapshot: Equatable, Sendable {
    public let targetName: String
    public let capturedAt: Date
    public let jobs: [JobInventoryRecord]
    public let locks: [JobLockRecord]
    public let jobLogMessages: [JobLogMessage]
    public let operatorMessages: [OperatorMessageRecord]
    public let receipts: [JobIncidentEvidenceReceipt]

    public init(
        targetName: String,
        capturedAt: Date,
        jobs: [JobInventoryRecord],
        locks: [JobLockRecord],
        jobLogMessages: [JobLogMessage],
        operatorMessages: [OperatorMessageRecord],
        receipts: [JobIncidentEvidenceReceipt]
    ) {
        self.targetName = targetName
        self.capturedAt = capturedAt
        self.jobs = jobs
        self.locks = locks
        self.jobLogMessages = jobLogMessages
        self.operatorMessages = operatorMessages
        self.receipts = receipts
    }

    public func job(named name: IBMQualifiedJobName) -> JobInventoryRecord? {
        jobs.first(where: { $0.qualifiedName == name })
    }

    public var gaps: [JobIncidentEvidenceReceipt] {
        receipts.filter { !$0.outcome.isCollected }
    }

    public var queueSummaries: [JobQueueSummary] {
        let grouped = Dictionary(grouping: jobs.compactMap { job -> (IBMQueueIdentity, JobInventoryRecord)? in
            guard let queue = job.jobQueue else { return nil }
            return (queue, job)
        }, by: { $0.0 })
        return grouped.map { queue, pairs in
            let records = pairs.map(\.1)
            return JobQueueSummary(
                identity: queue,
                activeCount: records.filter { $0.status == .active }.count,
                queuedCount: records.filter { $0.status == .jobQueue }.count,
                heldCount: records.filter { $0.jobQueueStatus == "HELD" }.count,
                scheduledCount: records.filter { $0.jobQueueStatus == "SCHEDULED" }.count,
                oldestQueueTime: records.compactMap(\.jobQueueTime).min()
            )
        }
        .sorted { lhs, rhs in
            if lhs.queuedCount != rhs.queuedCount { return lhs.queuedCount > rhs.queuedCount }
            return lhs.identity.id < rhs.identity.id
        }
    }
}

public struct JobQueueSummary: Equatable, Sendable, Identifiable {
    public let identity: IBMQueueIdentity
    public let activeCount: Int
    public let queuedCount: Int
    public let heldCount: Int
    public let scheduledCount: Int
    public let oldestQueueTime: Date?
    public var id: IBMQueueIdentity { identity }
}

public enum JobIncidentConfidence: String, Equatable, Sendable {
    case high
    case medium
    case low

    public var label: String { rawValue.uppercased() }
}

public struct JobLockCorrelation: Equatable, Sendable, Identifiable {
    public let waiting: JobLockRecord
    public let holder: JobLockRecord
    public var id: String { "\(waiting.id)->\(holder.id)" }
}

public struct JobIncidentAnalysis: Equatable, Sendable {
    public let selectedJob: JobInventoryRecord
    public let waitingLocks: [JobLockRecord]
    public let holderCandidates: [JobLockCorrelation]
    public let selectedMessage: JobLogMessage?
    public let relatedOperatorMessages: [OperatorMessageRecord]
    public let confidence: JobIncidentConfidence
    public let relationshipBasis: String
    public let messageSelectionBasis: String

    public init(snapshot: JobIncidentSnapshot, selectedJob: JobInventoryRecord) {
        self.selectedJob = selectedJob
        waitingLocks = snapshot.locks.filter {
            $0.job == selectedJob.qualifiedName && ($0.status == .waiting || $0.status == .requested)
        }

        holderCandidates = waitingLocks.flatMap { waiting in
            snapshot.locks.compactMap { candidate in
                guard candidate.status == .held,
                      candidate.job != waiting.job,
                      candidate.object == waiting.object else { return nil }
                return JobLockCorrelation(waiting: waiting, holder: candidate)
            }
        }

        let jobMessages = snapshot.jobLogMessages
            .filter { $0.qualifiedJobName == selectedJob.qualifiedName }
        if let latestInquiry = jobMessages.filter(\.isInquiry).max(by: {
            $0.ordinalPosition < $1.ordinalPosition
        }) {
            selectedMessage = latestInquiry
            messageSelectionBasis = "The latest inquiry message is selected because it can explain an operator-visible wait; this is a triage choice, not proof of cause."
        } else {
            selectedMessage = jobMessages.max {
                ($0.severity, $0.ordinalPosition) < ($1.severity, $1.ordinalPosition)
            }
            messageSelectionBasis = selectedMessage == nil
                ? "No accessible job-log message was present for the selected job."
                : "The highest-severity, latest job-log message is selected as a triage lead, not proof of cause."
        }

        relatedOperatorMessages = snapshot.operatorMessages.filter {
            $0.fromJob == selectedJob.qualifiedName
        }

        let distinctHolders = Set(holderCandidates.map { $0.holder.job })
        confidence = switch distinctHolders.count {
        case 1 where !waitingLocks.isEmpty: .high
        case 2...: .medium
        default: .low
        }
        relationshipBasis = switch distinctHolders.count {
        case 0:
            "No HELD record with the exact same object identity was visible in this snapshot."
        case 1:
            "One different job has a HELD record with the exact object identity requested by the selected job. This is strong correlation, not scheduler-causality proof."
        default:
            "Multiple jobs have HELD records with the exact object identity. They remain candidates until an operator reviews lock compatibility and timing."
        }
    }
}

public struct JobIncidentSQLPlanner: Sendable {
    public let limits: JobIncidentLimits

    public init(limits: JobIncidentLimits = .standard) {
        self.limits = limits
    }

    public var jobInventory: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT JOB_NAME,
                   JOB_INFORMATION,
                   JOB_STATUS,
                   JOB_TYPE,
                   JOB_TYPE_ENHANCED,
                   JOB_SUBSYSTEM,
                   JOB_QUEUE_LIBRARY,
                   JOB_QUEUE_NAME,
                   JOB_QUEUE_STATUS,
                   JOB_QUEUE_PRIORITY,
                   JOB_QUEUE_TIME,
                   JOB_LOG_PENDING,
                   OUTPUT_QUEUE_LIBRARY,
                   OUTPUT_QUEUE_NAME
              FROM TABLE(QSYS2.JOB_INFO(
                       JOB_STATUS_FILTER => '*ALL',
                       JOB_TYPE_FILTER => '*ALL',
                       JOB_SUBSYSTEM_FILTER => '*ALL',
                       JOB_USER_FILTER => '*ALL',
                       JOB_SUBMITTER_FILTER => '*ALL',
                       JOB_NAME_FILTER => '*ALL'
                   )) AS J
             WHERE JOB_TYPE IS NULL
                OR JOB_TYPE NOT IN ('SBS', 'SYS', 'RDR', 'WTR')
             ORDER BY CASE JOB_STATUS
                        WHEN 'ACTIVE' THEN 0
                        WHEN 'JOBQ' THEN 1
                        ELSE 2
                      END,
                      JOB_QUEUE_TIME,
                      JOB_NAME
             FETCH FIRST \(limits.maximumJobs) ROWS ONLY
            """,
            maximumRows: limits.maximumJobs,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }

    public var objectLocks: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT SYSTEM_OBJECT_SCHEMA,
                   SYSTEM_OBJECT_NAME,
                   SYSTEM_TABLE_MEMBER,
                   OBJECT_TYPE,
                   LOCK_STATE,
                   LOCK_STATUS,
                   LOCK_SCOPE,
                   JOB_NAME,
                   THREAD_ID,
                   PROGRAM_LIBRARY_NAME,
                   PROGRAM_NAME,
                   MODULE_NAME,
                   PROCEDURE_NAME,
                   STATEMENT_ID
              FROM QSYS2.OBJECT_LOCK_INFO
             WHERE JOB_NAME IS NOT NULL
             ORDER BY CASE LOCK_STATUS
                        WHEN 'WAITING' THEN 0
                        WHEN 'REQUESTED' THEN 1
                        ELSE 2
                      END,
                      SYSTEM_OBJECT_SCHEMA,
                      SYSTEM_OBJECT_NAME,
                      JOB_NAME
             FETCH FIRST \(limits.maximumLocks) ROWS ONLY
            """,
            maximumRows: limits.maximumLocks,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }

    public func jobLog(for job: IBMQualifiedJobName) -> SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            WITH RECENT_MESSAGES AS (
                SELECT ORDINAL_POSITION AS SERVICE_POSITION,
                       MESSAGE_ID,
                       MESSAGE_TYPE,
                       SEVERITY,
                       MESSAGE_TIMESTAMP,
                       MESSAGE_TEXT,
                       MESSAGE_SECOND_LEVEL_TEXT,
                       FROM_PROGRAM,
                       FROM_MODULE,
                       FROM_PROCEDURE,
                       QUALIFIED_JOB_NAME
                  FROM TABLE(QSYS2.JOBLOG_INFO(
                           JOB_NAME => '\(job.rawValue)',
                           IGNORE_ERRORS => 'NO',
                           MESSAGE_ORDER => 'DESCENDING',
                           MESSAGE_LIMIT => \(limits.maximumJobLogMessages)
                       )) AS L
            )
            SELECT ROW_NUMBER() OVER (
                       ORDER BY MESSAGE_TIMESTAMP NULLS FIRST,
                                SERVICE_POSITION DESC
                   ) AS ORDINAL_POSITION,
                   MESSAGE_ID,
                   MESSAGE_TYPE,
                   SEVERITY,
                   MESSAGE_TIMESTAMP,
                   MESSAGE_TEXT,
                   MESSAGE_SECOND_LEVEL_TEXT,
                   FROM_PROGRAM,
                   FROM_MODULE,
                   FROM_PROCEDURE,
                   QUALIFIED_JOB_NAME
              FROM RECENT_MESSAGES
             ORDER BY MESSAGE_TIMESTAMP NULLS FIRST,
                      SERVICE_POSITION DESC
             FETCH FIRST \(limits.maximumJobLogMessages) ROWS ONLY
            """,
            maximumRows: limits.maximumJobLogMessages,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }

    public var operatorInquiries: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT MESSAGE_ID,
                   MESSAGE_TYPE,
                   SEVERITY,
                   MESSAGE_TIMESTAMP,
                   MESSAGE_TEXT,
                   MESSAGE_SECOND_LEVEL_TEXT,
                   FROM_USER,
                   FROM_JOB,
                   FROM_PROGRAM
              FROM TABLE(QSYS2.MESSAGE_QUEUE_INFO(
                       QUEUE_LIBRARY => 'QSYS',
                       QUEUE_NAME => 'QSYSOPR',
                       MESSAGE_FILTER => 'INQUIRY',
                       SEVERITY_FILTER => 0
                   )) AS M
             ORDER BY MESSAGE_TIMESTAMP DESC
             FETCH FIRST \(limits.maximumOperatorMessages) ROWS ONLY
            """,
            maximumRows: limits.maximumOperatorMessages,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }
}

public struct JobIncidentSQLDecoder: Sendable {
    public let limits: JobIncidentLimits

    public init(limits: JobIncidentLimits = .standard) {
        self.limits = limits
    }

    public func decodeJobs(_ result: SQLResult) throws -> [JobInventoryRecord] {
        let rows = try Rows(result: result, surface: "JOB_INFO", maximum: limits.maximumJobs)
        return try rows.map { row in
            let qualifiedName = try IBMQualifiedJobName(try row.requiredString("JOB_NAME"))
            let information = try row.requiredString("JOB_INFORMATION").uppercased()
            guard information == "YES" || information == "NO" else {
                throw row.invalid("JOB_INFORMATION")
            }
            let available = information == "YES"
            let status: JobInventoryStatus
            if !available {
                status = .unavailable
            } else {
                guard let value = try row.optionalString("JOB_STATUS"),
                      let parsed = JobInventoryStatus(rawValue: value.uppercased()) else {
                    throw row.invalid("JOB_STATUS")
                }
                status = parsed
            }

            let jobQueue = try queueIdentity(
                library: row.optionalString("JOB_QUEUE_LIBRARY"),
                name: row.optionalString("JOB_QUEUE_NAME"),
                row: row,
                prefix: "JOB_QUEUE"
            )
            let outputQueue = try queueIdentity(
                library: row.optionalString("OUTPUT_QUEUE_LIBRARY"),
                name: row.optionalString("OUTPUT_QUEUE_NAME"),
                row: row,
                prefix: "OUTPUT_QUEUE"
            )
            let subsystem = try row.optionalString("JOB_SUBSYSTEM").map {
                try systemName($0, field: "JOB_SUBSYSTEM", row: row)
            }
            let logPending: Bool
            if let value = try row.optionalString("JOB_LOG_PENDING")?.uppercased() {
                guard value == "YES" || value == "NO" else { throw row.invalid("JOB_LOG_PENDING") }
                logPending = value == "YES"
            } else {
                logPending = false
            }
            let jobQueueStatus = try bounded(
                row.optionalString("JOB_QUEUE_STATUS"),
                maximum: 9,
                row: row,
                column: "JOB_QUEUE_STATUS"
            )?.uppercased()
            if let jobQueueStatus,
               !["HELD", "RELEASED", "SCHEDULED"].contains(jobQueueStatus) {
                throw row.invalid("JOB_QUEUE_STATUS")
            }
            let jobQueuePriority = try row.optionalInt("JOB_QUEUE_PRIORITY")
            if let jobQueuePriority, !(0...9).contains(jobQueuePriority) {
                throw row.invalid("JOB_QUEUE_PRIORITY")
            }

            return JobInventoryRecord(
                qualifiedName: qualifiedName,
                informationAvailable: available,
                status: status,
                type: try bounded(row.optionalString("JOB_TYPE"), maximum: 28, row: row, column: "JOB_TYPE"),
                enhancedType: try bounded(row.optionalString("JOB_TYPE_ENHANCED"), maximum: 64, row: row, column: "JOB_TYPE_ENHANCED"),
                subsystem: subsystem,
                jobQueue: jobQueue,
                jobQueueStatus: jobQueueStatus,
                jobQueuePriority: jobQueuePriority,
                jobQueueTime: try row.optionalDate("JOB_QUEUE_TIME"),
                jobLogPending: logPending,
                outputQueue: outputQueue
            )
        }
    }

    public func decodeLocks(_ result: SQLResult) throws -> [JobLockRecord] {
        let rows = try Rows(result: result, surface: "OBJECT_LOCK_INFO", maximum: limits.maximumLocks)
        return try rows.map { row in
            let member = try row.optionalString("SYSTEM_TABLE_MEMBER").map {
                try systemName($0, field: "SYSTEM_TABLE_MEMBER", row: row)
            }
            let identity = try IBMObjectLockIdentity(
                library: systemName(try row.requiredString("SYSTEM_OBJECT_SCHEMA"), field: "SYSTEM_OBJECT_SCHEMA", row: row),
                object: systemName(try row.requiredString("SYSTEM_OBJECT_NAME"), field: "SYSTEM_OBJECT_NAME", row: row),
                member: member,
                objectType: try row.requiredString("OBJECT_TYPE")
            )
            guard let status = JobLockStatus(rawValue: try row.requiredString("LOCK_STATUS").uppercased()) else {
                throw row.invalid("LOCK_STATUS")
            }
            let state = try boundedRequired(row.requiredString("LOCK_STATE"), maximum: 7, row: row, column: "LOCK_STATE").uppercased()
            guard ["*EXCL", "*EXCLRD", "*SHRNUP", "*SHRRD", "*SHRUPD"].contains(state) else {
                throw row.invalid("LOCK_STATE")
            }
            let scope = try boundedRequired(row.requiredString("LOCK_SCOPE"), maximum: 10, row: row, column: "LOCK_SCOPE").uppercased()
            guard ["JOB", "LOCK SPACE", "THREAD"].contains(scope) else {
                throw row.invalid("LOCK_SCOPE")
            }
            return JobLockRecord(
                rowIndex: row.index,
                object: identity,
                job: try IBMQualifiedJobName(try row.requiredString("JOB_NAME")),
                status: status,
                state: state,
                scope: scope,
                threadID: try row.optionalInt64("THREAD_ID"),
                programLibrary: try row.optionalString("PROGRAM_LIBRARY_NAME").map {
                    try systemName($0, field: "PROGRAM_LIBRARY_NAME", row: row)
                },
                program: try row.optionalString("PROGRAM_NAME").map {
                    try systemName($0, field: "PROGRAM_NAME", row: row)
                },
                module: try row.optionalString("MODULE_NAME").map {
                    try systemName($0, field: "MODULE_NAME", row: row)
                },
                procedure: try bounded(row.optionalString("PROCEDURE_NAME"), maximum: 4_096, row: row, column: "PROCEDURE_NAME"),
                statementID: try bounded(row.optionalString("STATEMENT_ID"), maximum: 32, row: row, column: "STATEMENT_ID")
            )
        }
    }

    public func decodeJobLog(_ result: SQLResult) throws -> [JobLogMessage] {
        let rows = try Rows(result: result, surface: "JOBLOG_INFO", maximum: limits.maximumJobLogMessages)
        return try rows.map { row in
            let ordinalPosition = try row.requiredInt("ORDINAL_POSITION")
            guard ordinalPosition > 0 else { throw row.invalid("ORDINAL_POSITION") }
            let severity = try row.requiredInt("SEVERITY")
            guard (0...99).contains(severity) else { throw row.invalid("SEVERITY") }
            return JobLogMessage(
                ordinalPosition: ordinalPosition,
                messageID: try bounded(row.optionalString("MESSAGE_ID"), maximum: 7, row: row, column: "MESSAGE_ID"),
                type: try boundedRequired(row.requiredString("MESSAGE_TYPE"), maximum: 22, row: row, column: "MESSAGE_TYPE").uppercased(),
                severity: severity,
                timestamp: try row.optionalDate("MESSAGE_TIMESTAMP"),
                text: try bounded(row.optionalText("MESSAGE_TEXT"), maximum: limits.maximumMessageCharacters, row: row, column: "MESSAGE_TEXT"),
                secondLevelText: try bounded(row.optionalText("MESSAGE_SECOND_LEVEL_TEXT"), maximum: limits.maximumSecondLevelCharacters, row: row, column: "MESSAGE_SECOND_LEVEL_TEXT"),
                fromProgram: try bounded(row.optionalString("FROM_PROGRAM"), maximum: 256, row: row, column: "FROM_PROGRAM"),
                fromModule: try bounded(row.optionalString("FROM_MODULE"), maximum: 10, row: row, column: "FROM_MODULE"),
                fromProcedure: try bounded(row.optionalString("FROM_PROCEDURE"), maximum: 4_096, row: row, column: "FROM_PROCEDURE"),
                qualifiedJobName: try IBMQualifiedJobName(try row.requiredString("QUALIFIED_JOB_NAME"))
            )
        }
    }

    public func decodeOperatorMessages(_ result: SQLResult) throws -> [OperatorMessageRecord] {
        let rows = try Rows(result: result, surface: "MESSAGE_QUEUE_INFO", maximum: limits.maximumOperatorMessages)
        return try rows.map { row in
            let severity = try row.requiredInt("SEVERITY")
            guard (0...99).contains(severity) else { throw row.invalid("SEVERITY") }
            return OperatorMessageRecord(
                rowIndex: row.index,
                messageID: try bounded(row.optionalString("MESSAGE_ID"), maximum: 7, row: row, column: "MESSAGE_ID"),
                type: try boundedRequired(row.requiredString("MESSAGE_TYPE"), maximum: 22, row: row, column: "MESSAGE_TYPE").uppercased(),
                severity: severity,
                timestamp: try row.optionalDate("MESSAGE_TIMESTAMP"),
                text: try bounded(row.optionalText("MESSAGE_TEXT"), maximum: limits.maximumMessageCharacters, row: row, column: "MESSAGE_TEXT"),
                secondLevelText: try bounded(row.optionalText("MESSAGE_SECOND_LEVEL_TEXT"), maximum: limits.maximumSecondLevelCharacters, row: row, column: "MESSAGE_SECOND_LEVEL_TEXT"),
                fromUser: try bounded(row.optionalString("FROM_USER"), maximum: 10, row: row, column: "FROM_USER"),
                fromJob: try row.optionalString("FROM_JOB").map(IBMQualifiedJobName.init),
                fromProgram: try bounded(row.optionalString("FROM_PROGRAM"), maximum: 10, row: row, column: "FROM_PROGRAM")
            )
        }
    }

    private func queueIdentity(
        library: String?,
        name: String?,
        row: Row,
        prefix: String
    ) throws -> IBMQueueIdentity? {
        switch (library, name) {
        case (nil, nil):
            return nil
        case (.some(let library), .some(let name)):
            return IBMQueueIdentity(
                library: try systemName(library, field: "\(prefix)_LIBRARY", row: row),
                name: try systemName(name, field: "\(prefix)_NAME", row: row)
            )
        default:
            throw row.invalid("\(prefix)_IDENTITY")
        }
    }

    private func bounded(
        _ value: String?,
        maximum: Int,
        row: Row,
        column: String
    ) throws -> String? {
        guard let value else { return nil }
        guard value.count <= maximum else {
            throw JobIncidentError.textTooLarge(
                surface: row.surface,
                index: row.index,
                column: column,
                maximum: maximum
            )
        }
        guard !value.contains("\0"), value.unicodeScalars.allSatisfy({ scalar in
            !CharacterSet.controlCharacters.contains(scalar) || scalar.value == 10 || scalar.value == 9
        }) else {
            throw row.invalid(column)
        }
        return value
    }

    private func boundedRequired(
        _ value: String,
        maximum: Int,
        row: Row,
        column: String
    ) throws -> String {
        guard let checked = try bounded(value, maximum: maximum, row: row, column: column) else {
            throw row.invalid(column)
        }
        return checked
    }

    private func systemName(_ value: String, field: String, row: Row) throws -> IBMSystemObjectName {
        do {
            return try IBMSystemObjectName(value)
        } catch {
            throw row.invalid(field)
        }
    }

    private struct Rows: Sequence {
        let surface: String
        let columns: [String: Int]
        let values: [[SQLValue]]

        init(result: SQLResult, surface: String, maximum: Int) throws {
            guard result.rows.count <= maximum else {
                throw JobIncidentError.tooManyRows(surface: surface, maximum: maximum)
            }
            var columns: [String: Int] = [:]
            for (index, column) in result.columns.enumerated() {
                let key = column.name.uppercased()
                guard columns[key] == nil else {
                    throw JobIncidentError.duplicateColumn(surface: surface, column: key)
                }
                columns[key] = index
            }
            for (index, row) in result.rows.enumerated() where row.count != result.columns.count {
                throw JobIncidentError.malformedRow(surface: surface, index: index + 1)
            }
            self.surface = surface
            self.columns = columns
            values = result.rows
        }

        func makeIterator() -> AnyIterator<Row> {
            var offset = 0
            return AnyIterator {
                guard offset < values.count else { return nil }
                defer { offset += 1 }
                return Row(surface: surface, index: offset + 1, columns: columns, values: values[offset])
            }
        }

        func map<T>(_ transform: (Row) throws -> T) rethrows -> [T] {
            try Array(self).map(transform)
        }
    }

    private struct Row {
        let surface: String
        let index: Int
        let columns: [String: Int]
        let values: [SQLValue]

        func invalid(_ column: String) -> JobIncidentError {
            .invalidValue(surface: surface, index: index, column: column)
        }

        func value(_ column: String) throws -> SQLValue {
            guard let position = columns[column.uppercased()] else {
                throw JobIncidentError.missingColumn(surface: surface, column: column)
            }
            guard values.indices.contains(position) else {
                throw JobIncidentError.malformedRow(surface: surface, index: index)
            }
            return values[position]
        }

        func requiredString(_ column: String) throws -> String {
            guard let value = try optionalString(column), !value.isEmpty else { throw invalid(column) }
            return value
        }

        func optionalString(_ column: String) throws -> String? {
            switch try value(column) {
            case .null: nil
            case .string(let value): value.trimmingCharacters(in: .whitespacesAndNewlines)
            case .integer(let value): String(value)
            case .decimal(let value): value
            case .boolean(let value): value ? "YES" : "NO"
            default: throw invalid(column)
            }
        }

        func optionalText(_ column: String) throws -> String? {
            switch try value(column) {
            case .null: nil
            case .string(let value): value
            default: throw invalid(column)
            }
        }

        func requiredInt(_ column: String) throws -> Int {
            guard let value = try optionalInt(column) else { throw invalid(column) }
            return value
        }

        func optionalInt(_ column: String) throws -> Int? {
            guard let value = try optionalInt64(column) else { return nil }
            guard let converted = Int(exactly: value) else { throw invalid(column) }
            return converted
        }

        func optionalInt64(_ column: String) throws -> Int64? {
            switch try value(column) {
            case .null:
                return nil
            case .integer(let value):
                return value
            case .decimal(let value), .string(let value):
                guard let parsed = Int64(value) else { throw invalid(column) }
                return parsed
            default: throw invalid(column)
            }
        }

        func optionalDate(_ column: String) throws -> Date? {
            switch try value(column) {
            case .null: nil
            case .date(let value), .timestamp(let value): value
            default: throw invalid(column)
            }
        }
    }
}
