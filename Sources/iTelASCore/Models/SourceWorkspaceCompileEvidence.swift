import Foundation

public enum SourceWorkspaceCompileEvidenceError: Error, Equatable, LocalizedError, Sendable {
    case invalidReleaseLevel(String)
    case invalidTargetReleaseToken(String)
    case conflictingTargetReleaseTokens
    case commandTextTooLarge(Int)
    case invalidRunFingerprint
    case noSourceFiles
    case invalidMapping
    case duplicateMappingTarget(String)
    case invalidReviewer
    case staleReview

    public var errorDescription: String? {
        switch self {
        case .invalidReleaseLevel(let value):
            "The IBM i release level must use the exact VvRrMm form: \(value)."
        case .invalidTargetReleaseToken(let value):
            "The retained TGTRLS value is unsupported or malformed: \(value)."
        case .conflictingTargetReleaseTokens:
            "The retained compiler text contains conflicting TGTRLS values."
        case .commandTextTooLarge(let maximum):
            "The retained compiler text exceeds the \(maximum)-byte release-evidence limit."
        case .invalidRunFingerprint:
            "The compile run is not bound to one exact SHA-256 evidence identity."
        case .noSourceFiles:
            "The compile evidence contains no source-file identities to map."
        case .invalidMapping:
            "Choose at least one exact compile-file to indexed-document mapping from the current evidence."
        case .duplicateMappingTarget(let path):
            "More than one compile-file identity was mapped to the same indexed document: \(path)."
        case .invalidReviewer:
            "The compiler-evidence reviewer identity is empty, unsafe, or unbounded."
        case .staleReview:
            "The reviewed compiler evidence no longer matches this exact source index and compile run."
        }
    }
}

public struct IBMReleaseLevel: Hashable, Codable, Sendable, CustomStringConvertible {
    public let version: Int
    public let release: Int
    public let modification: Int

    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.utf8.count <= 24,
              value.first == "V",
              let releaseMarker = value.firstIndex(of: "R"),
              let modificationMarker = value.firstIndex(of: "M"),
              releaseMarker < modificationMarker else {
            throw SourceWorkspaceCompileEvidenceError.invalidReleaseLevel(rawValue)
        }
        let versionText = value[value.index(after: value.startIndex)..<releaseMarker]
        let releaseText = value[value.index(after: releaseMarker)..<modificationMarker]
        let modificationText = value[value.index(after: modificationMarker)...]
        guard Self.isASCIIInteger(versionText),
              Self.isASCIIInteger(releaseText),
              Self.isASCIIInteger(modificationText),
              let version = Int(versionText),
              let release = Int(releaseText),
              let modification = Int(modificationText),
              (0...99).contains(version),
              (0...99).contains(release),
              (0...99).contains(modification) else {
            throw SourceWorkspaceCompileEvidenceError.invalidReleaseLevel(rawValue)
        }
        self.version = version
        self.release = release
        self.modification = modification
    }

    public var value: String { "V\(version)R\(release)M\(modification)" }
    public var description: String { value }

    public var previousRelease: IBMReleaseLevel? {
        guard release > 0 else { return nil }
        return try? IBMReleaseLevel("V\(version)R\(release - 1)M0")
    }

    private static func isASCIIInteger(_ value: Substring) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}

public enum CompileTargetReleaseToken: Hashable, Sendable {
    case current
    case previous
    case specific(IBMReleaseLevel)
    case notRecorded

    public var label: String {
        switch self {
        case .current: "TGTRLS(*CURRENT)"
        case .previous: "TGTRLS(*PRV)"
        case .specific(let release): "TGTRLS(\(release.value))"
        case .notRecorded: "TGTRLS NOT RECORDED"
        }
    }

    fileprivate var fingerprintValue: String {
        switch self {
        case .current: "current"
        case .previous: "previous"
        case .specific(let release): "specific|\(release.value)"
        case .notRecorded: "not-recorded"
        }
    }
}

public enum CompileTargetReleaseResolution: String, Hashable, Sendable {
    case exact
    case relative
    case missing

    public var label: String {
        switch self {
        case .exact: "EXACT TARGET"
        case .relative: "RELATIVE TARGET"
        case .missing: "NOT RECORDED"
        }
    }
}

