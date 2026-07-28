import Foundation
import XCTest
@testable import iTelASCore

final class PUB400IntegrationTests: XCTestCase {
    func testPUB400TLSNegotiationReachesSignOnScreen() async throws {
        guard let emailPath = ProcessInfo.processInfo.environment["ITELAS_PUB400_EML"] else {
            throw XCTSkip("Set ITELAS_PUB400_EML to run the opt-in PUB400 compatibility probe.")
        }
        let email = try String(contentsOfFile: emailPath, encoding: .ascii)
        let host = try PUB400EmailConfiguration.host(from: email)
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(7)
        let profile = SessionProfile(
            name: "PUB400 compatibility probe",
            host: host,
            port: 992,
            security: .tls,
            terminalModel: .ibm3179_2,
            ccsid: 37,
            deviceName: "ITL\(suffix)",
            environment: .development
        )

        let (events, continuation) = AsyncStream<TN5250ClientEvent>.makeStream()
        let client = try TN5250Client(profile: profile) { event in
            continuation.yield(event)
        }
        defer {
            client.disconnect()
            continuation.finish()
        }
        client.connect()

        let outcome = try await withThrowingTaskGroup(of: PUB400ProbeOutcome.self) { group in
            group.addTask {
                var startupCode: String?
                var sentTerminalType = false
                var sentEnvironment = false
                var transparentModeReady = false
                for await event in events {
                    switch event {
                    case .startupResponse(let response):
                        startupCode = response.responseCode
                        if response.disposition == .failure {
                            return .failed("Startup response \(response.responseCode): \(response.message)")
                        }
                    case .screen(let screen):
                        let visible = screen.visibleText().uppercased()
                        let editableFields = screen.fields.filter { !$0.isProtected }
                        if visible.contains("SIGN ON") || editableFields.count >= 2 {
                            let cursorPosition = screen.cursor.row * screen.columns + screen.cursor.column
                            return .signOnScreen(
                                startupCode: startupCode,
                                editableFields: editableFields.count,
                                cursorInEditableField: editableFields.contains { $0.contains(cursorPosition) },
                                sentTerminalType: sentTerminalType,
                                sentEnvironment: sentEnvironment,
                                transparentModeReady: transparentModeReady
                            )
                        }
                    case .negotiation(.terminalTypeSent):
                        sentTerminalType = true
                    case .negotiation(.environmentSent):
                        sentEnvironment = true
                    case .negotiation(.transparentModeReady):
                        transparentModeReady = true
                    case .negotiation:
                        continue
                    case .state(.failed(let message)):
                        return .failed(message)
                    case .state, .protocolNotice:
                        continue
                    }
                }
                return .failed("The PUB400 event stream ended before a sign-on screen arrived.")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(25))
                return .timedOut
            }
            let first = try await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }

        switch outcome {
        case .signOnScreen(
            let startupCode,
            let editableFields,
            let cursorInEditableField,
            let sentTerminalType,
            let sentEnvironment,
            let transparentModeReady
        ):
            XCTAssertGreaterThanOrEqual(editableFields, 2)
            XCTAssertTrue(cursorInEditableField)
            XCTAssertTrue(sentTerminalType)
            XCTAssertTrue(sentEnvironment)
            XCTAssertTrue(transparentModeReady)
            XCTAssertNotNil(startupCode)
            XCTAssertTrue(["I901", "I902", "I906"].contains(startupCode ?? ""))
        case .failed(let message):
            XCTFail("PUB400 compatibility probe failed: \(message)")
        case .timedOut:
            XCTFail("PUB400 did not reach a parsed sign-on screen within 25 seconds.")
        }
    }
}

private enum PUB400ProbeOutcome: Sendable {
    case signOnScreen(
        startupCode: String?,
        editableFields: Int,
        cursorInEditableField: Bool,
        sentTerminalType: Bool,
        sentEnvironment: Bool,
        transparentModeReady: Bool
    )
    case failed(String)
    case timedOut
}

private enum PUB400EmailConfiguration {
    enum Error: Swift.Error, LocalizedError {
        case hostNotFound

        var errorDescription: String? {
            "The supplied PUB400 email does not contain a recognizable PUB400 host."
        }
    }

    static func host(from email: String) throws -> String {
        let expression = try NSRegularExpression(
            pattern: #"(?i)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+pub400\.com|pub400\.com"#
        )
        let range = NSRange(email.startIndex..<email.endIndex, in: email)
        guard let match = expression.firstMatch(in: email, range: range),
              let matchRange = Range(match.range, in: email) else {
            throw Error.hostNotFound
        }
        return String(email[matchRange]).lowercased()
    }
}
