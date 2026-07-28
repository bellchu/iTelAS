import Foundation

public enum SourceWorkspaceHostIncludeError: Error, Equatable, LocalizedError, Sendable {
    case invalidDependency
    case dependencyIsNotHostInclude
    case sourceMemberLibraryRequired
    case conflictingSourceMemberLibrary
    case invalidTarget
    case staleReview
    case targetMismatch
    case contentTooLarge(Int)
    case workspaceCapacityExhausted
    case invalidProviderMetadata
    case duplicateOverlayPath(String)
    case exactTargetUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidDependency:
            "The selected dependency is no longer present in this exact source index."
        case .dependencyIsNotHostInclude:
            "Only a host-backed /COPY or /INCLUDE edge can enter reviewed host intake."
        case .sourceMemberLibraryRequired:
            "Enter the exact source-member library before reviewing this host read."
        case .conflictingSourceMemberLibrary:
            "The entered library conflicts with the library already named by the source directive."
        case .invalidTarget:
            "The include target cannot be represented as one exact IFS path or source-member identity."
        case .staleReview:
            "The reviewed host-read request no longer matches the exact source index and dependency edge."
        case .targetMismatch:
            "The provider returned content for a different host target than the reviewed request."
        case .contentTooLarge(let maximum):
            "The host include exceeds the \(maximum)-byte in-memory index limit."
        case .workspaceCapacityExhausted:
            "The current index has no remaining bounded capacity for another host include."
        case .invalidProviderMetadata:
            "The provider receipt contains empty, unsafe, or unbounded metadata."
        case .duplicateOverlayPath(let path):
            "A host include is already loaded at the case-insensitive overlay path \(path)."
        case .exactTargetUnavailable:
            "The exact reviewed host target was not returned by the connected read-only provider."
        }
    }
}

public enum SourceWorkspaceHostIncludeProviderKind: String, Hashable, Sendable {
    case sourceMember
    case ifs

    public var label: String {
        switch self {
        case .sourceMember: "SOURCE MEMBER"
        case .ifs: "IFS PATH"
        }
    }
}

public enum SourceWorkspaceHostIncludeTarget: Hashable, Sendable {
    case sourceMember(SourceMemberIdentity)
    case ifs(IFSPath)

    public var providerKind: SourceWorkspaceHostIncludeProviderKind {
        switch self {
        case .sourceMember: .sourceMember
        case .ifs: .ifs
        }
    }

    public var displayName: String {
        switch self {
        case .sourceMember(let identity): identity.description
        case .ifs(let path): path.value
        }
    }

    public var canonicalIdentity: String {
        switch self {
        case .sourceMember(let identity):
            "member|\(identity.library.value)|\(identity.sourceFile.value)|\(identity.member.value)"
        case .ifs(let path):
            "ifs|\(path.value)"
        }
    }

    fileprivate func overlayRelativePath(format: SourceFormat) -> String {
        switch self {
        case .sourceMember(let identity):
            return "__HOST__/MEMBER/\(identity.library.value)/\(identity.sourceFile.value)/\(identity.member.value).\(Self.extension(for: format))"
        case .ifs(let path):
            return "__HOST__/IFS/\(path.value.drop(while: { $0 == "/" }))"
        }
    }

    private static func `extension`(for format: SourceFormat) -> String {
        switch format {
        case .rpgle: "rpgle"
        case .clle: "clle"
        case .cobol: "cobol"
        case .dds: "dds"
        case .sql: "sql"
        case .text: "txt"
        }
    }
}

public struct SourceWorkspaceHostIncludeOrigin: Hashable, Sendable {
    public let requestFingerprint: String
    public let target: SourceWorkspaceHostIncludeTarget
    public let providerName: String
    public let targetName: String
    public let remoteRevision: String
    public let ccsid: Int
    public let capturedAt: Date

    public var shortRevision: String {
        let digest = AIContentFingerprint.sha256(remoteRevision)
        return String(digest.prefix(8)).uppercased()
    }

    var fingerprintFields: [String] {
        [
            "host", requestFingerprint, target.canonicalIdentity, providerName, targetName,
            remoteRevision, String(ccsid), String(format: "%.3f", capturedAt.timeIntervalSince1970)
        ]
    }
}

public enum SourceWorkspaceDocumentOrigin: Hashable, Sendable {
    case local
    case hostInclude(SourceWorkspaceHostIncludeOrigin)

    public var isHostBacked: Bool {
        if case .hostInclude = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .local: "LOCAL"
        case .hostInclude(let origin): "HOST · \(origin.target.providerKind.label)"
        }
    }

    var fingerprintFields: [String] {
        switch self {
        case .local: ["local"]
        case .hostInclude(let origin): origin.fingerprintFields
        }
    }
}

