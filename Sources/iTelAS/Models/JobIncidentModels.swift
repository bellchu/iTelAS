import Foundation
import iTelASCore

enum JobIncidentPhase: Equatable {
    case localReplay
    case collecting
    case ready
    case failed

    var label: String {
        switch self {
        case .localReplay: "LOCAL REPLAY"
        case .collecting: "COLLECTING"
        case .ready: "LIVE SNAPSHOT"
        case .failed: "COLLECTION GAP"
        }
    }

    var isCollecting: Bool { self == .collecting }
}

enum JobIncidentSamples {
    static let selectedJobID = qualifiedJob("847216/DEVUSER/ITELASBLD")

    static func makeSnapshot() -> JobIncidentSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_785_159_420)
        let devQueue = queue("DEVLIB", "DEVJOBQ")
        let opsQueue = queue("OPSLIB", "OPSJOBQ")
        let batchQueue = queue("QGPL", "QBATCH")
        let printQueue = queue("QGPL", "QPRINT")
        let development = systemName("DEVLIB")
        let qbatch = systemName("QBATCH")
        let qinter = systemName("QINTER")

        let waitingJob = JobInventoryRecord(
            qualifiedName: selectedJobID,
            informationAvailable: true,
            status: .active,
            type: "BCI",
            enhancedType: "BATCH_IMMEDIATE",
            subsystem: qbatch,
            jobQueue: devQueue,
            jobQueueStatus: "RELEASED",
            jobQueuePriority: 2,
            jobQueueTime: capturedAt.addingTimeInterval(-2_760),
            jobLogPending: false,
            outputQueue: printQueue
        )
        let holderJob = JobInventoryRecord(
            qualifiedName: qualifiedJob("847118/OPSUSR/ORDWRITER"),
            informationAvailable: true,
            status: .active,
            type: "PJ",
            enhancedType: "PRESTART_BATCH",
            subsystem: qbatch,
            jobQueue: opsQueue,
            jobQueueStatus: "RELEASED",
            jobQueuePriority: 1,
            jobQueueTime: capturedAt.addingTimeInterval(-4_920),
            outputQueue: printQueue
        )
        let sqlJob = JobInventoryRecord(
            qualifiedName: qualifiedJob("847301/DEVUSER/QZDASOINIT"),
            informationAvailable: true,
            status: .active,
            type: "PJ",
            enhancedType: "PRESTART_BATCH",
            subsystem: qinter,
            jobLogPending: false,
            outputQueue: printQueue
        )
        let nightlyJob = JobInventoryRecord(
            qualifiedName: qualifiedJob("847402/BATCHUSR/ORDNIGHT"),
            informationAvailable: true,
            status: .jobQueue,
            type: "BCH",
            enhancedType: "BATCH",
            subsystem: qbatch,
            jobQueue: batchQueue,
            jobQueueStatus: "HELD",
            jobQueuePriority: 3,
            jobQueueTime: capturedAt.addingTimeInterval(-9_420),
            jobLogPending: true,
            outputQueue: printQueue
        )
        let queuedJobs = (1...19).map { index in
            JobInventoryRecord(
                qualifiedName: qualifiedJob(String(format: "84%04d/BATCHUSR/QJOB%04d", 7402 + index, index)),
                informationAvailable: true,
                status: .jobQueue,
                type: "BCH",
                enhancedType: "BATCH",
                subsystem: qbatch,
                jobQueue: index.isMultiple(of: 3) ? devQueue : batchQueue,
                jobQueueStatus: index.isMultiple(of: 4) ? "SCHEDULED" : "RELEASED",
                jobQueuePriority: 2 + (index % 4),
                jobQueueTime: capturedAt.addingTimeInterval(TimeInterval(-8_400 + index * 210)),
                jobLogPending: index.isMultiple(of: 6),
                outputQueue: printQueue
            )
        }

        let orderHeader = try! IBMObjectLockIdentity(
            library: development,
            object: systemName("ORDHDR"),
            objectType: "*FILE"
        )
        let customerMaster = try! IBMObjectLockIdentity(
            library: development,
            object: systemName("CUSTMAST"),
            objectType: "*FILE"
        )
        let locks = [
            JobLockRecord(
                rowIndex: 1,
                object: orderHeader,
                job: selectedJobID,
                status: .waiting,
                state: "*EXCLRD",
                scope: "JOB",
                threadID: 1,
                programLibrary: development,
                program: systemName("ITELASBLD"),
                module: systemName("ORDUPD"),
                procedure: "reserveOrder",
                statementID: "184"
            ),
            JobLockRecord(
                rowIndex: 2,
                object: orderHeader,
                job: holderJob.qualifiedName,
                status: .held,
                state: "*EXCLRD",
                scope: "JOB",
                threadID: 7,
                programLibrary: systemName("OPSLIB"),
                program: systemName("ORDWRITER"),
                module: systemName("ORDCOMMIT"),
                procedure: "persistOrder",
                statementID: "622"
            ),
            JobLockRecord(
                rowIndex: 3,
                object: customerMaster,
                job: sqlJob.qualifiedName,
                status: .held,
                state: "*SHRRD",
                scope: "THREAD",
                threadID: 4,
                programLibrary: systemName("QSYS"),
                program: systemName("QSQSRVR")
            )
        ]

        let messages = [
            jobLog(245, "CPIAD09", "INFORMATIONAL", 0, capturedAt.addingTimeInterval(-31), "Commitment control started for activation group ITELAS.", nil),
            jobLog(246, "CPI432E", "DIAGNOSTIC", 10, capturedAt.addingTimeInterval(-24), "Procedure reserveOrder opened DEVLIB/ORDHDR for update.", "The job is running under commitment control. Review outstanding work before proposing any action."),
            jobLog(247, "CPF5026", "DIAGNOSTIC", 30, capturedAt.addingTimeInterval(-18), "Record or object ORDHDR in DEVLIB is already in use.", "Another job may hold an incompatible lock. Compare the exact object identity with OBJECT_LOCK_INFO evidence."),
            jobLog(248, "CPF9898", "ESCAPE", 40, capturedAt.addingTimeInterval(-12), "Order reservation did not complete within the application wait interval.", "Review the earlier diagnostic messages and the current lock snapshot."),
            jobLog(249, "CPA9897", "INQUIRY", 30, capturedAt.addingTimeInterval(-7), "Reply C to cancel or R to retry the order reservation.", "A human operator must review the transaction state before replying. iTelAS does not reply automatically.")
        ]
        let operatorMessages = [
            OperatorMessageRecord(
                rowIndex: 1,
                messageID: "CPA9897",
                type: "INQUIRY",
                severity: 30,
                timestamp: capturedAt.addingTimeInterval(-7),
                text: "Reply C to cancel or R to retry the order reservation.",
                secondLevelText: "Review commitment state and the exact lock evidence before replying.",
                fromUser: "DEVUSER",
                fromJob: selectedJobID,
                fromProgram: "ITELASBLD"
            )
        ]

        let planner = JobIncidentSQLPlanner()
        let receipts = [
            receipt(.jobInfo, rowCount: 23, request: planner.jobInventory),
            receipt(.objectLockInfo, rowCount: locks.count, request: planner.objectLocks),
            receipt(.joblogInfo, rowCount: messages.count, request: planner.jobLog(for: selectedJobID)),
            receipt(.messageQueueInfo, rowCount: operatorMessages.count, request: planner.operatorInquiries)
        ]

        return JobIncidentSnapshot(
            targetName: "LOCAL INCIDENT REPLAY",
            capturedAt: capturedAt,
            jobs: [waitingJob, holderJob, sqlJob, nightlyJob] + queuedJobs,
            locks: locks,
            jobLogMessages: messages,
            operatorMessages: operatorMessages,
            receipts: receipts
        )
    }

    private static func jobLog(
        _ ordinal: Int,
        _ messageID: String,
        _ type: String,
        _ severity: Int,
        _ timestamp: Date,
        _ text: String,
        _ secondLevelText: String?
    ) -> JobLogMessage {
        JobLogMessage(
            ordinalPosition: ordinal,
            messageID: messageID,
            type: type,
            severity: severity,
            timestamp: timestamp,
            text: text,
            secondLevelText: secondLevelText,
            fromProgram: "ITELASBLD",
            fromModule: "ORDUPD",
            fromProcedure: "reserveOrder",
            qualifiedJobName: selectedJobID
        )
    }

    private static func receipt(
        _ source: JobIncidentEvidenceSource,
        rowCount: Int,
        request: SQLExecutionRequest
    ) -> JobIncidentEvidenceReceipt {
        JobIncidentEvidenceReceipt(
            source: source,
            rowCount: rowCount,
            wasTruncated: false,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }

    private static func qualifiedJob(_ value: String) -> IBMQualifiedJobName {
        try! IBMQualifiedJobName(value)
    }

    private static func systemName(_ value: String) -> IBMSystemObjectName {
        try! IBMSystemObjectName(value)
    }

    private static func queue(_ library: String, _ name: String) -> IBMQueueIdentity {
        IBMQueueIdentity(library: systemName(library), name: systemName(name))
    }
}

