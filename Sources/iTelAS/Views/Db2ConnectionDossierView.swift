import SwiftUI
import iTelASCore

struct Db2ConnectionDossierView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Db2ConnectionProfile(name: "Db2 development", host: "", username: "")
    @State private var password = ""
    @State private var rememberPassword = false

    private var runtime: ProviderRuntimeSnapshot { model.providerRuntimeSnapshot }
    private var profileIsValid: Bool { draft.validationErrors.isEmpty }
    private var hasPassword: Bool { !password.isEmpty || model.db2PasswordExists }
    private var requestedAccessMode: Db2AccessMode { model.db2RequestedAccessMode }
    private var requestedModeAllowed: Bool {
        requestedAccessMode == .readOnly || draft.environment != .production
    }
    private var canConnect: Bool {
        runtime.secureDb2PrerequisitesReady
            && profileIsValid
            && hasPassword
            && requestedModeAllowed
            && !model.db2Phase.isBusy
            && !model.db2Phase.isConnected
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                identityColumn.frame(width: 342)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                capabilityCircuit
                Rectangle().fill(AppPalette.border).frame(width: 1)
                policyColumn.frame(width: 326)
            }
            statusStrip
        }
        .background(AppPalette.window)
        .foregroundStyle(AppPalette.text)
        .onAppear {
            model.refreshProviderRuntimeProbe()
            draft = model.db2Profile
            rememberPassword = model.db2PasswordExists
        }
    }

    private var titleBar: some View {
        HStack(spacing: 13) {
            Db2LedgerMark().frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 1) {
                Text("iTelAS").font(.system(size: 13, weight: .bold))
                Text("DB2 CONNECTION DOSSIER")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(1.05)
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            Spacer()
            Db2DossierBadge(
                label: draft.normalizedHost.isEmpty ? "TARGET: NOT SELECTED" : "TARGET: \(draft.targetLabel.uppercased())",
                color: AppPalette.ibmBlue
            )
            Db2DossierBadge(
                label: "MODE: \(requestedAccessMode.label.uppercased())",
                color: requestedAccessMode == .reviewedSourceMemberWrite ? AppPalette.warning : AppPalette.success
            )
            Button("CLOSE") { dismiss() }
                .buttonStyle(Db2OutlineButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var identityColumn: some View {
        VStack(spacing: 0) {
            dossierHeader(
                eyebrow: "CONNECTION IDENTITY",
                title: "One target, visibly",
                detail: "No DSN can quietly override this contract."
            )

            HStack(spacing: 0) {
                ForEach(IBMEnvironment.allCases, id: \.self) { environment in
                    Button {
                        draft.environment = environment
                    } label: {
                        Text(environment.label)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(draft.environment == environment ? Color.white : AppPalette.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(draft.environment == environment ? AppPalette.instrument : AppPalette.raised)
                            .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 0.7) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.environment == environment ? .isSelected : [])
                }
            }
            .padding(7)
            .frame(height: 45)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                VStack(spacing: 0) {
                    Db2DossierField(label: "PROFILE NAME") {
                        TextField("Development partition", text: $draft.name)
                    }
                    Db2DossierField(label: "IBM i HOST") {
                        TextField("dev400.example.com", text: $draft.host)
                            .textContentType(.URL)
                    }
                    Db2DossierField(label: "USER PROFILE") {
                        TextField("DEVUSER", text: $draft.username)
                    }
                    Db2DossierField(label: "DRIVER") {
                        Text(Db2ConnectionProfile.registeredDriverName)
                            .font(.system(size: 10, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        sectionLabel("FAILURE BOUNDS")
                        HStack(spacing: 12) {
                            Db2TimeoutEditor(
                                label: "SIGN-ON",
                                value: $draft.loginTimeoutSeconds,
                                range: 1...60
                            )
                            Db2TimeoutEditor(
                                label: "CONNECT",
                                value: $draft.connectionTimeoutSeconds,
                                range: 1...120
                            )
                        }
                    }
                    .padding(14)
                    .background(AppPalette.raised)
                    .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

                    VStack(alignment: .leading, spacing: 9) {
                        sectionLabel("PASSWORD AT CONNECTION")
                        SecureField(
                            model.db2PasswordExists ? "Stored in Keychain — type to replace" : "IBM i password",
                            text: $password
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(AppPalette.window)
                        .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
                        .accessibilityLabel("IBM i Db2 password")

                        Toggle("Remember in device-only Keychain", isOn: $rememberPassword)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.system(size: 9))

                        Text("Otherwise the password is used for this connection attempt and released. It is never part of the profile, receipt, SQL log, or project files.")
                            .font(.system(size: 8.3))
                            .foregroundStyle(AppPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if model.db2PasswordExists {
                            Button("REMOVE STORED PASSWORD") { model.removeStoredDb2Password() }
                                .buttonStyle(Db2InlineButtonStyle(color: AppPalette.danger))
                        }
                    }
                    .padding(14)

                    if !draft.validationErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            sectionLabel("PROFILE REQUIRES ATTENTION", color: AppPalette.danger)
                            ForEach(draft.validationErrors, id: \.self) { error in
                                Text(error)
                                    .font(.system(size: 8.3))
                                    .foregroundStyle(AppPalette.danger)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppPalette.danger.opacity(0.055))
                        .overlay(alignment: .top) { Rectangle().fill(AppPalette.danger.opacity(0.4)).frame(height: 1) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("NO HIDDEN DSN STATE", color: AppPalette.success)
                Text("Host, user, environment, driver, TLS, and capability remain visible before any network request.")
                    .font(.system(size: 8.3))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(AppPalette.panel)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var capabilityCircuit: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                dossierHeaderCopy(
                    eyebrow: "LEAST-PRIVILEGE CIRCUIT",
                    title: "Know every hop before sign-on",
                    detail: "Local evidence first; the host stays untouched until Connect."
                )
                Button("INSPECT LOCAL RUNTIME") {
                    model.refreshProviderRuntimeProbe()
                    model.showNotice("Refreshed fixed local runtime paths. No host was contacted.")
                }
                .buttonStyle(Db2OutlineButtonStyle())
            }
            .padding(.horizontal, 16)
            .frame(height: 82)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            nativeCircuit
                .frame(height: 242)

            capabilityModes
                .frame(height: 146)

            preflightLedger

            connectAction
                .frame(height: 82)
        }
        .background(AppPalette.window)
    }

    private var nativeCircuit: some View {
        VStack(spacing: 11) {
            HStack(spacing: 9) {
                Text("NATIVE DATA PATH")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                Text("process → manager → driver → cipher → host")
                    .font(.system(size: 8.2))
                    .foregroundStyle(Color.white.opacity(0.52))
                Spacer()
                Text(runtime.secureDb2PrerequisitesReady ? "LOCAL PATH READY" : "PREREQUISITES MISSING")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(runtime.secureDb2PrerequisitesReady ? AppPalette.terminalGreen : Color(red: 1, green: 0.61, blue: 0.37))
            }

            HStack(spacing: 7) {
                Db2RuntimeNode(
                    title: "M5 PRO",
                    role: "ARM64 PROCESS",
                    state: runtime.component(.architecture).state,
                    stateLabel: runtime.component(.architecture).state == .ready ? "READY" : "BLOCKED"
                )
                Db2RuntimeNode(
                    title: "unixODBC",
                    role: "DRIVER MANAGER",
                    state: runtime.component(.unixODBC).state
                )
                Db2RuntimeNode(
                    title: "IBM i ACS",
                    role: "ODBC DRIVER",
                    state: runtime.component(.ibmIODBC).state
                )
                Db2RuntimeNode(
                    title: "OPENSSL",
                    role: "TLS RUNTIME",
                    state: runtime.component(.openSSL).state
                )
                Db2RuntimeNode(
                    title: "DB2 FOR i",
                    role: "HOST SERVER",
                    state: nil,
                    stateLabel: model.db2Phase.isConnected ? "CONNECTED" : "UNTOUCHED"
                )
            }

            HStack(spacing: 10) {
                Db2CircuitDiamond()
                    .stroke(AppPalette.terminalGreen, lineWidth: 1.1)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NO FALLBACK PATH")
                        .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.terminalGreen)
                    Text("No Java bridge, Rosetta process, DSN override, plaintext session, or driver trace.")
                        .font(.system(size: 8.2))
                        .foregroundStyle(Color.white.opacity(0.66))
                }
                Spacer()
                Text("SSL=1\nCCSID=1208")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 11)
            .frame(height: 60)
            .background(Color.white.opacity(0.025))
            .overlay { Rectangle().stroke(Color.white.opacity(0.14), lineWidth: 1) }
        }
        .padding(13)
        .background(AppPalette.instrument)
    }

    private var capabilityModes: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionLabel("CAPABILITY REQUEST", color: AppPalette.ibmBlue)
                Spacer()
                sectionLabel(
                    requestedAccessMode == .readOnly ? "DEFAULT · READ ONLY" : "EXPLICIT · SESSION ONLY",
                    color: requestedAccessMode == .reviewedSourceMemberWrite ? AppPalette.warning : AppPalette.success
                )
            }
            HStack(spacing: 7) {
                capabilityButton(
                    .readOnly,
                    title: "READ ONLY",
                    scope: "SELECT only",
                    contract: "CONNTYPE=2 · safest default"
                )
                capabilityButton(
                    .sourceMemberRead,
                    title: "MEMBER READ",
                    scope: "QTEMP alias + SELECT",
                    contract: "Generated exact lifecycle"
                )
                capabilityButton(
                    .reviewedSourceMemberWrite,
                    title: "MEMBER WRITE",
                    scope: "Reviewed record replace",
                    contract: "Serializable · separate review"
                )
            }
        }
        .padding(12)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var preflightLedger: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PRE-CONNECTION CHECKS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                Spacer()
                Text(model.db2Phase.label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(db2PhaseColor)
            }
            .padding(.horizontal, 12)
            .frame(height: 39)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            Db2GateRow(label: "PROFILE", detail: profileIsValid ? "Validated" : "Review identity fields", ready: profileIsValid)
            Db2GateRow(label: "RUNTIME", detail: "unixODBC + ACS + TLS", ready: runtime.secureDb2PrerequisitesReady)
            Db2GateRow(
                label: "CAPABILITY",
                detail: requestedModeAllowed ? requestedAccessMode.label : "Member capability blocked on PROD",
                ready: requestedModeAllowed
            )
            Db2GateRow(label: "NETWORK", detail: model.db2Phase.isConnected ? "TLS session active" : "No bytes transmitted", ready: true)
            Db2GateRow(label: "SECRET", detail: model.db2PasswordExists ? "Device-only Keychain consent" : "Memory only by default", ready: hasPassword)

            if let diagnostic = model.db2Diagnostic {
                Text(diagnostic)
                    .font(.system(size: 8.4))
                    .foregroundStyle(model.db2Phase == .failed ? AppPalette.danger : AppPalette.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(db2PhaseColor.opacity(0.055))
                    .overlay(alignment: .top) { Rectangle().fill(db2PhaseColor.opacity(0.34)).frame(height: 1) }
            }
        }
        .background(AppPalette.panel)
    }

    private var connectAction: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.db2Phase.isConnected ? "\(model.db2Receipt?.accessMode.label.uppercased() ?? "CAPABILITY") SESSION ACTIVE" : canConnect ? "CONNECTION GATE · READY" : "CONNECTION GATE · BLOCKED")
                    .font(.system(size: 7.8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(model.db2Phase.isConnected || canConnect ? AppPalette.success : AppPalette.warning)
                Text(connectGateDetail)
                    .font(.system(size: 8.4))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if model.db2Phase.isConnected {
                Button("DISCONNECT DB2") { model.disconnectDb2() }
                    .buttonStyle(Db2OutlineButtonStyle(color: AppPalette.danger))
            } else {
                Button(model.db2Phase.isBusy ? "CONNECTING…" : "CONNECT \(requestedAccessMode.label.uppercased())") {
                    model.updateDb2Profile(draft)
                    model.connectDb2(password: password, rememberPassword: rememberPassword)
                    password = ""
                }
                .buttonStyle(Db2BlackButtonStyle(enabled: canConnect))
                .disabled(!canConnect)
            }
        }
        .padding(.horizontal, 14)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var policyColumn: some View {
        VStack(spacing: 0) {
            dossierHeader(
                eyebrow: "CONNECTION CONTRACT",
                title: "Fixed, inspectable policy",
                detail: "A DSN cannot loosen these settings."
            )

            HStack(spacing: 10) {
                Db2LedgerMark().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(requestedAccessMode.label.uppercased()) SESSION")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                    Text("Pinned attributes · no DSN inheritance")
                        .font(.system(size: 8.3))
                        .foregroundStyle(AppPalette.secondary)
                }
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 64)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            Db2PolicyRow(label: "TLS TRANSPORT", detail: "All traffic encrypted", value: "SSL=1")
            Db2PolicyRow(label: "EXPLICIT SIGN-ON", detail: "No default identity", value: "SIGNON=2")
            Db2PolicyRow(label: "DRIVER ACCESS", detail: driverAccessDetail, value: "CONNTYPE=\(requestedAccessMode.connectionTypeValue)")
            Db2PolicyRow(label: "COMMITMENT", detail: commitmentDetail, value: "CMT=\(requestedAccessMode.commitmentControlValue)")
            Db2PolicyRow(label: "SQL NAMING", detail: "Schema.object resolution", value: "NAM=0")
            Db2PolicyRow(label: "CONVERSION", detail: "Report unsupported text", value: "ALLOWUNSCHAR=0")
            Db2PolicyRow(label: "TRACE SURFACE", detail: "Driver tracing disabled", value: "TRACE=0")

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("NEVER IN PROFILE OR RECEIPT", color: AppPalette.success)
                Db2PolicyBullet("Password bytes are non-printable")
                Db2PolicyBullet("ODBC output connection string is discarded")
                Db2PolicyBullet("SQL text is absent from connection receipts")
            }
            .padding(12)
            .background(AppPalette.success.opacity(0.07))
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.success.opacity(0.38)).frame(height: 1) }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("PRODUCTION FAILS CLOSED", color: AppPalette.warning)
                Text("Interactive execution remains blocked on PROD. Source-member alias and write capabilities require a non-production target and a separate connection.")
                    .font(.system(size: 8.2))
                    .foregroundStyle(Color(red: 0.46, green: 0.31, blue: 0.2))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(AppPalette.warning.opacity(0.08))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.warning.opacity(0.48)).frame(height: 1) }

            Link(
                "OFFICIAL IBM macOS DRIVER GUIDE",
                destination: URL(string: "https://www.ibm.com/support/pages/ibm-i-access-acs-updates-mac")!
            )
            .buttonStyle(Db2InlineButtonStyle(color: AppPalette.ibmBlue))
            .padding(12)
        }
        .background(AppPalette.panel)
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Text("DB2: \(model.db2Phase.label)")
                .fontWeight(.bold)
                .foregroundStyle(db2PhaseColor)
            Text(model.db2Phase.isConnected ? "TLS: ACTIVE" : "HOST: NOT CONTACTED")
            Text("PASSWORD: \(model.db2PasswordExists ? "KEYCHAIN" : "NOT RETAINED")")
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("\(runtime.architecture.uppercased()) · NATIVE ODBC")
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }

    private func dossierHeader(eyebrow: String, title: String, detail: String) -> some View {
        dossierHeaderCopy(eyebrow: eyebrow, title: title, detail: detail)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func dossierHeaderCopy(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(AppPalette.ibmBlue)
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppPalette.text)
            Text(detail)
                .font(.system(size: 8.7))
                .foregroundStyle(AppPalette.secondary)
        }
    }

    private func sectionLabel(_ label: String, color: Color = AppPalette.muted) -> some View {
        Text(label)
            .font(.system(size: 7.2, weight: .bold, design: .monospaced))
            .tracking(0.65)
            .foregroundStyle(color)
    }

    private func capabilityButton(
        _ mode: Db2AccessMode,
        title: String,
        scope: String,
        contract: String
    ) -> some View {
        Button {
            model.selectDb2AccessMode(mode)
        } label: {
            Db2ModeLane(
                title: title,
                scope: scope,
                contract: contract,
                selected: requestedAccessMode == mode
            )
        }
        .buttonStyle(.plain)
        .disabled(model.db2Phase.isBusy || model.db2Phase.isConnected)
        .accessibilityLabel("Request \(mode.label) Db2 capability")
    }

    private var db2PhaseColor: Color {
        switch model.db2Phase {
        case .idle: AppPalette.terminalGreen
        case .connecting: AppPalette.warning
        case .connected: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var connectGateDetail: String {
        if model.db2Phase.isConnected {
            return "The receipt proves TLS, target, environment, and \(model.db2Receipt?.accessMode.label.lowercased() ?? "selected") capability for this app session."
        }
        if !runtime.secureDb2PrerequisitesReady {
            return "Verify native unixODBC, the IBM driver, and OpenSSL. No host has been contacted."
        }
        if !profileIsValid { return "Complete the target identity fields before connecting." }
        if !hasPassword { return "Enter a password or opt into device-only Keychain storage." }
        if !requestedModeAllowed {
            return "Source-member capability is blocked for PROD. Choose Read only or a non-production target."
        }
        return "The next action opens one TLS-only \(requestedAccessMode.label.lowercased()) ODBC session."
    }

    private var driverAccessDetail: String {
        switch requestedAccessMode {
        case .readOnly: "Bounded SELECT statements only"
        case .sourceMemberRead: "Generated QTEMP alias lifecycle only"
        case .reviewedSourceMemberWrite: "Exact reviewed member transaction only"
        }
    }

    private var commitmentDetail: String {
        switch requestedAccessMode {
        case .readOnly: "Driver read-only unit"
        case .sourceMemberRead: "Alias lifecycle without app writes"
        case .reviewedSourceMemberWrite: "Serializable explicit transaction"
        }
    }
}

private struct Db2DossierField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.65)
                .foregroundStyle(AppPalette.muted)
            content
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 55)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.75)).frame(height: 1) }
    }
}

