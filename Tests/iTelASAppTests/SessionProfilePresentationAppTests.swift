import XCTest
@testable import iTelAS
@testable import iTelASCore

final class SessionProfilePresentationAppTests: XCTestCase {
    func testWorkspaceTextDoesNotExposeTheConnectionEndpoint() {
        let profile = SessionProfile(
            name: "Development",
            host: "sensitive.internal.example",
            port: 15_432,
            security: .tls,
            terminalModel: .ibm3179_2
        )

        XCTAssertEqual(profile.workspaceSummary, "TLS · 24×80")
        XCTAssertFalse(profile.workspaceSummary.contains(profile.host))
        XCTAssertFalse(profile.workspaceSummary.contains(String(profile.port)))
        XCTAssertFalse(profile.deletionConfirmationMessage.contains(profile.host))
        XCTAssertFalse(profile.deletionConfirmationMessage.contains(String(profile.port)))

        XCTAssertEqual(profile.host, "sensitive.internal.example")
        XCTAssertEqual(profile.port, 15_432)
    }
}
