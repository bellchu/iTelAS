import SwiftUI
import iTelASCore

struct AIReviewDossierView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var proverb = WorkbenchProverb.random()

    private var draft: AIReviewDraft? { model.aiReviewDraft }

    private var bundle: AIContextBundle? {
        try? model.buildAIReviewContextBundle()
    }

    private var primaryFragment: AIContextFragment? {
        bundle?.fragments.first(where: { $0.kind != .terminalScreen })
    }

    var body: some View {
        VStack(spacing: 0) {
            dossierHeader
            if let draft {
                HStack(spacing: 0) {
                    contextManifest(draft)
                        .frame(width: 286)
                    divider
                    reviewRequest(draft)
                        .frame(minWidth: 500, maxWidth: .infinity)
                    divider
                    proposalComparator(draft)
                        .frame(width: 390)
                }
            } else {
                ContentUnavailableView(
                    "No Assist review prepared",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Open Source or SQL and choose Prepare Assist Review.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            dossierFooter
        }
        .frame(minWidth: 1_200, minHeight: 760)
        .background(AppPalette.window)
        .onAppear { proverb = .random(excluding: proverb.id) }
    }

    private var divider: some View {
        Rectangle().fill(AppPalette.border).frame(width: 1)
    }

    private var dossierHeader: some View {
        HStack(spacing: 11) {
            AssistContextWeaveMark()
                .frame(width: 31, height: 31)
            VStack(alignment: .leading, spacing: 2) {
                Text("iTelAS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("ASSIST CONTEXT + PROPOSAL DOSSIER")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            Spacer()
            DossierBadge(
                label: "CONTEXT: \(draft?.contextKind.label.uppercased() ?? "NOT PREPARED")",
                color: AppPalette.ibmBlue
            )
            DossierBadge(label: "APPLY: LOCAL DRAFT ONLY", color: AppPalette.success)
            Button {
                model.pinAIReviewContextToShelf()
            } label: {
                HStack(spacing: 6) {
                    UtilityGlyph(kind: .contextShelf, color: AppPalette.secondary, size: 13)
                    Text("Pin to Shelf")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(bundle == nil || model.isAssistantResponding)
            .help("Pin the exact reviewed source or SQL context for a later multi-workspace Assist request")
            Button("Close") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 17)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func contextManifest(_ draft: AIReviewDraft) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                dossierEyebrow("CONTEXT MANIFEST")
                Text("Know what leaves")
                    .font(.system(size: 20, weight: .bold))
                Text("Nothing is attached by implication.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("\(draft.target == .sourceDraft ? "SOURCE" : "SQL") SCOPE")
                HStack(spacing: 0) {
                    ForEach(AIReviewContextScope.allCases) { scope in
                        let selected = draft.scope == scope
                        Button(scope.label.uppercased()) {
                            model.updateAIReviewScope(scope)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? Color.white : AppPalette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 31)
                        .background(selected ? AppPalette.terminal : AppPalette.panel)
                        .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 0.8) }
                        .disabled(model.isAssistantResponding || (scope == .selection && !draft.selectedScopeIsAvailable))
                    }
                }
                Text(scopeMetadata)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
            }
            .padding(13)
            .background(AppPalette.raised)

            AIManifestRow(
                title: draft.contextKind.label.uppercased(),
                detail: draft.documentName,
                state: "INCLUDED FOR THIS SEND",
                included: true
            )
            AIManifestRow(
                title: draft.target == .sourceDraft ? "SQL DRAFT" : "SOURCE DRAFT",
                detail: "Other editor workspace",
                state: "NOT SHARED",
                included: false
            )
            AIManifestRow(
                title: "5250 SCREEN",
                detail: draft.includeTerminalScreen ? "Frozen redacted snapshot" : "Visible rows only",
                state: draft.includeTerminalScreen ? "INCLUDED FOR THIS SEND" : "NOT SHARED",
                included: draft.includeTerminalScreen
            )

            Toggle(isOn: Binding(
                get: { model.aiReviewDraft?.includeTerminalScreen ?? false },
                set: { model.updateAIReviewIncludesTerminal($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INCLUDE REDACTED 5250 SNAPSHOT")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    Text("Captured now; it will not follow later screen changes.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(model.isAssistantResponding)
            .padding(12)
            .background(AppPalette.panel)

            VStack(alignment: .leading, spacing: 7) {
                Text("UNTRUSTED INPUT BOUNDARY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.terminalGreen)
                Text("Source, SQL, and host text are reference data. Instructions inside them cannot change Assist policy or trigger an action.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                Text("NO PASSWORDS · NO API KEYS · NO HOST EXECUTION")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.orange.opacity(0.85))
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.terminal)

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("RECEIPT BEFORE SEND")
                    receiptRow("TARGET", URL(string: model.aiConfiguration.endpoint)?.host ?? "Invalid endpoint")
                    receiptRow("MODEL", model.aiConfiguration.model.isEmpty ? "NOT CONFIGURED" : model.aiConfiguration.model)
                    receiptRow("DOCUMENT", draft.documentName)
                    receiptRow("BASELINE", primaryFragment.map { shortHash($0.baselineSHA256) } ?? "UNAVAILABLE")
                    receiptRow("CONTEXT", bundle.map { "\($0.totalUTF8Bytes) BYTES" } ?? "BLOCKED", accent: AppPalette.success)
                    receiptRow("BUNDLE", bundle.map { shortHash($0.fingerprint) } ?? "UNAVAILABLE")
                }
                .padding(13)
            }
            .background(AppPalette.panel)

            VStack(alignment: .leading, spacing: 3) {
                Text("DEFAULT: SHARE NOTHING")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
                Text("Every context source is chosen for one send.")
                    .font(.system(size: 8.8))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised)
        }
        .background(AppPalette.panel)
    }

    private func reviewRequest(_ draft: AIReviewDraft) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                dossierEyebrow("REVIEW REQUEST")
                Text("Ask with evidence, not ambiguity")
                    .font(.system(size: 20, weight: .bold))
                Text("The exact question and exact context travel together.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    sectionLabel("OPERATOR QUESTION")
                    Spacer()
                    Text("EDITABLE UNTIL SEND")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.success)
                }
                TextEditor(text: Binding(
                    get: { model.aiReviewDraft?.question ?? "" },
                    set: { model.updateAIReviewQuestion($0) }
                ))
                .font(.system(size: 11.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 75)
                .background(AppPalette.panel)
                .overlay(alignment: .leading) { Rectangle().fill(AppPalette.ibmBlue).frame(width: 4) }
                .overlay { Rectangle().stroke(AppPalette.ibmBlue, lineWidth: 0.8) }
                .disabled(model.isAssistantResponding)
                HStack(spacing: 15) {
                    compactTag("MODE · REVIEW", color: AppPalette.ibmBlue)
                    compactTag("TARGET · \(draft.target.label.uppercased())")
                    compactTag("OUTPUT · EXPLANATION + OPTIONAL PROPOSAL")
                }
            }
            .padding(13)
            .background(AppPalette.raised)

            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Rectangle().fill(AppPalette.terminalGreen).frame(width: 4, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXACT CONTEXT PREVIEW")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(AppPalette.terminalGreen)
                        Text(primaryPreviewIdentity)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.58))
                    }
                    Spacer()
                    Text(primaryFragment.map { "\($0.utf8ByteCount) B" } ?? "BLOCKED")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 15)
                .frame(height: 43)
                .background(AppPalette.terminalRaised)

                if let fragment = primaryFragment {
                    HStack {
                        Text(fragment.wasRedacted
                            ? "\(fragment.language.uppercased()) · REDACTED · ADVICE ONLY"
                            : "\(fragment.language.uppercased()) · UTF-8 PREVIEW · READ-ONLY REFERENCE")
                        Spacer()
                        Text("BASELINE \(shortHash(fragment.baselineSHA256))")
                            .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
                    }
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .padding(.horizontal, 15)
                    .frame(height: 31)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }

                    ScrollView([.horizontal, .vertical]) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(previewLineNumbers(fragment))
                                .foregroundStyle(Color.white.opacity(0.32))
                                .multilineTextAlignment(.trailing)
                            Rectangle().fill(AppPalette.terminalGreen).frame(width: 3)
                            Text(fragment.content)
                                .foregroundStyle(Color.white.opacity(0.9))
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .lineSpacing(3)
                        .padding(15)
                    }
                } else {
                    ContentUnavailableView(
                        "Context blocked",
                        systemImage: "exclamationmark.shield",
                        description: Text("Reduce the selected context or choose a valid editor selection.")
                    )
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.terminal)

            HStack(spacing: 9) {
                compositionCell("01 · QUESTION", "Operator-authored request", color: AppPalette.ibmBlue)
                Text("+").foregroundStyle(AppPalette.muted)
                compositionCell("02 · MANIFEST", "Exact preview + receipt", color: AppPalette.success)
                Text("→").foregroundStyle(AppPalette.muted)
                compositionCell("ONE BOUNDED REQUEST", "No ambient workspace access", color: AppPalette.terminalGreen, dark: true)
            }
            .padding(11)
            .background(AppPalette.panel)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reviewChannelLabel)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(model.isAssistantResponding ? AppPalette.ibmBlue : AppPalette.success)
                    Text(model.isAssistantResponding
                        ? "Complete response required. No partial proposal can apply."
                        : "No tool execution. No automatic edits.")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                if model.isAssistantResponding {
                    HStack(spacing: 6) {
                        PhaseAnimator([false, true]) { active in
                            Rectangle()
                                .fill(AppPalette.registrationBlue)
                                .frame(width: 5, height: 5)
                                .opacity(active ? 1 : 0.34)
                        } animation: { _ in
                            .easeInOut(duration: 0.72)
                        }
                        Text(model.assistantResponsePhase == .reviewing ? "VALIDATING ENVELOPE" : "ASSIST BUSY")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.ibmBlue)
                    }
                    Button {
                        model.cancelAssistantResponse()
                    } label: {
                        HStack(spacing: 7) {
                            UtilityGlyph(kind: .stopGeneration, color: .white, size: 13)
                            Text(model.assistantResponsePhase == .reviewing ? "STOP REVIEW" : "STOP ASSIST")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.45)
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(height: 31)
                        .background(AppPalette.text, in: ChamferedRectangle(cut: 3))
                        .overlay {
                            ChamferedRectangle(cut: 3)
                                .stroke(AppPalette.registrationBlue, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Stop the request; no partial proposal can be applied")
                } else {
                    Button("SEND REVIEW REQUEST") {
                        model.sendAIReviewRequest()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sendIsDisabled)
                }
            }
            .padding(13)
            .background(AppPalette.raised)
        }
    }

    private var reviewChannelLabel: String {
        guard model.isAssistantResponding else { return "READY FOR ONE SEND" }
        return model.assistantResponsePhase == .reviewing
            ? "REVIEW IN FLIGHT"
            : "ANOTHER ASSIST RESPONSE IS IN FLIGHT"
    }

    private func proposalComparator(_ draft: AIReviewDraft) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                dossierEyebrow("PROPOSAL COMPARATOR")
                Text("Nothing changes until reviewed")
                    .font(.system(size: 18, weight: .bold))
                Text("A parsed replacement, held beside the current baseline.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)

            if let explanation = model.latestAIProposalExplanation {
                ScrollView {
                    Text(explanation)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppPalette.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                }
                .frame(height: 100)
                .background(AppPalette.raised)
            } else {
                HStack(spacing: 9) {
                    Rectangle().fill(Color.orange.opacity(0.72)).frame(width: 5, height: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AWAITING REVIEW")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.ibmBlue)
                        Text("A response may contain advice, one validated proposal, or no edit at all.")
                            .font(.system(size: 9.2))
                            .foregroundStyle(AppPalette.secondary)
                    }
                }
                .padding(13)
                .frame(height: 100)
                .background(AppPalette.raised)
            }

            if let proposal = model.latestAIEditProposal {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Rectangle().fill(Color(red: 0.47, green: 0.66, blue: 1)).frame(width: 4, height: 18)
                        Text("PARSED REPLACEMENT")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                        Spacer()
                        Text(draft.language.uppercased())
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.terminalGreen)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(AppPalette.terminal)

                    ProposalDiffView(
                        before: currentProposalTargetText(proposal),
                        after: proposal.replacement
                    )
                }
                .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No local proposal",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(model.isAssistantResponding
                        ? "Assist is preparing a review response."
                        : "Send the reviewed request to receive advice or an inert local edit proposal.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppPalette.panel)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    sectionLabel("APPLY GATES")
                    Spacer()
                    Text(applyGateSummary)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(proposalCanApply ? AppPalette.success : AppPalette.danger)
                }
                proposalGate("BASELINE HASH", baselineMatches ? "MATCH" : "BLOCKED", passes: baselineMatches)
                proposalGate("PROPOSAL FORMAT", model.latestAIEditProposal == nil ? "NONE" : "ONE REPLACEMENT", passes: model.latestAIEditProposal != nil)
                proposalGate(
                    "APPLY TARGET",
                    documentMatches ? "EXACT LOCAL BUFFER" : "DOCUMENT CHANGED",
                    passes: documentMatches
                )
                proposalGate("HOST EFFECT", "NO WRITE · NO EXECUTE", passes: true)
            }
            .padding(13)
            .background(AppPalette.panel)

            VStack(spacing: 8) {
                if let diagnostic = model.aiProposalDiagnostic {
                    Text(diagnostic)
                        .font(.system(size: 8.5))
                        .foregroundStyle(model.aiProposalWasApplied ? AppPalette.success : AppPalette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 9) {
                    Button("Reject") { model.rejectLatestAIProposal() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.latestAIEditProposal == nil)
                    Button(model.latestAIProposalIsQueued ? "QUEUED IN PATCH STACK" : "ADD TO PATCH STACK") {
                        model.queueLatestAIProposal()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.latestAIEditProposal == nil || model.latestAIProposalIsQueued)
                }
                Button(
                    model.aiProposalWasApplied
                        ? "APPLIED LOCALLY"
                        : model.latestAIProposalIsQueued
                            ? "QUEUED FOR ATOMIC REVIEW"
                            : "APPLY TO LOCAL DRAFT"
                ) {
                    model.applyLatestAIProposal()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!proposalCanApply || model.aiProposalWasApplied || model.latestAIProposalIsQueued)
                Text("A later host save remains a separate, explicit operator action.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(AppPalette.raised)
        }
    }

    private var dossierFooter: some View {
        HStack(spacing: 17) {
            Text("ASSIST: REVIEW READY")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("PROVIDER: OPT-IN")
                .foregroundStyle(Color.white.opacity(0.58))
            Text("HOST WRITE: IMPOSSIBLE")
                .foregroundStyle(Color.orange.opacity(0.82))
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .font(.system(size: 8, design: .default).italic())
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
            Text("ARM64 · LOCAL REVIEW")
                .foregroundStyle(.white)
        }
        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        .padding(.horizontal, 15)
        .frame(height: 31)
        .background(AppPalette.terminal)
    }

    private var scopeMetadata: String {
        guard let fragment = primaryFragment else { return "CONTEXT BLOCKED" }
        if let first = fragment.firstLine, let last = fragment.lastLine {
            return "LINES \(first)–\(last) · \(fragment.utf8ByteCount) UTF-8 BYTES"
        }
        let lineCount = fragment.content.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(lineCount) LINES · \(fragment.utf8ByteCount) UTF-8 BYTES"
    }

    private var primaryPreviewIdentity: String {
        guard let fragment = primaryFragment else { return "NO VALID CONTEXT" }
        let range = if let first = fragment.firstLine, let last = fragment.lastLine {
            " · LINES \(first)–\(last)"
        } else {
            " · WHOLE DRAFT"
        }
        return fragment.documentName.uppercased() + range
    }

    private var sendIsDisabled: Bool {
        model.isAssistantResponding
            || bundle == nil
            || draft?.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private var currentProposalText: String {
        guard let proposal = model.latestAIEditProposal else { return "" }
        return switch proposal.target {
        case .sourceDraft: model.sourceDocument.text
        case .sqlDraft: model.sqlText
        }
    }

    private var baselineMatches: Bool {
        guard let proposal = model.latestAIEditProposal else { return false }
        return AIContentFingerprint.sha256(currentProposalText) == proposal.baselineSHA256
    }

    private var currentProposalDocumentName: String {
        guard let proposal = model.latestAIEditProposal else { return "" }
        return switch proposal.target {
        case .sourceDraft:
            model.sourceDocument.identity.hostLocation ?? model.sourceDocument.identity.displayName
        case .sqlDraft:
            model.selectedSQLService.map { "\($0.id).sql" } ?? "active-query.sql"
        }
    }

    private var documentMatches: Bool {
        guard let proposal = model.latestAIEditProposal else { return false }
        return proposal.documentName == currentProposalDocumentName
    }

    private var proposalCanApply: Bool {
        model.latestAIEditProposal != nil && documentMatches && baselineMatches
    }

    private var applyGateSummary: String {
        proposalCanApply ? "4 / 4 PASS" : "REVIEW BLOCKED"
    }

    private func currentProposalTargetText(_ proposal: AIEditProposal) -> String {
        guard let selection = proposal.selection else { return currentProposalText }
        return (try? selection.selectedText(in: currentProposalText)) ?? "Selection no longer matches the draft."
    }

    private func previewLineNumbers(_ fragment: AIContextFragment) -> String {
        let start = fragment.firstLine ?? 1
        let count = fragment.content.split(separator: "\n", omittingEmptySubsequences: false).count
        return (0..<count).map { String(start + $0) }.joined(separator: "\n")
    }

    private func shortHash(_ hash: String) -> String {
        guard hash.count > 12 else { return hash.uppercased() }
        return "\(hash.prefix(5).uppercased())…\(hash.suffix(4).uppercased())"
    }

    private func dossierEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(AppPalette.ibmBlue)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(AppPalette.muted)
    }

    private func receiptRow(_ key: String, _ value: String, accent: Color = AppPalette.text) -> some View {
        HStack(spacing: 7) {
            Text(key)
                .foregroundStyle(AppPalette.muted)
            Spacer(minLength: 4)
            Text(value)
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
    }

    private func compactTag(_ text: String, color: Color = AppPalette.secondary) -> some View {
        Text(text)
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func compositionCell(_ label: String, _ detail: String, color: Color, dark: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(detail)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(dark ? Color.white : AppPalette.text)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dark ? AppPalette.terminal : color.opacity(0.08))
        .overlay { Rectangle().stroke(color.opacity(0.8), lineWidth: 0.8) }
    }

    private func proposalGate(_ label: String, _ value: String, passes: Bool) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(passes ? AppPalette.success : AppPalette.danger).frame(width: 4, height: 17)
            Text(label)
                .foregroundStyle(AppPalette.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(AppPalette.text)
        }
        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
    }
}

