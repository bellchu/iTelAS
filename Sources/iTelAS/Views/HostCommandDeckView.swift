import SwiftUI

struct HostCommandDeckView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID = HostDiagnosticCommand.library[0].id

    private var selectedCommand: HostDiagnosticCommand {
        HostDiagnosticCommand.library.first(where: { $0.id == selectedID })
            ?? HostDiagnosticCommand.library[0]
    }

    private var status: HostCommandStagingStatus {
        model.hostCommandStagingStatus(for: selectedCommand.command)
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                header
                signalPath
                Rectangle().fill(AppPalette.border).frame(height: 1)
                HStack(alignment: .top, spacing: 0) {
                    commandLibrary
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    stagingRail
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            UtilityGlyph(kind: .stage, color: AppPalette.terminalGreen, size: 22)
                .frame(width: 39, height: 39)
                .background(AppPalette.instrument, in: ChamferedRectangle(cut: 5))
                .overlay { ChamferedRectangle(cut: 5).stroke(AppPalette.registrationBlue, lineWidth: 0.8) }
            VStack(alignment: .leading, spacing: 3) {
                Text("HOST COMMAND DECK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Stage a diagnostic. Keep Enter yours.")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("A safe bridge from the workbench into the current 5250 command field—never an automatic executor.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            Text("LIVE TERMINAL BRIDGE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(status.isReady ? AppPalette.success : AppPalette.muted)
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(AppPalette.panel)
    }

    private var signalPath: some View {
        HStack(spacing: 0) {
            signalNode("01", "SESSION", connectionSignal, status.isReady ? AppPalette.success : AppPalette.muted)
            signalConnector
            signalNode("02", "RISK GATE", "READ ONLY", AppPalette.ibmBlue)
            signalConnector
            signalNode("03", "TARGET", targetSignal, AppPalette.registrationBlue)
            signalConnector
            signalNode("04", "SUBMIT", "OPERATOR", AppPalette.warning)
        }
        .padding(.horizontal, 10)
        .frame(height: 57)
        .background(AppPalette.raised)
    }

    private func signalNode(_ index: String, _ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(index).foregroundStyle(color)
                Text(label).foregroundStyle(AppPalette.muted)
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.5)
            Text(value)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var signalConnector: some View {
        UtilityGlyph(kind: .outbound, color: AppPalette.borderStrong, size: 14)
            .frame(width: 18)
    }

    private var connectionSignal: String {
        if case .connected = model.connectionState { return "LIVE 5250" }
        return "OFFLINE"
    }

    private var targetSignal: String {
        guard let field = model.screen.currentEditableFieldOrdinal else { return "NO FIELD" }
        return "FIELD \(field)/\(model.screen.editableFieldCount)"
    }

    private var commandLibrary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DIAGNOSTIC LIBRARY")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                Spacer()
                Text("CLICK TO SELECT")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 35)
            .background(AppPalette.raised)

            ForEach(Array(HostDiagnosticCommand.library.enumerated()), id: \.element.id) { index, command in
                Button {
                    selectedID = command.id
                } label: {
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(command.id == selectedID ? AppPalette.ibmBlue : AppPalette.muted)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppPalette.text)
                            Text(command.detail)
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppPalette.muted)
                        }
                        Spacer(minLength: 8)
                        Text(command.command)
                            .font(.system(size: 8.5, weight: command.id == selectedID ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(command.id == selectedID ? AppPalette.ibmBlue : AppPalette.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 49)
                    .contentShape(Rectangle())
                    .background(command.id == selectedID ? AppPalette.ibmBlue.opacity(0.065) : Color.clear)
                }
                .buttonStyle(.plain)
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stagingRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(AppPalette.registrationBlue).frame(height: 3)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("STAGED TEXT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.muted)
                    Spacer()
                    Text("READ ONLY")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.success)
                }
                Text(selectedCommand.command)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .textSelection(.enabled)
                Text(status.message)
                    .font(.system(size: 9))
                    .foregroundStyle(status.isReady ? AppPalette.secondary : AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)

            Rectangle().fill(AppPalette.border).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("OPERATOR GATE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.warning)
                Text("Staging replaces only the current visible field. It sends no AID key and cannot submit the command.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)

            Spacer(minLength: 8)

            Button {
                model.stageReadOnlyHostCommand(selectedCommand.command)
            } label: {
                HStack(spacing: 8) {
                    UtilityGlyph(kind: .stage, color: .white, size: 16)
                    Text("Stage in current field")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!status.isReady)
            .padding(.horizontal, 13)

            Button("Open terminal") { model.selectedTool = .terminal }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppPalette.ibmBlue)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
        }
        .frame(width: 285)
        .frame(minHeight: 232)
        .background(AppPalette.panel)
    }
}
