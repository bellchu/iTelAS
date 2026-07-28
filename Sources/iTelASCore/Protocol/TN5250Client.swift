import Foundation
import Network

public enum TN5250ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case negotiating
    case connected
    case waiting(String)
    case failed(String)
}

public enum TN5250ClientEvent: Sendable {
    case state(TN5250ConnectionState)
    case screen(TerminalScreen)
    case negotiation(TelnetNegotiationEvent)
    case startupResponse(TN5250StartupResponse)
    case protocolNotice(String)
}

public final class TN5250Client: @unchecked Sendable {
    public typealias EventHandler = @Sendable (TN5250ClientEvent) -> Void

    private let profile: SessionProfile
    private let queue: DispatchQueue
    private var connection: NWConnection?
    private var negotiator: TelnetNegotiator
    private var parser: TN5250DataStreamParser
    private var screen: TerminalScreen
    private var eventHandler: EventHandler?

    public init(profile: SessionProfile, eventHandler: EventHandler? = nil) throws {
        self.profile = profile
        self.eventHandler = eventHandler
        self.queue = DispatchQueue(label: "io.situ.iTelAS.tn5250.\(profile.id.uuidString)")
        self.negotiator = TelnetNegotiator(environment: TelnetEnvironment(
            terminalType: profile.terminalModel.telnetName,
            deviceName: profile.deviceName,
            keyboardType: profile.keyboardType,
            codePage: profile.negotiatedCodePage,
            characterSet: profile.negotiatedCharacterSet,
            requestStartupRecord: true
        ))
        self.parser = try TN5250DataStreamParser(ccsid: profile.ccsid)
        self.screen = TerminalScreen(rows: profile.terminalModel.rows, columns: profile.terminalModel.columns)
    }

    public func setEventHandler(_ handler: EventHandler?) {
        queue.async { [weak self] in self?.eventHandler = handler }
    }

    public func connect() {
        queue.async { [weak self] in self?.startConnection() }
    }

    public func disconnect() {
        queue.async {
            self.connection?.cancel()
            self.connection = nil
            self.emit(.state(.disconnected))
        }
    }

    public func sendAID(_ aid: UInt8, screen editedScreen: TerminalScreen) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                // Keep locally edited cells and MDTs as the base for any
                // partial host update that follows the AID response.
                self.screen = editedScreen
                let payload = try TN5250InputEncoder.payload(
                    aid: aid,
                    screen: editedScreen,
                    ccsid: self.profile.ccsid
                )
                self.send(TN5250Record(opcode: .putGet, payload: payload).telnetFramed())
            } catch {
                // Nothing reached the host, so restore local input instead of
                // leaving the workstation inhibited after a fail-closed check.
                self.screen.inputInhibited = false
                self.emit(.screen(self.screen))
                self.emit(.protocolNotice("Input was not sent: \(error.localizedDescription)"))
            }
        }
    }

    private func startConnection() {
        guard connection == nil else { return }
        emit(.state(.connecting))

        let parameters: NWParameters
        switch profile.security {
        case .tls:
            parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        case .telnet:
            parameters = .tcp
        }
        parameters.allowLocalEndpointReuse = true
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(profile.port)) else {
            emit(.state(.failed("Port must be between 1 and 65535.")))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(profile.host), port: endpointPort, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                switch state {
                case .setup:
                    break
                case .preparing:
                    self.emit(.state(.negotiating))
                case .ready:
                    self.emit(.state(.negotiating))
                    self.receiveNext()
                case .waiting(let error):
                    self.emit(.state(.waiting(error.localizedDescription)))
                case .failed(let error):
                    self.emit(.state(.failed(Self.describe(error))))
                    self.connection = nil
                case .cancelled:
                    self.emit(.state(.disconnected))
                    self.connection = nil
                @unknown default:
                    self.emit(.state(.failed("Unknown Network.framework connection state.")))
                }
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let data, !data.isEmpty {
                    let result = self.negotiator.process(data)
                    result.responses.forEach(self.send)
                    for event in result.events {
                        self.emit(.negotiation(event))
                        if event == .transparentModeReady {
                            self.emit(.state(.connected))
                        }
                    }
                    for rawRecord in result.records {
                        self.consume(rawRecord)
                    }
                }
                if let error {
                    self.emit(.state(.failed(Self.describe(error))))
                    self.connection?.cancel()
                    return
                }
                if isComplete {
                    self.connection?.cancel()
                    return
                }
                self.receiveNext()
            }
        }
    }

    private func consume(_ data: Data) {
        do {
            let record = try TN5250Record(data: data)
            if record.isStartupResponse {
                let response = try TN5250StartupResponse(record: record)
                emit(.startupResponse(response))
                switch response.disposition {
                case .success, .warning:
                    emit(.state(.connected))
                case .retryableDeviceName:
                    emit(.state(.waiting("\(response.message) Waiting for IBM i to request another device name.")))
                case .failure:
                    emit(.state(.failed("\(response.message) [\(response.responseCode)]")))
                }
                return
            }
            if TN5250DeviceQuery.matches(record.payload) {
                let capabilities = TN5250DeviceCapabilities(terminalModel: profile.terminalModel)
                send(TN5250DeviceQuery.reply(for: capabilities).telnetFramed())
                emit(.protocolNotice(capabilities.summary))
            }
            if record.opcode == .cancelInvite {
                send(TN5250Record(opcode: .cancelInvite).telnetFramed())
                emit(.protocolNotice("IBM i reversed the data-flow direction; local input is paused."))
            }
            parser.apply(record, to: &screen)
            emit(.screen(screen))
        } catch {
            emit(.protocolNotice(error.localizedDescription))
        }
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.emit(.state(.failed(Self.describe(error))))
            }
        })
    }

    private func emit(_ event: TN5250ClientEvent) {
        eventHandler?(event)
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            "Network error \(code.rawValue): \(String(cString: strerror(code.rawValue)))."
        case .dns(let code):
            "DNS error \(code): verify the IBM i hostname and network path."
        case .tls(let code):
            "TLS error \(code): verify the port, certificate chain, and system clock."
        default:
            error.localizedDescription
        }
    }

}
