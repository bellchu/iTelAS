import Foundation

public struct SourceWorkspaceIndexLimits: Equatable, Sendable {
    public var maximumFiles: Int
    public var maximumFileUTF8Bytes: Int
    public var maximumTotalUTF8Bytes: Int
    public var maximumSymbols: Int
    public var maximumReferences: Int
    public var maximumSearchResults: Int
    public var maximumRenameOccurrences: Int
    public var maximumRelativePathUTF8Bytes: Int

    public init(
        maximumFiles: Int = 5_000,
        maximumFileUTF8Bytes: Int = 2 * 1_024 * 1_024,
        maximumTotalUTF8Bytes: Int = 128 * 1_024 * 1_024,
        maximumSymbols: Int = 100_000,
        maximumReferences: Int = 100_000,
        maximumSearchResults: Int = 500,
        maximumRenameOccurrences: Int = 10_000,
        maximumRelativePathUTF8Bytes: Int = 1_024
    ) {
        self.maximumFiles = max(1, maximumFiles)
        self.maximumFileUTF8Bytes = max(1, maximumFileUTF8Bytes)
        self.maximumTotalUTF8Bytes = max(1, maximumTotalUTF8Bytes)
        self.maximumSymbols = max(1, maximumSymbols)
        self.maximumReferences = max(1, maximumReferences)
        self.maximumSearchResults = max(1, maximumSearchResults)
        self.maximumRenameOccurrences = max(1, maximumRenameOccurrences)
        self.maximumRelativePathUTF8Bytes = max(1, maximumRelativePathUTF8Bytes)
    }
}

public enum SourceWorkspaceIndexError: Error, Equatable, LocalizedError, Sendable {
    case invalidRootName
    case invalidRelativePath(String)
    case duplicateRelativePath(String)
    case emptyWorkspace
    case tooManyFiles(Int)
    case fileTooLarge(path: String, maximum: Int)
    case workspaceTooLarge(Int)
    case tooManySymbols(Int)
    case tooManyReferences(Int)
    case invalidSearch
    case invalidDependencySelection
    case staleDependencyReview
    case invalidRenameIdentifier(String)
    case unchangedRename
    case renameAnalysisLimited(String)
    case noRenameOccurrences
    case tooManyRenameOccurrences(Int)
    case staleRenamePlan
    case invalidRenameReview
    case staleRenameReview
    case invalidRenameOccurrence(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRootName:
            "The workspace root name is empty or contains unsafe control text."
        case .invalidRelativePath(let path):
            "The workspace path is not a safe relative source path: \(path)."
        case .duplicateRelativePath(let path):
            "The workspace contains a duplicate case-insensitive path: \(path)."
        case .emptyWorkspace:
            "No supported UTF-8 source files were found in the selected folder."
        case .tooManyFiles(let maximum):
            "The workspace exceeds the \(maximum)-file index limit."
        case .fileTooLarge(let path, let maximum):
            "\(path) exceeds the \(maximum)-byte per-file index limit."
        case .workspaceTooLarge(let maximum):
            "The workspace exceeds the \(maximum)-byte index limit."
        case .tooManySymbols(let maximum):
            "The workspace exceeds the \(maximum)-symbol index limit."
        case .tooManyReferences(let maximum):
            "The workspace exceeds the \(maximum)-reference index limit."
        case .invalidSearch:
            "Search text must be a single bounded line without control characters."
        case .invalidDependencySelection:
            "Choose one or more distinct indexed files before reviewing completion scope."
        case .staleDependencyReview:
            "The reviewed dependency scope no longer matches this exact workspace index."
        case .invalidRenameIdentifier(let value):
            "The rename identifier is invalid or unbounded: \(value)."
        case .unchangedRename:
            "The current and proposed symbol names are identical."
        case .renameAnalysisLimited(let path):
            "Rename preview stopped because local comment/string analysis was limited for \(path)."
        case .noRenameOccurrences:
            "No editable code-token occurrences were found for this rename preview."
        case .tooManyRenameOccurrences(let maximum):
            "The rename preview exceeds the \(maximum)-occurrence limit."
        case .staleRenamePlan:
            "The rename preview no longer matches the exact indexed workspace."
        case .invalidRenameReview:
            "The rename review identity is empty, unsafe, or not bound to the current preview."
        case .staleRenameReview:
            "The reviewed rename no longer matches the exact preview and workspace index."
        case .invalidRenameOccurrence(let path):
            "The frozen rename occurrence no longer resolves exactly in \(path)."
        }
    }
}

public struct SourceWorkspaceFile: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let format: SourceFormat
    public let text: String
    public let modifiedAt: Date?
    public let sourceDate: String?
    public let origin: SourceWorkspaceDocumentOrigin
    public let contentFingerprint: String

    public var id: String { relativePath.uppercased() }
    public var utf8ByteCount: Int { text.lengthOfBytes(using: .utf8) }

    public init(
        relativePath: String,
        format: SourceFormat,
        text: String,
        modifiedAt: Date? = nil,
        sourceDate: String? = nil,
        origin: SourceWorkspaceDocumentOrigin = .local,
        limits: SourceWorkspaceIndexLimits = SourceWorkspaceIndexLimits()
    ) throws {
        self.relativePath = try Self.validate(relativePath, limits: limits)
        guard text.lengthOfBytes(using: .utf8) <= limits.maximumFileUTF8Bytes else {
            throw SourceWorkspaceIndexError.fileTooLarge(
                path: relativePath,
                maximum: limits.maximumFileUTF8Bytes
            )
        }
        if let sourceDate,
           sourceDate.isEmpty || sourceDate.utf8.count > 64 || sourceDate.unicodeScalars.contains(where: \._isUnsafeIndexControl) {
            throw SourceWorkspaceIndexError.invalidRelativePath(relativePath)
        }
        self.format = format
        self.text = text
        self.modifiedAt = modifiedAt.map(sourceIndexDate)
        self.sourceDate = sourceDate
        self.origin = origin
        contentFingerprint = SourceIntelligenceAnalyzer.fingerprint(of: text)
    }

    private static func validate(
        _ value: String,
        limits: SourceWorkspaceIndexLimits
    ) throws -> String {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !path.contains("\\"),
              path.utf8.count <= limits.maximumRelativePathUTF8Bytes,
              !path.unicodeScalars.contains(where: \._isUnsafeIndexControl),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw SourceWorkspaceIndexError.invalidRelativePath(value)
        }
        return path
    }
}

public struct SourceWorkspaceSkippedFile: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let reason: String

    public var id: String { "\(relativePath.uppercased())|\(reason)" }

    public init(relativePath: String, reason: String) {
        self.relativePath = String(relativePath.prefix(1_024))
        self.reason = String(reason.prefix(240))
    }
}

