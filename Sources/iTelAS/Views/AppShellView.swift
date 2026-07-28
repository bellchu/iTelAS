import AppKit
import SwiftUI
import iTelASCore

struct AppShellView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ZStack {
            VStack(spacing: 0) {
                AppTitleBar()
                HStack(spacing: 0) {
                    if model.selectedTool == .sourceWorkspace
                        || model.selectedTool == .sqlStudio
                        || model.selectedTool == .objectGraph
                        || model.selectedTool == .buildAndTest
                        || model.selectedTool == .jobsAndQueues
                        || model.selectedTool == .spoolAndOutput
                        || model.selectedTool == .transferCenter
                        || model.selectedTool == .systemHealth
                        || model.selectedTool == .automation
                        || model.selectedTool == .securityAdvisor
                        || model.selectedTool == .casebook {
                        WorkbenchInstrumentRailView()
                            .frame(width: 68)
                    } else {
                        SidebarView()
                            .frame(width: 238)
                    }

                    Rectangle()
                        .fill(AppPalette.border)
                        .frame(width: 1)

                    Group {
                        switch model.selectedTool {
                        case .terminal:
                            SessionWorkspaceView()
                        case .commandCenter:
                            CommandCenterView()
                        case .sourceWorkspace:
                            SourceWorkspaceView()
                        case .sqlStudio:
                            SQLWorkspaceView()
                        case .objectGraph:
                            ObjectImpactView()
                        case .buildAndTest:
                            CompileEvidenceTimelineView()
                        case .jobsAndQueues:
                            JobIncidentThreadView()
                        case .spoolAndOutput:
                            SpoolOutputView()
                        case .transferCenter:
                            DataTransferView()
                        case .systemHealth:
                            SystemHealthView()
                        case .automation:
                            RunbookFlightDeckView()
                        case .securityAdvisor:
                            AuthorityPathAtlasView()
                        case .casebook:
                            ContinuityCasebookView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if model.isAssistantVisible {
                        Rectangle()
                            .fill(AppPalette.border)
                            .frame(width: 1)
                        AIAssistantView()
                            .frame(width: 366)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }

            if model.isCommandPalettePresented {
                CommandPaletteView()
                    .environment(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(20)
            }
        }
        .background(AppPalette.window)
        .sheet(isPresented: $model.isConnectionStudioPresented) {
            ConnectionStudioView()
                .environment(model)
        }
        .sheet(isPresented: $model.isAISettingsPresented) {
            AISettingsView()
                .environment(model)
                .frame(width: 620, height: 560)
        }
        .sheet(isPresented: $model.isScreenHistoryPresented) {
            TerminalFlightRecorderView()
                .environment(model)
                .frame(width: 1_360, height: 840)
        }
        .sheet(isPresented: $model.isSourceWorkspaceIndexPresented) {
            SourceCrossReferenceAtlasView()
                .environment(model)
                .frame(width: 1_360, height: 840)
        }
        .sheet(isPresented: $model.isProviderBayPresented) {
            ProviderBayView()
                .environment(model)
                .frame(width: 1_180, height: 780)
        }
        .sheet(isPresented: $model.isSecureChannelDossierPresented) {
            SecureChannelDossierView()
                .environment(model)
                .frame(width: 1_180, height: 760)
        }
        .sheet(isPresented: $model.isDb2ConnectionDossierPresented) {
            Db2ConnectionDossierView()
                .environment(model)
                .frame(width: 1_220, height: 790)
        }
        .sheet(isPresented: $model.isAIReviewDossierPresented) {
            AIReviewDossierView()
                .environment(model)
                .frame(width: 1_320, height: 820)
        }
        .sheet(isPresented: $model.isAIContextPreviewPresented) {
            AIContextPreviewView()
                .environment(model)
                .frame(width: 1_260, height: 790)
        }
        .sheet(item: $model.selectedAssistantRequestReceipt) { receipt in
            AIContextPreviewView(receipt: receipt)
                .environment(model)
                .frame(width: 1_260, height: 790)
        }
        .sheet(isPresented: $model.isAIProposalPatchStackPresented) {
            AIProposalPatchStackView()
                .environment(model)
                .frame(width: 1_320, height: 820)
        }
        .sheet(isPresented: $model.isContinuityReferenceReviewPresented) {
            ContinuityReferenceReviewView()
                .environment(model)
                .frame(width: 960, height: 720)
        }
        .sheet(isPresented: $model.isContinuitySnapshotPresented) {
            ContinuityHandoffSnapshotView()
                .environment(model)
                .frame(width: 1_040, height: 760)
        }
        .alert(
            "Delete session profile?",
            isPresented: Binding(
                get: { model.profilePendingDeletion != nil },
                set: { if !$0 { model.profilePendingDeletion = nil } }
            ),
            presenting: model.profilePendingDeletion
        ) { profile in
            Button("Delete “\(profile.name)”", role: .destructive) {
                model.deleteProfile(profile)
            }
            Button("Cancel", role: .cancel) {
                model.profilePendingDeletion = nil
            }
        } message: { profile in
            Text(profile.deletionConfirmationMessage)
        }
        .onAppear { model.rotateProverb() }
        .onDisappear { model.flushLocalDrafts() }
        .onChange(of: model.selectedTool) { model.rotateProverb() }
        .onChange(of: model.terminalAlarmSignal) { previous, current in
            guard current > previous else { return }
            NSSound.beep()
        }
        .animation(.snappy(duration: 0.22), value: model.isAssistantVisible)
        .animation(.easeOut(duration: 0.16), value: model.isCommandPalettePresented)
    }
}

private struct AppTitleBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            BrandWordmark(compact: true)

            Divider().frame(height: 22)

            ProverbRibbon(proverb: model.proverb, compact: true)

            Spacer(minLength: 16)

            connectionStatus

            Button {
                model.isCommandPalettePresented = true
            } label: {
                UtilityGlyph(kind: .commandPalette, size: 15)
            }
            .buttonStyle(PrecisionIconButtonStyle())
            .help("Open Command Palette (⌘K)")

            Button {
                model.isAssistantVisible.toggle()
            } label: {
                UtilityGlyph(kind: .assistant, size: 16)
            }
            .buttonStyle(PrecisionIconButtonStyle())
            .help(model.isAssistantVisible ? "Hide iTelAS Assist" : "Show iTelAS Assist")

            Button {
                model.isAISettingsPresented = true
            } label: {
                UtilityGlyph(kind: .settings, size: 16)
            }
            .buttonStyle(PrecisionIconButtonStyle())
            .help("Settings")
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.secondary)
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        let status: (text: String, color: Color) = switch model.connectionState {
        case .connected:
            (model.selectedProfile?.name.uppercased() ?? "CONNECTED", AppPalette.success)
        case .connecting, .negotiating:
            ("CONNECTING", AppPalette.warning)
        case .failed:
            ("CONNECTION ERROR", AppPalette.danger)
        case .waiting:
            ("WAITING", AppPalette.warning)
        case .disconnected:
            ("OFFLINE", AppPalette.muted)
        }
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(status.text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.1), in: ChamferedRectangle(cut: 4))
        .overlay {
            ChamferedRectangle(cut: 4)
                .stroke(status.color.opacity(0.28), lineWidth: 0.7)
        }
    }
}
