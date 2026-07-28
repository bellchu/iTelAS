import Foundation

public struct SystemHealthLimits: Equatable, Sendable {
    public var maximumASPs: Int
    public var maximumLimitOccurrences: Int
    public var maximumPTFGroups: Int
    public var queryTimeoutSeconds: Int
    public var cpuSampleSeconds: Int

    public init(
        maximumASPs: Int = 64,
        maximumLimitOccurrences: Int = 100,
        maximumPTFGroups: Int = 100,
        queryTimeoutSeconds: Int = 30,
        cpuSampleSeconds: Int = 1
    ) {
        self.maximumASPs = maximumASPs
        self.maximumLimitOccurrences = maximumLimitOccurrences
        self.maximumPTFGroups = maximumPTFGroups
        self.queryTimeoutSeconds = queryTimeoutSeconds
        self.cpuSampleSeconds = cpuSampleSeconds
    }

    public static let standard = SystemHealthLimits()
}

public enum SystemHealthError: Error, Equatable, LocalizedError, Sendable {
    case duplicateColumn(surface: String, column: String)
    case missingColumn(surface: String, column: String)
    case malformedRow(surface: String, index: Int)
    case unexpectedRowCount(surface: String, expected: Int, actual: Int)
    case tooManyRows(surface: String, maximum: Int)
    case truncatedSingleton(surface: String)
    case invalidValue(surface: String, index: Int, column: String)
    case invalidText(surface: String, index: Int, column: String)
    case invalidCapacity(surface: String, index: Int)

    public var errorDescription: String? {
        switch self {
        case .duplicateColumn(let surface, let column):
            "The \(surface) result contains an ambiguous duplicate \(column) column."
        case .missingColumn(let surface, let column):
            "The \(surface) result does not contain the required \(column) column."
        case .malformedRow(let surface, let index):
            "The \(surface) result row \(index) does not match its column layout."
        case .unexpectedRowCount(let surface, let expected, let actual):
            "The \(surface) result returned \(actual) rows; exactly \(expected) were expected."
        case .tooManyRows(let surface, let maximum):
            "The \(surface) result exceeds the \(maximum)-row evidence limit."
        case .truncatedSingleton(let surface):
            "The singleton \(surface) result reached its transport bound and is ambiguous."
        case .invalidValue(let surface, let index, let column):
            "The \(surface) result row \(index) contains an invalid \(column) value."
        case .invalidText(let surface, let index, let column):
            "The \(surface) result row \(index) contains unsafe or oversized \(column) text."
        case .invalidCapacity(let surface, let index):
            "The \(surface) result row \(index) contains an impossible capacity relationship."
        }
    }
}

public enum SystemHealthSeverity: String, CaseIterable, Equatable, Sendable {
    case stable
    case watch
    case warning
    case critical

    public var label: String { rawValue.uppercased() }
}

public struct SystemStatusEvidence: Equatable, Sendable {
    public let totalJobs: Int
    public let maximumJobs: Int
    public let activeJobs: Int
    public let systemASPStorageMB: Int64
    public let systemASPUsedPercent: Decimal
    public let currentTemporaryStorageMB: Int64
    public let maximumTemporaryStorageMB: Int64
    public let totalJobTableEntries: Int
    public let availableJobTableEntries: Int
    public let inUseJobTableEntries: Int
    public let attentionLight: Bool
    public let restrictedState: Bool

    public init(
        totalJobs: Int,
        maximumJobs: Int,
        activeJobs: Int,
        systemASPStorageMB: Int64,
        systemASPUsedPercent: Decimal,
        currentTemporaryStorageMB: Int64,
        maximumTemporaryStorageMB: Int64,
        totalJobTableEntries: Int,
        availableJobTableEntries: Int,
        inUseJobTableEntries: Int,
        attentionLight: Bool,
        restrictedState: Bool
    ) throws {
        guard totalJobs >= 0, maximumJobs > 0, activeJobs >= 0,
              systemASPStorageMB >= 0,
              systemASPUsedPercent >= 0, systemASPUsedPercent <= 100,
              currentTemporaryStorageMB >= 0, maximumTemporaryStorageMB >= 0,
              totalJobTableEntries > 0,
              availableJobTableEntries >= 0, inUseJobTableEntries >= 0,
              availableJobTableEntries <= totalJobTableEntries,
              inUseJobTableEntries <= totalJobTableEntries,
              availableJobTableEntries <= totalJobTableEntries - inUseJobTableEntries,
              maximumTemporaryStorageMB == 0 || currentTemporaryStorageMB <= maximumTemporaryStorageMB else {
            throw SystemHealthError.invalidCapacity(surface: "SYSTEM_STATUS_INFO", index: 1)
        }
        self.totalJobs = totalJobs
        self.maximumJobs = maximumJobs
        self.activeJobs = activeJobs
        self.systemASPStorageMB = systemASPStorageMB
        self.systemASPUsedPercent = systemASPUsedPercent
        self.currentTemporaryStorageMB = currentTemporaryStorageMB
        self.maximumTemporaryStorageMB = maximumTemporaryStorageMB
        self.totalJobTableEntries = totalJobTableEntries
        self.availableJobTableEntries = availableJobTableEntries
        self.inUseJobTableEntries = inUseJobTableEntries
        self.attentionLight = attentionLight
        self.restrictedState = restrictedState
    }

    public var jobTablePressure: Double {
        guard totalJobTableEntries > 0 else { return 0 }
        return Double(inUseJobTableEntries) / Double(totalJobTableEntries)
    }

    public var temporaryStoragePressureAgainstPeak: Double? {
        guard maximumTemporaryStorageMB > 0 else { return nil }
        return Double(currentTemporaryStorageMB) / Double(maximumTemporaryStorageMB)
    }
}

