import Foundation
import XCTest
@testable import iTelASCore

final class SystemHealthTests: XCTestCase {
    private let decoder = SystemHealthSQLDecoder()

    func testPlannerBuildsFiveSingleStatementReadOnlyBoundedRequests() throws {
        let planner = SystemHealthSQLPlanner()
        let requests = [
            planner.systemStatus,
            planner.systemActivity,
            planner.aspInfo,
            planner.systemLimits,
            planner.groupPTFInfo
        ]

        XCTAssertEqual(requests.count, 5)
        for request in requests {
            XCTAssertTrue(request.readOnly)
            XCTAssertTrue((1...100).contains(request.maximumRows))
            XCTAssertTrue(SQLStatementAnalyzer().analyze(request.sql).isSingleReadOnlyStatement)
            XCTAssertNoThrow(try Db2OperationAuthorizer(accessMode: .readOnly).authorizeInteractiveSQL(request))
        }
        XCTAssertEqual(planner.systemStatus.maximumRows, 1)
        XCTAssertTrue(planner.systemStatus.sql.contains("FETCH FIRST 2 ROWS ONLY"))
        XCTAssertTrue(planner.systemActivity.sql.contains("SYSTEM_ACTIVITY_INFO(1)"))
        XCTAssertTrue(planner.aspInfo.sql.contains("FETCH FIRST 65 ROWS ONLY"))
        XCTAssertTrue(planner.systemLimits.sql.contains("FROM QSYS2.SYSLIMITS"))
        XCTAssertTrue(planner.systemLimits.sql.contains("FETCH FIRST 101 ROWS ONLY"))
        XCTAssertTrue(planner.groupPTFInfo.sql.contains("FROM QSYS2.GROUP_PTF_INFO"))
        XCTAssertFalse(requests.contains { $0.sql.contains("CERTIFICATE_INFO") })
    }

    func testSystemStatusDecoderUsesColumnNamesAndPreservesCapacitySemantics() throws {
        let values: [String: SQLValue] = [
            "TOTAL_JOBS_IN_SYSTEM": .integer(18_642),
            "MAXIMUM_JOBS_IN_SYSTEM": .integer(485_000),
            "ACTIVE_JOBS_IN_SYSTEM": .integer(287),
            "SYSTEM_ASP_STORAGE": .integer(12_800_000),
            "SYSTEM_ASP_USED": .decimal("78.40"),
            "CURRENT_TEMPORARY_STORAGE": .integer(42_600),
            "MAXIMUM_TEMPORARY_STORAGE_USED": .integer(61_300),
            "TOTAL_JOB_TABLE_ENTRIES": .integer(163_520),
            "AVAILABLE_JOB_TABLE_ENTRIES": .integer(144_878),
            "IN_USE_JOB_TABLE_ENTRIES": .integer(18_642),
            "ATTENTION_LIGHT": .string("NO"),
            "RESTRICTED_STATE": .string("NO")
        ]
        let result = namedResult(order: statusColumns.reversed(), values: values)
        let status = try decoder.decodeSystemStatus(result)

        XCTAssertEqual(status.totalJobs, 18_642)
        XCTAssertEqual(status.systemASPUsedPercent, decimal("78.40"))
        XCTAssertEqual(status.jobTablePressure, 18_642.0 / 163_520.0, accuracy: 0.000_001)
        XCTAssertEqual(status.temporaryStoragePressureAgainstPeak!, 42_600.0 / 61_300.0, accuracy: 0.000_001)
        XCTAssertFalse(status.attentionLight)
        XCTAssertFalse(status.restrictedState)
    }

