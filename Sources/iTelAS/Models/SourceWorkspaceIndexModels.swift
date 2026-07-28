import Foundation
import iTelASCore

enum SourceWorkspaceIndexPhase: Equatable {
    case localReplay
    case indexing
    case ready
    case failed

    var label: String {
        switch self {
        case .localReplay: "LOCAL REPLAY"
        case .indexing: "INDEXING"
        case .ready: "LOCAL INDEX"
        case .failed: "INDEX GAP"
        }
    }

    var isIndexing: Bool { self == .indexing }
}

enum SourceWorkspaceDriftPhase: Equatable {
    case localReplay
    case watching
    case pending
    case paused
    case failed

    var label: String {
        switch self {
        case .localReplay: "SIGNAL REPLAY"
        case .watching: "WATCH CURRENT"
        case .pending: "DRIFT PENDING"
        case .paused: "WATCH PAUSED"
        case .failed: "WATCH GAP"
        }
    }

    var isPaused: Bool { self == .paused }
}

enum SourceWorkspaceSearchPhase: Equatable {
    case idle
    case searching
    case ready
    case failed

    var label: String {
        switch self {
        case .idle: "SEARCH IDLE"
        case .searching: "SEARCHING"
        case .ready: "SEARCH CURRENT"
        case .failed: "SEARCH GAP"
        }
    }

    var isSearching: Bool { self == .searching }
}

enum SourceWorkspaceRenameApplyPhase: Equatable {
    case idle
    case reviewReady
    case applying
    case applied
    case failed

    var label: String {
        switch self {
        case .idle: "PREVIEW"
        case .reviewReady: "REVIEW READY"
        case .applying: "APPLYING"
        case .applied: "APPLIED"
        case .failed: "INSPECTION REQUIRED"
        }
    }

    var isApplying: Bool { self == .applying }
}

enum SourceWorkspaceHostIncludePhase: Equatable {
    case idle
    case reviewReady
    case reading
    case installed
    case failed

    var label: String {
        switch self {
        case .idle: "HOST GAP"
        case .reviewReady: "REVIEW READY"
        case .reading: "READING EXACT TARGET"
        case .installed: "HOST OVERLAY"
        case .failed: "HOST READ BLOCKED"
        }
    }

    var isReading: Bool { self == .reading }
}

enum SourceWorkspaceIndexSamples {
    static let index: SourceWorkspaceIndex = makeIndex()
    static let refreshBuildReport: SourceWorkspaceIndexBuildReport = makeRefreshBuildReport()
    static let reviewedScope: ReviewedSourceDependencyScope = {
        try! ReviewedSourceDependencyScope(
            index: index,
            selectedPaths: [
                "qrpglesrc/taxservice.rpgle",
                "includes/taxrules.cpy",
                "qddssrc/orderfmt.dspf"
            ],
            reviewedAt: Date(timeIntervalSince1970: 1_785_180_486)
        )
    }()

    static var orderEntrySource: String {
        var lines = Array(repeating: "", count: 58)
        lines[0] = "**free"
        lines[1] = "ctl-opt dftactgrp(*no) option(*srcstmt:*nodebugio);"
        lines[2] = "/copy includes/taxrules"
        lines[3] = "/include ARLIB/QRPGLESRC,CUSCOPY"
        lines[5] = "dcl-pr LoadOrder ind;"
        lines[6] = "  orderID packed(9:0) const;"
        lines[7] = "end-pr;"
        lines[9] = "dcl-s customerName varchar(80);"
        lines[10] = "dcl-s customerID packed(9:0);"
        lines[11] = "dcl-s orderTotal packed(11:2);"
        lines[12] = "dcl-s taxAmount packed(11:2);"
        lines[14] = "taxAmount = CalculateTax(orderTotal);"
        lines[39] = "exec sql"
        lines[40] = "  select CUSTOMER_NAME, CREDIT_LIMIT"
        lines[41] = "    into :customerName, :customerNo"
        lines[42] = "    from CUSTOMER"
        lines[43] = "   where CUSTOMER_ID = :customerID;"
        lines[45] = "if SQLCOD < 0;"
        lines[46] = "  return *off;"
        lines[47] = "endif;"
        lines[49] = "return *on;"
        return lines.joined(separator: "\n")
    }

