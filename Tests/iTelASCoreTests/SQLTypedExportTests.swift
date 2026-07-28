import Foundation
import XCTest
@testable import iTelASCore

final class SQLTypedExportTests: XCTestCase {
    func testCSVBundleIsDeterministicAndDisclosesEveryRepresentationChange() throws {
        let result = sampleResult()
        let builder = SQLTypedExportBuilder()

        let first = try builder.build(
            result: result,
            query: sampleQuery,
            providerName: "IBM i Access ODBC",
            environment: .development,
            format: .csvBundle
        )
        let second = try builder.build(
            result: result,
            query: sampleQuery,
            providerName: "IBM i Access ODBC",
            environment: .development,
            format: .csvBundle
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.files.map(\.name), ["data.csv", "schema.json", "receipt.json"])
        XCTAssertEqual(first.rowCount, 2)
        XCTAssertEqual(first.columnCount, 8)
        XCTAssertEqual(first.nullCount, 2)
        XCTAssertEqual(first.formulaRiskCount, 1)
        XCTAssertEqual(first.binaryCellCount, 1)
        XCTAssertEqual(first.columns[0].ccsid, 37)
        XCTAssertEqual(first.columns[1].observedKinds, [.decimal])

        let csv = try XCTUnwrap(String(
            data: try XCTUnwrap(first.files.first(where: { $0.name == "data.csv" })).data,
            encoding: .utf8
        ))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
        XCTAssertTrue(csv.contains("'=OPS"))
        XCTAssertTrue(csv.contains("'12345678901234567890.4400"))
        XCTAssertTrue(csv.contains("'9223372036854775807"))
        XCTAssertTrue(csv.contains("\\N"))
        XCTAssertTrue(csv.contains("'AQID"))

        let schema = try jsonObject(named: "schema.json", in: first)
        XCTAssertEqual(schema["nullToken"] as? String, "\\N")
        XCTAssertEqual(schema["decimalMode"] as? String, "apostrophe-prefixed exact text")
        let columns = try XCTUnwrap(schema["columns"] as? [[String: Any]])
        XCTAssertEqual(columns[0]["name"] as? String, "AUTHORIZATION_NAME")
        XCTAssertEqual(columns[0]["ccsid"] as? Int, 37)

        let receipt = try jsonObject(named: "receipt.json", in: first)
        XCTAssertEqual(receipt["planSHA256"] as? String, first.fingerprint)
        XCTAssertEqual(receipt["querySHA256"] as? String, first.queryFingerprint)
        XCTAssertEqual(receipt["resultSHA256"] as? String, first.resultFingerprint)
        XCTAssertEqual((receipt["payloadFiles"] as? [[String: Any]])?.count, 2)
    }

    func testTypedJSONKeepsFormulaTextAndTaggedExactValues() throws {
        let plan = try SQLTypedExportBuilder().build(
            result: sampleResult(),
            query: sampleQuery,
            providerName: "IBM i Access ODBC",
            environment: .development,
            format: .typedJSON
        )

        XCTAssertEqual(plan.files.map(\.name), ["result.typed.json"])
        XCTAssertEqual(plan.formulaRiskCount, 0)
        let document = try jsonObject(named: "result.typed.json", in: plan)
        let rows = try XCTUnwrap(document["rows"] as? [[[String: Any]]])
        XCTAssertEqual(rows[0][0]["kind"] as? String, "string")
        XCTAssertEqual(rows[0][0]["value"] as? String, "=OPS")
        XCTAssertEqual(rows[0][1]["kind"] as? String, "decimal")
        XCTAssertEqual(rows[0][1]["value"] as? String, "12345678901234567890.4400")
        XCTAssertEqual(rows[0][6]["kind"] as? String, "integer")
        XCTAssertEqual(rows[0][6]["value"] as? String, "9223372036854775807")
        XCTAssertEqual(rows[1][2]["kind"] as? String, "null")
        XCTAssertNil(rows[1][2]["value"])
        XCTAssertEqual(rows[0][5]["kind"] as? String, "binary")
        XCTAssertEqual(rows[0][5]["value"] as? String, "AQID")
        XCTAssertEqual(rows[0][5]["byteCount"] as? Int, 3)
    }

