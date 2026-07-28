import SwiftUI
import iTelASCore

struct AIProposalPatchStackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var proverb = WorkbenchProverb.random()

    private var selectedPatches: [AIProposalPatch] {
        model.aiProposalPatchStack.patches.filter {
            model.selectedAIProposalPatchIDs.contains($0.id)
        }
    }

    private var displayedImpact: AIProposalLocalImpact? {
        model.aiProposalPatchPreview?.impact ?? model.aiProposalPatchLastApplication?.impact
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                queueRail
                    .frame(width: 318)
                divider
                atomicPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                divider
                impactLens
                    .frame(width: 330)
            }
            footer
        }
        .frame(minWidth: 1_220, minHeight: 760)
        .background(AppPalette.window)
        .onAppear {
            model.refreshAIProposalPatchPreview()
            proverb = .random(excluding: proverb.id)
        }
    }

    private var divider: some View {
        Rectangle().fill(AppPalette.border).frame(width: 1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            PatchLoomMark()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("iTelAS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("PROPOSAL PATCH STACK + LOCAL IMPACT LENS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.85)
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            Spacer()
            PatchStackBadge(
                label: "\(model.selectedAIProposalPatchIDs.count) SELECTED / \(model.aiProposalPatchStack.count) QUEUED",
                color: AppPalette.ibmBlue
            )
            PatchStackBadge(
                label: model.aiProposalPatchPreview == nil ? "ATOMIC PREVIEW BLOCKED" : "ATOMIC PREVIEW READY",
                color: model.aiProposalPatchPreview == nil ? AppPalette.warning : AppPalette.success
            )
            Button("Close") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var queueRail: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                eyebrow("PATCH STACK / 01")
                Text("Bounded proposal queue")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("Collect alternatives without changing a draft. Order supports review; exact ranges control application.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                    .lineSpacing(2)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            documentLane

            if model.aiProposalPatchStack.isEmpty {
                VStack(spacing: 12) {
                    UtilityGlyph(kind: .patchStack, color: AppPalette.muted, size: 28)
                    Text("PATCH STACK EMPTY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                    Text("Add a validated proposal from a Source or SQL Assist review.")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppPalette.window)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.aiProposalPatchStack.patches.enumerated()), id: \.element.id) { index, patch in
                            PatchQueueRow(
                                patch: patch,
                                sequence: index + 1,
                                isSelected: model.selectedAIProposalPatchIDs.contains(patch.id),
                                state: patchState(patch),
                                range: patchRange(patch),
                                canMoveEarlier: index > 0,
                                canMoveLater: index + 1 < model.aiProposalPatchStack.count,
                                toggle: { model.toggleAIProposalPatchSelection(patch.id) },
                                selectOnly: { model.selectOnlyAIProposalPatch(patch.id) },
                                moveEarlier: { model.moveAIProposalPatch(patch.id, toward: .earlier) },
                                moveLater: { model.moveAIProposalPatch(patch.id, toward: .later) },
                                remove: { model.removeAIProposalPatch(patch.id) }
                            )
                        }
                    }
                }
                .background(AppPalette.panel)
            }

            queueActions
        }
        .background(AppPalette.panel)
    }

    private var documentLane: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Rectangle().fill(AppPalette.terminalGreen).frame(width: 4, height: 15)
                Text(queueDocumentName)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(queueTargetLabel)
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
            }
            Text(queueBaselineLabel)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.terminalGreen)
                .lineLimit(1)
            Text("One document · one baseline · no provider-side action")
                .font(.system(size: 8))
                .foregroundStyle(Color.white.opacity(0.58))
        }
        .padding(.horizontal, 14)
        .frame(height: 70)
        .background(AppPalette.terminal)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var queueActions: some View {
        VStack(spacing: 9) {
            HStack(spacing: 1) {
                QueueMetric(value: "\(model.selectedAIProposalPatchIDs.count)", label: "SELECTED")
                QueueMetric(value: "\(selectedPatches.compactMap(\.proposal.selection).count)", label: "RANGES")
                QueueMetric(value: "\(selectedReplacementBytes) B", label: "INSERTED")
            }
            HStack(spacing: 8) {
                Button("Compatible") { model.selectCompatibleAIProposalPatches() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Remove Selected") { model.removeSelectedAIProposalPatches() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.selectedAIProposalPatchIDs.isEmpty)
            }
            HStack {
                Text("\(model.aiProposalPatchStack.count) / \(model.aiProposalPatchStack.limits.maximumPatches) PATCHES")
                Spacer()
                Button("Clear Stack") { model.clearAIProposalPatchStack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppPalette.danger)
                    .disabled(model.aiProposalPatchStack.isEmpty)
            }
            .font(.system(size: 7, weight: .bold, design: .monospaced))
        }
        .padding(12)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var atomicPreview: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    eyebrow("ATOMIC PREVIEW / 02")
                    Spacer()
                    PatchStackBadge(label: "LOCAL BUFFER ONLY", color: AppPalette.success)
                }
                Text("One exact assembled outcome")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("Every selected replacement is resolved against one immutable SHA-256 baseline before any local mutation.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            transformLane

            if let preview = model.aiProposalPatchPreview {
                AtomicPatchDiffView(
                    patches: selectedPatches,
                    currentText: currentText(for: preview.target)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                assemblyReceipt(preview)
            } else if let applied = model.aiProposalPatchLastApplication,
                      model.aiProposalPatchWasApplied {
                appliedReceipt(applied)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                blockedPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                UtilityGlyph(
                    kind: model.aiProposalPatchPreview == nil ? .provisionalBoundary : .impactLens,
                    color: model.aiProposalPatchPreview == nil ? AppPalette.warning : AppPalette.ibmBlue,
                    size: 17
                )
                Text(model.aiProposalPatchDiagnostic ?? "Select compatible proposals to build an inert local preview.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 54)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.window)
    }

    private var transformLane: some View {
        HStack(spacing: 8) {
            HashNode(label: "BASELINE", value: shortHash(activeBaselineHash), color: AppPalette.terminalGreen)
            Rectangle().fill(AppPalette.borderStrong).frame(width: 16, height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(selectedPatches.enumerated()), id: \.element.id) { index, patch in
                        HunkNode(
                            sequence: index + 1,
                            range: compactPatchRange(patch),
                            color: index.isMultiple(of: 2) ? AppPalette.ibmBlue : AppPalette.registrationBlue
                        )
                    }
                }
            }
            Rectangle().fill(AppPalette.borderStrong).frame(width: 16, height: 1)
            HashNode(
                label: "RESULT",
                value: shortHash(model.aiProposalPatchPreview?.resultSHA256 ?? model.aiProposalPatchLastApplication?.resultSHA256 ?? "—"),
                color: Color(red: 0.47, green: 0.66, blue: 1)
            )
        }
        .padding(.horizontal, 15)
        .frame(height: 72)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func assemblyReceipt(_ preview: AIProposalPatchPreview) -> some View {
        HStack(spacing: 1) {
            ReceiptCell(value: "\(preview.patchIDs.count)", label: "NON-OVERLAPPING HUNKS", color: AppPalette.terminalGreen)
            ReceiptCell(value: shortHash(preview.baselineSHA256), label: "BEFORE SHA-256", color: AppPalette.terminalGreen)
            ReceiptCell(value: shortHash(preview.resultSHA256), label: "AFTER SHA-256", color: Color(red: 0.47, green: 0.66, blue: 1))
        }
        .frame(height: 68)
        .background(AppPalette.border)
    }

    private func appliedReceipt(_ preview: AIProposalPatchPreview) -> some View {
        VStack(spacing: 14) {
            UtilityGlyph(kind: .patchStack, color: AppPalette.success, size: 38)
            Text("ATOMIC LOCAL APPLY COMPLETE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.success)
            Text("\(preview.patchIDs.count) patch\(preview.patchIDs.count == 1 ? "" : "es") changed the open local draft in one assembled update.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.text)
            Text("No save, compile, query execution, or host write occurred.")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.secondary)
            HStack(spacing: 1) {
                ReceiptCell(value: shortHash(preview.baselineSHA256), label: "BEFORE", color: AppPalette.terminalGreen)
                ReceiptCell(value: shortHash(preview.resultSHA256), label: "AFTER", color: Color(red: 0.47, green: 0.66, blue: 1))
            }
            .frame(height: 66)
        }
        .padding(24)
        .background(AppPalette.panel)
    }

    private var blockedPreview: some View {
        VStack(spacing: 12) {
            UtilityGlyph(kind: .impactLens, color: AppPalette.warning, size: 36)
            Text("ATOMIC PREVIEW NOT READY")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.warning)
            Text(model.aiProposalPatchStack.isEmpty
                ? "Queue a validated Assist proposal first."
                : "Resolve the visible selection, document, baseline, or range conflict.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.text)
                .multilineTextAlignment(.center)
            Text("The local editor and IBM i host remain unchanged.")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.secondary)
        }
        .padding(24)
        .background(AppPalette.panel)
    }

    private var impactLens: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    eyebrow("IMPACT LENS / 03")
                    Spacer()
                    UtilityGlyph(kind: .impactLens, color: AppPalette.ibmBlue, size: 20)
                }
                Text("Locally evidenced change")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("Text deltas are exact; IBM i effects remain explicitly unverified.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            impactMetrics
            affectedSpans
            applyGates
            evidenceGaps

            VStack(spacing: 9) {
                Button {
                    model.applySelectedAIProposalPatches()
                } label: {
                    HStack(spacing: 7) {
                        UtilityGlyph(kind: .patchStack, color: .white, size: 14)
                        Text("APPLY \(model.selectedAIProposalPatchIDs.count) PATCH\(model.selectedAIProposalPatchIDs.count == 1 ? "" : "ES") LOCALLY")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.aiProposalPatchPreview == nil)
                Text("Save, compile, test, and host effects remain separate.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(AppPalette.panel)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var impactMetrics: some View {
        let impact = displayedImpact
        return HStack(spacing: 1) {
            ImpactMetric(value: signed(impact?.lineDelta), label: "LINE Δ", color: AppPalette.ibmBlue)
            ImpactMetric(value: "\(signed(impact?.byteDelta)) B", label: "BYTE Δ", color: AppPalette.registrationBlue)
            ImpactMetric(value: "\(impact?.changedRangeCount ?? 0)", label: "RANGES", color: AppPalette.success)
            ImpactMetric(value: "0", label: "HOST ACTIONS", color: AppPalette.text)
        }
        .frame(height: 82)
        .background(AppPalette.border)
    }

    private var affectedSpans: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("AFFECTED LOCAL LINES")
                Spacer()
                Text("\(displayedImpact?.affectedLineSpans.count ?? 0) EXACT")
                    .foregroundStyle(AppPalette.success)
            }
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array((displayedImpact?.affectedLineSpans ?? []).enumerated()), id: \.offset) { index, span in
                        VStack(spacing: 3) {
                            Text(span.firstLine == span.lastLine ? "L\(span.firstLine)" : "L\(span.firstLine)–\(span.lastLine)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppPalette.terminalGreen)
                            Text("HUNK \(index + 1)")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.58))
                        }
                        .frame(width: 76, height: 42)
                        .background(AppPalette.terminal)
                        .overlay { Rectangle().stroke(AppPalette.ibmBlue, lineWidth: 0.8) }
                    }
                    if displayedImpact == nil {
                        Text("NO ASSEMBLED RANGES")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
            }
        }
        .padding(12)
        .frame(height: 94)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var applyGates: some View {
        VStack(spacing: 6) {
            HStack {
                sectionLabel("ATOMIC APPLY GATES")
                Spacer()
                Text(model.aiProposalPatchPreview == nil ? "BLOCKED" : "5 / 5 PASS")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.aiProposalPatchPreview == nil ? AppPalette.danger : AppPalette.success)
            }
            gate("TARGET", targetGateValue, passes: targetGatePasses)
            gate("DOCUMENT", documentGateValue, passes: documentGatePasses)
            gate("BASELINE", baselineGateValue, passes: baselineGatePasses)
            gate("RANGES", rangesGateValue, passes: rangesGatePasses)
            gate("HOST EFFECT", "NO WRITE · NO EXECUTE", passes: true)
        }
        .padding(12)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var evidenceGaps: some View {
        let gaps = displayedImpact?.evidenceGaps ?? defaultEvidenceGaps
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionLabel("OPEN EVIDENCE GAPS")
                    .foregroundStyle(Color(red: 0.54, green: 0.40, blue: 0))
                Spacer()
                Text("\(gaps.count) UNVERIFIED")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.54, green: 0.40, blue: 0))
            }
            ForEach(gaps, id: \.rawValue) { gap in
                HStack(spacing: 8) {
                    EvidenceGapMark()
                        .frame(width: 20, height: 20)
                    Text(gap.label)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(AppPalette.warning.opacity(0.14))
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var footer: some View {
        HStack(spacing: 17) {
            Text("STACK: \(model.aiProposalPatchStack.count) QUEUED")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("HOST EFFECT: NONE")
                .foregroundStyle(Color.orange.opacity(0.82))
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .font(.system(size: 8, design: .default).italic())
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
            Text("ARM64 · ATOMIC LOCAL PREVIEW")
                .foregroundStyle(.white)
        }
        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        .padding(.horizontal, 15)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.75)
            .foregroundStyle(AppPalette.ibmBlue)
    }

    private func sectionLabel(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(AppPalette.ibmBlue)
    }

    private func gate(_ label: String, _ value: String, passes: Bool) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(passes ? AppPalette.success : AppPalette.danger).frame(width: 4, height: 15)
            Text(label).foregroundStyle(AppPalette.secondary)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(AppPalette.text).lineLimit(1)
        }
        .font(.system(size: 6.7, weight: .bold, design: .monospaced))
    }

    private var selectedReplacementBytes: Int {
        selectedPatches.reduce(into: 0) { $0 += $1.replacementUTF8ByteCount }
    }

    private var queueDocumentName: String {
        guard let patch = selectedPatches.first ?? model.aiProposalPatchStack.patches.first else {
            return "NO DOCUMENT SELECTED"
        }
        return patch.proposal.documentName.uppercased()
    }

    private var queueTargetLabel: String {
        guard let patch = selectedPatches.first ?? model.aiProposalPatchStack.patches.first else {
            return "LOCAL DRAFT"
        }
        return patch.proposal.target == .sourceDraft ? "SOURCE DRAFT" : "SQL DRAFT"
    }

    private var activeBaselineHash: String {
        selectedPatches.first?.proposal.baselineSHA256
            ?? model.aiProposalPatchStack.patches.first?.proposal.baselineSHA256
            ?? "—"
    }

    private var queueBaselineLabel: String {
        guard let patch = selectedPatches.first ?? model.aiProposalPatchStack.patches.first else {
            return "BASELINE SHA-256  —"
        }
        let current = currentDocument(for: patch.proposal.target)
        let matches = patch.proposal.documentName == current.name
            && patch.proposal.baselineSHA256 == AIContentFingerprint.sha256(current.text)
        return "BASELINE SHA-256  \(shortHash(patch.proposal.baselineSHA256))  ·  \(matches ? "EXACT CURRENT BUFFER" : "CURRENT BUFFER DIFFERS")"
    }

    private func patchState(_ patch: AIProposalPatch) -> (label: String, color: Color) {
        let current = currentDocument(for: patch.proposal.target)
        if patch.proposal.documentName != current.name {
            return ("OTHER DOCUMENT", AppPalette.warning)
        }
        if patch.proposal.baselineSHA256 != AIContentFingerprint.sha256(current.text) {
            return ("STALE BASELINE", AppPalette.danger)
        }
        if model.selectedAIProposalPatchIDs.contains(patch.id) {
            return ("SELECTED", AppPalette.ibmBlue)
        }
        if patch.proposal.selection == nil {
            return ("WHOLE-DRAFT ALTERNATIVE", AppPalette.warning)
        }
        return ("QUEUED ALTERNATIVE", AppPalette.muted)
    }

    private func patchRange(_ patch: AIProposalPatch) -> String {
        guard let selection = patch.proposal.selection else { return "WHOLE LOCAL DRAFT" }
        let current = currentDocument(for: patch.proposal.target)
        guard patch.proposal.baselineSHA256 == AIContentFingerprint.sha256(current.text),
              let range = try? selection.stringRange(in: current.text) else {
            return "UTF-16 \(selection.locationUTF16) + \(selection.lengthUTF16)"
        }
        let first = current.text[..<range.lowerBound].reduce(into: 1) { line, character in
            if character == "\n" { line += 1 }
        }
        let removed = String(current.text[range])
        let last = first + removed.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        let lineLabel = first == last ? "LINE \(first)" : "LINES \(first)–\(last)"
        return "\(lineLabel) · \(selection.lengthUTF16)→\(patch.proposal.replacement.utf16.count) UTF-16"
    }

    private func compactPatchRange(_ patch: AIProposalPatch) -> String {
        let label = patchRange(patch)
        return label.components(separatedBy: " · ").first ?? label
    }

    private func currentDocument(for target: AIProposalTarget) -> (text: String, name: String) {
        switch target {
        case .sourceDraft:
            (
                model.sourceDocument.text,
                model.sourceDocument.identity.hostLocation ?? model.sourceDocument.identity.displayName
            )
        case .sqlDraft:
            (
                model.sqlText,
                model.selectedSQLService.map { "\($0.id).sql" } ?? "active-query.sql"
            )
        }
    }

    private func currentText(for target: AIProposalTarget) -> String {
        currentDocument(for: target).text
    }

    private var targetGatePasses: Bool {
        Set(selectedPatches.map(\.proposal.target.rawValue)).count == 1 && !selectedPatches.isEmpty
    }

    private var targetGateValue: String {
        targetGatePasses ? (selectedPatches.first?.proposal.target == .sourceDraft ? "SOURCE DRAFT" : "SQL DRAFT") : "MIXED OR EMPTY"
    }

    private var documentGatePasses: Bool {
        guard targetGatePasses, let first = selectedPatches.first else { return false }
        let names = Set(selectedPatches.map(\.proposal.documentName))
        return names.count == 1 && first.proposal.documentName == currentDocument(for: first.proposal.target).name
    }

    private var documentGateValue: String { documentGatePasses ? "EXACT MATCH" : "DOCUMENT DIFFERS" }

    private var baselineGatePasses: Bool {
        guard documentGatePasses, let first = selectedPatches.first else { return false }
        let hashes = Set(selectedPatches.map(\.proposal.baselineSHA256))
        return hashes.count == 1
            && first.proposal.baselineSHA256 == AIContentFingerprint.sha256(currentText(for: first.proposal.target))
    }

    private var baselineGateValue: String { baselineGatePasses ? "ONE SHA-256" : "STALE OR MIXED" }

    private var rangesGatePasses: Bool {
        guard baselineGatePasses else { return false }
        let selections = selectedPatches.compactMap(\.proposal.selection)
        if selections.count != selectedPatches.count { return selectedPatches.count == 1 }
        let ordered = selections.sorted { $0.locationUTF16 < $1.locationUTF16 }
        return zip(ordered, ordered.dropFirst()).allSatisfy {
            $0.locationUTF16 + $0.lengthUTF16 <= $1.locationUTF16
        }
    }

    private var rangesGateValue: String { rangesGatePasses ? "NON-OVERLAPPING" : "CONFLICT" }

    private var defaultEvidenceGaps: [AIProposalImpactGap] {
        selectedPatches.first?.proposal.target == .sqlDraft
            ? [.queryPlan, .authority, .runtimeBehavior]
            : [.compileStatus, .hostDependencies, .runtimeBehavior]
    }

    private func shortHash(_ hash: String) -> String {
        guard hash.count > 12 else { return hash.uppercased() }
        return "\(hash.prefix(5).uppercased())…\(hash.suffix(4).uppercased())"
    }

    private func signed(_ value: Int?) -> String {
        guard let value else { return "0" }
        return value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct PatchQueueRow: View {
    let patch: AIProposalPatch
    let sequence: Int
    let isSelected: Bool
    let state: (label: String, color: Color)
    let range: String
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let toggle: () -> Void
    let selectOnly: () -> Void
    let moveEarlier: () -> Void
    let moveLater: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 7) {
                Button(action: toggle) {
                    PatchSelectionMark(selected: isSelected, color: state.color)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Deselect patch \(sequence)" : "Select patch \(sequence)")
                Text(String(format: "%02d", sequence))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(state.color)
                HStack(spacing: 3) {
                    Button(action: moveEarlier) { Text("↑") }
                        .disabled(!canMoveEarlier)
                    Button(action: moveLater) { Text("↓") }
                        .disabled(!canMoveLater)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Rectangle().fill(state.color).frame(width: 4, height: 13)
                    Text(state.label)
                        .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                        .foregroundStyle(state.color)
                    Spacer(minLength: 0)
                    Text(shortFingerprint)
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Text(patch.explanation.isEmpty ? "Local draft replacement" : patch.explanation)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(2)
                Text(range)
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Button("Only") { selectOnly() }
                    Button("Remove", role: .destructive) { remove() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(AppPalette.secondary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AppPalette.ibmBlue.opacity(0.08) : AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var shortFingerprint: String {
        "\(patch.fingerprint.prefix(4).uppercased())…\(patch.fingerprint.suffix(4).uppercased())"
    }
}

private struct AtomicPatchDiffView: View {
    struct Line: Identifiable {
        let id: String
        let line: Int
        let sign: String
        let text: String
        let foreground: Color
        let background: Color
    }

    struct Hunk: Identifiable {
        let id: UUID
        let sequence: Int
        let firstLine: Int
        let lines: [Line]
        let fingerprint: String
    }

    let patches: [AIProposalPatch]
    let currentText: String

    private var hunks: [Hunk] {
        patches
            .sorted {
                ($0.proposal.selection?.locationUTF16 ?? Int.min)
                    < ($1.proposal.selection?.locationUTF16 ?? Int.min)
            }
            .enumerated()
            .map { index, patch in
                let removed: String
                let firstLine: Int
                if let selection = patch.proposal.selection,
                   let range = try? selection.stringRange(in: currentText) {
                    removed = String(currentText[range])
                    firstLine = currentText[..<range.lowerBound].reduce(into: 1) { line, character in
                        if character == "\n" { line += 1 }
                    }
                } else {
                    removed = currentText
                    firstLine = 1
                }
                let removedLines = removed
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                let addedLines = patch.proposal.replacement
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                let lines = removedLines.enumerated().map { offset, line in
                    Line(
                        id: "\(patch.id.uuidString)-removed-\(offset)",
                        line: firstLine + offset,
                        sign: "−",
                        text: line,
                        foreground: Color(red: 1, green: 0.64, blue: 0.67),
                        background: Color(red: 0.16, green: 0.055, blue: 0.06)
                    )
                } + addedLines.enumerated().map { offset, line in
                    Line(
                        id: "\(patch.id.uuidString)-added-\(offset)",
                        line: firstLine + offset,
                        sign: "+",
                        text: line,
                        foreground: AppPalette.terminalGreen,
                        background: Color(red: 0.035, green: 0.16, blue: 0.09)
                    )
                }
                return Hunk(
                    id: patch.id,
                    sequence: index + 1,
                    firstLine: firstLine,
                    lines: lines,
                    fingerprint: patch.fingerprint
                )
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(Color(red: 0.47, green: 0.66, blue: 1)).frame(width: 4, height: 17)
                Text("EXACT BASELINE-BOUND HUNKS")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                Spacer()
                Text("REMOVED + REPLACEMENT · NO HOST EFFECT")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.terminalGreen)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(AppPalette.terminalRaised)

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hunks) { hunk in
                        HStack {
                            Text("HUNK \(String(format: "%02d", hunk.sequence)) · START LINE \(hunk.firstLine)")
                            Spacer()
                            Text("\(hunk.fingerprint.prefix(5).uppercased())…\(hunk.fingerprint.suffix(4).uppercased())")
                        }
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .padding(.horizontal, 12)
                        .frame(minWidth: 620, minHeight: 28)
                        .background(AppPalette.terminalRaised)

                        ForEach(hunk.lines) { line in
                            DiffLine(
                                line: line.line,
                                sign: line.sign,
                                text: line.text,
                                foreground: line.foreground,
                                background: line.background
                            )
                        }
                    }
                }
            }
            .background(AppPalette.terminal)
        }
    }
}

private struct DiffLine: View {
    let line: Int
    let sign: String
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(foreground).frame(width: 3)
            Text("\(line)")
                .foregroundStyle(Color.white.opacity(0.38))
                .frame(width: 34, alignment: .trailing)
            Text(sign)
                .fontWeight(.bold)
                .foregroundStyle(foreground)
                .frame(width: 12)
            Text(text.isEmpty ? " " : text)
                .foregroundStyle(foreground)
                .textSelection(.enabled)
            Spacer(minLength: 20)
        }
        .font(.system(size: 8.2, design: .monospaced))
        .padding(.horizontal, 9)
        .frame(minWidth: 620, minHeight: 25, alignment: .leading)
        .background(background)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5) }
    }
}

