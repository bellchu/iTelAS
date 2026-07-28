import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class TerminalForwardEdgeTriggerAppTests: XCTestCase {
    func testOperatorAreaRendersForwardEdgeAIDContract() throws {
        let profile = SessionProfile(
            name: "DEV400",
            host: "dev400.example.invalid",
            environment: .development
        )
        var session = TerminalSessionState(profile: profile)
        session.screen.fields = [TerminalField(
            start: 10,
            length: 4,
            isProtected: false,
            autoEnter: true,
            isForwardEdgeTrigger: true,
            modified: true
        )]
        session.screen.moveCursor(row: 0, column: 10)
        session.screen.inputInhibited = false

        let model = AppModel()
        model.profiles = [profile]
        model.terminalSessions = [session]
        model.selectedTerminalSessionID = session.id

        XCTAssertEqual(
            model.screen.currentEditableFieldContract,
            "ALPHA SHIFT · FWD EDGE · AID FET"
        )

        let content = SessionWorkspaceView()
            .environment(model)
            .frame(width: 1_260, height: 820)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_260, height: 820)
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_260)
        XCTAssertEqual(image.height, 820)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_FORWARD_EDGE"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_260, height: 820)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-forward-edge-trigger-native.png"),
                options: .atomic
            )
        }
    }
}