public struct SystemCPUActivitySample: Equatable, Sendable {
    public let sampleSeconds: Int
    public let averageCPUUtilization: Decimal?
    public let minimumCPUUtilization: Decimal?
    public let maximumCPUUtilization: Decimal?
    public let averageCPURate: Decimal?

    public init(
        sampleSeconds: Int,
        averageCPUUtilization: Decimal?,
        minimumCPUUtilization: Decimal?,
        maximumCPUUtilization: Decimal?,
        averageCPURate: Decimal?
    ) throws {
        let values = [averageCPUUtilization, minimumCPUUtilization, maximumCPUUtilization, averageCPURate]
            .compactMap { $0 }
        guard sampleSeconds >= 1, values.allSatisfy({ $0 >= 0 && $0 <= 1_000 }) else {
            throw SystemHealthError.invalidCapacity(surface: "SYSTEM_ACTIVITY_INFO", index: 1)
        }
        self.sampleSeconds = sampleSeconds
        self.averageCPUUtilization = averageCPUUtilization
        self.minimumCPUUtilization = minimumCPUUtilization
        self.maximumCPUUtilization = maximumCPUUtilization
        self.averageCPURate = averageCPURate
    }
}

public struct ASPHealthRecord: Equatable, Sendable, Identifiable {
    public let aspNumber: Int
    public let state: String
    public let type: String?
    public let relationalDatabaseName: String?
    public let numberOfDiskUnits: Int
    public let diskUnitsPresent: String
    public let isEncrypted: Bool?
    public let totalCapacityMB: Int64?
    public let availableCapacityMB: Int64?
    public let capacityValueExceededField: Bool
    public let storageThresholdPercent: Int

    public var id: Int { aspNumber }

    public init(
        aspNumber: Int,
        state: String,
        type: String?,
        relationalDatabaseName: String?,
        numberOfDiskUnits: Int,
        diskUnitsPresent: String,
        isEncrypted: Bool?,
        totalCapacityMB: Int64?,
        availableCapacityMB: Int64?,
        capacityValueExceededField: Bool = false,
        storageThresholdPercent: Int
    ) throws {
        guard (1...255).contains(aspNumber), numberOfDiskUnits >= 0,
              (0...100).contains(storageThresholdPercent) else {
            throw SystemHealthError.invalidCapacity(surface: "ASP_INFO", index: aspNumber)
        }
        if let totalCapacityMB, let availableCapacityMB {
            guard totalCapacityMB >= 0, availableCapacityMB >= 0,
                  availableCapacityMB <= totalCapacityMB else {
                throw SystemHealthError.invalidCapacity(surface: "ASP_INFO", index: aspNumber)
            }
        }
        self.aspNumber = aspNumber
        self.state = state
        self.type = type
        self.relationalDatabaseName = relationalDatabaseName
        self.numberOfDiskUnits = numberOfDiskUnits
        self.diskUnitsPresent = diskUnitsPresent
        self.isEncrypted = isEncrypted
        self.totalCapacityMB = totalCapacityMB
        self.availableCapacityMB = availableCapacityMB
        self.capacityValueExceededField = capacityValueExceededField
        self.storageThresholdPercent = storageThresholdPercent
    }

    public var usedPercent: Double? {
        guard let totalCapacityMB, let availableCapacityMB, totalCapacityMB > 0 else { return nil }
        return Double(totalCapacityMB - availableCapacityMB) / Double(totalCapacityMB) * 100
    }

    public var severity: SystemHealthSeverity {
        if state == "FAILED" || diskUnitsPresent == "NONE" || diskUnitsPresent == "SOME" {
            return .critical
        }
        guard let usedPercent else { return .watch }
        if usedPercent >= Double(storageThresholdPercent) { return .critical }
        if usedPercent >= Double(max(0, storageThresholdPercent - 10)) { return .warning }
        if usedPercent >= Double(max(0, storageThresholdPercent - 20)) { return .watch }
        return .stable
    }
}

public struct SystemLimitOccurrence: Equatable, Sendable, Identifiable {
    public let rowIndex: Int
    public let lastChangedAt: Date
    public let category: String
    public let type: String
    public let sizingName: String
    public let currentValue: Decimal
    public let maximumValue: Decimal
    public let limitID: Int
    public let systemSchemaName: String?
    public let systemObjectName: String?
    public let objectType: String?
    public let jobName: String?

    public var id: String {
        "\(limitID)|\(systemSchemaName ?? "")|\(systemObjectName ?? "")|\(jobName ?? "")|\(lastChangedAt.timeIntervalSince1970)|\(rowIndex)"
    }

    public init(
        rowIndex: Int,
        lastChangedAt: Date,
        category: String,
        type: String,
        sizingName: String,
        currentValue: Decimal,
        maximumValue: Decimal,
        limitID: Int,
        systemSchemaName: String?,
        systemObjectName: String?,
        objectType: String?,
        jobName: String?
    ) throws {
        guard rowIndex >= 1, currentValue >= 0, maximumValue > 0, limitID >= 0 else {
            throw SystemHealthError.invalidCapacity(surface: "SYSLIMITS", index: rowIndex)
        }
        self.rowIndex = rowIndex
        self.lastChangedAt = lastChangedAt
        self.category = category
        self.type = type
        self.sizingName = sizingName
        self.currentValue = currentValue
        self.maximumValue = maximumValue
        self.limitID = limitID
        self.systemSchemaName = systemSchemaName
        self.systemObjectName = systemObjectName
        self.objectType = objectType
        self.jobName = jobName
    }

    public var pressure: Double {
        NSDecimalNumber(decimal: currentValue).doubleValue
            / NSDecimalNumber(decimal: maximumValue).doubleValue
    }

