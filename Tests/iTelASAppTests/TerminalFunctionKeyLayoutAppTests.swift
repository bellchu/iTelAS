import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class TerminalFunctionKeyLayoutAppTests: XCTestCase {
    func testCustomizedProfileMappingDrivesModelAndNativeEditorRender() throws {
        var bindings = TerminalFunctionKeyBinding.standard
        bindings[0] = TerminalFunctionKeyBinding(
            slot: 1,
            hostFunction: 12,
            label: "Abort request",
            isPinned: true
        )
        bindings[11].isPinned = false

        let profile = SessionProfile(
            name: "DEV400",
            host: "dev400.example.invalid",
            functionKeyBindings: bindings
        )
        let session = TerminalSessionState(profile: profile)
        let model = AppModel()
        model.profiles = [profile]
        model.terminalSessions = [session]
        model.selectedTerminalSessionID = session.id

        let resolved = try XCTUnwrap(model.terminalFunctionKeyBinding(for: 1))
        XCTAssertEqual(resolved.hostFunction, 12)
        XCTAssertEqual(TN5250AID.function(resolved.hostFunction), TN5250AID.function(12))
        XCTAssertEqual(resolved.displayLabel, "Abort request")
        XCTAssertTrue(resolved.isPinned)
        XCTAssertFalse(try XCTUnwrap(model.terminalFunctionKeyBinding(for: 12)).isPinned)

        let content = TerminalFunctionKeyLayoutView(profile: profile)
            .environment(model)
            .frame(width: 1_080, height: 720)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_080, height: 720)
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_080)
        XCTAssertEqual(image.height, 720)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_FUNCTION_KEYS"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_080, height: 720)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-function-key-layout-native.png"),
                options: .atomic
            )
        }
    }
}