private struct DossierBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: 4, height: 16)
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(color.opacity(0.07))
        .overlay { Rectangle().stroke(color.opacity(0.85), lineWidth: 0.8) }
    }
}

private struct AIManifestRow: View {
    let title: String
    let detail: String
    let state: String
    let included: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(included ? AppPalette.success : AppPalette.muted.opacity(0.75))
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
                Text(state)
                    .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                    .foregroundStyle(included ? AppPalette.success : AppPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct ProposalDiffView: View {
    private enum Kind { case context, removed, added }
    private struct Row: Identifiable {
        let id: Int
        let kind: Kind
        let line: Int
        let text: String
    }

    let before: String
    let after: String

    private var rows: [Row] {
        let old = before.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        let new = after.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var result: [Row] = []
        var id = 0
        for index in 0..<max(old.count, new.count) {
            let oldLine = index < old.count ? old[index] : nil
            let newLine = index < new.count ? new[index] : nil
            if oldLine == newLine, let line = oldLine {
                result.append(Row(id: id, kind: .context, line: index + 1, text: line))
                id += 1
            } else {
                if let oldLine {
                    result.append(Row(id: id, kind: .removed, line: index + 1, text: oldLine))
                    id += 1
                }
                if let newLine {
                    result.append(Row(id: id, kind: .added, line: index + 1, text: newLine))
                    id += 1
                }
            }
            if result.count >= 120 { break }
        }
        return result
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 7) {
                        Text(String(row.line))
                            .foregroundStyle(AppPalette.muted)
                            .frame(width: 30, alignment: .trailing)
                        Text(sign(row.kind))
                            .fontWeight(.bold)
                            .foregroundStyle(color(row.kind))
                            .frame(width: 12)
                        Text(row.text.isEmpty ? " " : row.text)
                            .foregroundStyle(color(row.kind))
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 8.3, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(minWidth: 360, minHeight: 24, alignment: .leading)
                    .background(background(row.kind))
                    .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.55)).frame(height: 0.5) }
                }
            }
        }
        .background(AppPalette.panel)
        .overlay(alignment: .bottomLeading) {
            Text("EXPLANATION IS ADVISORY · CODE REMAINS INERT")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.raised.opacity(0.96))
        }
    }

    private func sign(_ kind: Kind) -> String {
        switch kind {
        case .context: " "
        case .removed: "−"
        case .added: "+"
        }
    }

    private func color(_ kind: Kind) -> Color {
        switch kind {
        case .context: AppPalette.secondary
        case .removed: AppPalette.danger
        case .added: Color(red: 0.07, green: 0.45, blue: 0.2)
        }
    }

    private func background(_ kind: Kind) -> Color {
        switch kind {
        case .context: AppPalette.panel
        case .removed: AppPalette.danger.opacity(0.07)
        case .added: AppPalette.success.opacity(0.08)
        }
    }
}

private struct AssistContextWeaveMark: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AppPalette.terminal))
            let spine = CGRect(x: size.width * 0.23, y: size.height * 0.18, width: 3, height: size.height * 0.64)
            context.fill(Path(spine), with: .color(Color(red: 0.47, green: 0.66, blue: 1)))
            let rails: [(CGFloat, CGFloat, Color)] = [
                (0.32, 0.48, AppPalette.terminalGreen),
                (0.48, 0.34, Color.white),
                (0.64, 0.56, Color(red: 0.47, green: 0.66, blue: 1))
            ]
            for (y, width, color) in rails {
                let rect = CGRect(x: size.width * 0.31, y: size.height * y, width: size.width * width, height: 3)
                context.fill(Path(rect), with: .color(color))
            }
            context.stroke(
                Path(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)),
                with: .color(AppPalette.borderStrong),
                lineWidth: 1
            )
        }
        .accessibilityHidden(true)
    }
}
