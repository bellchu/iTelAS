import Foundation

public struct TelnetEnvironment: Equatable, Sendable {
    public var terminalType: String
    public var deviceName: String
    public var deviceNameCandidates: [String]
    public var keyboardType: String
    public var codePage: String
    public var characterSet: String
    public var requestStartupRecord: Bool
    public var maximumGeneratedDeviceNameRetries: Int

    public init(
        terminalType: String = "IBM-3179-2",
        deviceName: String = "",
        deviceNameCandidates: [String] = [],
        keyboardType: String = "USB",
        codePage: String = "",
        characterSet: String = "",
        requestStartupRecord: Bool = true,
        maximumGeneratedDeviceNameRetries: Int = 8
    ) {
        self.terminalType = terminalType
        self.deviceName = deviceName
        self.deviceNameCandidates = deviceNameCandidates
        self.keyboardType = keyboardType
        self.codePage = codePage
        self.characterSet = characterSet
        self.requestStartupRecord = requestStartupRecord
        self.maximumGeneratedDeviceNameRetries = max(0, maximumGeneratedDeviceNameRetries)
    }
}

public enum TelnetNegotiationEvent: Equatable, Sendable {
    case terminalTypeSent(String)
    case environmentSent([String])
    case deviceNameRetried(previous: String, next: String, attempt: Int)
    case deviceNameRetryExhausted(String)
    case transparentModeReady
}

public struct TelnetNegotiationSnapshot: Equatable, Sendable {
    public let localOptions: Set<UInt8>
    public let remoteOptions: Set<UInt8>
    public let terminalTypeWasSent: Bool
    public let environmentWasSent: Bool

    public var isTransparentModeReady: Bool {
        let required: Set<UInt8> = [TelnetNegotiator.Option.binary, TelnetNegotiator.Option.endOfRecord]
        let enhancedEnvironmentReady = !localOptions.contains(TelnetNegotiator.Option.newEnvironment) || environmentWasSent
        return required.isSubset(of: localOptions)
            && required.isSubset(of: remoteOptions)
            && terminalTypeWasSent
            && enhancedEnvironmentReady
    }
}

public struct TelnetProcessingResult: Equatable, Sendable {
    public var records: [Data] = []
    public var responses: [Data] = []
    public var events: [TelnetNegotiationEvent] = []

    public init(
        records: [Data] = [],
        responses: [Data] = [],
        events: [TelnetNegotiationEvent] = []
    ) {
        self.records = records
        self.responses = responses
        self.events = events
    }
}

public struct TelnetNegotiator: Sendable {
    public enum Byte {
        public static let iac: UInt8 = 0xFF
        public static let dont: UInt8 = 0xFE
        public static let `do`: UInt8 = 0xFD
        public static let wont: UInt8 = 0xFC
        public static let will: UInt8 = 0xFB
        public static let subnegotiation: UInt8 = 0xFA
        public static let endOfRecord: UInt8 = 0xEF
        public static let subnegotiationEnd: UInt8 = 0xF0
    }

    public enum Option {
        public static let binary: UInt8 = 0
        public static let suppressGoAhead: UInt8 = 3
        public static let terminalType: UInt8 = 24
        public static let endOfRecord: UInt8 = 25
        public static let newEnvironment: UInt8 = 39
    }

    private enum EnvironmentMarker {
        static let variable: UInt8 = 0
        static let value: UInt8 = 1
        static let escape: UInt8 = 2
        static let userVariable: UInt8 = 3
    }

    private struct EnvironmentRequest: Equatable, Sendable {
        let marker: UInt8
        let name: String
    }

    private enum State: Sendable {
        case data
        case iac
        case command(UInt8)
        case subOption
        case subnegotiation(option: UInt8, payload: [UInt8])
        case subnegotiationIAC(option: UInt8, payload: [UInt8])
    }

    private var state: State = .data
    private var record: [UInt8] = []
    private var localOptions: Set<UInt8> = []
    private var remoteOptions: Set<UInt8> = []
    private var terminalTypeWasSent = false
    private var environmentWasSent = false
    private var announcedTransparentModeReady = false
    private var currentDeviceName: String
    private var hasSentDeviceName = false
    private var deviceNameRetryCount = 0
    public var environment: TelnetEnvironment

    public var snapshot: TelnetNegotiationSnapshot {
        TelnetNegotiationSnapshot(
            localOptions: localOptions,
            remoteOptions: remoteOptions,
            terminalTypeWasSent: terminalTypeWasSent,
            environmentWasSent: environmentWasSent
        )
    }