private struct Db2TimeoutEditor: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Stepper(value: $value, in: range) {
                Text("\(value) SEC")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            }
            .controlSize(.mini)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Db2RuntimeNode: View {
    let title: String
    let role: String
    let state: ProviderRuntimeState?
    var stateLabel: String?

    private var ready: Bool { state == .ready || stateLabel == "CONNECTED" }
    private var muted: Bool { state == nil && stateLabel != "CONNECTED" }
    private var color: Color {
        if ready { return AppPalette.terminalGreen }
        if muted { return Color.white.opacity(0.38) }
        return Color(red: 1, green: 0.61, blue: 0.37)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(role)
                .font(.system(size: 6.4))
                .foregroundStyle(Color.white.opacity(0.52))
                .lineLimit(1)
            Text(stateLabel ?? (state == .ready ? "READY" : "MISSING"))
                .font(.system(size: 5.9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66)
        .background(Color.white.opacity(0.025))
        .overlay { Rectangle().stroke(color.opacity(0.8), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

private struct Db2ModeLane: View {
    let title: String
    let scope: String
    let contract: String
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? Color(red: 0.09, green: 0.29, blue: 0.57) : AppPalette.text)
            Text(scope)
                .font(.system(size: 8.2, weight: .semibold))
                .lineLimit(1)
            Text(contract)
                .font(.system(size: 6.2, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(selected ? AppPalette.ibmBlue.opacity(0.09) : AppPalette.window)
        .overlay { Rectangle().stroke(selected ? AppPalette.ibmBlue : AppPalette.borderStrong, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct Db2GateRow: View {
    let label: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 9) {
            Rectangle().fill(ready ? AppPalette.success : AppPalette.warning).frame(width: 4, height: 22)
            Text(label)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .frame(width: 58, alignment: .leading)
            Text(detail)
                .font(.system(size: 8.2))
                .foregroundStyle(AppPalette.secondary)
            Spacer()
            Text(ready ? "READY" : "BLOCKED")
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(ready ? AppPalette.success : AppPalette.warning)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.72)).frame(height: 1) }
    }
}

private struct Db2PolicyRow: View {
    let label: String
    let detail: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(AppPalette.success).frame(width: 4, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 6.7, weight: .bold, design: .monospaced))
                Text(detail).font(.system(size: 7.8)).foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            Text(value)
                .font(.system(size: 6.1, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.success)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.75)).frame(height: 1) }
    }
}

private struct Db2PolicyBullet: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(AppPalette.success).frame(width: 5, height: 5)
            Text(text).font(.system(size: 7.8)).foregroundStyle(Color(red: 0.31, green: 0.38, blue: 0.34))
        }
    }
}

