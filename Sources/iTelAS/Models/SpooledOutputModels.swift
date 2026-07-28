import Foundation
import iTelASCore

enum SpoolInventoryPhase: Equatable {
    case localReplay
    case collecting
    case ready
    case failed

    var label: String {
        switch self {
        case .localReplay: "LOCAL REPLAY"
        case .collecting: "COLLECTING"
        case .ready: "LIVE INVENTORY"
        case .failed: "COLLECTION GAP"
        }
    }

    var isCollecting: Bool { self == .collecting }
}

enum SpoolPreviewPhase: Equatable {
    case localReplay
    case notLoaded
    case loading
    case ready
    case failed

    var label: String {
        switch self {
        case .localReplay: "LOCAL PREVIEW"
        case .notLoaded: "CONTENT NOT LOADED"
        case .loading: "LOADING CONTENT"
        case .ready: "LIVE TEXT PREVIEW"
        case .failed: "PREVIEW GAP"
        }
    }

    var isLoading: Bool { self == .loading }
}

enum SpooledOutputSamples {
    static let selectedIdentity = identity(
        job: "084219/BATCH/ARPOST",
        file: "QPJOBLOG",
        number: 184
    )

    static func makeSnapshot() -> SpooledOutputSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_785_159_787)
        let qprint = queue("QGPL", "QPRINT")
        let invoice = queue("QGPL", "INVOICE")
        let reports = queue("OPS", "REPORTS")
        let devout = queue("DEV", "DEVOUT")
        let queues = [
            OutputQueueRecord(
                identity: qprint,
                numberOfFiles: 41,
                numberOfWriters: 2,
                printerDeviceName: systemName("PRT01"),
                orderOfFiles: "*FIFO",
                displayAnyFile: "*OWNER",
                operatorControlled: true,
                authorityToCheck: "*OWNER",
                status: .released,
                writerJob: qualifiedJob("084155/QSPLJOB/PRT01"),
                writerJobStatus: "STR",
                writerType: "PRINTER",
                textDescription: "Primary operations output"
            ),
            OutputQueueRecord(
                identity: invoice,
                numberOfFiles: 28,
                numberOfWriters: 0,
                orderOfFiles: "*FIFO",
                displayAnyFile: "*OWNER",
                operatorControlled: true,
                authorityToCheck: "*OWNER",
                status: .held,
                textDescription: "Invoice forms"
            ),
            OutputQueueRecord(
                identity: reports,
                numberOfFiles: 19,
                numberOfWriters: 1,
                orderOfFiles: "*JOBNBR",
                displayAnyFile: "*NO",
                operatorControlled: false,
                authorityToCheck: "*DTAAUT",
                status: .released,
                writerJob: qualifiedJob("084166/QSPLJOB/RPTWTR"),
                writerJobStatus: "STR",
                writerType: "REMOTE",
                textDescription: "Operations reports"
            ),
            OutputQueueRecord(
                identity: devout,
                numberOfFiles: 8,
                numberOfWriters: 0,
                orderOfFiles: "*FIFO",
                displayAnyFile: "*YES",
                operatorControlled: false,
                authorityToCheck: "*DTAAUT",
                status: .released,
                textDescription: "Development output"
            )
        ]

        let primary = [
            file(selectedIdentity, .ready, qprint, capturedAt, userData: "ARPOST", size: 129_024, pages: 6, priority: 5),
            file(identity(job: "084201/OPR/DSPAUD", file: "QSYSPRT", number: 17), .messageWaiting, qprint, capturedAt.addingTimeInterval(-360), userData: "AUDIT", size: 53_120, pages: 2, priority: 2),
            file(identity(job: "084166/BATCH/INVPRT", file: "INVOICE", number: 811), .held, invoice, capturedAt.addingTimeInterval(-1_500), userData: "JULY", size: 2_600_000, pages: 118, priority: 3),
            file(identity(job: "084151/OPS/TRACE", file: "QPDSPJOB", number: 3), .ready, reports, capturedAt.addingTimeInterval(-2_820), userData: "TRACE", size: 41_980, pages: 4, priority: 5),
            file(identity(job: "084099/BUY/POBATCH", file: "POPRINT", number: 92), .saved, qprint, capturedAt.addingTimeInterval(-5_460), userData: "PO", size: 782_100, pages: 32, priority: 4),
            file(identity(job: "084031/DEV/CRTBND", file: "QPRTJOB", number: 44), .deferred, devout, capturedAt.addingTimeInterval(-6_900), userData: "BUILD", size: 93_230, pages: 7, priority: 6)
        ]
        let generated = (0..<90).map { index in
            let outputQueue = [qprint, invoice, reports, devout][index % 4]
            let status: SpooledFileStatus = index.isMultiple(of: 17) ? .held : .ready
            return file(
                identity(
                    job: String(format: "%06d/BATCH/RPT%04d", 84_300 + index, index),
                    file: index.isMultiple(of: 3) ? "RPTDAILY" : "QSYSPRT",
                    number: 200 + index
                ),
                status,
                outputQueue,
                capturedAt.addingTimeInterval(TimeInterval(-7_200 - index * 270)),
                userData: String(format: "RUN%04d", index),
                size: Int64(22_000 + index * 8_500),
                pages: 1 + index % 48,
                priority: 2 + index % 7
            )
        }
        let planner = SpooledOutputSQLPlanner()
        let receipts = [
            receipt(.spooledFileInfo, rowCount: primary.count + generated.count, request: planner.inventory),
            receipt(.outputQueueInfo, rowCount: queues.count, request: planner.outputQueues),
            SpooledOutputEvidenceReceipt(
                source: .spooledFileData,
                rowCount: 0,
                boundWasReached: false,
                queryFingerprint: AIContentFingerprint.sha256("SPOOLED_FILE_DATA NOT EXECUTED IN LOCAL REPLAY"),
                outcome: .unavailable("The visible preview is deterministic local data; no host content read occurred.")
            )
        ]
        return SpooledOutputSnapshot(
            targetName: "LOCAL OUTPUT REPLAY",
            capturedAt: capturedAt,
            files: primary + generated,
            queues: queues,
            receipts: receipts
        )
    }

    static func makePreview() -> SpooledTextPreview {
        let lines = [
            "5722SS1 V7R5M0  230413                       JOB LOG                                 DEV01",
            "Job name . . . . . . . . . . :   ARPOST        User  . . . . . . :   BATCH",
            "Job number . . . . . . . . . :   084219        Date  . . . . . . :   07/27/26",
            "--------------------------------------------------------------------------------",
            "CPI1125  Information  00  09:43:08.013421  Job 084219/BATCH/ARPOST started.",
            "CPI1468  Information  00  09:43:08.032805  Commitment control started.",
            "CPF4131  Escape       40  09:43:09.144003  Error loading file ARCUST in ARLIB.",
            "Cause . . . . . :  Member JULY2026 was not found for file ARCUST in library ARLIB.",
            "Recovery  . . . :  Add the member or correct the processing date and retry.",
            "RNQ1216  Inquiry      99  09:43:09.144820  Reply C, D, F, or R.",
            "C                       Reply entered by program default.",
            "CPF9999  Escape       40  09:43:09.145901  Function check. CPF4131 unmonitored.",
            "CPC2401  Completion   00  09:43:09.151208  Job ended abnormally.",
            "",
            "END OF JOB LOG — 13 RECORDS SHOWN IN LOCAL REPLAY"
        ]
        return preview(
            identity: selectedIdentity,
            lines: lines,
            capturedAt: Date(timeIntervalSince1970: 1_785_159_787)
        )
    }

    static func makeBaseline() -> SpooledTextPreview {
        let lines = [
            "5722SS1 V7R5M0  230413                       JOB LOG                                 DEV01",
            "Job name . . . . . . . . . . :   ARPOST        User  . . . . . . :   BATCH",
            "Job number . . . . . . . . . :   083912        Date  . . . . . . :   07/26/26",
            "--------------------------------------------------------------------------------",
            "CPI1125  Information  00  18:02:01.002410  Job 083912/BATCH/ARPOST started.",
            "CPI1468  Information  00  18:02:01.018900  Commitment control started.",
            "CPC2401  Completion   00  18:02:04.332182  Job completed normally.",
            "",
            "END OF JOB LOG — 7 RECORDS SHOWN IN LOCAL REPLAY"
        ]
        return preview(
            identity: identity(job: "083912/BATCH/ARPOST", file: "QPJOBLOG", number: 179),
            lines: lines,
            capturedAt: Date(timeIntervalSince1970: 1_785_103_321)
        )
    }

    private static func preview(
        identity: SpooledFileIdentity,
        lines: [String],
        capturedAt: Date
    ) -> SpooledTextPreview {
        SpooledTextPreview(
            identity: identity,
            targetName: "LOCAL OUTPUT REPLAY",
            capturedAt: capturedAt,
            records: lines.enumerated().map {
                SpooledTextRecord(ordinalPosition: $0.offset + 1, text: $0.element)
            },
            isComplete: true
        )
    }

    private static func file(
        _ identity: SpooledFileIdentity,
        _ status: SpooledFileStatus,
        _ outputQueue: IBMQueueIdentity,
        _ timestamp: Date,
        userData: String,
        size: Int64,
        pages: Int,
        priority: Int
    ) -> SpooledFileRecord {
        SpooledFileRecord(
            identity: identity,
            status: status,
            outputPriority: priority,
            creationTimestamp: timestamp,
            userData: userData,
            sizeBytes: size,
            totalPages: pages,
            copies: 1,
            availability: .immediate,
            formType: "*STD",
            outputQueue: outputQueue,
            aspNumber: 1
        )
    }

    private static func receipt(
        _ source: SpooledOutputEvidenceSource,
        rowCount: Int,
        request: SQLExecutionRequest
    ) -> SpooledOutputEvidenceReceipt {
        SpooledOutputEvidenceReceipt(
            source: source,
            rowCount: rowCount,
            boundWasReached: false,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }

    private static func identity(job: String, file: String, number: Int) -> SpooledFileIdentity {
        try! SpooledFileIdentity(
            job: qualifiedJob(job),
            file: systemName(file),
            number: number,
            system: systemName("DEV01")
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

struct SpoolOutputAssistContextBuilder {
    func build(
        snapshot: SpooledOutputSnapshot,
        file: SpooledFileRecord,
        preview: SpooledTextPreview?,
        comparison: SpooledTextComparison?
    ) -> String {
        let queue = snapshot.queue(for: file)
        var lines = [
            "iTelAS reviewed spooled-output evidence",
            "Target: \(snapshot.targetName)",
            "Inventory captured: \(Self.timestamp(snapshot.capturedAt))",
            "Exact job: \(file.identity.job.rawValue)",
            "Spooled file: \(file.identity.file.value)",
            "Spooled file number: \(file.identity.number)",
            "System: \(file.identity.system?.value ?? "UNAVAILABLE")",
            "Status: \(file.status.rawValue)",
            "Output queue: \(file.outputQueue?.id ?? "UNAVAILABLE")",
            "Created: \(Self.timestamp(file.creationTimestamp))",
            "User data: \(file.userData ?? "UNAVAILABLE")",
            "Form type: \(file.formType ?? "UNAVAILABLE")",
            "Schedule: \(file.availability?.rawValue ?? "UNAVAILABLE")",
            "Priority: \(file.outputPriority.map(String.init) ?? "UNAVAILABLE")",
            "Pages or records: \(file.totalPages.map(String.init) ?? "UNAVAILABLE")",
            "Size bytes: \(file.sizeBytes.map(String.init) ?? "UNAVAILABLE")",
            "",
            "OUTPUT QUEUE EVIDENCE"
        ]
        if let queue {
            lines.append("- \(queue.identity.id): \(queue.status.rawValue); files \(queue.numberOfFiles); writers \(queue.numberOfWriters); order \(queue.orderOfFiles)")
            lines.append("- First writer: \(queue.writerJob?.rawValue ?? "UNAVAILABLE"); state \(queue.writerJobStatus ?? "UNAVAILABLE"); type \(queue.writerType ?? "UNAVAILABLE")")
            lines.append("- Display-any-file \(queue.displayAnyFile); operator-controlled \(queue.operatorControlled ? "YES" : "NO"); authority check \(queue.authorityToCheck)")
        } else {
            lines.append("No exact output-queue row was visible for the selected file.")
        }

        lines.append(contentsOf: ["", "TEXT-RECORD PREVIEW"])
        if let preview {
            lines.append("Preview captured: \(Self.timestamp(preview.capturedAt))")
            lines.append("Preview complete within bound: \(preview.isComplete ? "YES" : "NO")")
            lines.append("Preview SHA-256: \(preview.contentFingerprint)")
            let included = preview.records.prefix(60)
            lines.append(contentsOf: included.map {
                String(format: "%05d | %@", $0.ordinalPosition, $0.text)
            })
            if preview.records.count > included.count {
                lines.append("[\(preview.records.count - included.count) additional preview records omitted from Assist context]")
            }
        } else {
            lines.append("No spooled-file content was loaded or selected for sharing.")
        }

        lines.append(contentsOf: ["", "LOCAL COMPARISON"])
        if let comparison {
            lines.append("Identical: \(comparison.isIdentical ? "YES" : "NO")")
            lines.append("Changed ordinals: \(comparison.changedOrdinalCount); added tail records: \(comparison.addedRecordCount); removed tail records: \(comparison.removedRecordCount)")
            lines.append("First difference: \(comparison.firstDifferenceOrdinal.map(String.init) ?? "NONE")")
            lines.append("Basis: \(comparison.comparisonBasis)")
        } else {
            lines.append("No exact-identity local baseline comparison is available.")
        }

        lines.append(contentsOf: ["", "EVIDENCE RECEIPTS"])
        lines.append(contentsOf: snapshot.receipts.map { receipt in
            let outcome = switch receipt.outcome {
            case .collected: "COLLECTED"
            case .unavailable(let reason): "UNAVAILABLE: \(reason)"
            }
            return "- \(receipt.source.rawValue): \(outcome); rows \(receipt.rowCount); bound reached \(receipt.boundWasReached ? "YES" : "NO"); query SHA-256 \(receipt.queryFingerprint)"
        })

        lines.append(contentsOf: [
            "",
            "REVIEW BOUNDARY",
            "SPOOLED_FILE_DATA is an explicit SYSTOOLS content read and can be audited by IBM i. Do not imply that inventory collection opened file content.",
            "The preview is ordered text records. It does not prove page layout, overlays, graphics, fonts, AFP resources, IPDS fidelity, or PDF equivalence.",
            "Do not describe any hold, release, move, host spool-copy, writer, print, send, or delete action as performed.",
            "Separate exact evidence from inference and recommend only the smallest safe read-only checks."
        ])
        return lines.joined(separator: "\n")
    }

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "UNAVAILABLE" }
        return date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
    }
}
