import Foundation
import XCTest
@testable import iTelASCore

final class ObjectImpactTests: XCTestCase {
    private let target = IBMObjectIdentity(
        library: try! IBMSystemObjectName("ARLIB"),
        name: try! IBMSystemObjectName("ORDERSRV"),
        type: .serviceProgram
    )

    func testIdentityNormalizesNamesAndRejectsUnsafeInput() throws {
        let identity = try IBMObjectIdentity(library: "arlib", name: "ordersrv", type: .serviceProgram)
        XCTAssertEqual(identity.description, "ARLIB/ORDERSRV *SRVPGM")
        XCTAssertThrowsError(try IBMObjectIdentity(library: "ARLIB'", name: "ORDERSRV", type: .serviceProgram))
        XCTAssertEqual(IBMObjectType.allCases.count, 12)
    }

    func testPlannerBuildsSixExactBoundedReadOnlyRequestsWithoutHostWrites() throws {
        let planner = ObjectImpactSQLPlanner(target: target)
        XCTAssertEqual(planner.liveRequests.map(\.0), ObjectImpactEvidenceSource.liveSQLSources)
        XCTAssertEqual(planner.liveRequests.count, 6)

        for (_, request) in planner.liveRequests {
            XCTAssertTrue(request.readOnly)
            XCTAssertEqual(request.timeoutSeconds, 30)
            XCTAssertTrue((1...100).contains(request.maximumRows))
            XCTAssertTrue(SQLStatementAnalyzer().analyze(request.sql).isSingleReadOnlyStatement)
            XCTAssertNoThrow(try Db2OperationAuthorizer(accessMode: .readOnly).authorizeInteractiveSQL(request))
            XCTAssertFalse(request.sql.uppercased().contains("DSPPGMREF"))
            XCTAssertFalse(request.sql.uppercased().contains("OUTFILE"))
        }

        XCTAssertTrue(planner.objectStatistics.sql.contains("'ARLIB', '*SRVPGM', 'ORDERSRV'"))
        XCTAssertTrue(planner.boundServicePrograms.sql.contains("BOUND_SERVICE_PROGRAM_LIBRARY = 'ARLIB'"))
        XCTAssertTrue(planner.boundServicePrograms.sql.contains("BOUND_SERVICE_PROGRAM = 'ORDERSRV'"))
        XCTAssertTrue(planner.boundModules.sql.contains("PROGRAM_LIBRARY = 'ARLIB'"))
        XCTAssertTrue(planner.bindingDirectories.sql.contains("ENTRY_TYPE = '*SRVPGM'"))
        XCTAssertTrue(planner.sqlRoutines.sql.contains("ARLIB/ORDERSRV(%"))
        XCTAssertTrue(planner.viewDependencies.sql.contains("1 = 0"))
        XCTAssertFalse(planner.liveRequests.contains { $0.0 == .programReferences })
    }

    func testMetadataDecoderUsesNamesAndPreservesExactObjectEvidence() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let values: [String: SQLValue] = [
            "OBJNAME": .string("ORDERSRV"),
            "OBJTYPE": .string("*SRVPGM"),
            "OBJLIB": .string("ARLIB"),
            "OBJOWNER": .string("ARAPP"),
            "OBJATTRIBUTE": .string("RPGLE"),
            "OBJTEXT": .string("Order services"),
            "OBJSIZE": .decimal("418816"),
            "OBJCREATED": .timestamp(date),
            "CHANGE_TIMESTAMP": .timestamp(date.addingTimeInterval(10)),
            "LAST_USED_TIMESTAMP": .timestamp(date.addingTimeInterval(20)),
            "SOURCE_LIBRARY": .string("ARLIB"),
            "SOURCE_FILE": .string("QRPGLESRC"),
            "SOURCE_MEMBER": .string("ORDERSRV"),
            "SOURCE_TIMESTAMP": .timestamp(date.addingTimeInterval(-10)),
            "SQL_OBJECT_TYPE": .null
        ]
        let result = namedResult(order: metadataColumns.reversed(), values: values)
        let metadata = try XCTUnwrap(ObjectImpactSQLDecoder().decodeMetadata(result, target: target))

