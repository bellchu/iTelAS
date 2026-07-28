import Foundation

public struct AIContextRedactor: Sendable {
    private static let sensitiveMarkers = [
        "PASSWORD", "PASSWD", "PWD", "API KEY", "API_KEY", "TOKEN", "SECRET", "IBMSUBSPW"
    ]

    public init() {}

    public func redact(screen: TerminalScreen) -> String {
        redact(text: screen.visibleText(redactingSensitive: true))
    }

    public func redact(text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine in
            let line = String(rawLine)
            let upper = line.uppercased()
            guard Self.sensitiveMarkers.contains(where: upper.contains) else { return line }

            if let separator = line.firstIndex(where: { $0 == ":" || $0 == ">" || $0 == "=" }) {
                return String(line[...separator]) + " [REDACTED]"
            }
            return "[REDACTED SENSITIVE LINE]"
        }.joined(separator: "\n")
    }
}

public enum CommandRisk: String, Codable, Sendable {
    case readOnly
    case mutating
    case destructive
    case unknown

    public var requiresExplicitConfirmation: Bool {
        self != .readOnly
    }
}

public struct IBMCommandSafetyClassifier: Sendable {
    public init() {}

    public func classify(_ command: String) -> CommandRisk {
        let normalized = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let verb = normalized.split(whereSeparator: { $0.isWhitespace || $0 == ";" }).first.map(String.init) ?? ""

        if ["DLT", "DLTF", "DLTLIB", "DLTOBJ", "CLRPFM", "CLROUTQ", "ENDJOB", "ENDSBS", "PWRDWNSYS"].contains(where: verb.hasPrefix) {
            return .destructive
        }
        if ["CHG", "CRT", "ADD", "RMV", "CPY", "MOV", "RST", "SBM", "CALL", "RUNSQLSTM", "GRTOBJAUT", "RVKOBJAUT"].contains(where: verb.hasPrefix) {
            return .mutating
        }
        if ["DSP", "WRK", "PRT", "CHK", "PING", "SELECT", "VALUES", "WITH", "EXPLAIN"].contains(where: verb.hasPrefix) {
            return .readOnly
        }
        return .unknown
    }
}