public enum SourceWorkspaceDependencyResolutionKind: String, CaseIterable, Sendable {
    case exact
    case ambiguous
    case hostBacked
    case unresolved

    public var label: String {
        switch self {
        case .exact: "EXACT"
        case .ambiguous: "AMBIGUOUS"
        case .hostBacked: "HOST CONTENT NOT LOADED"
        case .unresolved: "UNRESOLVED"
        }
    }
}

public struct SourceWorkspaceDependencyEdge: Equatable, Sendable, Identifiable {
    public let id: String
    public let sourcePath: String
    public let kind: SourceReferenceKind
    public let targetLabel: String
    public let target: SourceReferenceTarget
    public let targetPaths: [String]
    public let resolution: SourceWorkspaceDependencyResolutionKind
    public let range: SourceTextRange

    public init(
        sourcePath: String,
        kind: SourceReferenceKind,
        targetLabel: String,
        target: SourceReferenceTarget,
        targetPaths: [String],
        resolution: SourceWorkspaceDependencyResolutionKind,
        range: SourceTextRange
    ) {
        self.sourcePath = sourcePath
        self.kind = kind
        self.targetLabel = targetLabel
        self.target = target
        self.targetPaths = targetPaths
        self.resolution = resolution
        self.range = range
        id = AIContentFingerprint.sha256(indexFields([
            sourcePath, kind.rawValue, targetLabel, targetPaths.joined(separator: "\n"),
            resolution.rawValue, String(range.startLine), String(range.startColumn)
        ]))
    }
}

public struct SourceWorkspaceDocumentIndex: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let format: SourceFormat
    public let text: String
    public let modifiedAt: Date?
    public let sourceDate: String?
    public let origin: SourceWorkspaceDocumentOrigin
    public let contentFingerprint: String
    public let snapshot: SourceIntelligenceSnapshot
    public let dependencies: [SourceWorkspaceDependencyEdge]

    public var id: String { relativePath.uppercased() }
    public var lineCount: Int { text.split(separator: "\n", omittingEmptySubsequences: false).count }
    public var utf8ByteCount: Int { text.lengthOfBytes(using: .utf8) }
    public var displayName: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    public var shortFingerprint: String { String(contentFingerprint.prefix(8)).uppercased() }

    fileprivate init(file: SourceWorkspaceFile, snapshot: SourceIntelligenceSnapshot, dependencies: [SourceWorkspaceDependencyEdge]) {
        relativePath = file.relativePath
        format = file.format
        text = file.text
        modifiedAt = file.modifiedAt
        sourceDate = file.sourceDate
        origin = file.origin
        contentFingerprint = file.contentFingerprint
        self.snapshot = snapshot
        self.dependencies = dependencies
    }
}

public enum SourceWorkspaceSearchKind: String, CaseIterable, Sendable {
    case file
    case symbol
    case reference
    case text

    public var label: String { rawValue.uppercased() }
}

public struct SourceWorkspaceSearchResult: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: SourceWorkspaceSearchKind
    public let relativePath: String
    public let line: Int
    public let column: Int
    public let label: String
    public let detail: String
    public let excerpt: String
    public let score: Int

    public init(
        kind: SourceWorkspaceSearchKind,
        relativePath: String,
        line: Int,
        column: Int,
        label: String,
        detail: String,
        excerpt: String,
        score: Int
    ) {
        self.kind = kind
        self.relativePath = relativePath
        self.line = max(1, line)
        self.column = max(1, column)
        self.label = label
        self.detail = detail
        self.excerpt = excerpt
        self.score = score
        id = AIContentFingerprint.sha256(indexFields([
            kind.rawValue, relativePath, String(line), String(column), label, detail, excerpt
        ]))
    }
}

public enum SourceWorkspaceSearchCompletion: String, Equatable, Sendable {
    case complete
    case perDocumentTextLimitReached
    case resultLimitReached
    case candidateLimitReached

    public var label: String {
        switch self {
        case .complete: "COMPLETE"
        case .perDocumentTextLimitReached: "TEXT MATCH CAP"
        case .resultLimitReached: "RESULT CAP"
        case .candidateLimitReached: "CANDIDATE CAP"
        }
    }

    public var isTruncated: Bool { self != .complete }
}

public struct SourceWorkspaceSearchReport: Equatable, Sendable, Identifiable {
    public let id: String
    public let indexFingerprint: String
    public let query: String
    public let results: [SourceWorkspaceSearchResult]
    public let examinedDocumentCount: Int
    public let scopeDocumentCount: Int
    public let examinedLineCount: Int
    public let candidateCount: Int
    public let resultLimit: Int
    public let completion: SourceWorkspaceSearchCompletion
    public let fingerprint: String

    public var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }
    public var isTruncated: Bool { completion.isTruncated }

    fileprivate init(
        indexFingerprint: String,
        query: String,
        results: [SourceWorkspaceSearchResult],
        examinedDocumentCount: Int,
        scopeDocumentCount: Int,
        examinedLineCount: Int,
        candidateCount: Int,
        resultLimit: Int,
        completion: SourceWorkspaceSearchCompletion
    ) {
        let fingerprint = AIContentFingerprint.sha256(indexFields(
            [
                "itelas-source-workspace-search-v1", indexFingerprint, query,
                String(examinedDocumentCount), String(scopeDocumentCount),
                String(examinedLineCount), String(candidateCount), String(resultLimit),
                completion.rawValue
            ] + results.map(\.id)
        ))
        id = fingerprint
        self.indexFingerprint = indexFingerprint
        self.query = query
        self.results = results
        self.examinedDocumentCount = examinedDocumentCount
        self.scopeDocumentCount = scopeDocumentCount
        self.examinedLineCount = examinedLineCount
        self.candidateCount = candidateCount
        self.resultLimit = resultLimit
        self.completion = completion
        self.fingerprint = fingerprint
    }

    public func isCurrent(for index: SourceWorkspaceIndex, query: String) -> Bool {
        index.fingerprint == indexFingerprint
            && query.trimmingCharacters(in: .whitespacesAndNewlines) == self.query
    }
}

public enum SourceWorkspaceIndexDeltaKind: String, Equatable, Sendable {
    case added
    case reanalyzed
    case metadataOnly
    case removed

    public var label: String {
        switch self {
        case .added: "ADDED"
        case .reanalyzed: "REANALYZED"
        case .metadataOnly: "METADATA ONLY"
        case .removed: "REMOVED"
        }
    }
}

public struct SourceWorkspaceIndexDeltaEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: SourceWorkspaceIndexDeltaKind
    public let relativePath: String
    public let previousRelativePath: String?
    public let format: SourceFormat
    public let previousContentFingerprint: String?
    public let currentContentFingerprint: String?
    public let previousUTF8ByteCount: Int?
    public let currentUTF8ByteCount: Int?

    public var shortFingerprint: String { String(id.prefix(8)).uppercased() }
    public var byteDelta: Int? {
        guard let previousUTF8ByteCount, let currentUTF8ByteCount else { return nil }
        return currentUTF8ByteCount - previousUTF8ByteCount
    }

    fileprivate init(
        kind: SourceWorkspaceIndexDeltaKind,
        previous: SourceWorkspaceDocumentIndex?,
        current: SourceWorkspaceFile?
    ) {
        let relativePath = current?.relativePath ?? previous?.relativePath ?? "UNKNOWN"
        let format = current?.format ?? previous?.format ?? .text
        self.kind = kind
        self.relativePath = relativePath
        previousRelativePath = previous?.relativePath
        self.format = format
        previousContentFingerprint = previous?.contentFingerprint
        currentContentFingerprint = current?.contentFingerprint
        previousUTF8ByteCount = previous?.utf8ByteCount
        currentUTF8ByteCount = current?.utf8ByteCount
        id = AIContentFingerprint.sha256(indexFields([
            "itelas-source-index-delta-entry-v1", kind.rawValue, relativePath,
            previous?.relativePath ?? "", format.rawValue,
            previous?.contentFingerprint ?? "", current?.contentFingerprint ?? "",
            previous.map { String($0.utf8ByteCount) } ?? "",
            current.map { String($0.utf8ByteCount) } ?? ""
        ]))
    }
}

public struct SourceWorkspaceIndexBuildReport: Equatable, Sendable, Identifiable {
    public let id: String
    public let previousIndexFingerprint: String?
    public let currentIndexFingerprint: String
    public let inputFileCount: Int
    public let inputUTF8ByteCount: Int
    public let unchangedDocumentCount: Int
    public let metadataOnlyDocumentCount: Int
    public let reanalyzedDocumentCount: Int
    public let addedDocumentCount: Int
    public let removedDocumentCount: Int
    public let entries: [SourceWorkspaceIndexDeltaEntry]
    public let fingerprint: String

    public var isIncremental: Bool { previousIndexFingerprint != nil }
    public var reusedAnalysisCount: Int { unchangedDocumentCount + metadataOnlyDocumentCount }
    public var analyzedDocumentCount: Int { reanalyzedDocumentCount + addedDocumentCount }
    public var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }
    public var previousShortFingerprint: String? {
        previousIndexFingerprint.map { String($0.prefix(8)).uppercased() }
    }

    fileprivate init(
        previousIndexFingerprint: String?,
        currentIndexFingerprint: String,
        inputFileCount: Int,
        inputUTF8ByteCount: Int,
        unchangedDocumentCount: Int,
        metadataOnlyDocumentCount: Int,
        reanalyzedDocumentCount: Int,
        addedDocumentCount: Int,
        removedDocumentCount: Int,
        entries: [SourceWorkspaceIndexDeltaEntry]
    ) {
        let sortedEntries = entries.sorted { lhs, rhs in
            let pathOrder = lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath)
            if pathOrder != .orderedSame { return pathOrder == .orderedAscending }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        let fingerprint = AIContentFingerprint.sha256(indexFields(
            [
                "itelas-source-index-build-report-v1", previousIndexFingerprint ?? "",
                currentIndexFingerprint, String(inputFileCount), String(inputUTF8ByteCount),
                String(unchangedDocumentCount), String(metadataOnlyDocumentCount),
                String(reanalyzedDocumentCount), String(addedDocumentCount),
                String(removedDocumentCount)
            ] + sortedEntries.map(\.id)
        ))
        id = fingerprint
        self.previousIndexFingerprint = previousIndexFingerprint
        self.currentIndexFingerprint = currentIndexFingerprint
        self.inputFileCount = inputFileCount
        self.inputUTF8ByteCount = inputUTF8ByteCount
        self.unchangedDocumentCount = unchangedDocumentCount
        self.metadataOnlyDocumentCount = metadataOnlyDocumentCount
        self.reanalyzedDocumentCount = reanalyzedDocumentCount
        self.addedDocumentCount = addedDocumentCount
        self.removedDocumentCount = removedDocumentCount
        self.entries = sortedEntries
        self.fingerprint = fingerprint
    }

    public func isCurrent(for index: SourceWorkspaceIndex) -> Bool {
        currentIndexFingerprint == index.fingerprint
    }
}

public struct SourceWorkspaceIndexBuildResult: Equatable, Sendable {
    public let index: SourceWorkspaceIndex
    public let report: SourceWorkspaceIndexBuildReport

    fileprivate init(index: SourceWorkspaceIndex, report: SourceWorkspaceIndexBuildReport) {
        self.index = index
        self.report = report
    }
}

public struct SourceWorkspaceCompletionSymbol: Equatable, Hashable, Sendable, Identifiable {
    public let relativePath: String
    public let contentFingerprint: String
    public let symbol: SourceSymbol

    public var id: String { "\(relativePath.uppercased())|\(symbol.id)" }

    public init(relativePath: String, contentFingerprint: String, symbol: SourceSymbol) {
        self.relativePath = relativePath
        self.contentFingerprint = contentFingerprint
        self.symbol = symbol
    }
}

public struct ReviewedSourceDependencyScope: Equatable, Sendable, Identifiable {
    public let id: String
    public let indexFingerprint: String
    public let selectedPaths: [String]
    public let contentFingerprints: [String]
    public let reviewedBy: String
    public let reviewedAt: Date
    public let reviewFingerprint: String

    public init(
        index: SourceWorkspaceIndex,
        selectedPaths: [String],
        reviewedBy: String = "LOCAL OPERATOR",
        reviewedAt: Date = Date()
    ) throws {
        let normalized = Array(Set(selectedPaths.map { $0.uppercased() })).sorted()
        let reviewer = reviewedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= 64,
              normalized.count == selectedPaths.count,
              !reviewer.isEmpty,
              reviewer.utf8.count <= 128,
              !reviewer.unicodeScalars.contains(where: \._isUnsafeIndexControl) else {
            throw SourceWorkspaceIndexError.invalidDependencySelection
        }
        var paths: [String] = []
        var fingerprints: [String] = []
        for normalizedPath in normalized {
            guard let document = index.documents.first(where: { $0.relativePath.uppercased() == normalizedPath }) else {
                throw SourceWorkspaceIndexError.invalidDependencySelection
            }
            paths.append(document.relativePath)
            fingerprints.append(document.contentFingerprint)
        }
        let timestamp = sourceIndexDate(reviewedAt)
        let fingerprint = Self.fingerprint(
            indexFingerprint: index.fingerprint,
            paths: paths,
            contentFingerprints: fingerprints,
            reviewer: reviewer,
            reviewedAt: timestamp
        )
        id = fingerprint
        indexFingerprint = index.fingerprint
        self.selectedPaths = paths
        self.contentFingerprints = fingerprints
        self.reviewedBy = reviewer
        self.reviewedAt = timestamp
        reviewFingerprint = fingerprint
    }