    func testMalformedAndOverLimitResultsFailClosed() throws {
        let builder = SQLTypedExportBuilder()
        let base = sampleResult()
        let duplicate = SQLResult(
            columns: [base.columns[0], SQLColumn(name: "authorization_name", databaseType: "VARCHAR", isNullable: false)],
            rows: [[.string("A"), .string("B")]],
            targetName: base.targetName,
            startedAt: base.startedAt,
            elapsedMilliseconds: 1,
            wasTruncated: false
        )
        XCTAssertThrowsError(try makePlan(duplicate, builder: builder)) {
            XCTAssertEqual($0 as? SQLTypedExportError, .duplicateColumn("authorization_name"))
        }

        let wrongWidth = SQLResult(
            columns: base.columns,
            rows: [[.string("only one")]],
            targetName: base.targetName,
            startedAt: base.startedAt,
            elapsedMilliseconds: 1,
            wasTruncated: false
        )
        XCTAssertThrowsError(try makePlan(wrongWidth, builder: builder)) {
            XCTAssertEqual(
                $0 as? SQLTypedExportError,
                .invalidRowWidth(row: 0, expected: base.columns.count, actual: 1)
            )
        }

        var invalidDecimalRows = base.rows
        invalidDecimalRows[0][1] = .decimal("12.3 DROP TABLE")
        let invalidDecimal = SQLResult(
            columns: base.columns,
            rows: invalidDecimalRows,
            targetName: base.targetName,
            startedAt: base.startedAt,
            elapsedMilliseconds: 1,
            wasTruncated: false
        )
        XCTAssertThrowsError(try makePlan(invalidDecimal, builder: builder)) {
            XCTAssertEqual($0 as? SQLTypedExportError, .invalidDecimal(row: 0, column: 1))
        }

        let tiny = SQLTypedExportBuilder(limits: SQLTypedExportLimits(
            maximumColumns: 2,
            maximumRows: 1,
            maximumCellUTF8Bytes: 8,
            maximumQueryUTF8Bytes: 8,
            maximumArtifactBytes: 64
        ))
        XCTAssertThrowsError(try makePlan(base, builder: tiny)) {
            XCTAssertEqual($0 as? SQLTypedExportError, .queryTooLarge(maximum: 8))
        }
    }

    func testWriterCreatesPrivateVerifiedPackageAndRefusesSymbolicDestination() throws {
        let plan = try SQLTypedExportBuilder().build(
            result: sampleResult(),
            query: sampleQuery,
            providerName: "IBM i Access ODBC",
            environment: .development,
            format: .csvBundle
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-sql-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("result.itelasdb2", isDirectory: true)

        try SQLTypedExportWriter().write(plan, to: destination)

        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        for file in plan.files {
            let url = destination.appendingPathComponent(file.name)
            XCTAssertEqual(try Data(contentsOf: url), file.data)
            let mode = try XCTUnwrap(
                FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            ).intValue
            XCTAssertEqual(mode & 0o777, 0o600)
        }

        let link = root.appendingPathComponent("linked.itelasdb2")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        XCTAssertThrowsError(
            try SQLTypedExportWriter().write(plan, to: link, replacingExisting: true)
        ) {
            XCTAssertEqual($0 as? SQLTypedExportError, .symbolicDestination)
        }
    }

    private let sampleQuery = "SELECT * FROM QSYS2.ACTIVE_JOB_INFO FETCH FIRST 2 ROWS ONLY"

    private func sampleResult() -> SQLResult {
        let instant = Date(timeIntervalSince1970: 1_700_000_000.123)
        return SQLResult(
            columns: [
                SQLColumn(name: "AUTHORIZATION_NAME", databaseType: "VARCHAR(10)", isNullable: false, ccsid: 37),
                SQLColumn(name: "AMOUNT", databaseType: "DECIMAL(31,4)", isNullable: false),
                SQLColumn(name: "LAST_ACTIVITY", databaseType: "TIMESTAMP(6)", isNullable: true),
                SQLColumn(name: "BUSINESS_DATE", databaseType: "DATE", isNullable: false),
                SQLColumn(name: "IS_HELD", databaseType: "BOOLEAN", isNullable: false),
                SQLColumn(name: "DETAIL_BLOB", databaseType: "BLOB", isNullable: true),
                SQLColumn(name: "LARGE_COUNT", databaseType: "BIGINT", isNullable: false),
                SQLColumn(name: "EMPTY_TEXT", databaseType: "VARCHAR(10)", isNullable: false, ccsid: 1208)
            ],
            rows: [
                [
                    .string("=OPS"),
                    .decimal("12345678901234567890.4400"),
                    .timestamp(instant),
                    .date(instant),
                    .boolean(false),
                    .binary(Data([1, 2, 3])),
                    .integer(Int64.max),
                    .string("")
                ],
                [
                    .string("RPGDEV1"),
                    .decimal("0.0000"),
                    .null,
                    .date(instant.addingTimeInterval(86_400)),
                    .boolean(true),
                    .null,
                    .integer(-42),
                    .string("\\N")
                ]
            ],
            targetName: "DEV ORION",
            startedAt: instant,
            elapsedMilliseconds: 184,
            wasTruncated: false
        )
    }

    private func makePlan(
        _ result: SQLResult,
        builder: SQLTypedExportBuilder
    ) throws -> SQLTypedExportPlan {
        try builder.build(
            result: result,
            query: sampleQuery,
            providerName: "IBM i Access ODBC",
            environment: .development,
            format: .csvBundle
        )
    }

    private func jsonObject(
        named name: String,
        in plan: SQLTypedExportPlan
    ) throws -> [String: Any] {
        let data = try XCTUnwrap(plan.files.first(where: { $0.name == name })?.data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