    public var severity: SystemHealthSeverity {
        switch pressure {
        case 0.90...: .critical
        case 0.75..<0.90: .warning
        case 0.50..<0.75: .watch
        default: .stable
        }
    }

    public var identityLabel: String {
        if let jobName { return jobName }
        let object = [systemSchemaName, systemObjectName].compactMap { $0 }.joined(separator: "/")
        return object.isEmpty ? "SYSTEM" : object
    }
}

public enum PTFGroupState: Equatable, Sendable {
    case installed
    case applyAtNextIPL
    case notInstalled
    case error
    case unknown
    case notApplicable
    case supportedOnly
    case relatedGroup
    case onOrder
    case other(String)

    public init(rawValue: String) {
        self = switch rawValue.uppercased() {
        case "INSTALLED": .installed
        case "APPLY AT NEXT IPL": .applyAtNextIPL
        case "NOT INSTALLED": .notInstalled
        case "ERROR": .error
        case "UNKNOWN": .unknown
        case "NOT APPLICABLE": .notApplicable
        case "SUPPORTED ONLY": .supportedOnly
        case "RELATED GROUP": .relatedGroup
        case "ON ORDER": .onOrder
        default: .other(rawValue)
        }
    }

    public var label: String {
        switch self {
        case .installed: "INSTALLED"
        case .applyAtNextIPL: "APPLY AT NEXT IPL"
        case .notInstalled: "NOT INSTALLED"
        case .error: "ERROR"
        case .unknown: "UNKNOWN"
        case .notApplicable: "NOT APPLICABLE"
        case .supportedOnly: "SUPPORTED ONLY"
        case .relatedGroup: "RELATED GROUP"
        case .onOrder: "ON ORDER"
        case .other(let value): value
        }
    }

    public var penalty: Int {
        switch self {
        case .installed, .notApplicable, .supportedOnly, .relatedGroup: 0
        case .applyAtNextIPL, .onOrder: 2
        case .notInstalled: 4
        case .unknown, .other: 1
        case .error: 7
        }
    }
}

public struct PTFGroupRecord: Equatable, Sendable, Identifiable {
    public let collectedAt: Date
    public let name: String
    public let description: String?
    public let level: Int?
    public let targetRelease: String?
    public let state: PTFGroupState

    public var id: String { name }

    public init(
        collectedAt: Date,
        name: String,
        description: String?,
        level: Int?,
        targetRelease: String?,
        state: PTFGroupState
    ) throws {
        guard !name.isEmpty, name.count <= 60, level.map({ $0 >= 0 }) ?? true else {
            throw SystemHealthError.invalidValue(surface: "GROUP_PTF_INFO", index: 1, column: "PTF_GROUP_NAME")
        }
        self.collectedAt = collectedAt
        self.name = name
        self.description = description
        self.level = level
        self.targetRelease = targetRelease
        self.state = state
    }
}

public enum SystemHealthEvidenceSource: String, CaseIterable, Sendable {
    case systemStatus = "SYSTEM_STATUS_INFO"
    case systemActivity = "SYSTEM_ACTIVITY_INFO"
    case aspInfo = "ASP_INFO"
    case systemLimits = "SYSLIMITS"
    case groupPTFInfo = "GROUP_PTF_INFO"
    case certificateInfo = "CERTIFICATE_INFO"
}

public enum SystemHealthEvidenceOutcome: Equatable, Sendable {
    case collected
    case unavailable(String)

    public var isCollected: Bool {
        if case .collected = self { return true }
        return false
    }
}

public struct SystemHealthEvidenceReceipt: Equatable, Sendable, Identifiable {
    public let source: SystemHealthEvidenceSource
    public let rowCount: Int
    public let boundWasReached: Bool
    public let elapsedMilliseconds: Int?
    public let queryFingerprint: String
    public let outcome: SystemHealthEvidenceOutcome

    public var id: SystemHealthEvidenceSource { source }

    public init(
        source: SystemHealthEvidenceSource,
        rowCount: Int,
        boundWasReached: Bool,
        elapsedMilliseconds: Int?,
        queryFingerprint: String,
        outcome: SystemHealthEvidenceOutcome
    ) {
        self.source = source
        self.rowCount = rowCount
        self.boundWasReached = boundWasReached
        self.elapsedMilliseconds = elapsedMilliseconds
        self.queryFingerprint = queryFingerprint
        self.outcome = outcome
    }
}

public struct SystemHealthSnapshot: Equatable, Sendable {
    public let targetName: String
    public let capturedAt: Date
    public let status: SystemStatusEvidence?
    public let cpu: SystemCPUActivitySample?
    public let asps: [ASPHealthRecord]
    public let limits: [SystemLimitOccurrence]
    public let ptfGroups: [PTFGroupRecord]
    public let receipts: [SystemHealthEvidenceReceipt]
    public let isBundledReplay: Bool

    public init(
        targetName: String,
        capturedAt: Date,
        status: SystemStatusEvidence?,
        cpu: SystemCPUActivitySample?,
        asps: [ASPHealthRecord],
        limits: [SystemLimitOccurrence],
        ptfGroups: [PTFGroupRecord],
        receipts: [SystemHealthEvidenceReceipt],
        isBundledReplay: Bool = false
    ) {
        self.targetName = targetName
        self.capturedAt = capturedAt
        self.status = status
        self.cpu = cpu
        self.asps = asps.sorted { $0.aspNumber < $1.aspNumber }
        self.limits = limits.sorted {
            if $0.pressure != $1.pressure { return $0.pressure > $1.pressure }
            return $0.lastChangedAt > $1.lastChangedAt
        }
        self.ptfGroups = ptfGroups.sorted { $0.name < $1.name }
        self.receipts = receipts.sorted {
            let order = SystemHealthEvidenceSource.allCases
            return (order.firstIndex(of: $0.source) ?? order.endIndex)
                < (order.firstIndex(of: $1.source) ?? order.endIndex)
        }
        self.isBundledReplay = isBundledReplay
    }