    public var shortFingerprint: String { String(reviewFingerprint.prefix(8)).uppercased() }

    public func isCurrent(for index: SourceWorkspaceIndex) -> Bool {
        guard index.fingerprint == indexFingerprint,
              selectedPaths.count == contentFingerprints.count,
              reviewFingerprint == Self.fingerprint(
                indexFingerprint: indexFingerprint,
                paths: selectedPaths,
                contentFingerprints: contentFingerprints,
                reviewer: reviewedBy,
                reviewedAt: reviewedAt
              ) else { return false }
        return zip(selectedPaths, contentFingerprints).allSatisfy { path, fingerprint in
            index.document(at: path)?.contentFingerprint == fingerprint
        }
    }

    private static func fingerprint(
        indexFingerprint: String,
        paths: [String],
        contentFingerprints: [String],
        reviewer: String,
        reviewedAt: Date
    ) -> String {
        AIContentFingerprint.sha256(indexFields([
            indexFingerprint,
            paths.joined(separator: "\n"),
            contentFingerprints.joined(separator: "\n"),
            reviewer,
            String(format: "%.3f", reviewedAt.timeIntervalSince1970)
        ]))
    }
}

public struct SourceWorkspaceRenameOccurrence: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let line: Int
    public let column: Int
    public let excerpt: String
    public let utf16Location: Int
    public let utf16Length: Int

    public var id: String { "\(relativePath.uppercased())|\(utf16Location)|\(utf16Length)" }

    public init(
        relativePath: String,
        line: Int,
        column: Int,
        excerpt: String,
        utf16Location: Int,
        utf16Length: Int
    ) {
        self.relativePath = relativePath
        self.line = max(1, line)
        self.column = max(1, column)
        self.excerpt = excerpt
        self.utf16Location = max(0, utf16Location)
        self.utf16Length = max(1, utf16Length)
    }
}

public struct SourceWorkspaceRenameBaseline: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let contentFingerprint: String
    public let modifiedAt: Date?
    public let sourceDate: String?

    public var id: String { relativePath.uppercased() }
}

public struct SourceWorkspaceRenamePlan: Equatable, Sendable, Identifiable {
    public let id: String
    public let indexFingerprint: String
    public let currentName: String
    public let proposedName: String
    public let occurrences: [SourceWorkspaceRenameOccurrence]
    public let baselines: [SourceWorkspaceRenameBaseline]
    public let fingerprint: String

    public var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }

    public func isCurrent(for index: SourceWorkspaceIndex) -> Bool {
        guard index.fingerprint == indexFingerprint,
              fingerprint == Self.makeFingerprint(
                indexFingerprint: indexFingerprint,
                currentName: currentName,
                proposedName: proposedName,
                occurrences: occurrences,
                baselines: baselines
              ) else { return false }
        return baselines.allSatisfy { baseline in
            guard let document = index.document(at: baseline.relativePath) else { return false }
            return document.contentFingerprint == baseline.contentFingerprint
                && document.modifiedAt == baseline.modifiedAt
                && document.sourceDate == baseline.sourceDate
        }
    }

    fileprivate init(
        indexFingerprint: String,
        currentName: String,
        proposedName: String,
        occurrences: [SourceWorkspaceRenameOccurrence],
        baselines: [SourceWorkspaceRenameBaseline]
    ) {
        self.indexFingerprint = indexFingerprint
        self.currentName = currentName
        self.proposedName = proposedName
        self.occurrences = occurrences
        self.baselines = baselines
        let fingerprint = Self.makeFingerprint(
            indexFingerprint: indexFingerprint,
            currentName: currentName,
            proposedName: proposedName,
            occurrences: occurrences,
            baselines: baselines
        )
        id = fingerprint
        self.fingerprint = fingerprint
    }

    private static func makeFingerprint(
        indexFingerprint: String,
        currentName: String,
        proposedName: String,
        occurrences: [SourceWorkspaceRenameOccurrence],
        baselines: [SourceWorkspaceRenameBaseline]
    ) -> String {
        AIContentFingerprint.sha256(indexFields([
            indexFingerprint,
            currentName,
            proposedName,
            occurrences.map {
                "\($0.relativePath):\($0.line):\($0.column):\($0.utf16Location):\($0.utf16Length)"
            }.joined(separator: "\n"),
            baselines.map {
                "\($0.relativePath):\($0.contentFingerprint):\($0.sourceDate ?? ""):\($0.modifiedAt?.timeIntervalSince1970 ?? 0)"
            }.joined(separator: "\n")
        ]))
    }
}

public struct ReviewedSourceWorkspaceRename: Equatable, Sendable, Identifiable {
    public let id: String
    public let planFingerprint: String
    public let indexFingerprint: String
    public let affectedPaths: [String]
    public let occurrenceCount: Int
    public let reviewedBy: String
    public let reviewedAt: Date
    public let reviewFingerprint: String

    public init(
        index: SourceWorkspaceIndex,
        plan: SourceWorkspaceRenamePlan,
        reviewedBy: String = "LOCAL OPERATOR",
        reviewedAt: Date = Date()
    ) throws {
        let reviewer = reviewedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plan.isCurrent(for: index),
              !reviewer.isEmpty,
              reviewer.utf8.count <= 128,
              !reviewer.unicodeScalars.contains(where: \._isUnsafeIndexControl) else {
            throw SourceWorkspaceIndexError.invalidRenameReview
        }
        let timestamp = sourceIndexDate(reviewedAt)
        let paths = plan.baselines.map(\.relativePath)
        let fingerprint = Self.fingerprint(
            planFingerprint: plan.fingerprint,
            indexFingerprint: index.fingerprint,
            affectedPaths: paths,
            occurrenceCount: plan.occurrences.count,
            reviewedBy: reviewer,
            reviewedAt: timestamp
        )
        id = fingerprint
        planFingerprint = plan.fingerprint
        indexFingerprint = index.fingerprint
        affectedPaths = paths
        occurrenceCount = plan.occurrences.count
        self.reviewedBy = reviewer
        self.reviewedAt = timestamp
        reviewFingerprint = fingerprint
    }

    public var shortFingerprint: String { String(reviewFingerprint.prefix(8)).uppercased() }

