import SwiftUI
import iTelASCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    systemsHeader

                    if model.profiles.isEmpty {
                        emptySystems
                    } else {
                        ForEach(model.profiles) { profile in
                            SessionProfileRow(
                                profile: profile,
                                sessions: model.sessions(for: profile),
                                selected: model.selectedProfileID == profile.id
                            ) {
                                model.selectProfile(profile)
                                model.selectedTool = .terminal
                            } connect: {
                                model.connect(profile)
                                model.selectedTool = .terminal
                            } openAdditional: {
                                model.openAdditionalSession(profile)
                                model.selectedTool = .terminal
                            } edit: {
                                model.presentEditSession(profile)
                            } delete: {
                                model.requestDeleteProfile(profile)
                            }
                        }
                    }

                    Rectangle()
                        .fill(AppPalette.border)
                        .frame(height: 1)
                        .padding(.vertical, 9)

                    ForEach(ToolGroup.allCases) { group in
                        Text(group.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(AppPalette.muted)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)

                        ForEach(WorkbenchTool.allCases.filter { $0.group == group }) { tool in
                            ToolRow(tool: tool, selected: model.selectedTool == tool) {
                                model.selectedTool = tool
                            }
                        }
                    }
                }
                .padding(8)
            }

            systemFooter
        }
        .background(AppPalette.panel)
    }

    private var systemsHeader: some View {
        HStack {
            Text("IBM i SYSTEMS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(AppPalette.muted)
            Spacer()
            Button {
                model.presentNewSession()
            } label: {
                UtilityGlyph(kind: .add, color: AppPalette.registrationBlue, size: 13)
            }
            .buttonStyle(PrecisionIconButtonStyle(size: 27))
            .help("New IBM i session")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.top, 5)
        .padding(.bottom, 3)
    }

    private var emptySystems: some View {
        Button {
            model.presentNewSession()
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                WorkbenchGlyph(tool: .terminal, color: AppPalette.registrationBlue, size: 21)
                Text("Add your first system")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text("TLS is the default. IBM i passwords are not saved.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(AppPalette.raised, in: ChamferedRectangle(cut: 4))
            .overlay {
                ChamferedRectangle(cut: 4)
                    .stroke(AppPalette.border, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private var systemFooter: some View {
        VStack(spacing: 9) {
            HStack {
                Label("LOCAL", systemImage: "cpu")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                Spacer()
                Text("ARM64 · NATIVE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(AppPalette.success)
                Text("Optional AI keys use macOS Keychain")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .background(AppPalette.raised)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }
}

private struct SessionProfileRow: View {
    let profile: SessionProfile
    let sessions: [TerminalSessionState]
    let selected: Bool
    let select: () -> Void
    let connect: () -> Void
    let openAdditional: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: select) {
                HStack(spacing: 9) {
                    Image(systemName: profile.environment == .production ? "lock.shield" : "server.rack")
                        .font(.system(size: 13))
                        .foregroundStyle(AppPalette.environment(profile.environment))
                        .frame(width: 28, height: 28)
                        .background(AppPalette.environment(profile.environment).opacity(0.1), in: ChamferedRectangle(cut: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                                .foregroundStyle(AppPalette.text)
                            EnvironmentBadge(environment: profile.environment)
                            if !sessions.isEmpty {
                                Circle()
                                    .fill(sessionStatusColor)
                                    .frame(width: 6, height: 6)
                                Text("×\(sessions.count)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AppPalette.muted)
                            }
                        }
                        Text(profile.workspaceSummary)
                            .lineLimit(1)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: connect) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
            }
            .buttonStyle(.plain)
            .help("Connect to \(profile.name)")

            Menu {
                if !sessions.isEmpty {
                    Button("Open another session", systemImage: "plus", action: openAdditional)
                    Divider()
                }
                Button("Edit session…", systemImage: "pencil", action: edit)
                Divider()
                Button("Delete session…", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                    .frame(width: 18, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Session actions")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(selected ? AppPalette.ibmBlue.opacity(0.09) : Color.clear)
        .clipShape(ChamferedRectangle(cut: 3))
    }

    private var sessionStatusColor: Color {
        if sessions.contains(where: {
            if case .connected = $0.connectionState { return true }
            return false
        }) {
            return AppPalette.success
        }
        if sessions.contains(where: {
            switch $0.connectionState {
            case .connecting, .negotiating, .waiting: true
            default: false
            }
        }) {
            return AppPalette.warning
        }
        if sessions.contains(where: {
            if case .failed = $0.connectionState { return true }
            return false
        }) {
            return AppPalette.danger
        }
        return AppPalette.muted
    }
}

private struct ToolRow: View {
    let tool: WorkbenchTool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                WorkbenchGlyph(
                    tool: tool,
                    color: selected ? AppPalette.registrationBlue : AppPalette.secondary,
                    size: 17
                )
                .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AppPalette.text : AppPalette.secondary)
                    if selected {
                        Text(tool.subtitle)
                            .font(.system(size: 8.5))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, selected ? 7 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? AppPalette.registrationBlue.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(AppPalette.registrationBlue).frame(width: 2)
            }
        }
        .clipShape(ChamferedRectangle(cut: 3))
    }
}