public struct ReviewedSourceWorkspaceHostInclude: Equatable, Sendable, Identifiable {
    public let id: String
    public let indexFingerprint: String
    public let sourcePath: String
    public let dependencyID: String
    public let dependencyKind: SourceReferenceKind
    public let dependencyRange: SourceTextRange
    public let target: SourceWorkspaceHostIncludeTarget
    public let maximumContentUTF8Bytes: Int
    public let maximumRelativePathUTF8Bytes: Int
    public let reviewedBy: String
    public let reviewedAt: Date
    public let reviewFingerprint: String

    public init(
        index: SourceWorkspaceIndex,
        dependencyID: String,
        sourceMemberLibrary: String? = nil,
        reviewedBy: String = "LOCAL OPERATOR",
        reviewedAt: Date = Date()
    ) throws {
        let matches = index.documents.flatMap(\.dependencies).filter { $0.id == dependencyID }
        guard matches.count == 1, let dependency = matches.first else {
            throw SourceWorkspaceHostIncludeError.invalidDependency
        }
        guard dependency.resolution == .hostBacked,
              dependency.kind == .copy || dependency.kind == .include else {
            throw SourceWorkspaceHostIncludeError.dependencyIsNotHostInclude
        }
        let override = sourceMemberLibrary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTarget: SourceWorkspaceHostIncludeTarget
        switch dependency.target {
        case .member(let library, let sourceFile, let member):
            if let library, let override, !override.isEmpty,
               library.caseInsensitiveCompare(override) != .orderedSame {
                throw SourceWorkspaceHostIncludeError.conflictingSourceMemberLibrary
            }
            let resolvedLibrary = library ?? override
            guard let resolvedLibrary, !resolvedLibrary.isEmpty else {
                throw SourceWorkspaceHostIncludeError.sourceMemberLibraryRequired
            }
            do {
                resolvedTarget = .sourceMember(try SourceMemberIdentity(
                    library: resolvedLibrary,
                    sourceFile: sourceFile,
                    member: member
                ))
            } catch {
                throw SourceWorkspaceHostIncludeError.invalidTarget
            }
        case .ifsPath(let rawPath):
            guard override == nil || override?.isEmpty == true else {
                throw SourceWorkspaceHostIncludeError.invalidTarget
            }
            do {
                let path = try IFSPath(rawPath)
                guard !path.isRoot else { throw SourceWorkspaceHostIncludeError.invalidTarget }
                resolvedTarget = .ifs(path)
            } catch {
                throw SourceWorkspaceHostIncludeError.invalidTarget
            }
        default:
            throw SourceWorkspaceHostIncludeError.invalidTarget
        }
        let reviewer = reviewedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reviewer.isEmpty,
              reviewer.utf8.count <= 128,
              !reviewer.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw SourceWorkspaceHostIncludeError.invalidProviderMetadata
        }
        let remainingCapacity = index.limits.maximumTotalUTF8Bytes - index.totalUTF8Bytes
        guard remainingCapacity > 0 else {
            throw SourceWorkspaceHostIncludeError.workspaceCapacityExhausted
        }
        let maximumContentUTF8Bytes = min(
            index.limits.maximumFileUTF8Bytes,
            remainingCapacity
        )
        let timestamp = hostIncludeDate(reviewedAt)
        let fingerprint = Self.fingerprint(
            indexFingerprint: index.fingerprint,
            sourcePath: dependency.sourcePath,
            dependencyID: dependency.id,
            dependencyKind: dependency.kind,
            dependencyRange: dependency.range,
            target: resolvedTarget,
            maximumContentUTF8Bytes: maximumContentUTF8Bytes,
            maximumRelativePathUTF8Bytes: index.limits.maximumRelativePathUTF8Bytes,
            reviewedBy: reviewer,
            reviewedAt: timestamp
        )
        id = fingerprint
        indexFingerprint = index.fingerprint
        sourcePath = dependency.sourcePath
        self.dependencyID = dependency.id
        dependencyKind = dependency.kind
        dependencyRange = dependency.range
        target = resolvedTarget
        self.maximumContentUTF8Bytes = maximumContentUTF8Bytes
        maximumRelativePathUTF8Bytes = index.limits.maximumRelativePathUTF8Bytes
        self.reviewedBy = reviewer
        self.reviewedAt = timestamp
        reviewFingerprint = fingerprint
    }

    public var shortFingerprint: String { String(reviewFingerprint.prefix(8)).uppercased() }

    public func isCurrent(for index: SourceWorkspaceIndex) -> Bool {
        guard index.fingerprint == indexFingerprint,
              reviewFingerprint == Self.fingerprint(
                indexFingerprint: indexFingerprint,
                sourcePath: sourcePath,
                dependencyID: dependencyID,
                dependencyKind: dependencyKind,
                dependencyRange: dependencyRange,
                target: target,
                maximumContentUTF8Bytes: maximumContentUTF8Bytes,
                maximumRelativePathUTF8Bytes: maximumRelativePathUTF8Bytes,
                reviewedBy: reviewedBy,
                reviewedAt: reviewedAt
              ) else { return false }
        let matches = index.documents.flatMap(\.dependencies).filter { $0.id == dependencyID }
        guard matches.count == 1, let dependency = matches.first else { return false }
        return dependency.sourcePath == sourcePath
            && dependency.kind == dependencyKind
            && dependency.range == dependencyRange
            && dependency.resolution == .hostBacked
    }

    private static func fingerprint(
        indexFingerprint: String,
        sourcePath: String,
        dependencyID: String,
        dependencyKind: SourceReferenceKind,
        dependencyRange: SourceTextRange,
        target: SourceWorkspaceHostIncludeTarget,
        maximumContentUTF8Bytes: Int,
        maximumRelativePathUTF8Bytes: Int,
        reviewedBy: String,
        reviewedAt: Date
    ) -> String {
        hostIncludeFingerprint([
            "itelas-host-include-review-v1", indexFingerprint, sourcePath, dependencyID,
            dependencyKind.rawValue, String(dependencyRange.startLine),
            String(dependencyRange.startColumn), String(dependencyRange.endColumn),
            target.canonicalIdentity, String(maximumContentUTF8Bytes),
            String(maximumRelativePathUTF8Bytes), reviewedBy,
            String(format: "%.3f", reviewedAt.timeIntervalSince1970)
        ])
    }
}

