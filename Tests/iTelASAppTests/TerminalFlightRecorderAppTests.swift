import AppKit
import SwiftUI
import XCTest
@testable import iTelAS
@testable import iTelASCore

@MainActor
final class TerminalFlightRecorderAppTests: XCTestCase {
    func testPrivateRecorderStoreRoundTripsAndRejectsBroadOrSymlinkCustody() throws {
        let base = temporaryDirectory(named: "store")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = TerminalFlightRecorderStore(baseDirectoryURL: base)
        let archive = TerminalFlightRecorderSamples.makeArchive()

        try store.write(archive)

        XCTAssertEqual(try store.read(), archive)
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: base.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(directoryMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.fileURL.path)
        XCTAssertThrowsError(try store.read())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.fileURL.path)

        let linkedBase = temporaryDirectory(named: "leaf-link")
        defer { try? FileManager.default.removeItem(at: linkedBase) }
        try FileManager.default.createDirectory(
            at: linkedBase,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let linkedStore = TerminalFlightRecorderStore(baseDirectoryURL: linkedBase)
        try FileManager.default.createSymbolicLink(
            at: linkedStore.fileURL,
            withDestinationURL: store.fileURL
        )
        XCTAssertThrowsError(try linkedStore.read())

        let parentLink = temporaryDirectory(named: "parent-link")
        defer { try? FileManager.default.removeItem(at: parentLink) }
        try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: base)
        XCTAssertThrowsError(try TerminalFlightRecorderStore(baseDirectoryURL: parentLink).read())
    }

    func testModelBookmarksRedactedFrameAndRunsOnlyOneReviewedMatchStep() throws {
        let base = temporaryDirectory(named: "model")
        defer { try? FileManager.default.removeItem(at: base) }
        let recorderStore = TerminalFlightRecorderStore(baseDirectoryURL: base)
        let casebookStore = ContinuityCasebookStore(
            baseDirectoryURL: temporaryDirectory(named: "casebook")
        )
        defer { try? FileManager.default.removeItem(at: casebookStore.fileURL.deletingLastPathComponent()) }
        let model = AppModel(
            continuityCasebookStore: casebookStore,
            terminalFlightRecorderStore: recorderStore
        )
        let profile = SessionProfile(
            name: "DEV Evidence",
            host: "dev.example.invalid",
            environment: .development
        )
        var session = TerminalSessionState(profile: profile)
        session.screen.write(
            "VISIBLE OPERATOR INPUT",
            row: 17,
            column: 12,
            attributes: TerminalAttributes(foreground: .white, protected: false)
        )
        session.screen.fields.append(TerminalField(
            start: 17 * 80 + 12,
            length: 24,
            isProtected: false
        ))
        model.profiles = [profile]
        model.terminalSessions = [session]
        model.selectTerminalSession(session.id)

        XCTAssertTrue(model.bookmarkCurrentTerminalFrame())
        let frame = try XCTUnwrap(model.selectedTerminalEvidenceFrame)
        XCTAssertFalse(frame.visibleText.contains("VISIBLE OPERATOR INPUT"))
        XCTAssertFalse(model.terminalFlightRecorderUsesReplay)

        let draft = TerminalMacroEditorDraft(
            name: "Verify current screen",
            targetProfileID: profile.id,
            steps: [TerminalMacroEditorStepDraft(
                name: "Match redacted baseline",
                kind: .matchFrame,
                frameFingerprint: frame.screenFingerprint
            )]
        )
        XCTAssertTrue(model.saveTerminalMacroDraft(draft))
        XCTAssertFalse(try XCTUnwrap(model.selectedTerminalMacro).isReviewCurrent)
        model.attestSelectedTerminalMacroReview()
        XCTAssertTrue(try XCTUnwrap(model.selectedTerminalMacro).isReviewCurrent)

        model.runSelectedTerminalMacroStep()

        XCTAssertEqual(model.terminalMacroRunState?.nextStepIndex, 1)
        XCTAssertEqual(model.terminalFlightRecorder.receipts.count, 1)
        XCTAssertEqual(model.terminalFlightRecorder.receipts[0].outcome, .passed)
        XCTAssertEqual(try recorderStore.read(), model.terminalFlightRecorder)
    }

    func testRecorderWorkspaceRendersAtNativeWorkbenchSize() throws {
        let base = temporaryDirectory(named: "render")
        defer { try? FileManager.default.removeItem(at: base) }
        let model = AppModel(
            continuityCasebookStore: ContinuityCasebookStore(
                baseDirectoryURL: temporaryDirectory(named: "render-casebook")
            ),
            terminalFlightRecorderStore: TerminalFlightRecorderStore(baseDirectoryURL: base)
        )
        let content = TerminalFlightRecorderView()
            .environment(model)
            .frame(width: 1_360, height: 840)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1_360, height: 840)

        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1_360)
        XCTAssertEqual(image.height, 840)

        if ProcessInfo.processInfo.environment["ITELAS_RENDER_FLIGHT_RECORDER"] == "1" {
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 1_360, height: 840)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/itelas-session-flight-recorder-native.png"),
                options: .atomic
            )
        }
    }

    private func temporaryDirectory(named suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-flight-recorder-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    }
}
