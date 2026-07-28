import Foundation

public struct SpooledOutputLimits: Equatable, Sendable {
    public var maximumInventoryRows: Int
    public var maximumQueueRows: Int
    public var maximumPreviewRecords: Int
    public var maximumPreviewRecordCharacters: Int
    public var queryTimeoutSeconds: Int

    public init(
        maximumInventoryRows: Int = 250,
        maximumQueueRows: Int = 100,
        maximumPreviewRecords: Int = 2_000,
        maximumPreviewRecordCharacters: Int = 378,
        queryTimeoutSeconds: Int = 30
    ) {
        self.maximumInventoryRows = maximumInventoryRows
        self.maximumQueueRows = maximumQueueRows
        self.maximumPreviewRecords = maximumPreviewRecords
        self.maximumPreviewRecordCharacters = maximumPreviewRecordCharacters
        self.queryTimeoutSeconds = queryTimeoutSeconds
    }

    public static let standard = SpooledOutputLimits()
}

public enum SpooledOutputError: Error, Equatable, LocalizedError, Sendable {
    case invalidSpooledFileNumber
    case invalidSystemName(field: String)
    case tooManyRows(surface: String, maximum: Int)
    case duplicateColumn(surface: String, column: String)
    case missingColumn(surface: String, column: String)
    case malformedRow(surface: String, index: Int)
    case invalidValue(surface: String, index: Int, column: String)
    case textTooLarge(surface: String, index: Int, column: String, maximum: Int)
    case duplicatePreviewOrdinal(Int)
    case comparisonFileMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidSpooledFileNumber:
            "The spooled-file number must be a positive 32-bit integer."
        case .invalidSystemName(let field):
            "The \(field) value is not a valid bounded IBM system name."
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
        case .duplicatePreviewOrdinal(let ordinal):
            "The spooled-file preview contains duplicate record ordinal \(ordinal)."
        case .comparisonFileMismatch:
            "Only previews with the same spooled-file name can be compared."
        }
    }
}

public struct SpooledFileIdentity: Hashable, Sendable, Identifiable, CustomStringConvertible {
    public let job: IBMQualifiedJobName
    public let file: IBMSystemObjectName
    public let number: Int
    public let system: IBMSystemObjectName?

    public var id: String {
        "\(system?.value ?? "-"):\(job.rawValue):\(file.value):\(number)"
    }

    public var description: String {
        "\(job.rawValue) · \(file.value) #\(number)"
    }

    public init(
        job: IBMQualifiedJobName,
        file: IBMSystemObjectName,
        number: Int,
        system: IBMSystemObjectName? = nil
    ) throws {
        guard (1...Int(Int32.max)).contains(number) else {
            throw SpooledOutputError.invalidSpooledFileNumber
        }
        self.job = job
        self.file = file
        self.number = number
        self.system = system
    }
}

public enum SpooledFileStatus: String, CaseIterable, Sendable {
    case closed = "CLOSED"
    case deferred = "DEFERRED"
    case deleted = "DELETED"
    case held = "HELD"
    case messageWaiting = "MESSAGE WAITING"
    case open = "OPEN"
    case pending = "PENDING"
    case printing = "PRINTING"
    case ready = "READY"
    case saved = "SAVED"
    case sending = "SENDING"
    case writing = "WRITING"
}

public enum SpooledFileAvailability: String, CaseIterable, Sendable {
    case immediate = "*IMMED"
    case fileEnd = "*FILEEND"
    case jobEnd = "*JOBEND"
}

public struct SpooledFileRecord: Equatable, Sendable, Identifiable {
    public let identity: SpooledFileIdentity
    public let status: SpooledFileStatus
    public let outputPriority: Int?
    public let creationTimestamp: Date?
    public let userData: String?
    public let sizeBytes: Int64?
    public let totalPages: Int?
    public let copies: Int?
    public let availability: SpooledFileAvailability?
    public let formType: String?
    public let outputQueue: IBMQueueIdentity?
    public let aspNumber: Int?
    public let ippJobID: Int64?

    public var id: SpooledFileIdentity { identity }
    public var isContentAvailable: Bool { status != .deleted }