    public func isCurrent(plan: SourceWorkspaceRenamePlan, index: SourceWorkspaceIndex) -> Bool {
        plan.isCurrent(for: index)
            && plan.fingerprint == planFingerprint
            && index.fingerprint == indexFingerprint
            && affectedPaths == plan.baselines.map(\.relativePath)
            && occurrenceCount == plan.occurrences.count
            && reviewFingerprint == Self.fingerprint(
                planFingerprint: planFingerprint,
                indexFingerprint: indexFingerprint,
                affectedPaths: affectedPaths,
                occurrenceCount: occurrenceCount,
                reviewedBy: reviewedBy,
                reviewedAt: reviewedAt
            )
    }

    private static func fingerprint(
        planFingerprint: String,
        indexFingerprint: String,
        affectedPaths: [String],
        occurrenceCount: Int,
        reviewedBy: String,
        reviewedAt: Date
    ) -> String {
        AIContentFingerprint.sha256(indexFields([
            planFingerprint,
            indexFingerprint,
            affectedPaths.joined(separator: "\n"),
            String(occurrenceCount),
            reviewedBy,
            String(format: "%.3f", reviewedAt.timeIntervalSince1970)
        ]))
    }
}

public struct SourceWorkspaceIndex: Equatable, Sendable {
    public let rootName: String
    public let createdAt: Date
    public let documents: [SourceWorkspaceDocumentIndex]
    public let skippedFiles: [SourceWorkspaceSkippedFile]
    public let fingerprint: String
    public let limits: SourceWorkspaceIndexLimits

