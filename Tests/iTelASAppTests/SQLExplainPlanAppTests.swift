import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class SQLExplainPlanAppTests: XCTestCase {
    func testModelBuildsAndStudioRendersLocalStaticReview() throws {
        let model = isolatedModel()
        model.sqlText = """
        SELECT *
          FROM QSYS2.ACTIVE_JOB_INFO
         WHERE JOB_TYPE <> 'SYS'
         ORDER BY ELAPSED_CPU_PERCENTAGE DESC
         FETCH FIRST 25 ROWS ONLY
        """
        model.sqlPolicy = SQLQueryPolicy(maximumRows: 50, timeoutSeconds: 15)

        model.presentSQLExplainStudio()

        let review = try XCTUnwrap(model.sqlExplainReview)
        XCTAssertTrue(model.isSQLExplainPresented)
        XCTAssertEqual(review.analysis.explicitRowLimit, 25)
        XCTAssertEqual(review.sourceReferences, ["QSYS2.ACTIVE_JOB_INFO"])
        XCTAssertTrue(model.sqlExplainDiagnostic.contains("No provider call"))

        let content = SQLExplainPlanStudioView()
            .environment(model)
            .frame(width: 1_180, height: 760)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_180, height: 760)
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_180)
        XCTAssertEqual(image.height, 760)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_SQL_EXPLAIN"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-sql-explain-native.png"),
                options: .atomic
            )
        }
    }

    private func isolatedModel() -> AppModel {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-sql-explain-\(UUID().uuidString)", isDirectory: true)
        return AppModel(
            continuityCasebookStore: ContinuityCasebookStore(
                baseDirectoryURL: base.appendingPathComponent("casebook", isDirectory: true)
            ),
            terminalFlightRecorderStore: TerminalFlightRecorderStore(
                baseDirectoryURL: base.appendingPathComponent("recorder", isDirectory: true)
            ),
            compileRecipeStore: CompileRecipeStore(
                baseDirectoryURL: base.appendingPathComponent("recipes", isDirectory: true)
            )
        )
    }
}
