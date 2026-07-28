import Foundation
import iTelASCore

struct TerminalSessionState: Identifiable, Equatable {
    let id: UUID
    let profileID: UUID
    let openedAt: Date
    var lastActivityAt: Date
    var screen: TerminalScreen
    var connectionState: TN5250ConnectionState
    var protocolNotice: String?
    var startupResponse: TN5250StartupResponse?
    var reconnectAttempt: Int
    var isInsertMode: Bool
    var screenHistory: [TerminalSnapshot]

    init(
        id: UUID = UUID(),
        profile: SessionProfile,
        openedAt: Date = Date()
    ) {
        let initialScreen = TerminalScreen.welcome(
            rows: profile.terminalModel.rows,
            columns: profile.terminalModel.columns
        )
        self.id = id
        self.profileID = profile.id
        self.openedAt = openedAt
        self.lastActivityAt = openedAt
        self.screen = initialScreen
        self.connectionState = .disconnected
        self.protocolNotice = "Session opened locally. No host connection has started."
        self.startupResponse = nil
        self.reconnectAttempt = 0
        self.isInsertMode = false
        self.screenHistory = [
            TerminalSnapshot(source: "\(profile.name) · local preview", screen: initialScreen)
        ]
    }

    var isTransportActive: Bool {
        switch connectionState {
        case .connecting, .negotiating, .connected, .waiting:
            true
        case .disconnected, .failed:
            false
        }
    }

    var connectionLabel: String {
        switch connectionState {
        case .disconnected: "OFFLINE · SCREEN RETAINED"
        case .connecting: "CONNECTING"
        case .negotiating: "NEGOTIATING TN5250"
        case .connected:
            if let deviceName = startupResponse?.deviceName, !deviceName.isEmpty {
                "\(deviceName) · READY"
            } else {
                "READY"
            }
        case .waiting(let message): message.uppercased()
        case .failed: "FAILED · SCREEN RETAINED"
        }
    }

    @discardableResult
    mutating func applyHostScreen(_ updatedScreen: TerminalScreen, at receivedAt: Date = Date()) -> Bool {
        let requestedAudibleAlarm = updatedScreen.audibleAlarmSequence > screen.audibleAlarmSequence
        screen = updatedScreen
        lastActivityAt = receivedAt
        return requestedAudibleAlarm
    }
}

@MainActor
final class TerminalSessionTransportRuntime {
    var client: TN5250Client?
    var generation: UUID?
    var reconnectTask: Task<Void, Never>?

    func invalidate() -> TN5250Client? {
        reconnectTask?.cancel()
        reconnectTask = nil
        generation = nil
        let activeClient = client
        client = nil
        return activeClient
    }
}