public struct SourceWorkspaceHostIncludeContent: Equatable, Sendable, Identifiable {
    public let id: String
    public let requestFingerprint: String
    public let sourceIndexFingerprint: String
    public let sourcePath: String
    public let dependencyID: String
    public let target: SourceWorkspaceHostIncludeTarget
    public let providerName: String
    public let targetName: String
    public let text: String
    public let format: SourceFormat
    public let ccsid: Int
    public let remoteRevision: String
    public let capturedAt: Date
    public let contentFingerprint: String
    public let overlayRelativePath: String

    public init(
        request: ReviewedSourceWorkspaceHostInclude,
        actualTarget: SourceWorkspaceHostIncludeTarget,
        providerName: String,
        targetName: String,
        text: String,
        format: SourceFormat,
        ccsid: Int,
        remoteRevision: String,
        capturedAt: Date = Date()
    ) throws {
        guard request.target == actualTarget else {
            throw SourceWorkspaceHostIncludeError.targetMismatch
        }
        guard text.lengthOfBytes(using: .utf8) <= request.maximumContentUTF8Bytes else {
            throw SourceWorkspaceHostIncludeError.contentTooLarge(request.maximumContentUTF8Bytes)
        }
        let provider = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerTarget = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = remoteRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [provider, providerTarget, revision].allSatisfy({ value in
            !value.isEmpty && value.utf8.count <= 512
                && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }), ccsid > 0 else {
            throw SourceWorkspaceHostIncludeError.invalidProviderMetadata
        }
        let path = actualTarget.overlayRelativePath(format: format)
        _ = try SourceWorkspaceFile(
            relativePath: path,
            format: format,
            text: text,
            limits: SourceWorkspaceIndexLimits(
                maximumFileUTF8Bytes: request.maximumContentUTF8Bytes,
                maximumRelativePathUTF8Bytes: request.maximumRelativePathUTF8Bytes
            )
        )
        let timestamp = hostIncludeDate(capturedAt)
        let contentFingerprint = SourceIntelligenceAnalyzer.fingerprint(of: text)
        let receiptFingerprint = hostIncludeFingerprint([
            "itelas-host-include-content-v1", request.reviewFingerprint,
            actualTarget.canonicalIdentity, provider, providerTarget, revision,
            String(ccsid), format.rawValue, contentFingerprint, path,
            String(format: "%.3f", timestamp.timeIntervalSince1970)
        ])
        id = receiptFingerprint
        requestFingerprint = request.reviewFingerprint
        sourceIndexFingerprint = request.indexFingerprint
        sourcePath = request.sourcePath
        dependencyID = request.dependencyID
        target = actualTarget
        self.providerName = provider
        self.targetName = providerTarget
        self.text = text
        self.format = format
        self.ccsid = ccsid
        self.remoteRevision = revision
        self.capturedAt = timestamp
        self.contentFingerprint = contentFingerprint
        overlayRelativePath = path
    }