    public var gaps: [SystemHealthEvidenceReceipt] {
        receipts.filter { !$0.outcome.isCollected }
    }

    public var systemASP: ASPHealthRecord? {
        asps.first(where: { $0.aspNumber == 1 })
    }

    public var assessment: SystemHealthAssessment {
        SystemHealthAssessment(snapshot: self)
    }
}

public struct SystemHealthAssessment: Equatable, Sendable {
    public let score: Int
    public let severity: SystemHealthSeverity
    public let limitsAtRisk: Int
    public let criticalLimitCount: Int
    public let warningLimitCount: Int
    public let method: String

    public init(snapshot: SystemHealthSnapshot) {
        let critical = snapshot.limits.filter { $0.severity == .critical }.count
        let warning = snapshot.limits.filter { $0.severity == .warning }.count
        let watch = snapshot.limits.filter { $0.severity == .watch }.count
        let limitPenalty = critical * 7 + warning * 3 + watch

        let aspPenalty = switch snapshot.systemASP?.severity {
        case .critical: 7
        case .warning: 4
        case .watch: 1
        default: 0
        }

        let cpuValue = snapshot.cpu?.averageCPUUtilization.map {
            NSDecimalNumber(decimal: $0).doubleValue
        }
        let cpuPenalty = switch cpuValue {
        case .some(90...): 7
        case .some(75..<90): 3
        default: 0
        }

        let maintenancePenalty = snapshot.ptfGroups.reduce(0) { $0 + $1.state.penalty }
        let computed = max(0, min(100, 100 - limitPenalty - aspPenalty - cpuPenalty - maintenancePenalty))
        score = computed
        severity = switch computed {
        case 85...: .stable
        case 70..<85: .watch
        case 50..<70: .warning
        default: .critical
        }
        limitsAtRisk = critical + warning
        criticalLimitCount = critical
        warningLimitCount = warning
        method = "Local heuristic: 100 minus visible limit, ASP, CPU, and PTF-status penalties. It is not an IBM score, trend, root-cause finding, or outage forecast."
    }
}

public struct SystemHealthSQLPlanner: Sendable {
    public let limits: SystemHealthLimits

    public init(limits: SystemHealthLimits = .standard) {
        self.limits = limits
    }

    public var systemStatus: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT TOTAL_JOBS_IN_SYSTEM,
                   MAXIMUM_JOBS_IN_SYSTEM,
                   ACTIVE_JOBS_IN_SYSTEM,
                   SYSTEM_ASP_STORAGE,
                   SYSTEM_ASP_USED,
                   CURRENT_TEMPORARY_STORAGE,
                   MAXIMUM_TEMPORARY_STORAGE_USED,
                   TOTAL_JOB_TABLE_ENTRIES,
                   AVAILABLE_JOB_TABLE_ENTRIES,
                   IN_USE_JOB_TABLE_ENTRIES,
                   ATTENTION_LIGHT,
                   RESTRICTED_STATE
              FROM QSYS2.SYSTEM_STATUS_INFO
             FETCH FIRST 2 ROWS ONLY
            """,
            maximumRows: 1,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }

    public var systemActivity: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT AVERAGE_CPU_RATE,
                   AVERAGE_CPU_UTILIZATION,
                   MINIMUM_CPU_UTILIZATION,
                   MAXIMUM_CPU_UTILIZATION
              FROM TABLE(QSYS2.SYSTEM_ACTIVITY_INFO(\(limits.cpuSampleSeconds))) AS A
             FETCH FIRST 2 ROWS ONLY
            """,
            maximumRows: 1,
            timeoutSeconds: max(limits.queryTimeoutSeconds, limits.cpuSampleSeconds + 5),
            readOnly: true
        )
    }

    public var aspInfo: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT ASP_NUMBER,
                   ASP_STATE,
                   ASP_TYPE,
                   RDB_NAME,
                   NUMBER_OF_DISK_UNITS,
                   DISK_UNITS_PRESENT,
                   ENCRYPTED_ASP,
                   TOTAL_CAPACITY,
                   TOTAL_CAPACITY_AVAILABLE,
                   STORAGE_THRESHOLD_PERCENTAGE
              FROM QSYS2.ASP_INFO
             ORDER BY ASP_NUMBER
             FETCH FIRST \(limits.maximumASPs + 1) ROWS ONLY
            """,
            maximumRows: limits.maximumASPs,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }

    public var systemLimits: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT LAST_CHANGE_TIMESTAMP,
                   LIMIT_CATEGORY,
                   LIMIT_TYPE,
                   SIZING_NAME,
                   CURRENT_VALUE,
                   MAXIMUM_VALUE,
                   LIMIT_ID,
                   SYSTEM_SCHEMA_NAME,
                   SYSTEM_OBJECT_NAME,
                   OBJECT_TYPE,
                   JOB_NAME
              FROM QSYS2.SYSLIMITS
             WHERE MAXIMUM_VALUE IS NOT NULL
               AND MAXIMUM_VALUE > 0
             ORDER BY CASE
                        WHEN MAXIMUM_VALUE > 0
                        THEN DOUBLE(CURRENT_VALUE) / DOUBLE(MAXIMUM_VALUE)
                        ELSE -1
                      END DESC,
                      LAST_CHANGE_TIMESTAMP DESC
             FETCH FIRST \(limits.maximumLimitOccurrences + 1) ROWS ONLY
            """,
            maximumRows: limits.maximumLimitOccurrences,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }

    public var groupPTFInfo: SQLExecutionRequest {
        SQLExecutionRequest(
            sql: """
            SELECT COLLECTED_TIME,
                   PTF_GROUP_NAME,
                   PTF_GROUP_DESCRIPTION,
                   PTF_GROUP_LEVEL,
                   PTF_GROUP_TARGET_RELEASE,
                   PTF_GROUP_STATUS
              FROM QSYS2.GROUP_PTF_INFO
             ORDER BY PTF_GROUP_NAME
             FETCH FIRST \(limits.maximumPTFGroups + 1) ROWS ONLY
            """,
            maximumRows: limits.maximumPTFGroups,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }
}

