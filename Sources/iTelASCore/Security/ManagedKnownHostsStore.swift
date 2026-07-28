import Foundation

public enum SSHHostPinState: Equatable, Sendable {
    case unpinned
    case pinned
    case changed
}

public struct ManagedKnownHostsStore: Sendable {
    public let fileURL: URL
    private let maximumBytes: Int

    public init(fileURL: URL, maximumBytes: Int = 1_048_576) {
        self.fileURL = fileURL
        self.maximumBytes = maximumBytes
    }

    public func pinState(for key: SSHHostKey) throws -> SSHHostPinState {
        let entries = try readEntries()
        if entries.contains(key.knownHostsEntry) { return .pinned }
        let prefix = "\(key.knownHostsToken) \(key.algorithm) "
        return entries.contains(where: { $0.hasPrefix(prefix) }) ? .changed : .unpinned
    }

    public func hasPinnedKey(for profile: SecureChannelProfile) throws -> Bool {
        let prefix = "\(profile.knownHostsToken) "
        return try readEntries().contains(where: { $0.hasPrefix(prefix) })
    }

    public func pin(_ key: SSHHostKey) throws {
        let state = try pinState(for: key)
        if state == .pinned { return }
        guard state != .changed else { throw SecureChannelError.hostKeyChanged }

        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try rejectSymbolicLink(at: directory, fileManager: fileManager)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try rejectSymbolicLink(at: fileURL, fileManager: fileManager)

        var entries = try readEntries()
        entries.append(key.knownHostsEntry)
        let payload = Data((entries.joined(separator: "\n") + "\n").utf8)
        guard payload.count <= maximumBytes else { throw SecureChannelError.outputLimitExceeded }
        try payload.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func readEntries() throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        try rejectSymbolicLink(at: fileURL, fileManager: fileManager)
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > maximumBytes {
            throw SecureChannelError.outputLimitExceeded
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw SecureChannelError.outputLimitExceeded
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func rejectSymbolicLink(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw SecureChannelError.invalidKnownHostsPath
        }
    }
}
