import Foundation
import iTelASCore

enum SystemHealthPhase: Equatable {
    case localReplay
    case collecting
    case ready
    case failed

    var label: String {
        switch self {
        case .localReplay: "LOCAL REPLAY"
        case .collecting: "COLLECTING"
        case .ready: "LIVE EVIDENCE"
        case .failed: "EVIDENCE GAP"
        }
    }

    var isCollecting: Bool { self == .collecting }
}

enum SystemHealthSamples {
    static func makeSnapshot() -> SystemHealthSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_785_164_812)
        let planner = SystemHealthSQLPlanner()
        let status = try! SystemStatusEvidence(
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
        let cpu = try! SystemCPUActivitySample(
            sampleSeconds: 1,
            averageCPUUtilization: decimal("42.8"),
            minimumCPUUtilization: decimal("31.6"),
            maximumCPUUtilization: decimal("71.2"),
            averageCPURate: decimal("108.3")
        )
        let asps = [
            try! ASPHealthRecord(
                aspNumber: 1,
                state: "NONE",
                type: "SYSTEM",
                relationalDatabaseName: "DEV01",
                numberOfDiskUnits: 16,
                diskUnitsPresent: "ALL",
                isEncrypted: true,
                totalCapacityMB: 12_800_000,
                availableCapacityMB: 2_764_800,
                storageThresholdPercent: 85
            )
        ]
        let limitRows = [
            limit(
                1, capturedAt.addingTimeInterval(-42), 15_106,
                "Maximum number of indexes over a partition",
                "13980", "15000", "ARLIB", "ORDERHIST", "*FILE", nil
            ),
            limit(
                2, capturedAt.addingTimeInterval(-109), 15_000,
                "Maximum number of all rows in a file member",
                "3981434678", "4294967288", "LOGDATA", "AUDITLOG", "*FILE", nil
            ),
            limit(
                3, capturedAt.addingTimeInterval(-181), 16_200,
                "Maximum number of record locks held by a transaction",
                "421000000", "500000000", nil, nil, nil, "184221/QBATCH/RECON"
            ),
            limit(
                4, capturedAt.addingTimeInterval(-266), 15_002,
                "Maximum number of deleted rows in a partition",
                "2701534420", "4294967288", "ARLIB", "TXNARCH", "*FILE", nil
            ),
            limit(
                5, capturedAt.addingTimeInterval(-411), 15_104,
                "Maximum number of variable-length segments in a file member",
                "30810", "65533", "APPDATA", "DOCSTORE", "*FILE", nil
            )
        ]
        let ptfs = [
            ptf(capturedAt, "SF99950", "Db2 for IBM i", 12, "V7R5M0", .installed),
            ptf(capturedAt, "SF99959", "Cumulative PTF package", 6, "V7R5M0", .applyAtNextIPL),
            ptf(capturedAt, "SF99958", "HIPER group", 5, "V7R5M0", .notInstalled)
        ]
        let receipts = [
            receipt(.systemStatus, rows: 1, request: planner.systemStatus),
            receipt(.systemActivity, rows: 1, request: planner.systemActivity),
            receipt(.aspInfo, rows: asps.count, request: planner.aspInfo),
            receipt(.systemLimits, rows: limitRows.count, request: planner.systemLimits),
            receipt(.groupPTFInfo, rows: ptfs.count, request: planner.groupPTFInfo),
            SystemHealthEvidenceReceipt(
                source: .certificateInfo,
                rowCount: 0,
                boundWasReached: false,
                elapsedMilliseconds: nil,
                queryFingerprint: AIContentFingerprint.sha256("CERTIFICATE_INFO INTENTIONALLY NOT EXECUTED"),
                outcome: .unavailable("Separate privileged DCM capability; no store password or elevated authority was requested.")
            )
        ]
        return SystemHealthSnapshot(
            targetName: "LOCAL SYSTEM HEALTH REPLAY",
            capturedAt: capturedAt,
            status: status,
            cpu: cpu,
            asps: asps,
            limits: limitRows,
            ptfGroups: ptfs,
            receipts: receipts,
            isBundledReplay: true
        )
    }

    private static func limit(
        _ row: Int,
        _ date: Date,
        _ id: Int,
        _ name: String,
        _ current: String,
        _ maximum: String,
        _ schema: String?,
        _ object: String?,
        _ objectType: String?,
        _ job: String?
    ) -> SystemLimitOccurrence {
        try! SystemLimitOccurrence(
            rowIndex: row,
            lastChangedAt: date,
            category: id == 16_200 ? "WORK MANAGEMENT" : "DATABASE",
            type: job == nil ? "OBJECT" : "JOB",
            sizingName: name,
            currentValue: decimal(current),
            maximumValue: decimal(maximum),
            limitID: id,
            systemSchemaName: schema,
            systemObjectName: object,
            objectType: objectType,
            jobName: job
        )
    }

    private static func ptf(
        _ date: Date,
        _ name: String,
        _ description: String,
        _ level: Int,
        _ target: String,
        _ state: PTFGroupState
    ) -> PTFGroupRecord {
        try! PTFGroupRecord(
            collectedAt: date,
            name: name,
            description: description,
            level: level,
            targetRelease: target,
            state: state
        )
    }

    private static func receipt(
        _ source: SystemHealthEvidenceSource,
        rows: Int,
        request: SQLExecutionRequest
    ) -> SystemHealthEvidenceReceipt {
        SystemHealthEvidenceReceipt(
            source: source,
            rowCount: rows,
            boundWasReached: false,
            elapsedMilliseconds: source == .systemActivity ? 1_012 : 18,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }

    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
