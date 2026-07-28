import Foundation
import iTelASCore

struct IFSWorkspaceService: IFSProvider, Sendable {
    private let knownHostsStore: ManagedKnownHostsStore
    private let runner: SystemProviderProcessRunner
    private let codec = IFSUTF8DocumentCodec()

    init(
        knownHostsURL: URL = SecureChannelService.defaultKnownHostsURL,
        runner: SystemProviderProcessRunner = SystemProviderProcessRunner()
    ) {
        knownHostsStore = ManagedKnownHostsStore(fileURL: knownHostsURL)
        self.runner = runner
    }

    func listDirectory(profile: SecureChannelProfile, path: IFSPath) async throws -> IFSDirectorySnapshot {
        try requirePinnedHost(profile)
        let result = try await runBatch(profile: profile, commands: [.listLong(path)])
        guard result.terminationStatus == 0 else {
            throw IFSWorkspaceError.processFailed(Self.diagnostic(
                from: result.standardError,
                fallback: "The SFTP directory listing failed."
            ))
        }
        return try SFTPDirectoryListingParser().parse(
            String(decoding: result.standardOutput, as: UTF8.self),
            directory: path
        )
    }

    func readFile(
        profile: SecureChannelProfile,
        metadata: IFSResourceMetadata
    ) async throws -> IFSDecodedDocument {
        guard metadata.kind == .file else { throw IFSWorkspaceError.remoteObjectUnsupported }
        guard metadata.byteCount >= 0,
              metadata.byteCount <= IFSUTF8DocumentCodec.maximumEditableBytes else {
            throw IFSWorkspaceError.fileTooLarge
        }
        try requirePinnedHost(profile)
        let directory = try makeTransferDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localURL = directory.appendingPathComponent("remote-file", isDirectory: false)
        let data = try await download(profile: profile, remote: metadata.path, local: localURL)
        return try codec.decode(data: data, metadata: metadata)
    }