public struct CompileTargetReleaseEvidence: Hashable, Sendable {
    public let commandToken: CompileTargetReleaseToken
    public let observedHostRelease: IBMReleaseLevel?
    public let effectiveTargetRelease: IBMReleaseLevel?
    public let resolution: CompileTargetReleaseResolution

    public init(
        commandText: String,
        observedHostRelease: String? = nil,
        maximumCommandUTF8Bytes: Int = 16 * 1_024
    ) throws {
        guard commandText.lengthOfBytes(using: .utf8) <= maximumCommandUTF8Bytes else {
            throw SourceWorkspaceCompileEvidenceError.commandTextTooLarge(maximumCommandUTF8Bytes)
        }
        guard !commandText.contains("\0") else {
            throw SourceWorkspaceCompileEvidenceError.invalidTargetReleaseToken("NUL")
        }
        let rawTokens = Self.targetReleaseValues(in: commandText)
        let tokens = try rawTokens.map(Self.parseToken)
        let uniqueTokens = Set(tokens)
        guard uniqueTokens.count <= 1 else {
            throw SourceWorkspaceCompileEvidenceError.conflictingTargetReleaseTokens
        }
        let token = uniqueTokens.first ?? .notRecorded
        let hostRelease: IBMReleaseLevel?
        if let rawHostRelease = observedHostRelease?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawHostRelease.isEmpty {
            hostRelease = try IBMReleaseLevel(rawHostRelease)
        } else {
            hostRelease = nil
        }
        let effective: IBMReleaseLevel?
        let resolution: CompileTargetReleaseResolution
        switch token {
        case .specific(let release):
            effective = release
            resolution = .exact
        case .current:
            effective = hostRelease
            resolution = hostRelease == nil ? .relative : .exact
        case .previous:
            effective = hostRelease?.previousRelease
            resolution = effective == nil ? .relative : .exact
        case .notRecorded:
            effective = nil
            resolution = .missing
        }
        commandToken = token
        self.observedHostRelease = hostRelease
        effectiveTargetRelease = effective
        self.resolution = resolution
    }

    public var effectiveTargetLabel: String {
        effectiveTargetRelease?.value ?? commandToken.label
    }

    fileprivate var fingerprintFields: [String] {
        [
            commandToken.fingerprintValue,
            observedHostRelease?.value ?? "",
            effectiveTargetRelease?.value ?? "",
            resolution.rawValue
        ]
    }

    private static func parseToken(_ rawValue: String) throws -> CompileTargetReleaseToken {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value == "*CURRENT" { return .current }
        if value == "*PRV" { return .previous }
        do {
            return .specific(try IBMReleaseLevel(value))
        } catch {
            throw SourceWorkspaceCompileEvidenceError.invalidTargetReleaseToken(rawValue)
        }
    }

    private static func targetReleaseValues(in text: String) -> [String] {
        let value = text.uppercased()
        var results: [String] = []
        var cursor = value.startIndex
        while cursor < value.endIndex,
              let marker = value.range(of: "TGTRLS", range: cursor..<value.endIndex) {
            var index = marker.upperBound
            while index < value.endIndex, value[index].isWhitespace {
                index = value.index(after: index)
            }
            guard index < value.endIndex, value[index] == "(" else {
                cursor = marker.upperBound
                continue
            }
            let start = value.index(after: index)
            guard let end = value[start...].firstIndex(of: ")") else {
                results.append(String(value[start...]))
                break
            }
            results.append(String(value[start..<end]))
            cursor = value.index(after: end)
        }
        return results
    }
}

public enum SourceWorkspaceCompileMappingBasis: String, Sendable {
    case exactHostIdentity
    case exactIFSIdentity
    case exactRelativePath
    case exactBaseName
    case manualReview

    public var label: String {
        switch self {
        case .exactHostIdentity: "EXACT MEMBER IDENTITY"
        case .exactIFSIdentity: "EXACT IFS IDENTITY"
        case .exactRelativePath: "EXACT RELATIVE PATH"
        case .exactBaseName: "EXACT BASE NAME"
        case .manualReview: "MANUAL REVIEW"
        }
    }
}

public struct SourceWorkspaceCompileMappingCandidate: Equatable, Sendable, Identifiable {
    public let compileFileID: String
    public let compilePath: String
    public let documentPath: String
    public let documentFingerprint: String
    public let documentOriginLabel: String
    public let basis: SourceWorkspaceCompileMappingBasis
    public let rank: Int

