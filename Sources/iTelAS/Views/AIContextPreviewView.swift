import SwiftUI
import iTelASCore

struct AIContextPreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: AIContextKind?
    @State private var proverb = WorkbenchProverb.random()
    private let frozenReceipt: AIContextReceipt?

    init(receipt: AIContextReceipt? = nil) {
        frozenReceipt = receipt
    }

    private var receipt: AIContextReceipt? { frozenReceipt ?? model.latestAIContextReceipt }
    private var isFrozenReceipt: Bool { frozenReceipt != nil }
    private var fragments: [AIContextFragment] { receipt?.contextBundle?.fragments ?? [] }
    private var selectedFragment: AIContextFragment? {
        fragments.first(where: { $0.kind == selectedKind }) ?? fragments.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                evidenceRail
                    .frame(width: 300)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                exactPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                sendManifest
                    .frame(width: 310)
            }
            footer
        }
        .background(AppPalette.window)
        .onAppear {
            selectedKind = selectedFragment?.kind
            proverb = .random(excluding: proverb.id)
        }
        .onChange(of: fragments.map(\.kind)) {
            if !fragments.contains(where: { $0.kind == selectedKind }) {
                selectedKind = fragments.first?.kind
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            UtilityGlyph(kind: .contextShelf, color: AppPalette.terminalGreen, size: 22)
                .frame(width: 36, height: 36)
                .background(AppPalette.instrument, in: ChamferedRectangle(cut: 3))
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.registrationBlue, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 2) {
                Text(isFrozenReceipt ? "Assist Request Receipt" : "Assist Context Shelf")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text(isFrozenReceipt
                    ? "IMMUTABLE ANSWER EVIDENCE · EXACT REDACTED PREVIEW · SESSION ONLY"
                    : "PINNED EVIDENCE · EXACT PREVIEW · ONE OPERATOR-INITIATED SEND")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.ibmBlue)
            }

            Spacer()

            shelfBadge(
                "\(fragments.count) SOURCE\(fragments.count == 1 ? "" : "S") · \(receipt?.totalContextBytes ?? 0) B",
                color: AppPalette.ibmBlue
            )
            shelfBadge(isFrozenReceipt ? "IMMUTABLE RECEIPT" : "LOCAL SELECTION", color: AppPalette.success)

            if !isFrozenReceipt, model.preparedAssistantContextBundle != nil {
                Button("Clear Shelf") {
                    model.clearPreparedAssistantContext()
                    model.previewCurrentAIContext()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var evidenceRail: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isFrozenReceipt ? "CAPTURED EVIDENCE" : "PINNED EVIDENCE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text(isFrozenReceipt ? "Context behind this answer" : "Context that stays visible")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text(isFrozenReceipt
                    ? "Each source is the exact redacted value frozen at send time."
                    : "Each source is explicit, bounded, and removable.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            HStack(spacing: 8) {
                UtilityGlyph(kind: .contextShelf, color: AppPalette.ibmBlue, size: 15)
                Text(isFrozenReceipt
                    ? "RECEIPT-BOUND · CANNOT BE ALTERED"
                    : "PIN FROM ANY ASSIST-READY WORKSPACE")
                    .font(.system(size: 7.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if fragments.isEmpty {
                ContentUnavailableView(
                    isFrozenReceipt ? "No context attached" : "Shelf empty",
                    systemImage: isFrozenReceipt ? "checkmark.shield" : "rectangle.stack.badge.plus",
                    description: Text(isFrozenReceipt
                        ? "This answer was sent without workspace or terminal context."
                        : "Use Prepare Assist in a source, compile, operations, or governance workspace.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(fragments.enumerated()), id: \.element.id) { index, fragment in
                            EvidenceShelfRow(
                                index: index + 1,
                                fragment: fragment,
                                isSelected: selectedFragment?.kind == fragment.kind,
                                isPinned: isPinned(fragment.kind),
                                isImmutable: isFrozenReceipt,
                                select: { selectedKind = fragment.kind },
                                remove: { remove(fragment.kind) }
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BUDGET \(receipt?.totalContextBytes ?? 0) / \(AIContextLimits.standard.maximumBundleUTF8Bytes) UTF-8 BYTES")
                    .font(.system(size: 7.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(AppPalette.border)
                        Rectangle()
                            .fill(AppPalette.success)
                            .frame(width: geometry.size.width * contextBudgetProgress)
                    }
                }
                .frame(height: 3)
                Text(isFrozenReceipt
                    ? "Retained with the \(AssistantRequestReceiptStore.standardMaximumCount) newest answers. New Chat clears every receipt."
                    : "The shelf is local. Each send freezes its own receipt.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(14)
            .background(AppPalette.panel)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var exactPreview: some View {
        VStack(spacing: 0) {
            if let fragment = selectedFragment {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EXACT REDACTED PREVIEW")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(AppPalette.success)
                        Text(fragment.documentName)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(AppPalette.text)
                            .lineLimit(1)
                        Text(fragmentScope(fragment))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CONTENT SHA-256")
                            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                        Text(shortFingerprint(fragment.contentSHA256))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.terminalGreen)
                    }
                    .padding(9)
                    .frame(width: 138, alignment: .leading)
                    .background(AppPalette.instrument, in: ChamferedRectangle(cut: 3))
                }
                .padding(.horizontal, 18)
                .frame(height: 84)
                .background(AppPalette.panel)

                HStack(spacing: 8) {
                    Rectangle().fill(kindColor(fragment.kind)).frame(width: 4, height: 18)
                    Text("\(fragment.kind.label.uppercased()) · \(fragment.language.uppercased()) · READ-ONLY REFERENCE")
                    Spacer()
                    Text("\(fragment.utf8ByteCount) B · \(fragment.wasRedacted ? "REDACTED" : "NO MARKER MATCH")")
                        .foregroundStyle(fragment.wasRedacted ? AppPalette.warning : AppPalette.terminalGreen)
                }
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.62, green: 0.69, blue: 0.65))
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(AppPalette.terminalRaised)

                ScrollView([.horizontal, .vertical]) {
                    Text(fragment.content)
                        .textSelection(.enabled)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color(red: 0.91, green: 0.97, blue: 0.93))
                        .lineSpacing(3)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AppPalette.terminal)

                HStack(alignment: .top, spacing: 12) {
                    UtilityGlyph(kind: .contextShelf, color: AppPalette.terminalGreen, size: 23)
                        .frame(width: 40, height: 40)
                        .background(AppPalette.instrument, in: ChamferedRectangle(cut: 3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EVIDENCE BOUNDARY")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(AppPalette.ibmBlue)
                        Text(isFrozenReceipt
                            ? "These exact redacted sources were frozen for this answer. The receipt cannot replay a request or trigger an action."
                            : "Sources are joined because you pinned them. Correlation, completeness, and causality are never inferred from shelf membership.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppPalette.secondary)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(height: 82)
                .background(AppPalette.panel)
                .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            } else {
                ContentUnavailableView(
                    isFrozenReceipt ? "No redacted evidence was sent" : "Nothing is eligible to leave",
                    systemImage: "shield.lefthalf.filled",
                    description: Text(isFrozenReceipt
                        ? "The answer still retains its destination, model, timestamp, question, and prior-turn count."
                        : "The default is to share no workspace or screen context.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppPalette.window)
    }

    private var sendManifest: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isFrozenReceipt ? "REQUEST RECEIPT" : "SEND MANIFEST")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text(isFrozenReceipt ? "Inspect request evidence" : "Review what leaves")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text(isFrozenReceipt
                    ? "Frozen when this answer was requested. No replay is available."
                    : "No request is sent from this window.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            HStack(spacing: 0) {
                ManifestMetric(value: String(fragments.count), label: "SOURCES", color: AppPalette.ibmBlue)
                ManifestMetric(value: String(receipt?.totalContextBytes ?? 0), label: "BYTES", color: AppPalette.success)
                ManifestMetric(value: String(fragments.count(where: \.wasRedacted)), label: "REDACTED", color: AppPalette.danger)
            }
            .frame(height: 92)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(spacing: 11) {
                if isFrozenReceipt {
                    manifestRow("SENT", receiptTimestamp)
                }
                manifestRow("DESTINATION", receipt?.endpointHost ?? "Not configured", color: destinationColor)
                manifestRow("MODEL", receipt?.model.isEmpty == false ? receipt!.model : "Not configured")
                manifestRow("PRIOR TURNS", String(receipt?.conversationTurns ?? 0))
                manifestRow(isFrozenReceipt ? "CONTEXT" : "SHELF", receipt?.bundleFingerprint.map(shortFingerprint) ?? "None")
                manifestRow("HOST ACTION", "Impossible", color: AppPalette.success)
            }
            .padding(15)
            .background(AppPalette.panel)

            if isFrozenReceipt, let question = receipt?.question, !question.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUBMITTED QUESTION")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text(question)
                        .textSelection(.enabled)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(5)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.ibmBlue.opacity(0.055))
                .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    UtilityGlyph(kind: .provisionalBoundary, color: AppPalette.terminalGreen, size: 16)
                    Text("UNTRUSTED INPUT BOUNDARY")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppPalette.terminalGreen)
                }
                Text(isFrozenReceipt
                    ? "Captured host and source text was reference data. Instructions inside it could not alter Assist policy or trigger an action."
                    : "Pinned host and source text stays reference data. Instructions inside it cannot alter Assist policy or trigger an action.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 0.77, green: 0.83, blue: 0.80))
                    .lineSpacing(2)
                Text("NO KEYS · NO PASSWORDS · NO HOST EXECUTION")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.45))
            }
            .padding(15)
            .background(AppPalette.terminal)

            VStack(alignment: .leading, spacing: 7) {
                Text("REDACTION REVIEW")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.danger)
                Text(isFrozenReceipt
                    ? "Marker matches applied before send: \(fragments.count(where: \.wasRedacted))"
                    : "Marker matches: \(fragments.count(where: \.wasRedacted))")
                Text(isFrozenReceipt
                    ? "This proves marker redaction, not business-sensitivity review."
                    : "Business sensitivity still needs your review.")
            }
            .font(.system(size: 9))
            .foregroundStyle(AppPalette.secondary)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.danger.opacity(0.055))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(isFrozenReceipt ? "IMMUTABLE SESSION EVIDENCE" : "DEFAULT: SHARE NOTHING")
                    .font(.system(size: 7.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
                Text(isFrozenReceipt
                    ? "This is not a raw HTTP body or replay. The oldest receipt rolls off after \(AssistantRequestReceiptStore.standardMaximumCount) answers; New Chat clears all."
                    : "Close this review, finish your question, then send deliberately from Assist.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                if !isFrozenReceipt {
                    Button {
                        model.capturePreparedAssistantContextInCasebook()
                    } label: {
                        HStack {
                            WorkbenchGlyph(tool: .casebook, color: AppPalette.ibmBlue, size: 14)
                            Text("ADD REVIEWED EVIDENCE TO CASEBOOK")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(fragments.isEmpty)
                    .help("Persist these exact reviewed artifacts locally without contacting the provider or host")
                    Button {
                        model.isAssistantVisible = true
                        dismiss()
                    } label: {
                        HStack {
                            UtilityGlyph(kind: .streamRoute, color: .white, size: 14)
                            Text("RETURN TO ASSIST")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(fragments.isEmpty)
                }
            }
            .padding(15)
        }
        .background(AppPalette.panel)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(isFrozenReceipt ? "RECEIPT: \(fragments.count) CAPTURED" : "SHELF: \(fragments.count) PINNED")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("NETWORK: IDLE")
                .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.45))
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .font(.system(size: 8, weight: .regular).italic())
                .foregroundStyle(Color(red: 0.62, green: 0.69, blue: 0.65))
                .lineLimit(1)
            Text(isFrozenReceipt ? "ARM64 · SESSION RECEIPT" : "ARM64 · LOCAL REVIEW")
                .foregroundStyle(.white)
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .padding(.horizontal, 15)
        .frame(height: 32)
        .background(AppPalette.terminal)
    }

    private var contextBudgetProgress: Double {
        min(1, Double(receipt?.totalContextBytes ?? 0) / Double(AIContextLimits.standard.maximumBundleUTF8Bytes))
    }

    private var destinationColor: Color {
        guard let receipt, !receipt.model.isEmpty, receipt.endpointHost != "Not configured" else {
            return AppPalette.danger
        }
        return AppPalette.text
    }

    private var receiptTimestamp: String {
        receipt?.createdAt.formatted(date: .abbreviated, time: .standard) ?? "Unknown"
    }

    private func isPinned(_ kind: AIContextKind) -> Bool {
        model.preparedAssistantContextBundle?.fragments.contains(where: { $0.kind == kind }) == true
    }

    private func remove(_ kind: AIContextKind) {
        if isPinned(kind) {
            model.removePreparedAssistantContext(kind)
        } else if kind == .terminalScreen {
            model.updateAutomaticScreenContext(false)
            model.previewCurrentAIContext()
        }
    }

    private func fragmentScope(_ fragment: AIContextFragment) -> String {
        let lines: String
        if let first = fragment.firstLine, let last = fragment.lastLine {
            lines = " · LINES \(first)–\(last)"
        } else {
            lines = ""
        }
        return "\(fragment.kind.label.uppercased())\(lines) · BASELINE \(shortFingerprint(fragment.baselineSHA256))"
    }

    private func shortFingerprint(_ value: String) -> String {
        String(value.prefix(8)).uppercased() + "…" + String(value.suffix(4)).uppercased()
    }

    private func kindColor(_ kind: AIContextKind) -> Color {
        switch kind {
        case .compileEvidence: AppPalette.danger
        case .terminalScreen, .systemHealth: AppPalette.success
        case .runbook, .authorityReview: AppPalette.warning
        default: AppPalette.ibmBlue
        }
    }

    private func shelfBadge(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 3, height: 15)
            Text(text)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(color.opacity(0.08), in: ChamferedRectangle(cut: 3))
        .overlay { ChamferedRectangle(cut: 3).stroke(color.opacity(0.7), lineWidth: 0.8) }
    }

    private func manifestRow(_ key: String, _ value: String, color: Color = AppPalette.text) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .foregroundStyle(AppPalette.muted)
            Spacer(minLength: 4)
            Text(value)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .font(.system(size: 7, weight: .bold, design: .monospaced))
    }
}

private struct EvidenceShelfRow: View {
    let index: Int
    let fragment: AIContextFragment
    let isSelected: Bool
    let isPinned: Bool
    let isImmutable: Bool
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: select) {
                HStack(alignment: .top, spacing: 10) {
                    Text(String(format: "%02d", index))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? AppPalette.terminalGreen : AppPalette.muted)
                        .frame(width: 29, height: 29)
                        .background(isSelected ? AppPalette.instrument : AppPalette.raised, in: ChamferedRectangle(cut: 2))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fragment.kind.label.uppercased())
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(AppPalette.ibmBlue)
                        Text(fragment.documentName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppPalette.text)
                            .lineLimit(1)
                        Text("\(fragment.utf8ByteCount) B · \(fragment.wasRedacted ? "REDACTED" : "REVIEWED")")
                            .font(.system(size: 7.2, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                        Text(isImmutable ? "CAPTURED · IMMUTABLE" : isPinned ? "PINNED · LOCAL" : "AUTOMATIC · LOCAL")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.success)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isImmutable {
                Button(action: remove) {
                    UtilityGlyph(kind: .unpinContext, color: AppPalette.muted, size: 12)
                }
                .buttonStyle(PrecisionIconButtonStyle(size: 23))
                .help(isPinned ? "Remove from Context Shelf" : "Disable automatic screen context")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(isSelected ? AppPalette.ibmBlue.opacity(0.08) : AppPalette.panel)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(AppPalette.ibmBlue).frame(width: 3) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct ManifestMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 6.4, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) { Rectangle().fill(AppPalette.border).frame(width: 1) }
    }
}