    func writeFile(
        profile: SecureChannelProfile,
        document: SourceDocument,
        metadata: IFSResourceMetadata,
        plan: IFSWritePlan
    ) async throws -> IFSWriteReceipt {
        try requirePinnedHost(profile)
        guard metadata.kind == .file,
              metadata.path == plan.target,
              case .ifs(let rawPath) = document.identity,
              try IFSPath(rawPath) == plan.target,
              document.remoteRevision == plan.expectedRevision.token else {
            throw IFSWorkspaceError.remoteObjectUnsupported
        }

        guard let parent = plan.target.parent else { throw IFSWorkspaceError.remoteObjectUnsupported }
        let latestDirectory = try await listDirectory(profile: profile, path: parent)
        guard let currentEntry = latestDirectory.entries.first(where: { $0.metadata.path == plan.target }),
              currentEntry.kind == .file else {
            throw IFSWorkspaceError.remoteObjectUnsupported
        }
        guard currentEntry.metadata.byteCount >= 0,
              currentEntry.metadata.byteCount <= IFSUTF8DocumentCodec.maximumEditableBytes else {
            throw IFSWorkspaceError.fileTooLarge
        }

        let directory = try makeTransferDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let currentURL = directory.appendingPathComponent("current", isDirectory: false)
        let payloadURL = directory.appendingPathComponent("payload", isDirectory: false)
        let stagedURL = directory.appendingPathComponent("staged-verification", isDirectory: false)
        let preRenameURL = directory.appendingPathComponent("pre-rename-revision", isDirectory: false)
        let committedURL = directory.appendingPathComponent("committed-verification", isDirectory: false)

        let currentData = try await download(profile: profile, remote: plan.target, local: currentURL)
        let currentRevision = IFSRemoteRevision(data: currentData)
        guard currentRevision == plan.expectedRevision else { throw IFSWorkspaceError.revisionChanged }

        let payload = try codec.encode(document)
        let payloadRevision = IFSRemoteRevision(data: payload)
        guard payload.count == plan.byteCount,
              payloadRevision.sha256 == plan.payloadSHA256 else {
            throw IFSWorkspaceError.payloadVerificationFailed
        }
        try writeRestricted(payload, to: payloadURL)

        var stagedUploadMayExist = false
        do {
            stagedUploadMayExist = true
            try await requireSuccessfulBatch(
                profile: profile,
                commands: [.upload(local: payloadURL, remote: plan.stagedSibling)],
                fallback: "The staged SFTP upload failed; the target file was not renamed."
            )

            let stagedData = try await download(profile: profile, remote: plan.stagedSibling, local: stagedURL)
            guard IFSRemoteRevision(data: stagedData) == payloadRevision else {
                throw IFSWorkspaceError.payloadVerificationFailed
            }

            let preRenameData = try await download(
                profile: profile,
                remote: plan.target,
                local: preRenameURL
            )
            guard IFSRemoteRevision(data: preRenameData) == currentRevision else {
                throw IFSWorkspaceError.revisionChanged
            }

            var committedDataFromAmbiguousRename: Data?
            do {
                try await requireSuccessfulBatch(
                    profile: profile,
                    commands: [.rename(from: plan.stagedSibling, to: plan.target)],
                    fallback: "The same-directory SFTP rename did not return a verified success result."
                )
                stagedUploadMayExist = false
            } catch {
                guard let observedData = try? await download(
                    profile: profile,
                    remote: plan.target,
                    local: committedURL
                ) else {
                    throw IFSWorkspaceError.writeOutcomeUncertain
                }
                let observedRevision = IFSRemoteRevision(data: observedData)
                if observedRevision == payloadRevision {
                    stagedUploadMayExist = false
                    committedDataFromAmbiguousRename = observedData
                } else if observedRevision == currentRevision {
                    throw error
                } else {
                    throw IFSWorkspaceError.payloadVerificationFailed
                }
            }

            let committedData: Data
            if let committedDataFromAmbiguousRename {
                committedData = committedDataFromAmbiguousRename
            } else {
                do {
                    committedData = try await download(profile: profile, remote: plan.target, local: committedURL)
                } catch {
                    throw IFSWorkspaceError.writeOutcomeUncertain
                }
            }
            let committedRevision = IFSRemoteRevision(data: committedData)
            guard committedRevision == payloadRevision else {
                throw IFSWorkspaceError.payloadVerificationFailed
            }
            return IFSWriteReceipt(
                target: plan.target,
                priorRevision: currentRevision,
                committedRevision: committedRevision,
                stagedSibling: plan.stagedSibling,
                verifiedAt: Date(),
                sameDirectoryRenameRequested: true
            )
        } catch {
            if stagedUploadMayExist {
                try? await requireSuccessfulBatch(
                    profile: profile,
                    commands: [.remove(plan.stagedSibling)],
                    fallback: "The staged upload could not be removed."
                )
            }
            throw error
        }
    }

    private func download(
        profile: SecureChannelProfile,
        remote: IFSPath,
        local: URL
    ) async throws -> Data {
        try await requireSuccessfulBatch(
            profile: profile,
            commands: [.download(remote: remote, local: local)],
            fallback: "The SFTP download failed."
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: local.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw IFSWorkspaceError.remoteObjectUnsupported
        }
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard byteCount <= IFSUTF8DocumentCodec.maximumEditableBytes else {
            throw IFSWorkspaceError.fileTooLarge
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: local.path)
        return try Data(contentsOf: local, options: .mappedIfSafe)
    }

    private func runBatch(
        profile: SecureChannelProfile,
        commands: [SFTPBatchCommand]
    ) async throws -> ProviderProcessResult {
        let plan = try SystemSSHCommandPlan.sftpBatch(
            for: profile,
            knownHostsFile: knownHostsStore.fileURL.path,
            commands: commands
        )
        return try await runner.run(plan)
    }

    private func requireSuccessfulBatch(
        profile: SecureChannelProfile,
        commands: [SFTPBatchCommand],
        fallback: String
    ) async throws {
        let result = try await runBatch(profile: profile, commands: commands)
        guard result.terminationStatus == 0 else {
            throw IFSWorkspaceError.processFailed(Self.diagnostic(from: result.standardError, fallback: fallback))
        }
    }

    private func requirePinnedHost(_ profile: SecureChannelProfile) throws {
        guard try knownHostsStore.hasPinnedKey(for: profile) else {
            throw IFSWorkspaceError.processFailed("Pin and test the SSH host identity before using IFS operations.")
        }
    }

    private func makeTransferDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itelas-ifs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func writeRestricted(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func diagnostic(from data: Data, fallback: String) -> String {
        let raw = String(decoding: data.prefix(1_024), as: UTF8.self)
        return raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? fallback
    }
}