    public init(
        identity: SpooledFileIdentity,
        status: SpooledFileStatus,
        outputPriority: Int? = nil,
        creationTimestamp: Date? = nil,
        userData: String? = nil,
        sizeBytes: Int64? = nil,
        totalPages: Int? = nil,
        copies: Int? = nil,
        availability: SpooledFileAvailability? = nil,
        formType: String? = nil,
        outputQueue: IBMQueueIdentity? = nil,
        aspNumber: Int? = nil,
        ippJobID: Int64? = nil
    ) {
        self.identity = identity
        self.status = status
        self.outputPriority = outputPriority
        self.creationTimestamp = creationTimestamp
        self.userData = userData
        self.sizeBytes = sizeBytes
        self.totalPages = totalPages
        self.copies = copies
        self.availability = availability
        self.formType = formType
        self.outputQueue = outputQueue
        self.aspNumber = aspNumber
        self.ippJobID = ippJobID
    }
}

public enum OutputQueueStatus: String, Sendable {
    case held = "HELD"
    case released = "RELEASED"
}

public struct OutputQueueRecord: Equatable, Sendable, Identifiable {
    public let identity: IBMQueueIdentity
    public let numberOfFiles: Int
    public let numberOfWriters: Int
    public let printerDeviceName: IBMSystemObjectName?
    public let orderOfFiles: String
    public let displayAnyFile: String
    public let operatorControlled: Bool
    public let authorityToCheck: String
    public let status: OutputQueueStatus
    public let writerJob: IBMQualifiedJobName?
    public let writerJobStatus: String?
    public let writerType: String?
    public let textDescription: String?

    public var id: IBMQueueIdentity { identity }

    public init(
        identity: IBMQueueIdentity,
        numberOfFiles: Int,
        numberOfWriters: Int,
        printerDeviceName: IBMSystemObjectName? = nil,
        orderOfFiles: String,
        displayAnyFile: String,
        operatorControlled: Bool,
        authorityToCheck: String,
        status: OutputQueueStatus,
        writerJob: IBMQualifiedJobName? = nil,
        writerJobStatus: String? = nil,
        writerType: String? = nil,
        textDescription: String? = nil
    ) {
        self.identity = identity
        self.numberOfFiles = numberOfFiles
        self.numberOfWriters = numberOfWriters
        self.printerDeviceName = printerDeviceName
        self.orderOfFiles = orderOfFiles
        self.displayAnyFile = displayAnyFile
        self.operatorControlled = operatorControlled
        self.authorityToCheck = authorityToCheck
        self.status = status
        self.writerJob = writerJob
        self.writerJobStatus = writerJobStatus
        self.writerType = writerType
        self.textDescription = textDescription
    }
}

public struct SpooledTextRecord: Equatable, Sendable, Identifiable {
    public let ordinalPosition: Int
    public let text: String
    public var id: Int { ordinalPosition }

    public init(ordinalPosition: Int, text: String) {
        self.ordinalPosition = ordinalPosition
        self.text = text
    }
}

public struct SpooledTextPreview: Equatable, Sendable {
    public let identity: SpooledFileIdentity
    public let targetName: String
    public let capturedAt: Date
    public let records: [SpooledTextRecord]
    public let isComplete: Bool
    public let contentFingerprint: String

    public var text: String { records.map(\.text).joined(separator: "\n") }

    public init(
        identity: SpooledFileIdentity,
        targetName: String,
        capturedAt: Date,
        records: [SpooledTextRecord],
        isComplete: Bool
    ) {
        self.identity = identity
        self.targetName = targetName
        self.capturedAt = capturedAt
        self.records = records
        self.isComplete = isComplete
        contentFingerprint = AIContentFingerprint.sha256(
            records.map { "\($0.ordinalPosition):\($0.text)" }.joined(separator: "\n")
        )
    }
}

public struct SpooledTextComparison: Equatable, Sendable {
    public let currentIdentity: SpooledFileIdentity
    public let baselineIdentity: SpooledFileIdentity
    public let baselineFingerprint: String
    public let currentFingerprint: String
    public let changedOrdinalCount: Int
    public let addedRecordCount: Int
    public let removedRecordCount: Int
    public let firstDifferenceOrdinal: Int?
    public let comparisonBasis: String

    public var isIdentical: Bool { baselineFingerprint == currentFingerprint }

