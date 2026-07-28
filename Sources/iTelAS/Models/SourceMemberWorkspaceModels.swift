import Foundation
import iTelASCore

enum SourceMemberWorkspacePhase: Equatable {
    case localReplay
    case offline
    case loadingLibraries
    case loadingFiles
    case loadingMembers
    case catalogReady
    case opening
    case ready
    case comparing
    case revisionMatch
    case revisionConflict
    case preparingWrite
    case reviewReady
    case writing
    case written
    case failed

    var label: String {
        switch self {
        case .localReplay: "LOCAL REPLAY"
        case .offline: "MEMBER PROVIDER OFFLINE"
        case .loadingLibraries: "READING LIBRARIES"
        case .loadingFiles: "READING SOURCE FILES"
        case .loadingMembers: "READING MEMBERS"
        case .catalogReady: "CATALOG READY"
        case .opening: "OPENING MEMBER"
        case .ready: "MEMBER SNAPSHOT OPEN"
        case .comparing: "CHECKING REVISION"
        case .revisionMatch: "REVISION MATCH"
        case .revisionConflict: "WRITE BLOCKED · CONFLICT"
        case .preparingWrite: "BUILDING WRITE PLAN"
        case .reviewReady: "REVIEW REQUIRED"
        case .writing: "VERIFYING AND WRITING"
        case .written: "WRITE VERIFIED"
        case .failed: "MEMBER OPERATION BLOCKED"
        }
    }

    var isBusy: Bool {
        switch self {
        case .loadingLibraries, .loadingFiles, .loadingMembers, .opening, .comparing, .preparingWrite, .writing:
            true
        default:
            false
        }
    }
}

enum SourceMemberRevisionState: Equatable {
    case unverified
    case match
    case conflict

    var label: String {
        switch self {
        case .unverified: "REVISION UNVERIFIED"
        case .match: "EXACT REVISION MATCH"
        case .conflict: "REMOTE REVISION CHANGED"
        }
    }
}

enum SourceMemberWorkspaceSamples {
    static let developmentLibrary = try! IBMSystemObjectName("DEVLIB")
    static let generalLibrary = try! IBMSystemObjectName("QGPL")
    static let selectedSourceFile = try! IBMSystemObjectName("QRPGLESRC")

    static let libraries = [developmentLibrary, generalLibrary]

    static let sourceFiles: [SourceMemberFileSummary] = [
        SourceMemberFileSummary(
            library: developmentLibrary,
            sourceFile: selectedSourceFile,
            recordLength: 124,
            ccsid: 37,
            memberCount: 42,
            access: fullAccess
        ),
        SourceMemberFileSummary(
            library: developmentLibrary,
            sourceFile: try! IBMSystemObjectName("QCLSRC"),
            recordLength: 112,
            ccsid: 37,
            memberCount: 18,
            access: fullAccess
        ),
        SourceMemberFileSummary(
            library: developmentLibrary,
            sourceFile: try! IBMSystemObjectName("QDDSSRC"),
            recordLength: 112,
            ccsid: 37,
            memberCount: 26,
            access: fullAccess
        )
    ]

    static let members: [SourceMemberSummary] = [
        summary("CUSTSRV", type: "RPGLE", text: "Customer service procedure", rows: 16),
        summary("ORDERSRV", type: "RPGLE", text: "Order service procedure", rows: 238),
        summary("INVOICE", type: "SQLRPGLE", text: "Invoice transaction service", rows: 314),
        summary("CUSCOPY", type: "RPGLE", text: "Customer copy fields", rows: 67)
    ]

    static let snapshot: SourceMemberSnapshot = {
        let identity = SourceMemberIdentity(
            library: developmentLibrary,
            sourceFile: selectedSourceFile,
            member: try! IBMSystemObjectName("CUSTSRV")
        )
        let sourceLines = [
            "**free",
            "ctl-opt option(*srcstmt : *nodebugio);",
            "dcl-pr FindCustomer ind;",
            "  customerNumber packed(9:0) const;",
            "end-pr;",
            "",
            "dcl-s customerNumber packed(9:0) inz(100120);",
            "dcl-s customerFound ind inz(*off);",
            "",
            "customerFound = FindCustomer(customerNumber);",
            "if customerFound;",
            "  dsply ('Customer found');",
            "else;",
            "  dsply ('Customer is missing');",
            "endif;",
            "*inlr = *on;"
        ]
        let records = sourceLines.enumerated().map { index, text in
            try! SourceMemberRecord(
                sequence: SourceMemberSequence(hundredths: (index + 1) * 100),
                sourceDate: SourceMemberDateCode("260701"),
                text: text
            )
        }
        let metadata = try! SourceMemberMetadata(
            identity: identity,
            sourceType: "RPGLE",
            memberText: "Customer service procedure",
            recordLength: 124,
            sourceTextByteLength: 112,
            ccsid: 37,
            recordCount: records.count,
            fieldLayout: .standardThreeField,
            access: fullAccess,
            journalEvidence: .beforeAndAfter,
            triggerCount: 0,
            fileLevelIdentifier: "F1C9A2",
            lastSourceUpdate: Date(timeIntervalSince1970: 1_785_026_400)
        )
        return try! SourceMemberSnapshot(metadata: metadata, records: records)
    }()

    private static let fullAccess = SourceMemberAccess(
        canRead: true,
        canWrite: true,
        canUpdate: true,
        canDelete: true
    )

    private static func summary(
        _ member: String,
        type: String,
        text: String,
        rows: Int
    ) -> SourceMemberSummary {
        SourceMemberSummary(
            identity: SourceMemberIdentity(
                library: developmentLibrary,
                sourceFile: selectedSourceFile,
                member: try! IBMSystemObjectName(member)
            ),
            sourceType: type,
            text: text,
            lastSourceUpdate: Date(timeIntervalSince1970: 1_785_026_400),
            recordCount: rows
        )
    }
}