    public var id: String { "\(compileFileID)|\(documentPath.uppercased())" }
}

public struct SourceWorkspaceCompileEvidenceMatcher: Sendable {
    public init() {}

    public static func fileID(for file: CompileEvidenceSourceFile) -> String {
        compileBridgeFingerprint([
            "itelas-compile-file-v1", String(file.processorSequence), file.fileIdentifier, file.path
        ])
    }

    public func candidates(
        for file: CompileEvidenceSourceFile,
        in index: SourceWorkspaceIndex
    ) -> [SourceWorkspaceCompileMappingCandidate] {
        let compileFileID = Self.fileID(for: file)
        let normalizedPath = Self.normalizedPath(file.path)
        let memberIdentity = Self.memberIdentity(from: file.path)
        let ifsPath = file.path.hasPrefix("/") ? (try? IFSPath(file.path)) : nil
        let baseName = Self.baseName(for: file.path, memberIdentity: memberIdentity)
        var candidates: [SourceWorkspaceCompileMappingCandidate] = []

        for document in index.documents {
            var basis: SourceWorkspaceCompileMappingBasis?
            var rank = Int.max
            if case .hostInclude(let origin) = document.origin {
                switch (origin.target, memberIdentity, ifsPath) {
                case (.sourceMember(let actual), .some(let expected), _)
                    where actual == expected:
                    basis = .exactHostIdentity
                    rank = 0
                case (.ifs(let actual), _, .some(let expected))
                    where actual == expected:
                    basis = .exactIFSIdentity
                    rank = 0
                default:
                    break
                }
            } else {
                let documentPath = Self.normalizedPath(document.relativePath)
                if normalizedPath == documentPath || normalizedPath.hasSuffix("/\(documentPath)") {
                    basis = .exactRelativePath
                    rank = 1
                } else if !baseName.isEmpty,
                          Self.documentBaseName(document.relativePath) == baseName {
                    basis = .exactBaseName
                    rank = 2
                }
            }
            if let basis {
                candidates.append(SourceWorkspaceCompileMappingCandidate(
                    compileFileID: compileFileID,
                    compilePath: file.path,
                    documentPath: document.relativePath,
                    documentFingerprint: document.contentFingerprint,
                    documentOriginLabel: document.origin.label,
                    basis: basis,
                    rank: rank
                ))
            }
        }
        return candidates.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.documentPath.localizedCaseInsensitiveCompare($1.documentPath) == .orderedAscending
        }
    }

    private static func memberIdentity(from path: String) -> SourceMemberIdentity? {
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasSuffix(")"),
              let open = value.lastIndex(of: "("),
              open < value.index(before: value.endIndex) else { return nil }
        let member = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
        let prefix = String(value[..<open])
        let parts = prefix.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        return try? SourceMemberIdentity(
            library: String(parts[0]),
            sourceFile: String(parts[1]),
            member: member
        )
    }

    private static func baseName(
        for path: String,
        memberIdentity: SourceMemberIdentity?
    ) -> String {
        if let memberIdentity { return memberIdentity.member.value.uppercased() }
        return documentBaseName(path)
    }

    private static func documentBaseName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.uppercased()
    }

    private static func normalizedPath(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value.uppercased()
    }
}

public enum SourceWorkspaceCompileRevisionState: String, Sendable {
    case exact
    case different
    case notRecorded

    public var label: String {
        switch self {
        case .exact: "EXACT SNAPSHOT"
        case .different: "REVISION DIFFERENT"
        case .notRecorded: "REVISION NOT RECORDED"
        }
    }
}

public struct SourceWorkspaceCompileFileMapping: Equatable, Sendable, Identifiable {
    public let id: String
    public let compileFileID: String
    public let processorSequence: Int
    public let fileIdentifier: String
    public let compilePath: String
    public let documentPath: String
    public let documentFingerprint: String
    public let basis: SourceWorkspaceCompileMappingBasis
    public let revisionState: SourceWorkspaceCompileRevisionState
    public let diagnosticCount: Int

    public var shortFingerprint: String { String(id.prefix(8)).uppercased() }
}