private struct Db2DossierBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 4, height: 12)
            Text(label)
                .font(.system(size: 7.1, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(color.opacity(0.08))
        .overlay { Rectangle().stroke(color.opacity(0.42), lineWidth: 1) }
    }
}

private struct Db2LedgerMark: View {
    var body: some View {
        Canvas { context, size in
            let line = max(2, size.width * 0.09)
            let spine = CGRect(x: size.width * 0.2, y: size.height * 0.16, width: line, height: size.height * 0.68)
            context.fill(Path(spine), with: .color(Color(red: 0.35, green: 0.65, blue: 1)))
            let bars: [(CGFloat, CGFloat, Color)] = [
                (0.18, 0.64, AppPalette.terminalGreen),
                (0.43, 0.48, Color.white.opacity(0.9)),
                (0.68, 0.64, Color(red: 0.35, green: 0.65, blue: 1))
            ]
            for (y, width, color) in bars {
                context.fill(
                    Path(CGRect(x: size.width * 0.36, y: size.height * y, width: size.width * width, height: line)),
                    with: .color(color)
                )
            }
        }
        .padding(5)
        .background(AppPalette.instrument)
        .overlay { Rectangle().stroke(AppPalette.borderStrong.opacity(0.55), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

private struct Db2CircuitDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct Db2OutlineButtonStyle: ButtonStyle {
    var color = AppPalette.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.4, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(configuration.isPressed ? AppPalette.raised : AppPalette.panel)
            .overlay { Rectangle().stroke(color.opacity(0.52), lineWidth: 1) }
    }
}

private struct Db2InlineButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.65 : 1))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Db2BlackButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.8, weight: .bold, design: .monospaced))
            .tracking(0.45)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(enabled ? AppPalette.instrument.opacity(configuration.isPressed ? 0.78 : 1) : AppPalette.muted)
            .overlay(alignment: .leading) {
                Rectangle().fill(enabled ? AppPalette.terminalGreen : Color.clear).frame(width: 2, height: 24)
            }
    }
}
