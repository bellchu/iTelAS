import Foundation

struct HostDiagnosticCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let command: String

    init(title: String, detail: String, command: String) {
        self.id = command
        self.title = title
        self.detail = detail
        self.command = command
    }

    static let library: [HostDiagnosticCommand] = [
        .init(
            title: "Active jobs",
            detail: "CPU, status, and current function",
            command: "WRKACTJOB"
        ),
        .init(
            title: "Workstation messages",
            detail: "Messages affecting this display session",
            command: "DSPMSG MSGQ(*WRKSTN)"
        ),
        .init(
            title: "Current user output",
            detail: "Spooled files owned by the current user",
            command: "WRKSPLF SELECT(*CURRENT)"
        ),
        .init(
            title: "System status",
            detail: "CPU, jobs, storage, and pool activity",
            command: "WRKSYSSTS"
        )
    ]
}

enum HostCommandStagingStatus: Equatable {
    case ready(field: Int, total: Int)
    case disconnected
    case keyboardInhibited
    case noCurrentField
    case nonDisplayField
    case notCommandEntry
    case commandTooLong(capacity: Int)
    case notReadOnly

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .ready(let field, let total):
            "Ready to replace visible field \(field)/\(total); Enter remains manual."
        case .disconnected:
            "Connect a 5250 session, then open a host command-entry screen."
        case .keyboardInhibited:
            "IBM i owns the keyboard; wait for the next host screen."
        case .noCurrentField:
            "Move the terminal cursor into the command input field."
        case .nonDisplayField:
            "Staging is blocked in password and other non-display fields."
        case .notCommandEntry:
            "Open IBM i Main Menu or another recognized command-entry screen."
        case .commandTooLong(let capacity):
            "The current field holds \(capacity) characters; choose a shorter command."
        case .notReadOnly:
            "Only commands classified as read-only can use the staging deck."
        }
    }
}
