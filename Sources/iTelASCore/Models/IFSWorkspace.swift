import CryptoKit
import Foundation

public struct IFSPath: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ rawValue: String) throws {
        guard rawValue.hasPrefix("/") else { throw IFSWorkspaceError.pathMustBeAbsolute }
        guard !rawValue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw IFSWorkspaceError.invalidPath
        }

        let rawComponents = rawValue.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for component in rawComponents {
            try Self.validate(component: component)
        }

        let normalized = rawComponents.isEmpty ? "/" : "/" + rawComponents.joined(separator: "/")
        guard normalized.lengthOfBytes(using: .utf8) <= 4_096 else {
            throw IFSWorkspaceError.pathTooLong
        }
        value = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        do {
            try self.init(rawValue)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
    public var isRoot: Bool { value == "/" }

    public var name: String {
        isRoot ? "/" : String(value.split(separator: "/").last ?? "")
    }

    public var parent: IFSPath? {
        guard !isRoot else { return nil }
        let components = value.split(separator: "/").dropLast()
        return try? IFSPath(components.isEmpty ? "/" : "/" + components.joined(separator: "/"))
    }

    public func appending(_ component: String) throws -> IFSPath {
        try Self.validate(component: component)
        return try IFSPath(isRoot ? "/\(component)" : "\(value)/\(component)")
    }

    private static func validate(component: String) throws {
        guard !component.isEmpty,
              component != ".",
              component != "..",
              !component.contains("/"),
              !component.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              component.lengthOfBytes(using: .utf8) <= 255 else {
            throw IFSWorkspaceError.invalidPathComponent(component)
        }
    }
}

public enum IFSResourceKind: String, Codable, Sendable {
    case file
    case directory
    case symbolicLink
    case other
}

public struct IFSResourceMetadata: Hashable, Codable, Sendable {
    public let path: IFSPath
    public let kind: IFSResourceKind
    public let permissions: String
    public let owner: String
    public let group: String
    public let byteCount: Int64
    public let modifiedDescription: String

    public init(
        path: IFSPath,
        kind: IFSResourceKind,
        permissions: String,
        owner: String,
        group: String,
        byteCount: Int64,
        modifiedDescription: String
    ) {
        self.path = path
        self.kind = kind
        self.permissions = permissions
        self.owner = owner
        self.group = group
        self.byteCount = byteCount
        self.modifiedDescription = modifiedDescription
    }
}

public struct IFSDirectoryEntry: Hashable, Codable, Sendable, Identifiable {
    public let metadata: IFSResourceMetadata

    public init(metadata: IFSResourceMetadata) {
        self.metadata = metadata
    }

    public var id: IFSPath { metadata.path }
    public var name: String { metadata.path.name }
    public var kind: IFSResourceKind { metadata.kind }
}

public struct IFSDirectorySnapshot: Equatable, Sendable {
    public let directory: IFSPath
    public let entries: [IFSDirectoryEntry]

    public init(directory: IFSPath, entries: [IFSDirectoryEntry]) {
        self.directory = directory
        self.entries = entries
    }
}

public protocol IFSProvider: Sendable {
    func listDirectory(profile: SecureChannelProfile, path: IFSPath) async throws -> IFSDirectorySnapshot
    func readFile(profile: SecureChannelProfile, metadata: IFSResourceMetadata) async throws -> IFSDecodedDocument
    func writeFile(
        profile: SecureChannelProfile,
        document: SourceDocument,
        metadata: IFSResourceMetadata,
        plan: IFSWritePlan
    ) async throws -> IFSWriteReceipt
}

public struct IFSRemoteRevision: Hashable, Codable, Sendable {
    public let sha256: String
    public let byteCount: Int

    public init(data: Data) {
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        byteCount = data.count
    }