    public init(baseline: SpooledTextPreview, current: SpooledTextPreview) throws {
        guard baseline.identity.file == current.identity.file else {
            throw SpooledOutputError.comparisonFileMismatch
        }
        currentIdentity = current.identity
        baselineIdentity = baseline.identity
        baselineFingerprint = baseline.contentFingerprint
        currentFingerprint = current.contentFingerprint
        let sharedCount = min(baseline.records.count, current.records.count)
        let differences = (0..<sharedCount).filter {
            baseline.records[$0].ordinalPosition != current.records[$0].ordinalPosition
                || baseline.records[$0].text != current.records[$0].text
        }
        changedOrdinalCount = differences.count
        addedRecordCount = max(0, current.records.count - baseline.records.count)
        removedRecordCount = max(0, baseline.records.count - current.records.count)
        if let first = differences.first {
            firstDifferenceOrdinal = current.records[first].ordinalPosition
        } else if current.records.count > sharedCount {
            firstDifferenceOrdinal = current.records[sharedCount].ordinalPosition
        } else if baseline.records.count > sharedCount {
            firstDifferenceOrdinal = baseline.records[sharedCount].ordinalPosition
        } else {
            firstDifferenceOrdinal = nil
        }
        comparisonBasis = "The two exact spool identities are preserved separately. Records are compared in service order by ordinal and exact text; this does not prove report lineage, page layout, or AFP/IPDS fidelity."
    }
}

public enum SpooledOutputEvidenceSource: String, CaseIterable, Sendable {
    case spooledFileInfo = "SPOOLED_FILE_INFO"
    case outputQueueInfo = "OUTPUT_QUEUE_INFO"
    case spooledFileData = "SPOOLED_FILE_DATA"
}

public enum SpooledOutputEvidenceOutcome: Equatable, Sendable {
    case collected
    case unavailable(String)

    public var isCollected: Bool {
        if case .collected = self { return true }
        return false
    }
}

public struct SpooledOutputEvidenceReceipt: Equatable, Sendable, Identifiable {
    public let source: SpooledOutputEvidenceSource
    public let rowCount: Int
    public let boundWasReached: Bool
    public let queryFingerprint: String
    public let outcome: SpooledOutputEvidenceOutcome

    public var id: SpooledOutputEvidenceSource { source }

    public init(
        source: SpooledOutputEvidenceSource,
        rowCount: Int,
        boundWasReached: Bool,
        queryFingerprint: String,
        outcome: SpooledOutputEvidenceOutcome
    ) {
        self.source = source
        self.rowCount = rowCount
        self.boundWasReached = boundWasReached
        self.queryFingerprint = queryFingerprint
        self.outcome = outcome
    }
}

public struct SpooledOutputSnapshot: Equatable, Sendable {
    public let targetName: String
    public let capturedAt: Date
    public let files: [SpooledFileRecord]
    public let queues: [OutputQueueRecord]
    public let receipts: [SpooledOutputEvidenceReceipt]

    public init(
        targetName: String,
        capturedAt: Date,
        files: [SpooledFileRecord],
        queues: [OutputQueueRecord],
        receipts: [SpooledOutputEvidenceReceipt]
    ) {
        self.targetName = targetName
        self.capturedAt = capturedAt
        self.files = files
        self.queues = queues
        self.receipts = receipts
    }

    public func file(_ identity: SpooledFileIdentity) -> SpooledFileRecord? {
        files.first(where: { $0.identity == identity })
    }

    public func queue(for file: SpooledFileRecord) -> OutputQueueRecord? {
        guard let identity = file.outputQueue else { return nil }
        return queues.first(where: { $0.identity == identity })
    }

    public var gaps: [SpooledOutputEvidenceReceipt] {
        receipts.filter { !$0.outcome.isCollected }
    }
}

public struct SpooledOutputSQLPlanner: Sendable {
    public let limits: SpooledOutputLimits

    public init(limits: SpooledOutputLimits = .standard) {
        self.limits = limits
    }

