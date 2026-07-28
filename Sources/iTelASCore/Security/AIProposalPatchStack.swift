import Foundation

public struct AIProposalPatchLimits: Equatable, Sendable {
    public var maximumPatches: Int
    public var maximumTotalReplacementUTF8Bytes: Int
    public var maximumExplanationUTF8Bytes: Int

    public init(
        maximumPatches: Int = 12,
        maximumTotalReplacementUTF8Bytes: Int = 262_144,
        maximumExplanationUTF8Bytes: Int = 16_384
    ) {
        self.maximumPatches = maximumPatches
        self.maximumTotalReplacementUTF8Bytes = maximumTotalReplacementUTF8Bytes
        self.maximumExplanationUTF8Bytes = maximumExplanationUTF8Bytes
    }

    public static let standard = AIProposalPatchLimits()
}

public enum AIProposalPatchStackError: Error, LocalizedError, Equatable {
    case invalidExplanation
    case explanationTooLarge(maximum: Int)
    case stackFull(maximum: Int)
    case replacementBudgetExceeded(maximum: Int)
    case duplicateProposal
    case patchNotFound
    case noPatchesSelected
    case targetMismatch
    case documentMismatch
    case mixedBaselines
    case baselineMismatch
    case wholeDraftMustBeAppliedAlone
    case overlappingSelections
    case invalidSelection

    public var errorDescription: String? {
        switch self {
        case .invalidExplanation:
            "Patch explanations cannot contain binary or NUL text."
        case .explanationTooLarge(let maximum):
            "One patch explanation exceeds the \(maximum)-byte limit."
        case .stackFull(let maximum):
            "The Proposal Patch Stack can hold at most \(maximum) patches."
        case .replacementBudgetExceeded(let maximum):
            "The Proposal Patch Stack exceeds its \(maximum)-byte replacement budget."
        case .duplicateProposal:
            "That exact proposal is already in the Proposal Patch Stack."
        case .patchNotFound:
            "A selected proposal is no longer in the Proposal Patch Stack."
        case .noPatchesSelected:
            "Select at least one proposal to build an atomic preview."
        case .targetMismatch:
            "One atomic patch set must use the same local editor target."
        case .documentMismatch:
            "One atomic patch set must use the exact same local document."
        case .mixedBaselines:
            "The selected proposals were created from different draft baselines."
        case .baselineMismatch:
            "The local draft changed after these proposals were created. Build a new review from the current baseline."
        case .wholeDraftMustBeAppliedAlone:
            "A whole-draft proposal must be previewed and applied by itself."
        case .overlappingSelections:
            "Selected proposal ranges overlap. Keep one alternative for each affected range."
        case .invalidSelection:
            "A selected proposal range no longer maps to the reviewed draft."
        }
    }
}

public struct AIProposalPatch: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let proposal: AIEditProposal
    public let explanation: String
    public let fingerprint: String

    public init(
        id: UUID = UUID(),
        proposal: AIEditProposal,
        explanation: String,
        limits: AIProposalPatchLimits = .standard
    ) throws {
        let normalizedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedExplanation.contains("\0") else {
            throw AIProposalPatchStackError.invalidExplanation
        }
        guard normalizedExplanation.lengthOfBytes(using: .utf8) <= limits.maximumExplanationUTF8Bytes else {
            throw AIProposalPatchStackError.explanationTooLarge(
                maximum: limits.maximumExplanationUTF8Bytes
            )
        }
        self.id = id
        self.proposal = proposal
        self.explanation = normalizedExplanation
        fingerprint = Self.fingerprint(for: proposal)
    }

    public var replacementUTF8ByteCount: Int {
        proposal.replacement.lengthOfBytes(using: .utf8)
    }

    private static func fingerprint(for proposal: AIEditProposal) -> String {
        let selection = proposal.selection.map {
            "\($0.locationUTF16):\($0.lengthUTF16)"
        } ?? "whole-draft"
        let fields = [
            proposal.target.rawValue,
            proposal.documentName,
            proposal.baselineSHA256,
            selection,
            proposal.replacement
        ]
        let canonical = fields
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        return AIContentFingerprint.sha256(canonical)
    }
}

public enum AIProposalPatchMove: Sendable {
    case earlier
    case later
}

public enum AIProposalImpactGap: String, Equatable, CaseIterable, Sendable {
    case compileStatus
    case hostDependencies
    case runtimeBehavior
    case queryPlan
    case authority

    public var label: String {
        switch self {
        case .compileStatus: "Compile status not observed"
        case .hostDependencies: "Host dependency impact not queried"
        case .runtimeBehavior: "Runtime behavior not executed"
        case .queryPlan: "Db2 query plan not observed"
        case .authority: "Host authority outcome not observed"
        }
    }
}

public struct AIProposalLineSpan: Equatable, Sendable {
    public let firstLine: Int
    public let lastLine: Int

