import Foundation
import iTelASCore

@MainActor
struct TerminalFlightRecorderStore {
    let fileURL: URL
    private let fileManager: FileManager
    private let limits: TerminalFlightRecorderLimits

    init(
        baseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        limits: TerminalFlightRecorderLimits = .standard
    ) {
        self.fileManager = fileManager
        self.limits = limits
        let base = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("iTelAS", isDirectory: true)
        fileURL = base.appendingPathComponent("terminal-flight-recorder-v1.json", isDirectory: false)
    }

    func read() throws -> TerminalFlightRecorderArchive? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try validatePrivateDirectory(fileURL.deletingLastPathComponent())
        try validateRegularFile(
            fileURL,
            maximumBytes: limits.maximumArchiveUTF8Bytes,
            requiresPrivatePermissions: true
        )
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(TerminalFlightRecorderArchive.self, from: data)
        try archive.validate(limits: limits)
        return archive
    }

    func write(_ archive: TerminalFlightRecorderArchive) throws {
        try archive.validate(limits: limits)
        let directory = fileURL.deletingLastPathComponent()
        try prepareDirectory(directory)
        if fileManager.fileExists(atPath: fileURL.path) {
            try validateRegularFile(fileURL, maximumBytes: limits.maximumArchiveUTF8Bytes)
        }
        let data = try encodedData(archive, prettyPrinted: false)
        guard data.count <= limits.maximumArchiveUTF8Bytes else {
            throw TerminalFlightRecorderError.archiveTooLarge(maximum: limits.maximumArchiveUTF8Bytes)
        }
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func exportJSON(_ archive: TerminalFlightRecorderArchive) throws -> String {
        try archive.validate(limits: limits)
        let data = try encodedData(archive, prettyPrinted: true)
        guard data.count <= limits.maximumArchiveUTF8Bytes,
              let text = String(data: data, encoding: .utf8) else {
            throw TerminalFlightRecorderError.archiveTooLarge(maximum: limits.maximumArchiveUTF8Bytes)
        }
        return text + "\n"
    }

    private func encodedData(
        _ archive: TerminalFlightRecorderArchive,
        prettyPrinted: Bool
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(archive)
    }

    private func prepareDirectory(_ directory: URL) throws {
        if fileManager.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func validatePrivateDirectory(_ directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let attributes = try fileManager.attributesOfItem(atPath: directory.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0 else {
            throw CocoaError(.fileReadNoPermission)
        }
    }

    private func validateRegularFile(
        _ url: URL,
        maximumBytes: Int,
        requiresPrivatePermissions: Bool = false
    ) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize <= maximumBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if requiresPrivatePermissions {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let permissions = attributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o077 == 0 else {
                throw CocoaError(.fileReadNoPermission)
            }
        }
    }
}