    public init(environment: TelnetEnvironment = .init()) {
        self.environment = environment
        currentDeviceName = Self.normalizedDeviceName(environment.deviceName)
    }

    public mutating func process(_ data: Data) -> TelnetProcessingResult {
        var result = TelnetProcessingResult()
        for byte in data {
            switch state {
            case .data:
                if byte == Byte.iac {
                    state = .iac
                } else {
                    record.append(byte)
                }

            case .iac:
                switch byte {
                case Byte.iac:
                    record.append(Byte.iac)
                    state = .data
                case Byte.endOfRecord:
                    if !record.isEmpty {
                        result.records.append(Data(record))
                        record.removeAll(keepingCapacity: true)
                    }
                    state = .data
                case Byte.do, Byte.dont, Byte.will, Byte.wont:
                    state = .command(byte)
                case Byte.subnegotiation:
                    state = .subOption
                default:
                    state = .data
                }

            case .command(let command):
                if let response = negotiationResponse(command: command, option: byte) {
                    result.responses.append(response)
                }
                state = .data

            case .subOption:
                state = .subnegotiation(option: byte, payload: [])

            case .subnegotiation(let option, var payload):
                if byte == Byte.iac {
                    state = .subnegotiationIAC(option: option, payload: payload)
                } else {
                    payload.append(byte)
                    state = .subnegotiation(option: option, payload: payload)
                }

            case .subnegotiationIAC(let option, var payload):
                if byte == Byte.iac {
                    payload.append(Byte.iac)
                    state = .subnegotiation(option: option, payload: payload)
                } else if byte == Byte.subnegotiationEnd {
                    let subnegotiation = subnegotiationResponse(option: option, payload: payload)
                    if let response = subnegotiation.response {
                        result.responses.append(response)
                    }
                    result.events.append(contentsOf: subnegotiation.events)
                    state = .data
                } else {
                    state = .data
                }
            }
        }

        if snapshot.isTransparentModeReady, !announcedTransparentModeReady {
            announcedTransparentModeReady = true
            result.events.append(.transparentModeReady)
        }
        return result
    }

    private mutating func negotiationResponse(command: UInt8, option: UInt8) -> Data? {
        switch command {
        case Byte.do:
            let supported = [
                Option.binary,
                Option.suppressGoAhead,
                Option.terminalType,
                Option.endOfRecord,
                Option.newEnvironment
            ].contains(option)
            if supported { localOptions.insert(option) } else { localOptions.remove(option) }
            return Data([Byte.iac, supported ? Byte.will : Byte.wont, option])
        case Byte.will:
            let supported = [Option.binary, Option.suppressGoAhead, Option.endOfRecord].contains(option)
            if supported { remoteOptions.insert(option) } else { remoteOptions.remove(option) }
            return Data([Byte.iac, supported ? Byte.do : Byte.dont, option])
        case Byte.dont:
            localOptions.remove(option)
            return nil
        case Byte.wont:
            remoteOptions.remove(option)
            return nil
        default:
            return nil
        }
    }

    private mutating func subnegotiationResponse(
        option: UInt8,
        payload: [UInt8]
    ) -> (response: Data?, events: [TelnetNegotiationEvent]) {
        let send: UInt8 = 1
        let isValue: UInt8 = 0

        if option == Option.terminalType, payload.first == send {
            let terminal = Array(environment.terminalType.utf8)
            terminalTypeWasSent = true
            return (
                framedSubnegotiation(option: option, payload: [isValue] + terminal),
                [.terminalTypeSent(environment.terminalType)]
            )
        }

        guard option == Option.newEnvironment, payload.first == send else { return (nil, []) }
        let requests = Self.parseEnvironmentRequests(Array(payload.dropFirst()))
        let explicitDeviceRequest = requests.contains {
            $0.marker == EnvironmentMarker.userVariable && $0.name.caseInsensitiveCompare("DEVNAME") == .orderedSame
        }
        var events: [TelnetNegotiationEvent] = []
        if explicitDeviceRequest, hasSentDeviceName, !currentDeviceName.isEmpty {
            let previous = currentDeviceName
            if let retry = nextDeviceName(after: previous) {
                currentDeviceName = retry
                deviceNameRetryCount += 1
                events.append(.deviceNameRetried(previous: previous, next: retry, attempt: deviceNameRetryCount))
            } else {
                events.append(.deviceNameRetryExhausted(previous))
            }
        }

        let variables: [(String, String)] = [
            ("DEVNAME", currentDeviceName),
            ("KBDTYPE", environment.keyboardType.uppercased()),
            ("CODEPAGE", environment.codePage),
            ("CHARSET", environment.characterSet),
            ("IBMSENDCONFREC", environment.requestStartupRecord ? "YES" : "NO")
        ]
        var body: [UInt8] = [isValue]
        var sentNames: [String] = []
        for (name, content) in variables where !content.isEmpty {
            let requested = Self.isRequested(
                marker: EnvironmentMarker.userVariable,
                name: name,
                requests: requests
            ) || (explicitDeviceRequest && name == "IBMSENDCONFREC")
            guard requested else { continue }
            body.append(EnvironmentMarker.userVariable)
            body.append(contentsOf: Self.escapedEnvironmentBytes(Array(name.utf8)))
            body.append(EnvironmentMarker.value)
            body.append(contentsOf: Self.escapedEnvironmentBytes(Array(content.utf8)))
            sentNames.append(name)
            if name == "DEVNAME" { hasSentDeviceName = true }
        }
        environmentWasSent = true
        events.append(.environmentSent(sentNames))
        return (framedSubnegotiation(option: option, payload: body), events)
    }