    public var inventory: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT SPOOLED_FILE_NAME,
                   SPOOLED_FILE_NUMBER,
                   STATUS,
                   OUTPUT_PRIORITY,
                   CREATION_TIMESTAMP,
                   USER_DATA,
                   SIZE,
                   TOTAL_PAGES,
                   COPIES,
                   QUALIFIED_JOB_NAME,
                   FILE_AVAILABLE,
                   FORM_TYPE,
                   OUTPUT_QUEUE_LIBRARY,
                   OUTPUT_QUEUE,
                   ASP_NUMBER,
                   SYSTEM,
                   INTERNET_PRINT_PROTOCOL_JOB_ID
              FROM TABLE(QSYS2.SPOOLED_FILE_INFO(
                       USER_NAME => '*ALL',
                       STATUS => '*ALL',
                       JOB_NAME => '*ALL',
                       OUTPUT_QUEUE => '*ALL',
                       USER_DATA => '*ALL',
                       FORM_TYPE => '*ALL',
                       SYSTEM_NAME => '*ALL'
                   )) AS S
             ORDER BY CREATION_TIMESTAMP DESC,
                      QUALIFIED_JOB_NAME,
                      SPOOLED_FILE_NAME,
                      SPOOLED_FILE_NUMBER DESC
             FETCH FIRST \(limits.maximumInventoryRows) ROWS ONLY
            """,
            maximumRows: limits.maximumInventoryRows,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }

    public var outputQueues: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT OUTPUT_QUEUE_NAME,
                   OUTPUT_QUEUE_LIBRARY_NAME,
                   NUMBER_OF_FILES,
                   NUMBER_OF_WRITERS,
                   PRINTER_DEVICE_NAME,
                   ORDER_OF_FILES,
                   DISPLAY_ANY_FILE,
                   OPERATOR_CONTROLLED,
                   AUTHORITY_TO_CHECK,
                   OUTPUT_QUEUE_STATUS,
                   WRITER_JOB_NAME,
                   WRITER_JOB_STATUS,
                   WRITER_TYPE,
                   TEXT_DESCRIPTION
              FROM QSYS2.OUTPUT_QUEUE_INFO
             ORDER BY NUMBER_OF_FILES DESC,
                      OUTPUT_QUEUE_LIBRARY_NAME,
                      OUTPUT_QUEUE_NAME
             FETCH FIRST \(limits.maximumQueueRows) ROWS ONLY
            """,
            maximumRows: limits.maximumQueueRows,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }

    public func preview(_ identity: SpooledFileIdentity) -> SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT ORDINAL_POSITION,
                   SPOOLED_DATA
              FROM TABLE(SYSTOOLS.SPOOLED_FILE_DATA(
                       JOB_NAME => '\(identity.job.rawValue)',
                       SPOOLED_FILE_NAME => '\(identity.file.value)',
                       SPOOLED_FILE_NUMBER => \(identity.number),
                       IGNORE_ERRORS => 'NO'
                   )) AS D
             ORDER BY ORDINAL_POSITION
             FETCH FIRST \(limits.maximumPreviewRecords) ROWS ONLY
            """,
            maximumRows: limits.maximumPreviewRecords,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }
}

public struct SpooledOutputSQLDecoder: Sendable {
    public let limits: SpooledOutputLimits

    public init(limits: SpooledOutputLimits = .standard) {
        self.limits = limits
    }

    public func decodeInventory(_ result: SQLResult) throws -> [SpooledFileRecord] {
        let rows = try Rows(result: result, surface: "SPOOLED_FILE_INFO", maximum: limits.maximumInventoryRows)
        return try rows.map { row in
            let number = try row.requiredInt("SPOOLED_FILE_NUMBER")
            guard (1...Int(Int32.max)).contains(number) else { throw row.invalid("SPOOLED_FILE_NUMBER") }
            let identity = try SpooledFileIdentity(
                job: try IBMQualifiedJobName(try row.requiredString("QUALIFIED_JOB_NAME")),
                file: systemName(try row.requiredString("SPOOLED_FILE_NAME"), field: "SPOOLED_FILE_NAME", row: row),
                number: number,
                system: try row.optionalString("SYSTEM").map {
                    try systemName($0, field: "SYSTEM", row: row)
                }
            )
            guard let status = SpooledFileStatus(rawValue: try row.requiredString("STATUS").uppercased()) else {
                throw row.invalid("STATUS")
            }
            let priority = try row.optionalInt("OUTPUT_PRIORITY")
            if let priority, !(1...9).contains(priority) { throw row.invalid("OUTPUT_PRIORITY") }
            let size = try row.optionalInt64("SIZE")
            if let size, size < 0 { throw row.invalid("SIZE") }
            let pages = try row.optionalInt("TOTAL_PAGES")
            if let pages, pages < 0 { throw row.invalid("TOTAL_PAGES") }
            let copies = try row.optionalInt("COPIES")
            if let copies, copies < 0 { throw row.invalid("COPIES") }
            let asp = try row.optionalInt("ASP_NUMBER")
            if let asp, asp < 1 { throw row.invalid("ASP_NUMBER") }
            let ippJobID = try row.optionalInt64("INTERNET_PRINT_PROTOCOL_JOB_ID")
            if let ippJobID, ippJobID < 1 { throw row.invalid("INTERNET_PRINT_PROTOCOL_JOB_ID") }
            let availability: SpooledFileAvailability?
            if let value = try row.optionalString("FILE_AVAILABLE")?.uppercased() {
                guard let parsed = SpooledFileAvailability(rawValue: value) else { throw row.invalid("FILE_AVAILABLE") }
                availability = parsed
            } else {
                availability = nil
            }

            return SpooledFileRecord(
                identity: identity,
                status: status,
                outputPriority: priority,
                creationTimestamp: try row.optionalDate("CREATION_TIMESTAMP"),
                userData: try bounded(row.optionalString("USER_DATA"), maximum: 10, row: row, column: "USER_DATA"),
                sizeBytes: size,
                totalPages: pages,
                copies: copies,
                availability: availability,
                formType: try bounded(row.optionalString("FORM_TYPE"), maximum: 10, row: row, column: "FORM_TYPE"),
                outputQueue: try queueIdentity(
                    library: row.optionalString("OUTPUT_QUEUE_LIBRARY"),
                    name: row.optionalString("OUTPUT_QUEUE"),
                    row: row
                ),
                aspNumber: asp,
                ippJobID: ippJobID
            )
        }
    }

    public func decodeQueues(_ result: SQLResult) throws -> [OutputQueueRecord] {
        let rows = try Rows(result: result, surface: "OUTPUT_QUEUE_INFO", maximum: limits.maximumQueueRows)
        return try rows.map { row in
            let numberOfFiles = try row.requiredInt("NUMBER_OF_FILES")
            let numberOfWriters = try row.requiredInt("NUMBER_OF_WRITERS")
            guard numberOfFiles >= 0 else { throw row.invalid("NUMBER_OF_FILES") }
            guard numberOfWriters >= 0 else { throw row.invalid("NUMBER_OF_WRITERS") }
            let orderOfFiles = try boundedRequired(row.requiredString("ORDER_OF_FILES"), maximum: 7, row: row, column: "ORDER_OF_FILES").uppercased()
            guard ["*FIFO", "*JOBNBR"].contains(orderOfFiles) else { throw row.invalid("ORDER_OF_FILES") }
            let displayAnyFile = try boundedRequired(row.requiredString("DISPLAY_ANY_FILE"), maximum: 6, row: row, column: "DISPLAY_ANY_FILE").uppercased()
            guard ["*NO", "*OWNER", "*YES"].contains(displayAnyFile) else { throw row.invalid("DISPLAY_ANY_FILE") }
            let operatorControlledValue = try boundedRequired(row.requiredString("OPERATOR_CONTROLLED"), maximum: 4, row: row, column: "OPERATOR_CONTROLLED").uppercased()
            guard ["*NO", "*YES"].contains(operatorControlledValue) else { throw row.invalid("OPERATOR_CONTROLLED") }
            let authorityToCheck = try boundedRequired(row.requiredString("AUTHORITY_TO_CHECK"), maximum: 7, row: row, column: "AUTHORITY_TO_CHECK").uppercased()
            guard ["*DTAAUT", "*OWNER"].contains(authorityToCheck) else { throw row.invalid("AUTHORITY_TO_CHECK") }
            guard let status = OutputQueueStatus(rawValue: try row.requiredString("OUTPUT_QUEUE_STATUS").uppercased()) else {
                throw row.invalid("OUTPUT_QUEUE_STATUS")
            }
            let writerStatus = try bounded(row.optionalString("WRITER_JOB_STATUS"), maximum: 4, row: row, column: "WRITER_JOB_STATUS")?.uppercased()
            if let writerStatus, !["END", "HLD", "JOBQ", "MSGW", "STR"].contains(writerStatus) {
                throw row.invalid("WRITER_JOB_STATUS")
            }
            let writerType = try bounded(row.optionalString("WRITER_TYPE"), maximum: 7, row: row, column: "WRITER_TYPE")?.uppercased()
            if let writerType, !["PRINTER", "REMOTE"].contains(writerType) {
                throw row.invalid("WRITER_TYPE")
            }

            return OutputQueueRecord(
                identity: IBMQueueIdentity(
                    library: try systemName(try row.requiredString("OUTPUT_QUEUE_LIBRARY_NAME"), field: "OUTPUT_QUEUE_LIBRARY_NAME", row: row),
                    name: try systemName(try row.requiredString("OUTPUT_QUEUE_NAME"), field: "OUTPUT_QUEUE_NAME", row: row)
                ),
                numberOfFiles: numberOfFiles,
                numberOfWriters: numberOfWriters,
                printerDeviceName: try row.optionalString("PRINTER_DEVICE_NAME").map {
                    try systemName($0, field: "PRINTER_DEVICE_NAME", row: row)
                },
                orderOfFiles: orderOfFiles,
                displayAnyFile: displayAnyFile,
                operatorControlled: operatorControlledValue == "*YES",
                authorityToCheck: authorityToCheck,
                status: status,
                writerJob: try row.optionalString("WRITER_JOB_NAME").map(IBMQualifiedJobName.init),
                writerJobStatus: writerStatus,
                writerType: writerType,
                textDescription: try bounded(row.optionalString("TEXT_DESCRIPTION"), maximum: 50, row: row, column: "TEXT_DESCRIPTION")
            )
        }
    }

    public func decodePreview(
        _ result: SQLResult,
        identity: SpooledFileIdentity
    ) throws -> SpooledTextPreview {
        let rows = try Rows(result: result, surface: "SPOOLED_FILE_DATA", maximum: limits.maximumPreviewRecords)
        var seen = Set<Int>()
        let records = try rows.map { row in
            let ordinal = try row.requiredInt("ORDINAL_POSITION")
            guard ordinal > 0 else { throw row.invalid("ORDINAL_POSITION") }
            guard seen.insert(ordinal).inserted else { throw SpooledOutputError.duplicatePreviewOrdinal(ordinal) }
            let text = try bounded(
                row.optionalText("SPOOLED_DATA") ?? "",
                maximum: limits.maximumPreviewRecordCharacters,
                row: row,
                column: "SPOOLED_DATA"
            ) ?? ""
            return SpooledTextRecord(ordinalPosition: ordinal, text: text)
        }
        .sorted { $0.ordinalPosition < $1.ordinalPosition }
        return SpooledTextPreview(
            identity: identity,
            targetName: result.targetName,
            capturedAt: Date(),
            records: records,
            isComplete: !result.wasTruncated && records.count < limits.maximumPreviewRecords
        )
    }

    private func queueIdentity(
        library: String?,
        name: String?,
        row: Row
    ) throws -> IBMQueueIdentity? {
        switch (library, name) {
        case (nil, nil):
            nil
        case (.some(let library), .some(let name)):
            IBMQueueIdentity(
                library: try systemName(library, field: "OUTPUT_QUEUE_LIBRARY", row: row),
                name: try systemName(name, field: "OUTPUT_QUEUE", row: row)
            )
        default:
            throw row.invalid("OUTPUT_QUEUE_IDENTITY")
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
            throw SpooledOutputError.textTooLarge(
                surface: row.surface,
                index: row.index,
                column: column,
                maximum: maximum
            )
        }
        guard !value.contains("\0"), value.unicodeScalars.allSatisfy({ scalar in
            !CharacterSet.controlCharacters.contains(scalar) || scalar.value == 9
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
            throw SpooledOutputError.invalidValue(surface: row.surface, index: row.index, column: field)
        }
    }

    private struct Rows: Sequence {
        let surface: String
        let columns: [String: Int]
        let values: [[SQLValue]]

        init(result: SQLResult, surface: String, maximum: Int) throws {
            guard result.rows.count <= maximum else {
                throw SpooledOutputError.tooManyRows(surface: surface, maximum: maximum)
            }
            var columns: [String: Int] = [:]
            for (index, column) in result.columns.enumerated() {
                let key = column.name.uppercased()
                guard columns[key] == nil else {
                    throw SpooledOutputError.duplicateColumn(surface: surface, column: key)
                }
                columns[key] = index
            }
            for (index, row) in result.rows.enumerated() where row.count != result.columns.count {
                throw SpooledOutputError.malformedRow(surface: surface, index: index + 1)
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

        func invalid(_ column: String) -> SpooledOutputError {
            .invalidValue(surface: surface, index: index, column: column)
        }

        func value(_ column: String) throws -> SQLValue {
            guard let position = columns[column.uppercased()] else {
                throw SpooledOutputError.missingColumn(surface: surface, column: column)
            }
            guard values.indices.contains(position) else {
                throw SpooledOutputError.malformedRow(surface: surface, index: index)
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
                guard let parsed = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw invalid(column)
                }
                return parsed
            default:
                throw invalid(column)
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
