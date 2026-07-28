import Foundation

public enum IBMEnvironment: String, Codable, CaseIterable, Sendable {
    case development
    case qualityAssurance
    case staging
    case production

    public var label: String {
        switch self {
        case .development: "DEV"
        case .qualityAssurance: "QA"
        case .staging: "STAGE"
        case .production: "PROD"
        }
    }
}

public enum TransportSecurity: String, Codable, CaseIterable, Sendable {
    case tls
    case telnet

    public var defaultPort: Int {
        switch self {
        case .tls: 992
        case .telnet: 23
        }
    }
}

public enum SessionReconnectPolicy: String, Codable, CaseIterable, Sendable {
    case manual
    case retryThreeTimes

    public var label: String {
        switch self {
        case .manual: "Manual"
        case .retryThreeTimes: "Retry 3 times"
        }
    }

    public var maximumAttempts: Int {
        switch self {
        case .manual: 0
        case .retryThreeTimes: 3
        }
    }

    public func delaySeconds(forAttempt attempt: Int) -> Int? {
        guard attempt > 0, attempt <= maximumAttempts else { return nil }
        return min(1 << (attempt - 1), 4)
    }
}

public enum TerminalModel: String, Codable, CaseIterable, Sendable {
    case ibm3179_2
    case ibm3477_FC

    public var telnetName: String {
        switch self {
        case .ibm3179_2: "IBM-3179-2"
        case .ibm3477_FC: "IBM-3477-FC"
        }
    }

    public var rows: Int {
        switch self {
        case .ibm3179_2: 24
        case .ibm3477_FC: 27
        }
    }

    public var columns: Int {
        switch self {
        case .ibm3179_2: 80
        case .ibm3477_FC: 132
        }
    }

    public var displayName: String {
        "\(telnetName) · \(rows)×\(columns)"
    }
}

/// A profile-scoped physical function-key slot. Slots 1...12 correspond to F1...F12;
/// slots 13...24 correspond to Shift-F1...Shift-F12 on a Mac keyboard.
public struct TerminalFunctionKeyBinding: Codable, Hashable, Sendable, Identifiable {
    public static let slotRange = 1...24
    public static let maximumLabelLength = 32

    public var slot: Int
    public var hostFunction: Int
    public var label: String
    public var isPinned: Bool

    public var id: Int { slot }

    public init(
        slot: Int,
        hostFunction: Int,
        label: String,
        isPinned: Bool
    ) {
        self.slot = slot
        self.hostFunction = hostFunction
        self.label = label
        self.isPinned = isPinned
    }

    public var physicalKeyLabel: String {
        slot <= 12 ? "F\(slot)" : "⇧F\(slot - 12)"
    }

    public var hostActionLabel: String {
        "F\(hostFunction)"
    }

    public var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultLabel(for: hostFunction) : trimmed
    }

    public var isIdentityRoute: Bool {
        slot == hostFunction
    }

    public static func defaultLabel(for function: Int) -> String {
        switch function {
        case 1: "Help"
        case 3: "Exit"
        case 4: "Prompt"
        case 5: "Refresh"
        case 9: "Retrieve"
        case 12: "Cancel"
        default: "Host key"
        }
    }

    public static var standard: [TerminalFunctionKeyBinding] {
        slotRange.map { slot in
            TerminalFunctionKeyBinding(
                slot: slot,
                hostFunction: slot,
                label: defaultLabel(for: slot),
                isPinned: [1, 3, 4, 5, 9, 12].contains(slot)
            )
        }
    }

    public static func validationErrors(for bindings: [TerminalFunctionKeyBinding]) -> [String] {
        var errors: [String] = []
        let slots = bindings.map(\.slot)
        if bindings.count != slotRange.count || Set(slots) != Set(slotRange) {
            errors.append("Function-key layout must contain each F1–F24 slot exactly once.")
        }
        for binding in bindings {
            if !slotRange.contains(binding.hostFunction) {
                errors.append("\(binding.physicalKeyLabel) must route to a host function from F1 through F24.")
            }
            let trimmed = binding.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > maximumLabelLength {
                errors.append("\(binding.physicalKeyLabel) label must be at most \(maximumLabelLength) characters.")
            }
            if binding.label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                errors.append("\(binding.physicalKeyLabel) label cannot contain control characters.")
            }
        }
        return errors
    }
}