public struct SystemHealthSQLDecoder: Sendable {
    public let limits: SystemHealthLimits

    public init(limits: SystemHealthLimits = .standard) {
        self.limits = limits
    }

    public func decodeSystemStatus(_ result: SQLResult) throws -> SystemStatusEvidence {
        let surface = "SYSTEM_STATUS_INFO"
        try Self.validateColumns(result, surface: surface, required: [
            "TOTAL_JOBS_IN_SYSTEM", "MAXIMUM_JOBS_IN_SYSTEM", "ACTIVE_JOBS_IN_SYSTEM",
            "SYSTEM_ASP_STORAGE", "SYSTEM_ASP_USED", "CURRENT_TEMPORARY_STORAGE",
            "MAXIMUM_TEMPORARY_STORAGE_USED", "TOTAL_JOB_TABLE_ENTRIES",
            "AVAILABLE_JOB_TABLE_ENTRIES", "IN_USE_JOB_TABLE_ENTRIES",
            "ATTENTION_LIGHT", "RESTRICTED_STATE"
        ])
        guard !result.wasTruncated else { throw SystemHealthError.truncatedSingleton(surface: surface) }
        guard result.rows.count == 1 else {
            throw SystemHealthError.unexpectedRowCount(surface: surface, expected: 1, actual: result.rows.count)
        }
        let row = try HealthSQLRow(result: result, surface: surface, rowIndex: 1)
        return try SystemStatusEvidence(
            totalJobs: row.requiredInt("TOTAL_JOBS_IN_SYSTEM"),
            maximumJobs: row.requiredInt("MAXIMUM_JOBS_IN_SYSTEM"),
            activeJobs: row.requiredInt("ACTIVE_JOBS_IN_SYSTEM"),
            systemASPStorageMB: row.requiredInt64("SYSTEM_ASP_STORAGE"),
            systemASPUsedPercent: row.requiredDecimal("SYSTEM_ASP_USED"),
            currentTemporaryStorageMB: row.requiredInt64("CURRENT_TEMPORARY_STORAGE"),
            maximumTemporaryStorageMB: row.requiredInt64("MAXIMUM_TEMPORARY_STORAGE_USED"),
            totalJobTableEntries: row.requiredInt("TOTAL_JOB_TABLE_ENTRIES"),
            availableJobTableEntries: row.requiredInt("AVAILABLE_JOB_TABLE_ENTRIES"),
            inUseJobTableEntries: row.requiredInt("IN_USE_JOB_TABLE_ENTRIES"),
            attentionLight: try row.requiredYesNo("ATTENTION_LIGHT"),
            restrictedState: try row.requiredYesNo("RESTRICTED_STATE")
        )
    }

    public func decodeSystemActivity(_ result: SQLResult) throws -> SystemCPUActivitySample {
        let surface = "SYSTEM_ACTIVITY_INFO"
        try Self.validateColumns(result, surface: surface, required: [
            "AVERAGE_CPU_RATE", "AVERAGE_CPU_UTILIZATION",
            "MINIMUM_CPU_UTILIZATION", "MAXIMUM_CPU_UTILIZATION"
        ])
        guard !result.wasTruncated else { throw SystemHealthError.truncatedSingleton(surface: surface) }
        guard result.rows.count == 1 else {
            throw SystemHealthError.unexpectedRowCount(surface: surface, expected: 1, actual: result.rows.count)
        }
        let row = try HealthSQLRow(result: result, surface: surface, rowIndex: 1)
        return try SystemCPUActivitySample(
            sampleSeconds: limits.cpuSampleSeconds,
            averageCPUUtilization: row.optionalDecimal("AVERAGE_CPU_UTILIZATION"),
            minimumCPUUtilization: row.optionalDecimal("MINIMUM_CPU_UTILIZATION"),
            maximumCPUUtilization: row.optionalDecimal("MAXIMUM_CPU_UTILIZATION"),
            averageCPURate: row.optionalDecimal("AVERAGE_CPU_RATE")
        )
    }

