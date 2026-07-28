import Foundation
import XCTest
@testable import iTelAS
@testable import iTelASCore

final class TerminalSessionStateTests: XCTestCase {
    func testSessionStartsWithProfileGeometryAndRetainedLocalEvidence() {
        let openedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = makeProfile(name: "QA Ledger", model: .ibm3477_FC)

        let session = TerminalSessionState(profile: profile, openedAt: openedAt)

        XCTAssertEqual(session.profileID, profile.id)
        XCTAssertEqual(session.openedAt, openedAt)
        XCTAssertEqual(session.lastActivityAt, openedAt)
        XCTAssertEqual(session.screen.rows, 27)
        XCTAssertEqual(session.screen.columns, 132)
        XCTAssertEqual(session.connectionState, .disconnected)
        XCTAssertEqual(session.connectionLabel, "OFFLINE · SCREEN RETAINED")
        XCTAssertFalse(session.isTransportActive)
        XCTAssertEqual(session.screenHistory.count, 1)
        XCTAssertEqual(session.screenHistory[0].source, "QA Ledger · local preview")
    }

    func testTransportActivityAndOperatorLabelsFollowEachLifecyclePhase() {
        var session = TerminalSessionState(profile: makeProfile())

        session.connectionState = .connecting
        XCTAssertTrue(session.isTransportActive)
        XCTAssertEqual(session.connectionLabel, "CONNECTING")

        session.connectionState = .negotiating
        XCTAssertTrue(session.isTransportActive)
        XCTAssertEqual(session.connectionLabel, "NEGOTIATING TN5250")

        session.connectionState = .waiting("Reconnect 2/3 in 2s")
        XCTAssertTrue(session.isTransportActive)
        XCTAssertEqual(session.connectionLabel, "RECONNECT 2/3 IN 2S")

        session.connectionState = .connected
        XCTAssertTrue(session.isTransportActive)
        XCTAssertEqual(session.connectionLabel, "READY")

        session.connectionState = .failed("Socket closed")
        XCTAssertFalse(session.isTransportActive)
        XCTAssertEqual(session.connectionLabel, "FAILED · SCREEN RETAINED")
    }

