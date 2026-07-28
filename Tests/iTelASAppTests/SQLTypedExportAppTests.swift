import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class SQLTypedExportAppTests: XCTestCase {
    func testModelBuildsAndSwitchesExactRetainedExportPlans() throws {
        let model = configuredModel(suffix: "plan")

        model.presentSQLTypedExportStudio()

        let csv = try XCTUnwrap(model.sqlTypedExportPlan)
        XCTAssertTrue(model.isSQLTypedExportPresented)
        XCTAssertEqual(csv.format, .csvBundle)
        XCTAssertEqual(csv.files.map(\.name), ["data.csv", "schema.json", "receipt.json"])
        XCTAssertEqual(csv.rowCount, 5)
        XCTAssertEqual(csv.columnCount, 6)
        XCTAssertEqual(csv.formulaRiskCount, 1)
        XCTAssertTrue(model.sqlTypedExportDiagnostic.contains(csv.shortFingerprint))

        model.selectSQLTypedExportFormat(.typedJSON)

        let json = try XCTUnwrap(model.sqlTypedExportPlan)
        XCTAssertEqual(json.format, .typedJSON)
        XCTAssertEqual(json.files.map(\.name), ["result.typed.json"])
        XCTAssertEqual(json.resultFingerprint, csv.resultFingerprint)
        XCTAssertEqual(json.queryFingerprint, csv.queryFingerprint)
        XCTAssertNotEqual(json.fingerprint, csv.fingerprint)
    }

    func testMissingExecutionProvenanceRefusesExportPresentation() {
        let model = isolatedModel(suffix: "missing")
        model.sqlResult = sampleResult()

        model.presentSQLTypedExportStudio()

        XCTAssertNil(model.sqlTypedExportPlan)
        XCTAssertFalse(model.isSQLTypedExportPresented)
        XCTAssertTrue(model.sqlTypedExportDiagnostic.contains("exact executed query"))
    }

    func testSchemaAssistContextOmitsQueryAndCellValues() throws {
        let model = configuredModel(suffix: "assist")
        model.presentSQLTypedExportStudio()
        let plan = try XCTUnwrap(model.sqlTypedExportPlan)

        model.prepareSQLTypedExportAssist()

        let fragment = try XCTUnwrap(model.preparedAssistantContextBundle?.fragments.first)
        XCTAssertEqual(fragment.kind, .sqlResult)
        XCTAssertEqual(fragment.language, "Db2 for i result schema")
        XCTAssertTrue(fragment.content.contains("ITELAS DB2 TYPED EXPORT SCHEMA v1"))
        XCTAssertTrue(fragment.content.contains(plan.fingerprint))
        XCTAssertTrue(fragment.content.contains("target=withheld"))
        XCTAssertFalse(fragment.content.contains("=OPS-TEAM"))
        XCTAssertFalse(fragment.content.contains("SELECT JOB_NAME"))
        XCTAssertTrue(fragment.content.contains("No query text or result cell value"))
        XCTAssertTrue(model.isAssistantVisible)
        XCTAssertTrue(model.isAIContextPreviewPresented)
        XCTAssertNotNil(model.latestAIContextReceipt)
    }

    func testTypedExportStudioRendersAtNativeReviewSize() throws {
        let model = configuredModel(suffix: "render")
        model.presentSQLTypedExportStudio()
        let content = SQLTypedExportStudioView()
            .environment(model)
            .frame(width: 1_180, height: 760)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_180, height: 760)
        let image = try XCTUnwrap(renderer.cgImage)

        XCTAssertEqual(image.width, 1_180)
        XCTAssertEqual(image.height, 760)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SQL_TYPED_EXPORT"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-sql-typed-export-native.png"),
                options: .atomic
            )
        }
    }

    private func configuredModel(suffix: String) -> AppModel {
        let model = isolatedModel(suffix: suffix)
        model.sqlResult = sampleResult()
        model.sqlResultQueryText = "SELECT JOB_NAME, AUTHORIZATION_NAME, CPU_PERCENT, LAST_ACTIVITY, IS_HELD, DETAIL_BLOB FROM QSYS2.ACTIVE_JOB_INFO FETCH FIRST 5 ROWS ONLY"
        model.sqlResultProviderName = "IBM i Access ODBC"
        model.sqlResultEnvironment = .development
        return model
    }

    private func sampleResult() -> SQLResult {
        let instant = Date(timeIntervalSince1970: 1_700_000_000.123)
        return SQLResult(
            columns: [
                SQLColumn(name: "JOB_NAME", databaseType: "VARCHAR(28)", isNullable: false, ccsid: 1208),
                SQLColumn(name: "AUTHORIZATION_NAME", databaseType: "VARCHAR(10)", isNullable: false, ccsid: 37),
                SQLColumn(name: "CPU_PERCENT", databaseType: "DECIMAL(7,4)", isNullable: false),
                SQLColumn(name: "LAST_ACTIVITY", databaseType: "TIMESTAMP(6)", isNullable: true),
                SQLColumn(name: "IS_HELD", databaseType: "BOOLEAN", isNullable: false),
                SQLColumn(name: "DETAIL_BLOB", databaseType: "BLOB", isNullable: true)
            ],
            rows: [
                [.string("841209/QUSER/QZDASOINIT"), .string("QUSER"), .decimal("12.3750"), .timestamp(instant), .boolean(false), .binary(Data(repeating: 0xA5, count: 24))],
                [.string("841305/RPGDEV1/QRWTSRVR"), .string("RPGDEV1"), .decimal("8.0041"), .timestamp(instant.addingTimeInterval(-24)), .boolean(false), .null],
                [.string("841492/BATCH/QBATCH"), .string("=OPS-TEAM"), .decimal("3.5000"), .null, .boolean(true), .binary(Data(repeating: 0x2F, count: 16))],
                [.string("841501/QSYS/QSYSARB"), .string("QSYS"), .decimal("0.0512"), .timestamp(instant.addingTimeInterval(-180)), .boolean(false), .null],
                [.string("841517/REPORTS/QRWTSRVR"), .string("REPORTS"), .decimal("0.0000"), .timestamp(instant.addingTimeInterval(-240)), .boolean(false), .binary(Data(repeating: 0x10, count: 8))]
            ],
            targetName: "DEV ORION",
            startedAt: instant,
            elapsedMilliseconds: 184,
            wasTruncated: false
        )
    }

    private func isolatedModel(suffix: String) -> AppModel {
        AppModel(
            continuityCasebookStore: ContinuityCasebookStore(
                baseDirectoryURL: temporaryDirectory(named: "\(suffix)-casebook")
            ),
            terminalFlightRecorderStore: TerminalFlightRecorderStore(
                baseDirectoryURL: temporaryDirectory(named: "\(suffix)-recorder")
            ),
            compileRecipeStore: CompileRecipeStore(
                baseDirectoryURL: temporaryDirectory(named: "\(suffix)-recipes")
            )
        )
    }

    private func temporaryDirectory(named suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-sql-export-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    }
}
