import Foundation
import iTelASCore

enum ObjectImpactPhase: Equatable {
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

enum ObjectImpactSamples {
    static func makeSnapshot() -> ObjectImpactSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_785_164_812)
        let target = identity("ARLIB", "ORDERSRV", .serviceProgram)
        let planner = ObjectImpactSQLPlanner(target: target)
        let focus = ObjectImpactNode(target)
        let edges = [
            edge(.incoming, node("ARLIB", "ORDERAPI", "*PGM"), focus, .bound, .boundServiceProgramInfo, "*DEFER"),
            edge(.incoming, node("ARLIB", "ORDERBCH", "*PGM"), focus, .bound, .boundServiceProgramInfo, "*IMMED"),
            edge(.outgoing, focus, node("ARLIB", "COMMONSRV", "*SRVPGM"), .bound, .boundServiceProgramInfo, "*DEFER"),
            edge(.outgoing, focus, node("QSYS", "QC2LE", "*SRVPGM"), .bound, .boundServiceProgramInfo, "*DEFER"),
            edge(.outgoing, focus, node("ARLIB", "ORDERMOD", "*MODULE"), .bound, .boundModuleInfo, "RPGLE · ARLIB/QRPGLESRC(ORDERMOD)"),
            edge(.outgoing, focus, node("ARLIB", "ORDERDB", "*MODULE"), .bound, .boundModuleInfo, "SQLRPGLE · ARLIB/QRPGLESRC(ORDERDB)"),
            edge(.outgoing, focus, node("ARLIB", "ORDERVAL", "*MODULE"), .bound, .boundModuleInfo, "RPGLE · ARLIB/QRPGLESRC(ORDERVAL)"),
            edge(.incoming, node("ARLIB", "APPBNDDIR", "*BNDDIR"), focus, .candidate, .bindingDirectoryInfo, "Build-time candidate · *DEFER"),
            edge(.incoming, node("ARAPI", "GET_ORDER", "SQL PROCEDURE"), focus, .catalog, .sysroutines, "RPGLE · READS")
        ]
        let metadata = ObjectImpactMetadata(
            identity: target,
            owner: "ARAPP",
            attribute: "RPGLE",
            text: "Order domain service procedures",
            sizeBytes: 418_816,
            createdAt: capturedAt.addingTimeInterval(-8_640_000),
            changedAt: capturedAt.addingTimeInterval(-86_400),
            lastUsedAt: capturedAt.addingTimeInterval(-3_600),
            sourceLibrary: "ARLIB",
            sourceFile: "QRPGLESRC",
            sourceMember: "ORDERSRV",
            sourceChangedAt: capturedAt.addingTimeInterval(-90_000),
            sqlObjectType: nil
        )
        let receipts = [
            receipt(.objectStatistics, rows: 1, request: planner.objectStatistics),
            receipt(.boundServiceProgramInfo, rows: 4, request: planner.boundServicePrograms),
            receipt(.boundModuleInfo, rows: 3, request: planner.boundModules),
            receipt(.bindingDirectoryInfo, rows: 1, request: planner.bindingDirectories),
            receipt(.sysroutines, rows: 1, request: planner.sqlRoutines),
            receipt(.sysviewdep, rows: 0, request: planner.viewDependencies),
            ObjectImpactEvidenceReceipt(
                source: .programReferences,
                rowCount: 0,
                boundWasReached: false,
                elapsedMilliseconds: nil,
                queryFingerprint: AIContentFingerprint.sha256("PROGRAM REFERENCES INTENTIONALLY NOT COLLECTED"),
                outcome: .unavailable("DSPPGMREF output requires creating a host outfile; this read-only milestone performs no host writes.")
            )
        ]
        return ObjectImpactSnapshot(
            targetName: "LOCAL IMPACT REPLAY",
            target: target,
            capturedAt: capturedAt,
            metadata: metadata,
            edges: edges,
            receipts: receipts,
            isBundledReplay: true
        )
    }

    private static func identity(_ library: String, _ name: String, _ type: IBMObjectType) -> IBMObjectIdentity {
        try! IBMObjectIdentity(library: library, name: name, type: type)
    }

    private static func node(_ library: String, _ name: String, _ type: String) -> ObjectImpactNode {
        try! ObjectImpactNode(library: library, name: name, type: type)
    }

    private static func edge(
        _ direction: ObjectImpactEdgeDirection,
        _ from: ObjectImpactNode,
        _ to: ObjectImpactNode,
        _ evidenceClass: ObjectImpactEvidenceClass,
        _ source: ObjectImpactEvidenceSource,
        _ detail: String
    ) -> ObjectImpactEdge {
        ObjectImpactEdge(
            direction: direction,
            from: from,
            to: to,
            evidenceClass: evidenceClass,
            source: source,
            detail: detail
        )
    }

    private static func receipt(
        _ source: ObjectImpactEvidenceSource,
        rows: Int,
        request: SQLExecutionRequest
    ) -> ObjectImpactEvidenceReceipt {
        ObjectImpactEvidenceReceipt(
            source: source,
            rowCount: rows,
            boundWasReached: false,
            elapsedMilliseconds: source == .boundModuleInfo ? 41 : 18,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }
}