public enum SourceWorkspaceCompileNavigationState: String, Sendable {
    case exact
    case revisionNotRecorded
    case revisionDifferent
    case expansionMappingUnavailable
    case sourceRangeOutOfBounds

    public var label: String {
        switch self {
        case .exact: "EXACT NAVIGATION"
        case .revisionNotRecorded: "SOURCE REVISION NOT RECORDED"
        case .revisionDifferent: "SOURCE REVISION DIFFERENT"
        case .expansionMappingUnavailable: "EXPANSION REMAP UNAVAILABLE"
        case .sourceRangeOutOfBounds: "SOURCE RANGE OUT OF BOUNDS"
        }
    }

    public var canNavigate: Bool { self == .exact }
}

public struct SourceWorkspaceCompileDiagnosticLink: Equatable, Sendable, Identifiable {
    public let id: String
    public let diagnosticID: String
    public let mappingID: String
    public let documentPath: String
    public let messageID: String
    public let severity: Int
    public let message: String
    public let range: SourceTextRange
    public let navigationState: SourceWorkspaceCompileNavigationState

    public var canNavigate: Bool { navigationState.canNavigate }
}

public struct ReviewedSourceWorkspaceCompileEvidence: Equatable, Sendable, Identifiable {
    public let id: String
    public let indexFingerprint: String
    public let compileRunFingerprint: String
    public let evidenceFingerprint: String
    public let releaseEvidence: CompileTargetReleaseEvidence
    public let mappings: [SourceWorkspaceCompileFileMapping]
    public let diagnostics: [SourceWorkspaceCompileDiagnosticLink]
    public let unlinkedDiagnosticCount: Int
    public let expansionRecordCount: Int
    public let reviewedBy: String
    public let reviewedAt: Date
    public let reviewFingerprint: String

