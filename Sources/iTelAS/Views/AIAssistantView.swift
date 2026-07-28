import SwiftUI
import iTelASCore

struct AIAssistantView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            assistantHeader
            contextBar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 15) {
                        if model.assistantMessages.isEmpty {
                            welcome
                        }
                        ForEach(model.assistantMessages) { message in
                            AssistantMessageView(message: message)
                                .id(message.id)
                        }
                        if model.isAssistantResponding {
                            AssistantStreamingResponseView(
                                text: model.assistantStreamingText,
                                phase: model.assistantResponsePhase,
                                byteCount: model.assistantStreamingByteCount
                            )
                            .id("assistant-live-response")
                        }
                        if let error = model.assistantError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.danger)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppPalette.danger.opacity(0.08), in: ChamferedRectangle(cut: 4))
                        }
                    }
                    .padding(15)
                }
                .onChange(of: model.assistantMessages.count) {
                    if let last = model.assistantMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: model.assistantStreamingText) {
                    guard model.isAssistantResponding else { return }
                    proxy.scrollTo("assistant-live-response", anchor: .bottom)
                }
                .onChange(of: model.isAssistantResponding) {
                    if model.isAssistantResponding {
                        withAnimation { proxy.scrollTo("assistant-live-response", anchor: .bottom) }
                    }
                }
            }

            composer
        }
        .background(AppPalette.panel)
    }

    private var assistantHeader: some View {
        HStack(spacing: 9) {
            ITelASMark(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("iTelAS Assist")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("IBM i engineering copilot")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
            Button {
                model.selectedTool = .casebook
            } label: {
                WorkbenchGlyph(tool: .casebook, color: AppPalette.secondary, size: 15)
            }
            .buttonStyle(PrecisionIconButtonStyle(size: 27))
            .help("Open the Continuity Casebook")
            Button {
                model.openAIProposalPatchStack()
            } label: {
                UtilityGlyph(
                    kind: .patchStack,
                    color: model.aiProposalPatchStack.isEmpty ? AppPalette.secondary : AppPalette.ibmBlue,
                    size: 14
                )
                .overlay(alignment: .topTrailing) {
                    if !model.aiProposalPatchStack.isEmpty {
                        Text("\(model.aiProposalPatchStack.count)")
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(minWidth: 11, minHeight: 11)
                            .background(AppPalette.ibmBlue)
                            .offset(x: 5, y: -5)
                    }
                }
            }
            .buttonStyle(PrecisionIconButtonStyle(size: 27))
            .help("Open the Proposal Patch Stack")
            Button {
                model.clearAssistantConversation()
            } label: {
                UtilityGlyph(kind: .newConversation, color: AppPalette.secondary, size: 14)
            }
            .buttonStyle(PrecisionIconButtonStyle(size: 27))
            .help("New conversation")
            Button {
                model.isAssistantVisible = false
            } label: {
                UtilityGlyph(kind: .closePanel, color: AppPalette.secondary, size: 14)
            }
            .buttonStyle(PrecisionIconButtonStyle(size: 27))
            .help("Close assistant")
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var contextBar: some View {
        HStack(spacing: 8) {
            UtilityGlyph(
                kind: .contextShelf,
                color: model.preparedAssistantContextBundle == nil ? AppPalette.muted : AppPalette.ibmBlue,
                size: 15
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(model.preparedAssistantContextLabel ?? "Context Shelf empty")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text(preparedContextDetail)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
            if model.preparedAssistantContextBundle != nil {
                Button("Clear") {
                    model.clearPreparedAssistantContext()
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(AppPalette.secondary)
                .help("Remove the prepared evidence from the next Assist request")
            }
            Button("Shelf") {
                model.previewCurrentAIContext()
            }
            .buttonStyle(.plain)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(AppPalette.ibmBlue)
            .help("Open the Context Shelf and preview every exact item eligible for the next request")
            Toggle("", isOn: Binding(
                get: { model.includeScreenContext },
                set: { model.updateAutomaticScreenContext($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(model.aiConfiguration.contextMode == .none)
        }
        .padding(.horizontal, 13)
        .frame(height: 48)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var preparedContextDetail: String {
        if let bundle = model.preparedAssistantContextBundle {
            let screenSuffix = model.includeScreenContext ? " + redacted screen" : ""
            return "\(bundle.fragments.count) pinned · \(bundle.totalUTF8Bytes) bytes\(screenSuffix)"
        }
        return model.includeScreenContext ? "Automatic redacted screen eligible" : "Nothing attached by default"
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                UtilityGlyph(kind: .assistant, color: AppPalette.registrationBlue, size: 14)
                Text("ITELAS ASSIST")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.ibmBlue)
            Text("Ask about RPG, CL, COBOL, DDS, Db2 for i, jobs, messages, performance, authorities, or the visible terminal screen.")
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.secondary)
                .lineSpacing(3)

            ForEach([
                "Explain this screen without changing anything",
                "Diagnose a CPF message with read-only checks",
                "Review an RPG or CL approach",
                "Build a safe incident runbook"
            ], id: \.self) { suggestion in
                Button {
                    model.assistantInput = suggestion
                    model.askAssistant()
                } label: {
                    HStack {
                        UtilityGlyph(kind: .outbound, color: AppPalette.registrationBlue, size: 13)
                        Text(suggestion)
                            .foregroundStyle(AppPalette.text)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .overlay {
                        ChamferedRectangle(cut: 4)
                            .stroke(AppPalette.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            Label("AI never executes commands. You review every suggestion.", systemImage: "hand.raised.fill")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
                .padding(.top, 3)
        }
    }

    private var composer: some View {
        VStack(spacing: 7) {
            VStack(spacing: 8) {
                TextField(model.isAssistantResponding
                    ? "Response streaming — your draft is preserved"
                    : "Ask about this system, screen, or code…", text: Binding(
                    get: { model.assistantInput },
                    set: { model.assistantInput = $0 }
                ), axis: .vertical)
                    .font(.system(size: 11))
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .onSubmit { model.askAssistant() }

                HStack {
                    Button {
                        model.isAISettingsPresented = true
                    } label: {
                        UtilityGlyph(kind: .settings, color: AppPalette.secondary, size: 14)
                    }
                    .buttonStyle(PrecisionIconButtonStyle(size: 27))
                    .help("AI Assist settings")
                    Spacer()
                    if model.isAssistantResponding {
                        Button {
                            model.cancelAssistantResponse()
                        } label: {
                            HStack(spacing: 6) {
                                UtilityGlyph(kind: .stopGeneration, color: .white, size: 12)
                                Text("STOP")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(0.6)
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(AppPalette.text, in: ChamferedRectangle(cut: 3))
                            .overlay {
                                ChamferedRectangle(cut: 3)
                                    .stroke(AppPalette.registrationBlue, lineWidth: 1)
                            }
                        }
                        .help("Stop the response and keep any partial output clearly marked")
                        .accessibilityLabel("Stop AI response")
                    } else {
                        Button {
                            model.askAssistant()
                        } label: {
                            UtilityGlyph(kind: .send, color: .white, size: 13)
                                .frame(width: 28, height: 28)
                                .background(AppPalette.registrationBlue, in: ChamferedRectangle(cut: 4))
                        }
                        .disabled(model.assistantInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send to configured AI provider")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.muted)
            }
            .padding(10)
            .overlay {
                ChamferedRectangle(cut: 5)
                    .stroke(AppPalette.border, lineWidth: 1)
            }

            Label(
                model.apiKeyExists ? "API key in Keychain · send only on request" : "No API key configured",
                systemImage: model.apiKeyExists ? "key.fill" : "key"
            )
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(AppPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background(AppPalette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }
}

private struct AssistantMessageView: View {
    @Environment(AppModel.self) private var model
    let message: AssistantMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if message.role == .assistant {
                    UtilityGlyph(kind: .assistant, color: AppPalette.registrationBlue, size: 13)
                } else {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(AppPalette.secondary)
                }
                Text(message.role == .assistant ? "ITELAS ASSIST" : "YOU")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(message.role == .assistant ? AppPalette.ibmBlue : AppPalette.secondary)
                Spacer()
                if let risk = message.commandRisk {
                    CommandRiskBadge(risk: risk)
                }
                if message.completionState != .complete {
                    AssistantCompletionBadge(state: message.completionState)
                }
                if message.role == .assistant,
                   let receipt = model.assistantRequestReceipt(for: message) {
                    Button {
                        model.presentAssistantRequestReceipt(for: message)
                    } label: {
                        HStack(spacing: 4) {
                            UtilityGlyph(kind: .contextShelf, color: AppPalette.ibmBlue, size: 11)
                            Text("RECEIPT · \(receipt.contextBundle?.fragments.count ?? 0)")
                                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                                .tracking(0.35)
                        }
                        .foregroundStyle(AppPalette.ibmBlue)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(AppPalette.ibmBlue.opacity(0.08), in: ChamferedRectangle(cut: 2))
                        .overlay {
                            ChamferedRectangle(cut: 2)
                                .stroke(AppPalette.ibmBlue.opacity(0.55), lineWidth: 0.7)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Inspect this answer's immutable request receipt")
                    .accessibilityLabel("View immutable request receipt")
                } else if model.isAssistantRequestReceiptExpired(for: message) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("RECEIPT · EXPIRED")
                            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                            .tracking(0.3)
                    }
                    .foregroundStyle(AppPalette.warning)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(AppPalette.warning.opacity(0.09), in: ChamferedRectangle(cut: 2))
                    .overlay {
                        ChamferedRectangle(cut: 2)
                            .stroke(AppPalette.warning.opacity(0.55), lineWidth: 0.7)
                    }
                    .help("This chat keeps the \(AssistantRequestReceiptStore.standardMaximumCount) newest answer receipts")
                    .accessibilityLabel("Request receipt expired at the session limit")
                }
                if message.role == .assistant, message.provenance != nil {
                    Button {
                        model.recordAssistantMessageInCasebook(message)
                    } label: {
                        WorkbenchGlyph(
                            tool: .casebook,
                            color: model.isAssistantMessageRecorded(message) ? AppPalette.success : AppPalette.ibmBlue,
                            size: 12
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isAssistantMessageRecorded(message))
                    .help(model.isAssistantMessageRecorded(message)
                        ? "Recorded in the Continuity Casebook"
                        : "Record this response and its request summary in the Continuity Casebook")
                    .accessibilityLabel(model.isAssistantMessageRecorded(message)
                        ? "Response recorded in Casebook"
                        : "Record response in Casebook")
                }
                Button {
                    model.copyAssistantText(message.content)
                } label: {
                    UtilityGlyph(kind: .copy, color: AppPalette.muted, size: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.muted)
                .help("Copy message")
            }
            Text(.init(message.content))
                .textSelection(.enabled)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.text)
                .lineSpacing(3)
        }
        .padding(message.role == .user ? 10 : 0)
        .background(message.role == .user ? AppPalette.ibmBlue.opacity(0.08) : Color.clear)
        .clipShape(ChamferedRectangle(cut: 4))
    }
}

private struct AssistantStreamingResponseView: View {
    let text: String
    let phase: AIAssistantResponsePhase
    let byteCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                UtilityGlyph(kind: .streamRoute, color: AppPalette.registrationBlue, size: 13)
                Text(phase == .reviewing ? "ITELAS ASSIST / COMPLETE REVIEW" : "ITELAS ASSIST / LIVE RESPONSE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.ibmBlue)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    PhaseAnimator([false, true]) { active in
                        Circle()
                            .fill(AppPalette.registrationBlue)
                            .frame(width: 5, height: 5)
                            .opacity(active ? 1 : 0.34)
                    } animation: { _ in
                        .easeInOut(duration: 0.72)
                    }
                    Text(phase == .reviewing ? "VALIDATING" : phase == .connecting ? "OPENING" : "STREAMING")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppPalette.ibmBlue.opacity(0.08), in: ChamferedRectangle(cut: 2))
                .overlay {
                    ChamferedRectangle(cut: 2)
                        .stroke(AppPalette.ibmBlue.opacity(0.24), lineWidth: 0.7)
                }
            }

            Text(displayedText)
                .textSelection(.enabled)
                .font(.system(size: 11))
                .foregroundStyle(text.isEmpty ? AppPalette.muted : AppPalette.text)
                .lineSpacing(3)

            HStack(spacing: 9) {
                UtilityGlyph(kind: .streamRoute, color: AppPalette.registrationBlue, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(phase.channelLabel)
                        .font(.system(size: 7.8, weight: .bold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(AppPalette.text)
                    Text(receiptLabel)
                        .font(.system(size: 7.8, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer(minLength: 2)
                Text("STOP AVAILABLE")
                    .font(.system(size: 7.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            .padding(.horizontal, 9)
            .frame(height: 40)
            .background(AppPalette.raised, in: ChamferedRectangle(cut: 3))
            .overlay {
                ChamferedRectangle(cut: 3)
                    .stroke(AppPalette.border, lineWidth: 1)
            }

            HStack(spacing: 7) {
                UtilityGlyph(kind: .provisionalBoundary, color: AppPalette.warning, size: 13)
                Text(phase == .reviewing
                    ? "Proposal remains inert until the complete envelope validates"
                    : "Provisional output · commands unlock only after completion")
                    .font(.system(size: 8.2, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppPalette.registrationBlue)
                .frame(width: 2)
        }
    }

    private var displayedText: String {
        if !text.isEmpty { return text }
        return phase == .reviewing
            ? "Waiting for the complete local-edit proposal envelope…"
            : "Opening a bounded response channel to the configured provider…"
    }

    private var receiptLabel: String {
        guard byteCount > 0 else {
            return phase == .reviewing
                ? "Whole response required · context receipt locked"
                : "Waiting for first event · context receipt locked"
        }
        let size: String
        if byteCount < 1_024 {
            size = "\(byteCount) B"
        } else {
            size = String(format: "%.1f KB", Double(byteCount) / 1_024)
        }
        return "\(size) received · context receipt locked"
    }
}

private struct AssistantCompletionBadge: View {
    let state: AssistantMessage.CompletionState

    var body: some View {
        Text(label)
            .font(.system(size: 7.3, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.09), in: ChamferedRectangle(cut: 2))
            .overlay {
                ChamferedRectangle(cut: 2)
                    .stroke(color.opacity(0.28), lineWidth: 0.7)
            }
    }

    private var label: String {
        switch state {
        case .complete: "COMPLETE"
        case .stopped: "STOPPED BY OPERATOR"
        case .interrupted: "STREAM INTERRUPTED"
        }
    }

    private var color: Color {
        switch state {
        case .complete: AppPalette.success
        case .stopped: AppPalette.warning
        case .interrupted: AppPalette.danger
        }
    }
}

private struct CommandRiskBadge: View {
    let risk: CommandRisk

    var body: some View {
        let color: Color = switch risk {
        case .readOnly: AppPalette.success
        case .mutating: AppPalette.warning
        case .destructive: AppPalette.danger
        case .unknown: AppPalette.muted
        }
        Text(risk.rawValue.uppercased())
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: ChamferedRectangle(cut: 3))
            .overlay {
                ChamferedRectangle(cut: 3)
                    .stroke(color.opacity(0.24), lineWidth: 0.7)
            }
    }
}