    public var fileCount: Int { documents.count }
    public var symbolCount: Int { documents.reduce(0) { $0 + $1.snapshot.symbols.count } }
    public var referenceCount: Int { documents.reduce(0) { $0 + $1.snapshot.references.count } }
    public var dependencyCount: Int { documents.reduce(0) { $0 + $1.dependencies.count } }
    public var totalUTF8Bytes: Int { documents.reduce(0) { $0 + $1.utf8ByteCount } }
    public var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }

    fileprivate init(
        rootName: String,
        createdAt: Date,
        documents: [SourceWorkspaceDocumentIndex],
        skippedFiles: [SourceWorkspaceSkippedFile],
        limits: SourceWorkspaceIndexLimits
    ) {
        self.rootName = rootName
        self.createdAt = sourceIndexDate(createdAt)
        self.documents = documents
        self.skippedFiles = skippedFiles
        self.limits = limits
        fingerprint = AIContentFingerprint.sha256(indexFields(
            [rootName]
                + documents.flatMap { document in
                    [
                        document.relativePath,
                        document.format.rawValue,
                        document.contentFingerprint,
                        document.sourceDate ?? "",
                        document.modifiedAt.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? ""
                    ] + document.origin.fingerprintFields
                }
                + skippedFiles.flatMap { [$0.relativePath, $0.reason] }
        ))
    }

    public func document(at relativePath: String) -> SourceWorkspaceDocumentIndex? {
        documents.first { $0.relativePath.caseInsensitiveCompare(relativePath) == .orderedSame }
    }

    public func outboundDependencies(for relativePath: String) -> [SourceWorkspaceDependencyEdge] {
        document(at: relativePath)?.dependencies ?? []
    }

    public func inboundDependencies(for relativePath: String) -> [SourceWorkspaceDependencyEdge] {
        documents
            .flatMap(\.dependencies)
            .filter { edge in
                edge.targetPaths.contains { $0.caseInsensitiveCompare(relativePath) == .orderedSame }
            }
            .sorted(by: Self.edgePrecedes)
    }

    public func suggestedDependencyPaths(for relativePath: String) -> [String] {
        let outbound = outboundDependencies(for: relativePath)
            .filter { $0.resolution == .exact }
            .flatMap(\.targetPaths)
        let normalizedPaths = Set(outbound.map { $0.uppercased() })
        let resolvedPaths = normalizedPaths.compactMap { normalized in
            documents.first(where: { $0.relativePath.uppercased() == normalized })?.relativePath
        }
        return resolvedPaths.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func search(_ query: String) throws -> [SourceWorkspaceSearchResult] {
        try searchReport(query).results
    }

    public func searchReport(_ query: String) throws -> SourceWorkspaceSearchReport {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= 256,
              !value.unicodeScalars.contains(where: \._isUnsafeIndexControl) else {
            throw SourceWorkspaceIndexError.invalidSearch
        }
        let needle = value.uppercased()
        let candidateLimit = max(limits.maximumSearchResults, limits.maximumSearchResults * 4)
        var results: [SourceWorkspaceSearchResult] = []
        results.reserveCapacity(min(limits.maximumSearchResults * 2, 1_000))
        var candidateCount = 0
        var examinedDocumentCount = 0
        var examinedLineCount = 0
        var candidateLimitReached = false
        var perDocumentTextLimitReached = false

        func appendCandidate(_ result: SourceWorkspaceSearchResult) -> Bool {
            candidateCount += 1
            guard results.count < candidateLimit else {
                candidateLimitReached = true
                return false
            }
            results.append(result)
            return true
        }

        documentLoop: for document in documents {
            try Task.checkCancellation()
            examinedDocumentCount += 1
            if document.relativePath.uppercased().contains(needle),
               !appendCandidate(SourceWorkspaceSearchResult(
                    kind: .file,
                    relativePath: document.relativePath,
                    line: 1,
                    column: 1,
                    label: document.displayName,
                    detail: "\(document.format.rawValue) · \(document.lineCount) lines",
                    excerpt: document.relativePath,
                    score: document.displayName.uppercased() == needle ? 0 : 8
               )) {
                break documentLoop
            }
            for symbol in document.snapshot.symbols where symbol.name.uppercased().contains(needle) {
                guard appendCandidate(SourceWorkspaceSearchResult(
                    kind: .symbol,
                    relativePath: document.relativePath,
                    line: symbol.range.startLine,
                    column: symbol.range.startColumn,
                    label: symbol.name,
                    detail: symbol.kind.label,
                    excerpt: symbol.detail,
                    score: symbol.name.uppercased() == needle ? 1 : symbol.name.uppercased().hasPrefix(needle) ? 4 : 12
                )) else { break documentLoop }
            }
            for reference in document.snapshot.references where reference.target.displayName.uppercased().contains(needle) {
                guard appendCandidate(SourceWorkspaceSearchResult(
                    kind: .reference,
                    relativePath: document.relativePath,
                    line: reference.range.startLine,
                    column: reference.range.startColumn,
                    label: reference.target.displayName,
                    detail: reference.kind.label,
                    excerpt: lineExcerpt(document.text, line: reference.range.startLine),
                    score: reference.target.displayName.uppercased() == needle ? 14 : 20
                )) else { break documentLoop }
            }
            var matchesInDocument = 0
            let lines = document.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (offset, rawLine) in lines.enumerated() {
                if offset.isMultiple(of: 256) { try Task.checkCancellation() }
                examinedLineCount += 1
                let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                guard line.uppercased().contains(needle) else { continue }
                guard matchesInDocument < 6 else {
                    perDocumentTextLimitReached = true
                    break
                }
                let range = (line as NSString).range(of: value, options: .caseInsensitive)
                guard appendCandidate(SourceWorkspaceSearchResult(
                    kind: .text,
                    relativePath: document.relativePath,
                    line: offset + 1,
                    column: range.location == NSNotFound ? 1 : range.location + 1,
                    label: value,
                    detail: "TEXT MATCH",
                    excerpt: boundedIndexExcerpt(line),
                    score: 30
                )) else { break documentLoop }
                matchesInDocument += 1
            }
        }

        results.sort(by: Self.resultPrecedes)
        var seen: Set<String> = []
        let distinct = results.filter { seen.insert($0.id).inserted }
        let completion: SourceWorkspaceSearchCompletion
        if candidateLimitReached {
            completion = .candidateLimitReached
        } else if distinct.count > limits.maximumSearchResults {
            completion = .resultLimitReached
        } else if perDocumentTextLimitReached {
            completion = .perDocumentTextLimitReached
        } else {
            completion = .complete
        }
        return SourceWorkspaceSearchReport(
            indexFingerprint: fingerprint,
            query: value,
            results: Array(distinct.prefix(limits.maximumSearchResults)),
            examinedDocumentCount: examinedDocumentCount,
            scopeDocumentCount: documents.count,
            examinedLineCount: examinedLineCount,
            candidateCount: candidateCount,
            resultLimit: limits.maximumSearchResults,
            completion: completion
        )
    }

    public func reviewedCompletionSymbols(
        using review: ReviewedSourceDependencyScope
    ) throws -> [SourceWorkspaceCompletionSymbol] {
        guard review.isCurrent(for: self) else { throw SourceWorkspaceIndexError.staleDependencyReview }
        let permittedKinds: Set<SourceSymbolKind> = [
            .program, .procedure, .prototype, .procedureInterface, .dataStructure,
            .file, .recordFormat, .field, .division, .section, .paragraph, .label, .sqlObject
        ]
        let symbols = review.selectedPaths.flatMap { path -> [SourceWorkspaceCompletionSymbol] in
            guard let document = document(at: path) else { return [] }
            return document.snapshot.symbols
                .filter { permittedKinds.contains($0.kind) }
                .map {
                    SourceWorkspaceCompletionSymbol(
                        relativePath: document.relativePath,
                        contentFingerprint: document.contentFingerprint,
                        symbol: $0
                    )
                }
        }
        return Array(symbols.prefix(limits.maximumSearchResults * 20))
    }

    public func makeRenamePlan(currentName: String, proposedName: String) throws -> SourceWorkspaceRenamePlan {
        let current = try Self.validatedIdentifier(currentName)
        let proposed = try Self.validatedIdentifier(proposedName)
        guard current.caseInsensitiveCompare(proposed) != .orderedSame else {
            throw SourceWorkspaceIndexError.unchangedRename
        }
        let escaped = NSRegularExpression.escapedPattern(for: current)
        let expression = try NSRegularExpression(
            pattern: "(?i)(?<![A-Z0-9_$#@-])\(escaped)(?![A-Z0-9_$#@-])"
        )
        var occurrences: [SourceWorkspaceRenameOccurrence] = []
        var baselines: [SourceWorkspaceRenameBaseline] = []
        for document in documents where !document.origin.isHostBacked {
            guard !document.snapshot.wasLimited,
                  !document.snapshot.highlightingWasLimited else {
                throw SourceWorkspaceIndexError.renameAnalysisLimited(document.relativePath)
            }
            let fullRange = NSRange(location: 0, length: document.text.utf16.count)
            let excluded = document.snapshot.highlights.compactMap { highlight -> NSRange? in
                guard highlight.kind == .comment || highlight.kind == .stringLiteral else { return nil }
                return highlight.range.utf16Range(in: document.text)
            }
            var documentOccurrences: [SourceWorkspaceRenameOccurrence] = []
            expression.enumerateMatches(in: document.text, range: fullRange) { match, _, stop in
                guard let range = match?.range,
                      !excluded.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return }
                let location = sourceLocation(in: document.text, utf16Location: range.location)
                documentOccurrences.append(SourceWorkspaceRenameOccurrence(
                    relativePath: document.relativePath,
                    line: location.line,
                    column: location.column,
                    excerpt: lineExcerpt(document.text, line: location.line),
                    utf16Location: range.location,
                    utf16Length: range.length
                ))
                if occurrences.count + documentOccurrences.count > limits.maximumRenameOccurrences {
                    stop.pointee = true
                }
            }
            if occurrences.count + documentOccurrences.count > limits.maximumRenameOccurrences {
                throw SourceWorkspaceIndexError.tooManyRenameOccurrences(limits.maximumRenameOccurrences)
            }
            if !documentOccurrences.isEmpty {
                occurrences.append(contentsOf: documentOccurrences)
                baselines.append(SourceWorkspaceRenameBaseline(
                    relativePath: document.relativePath,
                    contentFingerprint: document.contentFingerprint,
                    modifiedAt: document.modifiedAt,
                    sourceDate: document.sourceDate
                ))
            }
        }
        guard !occurrences.isEmpty else { throw SourceWorkspaceIndexError.noRenameOccurrences }
        return SourceWorkspaceRenamePlan(
            indexFingerprint: fingerprint,
            currentName: current,
            proposedName: proposed,
            occurrences: occurrences,
            baselines: baselines
        )
    }

    public func replacementText(
        for plan: SourceWorkspaceRenamePlan,
        relativePath: String
    ) throws -> String {
        guard plan.isCurrent(for: self) else { throw SourceWorkspaceIndexError.staleRenamePlan }
        guard let baseline = plan.baselines.first(where: {
            $0.relativePath.caseInsensitiveCompare(relativePath) == .orderedSame
        }),
        let document = document(at: baseline.relativePath),
        document.contentFingerprint == baseline.contentFingerprint,
        document.modifiedAt == baseline.modifiedAt,
        document.sourceDate == baseline.sourceDate else {
            throw SourceWorkspaceIndexError.invalidRenameOccurrence(relativePath)
        }
        let occurrences = plan.occurrences
            .filter { $0.relativePath.caseInsensitiveCompare(document.relativePath) == .orderedSame }
            .sorted { $0.utf16Location > $1.utf16Location }
        guard !occurrences.isEmpty else {
            throw SourceWorkspaceIndexError.invalidRenameOccurrence(document.relativePath)
        }

        let source = document.text as NSString
        var nextUpperBound = source.length
        for occurrence in occurrences {
            let range = NSRange(location: occurrence.utf16Location, length: occurrence.utf16Length)
            let end = range.location + range.length
            let location = sourceLocation(in: document.text, utf16Location: range.location)
            guard range.location >= 0,
                  range.length > 0,
                  end <= source.length,
                  end <= nextUpperBound,
                  location.line == occurrence.line,
                  location.column == occurrence.column,
                  source.substring(with: range).caseInsensitiveCompare(plan.currentName) == .orderedSame else {
                throw SourceWorkspaceIndexError.invalidRenameOccurrence(document.relativePath)
            }
            nextUpperBound = range.location
        }

        let replacement = NSMutableString(string: document.text)
        for occurrence in occurrences {
            replacement.replaceCharacters(
                in: NSRange(location: occurrence.utf16Location, length: occurrence.utf16Length),
                with: plan.proposedName
            )
        }
        return String(replacement)
    }

    private static func validatedIdentifier(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 128,
              let first = name.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_$#@")).contains(first),
              name.unicodeScalars.dropFirst().allSatisfy({
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$#@-")).contains($0)
              }) else {
            throw SourceWorkspaceIndexError.invalidRenameIdentifier(value)
        }
        return name
    }

    private static func resultPrecedes(_ lhs: SourceWorkspaceSearchResult, _ rhs: SourceWorkspaceSearchResult) -> Bool {
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        let pathOrder = lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath)
        if pathOrder != .orderedSame { return pathOrder == .orderedAscending }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        return lhs.id < rhs.id
    }

    private static func edgePrecedes(_ lhs: SourceWorkspaceDependencyEdge, _ rhs: SourceWorkspaceDependencyEdge) -> Bool {
        let sourceOrder = lhs.sourcePath.localizedCaseInsensitiveCompare(rhs.sourcePath)
        if sourceOrder != .orderedSame { return sourceOrder == .orderedAscending }
        if lhs.range.startLine != rhs.range.startLine { return lhs.range.startLine < rhs.range.startLine }
        return lhs.id < rhs.id
    }
}