        XCTAssertEqual(metadata.identity, target)
        XCTAssertEqual(metadata.owner, "ARAPP")
        XCTAssertEqual(metadata.sizeBytes, 418_816)
        XCTAssertEqual(metadata.sourceFile, "QRPGLESRC")
        XCTAssertEqual(metadata.changedAt, date.addingTimeInterval(10))
    }

    func testMetadataDecoderFailsClosedOnDuplicateMissingMismatchAndTruncation() throws {
        let values = validMetadataValues
        let duplicateColumns = metadataColumns + ["objname"]
        let duplicateRow = metadataColumns.map { values[$0]! } + [.string("ORDERSRV")]
        XCTAssertThrowsError(try ObjectImpactSQLDecoder().decodeMetadata(
            sqlResult(columns: duplicateColumns, rows: [duplicateRow]),
            target: target
        )) { error in
            XCTAssertEqual(error as? ObjectImpactError, .duplicateColumn(source: "OBJECT_STATISTICS", column: "OBJNAME"))
        }

        let missing = metadataColumns.filter { $0 != "OBJOWNER" }
        XCTAssertThrowsError(try ObjectImpactSQLDecoder().decodeMetadata(
            namedResult(order: missing, values: values),
            target: target
        )) { error in
            XCTAssertEqual(error as? ObjectImpactError, .missingColumn(source: "OBJECT_STATISTICS", column: "OBJOWNER"))
        }

        var mismatch = values
        mismatch["OBJNAME"] = .string("OTHER")
        XCTAssertThrowsError(try ObjectImpactSQLDecoder().decodeMetadata(
            namedResult(order: metadataColumns, values: mismatch),
            target: target
        )) { error in
            XCTAssertEqual(error as? ObjectImpactError, .identityMismatch(source: "OBJECT_STATISTICS"))
        }

        XCTAssertThrowsError(try ObjectImpactSQLDecoder().decodeMetadata(
            namedResult(order: metadataColumns, values: values, truncated: true),
            target: target
        )) { error in
            XCTAssertEqual(error as? ObjectImpactError, .truncatedSingleton(source: "OBJECT_STATISTICS"))
        }
    }

    func testBoundServiceProgramDecoderPreservesDirectionAndActivation() throws {
        let values: [String: SQLValue] = [
            "EDGE_DIRECTION": .string("INCOMING"),
            "FROM_LIBRARY": .string("ARLIB"),
            "FROM_NAME": .string("ORDERAPI"),
            "FROM_TYPE": .string("*PGM"),
            "TO_LIBRARY": .string("ARLIB"),
            "TO_NAME": .string("ORDERSRV"),
            "TO_TYPE": .string("*SRVPGM"),
            "ACTIVATION": .string("*DEFER")
        ]
        let edge = try XCTUnwrap(ObjectImpactSQLDecoder().decodeBoundServicePrograms(
            namedResult(order: Array(values.keys).reversed(), values: values)
        ).first)

        XCTAssertEqual(edge.direction, .incoming)
        XCTAssertEqual(edge.evidenceClass, .bound)
        XCTAssertEqual(edge.source, .boundServiceProgramInfo)
        XCTAssertEqual(edge.from.label, "ARLIB/ORDERAPI *PGM")
        XCTAssertEqual(edge.to.label, "ARLIB/ORDERSRV *SRVPGM")
        XCTAssertEqual(edge.detail, "*DEFER")
    }

    func testModuleCandidateRoutineAndViewDecodersKeepEvidenceClassesDistinct() throws {
        let decoder = ObjectImpactSQLDecoder()
        let module = try XCTUnwrap(decoder.decodeBoundModules(namedResult(order: moduleValues.keys, values: moduleValues)).first)
        let candidate = try XCTUnwrap(decoder.decodeBindingDirectories(namedResult(order: directoryValues.keys, values: directoryValues)).first)
        let routine = try XCTUnwrap(decoder.decodeSQLRoutines(namedResult(order: routineValues.keys, values: routineValues)).first)
        let view = try XCTUnwrap(decoder.decodeViewDependencies(namedResult(order: viewValues.keys, values: viewValues)).first)

        XCTAssertEqual(module.evidenceClass, .bound)
        XCTAssertTrue(module.detail?.contains("QRPGLESRC") == true)
        XCTAssertEqual(candidate.evidenceClass, .candidate)
        XCTAssertTrue(candidate.detail?.contains("not proof") == false)
        XCTAssertEqual(routine.evidenceClass, .catalog)
        XCTAssertEqual(routine.detail, "RPGLE · READS")
        XCTAssertEqual(view.evidenceClass, .catalog)
        XCTAssertEqual(view.direction, .incoming)
    }

    func testEdgeDecoderRejectsBoundsAndControlCharacters() throws {
        let decoder = ObjectImpactSQLDecoder(limits: .init(maximumEdgesPerSource: 1))
        let columns = Array(serviceValues.keys)
        let row = columns.map { serviceValues[$0]! }
        XCTAssertThrowsError(try decoder.decodeBoundServicePrograms(sqlResult(columns: columns, rows: [row, row]))) { error in
            XCTAssertEqual(error as? ObjectImpactError, .tooManyRows(source: "BOUND_SRVPGM_INFO", maximum: 1))
        }

        var unsafe = serviceValues
        unsafe["FROM_NAME"] = .string("ORDER\nAPI")
        XCTAssertThrowsError(try ObjectImpactSQLDecoder().decodeBoundServicePrograms(namedResult(order: columns, values: unsafe))) { error in
            XCTAssertEqual(error as? ObjectImpactError, .invalidText(source: "BOUND_SRVPGM_INFO", index: 1, column: "FROM_NAME"))
        }
    }

    func testSnapshotDeduplicatesEdgesAndNeverProducesSafeChangeVerdict() throws {
        let edge = try sampleEdge()
        let gap = ObjectImpactEvidenceReceipt(
            source: .programReferences,
            rowCount: 0,
            boundWasReached: false,
            elapsedMilliseconds: nil,
            queryFingerprint: "gap",
            outcome: .unavailable("Read-only milestone")
        )
        let snapshot = ObjectImpactSnapshot(
            targetName: "DEV",
            target: target,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            metadata: nil,
            edges: [edge, edge],
            receipts: [gap]
        )

        XCTAssertEqual(snapshot.edges.count, 1)
        XCTAssertEqual(snapshot.assessment.incomingCount, 1)
        XCTAssertEqual(snapshot.assessment.gapCount, 1)
        XCTAssertEqual(snapshot.assessment.verdict, "REVIEW REQUIRED")
        XCTAssertTrue(snapshot.assessment.method.contains("Missing rows never prove absence"))
        XCTAssertTrue(snapshot.assessment.method.contains("No runtime frequency"))
    }

    func testAssistContextWithholdsHostAndObjectIdentifiers() throws {
        let snapshot = sampleSnapshot(targetName: "private-host")
        let context = ObjectImpactAssistContextBuilder().build(snapshot: snapshot)

        XCTAssertFalse(context.contains("private-host"))
        XCTAssertFalse(context.contains("ARLIB"))
        XCTAssertFalse(context.contains("ORDERSRV"))
        XCTAssertFalse(context.contains("ORDERAPI"))
        XCTAssertFalse(context.contains("authority details"))
        XCTAssertTrue(context.contains("FOCUS-OBJECT *SRVPGM"))
        XCTAssertTrue(context.contains("OBJECT-001 *PGM"))
        XCTAssertTrue(context.contains("BOUND_SRVPGM_INFO"))
        XCTAssertEqual(AIContextKind.objectImpact.label, "Object impact")
        XCTAssertFalse(AIContextKind.objectImpact.requiresSelection)
    }

    func testArtifactIncludesExactReceiptsAndExplicitLimitations() throws {
        let artifact = ObjectImpactArtifactBuilder().build(snapshot: sampleSnapshot(targetName: "DEV01"))
        XCTAssertTrue(artifact.contains("ARLIB/ORDERSRV *SRVPGM"))
        XCTAssertTrue(artifact.contains("ARLIB/ORDERAPI *PGM -> ARLIB/ORDERSRV *SRVPGM"))
        XCTAssertTrue(artifact.contains("PROGRAM_REFERENCES: UNAVAILABLE"))
        XCTAssertTrue(artifact.contains("Missing rows never prove absence"))
        XCTAssertTrue(artifact.contains("No runtime call frequency"))
        XCTAssertTrue(artifact.contains("No host writes"))
    }

    private func sampleEdge() throws -> ObjectImpactEdge {
        ObjectImpactEdge(
            direction: .incoming,
            from: try ObjectImpactNode(library: "ARLIB", name: "ORDERAPI", type: "*PGM"),
            to: ObjectImpactNode(target),
            evidenceClass: .bound,
            source: .boundServiceProgramInfo,
            detail: "*DEFER"
        )
    }

    private func sampleSnapshot(targetName: String) -> ObjectImpactSnapshot {
        let planner = ObjectImpactSQLPlanner(target: target)
        let collected = ObjectImpactEvidenceReceipt(
            source: .boundServiceProgramInfo,
            rowCount: 1,
            boundWasReached: false,
            elapsedMilliseconds: 12,
            queryFingerprint: AIContentFingerprint.sha256(planner.boundServicePrograms.sql),
            outcome: .collected
        )
        let gap = ObjectImpactEvidenceReceipt(
            source: .programReferences,
            rowCount: 0,
            boundWasReached: false,
            elapsedMilliseconds: nil,
            queryFingerprint: "private-fingerprint",
            outcome: .unavailable("private authority details")
        )
        return ObjectImpactSnapshot(
            targetName: targetName,
            target: target,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            metadata: nil,
            edges: [try! sampleEdge()],
            receipts: [collected, gap]
        )
    }

    private var metadataColumns: [String] {
        [
            "OBJNAME", "OBJTYPE", "OBJLIB", "OBJOWNER", "OBJATTRIBUTE", "OBJTEXT", "OBJSIZE",
            "OBJCREATED", "CHANGE_TIMESTAMP", "LAST_USED_TIMESTAMP", "SOURCE_LIBRARY", "SOURCE_FILE",
            "SOURCE_MEMBER", "SOURCE_TIMESTAMP", "SQL_OBJECT_TYPE"
        ]
    }

    private var validMetadataValues: [String: SQLValue] {
        let date = Date(timeIntervalSince1970: 1_000)
        return Dictionary(uniqueKeysWithValues: metadataColumns.map { ($0, SQLValue.null) }).merging([
            "OBJNAME": .string("ORDERSRV"), "OBJTYPE": .string("*SRVPGM"), "OBJLIB": .string("ARLIB"),
            "OBJSIZE": .integer(1), "OBJCREATED": .timestamp(date), "CHANGE_TIMESTAMP": .timestamp(date)
        ]) { _, replacement in replacement }
    }

    private var serviceValues: [String: SQLValue] {
        [
            "EDGE_DIRECTION": .string("INCOMING"), "FROM_LIBRARY": .string("ARLIB"),
            "FROM_NAME": .string("ORDERAPI"), "FROM_TYPE": .string("*PGM"),
            "TO_LIBRARY": .string("ARLIB"), "TO_NAME": .string("ORDERSRV"),
            "TO_TYPE": .string("*SRVPGM"), "ACTIVATION": .string("*DEFER")
        ]
    }

    private var moduleValues: [String: SQLValue] {
        [
            "EDGE_DIRECTION": .string("OUTGOING"), "FROM_LIBRARY": .string("ARLIB"),
            "FROM_NAME": .string("ORDERSRV"), "FROM_TYPE": .string("*SRVPGM"),
            "TO_LIBRARY": .string("ARLIB"), "TO_NAME": .string("ORDERMOD"),
            "TO_TYPE": .string("*MODULE"), "MODULE_ATTRIBUTE": .string("RPGLE"),
            "SOURCE_FILE_LIBRARY": .string("ARLIB"), "SOURCE_FILE": .string("QRPGLESRC"),
            "SOURCE_FILE_MEMBER": .string("ORDERMOD"), "SOURCE_STREAM_FILE_PATH": .null,
            "MODULE_CREATE_TIMESTAMP": .timestamp(Date(timeIntervalSince1970: 1_000)),
            "SOURCE_CHANGE_TIMESTAMP": .timestamp(Date(timeIntervalSince1970: 900))
        ]
    }

    private var directoryValues: [String: SQLValue] {
        [
            "EDGE_DIRECTION": .string("INCOMING"), "FROM_LIBRARY": .string("ARLIB"),
            "FROM_NAME": .string("APPBNDDIR"), "FROM_TYPE": .string("*BNDDIR"),
            "TO_LIBRARY": .string("ARLIB"), "TO_NAME": .string("ORDERSRV"),
            "TO_TYPE": .string("*SRVPGM"), "ENTRY_ACTIVATION": .string("*DEFER")
        ]
    }

    private var routineValues: [String: SQLValue] {
        [
            "EDGE_DIRECTION": .string("INCOMING"), "FROM_LIBRARY": .string("ARAPI"),
            "FROM_NAME": .string("GET_ORDER"), "FROM_TYPE": .string("PROCEDURE"),
            "TO_LIBRARY": .string("ARLIB"), "TO_NAME": .string("ORDERSRV"),
            "TO_TYPE": .string("*SRVPGM"), "EXTERNAL_NAME": .string("ARLIB/ORDERSRV(GET_ORDER)"),
            "EXTERNAL_LANGUAGE": .string("RPGLE"), "SQL_DATA_ACCESS": .string("READS")
        ]
    }

    private var viewValues: [String: SQLValue] {
        [
            "EDGE_DIRECTION": .string("INCOMING"), "FROM_LIBRARY": .string("ARLIB"),
            "FROM_NAME": .string("ORDERVIEW"), "FROM_TYPE": .string("*FILE"),
            "TO_LIBRARY": .string("ARLIB"), "TO_NAME": .string("ORDERHDR"),
            "TO_TYPE": .string("*FILE"), "VIEW_SCHEMA": .string("ARLIB"),
            "VIEW_NAME": .string("ORDER_VIEW"), "OBJECT_TYPE": .string("TABLE")
        ]
    }

    private func namedResult<S: Sequence>(
        order: S,
        values: [String: SQLValue],
        truncated: Bool = false
    ) -> SQLResult where S.Element == String {
        let columns = Array(order)
        return sqlResult(columns: columns, rows: [columns.map { values[$0] ?? .null }], truncated: truncated)
    }

    private func sqlResult(
        columns: [String],
        rows: [[SQLValue]],
        truncated: Bool = false
    ) -> SQLResult {
        SQLResult(
            columns: columns.map { SQLColumn(name: $0, databaseType: "VARCHAR", isNullable: true) },
            rows: rows,
            targetName: "TEST",
            startedAt: Date(timeIntervalSince1970: 1_000),
            elapsedMilliseconds: 12,
            wasTruncated: truncated
        )
    }
}