    public func decodeASPs(_ result: SQLResult) throws -> [ASPHealthRecord] {
        let surface = "ASP_INFO"
        try Self.validateColumns(result, surface: surface, required: [
            "ASP_NUMBER", "ASP_STATE", "ASP_TYPE", "RDB_NAME", "NUMBER_OF_DISK_UNITS",
            "DISK_UNITS_PRESENT", "ENCRYPTED_ASP", "TOTAL_CAPACITY",
            "TOTAL_CAPACITY_AVAILABLE", "STORAGE_THRESHOLD_PERCENTAGE"
        ])
        guard result.rows.count <= limits.maximumASPs else {
            throw SystemHealthError.tooManyRows(surface: surface, maximum: limits.maximumASPs)
        }
        var seen = Set<Int>()
        return try result.rows.enumerated().map { offset, _ in
            let row = try HealthSQLRow(result: result, surface: surface, rowIndex: offset + 1)
            let aspNumber = try row.requiredInt("ASP_NUMBER")
            guard seen.insert(aspNumber).inserted else {
                throw SystemHealthError.invalidValue(surface: surface, index: offset + 1, column: "ASP_NUMBER")
            }
            let totalRaw = try row.optionalInt64("TOTAL_CAPACITY")
            let availableRaw = try row.optionalInt64("TOTAL_CAPACITY_AVAILABLE")
            let exceeded = totalRaw == -2 || availableRaw == -2
            let total = totalRaw == -2 ? nil : totalRaw
            let available = availableRaw == -2 ? nil : availableRaw
            return try ASPHealthRecord(
                aspNumber: aspNumber,
                state: row.requiredText("ASP_STATE", maximum: 10),
                type: row.optionalText("ASP_TYPE", maximum: 9),
                relationalDatabaseName: row.optionalText("RDB_NAME", maximum: 18),
                numberOfDiskUnits: row.requiredInt("NUMBER_OF_DISK_UNITS"),
                diskUnitsPresent: row.requiredText("DISK_UNITS_PRESENT", maximum: 4),
                isEncrypted: try row.optionalYesNo("ENCRYPTED_ASP"),
                totalCapacityMB: total,
                availableCapacityMB: available,
                capacityValueExceededField: exceeded,
                storageThresholdPercent: row.requiredInt("STORAGE_THRESHOLD_PERCENTAGE")
            )
        }
    }

    public func decodeSystemLimits(_ result: SQLResult) throws -> [SystemLimitOccurrence] {
        let surface = "SYSLIMITS"
        try Self.validateColumns(result, surface: surface, required: [
            "LAST_CHANGE_TIMESTAMP", "LIMIT_CATEGORY", "LIMIT_TYPE", "SIZING_NAME",
            "CURRENT_VALUE", "MAXIMUM_VALUE", "LIMIT_ID", "SYSTEM_SCHEMA_NAME",
            "SYSTEM_OBJECT_NAME", "OBJECT_TYPE", "JOB_NAME"
        ])
        guard result.rows.count <= limits.maximumLimitOccurrences else {
            throw SystemHealthError.tooManyRows(surface: surface, maximum: limits.maximumLimitOccurrences)
        }
        return try result.rows.enumerated().map { offset, _ in
            let row = try HealthSQLRow(result: result, surface: surface, rowIndex: offset + 1)
            return try SystemLimitOccurrence(
                rowIndex: offset + 1,
                lastChangedAt: row.requiredDate("LAST_CHANGE_TIMESTAMP"),
                category: row.requiredText("LIMIT_CATEGORY", maximum: 15),
                type: row.requiredText("LIMIT_TYPE", maximum: 7),
                sizingName: row.requiredText("SIZING_NAME", maximum: 128),
                currentValue: row.requiredDecimal("CURRENT_VALUE"),
                maximumValue: row.requiredDecimal("MAXIMUM_VALUE"),
                limitID: row.requiredInt("LIMIT_ID"),
                systemSchemaName: row.optionalText("SYSTEM_SCHEMA_NAME", maximum: 10),
                systemObjectName: row.optionalText("SYSTEM_OBJECT_NAME", maximum: 10),
                objectType: row.optionalText("OBJECT_TYPE", maximum: 24),
                jobName: row.optionalText("JOB_NAME", maximum: 28)
            )
        }
    }

    public func decodePTFGroups(_ result: SQLResult) throws -> [PTFGroupRecord] {
        let surface = "GROUP_PTF_INFO"
        try Self.validateColumns(result, surface: surface, required: [
            "COLLECTED_TIME", "PTF_GROUP_NAME", "PTF_GROUP_DESCRIPTION",
            "PTF_GROUP_LEVEL", "PTF_GROUP_TARGET_RELEASE", "PTF_GROUP_STATUS"
        ])
        guard result.rows.count <= limits.maximumPTFGroups else {
            throw SystemHealthError.tooManyRows(surface: surface, maximum: limits.maximumPTFGroups)
        }
        var seen = Set<String>()
        return try result.rows.enumerated().map { offset, _ in
            let row = try HealthSQLRow(result: result, surface: surface, rowIndex: offset + 1)
            let name = try row.requiredText("PTF_GROUP_NAME", maximum: 60)
            guard seen.insert(name.uppercased()).inserted else {
                throw SystemHealthError.invalidValue(surface: surface, index: offset + 1, column: "PTF_GROUP_NAME")
            }
            let status = try row.requiredText("PTF_GROUP_STATUS", maximum: 20)
            return try PTFGroupRecord(
                collectedAt: row.requiredDate("COLLECTED_TIME"),
                name: name,
                description: row.optionalText("PTF_GROUP_DESCRIPTION", maximum: 100),
                level: try row.optionalInt("PTF_GROUP_LEVEL"),
                targetRelease: row.optionalText("PTF_GROUP_TARGET_RELEASE", maximum: 6),
                state: PTFGroupState(rawValue: status)
            )
        }
    }

    private static func validateColumns(
        _ result: SQLResult,
        surface: String,
        required: [String]
    ) throws {
        var seen = Set<String>()
        for column in result.columns {
            let key = column.name.uppercased()
            guard seen.insert(key).inserted else {
                throw SystemHealthError.duplicateColumn(surface: surface, column: key)
            }
        }
        for column in required where !seen.contains(column) {
            throw SystemHealthError.missingColumn(surface: surface, column: column)
        }
    }
}

public struct SystemHealthArtifactBuilder: Sendable {
    public init() {}