    func testSingletonDecoderRejectsDuplicateMissingMalformedAndTruncatedEvidence() throws {
        var values = validStatusValues
        let duplicateColumns = statusColumns + ["system_asp_used"]
        let duplicateRows = [statusColumns.map { values[$0]! } + [.decimal("78.4")]]
        XCTAssertThrowsError(try decoder.decodeSystemStatus(sqlResult(columns: duplicateColumns, rows: duplicateRows))) { error in
            XCTAssertEqual(error as? SystemHealthError, .duplicateColumn(surface: "SYSTEM_STATUS_INFO", column: "SYSTEM_ASP_USED"))
        }

        let missing = statusColumns.filter { $0 != "ATTENTION_LIGHT" }
        XCTAssertThrowsError(try decoder.decodeSystemStatus(namedResult(order: missing, values: values))) { error in
            XCTAssertEqual(error as? SystemHealthError, .missingColumn(surface: "SYSTEM_STATUS_INFO", column: "ATTENTION_LIGHT"))
        }

        values["TOTAL_JOBS_IN_SYSTEM"] = .string("not-a-number")
        XCTAssertThrowsError(try decoder.decodeSystemStatus(namedResult(order: statusColumns, values: values))) { error in
            XCTAssertEqual(error as? SystemHealthError, .invalidValue(surface: "SYSTEM_STATUS_INFO", index: 1, column: "TOTAL_JOBS_IN_SYSTEM"))
        }

        XCTAssertThrowsError(try decoder.decodeSystemStatus(namedResult(order: statusColumns, values: validStatusValues, truncated: true))) { error in
            XCTAssertEqual(error as? SystemHealthError, .truncatedSingleton(surface: "SYSTEM_STATUS_INFO"))
        }
    }

    func testActivityDecoderKeepsOneSecondSampleDistinctFromSystemStatus() throws {
        let order = [
            "MAXIMUM_CPU_UTILIZATION", "AVERAGE_CPU_RATE",
            "MINIMUM_CPU_UTILIZATION", "AVERAGE_CPU_UTILIZATION"
        ]
        let result = namedResult(order: order, values: [
            "AVERAGE_CPU_RATE": .decimal("108.30"),
            "AVERAGE_CPU_UTILIZATION": .decimal("42.80"),
            "MINIMUM_CPU_UTILIZATION": .decimal("31.60"),
            "MAXIMUM_CPU_UTILIZATION": .decimal("71.20")
        ])
        let sample = try decoder.decodeSystemActivity(result)

        XCTAssertEqual(sample.sampleSeconds, 1)
        XCTAssertEqual(sample.averageCPUUtilization, decimal("42.80"))
        XCTAssertEqual(sample.averageCPURate, decimal("108.30"))
    }

    func testASPDecoderComputesPressureAndRejectsImpossibleOrDuplicateRows() throws {
        let values: [String: SQLValue] = [
            "ASP_NUMBER": .integer(1),
            "ASP_STATE": .string("NONE"),
            "ASP_TYPE": .string("SYSTEM"),
            "RDB_NAME": .string("DEV01"),
            "NUMBER_OF_DISK_UNITS": .integer(16),
            "DISK_UNITS_PRESENT": .string("ALL"),
            "ENCRYPTED_ASP": .string("YES"),
            "TOTAL_CAPACITY": .integer(12_800_000),
            "TOTAL_CAPACITY_AVAILABLE": .integer(2_764_800),
            "STORAGE_THRESHOLD_PERCENTAGE": .integer(85)
        ]
        let record = try XCTUnwrap(decoder.decodeASPs(namedResult(order: aspColumns.reversed(), values: values)).first)
        XCTAssertEqual(record.usedPercent!, 78.4, accuracy: 0.000_1)
        XCTAssertEqual(record.severity, .warning)
        XCTAssertEqual(record.isEncrypted, true)

        var impossible = values
        impossible["TOTAL_CAPACITY_AVAILABLE"] = .integer(12_900_000)
        XCTAssertThrowsError(try decoder.decodeASPs(namedResult(order: aspColumns, values: impossible))) { error in
            XCTAssertEqual(error as? SystemHealthError, .invalidCapacity(surface: "ASP_INFO", index: 1))
        }

        let row = aspColumns.map { values[$0]! }
        XCTAssertThrowsError(try decoder.decodeASPs(sqlResult(columns: aspColumns, rows: [row, row]))) { error in
            XCTAssertEqual(error as? SystemHealthError, .invalidValue(surface: "ASP_INFO", index: 2, column: "ASP_NUMBER"))
        }
    }