public struct SourceWorkspaceIndexBuilder: Sendable {
    public let limits: SourceWorkspaceIndexLimits
    public let analyzer: SourceIntelligenceAnalyzer

    public init(
        limits: SourceWorkspaceIndexLimits = SourceWorkspaceIndexLimits(),
        analyzer: SourceIntelligenceAnalyzer = SourceIntelligenceAnalyzer()
    ) {
        self.limits = limits
        self.analyzer = analyzer
    }

    public func build(
        rootName: String,
        files: [SourceWorkspaceFile],
        skippedFiles: [SourceWorkspaceSkippedFile] = [],
        createdAt: Date = Date()
    ) throws -> SourceWorkspaceIndex {
        try buildIncrementally(
            rootName: rootName,
            files: files,
            previousIndex: nil,
            skippedFiles: skippedFiles,
            createdAt: createdAt
        ).index
    }

    public func buildIncrementally(
        rootName: String,
        files: [SourceWorkspaceFile],
        previousIndex: SourceWorkspaceIndex?,
        skippedFiles: [SourceWorkspaceSkippedFile] = [],
        createdAt: Date = Date()
    ) throws -> SourceWorkspaceIndexBuildResult {
        let name = rootName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.utf8.count <= 256,
              !name.unicodeScalars.contains(where: \._isUnsafeIndexControl) else {
            throw SourceWorkspaceIndexError.invalidRootName
        }
        guard !files.isEmpty else { throw SourceWorkspaceIndexError.emptyWorkspace }
        guard files.count <= limits.maximumFiles else {
            throw SourceWorkspaceIndexError.tooManyFiles(limits.maximumFiles)
        }
        var seenPaths: Set<String> = []
        var totalBytes = 0
        let sortedFiles = files.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
        let previousLocalDocuments = previousIndex?.documents.filter { !$0.origin.isHostBacked } ?? []
        let previousByPath = Dictionary(uniqueKeysWithValues: previousLocalDocuments.map { ($0.id, $0) })
        var staged: [(SourceWorkspaceFile, SourceIntelligenceSnapshot)] = []
        var totalSymbols = 0
        var totalReferences = 0
        var unchangedDocumentCount = 0
        var metadataOnlyDocumentCount = 0
        var reanalyzedDocumentCount = 0
        var addedDocumentCount = 0
        var deltaEntries: [SourceWorkspaceIndexDeltaEntry] = []
        for file in sortedFiles {
            try Task.checkCancellation()
            guard seenPaths.insert(file.relativePath.uppercased()).inserted else {
                throw SourceWorkspaceIndexError.duplicateRelativePath(file.relativePath)
            }
            guard file.utf8ByteCount <= limits.maximumFileUTF8Bytes else {
                throw SourceWorkspaceIndexError.fileTooLarge(
                    path: file.relativePath,
                    maximum: limits.maximumFileUTF8Bytes
                )
            }
            totalBytes += file.utf8ByteCount
            guard totalBytes <= limits.maximumTotalUTF8Bytes else {
                throw SourceWorkspaceIndexError.workspaceTooLarge(limits.maximumTotalUTF8Bytes)
            }
            let previous = previousByPath[file.id]
            let canReuseAnalysis = previous.map {
                $0.relativePath == file.relativePath
                    && $0.format == file.format
                    && $0.origin == file.origin
                    && $0.text.utf8.elementsEqual(file.text.utf8)
            } ?? false
            let snapshot: SourceIntelligenceSnapshot
            if let previous, canReuseAnalysis {
                snapshot = previous.snapshot
                if previous.modifiedAt == file.modifiedAt,
                   previous.sourceDate == file.sourceDate {
                    unchangedDocumentCount += 1
                } else {
                    metadataOnlyDocumentCount += 1
                    deltaEntries.append(SourceWorkspaceIndexDeltaEntry(
                        kind: .metadataOnly,
                        previous: previous,
                        current: file
                    ))
                }
            } else {
                snapshot = analyzer.analyze(
                    text: file.text,
                    format: file.format,
                    documentName: file.relativePath
                )
                if let previous {
                    reanalyzedDocumentCount += 1
                    deltaEntries.append(SourceWorkspaceIndexDeltaEntry(
                        kind: .reanalyzed,
                        previous: previous,
                        current: file
                    ))
                } else {
                    addedDocumentCount += 1
                    deltaEntries.append(SourceWorkspaceIndexDeltaEntry(
                        kind: .added,
                        previous: nil,
                        current: file
                    ))
                }
            }
            totalSymbols += snapshot.symbols.count
            totalReferences += snapshot.references.count
            guard totalSymbols <= limits.maximumSymbols else {
                throw SourceWorkspaceIndexError.tooManySymbols(limits.maximumSymbols)
            }
            guard totalReferences <= limits.maximumReferences else {
                throw SourceWorkspaceIndexError.tooManyReferences(limits.maximumReferences)
            }
            staged.append((file, snapshot))
        }

        let removedDocuments = previousLocalDocuments
            .filter { !seenPaths.contains($0.id) }
            .sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
        deltaEntries.append(contentsOf: removedDocuments.map {
            SourceWorkspaceIndexDeltaEntry(kind: .removed, previous: $0, current: nil)
        })

        let symbolPaths = Dictionary(grouping: staged.flatMap { file, snapshot in
            snapshot.symbols.map { ($0.name.uppercased(), file.relativePath) }
        }, by: \.0).mapValues { values in
            Array(Set(values.map { $0.1.uppercased() })).compactMap { normalized in
                staged.first(where: { $0.0.relativePath.uppercased() == normalized })?.0.relativePath
            }
        }
        var documents: [SourceWorkspaceDocumentIndex] = []
        documents.reserveCapacity(staged.count)
        for (file, snapshot) in staged {
            try Task.checkCancellation()
            let dependencies = snapshot.references.map { reference in
                let candidates = Self.candidatePaths(
                    for: reference,
                    sourcePath: file.relativePath,
                    files: sortedFiles,
                    symbolPaths: symbolPaths
                )
                let resolution: SourceWorkspaceDependencyResolutionKind
                if candidates.count == 1 {
                    resolution = .exact
                } else if candidates.count > 1 {
                    resolution = .ambiguous
                } else {
                    switch reference.target {
                    case .member, .ifsPath, .object:
                        resolution = .hostBacked
                    case .symbol, .unqualified:
                        resolution = .unresolved
                    }
                }
                return SourceWorkspaceDependencyEdge(
                    sourcePath: file.relativePath,
                    kind: reference.kind,
                    targetLabel: reference.target.displayName,
                    target: reference.target,
                    targetPaths: candidates,
                    resolution: resolution,
                    range: reference.range
                )
            }.sorted { lhs, rhs in
                if lhs.range.startLine != rhs.range.startLine { return lhs.range.startLine < rhs.range.startLine }
                return lhs.id < rhs.id
            }
            documents.append(SourceWorkspaceDocumentIndex(
                file: file,
                snapshot: snapshot,
                dependencies: dependencies
            ))
        }
        let index = SourceWorkspaceIndex(
            rootName: name,
            createdAt: createdAt,
            documents: documents,
            skippedFiles: skippedFiles.sorted { $0.relativePath < $1.relativePath },
            limits: limits
        )
        let report = SourceWorkspaceIndexBuildReport(
            previousIndexFingerprint: previousIndex?.fingerprint,
            currentIndexFingerprint: index.fingerprint,
            inputFileCount: sortedFiles.count,
            inputUTF8ByteCount: totalBytes,
            unchangedDocumentCount: unchangedDocumentCount,
            metadataOnlyDocumentCount: metadataOnlyDocumentCount,
            reanalyzedDocumentCount: reanalyzedDocumentCount,
            addedDocumentCount: addedDocumentCount,
            removedDocumentCount: removedDocuments.count,
            entries: deltaEntries
        )
        return SourceWorkspaceIndexBuildResult(index: index, report: report)
    }