public struct SessionProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var security: TransportSecurity
    public var terminalModel: TerminalModel
    public var ccsid: Int
    public var deviceName: String
    public var keyboardType: String
    public var negotiatedCodePage: String
    public var negotiatedCharacterSet: String
    public var environment: IBMEnvironment
    public var reconnectPolicy: SessionReconnectPolicy
    public var functionKeyBindings: [TerminalFunctionKeyBinding]

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 992,
        security: TransportSecurity = .tls,
        terminalModel: TerminalModel = .ibm3179_2,
        ccsid: Int = 37,
        deviceName: String = "",
        keyboardType: String = "USB",
        negotiatedCodePage: String = "",
        negotiatedCharacterSet: String = "",
        environment: IBMEnvironment = .development,
        reconnectPolicy: SessionReconnectPolicy = .retryThreeTimes,
        functionKeyBindings: [TerminalFunctionKeyBinding] = TerminalFunctionKeyBinding.standard
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.security = security
        self.terminalModel = terminalModel
        self.ccsid = ccsid
        self.deviceName = deviceName
        self.keyboardType = keyboardType
        self.negotiatedCodePage = negotiatedCodePage
        self.negotiatedCharacterSet = negotiatedCharacterSet
        self.environment = environment
        self.reconnectPolicy = reconnectPolicy
        self.functionKeyBindings = functionKeyBindings
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Session name is required.")
        }
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Host or IP address is required.")
        }
        if !(1...65_535).contains(port) {
            errors.append("Port must be between 1 and 65535.")
        }
        if !deviceName.isEmpty {
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#$@_")
            if deviceName.count > 10 || deviceName.uppercased().unicodeScalars.contains(where: { !allowed.contains($0) }) {
                errors.append("Device name must be at most 10 IBM i uppercase-name characters.")
            }
        }
        if EBCDICCCSIDCatalog.definition(for: ccsid)?.isAvailable != true {
            errors.append("CCSID \(ccsid) is not available in the native codec.")
        } else if EBCDICCCSIDCatalog.definition(for: ccsid)?.isTerminalReady != true {
            errors.append("CCSID \(ccsid) requires bidirectional 5250 field and cursor behavior that is not yet verified in the native terminal.")
        }
        let keyboardAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        if keyboardType.isEmpty || keyboardType.count > 3 || keyboardType.uppercased().unicodeScalars.contains(where: { !keyboardAllowed.contains($0) }) {
            errors.append("Keyboard type must contain 1 to 3 uppercase letters or digits.")
        }
        for (label, value) in [
            ("Device code page", negotiatedCodePage),
            ("Device character set", negotiatedCharacterSet)
        ] where !value.isEmpty {
            if value.count > 5 || value.contains(where: { !$0.isNumber }) {
                errors.append("\(label) must contain at most 5 digits.")
            }
        }
        errors += TerminalFunctionKeyBinding.validationErrors(for: functionKeyBindings)
        return errors
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case port
        case security
        case terminalModel
        case ccsid
        case deviceName
        case keyboardType
        case negotiatedCodePage
        case negotiatedCharacterSet
        case environment
        case reconnectPolicy
        case functionKeyBindings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 992
        security = try container.decodeIfPresent(TransportSecurity.self, forKey: .security) ?? .tls
        terminalModel = try container.decodeIfPresent(TerminalModel.self, forKey: .terminalModel) ?? .ibm3179_2
        ccsid = try container.decodeIfPresent(Int.self, forKey: .ccsid) ?? 37
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        keyboardType = try container.decodeIfPresent(String.self, forKey: .keyboardType) ?? "USB"
        negotiatedCodePage = try container.decodeIfPresent(String.self, forKey: .negotiatedCodePage) ?? ""
        negotiatedCharacterSet = try container.decodeIfPresent(String.self, forKey: .negotiatedCharacterSet) ?? ""
        environment = try container.decodeIfPresent(IBMEnvironment.self, forKey: .environment) ?? .development
        reconnectPolicy = try container.decodeIfPresent(SessionReconnectPolicy.self, forKey: .reconnectPolicy) ?? .retryThreeTimes
        functionKeyBindings = (try? container.decode([TerminalFunctionKeyBinding].self, forKey: .functionKeyBindings))
            ?? TerminalFunctionKeyBinding.standard
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(security, forKey: .security)
        try container.encode(terminalModel, forKey: .terminalModel)
        try container.encode(ccsid, forKey: .ccsid)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(keyboardType, forKey: .keyboardType)
        try container.encode(negotiatedCodePage, forKey: .negotiatedCodePage)
        try container.encode(negotiatedCharacterSet, forKey: .negotiatedCharacterSet)
        try container.encode(environment, forKey: .environment)
        try container.encode(reconnectPolicy, forKey: .reconnectPolicy)
        try container.encode(functionKeyBindings, forKey: .functionKeyBindings)
    }
}
