import SwiftUI
import iTelASCore

struct TerminalFlightRecorderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var proverb = WorkbenchProverb.random()
    @State private var confirmClear = false
    @State private var confirmDeleteMacro = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            custodyBand
            HStack(spacing: 0) {
                historyRail
                    .frame(width: 270)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                evidenceStage
                Rectangle().fill(AppPalette.border).frame(width: 1)
                macroStudio
                    .frame(width: 370)
            }
            footer
        }
        .background(AppPalette.window)
        .onAppear {
            proverb = .random(excluding: proverb.id)
            if model.selectedTerminalEvidenceFrameID == nil {
                model.selectedTerminalEvidenceFrameID = model.terminalFlightRecorder.frames.last?.id
            }
            if model.selectedTerminalMacroID == nil {
                model.selectedTerminalMacroID = model.terminalFlightRecorder.macros.first?.id
            }
        }
        .sheet(item: $model.terminalMacroEditorDraft) { draft in
            TerminalMacroEditorView(initialDraft: draft)
                .environment(model)
                .frame(width: 820, height: 720)
        }
        .confirmationDialog(
            "Clear recorder evidence?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Clear Frames and Receipts", role: .destructive) {
                model.clearTerminalRecorderEvidence()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reviewed macro definitions remain. Cleared redacted frames and execution receipts cannot be restored by iTelAS.")
        }
        .confirmationDialog(
            "Delete selected macro?",
            isPresented: $confirmDeleteMacro,
            titleVisibility: .visible
        ) {
            Button("Delete Macro and Receipts", role: .destructive) {
                model.deleteSelectedTerminalMacro()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandWordmark(compact: true)
            Rectangle().fill(AppPalette.border).frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("SESSION FLIGHT RECORDER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Redacted evidence + reviewed macros")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }

            Spacer()

            RecorderBadge(
                label: model.terminalFlightRecorderUsesReplay ? "LOCAL REPLAY" : "LOCAL VAULT",
                color: model.terminalFlightRecorderUsesReplay ? AppPalette.warning : AppPalette.success
            )
            RecorderBadge(
                label: "\(model.terminalFlightRecorder.frames.count) FRAMES · \(model.terminalFlightRecorder.policy.retention.rawValue) DAYS",
                color: AppPalette.registrationBlue
            )

            Menu {
                ForEach(TerminalHistoryRetention.allCases) { retention in
                    Button {
                        model.updateTerminalHistoryRetention(retention)
                    } label: {
                        if retention == model.terminalFlightRecorder.policy.retention {
                            Label(retention.label, systemImage: "checkmark")
                        } else {
                            Text(retention.label)
                        }
                    }
                }
                Divider()
                Button("Export redacted archive…") { model.exportTerminalFlightRecorderArchive() }
                Button("Clear frames and receipts…", role: .destructive) { confirmClear = true }
            } label: {
                Text("Retention")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 92)

            recorderArmButton

            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    @ViewBuilder
    private var recorderArmButton: some View {
        if model.selectedTerminalSession == nil {
            Button("Open Session to Arm") {}
                .buttonStyle(SecondaryButtonStyle())
                .disabled(true)
        } else if model.isSelectedTerminalRecorderArmed {
            Button {
                model.toggleTerminalFlightRecorder()
            } label: {
                HStack(spacing: 7) {
                    Circle().fill(AppPalette.danger).frame(width: 7, height: 7)
                    Text("Disarm")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.selectedTerminalSession == nil)
        } else {
            Button {
                model.toggleTerminalFlightRecorder()
            } label: {
                HStack(spacing: 7) {
                    Circle().fill(Color.white.opacity(0.75)).frame(width: 7, height: 7)
                    Text("Arm Session")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.selectedTerminalSession == nil)
        }
    }

    private var custodyBand: some View {
        HStack(spacing: 18) {
            FlightRecorderRouteMark(size: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text("ACTIVE SESSION")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.terminalGreen)
                Text(activeSessionName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(activeSessionDetail)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 295, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text("CUSTODY CONTRACT")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.terminal(.turquoise))
                Text("Visible host output only")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("Every input field is cleared · non-display content is never saved · identical frames collapse")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text("LOCAL VAULT")
                        .foregroundStyle(AppPalette.warning)
                    Text("0700 / 0600")
                        .foregroundStyle(AppPalette.terminalGreen)
                }
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                if let frame = model.selectedTerminalEvidenceFrame {
                    Text("FRAME \(frame.shortFingerprint)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                } else {
                    Text("NO DURABLE FRAME SELECTED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                Text("Provider idle · API key unread · host writes require an explicit macro step")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 88)
        .background(AppPalette.instrument)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
    }

    private var historyRail: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DURABLE TAPE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Spacer()
                    Text("\(model.terminalFlightRecorder.frames.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                }
                Text("Screen evidence")
                    .font(.system(size: 18, weight: .bold))
                Text("Newest first · retained across restarts")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 7) {
                UtilityGlyph(kind: .history, color: AppPalette.secondary, size: 12)
                Text("THIS ARCHIVE · NEWEST FIRST")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                Spacer()
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if model.terminalFlightRecorder.frames.isEmpty {
                ContentUnavailableView(
                    "No durable frames",
                    systemImage: "record.circle",
                    description: Text("Arm a session or bookmark the current screen. Input fields are cleared before storage.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.terminalFlightRecorder.frames.reversed()) { frame in
                            RecorderFrameRow(
                                frame: frame,
                                selected: model.selectedTerminalEvidenceFrameID == frame.id
                            ) {
                                model.selectTerminalEvidenceFrame(frame.id)
                            }
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                HStack {
                    Text("RETENTION")
                    Spacer()
                    Text(model.terminalFlightRecorder.policy.retention.label)
                        .foregroundStyle(AppPalette.ibmBlue)
                }
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))

                RecorderRetentionGauge(
                    used: min(model.terminalFlightRecorder.frames.count, 12),
                    capacity: 12
                )

                Button {
                    model.bookmarkCurrentTerminalFrame()
                } label: {
                    HStack(spacing: 6) {
                        UtilityGlyph(kind: .capture, color: AppPalette.text, size: 12)
                        Text("Bookmark Current Screen")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.selectedTerminalSession == nil)
            }
            .padding(12)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    @ViewBuilder
    private var evidenceStage: some View {
        if let frame = model.selectedTerminalEvidenceFrame {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXACT REDACTED EVIDENCE")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(AppPalette.ibmBlue)
                        Text(frame.title)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Copy Redacted") { model.copySelectedTerminalEvidence() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Export Evidence") { model.exportSelectedTerminalEvidence() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(AppPalette.panel)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Circle().fill(AppPalette.terminalGreen).frame(width: 7, height: 7)
                        Text("\(frame.deviceName ?? "AUTO DEVICE") · \(frame.profileName)")
                            .fontWeight(.bold)
                        Text("·")
                        Text("\(frame.rows)×\(frame.columns) · \(frame.readMode.label)")
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text(frame.capturedAt.formatted(date: .omitted, time: .standard))
                            .foregroundStyle(AppPalette.terminal(.turquoise))
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(AppPalette.terminalRaised)

                    TerminalCanvasView(screen: frame.previewScreen)
                }
                .background(AppPalette.terminal)
                .overlay { Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1) }
                .padding(13)

                evidenceReceipt(frame)
            }
        } else {
            ContentUnavailableView(
                "No terminal evidence",
                systemImage: "rectangle.and.text.magnifyingglass",
                description: Text("Durable history is opt-in. Arm an open session to begin retaining redacted host frames.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.window)
        }
    }

    private func evidenceReceipt(_ frame: TerminalEvidenceFrame) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text("EVIDENCE RECEIPT")
                    .foregroundStyle(AppPalette.ibmBlue)
                Spacer()
                Text("VERIFIED LOCAL RECORD")
                    .foregroundStyle(AppPalette.success)
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))

            HStack(spacing: 1) {
                RecorderMetric(label: "FINGERPRINT", value: frame.shortFingerprint)
                RecorderMetric(label: "INPUT CLEARED", value: "\(frame.clearedInputFieldCount)")
                RecorderMetric(label: "SENSITIVE ROWS", value: "\(frame.clearedSensitiveRowCount)")
                RecorderMetric(label: "SOURCE", value: "HOST DISPLAY")
            }
            .background(AppPalette.border)

            HStack(spacing: 9) {
                Rectangle().fill(AppPalette.warning).frame(width: 4, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Replay is evidence, not keystroke automation.")
                        .font(.system(size: 10.5, weight: .bold))
                    Text("A frame may gate one reviewed macro step; it cannot reconnect, restore input, or run a route.")
                        .font(.system(size: 8))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                Button("New Macro From Frame") { model.beginNewTerminalMacroDraft() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .background(AppPalette.panel)
    }

    private var macroStudio: some View {
        VStack(spacing: 0) {
            macroHeader
            macroToolbar

            if let macro = model.selectedTerminalMacro {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(macro.steps.enumerated()), id: \.element.id) { index, step in
                            MacroRouteStepRow(
                                ordinal: index + 1,
                                step: step,
                                state: macroStepState(index: index, macro: macro)
                            )
                        }
                    }
                }
                macroExecutionGate(macro)
            } else {
                ContentUnavailableView(
                    "No macro drafts",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Create a route from reviewed screen evidence. Every live step remains an operator action.")
                )
                .frame(maxHeight: .infinity)

                Button("Create Macro Draft") { model.beginNewTerminalMacroDraft() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(14)
            }
        }
        .background(AppPalette.panel)
    }

    private var macroHeader: some View {
        HStack(spacing: 10) {
            FlightRecorderRouteMark(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("REVIEWED MACRO")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                if let macro = model.selectedTerminalMacro {
                    Text(macro.name)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Text("\(macro.shortFingerprint) · \(macro.steps.count) STEPS")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                } else {
                    Text("Macro studio")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            Spacer()
            if let macro = model.selectedTerminalMacro {
                RecorderBadge(
                    label: macro.isReviewCurrent ? "REVIEWED" : "DRAFT",
                    color: macro.isReviewCurrent ? AppPalette.success : AppPalette.warning
                )
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 78)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var macroToolbar: some View {
        HStack(spacing: 7) {
            Menu {
                ForEach(model.terminalFlightRecorder.macros) { macro in
                    Button {
                        model.selectTerminalMacro(macro.id)
                    } label: {
                        if macro.id == model.selectedTerminalMacroID {
                            Label(macro.name, systemImage: "checkmark")
                        } else {
                            Text(macro.name)
                        }
                    }
                }
            } label: {
                Text("Macro Library")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button("Edit") { model.editSelectedTerminalMacroAsDraft() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.selectedTerminalMacro == nil)
            Button("New") { model.beginNewTerminalMacroDraft() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func macroExecutionGate(_ macro: ReviewedTerminalMacro) -> some View {
        let nextIndex = currentMacroStepIndex(macro)
        let isComplete = nextIndex >= macro.steps.count
        let nextStep = isComplete ? nil : macro.steps[nextIndex]
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(isComplete ? "ROUTE COMPLETE" : "SELECTED STEP / \(String(format: "%02d", nextIndex + 1))")
                    .foregroundStyle(isComplete ? AppPalette.success : AppPalette.ibmBlue)
                Spacer()
                Text(model.selectedTerminalSession == nil ? "SESSION REQUIRED" : "OPERATOR GATE")
                    .foregroundStyle(model.selectedTerminalSession == nil ? AppPalette.warning : AppPalette.success)
            }
            .font(.system(size: 7.2, weight: .bold, design: .monospaced))

            Text(nextStep?.name ?? "Every reviewed step has passed")
                .font(.system(size: 12.5, weight: .bold))
                .lineLimit(1)
            Text(isComplete
                ? "Reset the route to begin again. Existing receipts remain durable."
                : "Only this step may run. The route pauses before evaluating the next host screen.")
                .font(.system(size: 8.3))
                .foregroundStyle(AppPalette.secondary)
                .lineLimit(2)

            if macro.isReviewCurrent {
                if isComplete {
                    Button("Reset Route") { model.resetSelectedTerminalMacroRun() }
                        .buttonStyle(SecondaryButtonStyle())
                } else if model.selectedTerminalSession == nil {
                    Button("Select Open Session") {}
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(true)
                } else {
                    Button("Run Selected Step") { model.runSelectedTerminalMacroStep() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                Button("Review Exact Draft") { model.attestSelectedTerminalMacroReview() }
                    .buttonStyle(PrimaryButtonStyle())
            }

            HStack {
                Text("No background playback · no secret fields · no automatic chain")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                Menu {
                    Button("Duplicate as Draft") { model.duplicateSelectedTerminalMacroAsDraft() }
                    Button("Delete Macro…", role: .destructive) { confirmDeleteMacro = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(12)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(model.isSelectedTerminalRecorderArmed ? "RECORDER: ARMED" : "RECORDER: OFF")
                .foregroundStyle(model.isSelectedTerminalRecorderArmed ? AppPalette.terminalGreen : .white.opacity(0.52))
            Text("FRAMES: \(model.terminalFlightRecorder.frames.count)")
                .foregroundStyle(AppPalette.terminal(.turquoise))
            Text(model.terminalFlightRecorderDiagnostic)
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .font(.system(size: 8, design: .default).italic())
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
            Text("ARM64 · LOCAL CUSTODY")
                .foregroundStyle(.white)
        }
        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        .padding(.horizontal, 13)
        .frame(height: 30)
        .background(AppPalette.instrument)
    }

    private var activeSessionName: String {
        if let profile = model.selectedProfile {
            let device = model.startupResponse?.deviceName ?? profile.deviceName
            return device.isEmpty ? profile.name : "\(profile.name) · \(device)"
        }
        return model.terminalFlightRecorderUsesReplay ? "DEV ORION · QPADEV0041" : "NO SESSION SELECTED"
    }

    private var activeSessionDetail: String {
        if let profile = model.selectedProfile {
            return "\(profile.terminalModel.displayName) · CCSID \(profile.ccsid) · \(profile.environment.rawValue.uppercased())"
        }
        return model.terminalFlightRecorderUsesReplay
            ? "LOCAL REPLAY · 24×80 · CCSID 37"
            : "Recorder remains off until an operator arms an open session"
    }

    private func currentMacroStepIndex(_ macro: ReviewedTerminalMacro) -> Int {
        guard let run = model.terminalMacroRunState,
              run.macroID == macro.id,
              run.macroFingerprint == macro.contentFingerprint else {
            if model.terminalFlightRecorderUsesReplay {
                return min(2, macro.steps.count)
            }
            return 0
        }
        return run.nextStepIndex
    }

    private func macroStepState(index: Int, macro: ReviewedTerminalMacro) -> MacroRouteStepState {
        let current = currentMacroStepIndex(macro)
        if index < current { return .passed }
        if index == current, index < macro.steps.count { return .next }
        return .waiting
    }
}

private struct RecorderFrameRow: View {
    let frame: TerminalEvidenceFrame
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle()
                        .fill(AppPalette.border)
                        .frame(width: 1)
                    Circle()
                        .fill(selected ? AppPalette.ibmBlue : AppPalette.panel)
                        .overlay { Circle().stroke(selected ? AppPalette.ibmBlue : AppPalette.borderStrong, lineWidth: 1) }
                        .frame(width: 8, height: 8)
                }
                .frame(width: 18, height: 62)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(frame.capturedAt.formatted(date: .omitted, time: .standard))
                        Spacer()
                        if selected { Text("SELECTED") }
                    }
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.muted)
                    Text(frame.title)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(1)
                    Text("\(frame.profileName) · \(frame.shortFingerprint)")
                        .font(.system(size: 7.2, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                        .lineLimit(1)
                    Text("\(frame.clearedInputFieldCount) INPUT CLEARED")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(frame.clearedInputFieldCount > 0 ? AppPalette.warning : AppPalette.success)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 70)
            .background(selected ? AppPalette.ibmBlue.opacity(0.075) : AppPalette.panel)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.7)).frame(height: 1) }
    }
}

private struct RecorderBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 3, height: 14)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(color.opacity(0.08), in: ChamferedRectangle(cut: 3))
        .overlay { ChamferedRectangle(cut: 3).stroke(color.opacity(0.75), lineWidth: 0.8) }
    }
}

private struct RecorderMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(AppPalette.raised)
    }
}

private struct RecorderRetentionGauge: View {
    let used: Int
    let capacity: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<capacity, id: \.self) { index in
                Rectangle()
                    .fill(index < used ? AppPalette.ibmBlue : AppPalette.border)
                    .frame(maxWidth: .infinity, minHeight: 5, maxHeight: 5)
            }
        }
        .accessibilityLabel("Recorder retention utilization")
        .accessibilityValue("\(used) of \(capacity) sample segments used")
    }
}

private enum MacroRouteStepState {
    case passed
    case next
    case waiting

    var color: Color {
        switch self {
        case .passed: AppPalette.success
        case .next: AppPalette.ibmBlue
        case .waiting: AppPalette.muted
        }
    }

    var label: String {
        switch self {
        case .passed: "PASSED"
        case .next: "NEXT"
        case .waiting: "WAIT"
        }
    }
}

private struct MacroRouteStepRow: View {
    let ordinal: Int
    let step: ReviewedTerminalMacroStep
    let state: MacroRouteStepState

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Rectangle().fill(AppPalette.borderStrong).frame(width: 1)
                Text(String(format: "%02d", ordinal))
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(state == .waiting ? state.color : .white)
                    .frame(width: 22, height: 22)
                    .background(state == .waiting ? AppPalette.panel : state.color, in: ChamferedRectangle(cut: 3))
                    .overlay { ChamferedRectangle(cut: 3).stroke(state.color, lineWidth: 1) }
            }
            .frame(width: 28, height: 58)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.action.kindLabel)
                    Spacer()
                    Text(state.label)
                }
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(state.color)
                Text(step.name)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text(step.action.title)
                    .font(.system(size: 7.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 66)
        .background(state == .next ? AppPalette.ibmBlue.opacity(0.07) : AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct FlightRecorderRouteMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.035), lineCap: .square, lineJoin: .miter)

            for centerX in [w * 0.28, w * 0.72] {
                var reel = Path()
                reel.addEllipse(in: CGRect(x: centerX - w * 0.16, y: h * 0.12, width: w * 0.32, height: h * 0.32))
                context.stroke(reel, with: .color(centerX < w / 2 ? AppPalette.terminalGreen : AppPalette.terminal(.turquoise)), style: stroke)
                context.fill(
                    Path(ellipseIn: CGRect(x: centerX - w * 0.045, y: h * 0.235, width: w * 0.09, height: h * 0.09)),
                    with: .color(centerX < w / 2 ? AppPalette.terminalGreen : AppPalette.terminal(.turquoise))
                )
            }

            var route = Path()
            route.move(to: CGPoint(x: w * 0.14, y: h * 0.42))
            route.addCurve(
                to: CGPoint(x: w * 0.5, y: h * 0.72),
                control1: CGPoint(x: w * 0.2, y: h * 0.78),
                control2: CGPoint(x: w * 0.38, y: h * 0.78)
            )
            route.addCurve(
                to: CGPoint(x: w * 0.86, y: h * 0.42),
                control1: CGPoint(x: w * 0.62, y: h * 0.66),
                control2: CGPoint(x: w * 0.78, y: h * 0.58)
            )
            context.stroke(route, with: .color(.white.opacity(0.9)), style: stroke)
            context.fill(
                Path(CGRect(x: w * 0.44, y: h * 0.67, width: w * 0.12, height: h * 0.18)),
                with: .color(AppPalette.registrationBlue)
            )
        }
        .frame(width: size, height: size)
        .padding(size * 0.08)
        .background(AppPalette.terminalRaised, in: ChamferedRectangle(cut: size * 0.12))
        .overlay { ChamferedRectangle(cut: size * 0.12).stroke(AppPalette.registrationBlue, lineWidth: 0.8) }
        .accessibilityHidden(true)
    }
}