    public init(token: String) throws {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "sha256",
              parts[1].count == 64,
              parts[1].allSatisfy({ $0.isHexDigit }),
              let byteCount = Int(parts[2]),
              byteCount >= 0 else {
            throw IFSWorkspaceError.invalidRevision
        }
        sha256 = String(parts[1]).lowercased()
        self.byteCount = byteCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let token = try container.decode(String.self)
        do {
            try self.init(token: token)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }

    public var token: String { "sha256:\(sha256):\(byteCount)" }
    public var shortFingerprint: String { "\(sha256.prefix(8)).…\(sha256.suffix(4))".uppercased() }
}

public struct IFSDecodedDocument: Equatable, Sendable {
    public let document: SourceDocument
    public let revision: IFSRemoteRevision
    public let metadata: IFSResourceMetadata

    public init(document: SourceDocument, revision: IFSRemoteRevision, metadata: IFSResourceMetadata) {
        self.document = document
        self.revision = revision
        self.metadata = metadata
    }
}

public struct IFSUTF8DocumentCodec: Sendable {
    public static let maximumEditableBytes = 2_097_152

    public init() {}

    public func decode(data: Data, metadata: IFSResourceMetadata) throws -> IFSDecodedDocument {
        guard metadata.kind == .file else { throw IFSWorkspaceError.remoteObjectUnsupported }
        guard data.count <= Self.maximumEditableBytes else { throw IFSWorkspaceError.fileTooLarge }
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]) else { throw IFSWorkspaceError.byteOrderMarkUnsupported }
        guard !data.contains(0) else { throw IFSWorkspaceError.binaryFile }
        guard let decoded = String(data: data, encoding: .utf8) else { throw IFSWorkspaceError.invalidUTF8 }

        let hasCRLF = decoded.contains("\r\n")
        let withoutCRLF = decoded.replacingOccurrences(of: "\r\n", with: "")
        guard !withoutCRLF.contains("\r") else { throw IFSWorkspaceError.mixedLineEndings }
        if hasCRLF, withoutCRLF.contains("\n") { throw IFSWorkspaceError.mixedLineEndings }

        let lineEnding: SourceLineEnding = hasCRLF ? .crlf : .lf
        let normalizedText = hasCRLF ? decoded.replacingOccurrences(of: "\r\n", with: "\n") : decoded
        let revision = IFSRemoteRevision(data: data)
        let document = SourceDocument(
            identity: .ifs(path: metadata.path.value),
            format: Self.format(for: metadata.path),
            ccsid: 1208,
            sourceDatePolicy: .preserve,
            lineEnding: lineEnding,
            originalText: normalizedText,
            remoteRevision: revision.token
        )
        return IFSDecodedDocument(document: document, revision: revision, metadata: metadata)
    }

    public func encode(_ document: SourceDocument) throws -> Data {
        guard case .ifs = document.identity else { throw IFSWorkspaceError.remoteObjectUnsupported }
        guard document.ccsid == 1208 else { throw IFSWorkspaceError.unsupportedCCSID(document.ccsid) }
        guard !document.text.contains("\r") else { throw IFSWorkspaceError.mixedLineEndings }
        guard !document.text.contains("\0") else { throw IFSWorkspaceError.binaryFile }

        let encodedText = document.lineEnding == .crlf
            ? document.text.replacingOccurrences(of: "\n", with: "\r\n")
            : document.text
        let data = Data(encodedText.utf8)
        guard data.count <= Self.maximumEditableBytes else { throw IFSWorkspaceError.fileTooLarge }
        return data
    }

    private static func format(for path: IFSPath) -> SourceFormat {
        switch URL(fileURLWithPath: path.value).pathExtension.lowercased() {
        case "rpgle", "sqlrpgle": .rpgle
        case "cl", "clle": .clle
        case "cbl", "cob", "cobol": .cobol
        case "dds", "pf", "lf", "dspf", "prtf": .dds
        case "sql": .sql
        default: .text
        }
    }
}