    public init(
        request: ReviewedSourceWorkspaceHostInclude,
        snapshot: SourceMemberSnapshot,
        providerName: String,
        targetName: String,
        capturedAt: Date = Date()
    ) throws {
        guard snapshot.metadata.access.canRead else {
            throw SourceWorkspaceHostIncludeError.exactTargetUnavailable
        }
        try self.init(
            request: request,
            actualTarget: .sourceMember(snapshot.metadata.identity),
            providerName: providerName,
            targetName: targetName,
            text: snapshot.text,
            format: Self.format(forSourceType: snapshot.metadata.sourceType),
            ccsid: snapshot.metadata.ccsid,
            remoteRevision: snapshot.revision.token,
            capturedAt: capturedAt
        )
    }

    public init(
        request: ReviewedSourceWorkspaceHostInclude,
        decodedIFS: IFSDecodedDocument,
        providerName: String,
        targetName: String,
        capturedAt: Date = Date()
    ) throws {
        guard let ccsid = decodedIFS.document.ccsid, ccsid > 0 else {
            throw SourceWorkspaceHostIncludeError.invalidProviderMetadata
        }
        try self.init(
            request: request,
            actualTarget: .ifs(decodedIFS.metadata.path),
            providerName: providerName,
            targetName: targetName,
            text: decodedIFS.document.text,
            format: decodedIFS.document.format,
            ccsid: ccsid,
            remoteRevision: decodedIFS.revision.token,
            capturedAt: capturedAt
        )
    }

    public var shortFingerprint: String { String(id.prefix(8)).uppercased() }

    fileprivate func workspaceFile(limits: SourceWorkspaceIndexLimits) throws -> SourceWorkspaceFile {
        try SourceWorkspaceFile(
            relativePath: overlayRelativePath,
            format: format,
            text: text,
            origin: .hostInclude(SourceWorkspaceHostIncludeOrigin(
                requestFingerprint: requestFingerprint,
                target: target,
                providerName: providerName,
                targetName: targetName,
                remoteRevision: remoteRevision,
                ccsid: ccsid,
                capturedAt: capturedAt
            )),
            limits: limits
        )
    }

    private static func format(forSourceType rawValue: String) -> SourceFormat {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.contains("RPG") { return .rpgle }
        if value.contains("CL") { return .clle }
        if value.contains("COB") || value.contains("CBL") { return .cobol }
        if ["PF", "LF", "DSPF", "PRTF", "DDS"].contains(value) { return .dds }
        if value.contains("SQL") { return .sql }
        return .text
    }
}

public extension SourceWorkspaceIndex {
    var localFileCount: Int { documents.filter { !$0.origin.isHostBacked }.count }
    var hostIncludeFileCount: Int { documents.filter { $0.origin.isHostBacked }.count }
    var hostIncludeDocuments: [SourceWorkspaceDocumentIndex] { documents.filter { $0.origin.isHostBacked } }

    func appendingHostInclude(_ content: SourceWorkspaceHostIncludeContent) throws -> SourceWorkspaceIndex {
        guard content.sourceIndexFingerprint == fingerprint else {
            throw SourceWorkspaceHostIncludeError.staleReview
        }
        guard !documents.contains(where: {
            $0.relativePath.caseInsensitiveCompare(content.overlayRelativePath) == .orderedSame
        }) else {
            throw SourceWorkspaceHostIncludeError.duplicateOverlayPath(content.overlayRelativePath)
        }
        var files = try documents.map { document in
            try SourceWorkspaceFile(
                relativePath: document.relativePath,
                format: document.format,
                text: document.text,
                modifiedAt: document.modifiedAt,
                sourceDate: document.sourceDate,
                origin: document.origin,
                limits: limits
            )
        }
        files.append(try content.workspaceFile(limits: limits))
        return try SourceWorkspaceIndexBuilder(limits: limits).build(
            rootName: rootName,
            files: files,
            skippedFiles: skippedFiles,
            createdAt: createdAt
        )
    }

    func removingHostIncludes() throws -> SourceWorkspaceIndex {
        guard hostIncludeFileCount > 0 else { return self }
        let files = try documents.filter { !$0.origin.isHostBacked }.map { document in
            try SourceWorkspaceFile(
                relativePath: document.relativePath,
                format: document.format,
                text: document.text,
                modifiedAt: document.modifiedAt,
                sourceDate: document.sourceDate,
                origin: .local,
                limits: limits
            )
        }
        return try SourceWorkspaceIndexBuilder(limits: limits).build(
            rootName: rootName,
            files: files,
            skippedFiles: skippedFiles,
            createdAt: createdAt
        )
    }
}

private func hostIncludeFingerprint(_ fields: [String]) -> String {
    let framed = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    return AIContentFingerprint.sha256(framed)
}

private func hostIncludeDate(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
}