private struct TerminalMacroEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TerminalMacroEditorDraft
    @State private var validationMessage: String?

    init(initialDraft: TerminalMacroEditorDraft) {
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                FlightRecorderRouteMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MACRO DRAFT EDITOR")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Every edit invalidates the prior local review")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Save Draft") {
                    if model.saveTerminalMacroDraft(draft) {
                        dismiss()
                    } else {
                        validationMessage = model.terminalFlightRecorderDiagnostic
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MACRO IDENTITY")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                    TextField("Macro name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                    Picker("Target", selection: $draft.targetProfileID) {
                        Text("Any selected profile").tag(UUID?.none)
                        ForEach(model.profiles) { profile in
                            Text(profile.name).tag(UUID?.some(profile.id))
                        }
                        if model.profiles.isEmpty,
                           let replayProfileID = model.selectedTerminalEvidenceFrame?.profileID {
                            Text("Replay profile").tag(UUID?.some(replayProfileID))
                        }
                    }
                    .pickerStyle(.menu)
                }
                .frame(width: 250)

                VStack(alignment: .leading, spacing: 5) {
                    Text("REVIEW BOUNDARY")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.warning)
                    Text("Saving creates a draft. A separate Review Exact Draft action freezes its fingerprint before any live step can run.")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                    Text("Commands are staged only in recognized visible command fields. Credentials and secret assignments are rejected.")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, _ in
                        macroEditorStep(index)
                    }
                    Button {
                        draft.steps.append(TerminalMacroEditorStepDraft())
                    } label: {
                        HStack(spacing: 6) {
                            UtilityGlyph(kind: .add, color: AppPalette.ibmBlue, size: 12)
                            Text("Add Step")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 2)
                }
                .padding(16)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.danger)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .background(AppPalette.danger.opacity(0.06))
            }

            HStack {
                Text("LOCAL DRAFT · NO PROVIDER · NO HOST ACTION")
                    .foregroundStyle(AppPalette.terminalGreen)
                Spacer()
                Text("Maximum 32 steps · one explicit step at a time")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(AppPalette.instrument)
        }
        .background(AppPalette.window)
    }

    private func macroEditorStep(_ index: Int) -> some View {
        let binding = $draft.steps[index]
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 27, height: 27)
                    .background(AppPalette.ibmBlue, in: ChamferedRectangle(cut: 4))
                TextField("Step name", text: binding.name)
                    .textFieldStyle(.roundedBorder)
                Picker("Action", selection: binding.kind) {
                    ForEach(TerminalMacroEditorActionKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 205)
                Button {
                    guard index > 0 else { return }
                    draft.steps.swapAt(index, index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                Button {
                    guard index + 1 < draft.steps.count else { return }
                    draft.steps.swapAt(index, index + 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(index + 1 == draft.steps.count)
                Button(role: .destructive) {
                    if draft.steps.count > 1 { draft.steps.remove(at: index) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(draft.steps.count == 1)
            }

            switch draft.steps[index].kind {
            case .matchFrame:
                Picker("Required redacted frame", selection: binding.frameFingerprint) {
                    if model.terminalFlightRecorder.frames.isEmpty {
                        Text("No evidence frames available").tag("")
                    }
                    ForEach(model.terminalFlightRecorder.frames.reversed()) { frame in
                        Text("\(frame.title) · \(frame.shortFingerprint)").tag(frame.screenFingerprint)
                    }
                }
                .pickerStyle(.menu)
            case .stageReadOnlyCommand:
                TextField("Read-only IBM i command", text: binding.command)
                    .textFieldStyle(.roundedBorder)
            case .fieldExit:
                Picker("Field action", selection: binding.fieldExit) {
                    ForEach(TerminalMacroFieldExit.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            case .sendAID:
                Picker("Host key", selection: binding.aidCode) {
                    ForEach(Self.aidOptions, id: \.code) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
            case .bookmark:
                Text("Captures the current screen through the same input-clearing and sensitive-row policy.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
        }
        .padding(12)
        .background(AppPalette.panel, in: ChamferedRectangle(cut: 5))
        .overlay { ChamferedRectangle(cut: 5).stroke(AppPalette.border, lineWidth: 1) }
    }

    private static let aidOptions: [(label: String, code: UInt8)] = {
        var result: [(String, UInt8)] = [
            ("Enter", TN5250AID.enter.rawValue),
            ("Help", TN5250AID.help.rawValue),
            ("Clear", TN5250AID.clear.rawValue),
            ("Roll Up", TN5250AID.rollUp.rawValue),
            ("Roll Down", TN5250AID.rollDown.rawValue)
        ]
        result += [1, 3, 4, 5, 9, 12, 13, 24].compactMap { number in
            TN5250AID.function(number).map { ("F\(number)", $0) }
        }
        return result
    }()
}