    func testConcurrentSessionsKeepRecoveryEditingAndHistoryIndependent() {
        let profile = makeProfile()
        var first = TerminalSessionState(profile: profile)
        let second = TerminalSessionState(profile: profile)

        first.connectionState = .waiting("Reconnect 1/3 in 1s")
        first.reconnectAttempt = 1
        first.isInsertMode = true
        first.screenHistory.append(
            TerminalSnapshot(source: "DEV Ledger · host update", screen: first.screen)
        )

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.profileID, second.profileID)
        XCTAssertEqual(first.reconnectAttempt, 1)
        XCTAssertTrue(first.isInsertMode)
        XCTAssertEqual(first.screenHistory.count, 2)
        XCTAssertEqual(second.connectionState, .disconnected)
        XCTAssertEqual(second.reconnectAttempt, 0)
        XCTAssertFalse(second.isInsertMode)
        XCTAssertEqual(second.screenHistory.count, 1)
    }

    func testHostScreenAlarmIsEmittedOnceAndResetsAcrossARecoveredScreen() {
        var session = TerminalSessionState(profile: makeProfile())
        var alarmScreen = session.screen
        alarmScreen.audibleAlarmSequence = 1

        XCTAssertTrue(session.applyHostScreen(alarmScreen))
        XCTAssertFalse(session.applyHostScreen(alarmScreen))

        var recoveredScreen = session.screen
        recoveredScreen.audibleAlarmSequence = 0
        XCTAssertFalse(session.applyHostScreen(recoveredScreen))

        recoveredScreen.audibleAlarmSequence = 1
        XCTAssertTrue(session.applyHostScreen(recoveredScreen))
    }

    @MainActor
    func testDeckSelectionScopesVisibleGeometryEditingAndCloseReplacement() {
        let compactProfile = makeProfile(name: "DEV Ledger", model: .ibm3179_2)
        let wideProfile = makeProfile(name: "QA Ledger", model: .ibm3477_FC)
        let compactSession = TerminalSessionState(profile: compactProfile)
        let wideSession = TerminalSessionState(profile: wideProfile)
        let model = AppModel()
        model.profiles = [compactProfile, wideProfile]
        model.terminalSessions = [compactSession, wideSession]

        model.selectTerminalSession(compactSession.id)
        model.isTerminalInsertMode = true
        XCTAssertEqual(model.selectedProfile?.id, compactProfile.id)
        XCTAssertEqual(model.screen.rows, 24)
        XCTAssertTrue(model.isTerminalInsertMode)

        model.selectTerminalSession(wideSession.id)
        XCTAssertEqual(model.selectedProfile?.id, wideProfile.id)
        XCTAssertEqual(model.screen.columns, 132)
        XCTAssertFalse(model.isTerminalInsertMode)

        model.selectAdjacentTerminalSession(1)
        XCTAssertEqual(model.selectedTerminalSession?.id, compactSession.id)
        model.selectAdjacentTerminalSession(-1)
        XCTAssertEqual(model.selectedTerminalSession?.id, wideSession.id)

        model.closeTerminalSession(wideSession.id, announces: false)
        XCTAssertEqual(model.selectedTerminalSession?.id, compactSession.id)
        XCTAssertEqual(model.selectedProfile?.id, compactProfile.id)
        XCTAssertTrue(model.isTerminalInsertMode)
    }

    @MainActor
    func testAssistPreparationsAccumulateInOneRemovableContextShelf() {
        let model = AppModel()
        model.clearPreparedAssistantContext()

        model.prepareSystemHealthAssist()
        XCTAssertEqual(model.preparedAssistantContextBundle?.fragments.map(\.kind), [.systemHealth])

        model.prepareCompileAssist()
        XCTAssertEqual(
            model.preparedAssistantContextBundle?.fragments.map(\.kind),
            [.systemHealth, .compileEvidence]
        )
        XCTAssertEqual(model.preparedAssistantContextLabel, "Context Shelf · 2 pinned sources")

        model.removePreparedAssistantContext(.systemHealth)
        XCTAssertEqual(model.preparedAssistantContextBundle?.fragments.map(\.kind), [.compileEvidence])
        XCTAssertEqual(model.preparedAssistantContextLabel, "Context Shelf · 1 pinned source")

        model.clearPreparedAssistantContext()
        XCTAssertNil(model.preparedAssistantContextBundle)
        XCTAssertNil(model.latestAIContextReceipt)
    }

    @MainActor
    func testAutomaticScreenContextCannotSilentlyOverflowAFullShelf() throws {
        let model = AppModel()
        let kinds: [AIContextKind] = [
            .sourceDraft, .sqlDraft, .compileEvidence, .jobIncident,
            .spoolOutput, .dataTransfer, .systemHealth, .objectImpact
        ]
        let fragments = try kinds.map { kind in
            try AIContextFragment(
                kind: kind,
                documentName: "\(kind.rawValue).txt",
                language: "IBM i evidence",
                sourceText: "bounded \(kind.rawValue) evidence"
            )
        }
        model.preparedAssistantContextBundle = try AIContextBundle(fragments: fragments)
        model.aiConfiguration.contextMode = .visibleScreen

        model.updateAutomaticScreenContext(true)

        XCTAssertFalse(model.includeScreenContext)
        XCTAssertEqual(model.currentAssistantContextBundle?.fragments.count, 8)
        XCTAssertTrue(model.assistantError?.contains("at most 8 context items") == true)
    }

    private func makeProfile(
        name: String = "DEV Ledger",
        model: TerminalModel = .ibm3179_2
    ) -> SessionProfile {
        SessionProfile(
            name: name,
            host: "dev.example.invalid",
            terminalModel: model,
            environment: .development
        )
    }
}