    func testSystemLimitDecoderPreservesExactDecimalsAndSnapshotRanksPressure() throws {
        let captured = Date(timeIntervalSince1970: 1_000)
        let high = limitValues(
            date: captured,
            id: 15_106,
            name: "Maximum indexes",
            current: "13980",
            maximum: "15000",
            schema: "ARLIB",
            object: "ORDERHIST",
            job: nil
        )
        let medium = limitValues(
            date: captured.addingTimeInterval(-1),
            id: 16_200,
            name: "Maximum record locks",
            current: "421000000",
            maximum: "500000000",
            schema: nil,
            object: nil,
            job: "184221/QBATCH/RECON"
        )
        let result = namedRowsResult(order: limitColumns.reversed(), rows: [medium, high])
        let decoded = try decoder.decodeSystemLimits(result)
        let snapshot = SystemHealthSnapshot(
            targetName: "DEV",
            capturedAt: captured,
            status: nil,
            cpu: nil,
            asps: [],
            limits: decoded,
            ptfGroups: [],
            receipts: []
        )

        XCTAssertEqual(decoded[0].currentValue, decimal("421000000"))
        XCTAssertEqual(snapshot.limits.first?.limitID, 15_106)
        XCTAssertEqual(snapshot.limits.first?.severity, .critical)
        XCTAssertEqual(snapshot.limits.last?.severity, .warning)
        XCTAssertEqual(snapshot.limits.last?.identityLabel, "184221/QBATCH/RECON")
    }

    func testPTFDecoderPreservesDocumentedStatusesAndRejectsAmbiguousSchema() throws {
        let captured = Date(timeIntervalSince1970: 1_000)
        let installed = ptfValues(captured, "SF99950", 12, "INSTALLED")
        let pending = ptfValues(captured, "SF99959", 6, "APPLY AT NEXT IPL")
        let records = try decoder.decodePTFGroups(namedRowsResult(
            order: ptfColumns.reversed(),
            rows: [pending, installed]
        ))

        XCTAssertEqual(records.map(\.state), [.applyAtNextIPL, .installed])
        XCTAssertEqual(records[0].state.penalty, 2)
        XCTAssertEqual(records[1].state.penalty, 0)

        XCTAssertThrowsError(try decoder.decodePTFGroups(sqlResult(columns: ["COLLECTED_TIME"], rows: []))) { error in
            XCTAssertEqual(error as? SystemHealthError, .missingColumn(surface: "GROUP_PTF_INFO", column: "PTF_GROUP_NAME"))
        }

        XCTAssertThrowsError(try decoder.decodePTFGroups(namedRowsResult(
            order: ptfColumns,
            rows: [installed, installed]
        ))) { error in
            XCTAssertEqual(error as? SystemHealthError, .invalidValue(surface: "GROUP_PTF_INFO", index: 2, column: "PTF_GROUP_NAME"))
        }
    }

    func testAssessmentIsTransparentAndDoesNotClaimTrendOrOutageTime() throws {
        let snapshot = try assessmentFixture()
        let assessment = snapshot.assessment

        XCTAssertEqual(assessment.score, 72)
        XCTAssertEqual(assessment.severity, .watch)
        XCTAssertEqual(assessment.limitsAtRisk, 3)
        XCTAssertEqual(assessment.criticalLimitCount, 2)
        XCTAssertTrue(assessment.method.contains("not an IBM score"))
        XCTAssertTrue(assessment.method.contains("outage forecast"))
    }