public struct IFSWritePlan: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let target: IFSPath
    public let expectedRevision: IFSRemoteRevision
    public let stagedSibling: IFSPath
    public let byteCount: Int
    public let ccsid: Int
    public let lineEnding: SourceLineEnding
    public let payloadSHA256: String

    public init(
        document: SourceDocument,
        nonce: String = UUID().uuidString.lowercased(),
        codec: IFSUTF8DocumentCodec = IFSUTF8DocumentCodec()
    ) throws {
        guard case .ifs(let rawPath) = document.identity else {
            throw IFSWorkspaceError.remoteObjectUnsupported
        }
        guard let token = document.remoteRevision else { throw IFSWorkspaceError.missingRevision }
        let target = try IFSPath(rawPath)
        let expectedRevision = try IFSRemoteRevision(token: token)
        guard !nonce.isEmpty,
              nonce.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw IFSWorkspaceError.invalidWriteNonce
        }
        guard let parent = target.parent else { throw IFSWorkspaceError.remoteObjectUnsupported }
        let stagedSibling = try parent.appending(".itelas-\(nonce).tmp")
        let payload = try codec.encode(document)
        let payloadRevision = IFSRemoteRevision(data: payload)

        id = UUID()
        self.target = target
        self.expectedRevision = expectedRevision
        self.stagedSibling = stagedSibling
        byteCount = payload.count
        ccsid = 1208
        lineEnding = document.lineEnding
        payloadSHA256 = payloadRevision.sha256
    }
}

public struct IFSWriteReceipt: Equatable, Sendable {
    public let target: IFSPath
    public let priorRevision: IFSRemoteRevision
    public let committedRevision: IFSRemoteRevision
    public let stagedSibling: IFSPath
    public let verifiedAt: Date
    public let sameDirectoryRenameRequested: Bool

    public init(
        target: IFSPath,
        priorRevision: IFSRemoteRevision,
        committedRevision: IFSRemoteRevision,
        stagedSibling: IFSPath,
        verifiedAt: Date,
        sameDirectoryRenameRequested: Bool
    ) {
        self.target = target
        self.priorRevision = priorRevision
        self.committedRevision = committedRevision
        self.stagedSibling = stagedSibling
        self.verifiedAt = verifiedAt
        self.sameDirectoryRenameRequested = sameDirectoryRenameRequested
    }
}

public enum SFTPBatchCommand: Equatable, Sendable {
    case listLong(IFSPath)
    case download(remote: IFSPath, local: URL)
    case upload(local: URL, remote: IFSPath)
    case rename(from: IFSPath, to: IFSPath)
    case remove(IFSPath)
}

public struct SFTPBatchEncoder: Sendable {
    public init() {}

    public func encode(_ commands: [SFTPBatchCommand]) throws -> Data {
        guard !commands.isEmpty else { throw IFSWorkspaceError.emptyBatch }
        let lines = try commands.map(encode)
        return Data((lines + ["quit"]).joined(separator: "\n").appending("\n").utf8)
    }

    private func encode(_ command: SFTPBatchCommand) throws -> String {
        switch command {
        case .listLong(let path):
            return "ls -la \(quote(path.value))"
        case .download(let remote, let local):
            return "get \(quote(remote.value)) \(try quote(localURL: local))"
        case .upload(let local, let remote):
            return "put \(try quote(localURL: local)) \(quote(remote.value))"
        case .rename(let source, let target):
            return "rename \(quote(source.value)) \(quote(target.value))"
        case .remove(let path):
            return "rm \(quote(path.value))"
        }
    }

    private func quote(localURL: URL) throws -> String {
        guard localURL.isFileURL,
              localURL.path.hasPrefix("/"),
              !localURL.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw IFSWorkspaceError.invalidLocalPath
        }
        return quote(localURL.path)
    }

    private func quote(_ value: String) -> String {
        var escaped = ""
        for character in value {
            if character == "\\"
                || character == "\""
                || character == "*"
                || character == "?"
                || character == "["
                || character == "]" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return "\"\(escaped)\""
    }
}

public struct SFTPDirectoryListingParser: Sendable {
    public static let maximumEntries = 2_000

    public init() {}

