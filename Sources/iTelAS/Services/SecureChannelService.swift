import Foundation
import iTelASCore

struct ProviderProcessResult: Sendable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

struct SystemProviderProcessRunner: Sendable {
    private let maximumOutputBytes = 262_144

    func run(_ plan: SystemSSHCommandPlan) async throws -> ProviderProcessResult {
        let maximumOutputBytes = maximumOutputBytes
        return try await Task.detached(priority: .userInitiated) {
            let processBox = SendableProcessBox()
            let process = processBox.process
            let combinedOutput = Pipe()
            process.executableURL = URL(fileURLWithPath: plan.executable)
            process.arguments = plan.arguments
            process.standardOutput = combinedOutput
            process.standardError = combinedOutput

            let standardInput: Pipe?
            if let input = plan.standardInput {
                let pipe = Pipe()
                process.standardInput = pipe
                standardInput = pipe
                try process.run()
                try pipe.fileHandleForWriting.write(contentsOf: input)
                try pipe.fileHandleForWriting.close()
            } else {
                standardInput = nil
                try process.run()
            }

            let timeout = ProcessTimeoutFlag()
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timer.schedule(deadline: .now() + plan.timeoutSeconds)
            timer.setEventHandler {
                timeout.markTimedOut()
                if processBox.process.isRunning { processBox.process.terminate() }
            }
            timer.resume()

            var output = Data()
            while let chunk = try combinedOutput.fileHandleForReading.read(upToCount: 8_192), !chunk.isEmpty {
                guard output.count + chunk.count <= maximumOutputBytes else {
                    if process.isRunning { process.terminate() }
                    process.waitUntilExit()
                    timer.cancel()
                    throw SecureChannelError.outputLimitExceeded
                }
                output.append(chunk)
            }
            process.waitUntilExit()
            timer.cancel()
            if timeout.didTimeOut { throw SecureChannelError.timedOut }
            _ = standardInput
            return ProviderProcessResult(
                terminationStatus: process.terminationStatus,
                standardOutput: output,
                standardError: output
            )
        }.value
    }
}

private final class SendableProcessBox: @unchecked Sendable {
    let process = Process()
}

private final class ProcessTimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var didTimeOut: Bool {
        lock.withLock { value }
    }

    func markTimedOut() {
        lock.withLock { value = true }
    }
}

struct SecureChannelService: Sendable {
    let knownHostsStore: ManagedKnownHostsStore
    private let runner: SystemProviderProcessRunner

    init(
        knownHostsURL: URL = Self.defaultKnownHostsURL,
        runner: SystemProviderProcessRunner = SystemProviderProcessRunner()
    ) {
        knownHostsStore = ManagedKnownHostsStore(fileURL: knownHostsURL)
        self.runner = runner
    }

    static var defaultKnownHostsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iTelAS", isDirectory: true)
            .appendingPathComponent("ssh", isDirectory: true)
            .appendingPathComponent("known_hosts", isDirectory: false)
    }

    func scanHostKey(profile: SecureChannelProfile) async throws -> [SSHHostKey] {
        let plan = try SystemSSHCommandPlan.hostKeyScan(for: profile)
        let result = try await runner.run(plan)
        guard result.terminationStatus == 0 || !result.standardOutput.isEmpty else {
            throw SecureChannelError.processFailed(Self.diagnostic(from: result.standardError, fallback: "Host-key discovery failed."))
        }
        let output = String(decoding: result.standardOutput, as: UTF8.self)
        return try SSHHostKeyScanParser().parse(output, profile: profile)
    }

    func pin(_ key: SSHHostKey) throws {
        try knownHostsStore.pin(key)
    }

    func pinState(for key: SSHHostKey) throws -> SSHHostPinState {
        try knownHostsStore.pinState(for: key)
    }

    func testPinnedChannel(profile: SecureChannelProfile) async throws {
        guard try knownHostsStore.hasPinnedKey(for: profile) else {
            throw SecureChannelError.processFailed("Pin a verified host key before authentication.")
        }

        let ssh = try SystemSSHCommandPlan.authenticationTest(
            for: profile,
            knownHostsFile: knownHostsStore.fileURL.path
        )
        let sshResult = try await runner.run(ssh)
        guard sshResult.terminationStatus == 0 else {
            throw SecureChannelError.processFailed(Self.diagnostic(
                from: sshResult.standardError,
                fallback: "SSH authentication failed. Check the agent, key, user profile, and IBM i SSH service."
            ))
        }

        let sftp = try SystemSSHCommandPlan.sftpSubsystemProbe(
            for: profile,
            knownHostsFile: knownHostsStore.fileURL.path
        )
        let sftpResult = try await runner.run(sftp)
        guard sftpResult.terminationStatus == 0 else {
            throw SecureChannelError.processFailed(Self.diagnostic(
                from: sftpResult.standardError,
                fallback: "SSH succeeded, but the SFTP subsystem was unavailable."
            ))
        }
    }

    private static func diagnostic(from data: Data, fallback: String) -> String {
        let raw = String(decoding: data.prefix(1_024), as: UTF8.self)
        let line = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        return line ?? fallback
    }
}
