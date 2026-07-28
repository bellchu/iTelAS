import Foundation
import iTelASCore

@MainActor
struct ContinuityCasebookStore {
    let fileURL: URL
    private let fileManager: FileManager
    private let limits: ContinuityCasebookLimits

    init(
        baseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        limits: ContinuityCasebookLimits = .standard
    ) {
        self.fileManager = fileManager
        self.limits = limits
        let base = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("iTelAS", isDirectory: true)
        fileURL = base.appendingPathComponent("continuity-casebook-v1.json", isDirectory: false)
    }

    func read() throws -> ContinuityCasebook? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try validatePrivateDirectory(fileURL.deletingLastPathComponent())
        try validateRegularFile(
            fileURL,
            maximumBytes: limits.maximumCasebookUTF8Bytes,
            requiresPrivatePermissions: true
        )
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let casebook = try decoder.decode(ContinuityCasebook.self, from: data)
        try casebook.validate(limits: limits)
        return casebook
    }

    func write(_ casebook: ContinuityCasebook) throws {
        try casebook.validate(limits: limits)
        let directory = fileURL.deletingLastPathComponent()
        try prepareDirectory(directory)
        if fileManager.fileExists(atPath: fileURL.path) {
            try validateRegularFile(fileURL, maximumBytes: limits.maximumCasebookUTF8Bytes)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(casebook)
        guard data.count <= limits.maximumCasebookUTF8Bytes else {
            throw ContinuityCasebookError.casebookTooLarge(maximum: limits.maximumCasebookUTF8Bytes)
        }
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func readReferencePack(at url: URL) throws -> ContinuityReferencePack {
        try validateRegularFile(url, maximumBytes: limits.maximumReferencePackUTF8Bytes)
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try ContinuityReferencePackCodec().decode(data, limits: limits)
    }

    func snapshotJSON(_ snapshot: ContinuityHandoffSnapshot) throws -> String {
        try snapshot.validate(limits: limits)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        guard data.count <= limits.maximumCasebookUTF8Bytes,
              let text = String(data: data, encoding: .utf8) else {
            throw ContinuityCasebookError.casebookTooLarge(maximum: limits.maximumCasebookUTF8Bytes)
        }
        return text + "\n"
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
            throw CocoaError(.fileReadUnsupportedScheme)
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
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard let size = values.fileSize, size <= maximumBytes else {
            throw ContinuityCasebookError.limitExceeded("file bytes", maximum: maximumBytes)
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