    func testAssistContextWithholdsTargetJobAndPrivilegedGapDetails() throws {
        var snapshot = try assessmentFixture()
        let gap = SystemHealthEvidenceReceipt(
            source: .certificateInfo,
            rowCount: 0,
            boundWasReached: false,
            elapsedMilliseconds: nil,
            queryFingerprint: "fingerprint",
            outcome: .unavailable("private-host certificate store password denied")
        )
        snapshot = SystemHealthSnapshot(
            targetName: "private-host",
            capturedAt: snapshot.capturedAt,
            status: snapshot.status,
            cpu: snapshot.cpu,
            asps: snapshot.asps,
            limits: snapshot.limits,
            ptfGroups: snapshot.ptfGroups,
            receipts: [gap]
        )
        let context = SystemHealthAssistContextBuilder().build(snapshot: snapshot)

        XCTAssertTrue(context.contains("Target identity: WITHHELD"))
        XCTAssertFalse(context.contains("private-host"))
        XCTAssertFalse(context.contains("184221/QBATCH/RECON"))
        XCTAssertFalse(context.contains("password denied"))
        XCTAssertTrue(context.contains("high-water occurrence"))
        XCTAssertTrue(context.contains("does not establish internet currency"))
        XCTAssertEqual(AIContextKind.systemHealth.label, "System health")
        XCTAssertFalse(AIContextKind.systemHealth.requiresSelection)
        XCTAssertNoThrow(try AIContextFragment(
            kind: .systemHealth,
            documentName: "system-health.txt",
            language: "IBM i system-health evidence",
            sourceText: context
        ))
    }

    func testStatusAndCollectionBoundsFailClosed() throws {
        XCTAssertThrowsError(try SystemStatusEvidence(
            totalJobs: 2,
            maximumJobs: 10,
            activeJobs: 1,
            systemASPStorageMB: 100,
            systemASPUsedPercent: 50,
            currentTemporaryStorageMB: 11,
            maximumTemporaryStorageMB: 10,
            totalJobTableEntries: 10,
            availableJobTableEntries: 7,
            inUseJobTableEntries: 4,
            attentionLight: false,
            restrictedState: false
        ))

        let bounded = SystemHealthSQLDecoder(limits: .init(maximumASPs: 1))
        let values: [String: SQLValue] = [
            "ASP_NUMBER": .integer(1), "ASP_STATE": .string("NONE"), "ASP_TYPE": .string("SYSTEM"),
            "RDB_NAME": .null, "NUMBER_OF_DISK_UNITS": .integer(1), "DISK_UNITS_PRESENT": .string("ALL"),
            "ENCRYPTED_ASP": .string("NO"), "TOTAL_CAPACITY": .integer(100),
            "TOTAL_CAPACITY_AVAILABLE": .integer(50), "STORAGE_THRESHOLD_PERCENTAGE": .integer(90)
        ]
        let row = aspColumns.map { values[$0]! }
        XCTAssertThrowsError(try bounded.decodeASPs(sqlResult(columns: aspColumns, rows: [row, row]))) { error in
            XCTAssertEqual(error as? SystemHealthError, .tooManyRows(surface: "ASP_INFO", maximum: 1))
        }
    }

