import Foundation
import iTelASCore

struct SourceWorkspaceScanResult: Sendable {
    let index: SourceWorkspaceIndex
    let rootURL: URL
    let buildReport: SourceWorkspaceIndexBuildReport
}

enum LocalSourceWorkspaceScanError: Error, LocalizedError {
    case invalidRoot
    case enumerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidRoot:
            "Choose a regular local folder rather than a file or symbolic link."
        case .enumerationFailed:
            "The selected folder could not be enumerated under current macOS permissions."
        }
    }
}

struct SourceWorkspaceRenameRecoveryReport: Equatable, Sendable {
    let restoredPaths: [String]
    let unresolvedPaths: [String]

    var isComplete: Bool { unresolvedPaths.isEmpty }

    var label: String {
        if !unresolvedPaths.isEmpty { return "RECOVERY INCOMPLETE" }
        return restoredPaths.isEmpty ? "NO ROLLBACK NEEDED" : "BATCH ROLLED BACK"
    }
}

enum LocalSourceWorkspaceRenameError: Error, Equatable, LocalizedError, Sendable {
    case staleReview
    case unsafeTarget(String)
    case baselineChanged(String)
    case invalidSource(String)
    case applyFailed(path: String, recovery: SourceWorkspaceRenameRecoveryReport)

    var errorDescription: String? {
        switch self {
        case .staleReview:
            "The reviewed rename no longer matches the exact local index and preview."
        case .unsafeTarget(let path):
            "The reviewed path is no longer a regular, non-symbolic-link source file: \(path)."
        case .baselineChanged(let path):
            "The content, modification time, or permissions changed after indexing: \(path)."
        case .invalidSource(let path):
            "The reviewed source is no longer bounded NUL-free UTF-8 text: \(path)."
        case .applyFailed(let path, let recovery):
            if recovery.isComplete {
                "The batch stopped at \(path); every earlier replacement was restored."
            } else {
                "The batch stopped at \(path), and recovery needs inspection for: \(recovery.unresolvedPaths.joined(separator: ", "))."
            }
        }
    }
}

struct SourceWorkspaceRenameApplyReceipt: Equatable, Sendable, Identifiable {
    let id: String
    let planFingerprint: String
    let reviewFingerprint: String
    let changedPaths: [String]
    let replacementCount: Int
    let resultContentFingerprints: [String]
    let appliedAt: Date

    var shortFingerprint: String { String(id.prefix(8)).uppercased() }
}

struct SourceWorkspaceRenameApplyControl: Equatable, Sendable {
    var failAfterCommittedFileCount: Int?

    static let production = SourceWorkspaceRenameApplyControl(failAfterCommittedFileCount: nil)
}

struct SourceWorkspaceIndexService: Sendable {
    let limits: SourceWorkspaceIndexLimits

    init(limits: SourceWorkspaceIndexLimits = SourceWorkspaceIndexLimits()) {
        self.limits = limits
    }

    func scan(
        rootURL selectedURL: URL,
        previousIndex: SourceWorkspaceIndex? = nil
    ) throws -> SourceWorkspaceScanResult {
        let selectedValues = try selectedURL.standardizedFileURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard selectedValues.isDirectory == true, selectedValues.isSymbolicLink != true else {
            throw LocalSourceWorkspaceScanError.invalidRoot
        }
        let rootURL = selectedURL.standardizedFileURL
        let rootValues = try rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw LocalSourceWorkspaceScanError.invalidRoot
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw LocalSourceWorkspaceScanError.enumerationFailed
        }