    public init(firstLine: Int, lastLine: Int) {
        self.firstLine = firstLine
        self.lastLine = lastLine
    }
}

public struct AIProposalLocalImpact: Equatable, Sendable {
    public let patchCount: Int
    public let changedRangeCount: Int
    public let beforeUTF8Bytes: Int
    public let afterUTF8Bytes: Int
    public let removedUTF8Bytes: Int
    public let insertedUTF8Bytes: Int
    public let removedUTF16Units: Int
    public let insertedUTF16Units: Int
    public let beforeLineCount: Int
    public let afterLineCount: Int
    public let affectedLineSpans: [AIProposalLineSpan]
    public let isWholeDraftReplacement: Bool
    public let evidenceGaps: [AIProposalImpactGap]

    public var lineDelta: Int { afterLineCount - beforeLineCount }
    public var byteDelta: Int { afterUTF8Bytes - beforeUTF8Bytes }
}

public struct AIProposalPatchPreview: Equatable, Sendable {
    public let target: AIProposalTarget
    public let documentName: String
    public let baselineSHA256: String
    public let resultSHA256: String
    public let patchIDs: [UUID]
    public let revisedText: String
    public let impact: AIProposalLocalImpact
}

public struct AIProposalPatchStack: Equatable, Sendable {
    public let patches: [AIProposalPatch]
    public let limits: AIProposalPatchLimits

    public init(limits: AIProposalPatchLimits = .standard) {
        patches = []
        self.limits = limits
    }

    private init(patches: [AIProposalPatch], limits: AIProposalPatchLimits) {
        self.patches = patches
        self.limits = limits
    }

    public var isEmpty: Bool { patches.isEmpty }
    public var count: Int { patches.count }
    public var totalReplacementUTF8Bytes: Int {
        patches.reduce(into: 0) { $0 += $1.replacementUTF8ByteCount }
    }

    public func appending(
        proposal: AIEditProposal,
        explanation: String
    ) throws -> AIProposalPatchStack {
        guard patches.count < limits.maximumPatches else {
            throw AIProposalPatchStackError.stackFull(maximum: limits.maximumPatches)
        }
        let patch = try AIProposalPatch(
            proposal: proposal,
            explanation: explanation,
            limits: limits
        )
        guard !patches.contains(where: { $0.fingerprint == patch.fingerprint }) else {
            throw AIProposalPatchStackError.duplicateProposal
        }
        guard totalReplacementUTF8Bytes + patch.replacementUTF8ByteCount
                <= limits.maximumTotalReplacementUTF8Bytes else {
            throw AIProposalPatchStackError.replacementBudgetExceeded(
                maximum: limits.maximumTotalReplacementUTF8Bytes
            )
        }
        return AIProposalPatchStack(patches: patches + [patch], limits: limits)
    }

    public func removing(_ id: UUID) -> AIProposalPatchStack {
        AIProposalPatchStack(
            patches: patches.filter { $0.id != id },
            limits: limits
        )
    }

    public func removing(_ ids: Set<UUID>) -> AIProposalPatchStack {
        AIProposalPatchStack(
            patches: patches.filter { !ids.contains($0.id) },
            limits: limits
        )
    }

    public func moving(
        _ id: UUID,
        toward direction: AIProposalPatchMove
    ) throws -> AIProposalPatchStack {
        guard let index = patches.firstIndex(where: { $0.id == id }) else {
            throw AIProposalPatchStackError.patchNotFound
        }
        let destination = direction == .earlier ? index - 1 : index + 1
        guard patches.indices.contains(destination) else { return self }
        var reordered = patches
        reordered.swapAt(index, destination)
        return AIProposalPatchStack(patches: reordered, limits: limits)
    }