    private static func candidatePaths(
        for reference: SourceReference,
        sourcePath: String,
        files: [SourceWorkspaceFile],
        symbolPaths: [String: [String]]
    ) -> [String] {
        let candidates: [String]
        switch reference.target {
        case .member(_, let sourceFile, let member):
            candidates = files.compactMap { file in
                let components = file.relativePath.split(separator: "/").map(String.init)
                guard components.count >= 2,
                      components[components.count - 2].caseInsensitiveCompare(sourceFile) == .orderedSame,
                      URL(fileURLWithPath: file.relativePath).deletingPathExtension().lastPathComponent
                        .caseInsensitiveCompare(member) == .orderedSame else { return nil }
                return file.relativePath
            }
        case .ifsPath(let path):
            let target = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            candidates = files.compactMap { file in
                let normalized = file.relativePath.uppercased()
                let targetNormalized = target.uppercased()
                return normalized == targetNormalized || normalized.hasSuffix("/\(targetNormalized)")
                    ? file.relativePath : nil
            }
        case .object(let name), .symbol(let name):
            candidates = symbolPaths[name.uppercased()] ?? []
        case .unqualified(let name):
            let normalizedTarget = name
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .uppercased()
            let fileMatches = files.compactMap { file in
                let fileURL = URL(fileURLWithPath: file.relativePath)
                let stemPath = fileURL.deletingPathExtension().path
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .uppercased()
                let baseNameMatches = fileURL.deletingPathExtension().lastPathComponent
                    .caseInsensitiveCompare(name) == .orderedSame
                let pathMatches = stemPath == normalizedTarget || stemPath.hasSuffix("/\(normalizedTarget)")
                return baseNameMatches || pathMatches ? file.relativePath : nil
            }
            candidates = fileMatches + (symbolPaths[name.uppercased()] ?? [])
        }
        let normalizedCandidates = Set(candidates.map { $0.uppercased() })
        let unique = normalizedCandidates
            .compactMap { normalized in
                files.first(where: { $0.relativePath.uppercased() == normalized })?.relativePath
            }
            .filter {
                $0.caseInsensitiveCompare(sourcePath) != .orderedSame
                    || reference.resolution == .currentDocument
            }
        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private extension Unicode.Scalar {
    var _isUnsafeIndexControl: Bool {
        value < 32 || value == 127
    }
}

private func sourceIndexDate(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
}

private func indexFields(_ values: [String]) -> String {
    values.map { "\($0.utf8.count):\($0)" }.joined(separator: "")
}

private func boundedIndexExcerpt(_ text: String) -> String {
    let singleLine = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(singleLine.prefix(180))
}

private func lineExcerpt(_ text: String, line: Int) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.indices.contains(line - 1) else { return "" }
    return boundedIndexExcerpt(String(lines[line - 1]).trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
}

private func sourceLocation(in text: String, utf16Location: Int) -> (line: Int, column: Int) {
    let prefix = (text as NSString).substring(to: min(max(0, utf16Location), text.utf16.count))
    let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
    return (max(1, lines.count), (lines.last?.utf16.count ?? 0) + 1)
}