    public func parse(_ output: String, directory: IFSPath) throws -> IFSDirectorySnapshot {
        var entries: [IFSDirectoryEntry] = []
        var recognizedRows = 0
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = line.split(maxSplits: 8, whereSeparator: \.isWhitespace)
            guard fields.count == 9 else { continue }
            let permissions = String(fields[0])
            guard permissions.count == 10,
                  let kind = Self.kind(for: permissions.first) else { continue }
            guard let byteCount = Int64(fields[4]), byteCount >= 0 else { continue }
            recognizedRows += 1

            var name = String(fields[8])
            if kind == .symbolicLink, let range = name.range(of: " -> ") {
                name = String(name[..<range.lowerBound])
            }
            guard name != ".", name != ".." else { continue }
            let path: IFSPath
            do {
                path = try directory.appending(name)
            } catch {
                continue
            }

            let modified = "\(fields[5]) \(fields[6]) \(fields[7])"
            let metadata = IFSResourceMetadata(
                path: path,
                kind: kind,
                permissions: permissions,
                owner: String(fields[2]),
                group: String(fields[3]),
                byteCount: byteCount,
                modifiedDescription: modified
            )
            entries.append(IFSDirectoryEntry(metadata: metadata))
            guard entries.count <= Self.maximumEntries else { throw IFSWorkspaceError.listingTooLarge }
        }

        guard recognizedRows > 0 else { throw IFSWorkspaceError.listingFormatUnsupported }

        entries.sort {
            if $0.kind == .directory, $1.kind != .directory { return true }
            if $0.kind != .directory, $1.kind == .directory { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return IFSDirectorySnapshot(directory: directory, entries: entries)
    }

    private static func kind(for marker: Character?) -> IFSResourceKind? {
        switch marker {
        case "-": .file
        case "d": .directory
        case "l": .symbolicLink
        case "b", "c", "p", "s": .other
        default: nil
        }
    }
}

public enum IFSWorkspaceError: Error, Equatable, LocalizedError, Sendable {
    case pathMustBeAbsolute
    case invalidPath
    case invalidPathComponent(String)
    case pathTooLong
    case invalidRevision
    case missingRevision
    case invalidWriteNonce
    case invalidLocalPath
    case emptyBatch
    case listingFormatUnsupported
    case listingTooLarge
    case fileTooLarge
    case binaryFile
    case invalidUTF8
    case byteOrderMarkUnsupported
    case mixedLineEndings
    case unsupportedCCSID(Int?)
    case remoteObjectUnsupported
    case revisionChanged
    case payloadVerificationFailed
    case writeOutcomeUncertain
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .pathMustBeAbsolute: "IFS paths must start at the root directory."
        case .invalidPath: "The IFS path contains unsupported control characters."
        case .invalidPathComponent(let component): "The IFS path component “\(component)” is not safe to address."
        case .pathTooLong: "The IFS path is longer than the provider limit."
        case .invalidRevision: "The remote revision token is invalid."
        case .missingRevision: "Open or compare the current remote file before writing."
        case .invalidWriteNonce: "The staged-write identifier is invalid."
        case .invalidLocalPath: "The local transfer path is invalid."
        case .emptyBatch: "The SFTP batch contains no typed operation."
        case .listingFormatUnsupported: "The server returned an unsupported long-directory listing. No entries were inferred."
        case .listingTooLarge: "The directory contains more than \(SFTPDirectoryListingParser.maximumEntries) visible entries. Narrow the path."
        case .fileTooLarge: "The remote file exceeds the \(IFSUTF8DocumentCodec.maximumEditableBytes / 1_048_576) MiB editor limit."
        case .binaryFile: "The remote object appears to be binary and was not opened in the text editor."
        case .invalidUTF8: "The remote bytes are not valid UTF-8 (CCSID 1208)."
        case .byteOrderMarkUnsupported: "UTF-8 files with a byte-order mark are blocked to prevent a lossy rewrite."
        case .mixedLineEndings: "The file has mixed or unsupported line endings. Normalize it explicitly before writing."
        case .unsupportedCCSID(let ccsid): "This IFS provider currently writes only CCSID 1208; received \(ccsid.map(String.init) ?? "unset")."
        case .remoteObjectUnsupported: "This remote object type is read-only in the current provider."
        case .revisionChanged: "The remote bytes changed after this draft was opened. Compare again; no write was attempted."
        case .payloadVerificationFailed: "The staged or committed bytes did not match the reviewed payload."
        case .writeOutcomeUncertain: "The rename result could not be verified. Inspect the remote target before retrying; iTelAS will not replay the write automatically."
        case .processFailed(let detail): detail
        }
    }
}
