import XCTest
@testable import iTelASCore

final class SourceWorkspaceDriftTests: XCTestCase {
    func testReceiptCoalescesCaseInsensitivePathsAndFingerprintsDeterministically() throws {
        let first = try SourceWorkspaceDriftObservation(
            relativePath: "SRC/Order.rpgle",
            kinds: [.modified],
            rawEventCount: 2,
            eventID: 91
        )
        let second = try SourceWorkspaceDriftObservation(
            relativePath: "src/order.rpgle",
            kinds: [.metadata, .renamed],
            rawEventCount: 3,
            eventID: 94
        )
        let third = try SourceWorkspaceDriftObservation(
            relativePath: "includes/taxrules.cpy",
            kinds: [.created],
            eventID: 99
        )
        let receiptA = SourceWorkspaceDriftReceipt(
            baselineIndexFingerprint: "INDEX-A",
            observations: [first, second, third]
        )
        let receiptB = SourceWorkspaceDriftReceipt(
            baselineIndexFingerprint: "INDEX-A",
            observations: [
                try SourceWorkspaceDriftObservation(
                    relativePath: "includes/taxrules.cpy",
                    kinds: [.created],
                    eventID: 2
                ),
                try SourceWorkspaceDriftObservation(
                    relativePath: "src/order.rpgle",
                    kinds: [.renamed, .metadata],
                    rawEventCount: 3,
                    eventID: 3
                ),
                try SourceWorkspaceDriftObservation(
                    relativePath: "SRC/Order.rpgle",
                    kinds: [.modified],
                    rawEventCount: 2,
                    eventID: 4
                )
            ]
        )

        XCTAssertEqual(receiptA.fingerprint, receiptB.fingerprint)
        XCTAssertEqual(receiptA.rawEventCount, 6)
        XCTAssertEqual(receiptA.uniquePathCount, 2)
        XCTAssertEqual(receiptA.entries.map(\.displayPath), [
            "includes/taxrules.cpy", "SRC/Order.rpgle"
        ])
        XCTAssertEqual(receiptA.entries.last?.rawEventCount, 5)
        XCTAssertEqual(Set(receiptA.entries.last?.kinds ?? []), [.modified, .metadata, .renamed])
        XCTAssertEqual(receiptA.maximumEventID, 99)
        XCTAssertEqual(receiptB.maximumEventID, 4)
    }

    func testObservationRejectsUnsafeOrUnboundedPaths() {
        for path in ["", "/absolute.rpgle", "../escape.rpgle", "src/../escape.rpgle", "src\\escape.rpgle"] {
            XCTAssertThrowsError(try SourceWorkspaceDriftObservation(
                relativePath: path,
                kinds: [.modified],
                eventID: 1
            ))
        }
        XCTAssertThrowsError(try SourceWorkspaceDriftObservation(
            relativePath: "src/very-long-name.rpgle",
            kinds: [.modified],
            eventID: 1,
            limits: SourceWorkspaceDriftLimits(maximumRelativePathUTF8Bytes: 8)
        )) { error in
            XCTAssertEqual(error as? SourceWorkspaceDriftError, .relativePathTooLong(8))
        }
    }

    func testReceiptBoundsSignalsForcesVerificationAndClearsOnlyThroughBoundary() throws {
        let observations = try (1...5).map { number in
            try SourceWorkspaceDriftObservation(
                relativePath: "src/file\(number).rpgle",
                kinds: [.modified],
                eventID: UInt64(number)
            )
        }
        let bounded = SourceWorkspaceDriftReceipt(
            baselineIndexFingerprint: "INDEX-B",
            observations: observations,
            limits: SourceWorkspaceDriftLimits(maximumUniquePaths: 2, maximumRawEvents: 3)
        )

        XCTAssertTrue(bounded.isTruncated)
        XCTAssertTrue(bounded.requiresFullVerification)
        XCTAssertEqual(bounded.entries.count, 2)
        XCTAssertEqual(bounded.rawEventCount, 5)
        XCTAssertEqual(
            SourceWorkspaceDriftReceipt.observations(observations, afterClearingThrough: 3).map(\.eventID),
            [4, 5]
        )

        let rootSignal = try SourceWorkspaceDriftObservation(
            relativePath: nil,
            kinds: [.rootChanged, .rescanRequired],
            eventID: 6
        )
        let rootReceipt = SourceWorkspaceDriftReceipt(
            baselineIndexFingerprint: "INDEX-B",
            observations: [rootSignal]
        )
        XCTAssertTrue(rootReceipt.requiresFullVerification)
        XCTAssertEqual(rootReceipt.entries.first?.displayPath, "WORKSPACE ROOT")

        let coalescedOverflow = SourceWorkspaceDriftReceipt(
            baselineIndexFingerprint: "INDEX-B",
            observations: [try SourceWorkspaceDriftObservation(
                relativePath: "src/burst.rpgle",
                kinds: [.modified],
                rawEventCount: 4,
                eventID: 7
            )],
            limits: SourceWorkspaceDriftLimits(maximumRawEvents: 3)
        )
        XCTAssertTrue(coalescedOverflow.isTruncated)
        XCTAssertTrue(coalescedOverflow.requiresFullVerification)
    }
}
