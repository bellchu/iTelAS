import Foundation
import iTelASCore

@MainActor
struct CompileRecipeStore {
    let fileURL: URL
    private let fileManager: FileManager
    private let limits: CompileRecipeLimits

    init(
        baseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        limits: CompileRecipeLimits = .standard
    ) {
        self.fileManager = fileManager
        self.limits = limits
        let base = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("iTelAS", isDirectory: true)
        fileURL = base.appendingPathComponent("compile-recipes-v1.json", isDirectory: false)
    }

    func read() throws -> CompileRecipeLibrary? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try validatePrivateDirectory(fileURL.deletingLastPathComponent())
        try validateRegularFile(fileURL, requiresPrivatePermissions: true)
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard data.count <= limits.maximumLibraryUTF8Bytes else {
            throw CompileRecipeError.libraryTooLarge(maximum: limits.maximumLibraryUTF8Bytes)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let library = try decoder.decode(CompileRecipeLibrary.self, from: data)
        try library.validate(limits: limits)
        return library
    }

    func write(_ library: CompileRecipeLibrary) throws {
        try library.validate(limits: limits)
        let directory = fileURL.deletingLastPathComponent()
        try prepareDirectory(directory)
        if fileManager.fileExists(atPath: fileURL.path) {
            try validateRegularFile(fileURL, requiresPrivatePermissions: false)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(library)
        guard data.count <= limits.maximumLibraryUTF8Bytes else {
            throw CompileRecipeError.libraryTooLarge(maximum: limits.maximumLibraryUTF8Bytes)
        }
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
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
        requiresPrivatePermissions: Bool
    ) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size <= limits.maximumLibraryUTF8Bytes else {
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