    public func build(snapshot: SystemHealthSnapshot) -> String {
        var lines = [
            "iTelAS SYSTEM HEALTH EVIDENCE SNAPSHOT",
            "Target: \(snapshot.targetName)",
            "Captured: \(Self.iso(snapshot.capturedAt))",
            "Mode: \(snapshot.isBundledReplay ? "DETERMINISTIC LOCAL REPLAY" : "BOUNDED READ-ONLY COLLECTION")",
            "Health index: \(snapshot.assessment.score)/100 · \(snapshot.assessment.severity.label)",
            "Interpretation: \(snapshot.assessment.method)",
            "Host writes: NONE",
            ""
        ]
        if let status = snapshot.status {
            lines += [
                "SYSTEM VITALS",
                "Jobs: \(status.totalJobs) total · \(status.activeJobs) active · maximum \(status.maximumJobs)",
                "System ASP used: \(Self.decimal(status.systemASPUsedPercent))% of \(status.systemASPStorageMB) MB",
                "Job table: \(status.inUseJobTableEntries) of \(status.totalJobTableEntries) entries",
                "Temporary storage: \(status.currentTemporaryStorageMB) MB · peak since IPL \(status.maximumTemporaryStorageMB) MB",
                "Attention light: \(status.attentionLight ? "YES" : "NO") · restricted state: \(status.restrictedState ? "YES" : "NO")",
                ""
            ]
        }
        if let cpu = snapshot.cpu {
            lines += [
                "CPU SAMPLE",
                "Interval: \(cpu.sampleSeconds) second(s)",
                "Average utilization: \(cpu.averageCPUUtilization.map(Self.decimal) ?? "UNAVAILABLE")%",
                "Minimum / maximum: \(cpu.minimumCPUUtilization.map(Self.decimal) ?? "UNAVAILABLE")% / \(cpu.maximumCPUUtilization.map(Self.decimal) ?? "UNAVAILABLE")%",
                ""
            ]
        }
        lines.append("SYSTEM LIMIT HIGH-WATER OCCURRENCES")
        lines.append("These are recorded high-water occurrences, not a time series or exhaustion forecast.")
        for limit in snapshot.limits {
            lines.append("\(limit.severity.label) · \(limit.limitID) · \(limit.sizingName) · \(Self.decimal(limit.currentValue)) / \(Self.decimal(limit.maximumValue)) · \(Self.ratioPercent(limit.pressure)) · \(limit.identityLabel)")
        }
        lines += ["", "ASP CAPACITY"]
        for asp in snapshot.asps {
            lines.append("ASP \(asp.aspNumber) · \(asp.type ?? "UNKNOWN TYPE") · \(asp.state) · \(asp.usedPercent.map(Self.absolutePercent) ?? "UNAVAILABLE") used · threshold \(asp.storageThresholdPercent)% · disks \(asp.diskUnitsPresent)")
        }
        lines += ["", "PTF GROUP STATUS", "Installed group status does not establish internet currency."]
        for group in snapshot.ptfGroups {
            lines.append("\(group.name) · level \(group.level.map(String.init) ?? "UNAVAILABLE") · target \(group.targetRelease ?? "UNAVAILABLE") · \(group.state.label)")
        }
        lines += ["", "EVIDENCE RECEIPTS"]
        for receipt in snapshot.receipts {
            let outcome = switch receipt.outcome {
            case .collected: "COLLECTED"
            case .unavailable(let reason): "UNAVAILABLE · \(reason)"
            }
            lines.append("\(receipt.source.rawValue) · \(outcome) · \(receipt.rowCount) row(s) · bound \(receipt.boundWasReached ? "REACHED" : "NOT REACHED") · SHA-256 \(receipt.queryFingerprint)")
        }
        lines += [
            "",
            "CERTIFICATE BOUNDARY",
            "CERTIFICATE_INFO is not collected. Its store password and elevated authority requirements belong to a separate reviewed DCM capability."
        ]
        return lines.joined(separator: "\n")
    }

    fileprivate static func decimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    fileprivate static func ratioPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    fileprivate static func absolutePercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
    }
}

public struct SystemHealthAssistContextBuilder: Sendable {
    public init() {}

    public func build(snapshot: SystemHealthSnapshot) -> String {
        var lines = [
            "ITELAS SYSTEM HEALTH ASSIST CONTEXT",
            "Target identity: WITHHELD",
            "Mode: \(snapshot.isBundledReplay ? "DETERMINISTIC LOCAL REPLAY" : "BOUNDED READ-ONLY EVIDENCE")",
            "Health index: \(snapshot.assessment.score)/100 · \(snapshot.assessment.severity.label)",
            "Health-index method: \(snapshot.assessment.method)",
            "Safety: advice only; no host mutation capability is attached.",
            "Privacy: no serial number, partition identifier, credential, business row, or certificate-store password is included.",
            ""
        ]
        if let status = snapshot.status {
            lines += [
                "SYSTEM VITALS",
                "Jobs total/active/maximum: \(status.totalJobs) / \(status.activeJobs) / \(status.maximumJobs)",
                "System ASP used: \(SystemHealthArtifactBuilder.decimal(status.systemASPUsedPercent))%",
                "Job-table entries used/total: \(status.inUseJobTableEntries) / \(status.totalJobTableEntries)",
                "Temporary storage current/peak-since-IPL MB: \(status.currentTemporaryStorageMB) / \(status.maximumTemporaryStorageMB)",
                "Attention light: \(status.attentionLight ? "YES" : "NO")",
                ""
            ]
        }
        if let cpu = snapshot.cpu {
            lines += [
                "CPU SAMPLE",
                "Interval seconds: \(cpu.sampleSeconds)",
                "Average/minimum/maximum utilization: \(cpu.averageCPUUtilization.map(SystemHealthArtifactBuilder.decimal) ?? "UNAVAILABLE") / \(cpu.minimumCPUUtilization.map(SystemHealthArtifactBuilder.decimal) ?? "UNAVAILABLE") / \(cpu.maximumCPUUtilization.map(SystemHealthArtifactBuilder.decimal) ?? "UNAVAILABLE")",
                ""
            ]
        }
        lines += [
            "SYSTEM LIMIT EVIDENCE",
            "Interpret every row as a recorded high-water occurrence, never as a trend, root cause, or time-to-exhaustion."
        ]
        for limit in snapshot.limits.prefix(20) {
            let object = [limit.systemSchemaName, limit.systemObjectName].compactMap { $0 }.joined(separator: "/")
            lines.append("\(limit.severity.label) · ID \(limit.limitID) · \(limit.sizingName) · \(SystemHealthArtifactBuilder.ratioPercent(limit.pressure)) · object \(object.isEmpty ? "WITHHELD OR SYSTEM" : object)")
        }
        lines += ["", "PTF GROUP STATUS", "This is installed status only and does not establish internet currency."]
        for group in snapshot.ptfGroups.prefix(20) {
            lines.append("\(group.name) · level \(group.level.map(String.init) ?? "UNAVAILABLE") · target \(group.targetRelease ?? "UNAVAILABLE") · \(group.state.label)")
        }
        lines += ["", "EVIDENCE GAPS"]
        if snapshot.gaps.isEmpty {
            lines.append("NONE REPORTED")
        } else {
            for receipt in snapshot.gaps {
                lines.append("\(receipt.source.rawValue) · UNAVAILABLE · review the local receipt")
            }
        }
        lines += [
            "",
            "CERTIFICATE_INFO is intentionally unavailable. Do not request a certificate-store password or elevated authority in this review."
        ]
        return lines.joined(separator: "\n")
    }
}