private struct PatchLoomMark: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .square, lineJoin: .miter)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func line(_ points: [CGPoint], color: Color) {
                var path = Path()
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color), style: stroke)
            }
            line([point(0.22, 0.12), point(0.22, 0.88)], color: AppPalette.terminalGreen)
            line([point(0.32, 0.25), point(0.76, 0.25)], color: AppPalette.ibmBlue)
            line([point(0.32, 0.50), point(0.62, 0.50)], color: .white)
            line([point(0.32, 0.75), point(0.82, 0.75)], color: Color(red: 0.47, green: 0.66, blue: 1))
            line([point(0.76, 0.25), point(0.86, 0.25), point(0.86, 0.75), point(0.82, 0.75)], color: AppPalette.terminalGreen.opacity(0.7))
        }
        .background(AppPalette.terminal, in: ChamferedRectangle(cut: 3))
        .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.ibmBlue, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

private struct PatchSelectionMark: View {
    let selected: Bool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.stroke(Path(rect), with: .color(color), lineWidth: 1)
            if selected {
                context.fill(Path(rect.insetBy(dx: 3, dy: 3)), with: .color(AppPalette.terminal))
                var check = Path()
                check.move(to: CGPoint(x: size.width * 0.28, y: size.height * 0.52))
                check.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.68))
                check.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.32))
                context.stroke(check, with: .color(AppPalette.terminalGreen), style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter))
            } else {
                context.fill(Path(CGRect(x: size.width * 0.35, y: size.height * 0.47, width: size.width * 0.3, height: 1.5)), with: .color(color.opacity(0.7)))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct EvidenceGapMark: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.stroke(Path(rect), with: .color(AppPalette.warning), lineWidth: 1)
            context.fill(Path(CGRect(x: size.width * 0.46, y: size.height * 0.24, width: 2, height: size.height * 0.34)), with: .color(Color(red: 0.54, green: 0.40, blue: 0)))
            context.fill(Path(CGRect(x: size.width * 0.46, y: size.height * 0.70, width: 2, height: 2)), with: .color(Color(red: 0.54, green: 0.40, blue: 0)))
        }
        .accessibilityHidden(true)
    }
}

private struct PatchStackBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 4, height: 14)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(color.opacity(0.07))
        .overlay { Rectangle().stroke(color.opacity(0.8), lineWidth: 0.8) }
    }
}

private struct QueueMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
            Text(label)
                .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 43)
        .background(AppPalette.panel)
    }
}

private struct ImpactMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 5.8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.raised)
    }
}

private struct HashNode: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.54))
            Text(value)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .frame(width: 102, height: 42, alignment: .leading)
        .background(AppPalette.terminal)
        .overlay { Rectangle().stroke(color.opacity(0.85), lineWidth: 0.8) }
    }
}

private struct HunkNode: View {
    let sequence: Int
    let range: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("HUNK \(String(format: "%02d", sequence))")
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(range)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
        }
        .frame(width: 76, height: 42)
        .background(AppPalette.panel)
        .overlay { Rectangle().stroke(color.opacity(0.85), lineWidth: 0.8) }
    }
}

private struct ReceiptCell: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.terminal)
    }
}