    static func makeIndex() -> SourceWorkspaceIndex {
        let timestamp = Date(timeIntervalSince1970: 1_785_180_486)
        let files = try! [
            SourceWorkspaceFile(
                relativePath: "qrpglesrc/orderentry.rpgle",
                format: .rpgle,
                text: orderEntrySource,
                modifiedAt: timestamp,
                sourceDate: "260727"
            ),
            SourceWorkspaceFile(
                relativePath: "qrpglesrc/taxservice.rpgle",
                format: .rpgle,
                text: """
                **free
                dcl-proc CalculateTax export;
                  dcl-pi *n packed(9:2);
                    taxable packed(11:2) const;
                  end-pi;
                  return taxable * 0.13;
                end-proc;
                """,
                modifiedAt: timestamp,
                sourceDate: "260726"
            ),
            SourceWorkspaceFile(
                relativePath: "qrpglesrc/ordertotal.rpgle",
                format: .rpgle,
                text: """
                **free
                dcl-proc OrderTotal export;
                  dcl-pi *n packed(11:2);
                    subtotal packed(11:2) const;
                  end-pi;
                  return subtotal + CalculateTax(subtotal);
                end-proc;
                """,
                modifiedAt: timestamp,
                sourceDate: "260727"
            ),
            SourceWorkspaceFile(
                relativePath: "includes/taxrules.cpy",
                format: .rpgle,
                text: """
                dcl-pr CalculateTax packed(9:2);
                  taxable packed(11:2) const;
                end-pr;
                dcl-c ProvincialRate 0.13;
                """,
                modifiedAt: timestamp,
                sourceDate: "260701"
            ),
            SourceWorkspaceFile(
                relativePath: "qddssrc/orderfmt.dspf",
                format: .dds,
                text: """
                     A          R ORDERFMT
                     A            SUBTOTAL      11S 2B  8 20
                     A            TAXAMOUNT      9S 2O  9 20
                     A            TOTAL         11S 2O 10 20
                """,
                modifiedAt: timestamp,
                sourceDate: "260620"
            ),
            SourceWorkspaceFile(
                relativePath: "qcllesrc/reprice.clle",
                format: .clle,
                text: """
                PGM
                  CALL PGM(ORDERENTRY)
                ENDPGM
                """,
                modifiedAt: timestamp,
                sourceDate: "260601"
            ),
            SourceWorkspaceFile(
                relativePath: "sql/order_audit.sql",
                format: .sql,
                text: "SELECT ORDER_ID, TOTAL FROM ORDER_HEADER FETCH FIRST 100 ROWS ONLY;",
                modifiedAt: timestamp
            )
        ]
        return try! SourceWorkspaceIndexBuilder().build(
            rootName: "ORDER PLATFORM · SRC",
            files: files,
            skippedFiles: [
                SourceWorkspaceSkippedFile(relativePath: "legacy/tax.tbl", reason: "Unsupported extension."),
                SourceWorkspaceSkippedFile(relativePath: "vendor/current.cpy", reason: "Symbolic links are not indexed.")
            ],
            createdAt: timestamp
        )
    }

    private static func makeRefreshBuildReport() -> SourceWorkspaceIndexBuildReport {
        let currentFiles = try! index.documents.map { document in
            try SourceWorkspaceFile(
                relativePath: document.relativePath,
                format: document.format,
                text: document.text,
                modifiedAt: document.modifiedAt,
                sourceDate: document.sourceDate,
                origin: document.origin,
                limits: index.limits
            )
        }
        var previousFiles: [SourceWorkspaceFile] = []
        for document in index.documents {
            if document.relativePath == "sql/order_audit.sql" { continue }
            let text = document.relativePath == "qrpglesrc/taxservice.rpgle"
                ? document.text.replacingOccurrences(of: "0.13", with: "0.12")
                : document.text
            let modifiedAt = document.relativePath == "includes/taxrules.cpy"
                ? document.modifiedAt?.addingTimeInterval(-86_400)
                : document.modifiedAt
            previousFiles.append(try! SourceWorkspaceFile(
                relativePath: document.relativePath,
                format: document.format,
                text: text,
                modifiedAt: modifiedAt,
                sourceDate: document.sourceDate,
                origin: document.origin,
                limits: index.limits
            ))
        }
        previousFiles.append(try! SourceWorkspaceFile(
            relativePath: "qrpglesrc/legacytax.rpgle",
            format: .rpgle,
            text: "**free\ndcl-proc LegacyTax;\n  return;\nend-proc;",
            modifiedAt: index.createdAt.addingTimeInterval(-172_800),
            limits: index.limits
        ))
        let builder = SourceWorkspaceIndexBuilder(limits: index.limits)
        let previousIndex = try! builder.build(
            rootName: index.rootName,
            files: previousFiles,
            skippedFiles: index.skippedFiles,
            createdAt: index.createdAt.addingTimeInterval(-60)
        )
        let result = try! builder.buildIncrementally(
            rootName: index.rootName,
            files: currentFiles,
            previousIndex: previousIndex,
            skippedFiles: index.skippedFiles,
            createdAt: index.createdAt
        )
        precondition(result.index.fingerprint == index.fingerprint)
        return result.report
    }
}

enum SourceWorkspaceDriftSamples {
    static let receipt: SourceWorkspaceDriftReceipt = {
        let observations = [
            try! SourceWorkspaceDriftObservation(
                relativePath: "qrpglesrc/orderentry.rpgle",
                kinds: [.modified],
                rawEventCount: 3,
                eventID: 101
            ),
            try! SourceWorkspaceDriftObservation(
                relativePath: "includes/taxrules.cpy",
                kinds: [.renamed, .metadata],
                rawEventCount: 2,
                eventID: 102
            ),
            try! SourceWorkspaceDriftObservation(
                relativePath: "qddssrc/orderfmt.dspf",
                kinds: [.created],
                rawEventCount: 2,
                eventID: 103
            )
        ]
        return SourceWorkspaceDriftReceipt(
            baselineIndexFingerprint: SourceWorkspaceIndexSamples.index.fingerprint,
            observations: observations
        )
    }()
}

enum SourceWorkspaceHostIncludeSamples {
    static func content(
        for review: ReviewedSourceWorkspaceHostInclude
    ) throws -> SourceWorkspaceHostIncludeContent {
        try SourceWorkspaceHostIncludeContent(
            request: review,
            actualTarget: review.target,
            providerName: "BUNDLED REPLAY",
            targetName: "LOCAL SOURCE ATLAS REPLAY",
            text: """
            dcl-ds CustomerTemplate qualified;
              customerNumber packed(9:0);
              customerName varchar(80);
              creditLimit packed(11:2);
              active ind;
            end-ds;

            dcl-c CustomerStatusActive 'A';
            dcl-c CustomerStatusHold 'H';
            """,
            format: .rpgle,
            ccsid: 37,
            remoteRevision: "replay:ARLIB:QRPGLESRC:CUSCOPY:1",
            capturedAt: Date(timeIntervalSince1970: 1_785_180_486)
        )
    }
}