private struct HealthSQLRow {
    let surface: String
    let rowIndex: Int
    let row: [SQLValue]
    let index: [String: Int]

    init(result: SQLResult, surface: String, rowIndex: Int) throws {
        var index: [String: Int] = [:]
        for (offset, column) in result.columns.enumerated() {
            let key = column.name.uppercased()
            guard index[key] == nil else {
                throw SystemHealthError.duplicateColumn(surface: surface, column: key)
            }
            index[key] = offset
        }
        guard result.rows.indices.contains(rowIndex - 1) else {
            throw SystemHealthError.malformedRow(surface: surface, index: rowIndex)
        }
        let row = result.rows[rowIndex - 1]
        guard row.count == result.columns.count else {
            throw SystemHealthError.malformedRow(surface: surface, index: rowIndex)
        }
        self.surface = surface
        self.rowIndex = rowIndex
        self.row = row
        self.index = index
    }

    func value(_ column: String) throws -> SQLValue {
        let key = column.uppercased()
        guard let offset = index[key] else {
            throw SystemHealthError.missingColumn(surface: surface, column: key)
        }
        return row[offset]
    }

    func requiredText(_ column: String, maximum: Int) throws -> String {
        guard let value = try optionalText(column, maximum: maximum), !value.isEmpty else {
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
        return value
    }

    func optionalText(_ column: String, maximum: Int) throws -> String? {
        switch try value(column) {
        case .null:
            return nil
        case .string(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= maximum, Self.isSafeText(text) else {
                throw SystemHealthError.invalidText(surface: surface, index: rowIndex, column: column)
            }
            return text.isEmpty ? nil : text
        default:
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
    }

    func requiredInt(_ column: String) throws -> Int {
        let value = try requiredInt64(column)
        guard let converted = Int(exactly: value) else {
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
        return converted
    }

    func optionalInt(_ column: String) throws -> Int? {
        guard let value = try optionalInt64(column) else { return nil }
        guard let converted = Int(exactly: value) else {
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
        return converted
    }

    func requiredInt64(_ column: String) throws -> Int64 {
        guard let value = try optionalInt64(column) else {
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
        return value
    }

    func optionalInt64(_ column: String) throws -> Int64? {
        switch try value(column) {
        case .null:
            return nil
        case .integer(let value):
            return value
        case .decimal(let raw):
            guard let decimal = Self.decimal(raw), decimal.rounded(scale: 0) == decimal,
                  let value = Int64(exactly: NSDecimalNumber(decimal: decimal)) else {
                throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
            }
            return value
        case .string(let raw):
            guard let value = Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
            }
            return value
        default:
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
    }

    func requiredDecimal(_ column: String) throws -> Decimal {
        guard let value = try optionalDecimal(column) else {
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
        return value
    }

    func optionalDecimal(_ column: String) throws -> Decimal? {
        switch try value(column) {
        case .null:
            return nil
        case .integer(let value):
            return Decimal(value)
        case .decimal(let raw), .string(let raw):
            guard let value = Self.decimal(raw) else {
                throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
            }
            return value
        default:
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
    }

    func requiredDate(_ column: String) throws -> Date {
        switch try value(column) {
        case .date(let value), .timestamp(let value):
            return value
        default:
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
    }

    func requiredYesNo(_ column: String) throws -> Bool {
        guard let value = try optionalYesNo(column) else {
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
        return value
    }

    func optionalYesNo(_ column: String) throws -> Bool? {
        switch try value(column) {
        case .null:
            return nil
        case .boolean(let value):
            return value
        case .string(let raw):
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            case "YES", "Y": return true
            case "NO", "N": return false
            default:
                throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
            }
        default:
            throw SystemHealthError.invalidValue(surface: surface, index: rowIndex, column: column)
        }
    }

    private static func decimal(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64,
              trimmed.unicodeScalars.allSatisfy({ scalar in
                  ("0"..."9").contains(Character(scalar)) || scalar == "." || scalar == "-" || scalar == "+"
              }) else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isSafeText(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