    public func preview(
        patchIDs: Set<UUID>,
        currentText: String,
        target: AIProposalTarget,
        documentName: String
    ) throws -> AIProposalPatchPreview {
        guard !patchIDs.isEmpty else {
            throw AIProposalPatchStackError.noPatchesSelected
        }
        let selected = patches.filter { patchIDs.contains($0.id) }
        guard selected.count == patchIDs.count else {
            throw AIProposalPatchStackError.patchNotFound
        }
        guard selected.allSatisfy({ $0.proposal.target == target }) else {
            throw AIProposalPatchStackError.targetMismatch
        }
        guard selected.allSatisfy({ $0.proposal.documentName == documentName }) else {
            throw AIProposalPatchStackError.documentMismatch
        }
        let baselines = Set(selected.map(\.proposal.baselineSHA256))
        guard baselines.count == 1, let baselineSHA256 = baselines.first else {
            throw AIProposalPatchStackError.mixedBaselines
        }
        guard AIContentFingerprint.sha256(currentText) == baselineSHA256 else {
            throw AIProposalPatchStackError.baselineMismatch
        }

        let wholeDraftPatches = selected.filter { $0.proposal.selection == nil }
        guard wholeDraftPatches.isEmpty || selected.count == 1 else {
            throw AIProposalPatchStackError.wholeDraftMustBeAppliedAlone
        }

        if let wholeDraft = wholeDraftPatches.first {
            return Self.makePreview(
                selected: selected,
                target: target,
                documentName: documentName,
                baselineSHA256: baselineSHA256,
                currentText: currentText,
                revisedText: wholeDraft.proposal.replacement,
                removedTexts: [currentText],
                replacements: [wholeDraft.proposal.replacement],
                spans: [AIProposalLineSpan(
                    firstLine: 1,
                    lastLine: Self.lineCount(currentText)
                )],
                isWholeDraftReplacement: true
            )
        }

        struct ResolvedHunk {
            let patch: AIProposalPatch
            let selection: AITextSelection
            let range: Range<String.Index>
            let removedText: String
            let span: AIProposalLineSpan
        }

        var hunks: [ResolvedHunk] = []
        for patch in selected {
            guard let selection = patch.proposal.selection else {
                throw AIProposalPatchStackError.wholeDraftMustBeAppliedAlone
            }
            let range: Range<String.Index>
            do {
                range = try selection.stringRange(in: currentText)
            } catch {
                throw AIProposalPatchStackError.invalidSelection
            }
            let removedText = String(currentText[range])
            let firstLine = Self.lineNumber(at: range.lowerBound, in: currentText)
            let lastLine = firstLine + removedText.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
            hunks.append(ResolvedHunk(
                patch: patch,
                selection: selection,
                range: range,
                removedText: removedText,
                span: AIProposalLineSpan(firstLine: firstLine, lastLine: lastLine)
            ))
        }

        let ordered = hunks.sorted {
            $0.selection.locationUTF16 < $1.selection.locationUTF16
        }
        for pair in zip(ordered, ordered.dropFirst()) {
            let previousEnd = pair.0.selection.locationUTF16 + pair.0.selection.lengthUTF16
            guard previousEnd <= pair.1.selection.locationUTF16 else {
                throw AIProposalPatchStackError.overlappingSelections
            }
        }

        var revisedText = currentText
        for hunk in ordered.reversed() {
            revisedText.replaceSubrange(hunk.range, with: hunk.patch.proposal.replacement)
        }
        return Self.makePreview(
            selected: selected,
            target: target,
            documentName: documentName,
            baselineSHA256: baselineSHA256,
            currentText: currentText,
            revisedText: revisedText,
            removedTexts: ordered.map(\.removedText),
            replacements: ordered.map(\.patch.proposal.replacement),
            spans: ordered.map(\.span),
            isWholeDraftReplacement: false
        )
    }

    private static func makePreview(
        selected: [AIProposalPatch],
        target: AIProposalTarget,
        documentName: String,
        baselineSHA256: String,
        currentText: String,
        revisedText: String,
        removedTexts: [String],
        replacements: [String],
        spans: [AIProposalLineSpan],
        isWholeDraftReplacement: Bool
    ) -> AIProposalPatchPreview {
        let gaps: [AIProposalImpactGap] = switch target {
        case .sourceDraft:
            [.compileStatus, .hostDependencies, .runtimeBehavior]
        case .sqlDraft:
            [.queryPlan, .authority, .runtimeBehavior]
        }
        let impact = AIProposalLocalImpact(
            patchCount: selected.count,
            changedRangeCount: spans.count,
            beforeUTF8Bytes: currentText.lengthOfBytes(using: .utf8),
            afterUTF8Bytes: revisedText.lengthOfBytes(using: .utf8),
            removedUTF8Bytes: removedTexts.reduce(into: 0) {
                $0 += $1.lengthOfBytes(using: .utf8)
            },
            insertedUTF8Bytes: replacements.reduce(into: 0) {
                $0 += $1.lengthOfBytes(using: .utf8)
            },
            removedUTF16Units: removedTexts.reduce(into: 0) { $0 += $1.utf16.count },
            insertedUTF16Units: replacements.reduce(into: 0) { $0 += $1.utf16.count },
            beforeLineCount: lineCount(currentText),
            afterLineCount: lineCount(revisedText),
            affectedLineSpans: spans,
            isWholeDraftReplacement: isWholeDraftReplacement,
            evidenceGaps: gaps
        )
        return AIProposalPatchPreview(
            target: target,
            documentName: documentName,
            baselineSHA256: baselineSHA256,
            resultSHA256: AIContentFingerprint.sha256(revisedText),
            patchIDs: selected.map(\.id),
            revisedText: revisedText,
            impact: impact
        )
    }

    private static func lineNumber(at index: String.Index, in text: String) -> Int {
        text[..<index].reduce(into: 1) { line, character in
            if character == "\n" { line += 1 }
        }
    }

    private static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