    private func framedSubnegotiation(option: UInt8, payload: [UInt8]) -> Data {
        var bytes = [Byte.iac, Byte.subnegotiation, option]
        for byte in payload {
            bytes.append(byte)
            if byte == Byte.iac { bytes.append(byte) }
        }
        bytes.append(contentsOf: [Byte.iac, Byte.subnegotiationEnd])
        return Data(bytes)
    }

    private mutating func nextDeviceName(after previous: String) -> String? {
        let candidates = environment.deviceNameCandidates
            .map(Self.normalizedDeviceName)
            .filter { !$0.isEmpty }
        if let currentIndex = candidates.firstIndex(of: previous), currentIndex + 1 < candidates.count {
            return candidates[currentIndex + 1]
        }
        if let nextCandidate = candidates.first(where: { $0 != previous && $0 != currentDeviceName }) {
            return nextCandidate
        }
        guard deviceNameRetryCount < environment.maximumGeneratedDeviceNameRetries else { return nil }
        return Self.incrementingDeviceName(previous)
    }

    private static func parseEnvironmentRequests(_ bytes: [UInt8]) -> [EnvironmentRequest] {
        var requests: [EnvironmentRequest] = []
        var currentMarker: UInt8?
        var name: [UInt8] = []
        var escaping = false

        func appendCurrent() {
            guard let currentMarker else { return }
            requests.append(EnvironmentRequest(marker: currentMarker, name: String(decoding: name, as: UTF8.self)))
        }

        for byte in bytes {
            if escaping {
                name.append(byte)
                escaping = false
            } else if byte == EnvironmentMarker.escape {
                escaping = true
            } else if byte == EnvironmentMarker.variable || byte == EnvironmentMarker.userVariable {
                appendCurrent()
                currentMarker = byte
                name.removeAll(keepingCapacity: true)
            } else if byte == EnvironmentMarker.value {
                appendCurrent()
                currentMarker = nil
                name.removeAll(keepingCapacity: true)
            } else {
                name.append(byte)
            }
        }
        appendCurrent()
        return requests
    }

    private static func isRequested(marker: UInt8, name: String, requests: [EnvironmentRequest]) -> Bool {
        guard !requests.isEmpty else { return true }
        return requests.contains {
            $0.marker == marker && ($0.name.isEmpty || $0.name.caseInsensitiveCompare(name) == .orderedSame)
        }
    }

    private static func escapedEnvironmentBytes(_ bytes: [UInt8]) -> [UInt8] {
        var escaped: [UInt8] = []
        for byte in bytes {
            if [
                EnvironmentMarker.variable,
                EnvironmentMarker.value,
                EnvironmentMarker.escape,
                EnvironmentMarker.userVariable
            ].contains(byte) {
                escaped.append(EnvironmentMarker.escape)
            }
            escaped.append(byte)
        }
        return escaped
    }

    private static func normalizedDeviceName(_ value: String) -> String {
        String(value.uppercased().filter { "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#$@_".contains($0) }.prefix(10))
    }

    private static func incrementingDeviceName(_ value: String) -> String {
        let suffix = value.reversed().prefix(while: \.isNumber)
        let suffixText = String(suffix.reversed())
        let number = (Int(suffixText) ?? 1) + 1
        let width = max(1, suffixText.count)
        let formatted = String(format: "%0*d", width, number)
        let base = suffixText.isEmpty ? value : String(value.dropLast(suffixText.count))
        let maximumBaseLength = max(0, 10 - formatted.count)
        return String(base.prefix(maximumBaseLength)) + formatted
    }
}