    private func assessmentFixture() throws -> SystemHealthSnapshot {
        let date = Date(timeIntervalSince1970: 1_000)
        let status = try SystemStatusEvidence(
            totalJobs: 18_642,
            maximumJobs: 485_000,
            activeJobs: 287,
            systemASPStorageMB: 12_800_000,
            systemASPUsedPercent: decimal("78.4"),
            currentTemporaryStorageMB: 42_600,
            maximumTemporaryStorageMB: 61_300,
            totalJobTableEntries: 163_520,
            availableJobTableEntries: 144_878,
            inUseJobTableEntries: 18_642,
            attentionLight: false,
            restrictedState: false
        )
        let cpu = try SystemCPUActivitySample(
            sampleSeconds: 1,
            averageCPUUtilization: decimal("42.8"),
            minimumCPUUtilization: decimal("31.6"),
            maximumCPUUtilization: decimal("71.2"),
            averageCPURate: decimal("108.3")
        )
        let asp = try ASPHealthRecord(
            aspNumber: 1,
            state: "NONE",
            type: "SYSTEM",
            relationalDatabaseName: nil,
            numberOfDiskUnits: 16,
            diskUnitsPresent: "ALL",
            isEncrypted: true,
            totalCapacityMB: 12_800_000,
            availableCapacityMB: 2_764_800,
            storageThresholdPercent: 85
        )
        let ratios: [(Int, String, String)] = [
            (15_106, "93.2", "100"),
            (15_000, "92.7", "100"),
            (16_200, "84.2", "100"),
            (15_002, "62.9", "100"),
            (15_104, "47.0", "100")
        ]
        let limits = try ratios.enumerated().map { offset, row in
            try SystemLimitOccurrence(
                rowIndex: offset + 1,
                lastChangedAt: date.addingTimeInterval(Double(-offset)),
                category: row.0 == 16_200 ? "WORK MANAGEMENT" : "DATABASE",
                type: row.0 == 16_200 ? "JOB" : "OBJECT",
                sizingName: "Limit \(row.0)",
                currentValue: decimal(row.1),
                maximumValue: decimal(row.2),
                limitID: row.0,
                systemSchemaName: row.0 == 16_200 ? nil : "ARLIB",
                systemObjectName: row.0 == 16_200 ? nil : "OBJECT",
                objectType: row.0 == 16_200 ? nil : "*FILE",
                jobName: row.0 == 16_200 ? "184221/QBATCH/RECON" : nil
            )
        }
        let ptfs = [
            try PTFGroupRecord(collectedAt: date, name: "SF99950", description: "Db2", level: 12, targetRelease: "V7R5M0", state: .installed),
            try PTFGroupRecord(collectedAt: date, name: "SF99959", description: "Cumulative", level: 6, targetRelease: "V7R5M0", state: .applyAtNextIPL),
            try PTFGroupRecord(collectedAt: date, name: "SF99958", description: "HIPER", level: 5, targetRelease: "V7R5M0", state: .notInstalled)
        ]
        return SystemHealthSnapshot(
            targetName: "PRIVATE",
            capturedAt: date,
            status: status,
            cpu: cpu,
            asps: [asp],
            limits: limits,
            ptfGroups: ptfs,
            receipts: []
        )
    }

    private var statusColumns: [String] {
        [
            "TOTAL_JOBS_IN_SYSTEM", "MAXIMUM_JOBS_IN_SYSTEM", "ACTIVE_JOBS_IN_SYSTEM",
            "SYSTEM_ASP_STORAGE", "SYSTEM_ASP_USED", "CURRENT_TEMPORARY_STORAGE",
            "MAXIMUM_TEMPORARY_STORAGE_USED", "TOTAL_JOB_TABLE_ENTRIES",
            "AVAILABLE_JOB_TABLE_ENTRIES", "IN_USE_JOB_TABLE_ENTRIES",
            "ATTENTION_LIGHT", "RESTRICTED_STATE"
        ]
    }

    private var validStatusValues: [String: SQLValue] {
        [
            "TOTAL_JOBS_IN_SYSTEM": .integer(18_642), "MAXIMUM_JOBS_IN_SYSTEM": .integer(485_000),
            "ACTIVE_JOBS_IN_SYSTEM": .integer(287), "SYSTEM_ASP_STORAGE": .integer(12_800_000),
            "SYSTEM_ASP_USED": .decimal("78.4"), "CURRENT_TEMPORARY_STORAGE": .integer(42_600),
            "MAXIMUM_TEMPORARY_STORAGE_USED": .integer(61_300), "TOTAL_JOB_TABLE_ENTRIES": .integer(163_520),
            "AVAILABLE_JOB_TABLE_ENTRIES": .integer(144_878), "IN_USE_JOB_TABLE_ENTRIES": .integer(18_642),
            "ATTENTION_LIGHT": .string("NO"), "RESTRICTED_STATE": .string("NO")
        ]
    }

