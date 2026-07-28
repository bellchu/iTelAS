import XCTest
@testable import iTelASCore

final class SQLExplainReviewTests: XCTestCase {
    func testStaticReviewBuildsDeterministicClauseSequence() throws {
        let sql = """
        SELECT JOBS.JOB_NAME, COUNT(*) AS LOCK_COUNT
          FROM QSYS2.ACTIVE_JOB_INFO AS JOBS
          JOIN QSYS2.OBJECT_LOCK_INFO AS LOCKS
            ON LOCKS.JOB_NAME = JOBS.JOB_NAME
         WHERE JOBS.JOB_TYPE <> 'SYS'
         GROUP BY JOBS.JOB_NAME
         ORDER BY LOCK_COUNT DESC
         FETCH FIRST 50 ROWS ONLY
        """
        let builder = SQLExplainReviewBuilder()
        let policy = SQLQueryPolicy(maximumRows: 100, timeoutSeconds: 20)

        let first = try builder.build(sql: sql, policy: policy)
        let second = try builder.build(sql: sql, policy: policy)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.analysis.explicitRowLimit, 50)
        XCTAssertEqual(first.sourceReferences, ["QSYS2.ACTIVE_JOB_INFO", "QSYS2.OBJECT_LOCK_INFO"])
        XCTAssertEqual(first.stages.map(\.kind), [.source, .join, .filter, .grouping, .ordering, .limit, .projection])
        XCTAssertTrue(first.findings.contains { $0.title == "Join access path unknown" })
        XCTAssertEqual(first.findings.last?.detail, SQLExplainReview.boundary)
        XCTAssertTrue(first.summaryText().contains("review-sha256=\(first.fingerprint)"))
    }

    func testStaticReviewIgnoresSourceKeywordsInStringsAndComments() throws {
        let sql = """
        SELECT 'FROM QSYS2.NOT_A_SOURCE' AS NOTE
          FROM QSYS2.ACTIVE_JOB_INFO
         WHERE JOB_NAME <> 'JOIN QSYS2.NOT_A_SOURCE'
         -- JOIN QSYS2.NOT_A_SOURCE ON 1 = 1
         FETCH FIRST 10 ROWS ONLY
        """

        let review = try SQLExplainReviewBuilder().build(sql: sql)

        XCTAssertEqual(review.sourceReferences, ["QSYS2.ACTIVE_JOB_INFO"])
        XCTAssertEqual(review.stages.filter { $0.kind == .join }.count, 0)
    }

    func testStaticReviewUsesPolicyCapWithoutRewritingDraft() throws {
        let sql = "SELECT * FROM QSYS2.SYSTEM_STATUS_INFO"
        let review = try SQLExplainReviewBuilder().build(
            sql: sql,
            policy: SQLQueryPolicy(maximumRows: 75, timeoutSeconds: 12)
        )

        XCTAssertNil(review.analysis.explicitRowLimit)
        XCTAssertEqual(review.providerRowCap, 75)
        XCTAssertTrue(review.stages.contains {
            $0.kind == .limit && $0.detail.contains("75-row ceiling")
        })
        XCTAssertTrue(review.findings.contains { $0.title == "Wildcard projection" })
        XCTAssertTrue(review.findings.contains { $0.title == "Execution cap is external" })
        XCTAssertTrue(review.summaryText().contains(SQLExplainReview.boundary))
    }

    func testStaticReviewRejectsMultipleAndNonReadOnlyStatements() {
        let builder = SQLExplainReviewBuilder()

        XCTAssertThrowsError(try builder.build(sql: "SELECT 1; SELECT 2")) {
            XCTAssertEqual($0 as? SQLExplainReviewError, .requiresSingleStatement(found: 2))
        }
        XCTAssertThrowsError(try builder.build(sql: "UPDATE ARLIB.CUSTOMER SET STATUS = 'A'")) {
            XCTAssertEqual($0 as? SQLExplainReviewError, .requiresReadOnlySyntax(.dataChange))
        }
    }
}