struct JobIncidentAssistContextBuilder {
    func build(snapshot: JobIncidentSnapshot, analysis: JobIncidentAnalysis) -> String {
        var lines = [
            "iTelAS reviewed job incident evidence",
            "Target: \(snapshot.targetName)",
            "Captured: \(Self.timestamp(snapshot.capturedAt))",
            "Selected job: \(analysis.selectedJob.qualifiedName.rawValue)",
            "Status: \(analysis.selectedJob.status.rawValue)",
            "Subsystem: \(analysis.selectedJob.subsystem?.value ?? "UNAVAILABLE")",
            "Job queue: \(analysis.selectedJob.jobQueue?.id ?? "UNAVAILABLE")",
            "",
            "WAITING LOCK EVIDENCE"
        ]

        if analysis.waitingLocks.isEmpty {
            lines.append("No WAITING or REQUESTED lock row was visible for the selected job.")
        } else {
            lines.append(contentsOf: analysis.waitingLocks.map { lock in
                "- \(lock.status.rawValue) \(lock.object.displayName); state \(lock.state); scope \(lock.scope); thread \(lock.threadID.map(String.init) ?? "UNAVAILABLE")"
            })
        }

        lines.append(contentsOf: ["", "EXACT-OBJECT HOLDER CANDIDATES"])
        if analysis.holderCandidates.isEmpty {
            lines.append("No candidate holder was visible.")
        } else {
            lines.append(contentsOf: analysis.holderCandidates.map { correlation in
                "- CANDIDATE \(correlation.holder.job.rawValue) holds \(correlation.holder.object.displayName) in \(correlation.holder.state); exact-object correlation only."
            })
        }
        lines.append("Assessment confidence: \(analysis.confidence.label)")
        lines.append("Relationship basis: \(analysis.relationshipBasis)")

        lines.append(contentsOf: ["", "SELECTED MESSAGE"])
        if let message = analysis.selectedMessage {
            lines.append("- \(message.messageID ?? "NO-ID") · \(message.type) · severity \(message.severity) · \(Self.timestamp(message.timestamp))")
            lines.append("  Text: \(message.text ?? "UNAVAILABLE")")
            lines.append("  Recovery: \(message.secondLevelText ?? "UNAVAILABLE")")
        } else {
            lines.append("No accessible job-log message was available.")
        }
        lines.append("Selection basis: \(analysis.messageSelectionBasis)")

        lines.append(contentsOf: ["", "RELATED OPERATOR MESSAGES"])
        if analysis.relatedOperatorMessages.isEmpty {
            lines.append("No exact from-job match was visible in the QSYSOPR inquiry snapshot.")
        } else {
            lines.append(contentsOf: analysis.relatedOperatorMessages.map { message in
                "- \(message.messageID ?? "NO-ID") · severity \(message.severity) · \(Self.timestamp(message.timestamp)) · \(message.text ?? "UNAVAILABLE")"
            })
        }

        lines.append(contentsOf: ["", "EVIDENCE RECEIPTS"])
        lines.append(contentsOf: snapshot.receipts.map { receipt in
            let outcome = switch receipt.outcome {
            case .collected: "COLLECTED"
            case .unavailable(let reason): "UNAVAILABLE: \(reason)"
            }
            return "- \(receipt.source.rawValue): \(outcome); rows \(receipt.rowCount); truncated \(receipt.wasTruncated ? "YES" : "NO"); query SHA-256 \(receipt.queryFingerprint)"
        })

        lines.append(contentsOf: [
            "",
            "REVIEW BOUNDARY",
            "This is a bounded read-only snapshot. Lock rows describe state at collection time and do not carry timestamps.",
            "Exact object identity identifies candidate holders; it does not prove scheduler causality or lock compatibility.",
            "Treat message timestamps as exact only where supplied. Do not describe any reply, hold, release, end, or other host action as performed.",
            "Recommend evidence-first read-only checks and clearly label every inference."
        ])
        return lines.joined(separator: "\n")
    }

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "UNAVAILABLE" }
        return date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
    }
}