    private var aspColumns: [String] {
        [
            "ASP_NUMBER", "ASP_STATE", "ASP_TYPE", "RDB_NAME", "NUMBER_OF_DISK_UNITS",
            "DISK_UNITS_PRESENT", "ENCRYPTED_ASP", "TOTAL_CAPACITY",
            "TOTAL_CAPACITY_AVAILABLE", "STORAGE_THRESHOLD_PERCENTAGE"
        ]
    }

    private var limitColumns: [String] {
        [
            "LAST_CHANGE_TIMESTAMP", "LIMIT_CATEGORY", "LIMIT_TYPE", "SIZING_NAME",
            "CURRENT_VALUE", "MAXIMUM_VALUE", "LIMIT_ID", "SYSTEM_SCHEMA_NAME",
            "SYSTEM_OBJECT_NAME", "OBJECT_TYPE", "JOB_NAME"
        ]
    }

    private var ptfColumns: [String] {
        [
            "COLLECTED_TIME", "PTF_GROUP_NAME", "PTF_GROUP_DESCRIPTION",
            "PTF_GROUP_LEVEL", "PTF_GROUP_TARGET_RELEASE", "PTF_GROUP_STATUS"
        ]
    }

    private func limitValues(
        date: Date,
        id: Int,
        name: String,
        current: String,
        maximum: String,
        schema: String?,
        object: String?,
        job: String?
    ) -> [String: SQLValue] {
        [
            "LAST_CHANGE_TIMESTAMP": .timestamp(date),
            "LIMIT_CATEGORY": .string(id == 16_200 ? "WORK MANAGEMENT" : "DATABASE"),
            "LIMIT_TYPE": .string(job == nil ? "OBJECT" : "JOB"),
            "SIZING_NAME": .string(name),
            "CURRENT_VALUE": .decimal(current),
            "MAXIMUM_VALUE": .decimal(maximum),
            "LIMIT_ID": .integer(Int64(id)),
            "SYSTEM_SCHEMA_NAME": schema.map(SQLValue.string) ?? .null,
            "SYSTEM_OBJECT_NAME": object.map(SQLValue.string) ?? .null,
            "OBJECT_TYPE": object == nil ? .null : .string("*FILE"),
            "JOB_NAME": job.map(SQLValue.string) ?? .null
        ]
    }

    private func ptfValues(_ date: Date, _ name: String, _ level: Int, _ status: String) -> [String: SQLValue] {
        [
            "COLLECTED_TIME": .timestamp(date),
            "PTF_GROUP_NAME": .string(name),
            "PTF_GROUP_DESCRIPTION": .string("Group \(name)"),
            "PTF_GROUP_LEVEL": .integer(Int64(level)),
            "PTF_GROUP_TARGET_RELEASE": .string("V7R5M0"),
            "PTF_GROUP_STATUS": .string(status)
        ]
    }

    private func namedResult(
        order: some Sequence<String>,
        values: [String: SQLValue],
        truncated: Bool = false
    ) -> SQLResult {
        let columns = Array(order)
        return sqlResult(columns: columns, rows: [columns.map { values[$0]! }], truncated: truncated)
    }

    private func namedRowsResult(
        order: some Sequence<String>,
        rows: [[String: SQLValue]],
        truncated: Bool = false
    ) -> SQLResult {
        let columns = Array(order)
        return sqlResult(columns: columns, rows: rows.map { row in columns.map { row[$0]! } }, truncated: truncated)
    }

    private func sqlResult(
        columns: [String],
        rows: [[SQLValue]],
        truncated: Bool = false
    ) -> SQLResult {
        SQLResult(
            columns: columns.map { SQLColumn(name: $0, databaseType: "VARCHAR", isNullable: true) },
            rows: rows,
            targetName: "DEV",
            startedAt: Date(timeIntervalSince1970: 1_000),
            elapsedMilliseconds: 12,
            wasTruncated: truncated
        )
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
