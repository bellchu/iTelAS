import SwiftUI
import iTelASCore

struct CommandCenterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                environmentGuard
                HostCommandDeckView()

                HStack(alignment: .top, spacing: 14) {
                    urgentWork
                    systemPulse
                }

                recentWork
                capabilityMap
            }
            .padding(20)
        }
        .background(AppPalette.window)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("COMMAND CENTER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Start with the work, not the menu")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("One place to diagnose, change, verify, and leave an audit trail.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            Button {
                model.presentNewSession()
            } label: {
                HStack(spacing: 7) {
                    UtilityGlyph(kind: .add, color: .white, size: 12)
                    Text("New session")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private var environmentGuard: some View {
        let environment = model.selectedProfile?.environment ?? .development
        HStack(spacing: 11) {
            Image(systemName: environment == .production ? "exclamationmark.lock.fill" : "checkmark.shield.fill")
                .foregroundStyle(AppPalette.environment(environment))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(model.selectedProfile?.name ?? "No system selected")
                        .font(.system(size: 11, weight: .semibold))
                    EnvironmentBadge(environment: environment)
                }
                Text(environment == .production
                     ? "Production guard is active: mutating actions require an explicit review step."
                     : "Read-only diagnostics are the default; changes remain deliberate and visible.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            Button("Choose system") { model.presentNewSession() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(13)
        .background(AppPalette.environment(environment).opacity(0.075), in: ChamferedRectangle(cut: 5))
        .overlay {
            ChamferedRectangle(cut: 5)
                .stroke(AppPalette.environment(environment).opacity(0.22), lineWidth: 1)
        }
    }

    private var urgentWork: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("DO NEXT", "Pain-point shortcuts")
                ForEach(Array(ActionCard.items.enumerated()), id: \.offset) { index, item in
                    Button {
                        model.selectedTool = item.tool
                    } label: {
                        HStack(spacing: 11) {
                            WorkbenchGlyph(tool: item.tool, color: item.color, size: 17)
                                .frame(width: 31, height: 31)
                                .background(item.color.opacity(0.08), in: ChamferedRectangle(cut: 5))
                                .overlay {
                                    ChamferedRectangle(cut: 5)
                                        .stroke(item.color.opacity(0.35), lineWidth: 0.7)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppPalette.text)
                                Text(item.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppPalette.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AppPalette.muted)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 53)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < ActionCard.items.count - 1 {
                        Rectangle().fill(AppPalette.border).frame(height: 1).padding(.leading, 55)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var systemPulse: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("SYSTEM PULSE", "Read-only first")
                MetricRow(label: "Active jobs", value: "Connect", tool: .jobsAndQueues, color: AppPalette.registrationBlue)
                MetricRow(label: "Object locks", value: "Connect", tool: .objectGraph, color: AppPalette.warning)
                MetricRow(label: "ASP used", value: "Connect", tool: .systemHealth, color: AppPalette.success)
                MetricRow(label: "System limits", value: "Connect", tool: .systemHealth, color: AppPalette.danger)
                Text("Live metrics will use IBM i Services such as ACTIVE_JOB_INFO, OBJECT_LOCK_INFO, ASP_INFO, and SYSLIMITS.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.muted)
                    .lineSpacing(2)
                    .padding(.top, 2)
            }
            .padding(.bottom, 14)
        }
        .frame(width: 300)
    }

    private var recentWork: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("RESUME WITH CONTEXT", "Session, source, query, and output history")
                HStack(spacing: 0) {
                    ResumeCell(tool: .terminal, title: "Terminal", detail: "Open or create a secured 5250 session") {
                        model.selectedTool = .terminal
                    }
                    Divider().frame(height: 56)
                    ResumeCell(tool: .jobsAndQueues, title: "Job log", detail: "Keep messages beside the incident timeline") {
                        model.selectedTool = .jobsAndQueues
                    }
                    Divider().frame(height: 56)
                    ResumeCell(tool: .sourceWorkspace, title: "Cross-system search", detail: "Find source, objects, and spool together") {
                        model.selectedTool = .sourceWorkspace
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var capabilityMap: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("THE WORKBENCH")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(AppPalette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 178), spacing: 9)], spacing: 9) {
                ForEach(WorkbenchTool.allCases.filter { $0 != .commandCenter }) { tool in
                    Button {
                        model.selectedTool = tool
                    } label: {
                        HStack(spacing: 9) {
                            WorkbenchGlyph(tool: tool, color: AppPalette.registrationBlue, size: 18)
                                .frame(width: 23)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(AppPalette.text)
                                Text(tool.subtitle)
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(AppPalette.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppPalette.panel, in: ChamferedRectangle(cut: 4))
                        .overlay { ChamferedRectangle(cut: 4).stroke(AppPalette.border, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, _ detail: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.text)
            Spacer()
            Text(detail)
                .font(.system(size: 8.5))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 13)
        .frame(height: 39)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct ActionCard {
    let title: String
    let detail: String
    let color: Color
    let tool: WorkbenchTool

    static let items: [ActionCard] = [
        .init(title: "Why is this job stuck?", detail: "Jobs, locks, messages, and waiters in one trace", color: AppPalette.warning, tool: .jobsAndQueues),
        .init(title: "Find and explain an object", detail: "Definition, authority, usage, and dependencies", color: AppPalette.ibmBlue, tool: .objectGraph),
        .init(title: "Compile with usable diagnostics", detail: "Source, event file, job log, and fix loop", color: AppPalette.success, tool: .buildAndTest),
        .init(title: "Locate output without guesswork", detail: "Search spool by job, user, form, date, and text", color: Color.purple, tool: .spoolAndOutput)
    ]
}

private struct MetricRow: View {
    let label: String
    let value: String
    let tool: WorkbenchTool
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            WorkbenchGlyph(tool: tool, color: color, size: 16).frame(width: 22)
            Text(label).font(.system(size: 10)).foregroundStyle(AppPalette.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 13)
    }
}

private struct ResumeCell: View {
    let tool: WorkbenchTool
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                WorkbenchGlyph(tool: tool, color: AppPalette.registrationBlue, size: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(AppPalette.text)
                    Text(detail).font(.system(size: 8.5)).foregroundStyle(AppPalette.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