        var files: [SourceWorkspaceFile] = []
        var skipped: [SourceWorkspaceSkippedFile] = []
        var totalBytes = 0
        while let candidate = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values: URLResourceValues
            do {
                values = try candidate.resourceValues(forKeys: keys)
            } catch {
                skipped.append(SourceWorkspaceSkippedFile(
                    relativePath: relativePath(candidate, rootURL: rootURL),
                    reason: "Metadata could not be read."
                ))
                continue
            }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                if Self.format(for: candidate) != nil {
                    skipped.append(SourceWorkspaceSkippedFile(
                        relativePath: relativePath(candidate, rootURL: rootURL),
                        reason: "Symbolic links are not indexed."
                    ))
                }
                continue
            }
            guard values.isDirectory != true,
                  values.isRegularFile == true,
                  let format = Self.format(for: candidate) else { continue }
            guard files.count < limits.maximumFiles else {
                throw SourceWorkspaceIndexError.tooManyFiles(limits.maximumFiles)
            }
            let path = relativePath(candidate, rootURL: rootURL)
            let expectedSize = values.fileSize ?? 0
            guard expectedSize <= limits.maximumFileUTF8Bytes else {
                skipped.append(SourceWorkspaceSkippedFile(
                    relativePath: path,
                    reason: "File exceeds the \(limits.maximumFileUTF8Bytes)-byte limit."
                ))
                continue
            }
            let data: Data
            do {
                data = try Data(contentsOf: candidate, options: [.mappedIfSafe])
            } catch {
                skipped.append(SourceWorkspaceSkippedFile(
                    relativePath: path,
                    reason: "File content could not be read."
                ))
                continue
            }
            guard data.count <= limits.maximumFileUTF8Bytes else {
                skipped.append(SourceWorkspaceSkippedFile(
                    relativePath: path,
                    reason: "File changed beyond the per-file limit during indexing."
                ))
                continue
            }
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                skipped.append(SourceWorkspaceSkippedFile(
                    relativePath: path,
                    reason: "Only NUL-free UTF-8 source is indexed in this local workspace."
                ))
                continue
            }
            totalBytes += data.count
            guard totalBytes <= limits.maximumTotalUTF8Bytes else {
                throw SourceWorkspaceIndexError.workspaceTooLarge(limits.maximumTotalUTF8Bytes)
            }
            files.append(try SourceWorkspaceFile(
                relativePath: path,
                format: format,
                text: text,
                modifiedAt: values.contentModificationDate,
                limits: limits
            ))
        }

        let rootName = rootURL.lastPathComponent.isEmpty ? "LOCAL SOURCE ROOT" : rootURL.lastPathComponent
        let buildResult = try SourceWorkspaceIndexBuilder(limits: limits).buildIncrementally(
            rootName: rootName,
            files: files,
            previousIndex: previousIndex,
            skippedFiles: skipped
        )
        return SourceWorkspaceScanResult(
            index: buildResult.index,
            rootURL: rootURL,
            buildReport: buildResult.report
        )
    }

    func applyReviewedRename(
        rootURL selectedURL: URL,
        index: SourceWorkspaceIndex,
        plan: SourceWorkspaceRenamePlan,
        review: ReviewedSourceWorkspaceRename,
        control: SourceWorkspaceRenameApplyControl = .production
    ) throws -> SourceWorkspaceRenameApplyReceipt {
        guard review.isCurrent(plan: plan, index: index) else {
            throw LocalSourceWorkspaceRenameError.staleReview
        }
        let rootURL = try validatedRoot(selectedURL)
        let baselines = plan.baselines.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
        var prepared: [PreparedRenameFile] = []
        prepared.reserveCapacity(baselines.count)

        for baseline in baselines {
            try Task.checkCancellation()
            let target = try readTarget(rootURL: rootURL, relativePath: baseline.relativePath)
            guard target.text == index.document(at: baseline.relativePath)?.text,
                  SourceIntelligenceAnalyzer.fingerprint(of: target.text) == baseline.contentFingerprint,
                  sameMillisecond(target.modifiedAt, baseline.modifiedAt) else {
                throw LocalSourceWorkspaceRenameError.baselineChanged(baseline.relativePath)
            }
            let replacementText: String
            do {
                replacementText = try index.replacementText(for: plan, relativePath: baseline.relativePath)
            } catch {
                throw LocalSourceWorkspaceRenameError.invalidSource(baseline.relativePath)
            }
            let replacementData = Data(replacementText.utf8)
            guard replacementData.count <= limits.maximumFileUTF8Bytes,
                  replacementData != target.data else {
                throw LocalSourceWorkspaceRenameError.invalidSource(baseline.relativePath)
            }
            prepared.append(PreparedRenameFile(
                relativePath: baseline.relativePath,
                url: target.url,
                originalData: target.data,
                replacementData: replacementData,
                originalModifiedAt: target.modifiedAt,
                posixPermissions: target.posixPermissions
            ))
        }

        var committed: [PreparedRenameFile] = []
        var uncertainPaths: [String] = []
        var activePath = prepared.first?.relativePath ?? "reviewed source batch"
        do {
            for file in prepared {
                try Task.checkCancellation()
                activePath = file.relativePath
                let current = try readTarget(rootURL: rootURL, relativePath: file.relativePath)
                guard current.data == file.originalData,
                      sameMillisecond(current.modifiedAt, file.originalModifiedAt),
                      current.posixPermissions == file.posixPermissions else {
                    throw LocalSourceWorkspaceRenameError.baselineChanged(file.relativePath)
                }
                if control.failAfterCommittedFileCount == committed.count {
                    throw CocoaError(.fileWriteUnknown)
                }
                do {
                    try atomicReplace(
                        file.replacementData,
                        at: file.url,
                        posixPermissions: file.posixPermissions,
                        modificationDate: nil
                    )
                    committed.append(file)
                } catch {
                    if !committed.contains(where: { $0.relativePath == file.relativePath }) {
                        do {
                            let currentData = try Data(contentsOf: file.url, options: [.mappedIfSafe])
                            if currentData == file.replacementData {
                                committed.append(file)
                            } else if currentData != file.originalData {
                                uncertainPaths.append(file.relativePath)
                            }
                        } catch {
                            uncertainPaths.append(file.relativePath)
                        }
                    }
                    throw error
                }
            }
        } catch {
            guard !committed.isEmpty || !uncertainPaths.isEmpty else { throw error }
            let rollbackReport = rollback(committed.reversed())
            let recovery = SourceWorkspaceRenameRecoveryReport(
                restoredPaths: rollbackReport.restoredPaths,
                unresolvedPaths: Array(Set(rollbackReport.unresolvedPaths + uncertainPaths)).sorted()
            )
            throw LocalSourceWorkspaceRenameError.applyFailed(path: activePath, recovery: recovery)
        }

        let resultFingerprints = prepared.map {
            SourceIntelligenceAnalyzer.fingerprint(of: String(decoding: $0.replacementData, as: UTF8.self))
        }
        let appliedAt = Date()
        let receiptFingerprint = AIContentFingerprint.sha256([
            plan.fingerprint,
            review.reviewFingerprint,
            prepared.map(\.relativePath).joined(separator: "\n"),
            resultFingerprints.joined(separator: "\n"),
            String(plan.occurrences.count),
            String(format: "%.3f", appliedAt.timeIntervalSince1970)
        ].joined(separator: "|"))
        return SourceWorkspaceRenameApplyReceipt(
            id: receiptFingerprint,
            planFingerprint: plan.fingerprint,
            reviewFingerprint: review.reviewFingerprint,
            changedPaths: prepared.map(\.relativePath),
            replacementCount: plan.occurrences.count,
            resultContentFingerprints: resultFingerprints,
            appliedAt: appliedAt
        )
    }

    static func format(for url: URL) -> SourceFormat? {
        switch url.pathExtension.lowercased() {
        case "rpgle", "sqlrpgle", "rpgleinc", "rpg", "cpy": .rpgle
        case "clle", "clp", "cl": .clle
        case "cblle", "cobol", "cbl": .cobol
        case "dspf", "prtf", "pf", "lf", "dds": .dds
        case "sql": .sql
        case "txt": .text
        default: nil
        }
    }

    private func validatedRoot(_ selectedURL: URL) throws -> URL {
        let rootURL = selectedURL.standardizedFileURL
        let values = try rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw LocalSourceWorkspaceRenameError.unsafeTarget(rootURL.lastPathComponent)
        }
        return rootURL
    }

    private func readTarget(rootURL: URL, relativePath: String) throws -> ReadRenameTarget {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }) else {
            throw LocalSourceWorkspaceRenameError.unsafeTarget(relativePath)
        }
        var cursor = rootURL
        for component in components.dropLast() {
            cursor.appendPathComponent(component, isDirectory: true)
            let values = try cursor.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw LocalSourceWorkspaceRenameError.unsafeTarget(relativePath)
            }
        }
        let targetURL = cursor.appendingPathComponent(components.last!, isDirectory: false)
        let values = try targetURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount <= limits.maximumFileUTF8Bytes else {
            throw LocalSourceWorkspaceRenameError.unsafeTarget(relativePath)
        }
        let data = try Data(contentsOf: targetURL, options: [.mappedIfSafe])
        guard data.count <= limits.maximumFileUTF8Bytes,
              !data.contains(0),
              let text = String(data: data, encoding: .utf8) else {
            throw LocalSourceWorkspaceRenameError.invalidSource(relativePath)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            throw LocalSourceWorkspaceRenameError.unsafeTarget(relativePath)
        }
        return ReadRenameTarget(
            url: targetURL,
            data: data,
            text: text,
            modifiedAt: values.contentModificationDate,
            posixPermissions: permissions.intValue
        )
    }

    private func atomicReplace(
        _ data: Data,
        at url: URL,
        posixPermissions: Int,
        modificationDate: Date?
    ) throws {
        try data.write(to: url, options: [.atomic])
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: posixPermissions]
        if let modificationDate { attributes[.modificationDate] = modificationDate }
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              try Data(contentsOf: url, options: [.mappedIfSafe]) == data else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func rollback<S: Sequence>(_ files: S) -> SourceWorkspaceRenameRecoveryReport where S.Element == PreparedRenameFile {
        var restored: [String] = []
        var unresolved: [String] = []
        for file in files {
            do {
                let values = try file.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      try Data(contentsOf: file.url, options: [.mappedIfSafe]) == file.replacementData else {
                    unresolved.append(file.relativePath)
                    continue
                }
                try atomicReplace(
                    file.originalData,
                    at: file.url,
                    posixPermissions: file.posixPermissions,
                    modificationDate: file.originalModifiedAt
                )
                restored.append(file.relativePath)
            } catch {
                unresolved.append(file.relativePath)
            }
        }
        return SourceWorkspaceRenameRecoveryReport(
            restoredPaths: restored.sorted(),
            unresolvedPaths: unresolved.sorted()
        )
    }

    private func relativePath(_ url: URL, rootURL: URL) -> String {
        let rootComponents = rootURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let candidateComponents = url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL.pathComponents + [url.lastPathComponent]
        guard candidateComponents.count > rootComponents.count,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.lastPathComponent
        }
        return candidateComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}

private struct ReadRenameTarget {
    let url: URL
    let data: Data
    let text: String
    let modifiedAt: Date?
    let posixPermissions: Int
}

private struct PreparedRenameFile {
    let relativePath: String
    let url: URL
    let originalData: Data
    let replacementData: Data
    let originalModifiedAt: Date?
    let posixPermissions: Int
}

private func sameMillisecond(_ lhs: Date?, _ rhs: Date?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        true
    case (.some(let lhs), .some(let rhs)):
        Int64(floor(lhs.timeIntervalSince1970 * 1_000)) == Int64(floor(rhs.timeIntervalSince1970 * 1_000))
    default:
        false
    }
}
