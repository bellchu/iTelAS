import iTelASCore

extension SessionProfile {
    var workspaceSummary: String {
        let transport = security == .tls ? "TLS" : "TELNET"
        return "\(transport) · \(terminalModel.rows)×\(terminalModel.columns)"
    }

    var deletionConfirmationMessage: String {
        "This removes the saved session from iTelAS. It does not change the IBM i system."
    }
}