    public init(
        index: SourceWorkspaceIndex,
        evidence: CompileEvidenceParseResult,
        compileRunFingerprint: String,
        releaseEvidence: CompileTargetReleaseEvidence,
        selectedMappings: [String: String],
        sourceFingerprintsByFileID: [String: String] = [:],
        reviewedBy: String = "LOCAL OPERATOR",
        reviewedAt: Date = Date()
    ) throws {
        let runFingerprint = compileRunFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard runFingerprint.count == 64,
              runFingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SourceWorkspaceCompileEvidenceError.invalidRunFingerprint
        }
        guard !evidence.sourceFiles.isEmpty else {
            throw SourceWorkspaceCompileEvidenceError.noSourceFiles
        }
        guard !selectedMappings.isEmpty,
              selectedMappings.count <= 128 else {
            throw SourceWorkspaceCompileEvidenceError.invalidMapping
        }
        let reviewer = reviewedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reviewer.isEmpty,
              reviewer.utf8.count <= 128,
              !reviewer.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw SourceWorkspaceCompileEvidenceError.invalidReviewer
        }

        let matcher = SourceWorkspaceCompileEvidenceMatcher()
        var sourceFilesByID: [String: CompileEvidenceSourceFile] = [:]
        for file in evidence.sourceFiles {
            let fileID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: file)
            guard sourceFilesByID[fileID] == nil else {
                throw SourceWorkspaceCompileEvidenceError.invalidMapping
            }
            sourceFilesByID[fileID] = file
        }
        var resolvedMappings: [SourceWorkspaceCompileFileMapping] = []
        var usedDocumentPaths = Set<String>()
        for compileFileID in selectedMappings.keys.sorted() {
            guard let file = sourceFilesByID[compileFileID],
                  let selectedPath = selectedMappings[compileFileID],
                  let document = index.document(at: selectedPath) else {
                throw SourceWorkspaceCompileEvidenceError.invalidMapping
            }
            let normalizedDocumentPath = document.relativePath.uppercased()
            guard usedDocumentPaths.insert(normalizedDocumentPath).inserted else {
                throw SourceWorkspaceCompileEvidenceError.duplicateMappingTarget(document.relativePath)
            }
            let candidate = matcher.candidates(for: file, in: index).first {
                $0.documentPath.caseInsensitiveCompare(document.relativePath) == .orderedSame
            }
            let expectedFingerprint = sourceFingerprintsByFileID[compileFileID]?.lowercased()
            if let expectedFingerprint,
               expectedFingerprint.count != 64
                || !expectedFingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) {
                throw SourceWorkspaceCompileEvidenceError.invalidMapping
            }
            let revisionState: SourceWorkspaceCompileRevisionState
            if let expectedFingerprint {
                revisionState = expectedFingerprint == document.contentFingerprint.lowercased() ? .exact : .different
            } else {
                revisionState = .notRecorded
            }
            let diagnosticCount = evidence.diagnostics.filter {
                $0.processorSequence == file.processorSequence
                    && $0.fileIdentifier == file.fileIdentifier
                    && $0.filePath?.caseInsensitiveCompare(file.path) == .orderedSame
            }.count
            let mappingID = compileBridgeFingerprint([
                "itelas-compile-mapping-v1", compileFileID, file.path, document.relativePath,
                document.contentFingerprint, (candidate?.basis ?? .manualReview).rawValue,
                revisionState.rawValue, String(diagnosticCount)
            ])
            resolvedMappings.append(SourceWorkspaceCompileFileMapping(
                id: mappingID,
                compileFileID: compileFileID,
                processorSequence: file.processorSequence,
                fileIdentifier: file.fileIdentifier,
                compilePath: file.path,
                documentPath: document.relativePath,
                documentFingerprint: document.contentFingerprint,
                basis: candidate?.basis ?? .manualReview,
                revisionState: revisionState,
                diagnosticCount: diagnosticCount
            ))
        }

        var linkedDiagnostics: [SourceWorkspaceCompileDiagnosticLink] = []
        var unlinkedCount = 0
        for diagnostic in evidence.diagnostics {
            guard diagnostic.isSourceLinked,
                  let filePath = diagnostic.filePath,
                  let file = evidence.sourceFiles.first(where: {
                      $0.processorSequence == diagnostic.processorSequence
                          && $0.fileIdentifier == diagnostic.fileIdentifier
                          && $0.path.caseInsensitiveCompare(filePath) == .orderedSame
                  }) else {
                unlinkedCount += 1
                continue
            }
            let compileFileID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: file)
            guard let mapping = resolvedMappings.first(where: { $0.compileFileID == compileFileID }),
                  let document = index.document(at: mapping.documentPath) else {
                unlinkedCount += 1
                continue
            }
            let range = SourceTextRange(
                startLine: diagnostic.startLine,
                startColumn: diagnostic.startColumn,
                endLine: diagnostic.endLine,
                endColumn: diagnostic.endColumn
            )
            let navigationState: SourceWorkspaceCompileNavigationState
            if !Self.hasExactSourceCoordinates(diagnostic, in: document.text) {
                navigationState = .sourceRangeOutOfBounds
            } else if evidence.hasExpansionMappings {
                navigationState = .expansionMappingUnavailable
            } else {
                navigationState = switch mapping.revisionState {
                case .exact: .exact
                case .different: .revisionDifferent
                case .notRecorded: .revisionNotRecorded
                }
            }
            let linkID = compileBridgeFingerprint([
                "itelas-compile-diagnostic-link-v1", diagnostic.id, mapping.id,
                document.relativePath, diagnostic.messageID, String(diagnostic.severity),
                String(range.startLine), String(range.startColumn), String(range.endLine),
                String(range.endColumn), navigationState.rawValue
            ])
            linkedDiagnostics.append(SourceWorkspaceCompileDiagnosticLink(
                id: linkID,
                diagnosticID: diagnostic.id,
                mappingID: mapping.id,
                documentPath: document.relativePath,
                messageID: diagnostic.messageID,
                severity: diagnostic.severity,
                message: diagnostic.message,
                range: range,
                navigationState: navigationState
            ))
        }

        let timestamp = compileBridgeDate(reviewedAt)
        let fingerprint = Self.fingerprint(
            indexFingerprint: index.fingerprint,
            compileRunFingerprint: runFingerprint,
            evidenceFingerprint: evidence.fingerprint,
            releaseEvidence: releaseEvidence,
            mappings: resolvedMappings,
            diagnostics: linkedDiagnostics,
            unlinkedDiagnosticCount: unlinkedCount,
            expansionRecordCount: evidence.expansionRecordCount,
            reviewedBy: reviewer,
            reviewedAt: timestamp
        )
        id = fingerprint
        indexFingerprint = index.fingerprint
        self.compileRunFingerprint = runFingerprint
        evidenceFingerprint = evidence.fingerprint
        self.releaseEvidence = releaseEvidence
        mappings = resolvedMappings
        diagnostics = linkedDiagnostics
        unlinkedDiagnosticCount = unlinkedCount
        expansionRecordCount = evidence.expansionRecordCount
        self.reviewedBy = reviewer
        self.reviewedAt = timestamp
        reviewFingerprint = fingerprint
    }

    public var shortFingerprint: String { String(reviewFingerprint.prefix(8)).uppercased() }
    public var exactNavigationCount: Int { diagnostics.filter(\.canNavigate).count }
    public var blockedNavigationCount: Int { diagnostics.count - exactNavigationCount }

    public func diagnostics(for documentPath: String) -> [SourceWorkspaceCompileDiagnosticLink] {
        diagnostics.filter { $0.documentPath.caseInsensitiveCompare(documentPath) == .orderedSame }
    }

    public func isCurrent(
        for index: SourceWorkspaceIndex,
        compileRunFingerprint: String
    ) -> Bool {
        let runFingerprint = compileRunFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard index.fingerprint == indexFingerprint,
              runFingerprint == self.compileRunFingerprint,
              reviewFingerprint == Self.fingerprint(
                indexFingerprint: indexFingerprint,
                compileRunFingerprint: self.compileRunFingerprint,
                evidenceFingerprint: evidenceFingerprint,
                releaseEvidence: releaseEvidence,
                mappings: mappings,
                diagnostics: diagnostics,
                unlinkedDiagnosticCount: unlinkedDiagnosticCount,
                expansionRecordCount: expansionRecordCount,
                reviewedBy: reviewedBy,
                reviewedAt: reviewedAt
              ) else { return false }
        return mappings.allSatisfy { mapping in
            index.document(at: mapping.documentPath)?.contentFingerprint == mapping.documentFingerprint
        }
    }

    private static func hasExactSourceCoordinates(
        _ diagnostic: CompileDiagnostic,
        in text: String
    ) -> Bool {
        guard diagnostic.startLine > 0,
              diagnostic.endLine >= diagnostic.startLine,
              diagnostic.startColumn > 0,
              diagnostic.endColumn > 0 else { return false }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.indices.contains(diagnostic.startLine - 1),
              lines.indices.contains(diagnostic.endLine - 1) else { return false }
        let startLimit = lines[diagnostic.startLine - 1].utf16.count + 1
        let endLimit = lines[diagnostic.endLine - 1].utf16.count + 1
        guard diagnostic.startColumn <= startLimit,
              diagnostic.endColumn <= endLimit else { return false }
        return diagnostic.endLine > diagnostic.startLine
            || diagnostic.endColumn >= diagnostic.startColumn
    }

    private static func fingerprint(
        indexFingerprint: String,
        compileRunFingerprint: String,
        evidenceFingerprint: String,
        releaseEvidence: CompileTargetReleaseEvidence,
        mappings: [SourceWorkspaceCompileFileMapping],
        diagnostics: [SourceWorkspaceCompileDiagnosticLink],
        unlinkedDiagnosticCount: Int,
        expansionRecordCount: Int,
        reviewedBy: String,
        reviewedAt: Date
    ) -> String {
        compileBridgeFingerprint(
            [
                "itelas-source-compile-evidence-review-v1", indexFingerprint,
                compileRunFingerprint, evidenceFingerprint
            ]
            + releaseEvidence.fingerprintFields
            + mappings.flatMap {
                [
                    $0.id, $0.compileFileID, $0.compilePath, $0.documentPath,
                    $0.documentFingerprint, $0.basis.rawValue, $0.revisionState.rawValue,
                    String($0.diagnosticCount)
                ]
            }
            + diagnostics.flatMap {
                [
                    $0.id, $0.diagnosticID, $0.mappingID, $0.documentPath,
                    $0.messageID, String($0.severity), $0.navigationState.rawValue
                ]
            }
            + [
                String(unlinkedDiagnosticCount), String(expansionRecordCount), reviewedBy,
                String(format: "%.3f", reviewedAt.timeIntervalSince1970)
            ]
        )
    }
}

private func compileBridgeFingerprint(_ fields: [String]) -> String {
    AIContentFingerprint.sha256(fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|"))
}

private func compileBridgeDate(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
}
