import SwiftUI
import iTelASCore

struct ConnectionStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = SessionProfile(name: "Development", host: "")
    @State private var showsAdvanced = false
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        HStack(spacing: 0) {
            connectionBlueprint
                .frame(width: 390)

            VStack(alignment: .leading, spacing: 0) {
                formHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        formFields
                        securityNotice
                        if let diagnostic = model.connectionDiagnostic {
                            diagnosticView(diagnostic)
                        }
                    }
                    .padding(.horizontal, 44)
                    .padding(.bottom, 24)
                }

                formActions
            }
            .background(AppPalette.panel)
        }
        .frame(width: 1_080, height: 690)
        .background(AppPalette.panel)
        .onAppear {
            draft = model.editingProfile ?? SessionProfile(name: "Development", host: "")
            proverb = .random(excluding: proverb.id)
        }
        .onDisappear { model.editingProfile = nil }
    }

    private var connectionBlueprint: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 11) {
                ITelASMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iTelAS")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("APPLE SILICON · NATIVE")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.48))
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                Text("Built for the work behind every IBM i screen.")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("One command center for sessions, source, SQL, jobs, output, system health, automation, and deliberate AI assistance.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineSpacing(4)
            }

            securePathDiagram

            VStack(alignment: .leading, spacing: 5) {
                Text("WORKBENCH PROVERB · \(proverb.lesson.uppercased())")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.43))
                Text(proverb.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                Text(proverb.source)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.58))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .overlay {
                Rectangle().stroke(Color.white.opacity(0.13), lineWidth: 1)
            }

            Spacer()

            Label("IBM i passwords are entered on the host screen and are not saved by default.", systemImage: "key.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 38)
        .background(Color(red: 0.067, green: 0.094, blue: 0.125))
    }

    private var securePathDiagram: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SECURE SESSION PATH")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.42))
            PathNode(symbol: "laptopcomputer", title: "THIS MAC", detail: "arm64 · native Swift", color: Color(red: 0.47, green: 0.66, blue: 1))
            PathNode(symbol: "checkmark.shield.fill", title: "ENCRYPTED LINK", detail: "TLS · certificate validation", color: Color(red: 0.26, green: 0.75, blue: 0.4))
            PathNode(symbol: "server.rack", title: "IBM i", detail: "RFC 4777 · named virtual device", color: Color(red: 0.65, green: 0.94, blue: 0.73))
        }
        .padding(16)
        .overlay {
            Rectangle().stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    private var formHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.editingProfile == nil ? "NEW SESSION" : "EDIT SESSION")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(AppPalette.ibmBlue)
            Text(model.editingProfile == nil ? "Connect to an IBM i system" : "Update \(draft.name)")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppPalette.text)
            Text("Name the workspace, choose the transport, then verify the endpoint before opening a terminal.")
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.secondary)
        }
        .padding(.horizontal, 44)
        .padding(.top, 38)
        .padding(.bottom, 23)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 14) {
                LabeledField("SESSION NAME") {
                    TextField("Development", text: $draft.name)
                }
                LabeledField("HOST OR IP") {
                    TextField("dev400.example.com", text: $draft.host)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                LabeledField("PORT", width: 130) {
                    TextField("992", value: $draft.port, format: .number)
                }
                LabeledField("TRANSPORT") {
                    Picker("Transport", selection: $draft.security) {
                        Label("TLS", systemImage: "checkmark.shield").tag(TransportSecurity.tls)
                        Text("Telnet").tag(TransportSecurity.telnet)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: draft.security) { oldValue, newValue in
                        if draft.port == oldValue.defaultPort { draft.port = newValue.defaultPort }
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                LabeledField("TERMINAL MODEL") {
                    Picker("Terminal model", selection: $draft.terminalModel) {
                        ForEach(TerminalModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .labelsHidden()
                }
                LabeledField("CCSID") {
                    Picker("CCSID", selection: $draft.ccsid) {
                        ForEach(EBCDICCCSIDCatalog.terminalReady) { definition in
                            Text(definition.pickerLabel).tag(definition.ccsid)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack(alignment: .top, spacing: 14) {
                LabeledField("ENVIRONMENT") {
                    Picker("Environment", selection: $draft.environment) {
                        ForEach(IBMEnvironment.allCases, id: \.self) { environment in
                            Text(environment.label).tag(environment)
                        }
                    }
                    .labelsHidden()
                }
                LabeledField("SESSION RECOVERY") {
                    Picker("Session recovery", selection: $draft.reconnectPolicy) {
                        ForEach(SessionReconnectPolicy.allCases, id: \.self) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .labelsHidden()
                }
            }

            DisclosureGroup("Device name, keyboard map, and startup response", isExpanded: $showsAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        LabeledField("DEVICE NAME") {
                            TextField("Optional · max 10", text: $draft.deviceName)
                                .textCase(.uppercase)
                        }
                        LabeledField("KEYBOARD TYPE") {
                            TextField("USB", text: $draft.keyboardType)
                        }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        LabeledField("DEVICE CODE PAGE") {
                            TextField("Host default", text: $draft.negotiatedCodePage)
                        }
                        LabeledField("DEVICE CHARACTER SET") {
                            TextField("Host default", text: $draft.negotiatedCharacterSet)
                        }
                    }
                    Text("Device CODEPAGE and CHARSET are RFC 4777 creation attributes. Leave them blank to use IBM i defaults; the display CCSID above controls local byte conversion.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.muted)
                    Text("Automatic recovery keeps the last screen read-only, creates a fresh TLS/TN5250 session, and never resubmits edited fields or passwords.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.muted)
                }
                .padding(.top, 12)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(AppPalette.secondary)

            if !draft.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.circle")
                    }
                }
                .font(.system(size: 9.5))
                .foregroundStyle(AppPalette.danger)
            }
        }
    }

    private var securityNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: draft.security == .tls ? "lock.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(draft.security == .tls ? AppPalette.success : AppPalette.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.security == .tls ? "Certificate validation is enabled" : "Plain Telnet exposes terminal traffic")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(draft.security == .tls
                     ? "The connection fails closed if macOS cannot validate the IBM i certificate chain."
                     : "Use plain Telnet only on an explicitly trusted network. Interactive sign-on data is not encrypted.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((draft.security == .tls ? AppPalette.success : AppPalette.warning).opacity(0.08), in: ChamferedRectangle(cut: 4))
        .overlay {
            ChamferedRectangle(cut: 4)
                .stroke((draft.security == .tls ? AppPalette.success : AppPalette.warning).opacity(0.2), lineWidth: 0.8)
        }
    }

    private func diagnosticView(_ diagnostic: String) -> some View {
        Label(diagnostic, systemImage: model.connectionDiagnosticSucceeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
            .font(.system(size: 10))
            .foregroundStyle(model.connectionDiagnosticSucceeded ? AppPalette.success : AppPalette.danger)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((model.connectionDiagnosticSucceeded ? AppPalette.success : AppPalette.danger).opacity(0.07), in: ChamferedRectangle(cut: 4))
    }

    private var formActions: some View {
        HStack(spacing: 10) {
            Button {
                model.testConnection(draft)
            } label: {
                if model.isTestingConnection {
                    HStack { ProgressView().controlSize(.small); Text("Testing…") }
                } else {
                    HStack(spacing: 7) {
                        UtilityGlyph(kind: .connectionTest, color: AppPalette.secondary, size: 13)
                        Text("Test connection")
                    }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!draft.validationErrors.isEmpty || model.isTestingConnection)

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.secondary)

            Button {
                model.saveProfile(draft)
                dismiss()
                model.connect(draft)
            } label: {
                HStack(spacing: 7) {
                    UtilityGlyph(kind: .outbound, color: .white, size: 12)
                    Text(model.editingProfile == nil ? "Save & Connect" : "Save & Reconnect")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!draft.validationErrors.isEmpty)
        }
        .padding(.horizontal, 44)
        .frame(height: 66)
        .background(AppPalette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }
}

private struct PathNode: View {
    let symbol: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 29, height: 29)
                .background(Color.white.opacity(0.05))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text(detail)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.43))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 47)
        .background(Color.white.opacity(0.035))
        .overlay { Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1) }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    let width: CGFloat?
    let content: Content

    init(_ label: String, width: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(AppPalette.muted)
            content
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(AppPalette.panel)
                .clipShape(ChamferedRectangle(cut: 3))
                .overlay {
                    ChamferedRectangle(cut: 3)
                        .stroke(AppPalette.border, lineWidth: 1)
                }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }
}
