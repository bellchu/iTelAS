import Foundation

struct LocalTextDocumentStore {
    enum StoreError: LocalizedError {
        case applicationSupportUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable:
                "The local Application Support directory is unavailable."
            }
        }
    }

    private let fileManager: FileManager
    private let fileURL: URL

    init(
        fileName: String,
        subdirectory: String = "Workspace",
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.fileURL = support
                .appendingPathComponent("iTelAS", isDirectory: true)
                .appendingPathComponent(subdirectory, isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false)
        } else {
            self.fileURL = URL(fileURLWithPath: "/dev/null")
        }
    }

    func read() throws -> String? {
        guard fileURL.path != "/dev/null" else { throw StoreError.applicationSupportUnavailable }
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func write(_ text: String) throws {
        guard fileURL.path != "/dev/null" else { throw StoreError.applicationSupportUnavailable }
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try Data(text.utf8).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
