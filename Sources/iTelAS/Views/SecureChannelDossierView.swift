import SwiftUI
import iTelASCore

struct SecureChannelDossierView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                identityColumn
                    .frame(width: 300)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                trustPlane
                Rectangle().fill(AppPalette.border).frame(width: 1)
                capabilityColumn
                    .frame(width: 276)
            }

            statusStrip
        }
        .background(AppPalette.window)
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            SecureChannelConduitGlyph()
                .frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 1) {
                Text("iTelAS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("SECURE CHANNEL DOSSIER")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(1.05)
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            Spacer()
            ChannelBadge(label: targetBadge, color: AppPalette.ibmBlue)
            ChannelBadge(label: "AUTH: OPERATOR", color: AppPalette.success)
            Button("CLOSE") { dismiss() }
                .buttonStyle(ChannelOutlineButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var targetBadge: String {
        let host = model.secureChannelProfile.normalizedHost
        return host.isEmpty ? "TARGET: UNASSIGNED" : "TARGET: \(host.uppercased())"
    }

    private var identityColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CONNECTION IDENTITY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("SSH + SFTP target")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("One visible identity for PASE and IFS work.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .frame(height: 78)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            environmentSelector

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ChannelField(label: "CONNECTION NAME") {
                        TextField("Source workbench", text: profileBinding(\.name))
                            .textFieldStyle(.plain)
                    }
                    ChannelField(label: "HOST NAME") {
                        TextField("dev400.example.com", text: profileBinding(\.host))
                            .textFieldStyle(.plain)
                    }
                    HStack(alignment: .top, spacing: 9) {
                        ChannelField(label: "SSH PORT") {
                            TextField("22", value: profileBinding(\.port), format: .number)
                                .textFieldStyle(.plain)
                        }
                        .frame(width: 88)
                        ChannelField(label: "USER PROFILE") {
                            TextField("Required", text: profileBinding(\.username))
                                .textFieldStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("AUTHENTICATION METHOD")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(0.65)
                            .foregroundStyle(AppPalette.muted)
                        HStack(spacing: 5) {
                            ForEach(SSHAuthenticationMethod.allCases, id: \.self) { method in
                                Button(method.label.uppercased()) {
                                    var profile = model.secureChannelProfile
                                    profile.authenticationMethod = method
                                    model.updateSecureChannelProfile(profile)
                                }
                                .buttonStyle(ChannelSegmentButtonStyle(
                                    selected: model.secureChannelProfile.authenticationMethod == method
                                ))
                            }
                        }
                    }

                    if model.secureChannelProfile.authenticationMethod == .keyFile {
                        ChannelField(label: "PRIVATE KEY PATH") {
                            TextField("/Users/name/.ssh/id_ed25519", text: optionalProfileBinding(\.privateKeyPath))
                                .textFieldStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CREDENTIAL BOUNDARY")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(AppPalette.success)
                        Text("Keys and passphrases remain in the macOS SSH agent or the selected local key. iTelAS does not read the development secret file.")
                            .font(.system(size: 8.2))
                            .foregroundStyle(AppPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .background(AppPalette.success.opacity(0.07))
                    .overlay { Rectangle().stroke(AppPalette.success.opacity(0.42), lineWidth: 1) }

                    if !model.secureChannelProfile.validationErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(model.secureChannelProfile.validationErrors, id: \.self) { error in
                                Text("×  \(error)")
                            }
                        }
                        .font(.system(size: 7.8, design: .monospaced))
                        .foregroundStyle(AppPalette.danger)
                    }
                }
                .padding(13)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("IDENTITY BEFORE AUTHORITY")
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.success)
                Text("Target, environment, user, and authentication method stay visible before every remote action.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(12)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var environmentSelector: some View {
        HStack(spacing: 0) {
            ForEach(IBMEnvironment.allCases, id: \.self) { environment in
                Button(environment.label.uppercased()) {
                    var profile = model.secureChannelProfile
                    profile.environment = environment
                    model.updateSecureChannelProfile(profile)
                }
                .buttonStyle(ChannelEnvironmentButtonStyle(
                    selected: model.secureChannelProfile.environment == environment,
                    color: AppPalette.environment(environment)
                ))
            }
        }
        .padding(6)
        .frame(height: 42)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var trustPlane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HOST AUTHENTICITY")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Host Trust Plane")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppPalette.text)
                    Text("Pin what the host proves before authentication begins.")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                Button(model.secureChannelPhase == .scanning ? "DISCOVERING…" : "VERIFY HOST KEY") {
                    model.discoverSecureChannelHostKeys()
                }
                .buttonStyle(ChannelBlackButtonStyle())
                .disabled(!canScan)
            }
            .padding(.horizontal, 15)
            .frame(height: 78)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            trustLoom
            evidenceWorkspace
        }
        .background(AppPalette.window)
    }

    private var canScan: Bool {
        !model.secureChannelPhase.isBusy
            && model.providerRuntimeSnapshot.sshReady
            && model.secureChannelProfile.validationErrors.isEmpty
    }

    private var trustLoom: some View {
        VStack(spacing: 9) {
            HStack {
                Text("TRUST CHAIN")
                    .font(.system(size: 8.2, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.white)
                Text("Network discovery → presented key → operator decision → pinned identity")
                    .font(.system(size: 7.8))
                    .foregroundStyle(Color.white.opacity(0.52))
                Spacer()
                Text(model.secureChannelPhase.label)
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(channelStateColor)
            }

            HStack(spacing: 7) {
                ChannelTrustNode(label: "LOCAL RUNTIME", value: "/usr/bin/ssh", state: .ready)
                ChannelTrustLink(ready: true)
                ChannelTrustNode(
                    label: "TARGET",
                    value: model.secureChannelProfile.normalizedHost.isEmpty ? "unassigned" : "\(model.secureChannelProfile.normalizedHost):\(model.secureChannelProfile.port)",
                    state: model.secureChannelProfile.normalizedHost.isEmpty ? .waiting : .ready
                )
                ChannelTrustLink(ready: !model.secureChannelHostKeys.isEmpty)
                ChannelTrustNode(
                    label: "PRESENTED KEY",
                    value: model.secureChannelHostKeys.isEmpty ? "not collected" : "\(model.secureChannelHostKeys.count) candidate(s)",
                    state: model.secureChannelHostKeys.isEmpty ? .blocked : .ready
                )
                ChannelTrustLink(ready: model.secureChannelHasPinnedKey)
                ChannelTrustNode(
                    label: "PINNED HOST",
                    value: model.secureChannelHasPinnedKey ? "exact key" : "not trusted",
                    state: model.secureChannelHasPinnedKey ? .ready : .waiting
                )
            }

            HStack(spacing: 9) {
                ChannelCautionGlyph()
                    .stroke(Color(red: 1, green: 0.61, blue: 0.37), lineWidth: 1.1)
                    .frame(width: 15, height: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STOP BEFORE AUTHENTICATION")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.55)
                        .foregroundStyle(Color(red: 1, green: 0.70, blue: 0.54))
                    Text("A reachable host is not a trusted host. Compare the SHA-256 fingerprint through an independent channel, then pin it.")
                        .font(.system(size: 7.8))
                        .foregroundStyle(Color.white.opacity(0.66))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(Color(red: 0.17, green: 0.12, blue: 0.09))
            .overlay { Rectangle().stroke(Color(red: 0.55, green: 0.34, blue: 0.22), lineWidth: 1) }
        }
        .padding(12)
        .frame(height: 196)
        .background(AppPalette.instrument)
    }

    private var evidenceWorkspace: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PRESENTED KEY EVIDENCE")
                    .font(.system(size: 8.2, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.text)
                Spacer()
                Text(model.secureChannelHostKeys.isEmpty ? "EMPTY" : "\(model.secureChannelHostKeys.count) CANDIDATE(S)")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.secureChannelHostKeys.isEmpty ? AppPalette.warning : AppPalette.success)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if model.secureChannelHostKeys.isEmpty {
                VStack(spacing: 7) {
                    SecureChannelEmptyGlyph()
                        .stroke(AppPalette.borderStrong, lineWidth: 1.1)
                        .frame(width: 35, height: 35)
                    Text(model.secureChannelPhase == .scanning ? "COLLECTING PUBLIC HOST KEYS" : "NO HOST KEY COLLECTED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                    Text("Verification contacts only the named SSH endpoint. It does not authenticate or read credentials.")
                        .font(.system(size: 8.2))
                        .foregroundStyle(AppPalette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    if model.secureChannelPhase == .scanning { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppPalette.panel)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.secureChannelHostKeys) { key in
                            Button {
                                model.selectedSecureChannelHostKeyID = key.id
                            } label: {
                                ChannelHostKeyRow(
                                    key: key,
                                    selected: model.selectedSecureChannelHostKeyID == key.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(AppPalette.panel)
            }

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OPERATOR DECISION")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .tracking(0.55)
                        .foregroundStyle(AppPalette.warning)
                    Text(model.secureChannelDiagnostic ?? "Collect a key, compare it independently, and record the exact pin.")
                        .font(.system(size: 7.8))
                        .foregroundStyle(AppPalette.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("PIN SELECTED KEY") {
                    model.pinSelectedSecureChannelHostKey()
                }
                .buttonStyle(ChannelOutlineButtonStyle())
                .disabled(model.secureChannelPhase != .review || model.selectedSecureChannelHostKey == nil)
            }
            .padding(.horizontal, 12)
            .frame(height: 64)
            .background(AppPalette.warning.opacity(0.08))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.warning.opacity(0.5)).frame(height: 1) }
        }
    }

    private var capabilityColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LEAST PRIVILEGE")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Capability envelope")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("Open only the surfaces this workflow needs.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .frame(height: 78)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 2) {
                Text("SOURCE WORKBENCH")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Text("Proposed access plan · not active")
                    .font(.system(size: 8.2))
                    .foregroundStyle(AppPalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .frame(height: 52)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ForEach(ChannelCapability.defaults) { capability in
                ChannelCapabilityRow(capability: capability)
            }

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text("WRITE PATH FAILS CLOSED")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(AppPalette.success)
                Text("Upload still requires revision, compare, CCSID round-trip, and explicit operator action.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(11)
            .background(AppPalette.success.opacity(0.07))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.success.opacity(0.42)).frame(height: 1) }

            Button(model.secureChannelPhase == .authenticating ? "TESTING PINNED CHANNEL…" : model.secureChannelPhase == .connected ? "CHANNEL VERIFIED" : "TEST PINNED CHANNEL") {
                model.testPinnedSecureChannel()
            }
            .buttonStyle(ChannelGateButtonStyle(ready: model.secureChannelHasPinnedKey))
            .disabled(!model.secureChannelHasPinnedKey || model.secureChannelPhase.isBusy)
            .help("Uses BatchMode, strict host-key checking, no forwarding, and a constant read-only remote command")
        }
        .background(AppPalette.panel)
    }

    private var channelStateColor: Color {
        switch model.secureChannelPhase {
        case .pinned, .connected: AppPalette.terminalGreen
        case .scanning, .review, .authenticating: Color(red: 1, green: 0.70, blue: 0.52)
        case .failed: Color(red: 1, green: 0.45, blue: 0.45)
        case .idle: Color.white.opacity(0.55)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Text("CHANNEL: \(model.secureChannelPhase.label)")
                .fontWeight(.bold)
                .foregroundStyle(channelStateColor)
            Text(model.secureChannelHostKeys.isEmpty ? "KEY: NOT COLLECTED" : model.secureChannelHasPinnedKey ? "KEY: PINNED" : "KEY: REVIEW")
            Text(model.secureChannelPhase == .connected ? "SFTP: READY" : "SFTP: CLOSED")
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("ARM64 · SYSTEM OPENSSH")
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }

    private func profileBinding<Value>(_ keyPath: WritableKeyPath<SecureChannelProfile, Value>) -> Binding<Value> {
        Binding(
            get: { model.secureChannelProfile[keyPath: keyPath] },
            set: { value in
                var profile = model.secureChannelProfile
                profile[keyPath: keyPath] = value
                model.updateSecureChannelProfile(profile)
            }
        )
    }

    private func optionalProfileBinding(_ keyPath: WritableKeyPath<SecureChannelProfile, String?>) -> Binding<String> {
        Binding(
            get: { model.secureChannelProfile[keyPath: keyPath] ?? "" },
            set: { value in
                var profile = model.secureChannelProfile
                profile[keyPath: keyPath] = value.isEmpty ? nil : value
                model.updateSecureChannelProfile(profile)
            }
        )
    }
}

private struct ChannelField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.65)
                .foregroundStyle(AppPalette.muted)
            content
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(AppPalette.panel)
                .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
        }
    }
}

private enum ChannelTrustNodeState {
    case ready
    case waiting
    case blocked

    var color: Color {
        switch self {
        case .ready: AppPalette.terminalGreen
        case .waiting: Color(red: 0.54, green: 0.60, blue: 0.64)
        case .blocked: Color(red: 1, green: 0.61, blue: 0.37)
        }
    }
}

private struct ChannelTrustNode: View {
    let label: String
    let value: String
    let state: ChannelTrustNodeState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 5.7, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.40))
            Text(value)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(state.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Color.white.opacity(0.025))
        .overlay { Rectangle().stroke(state.color.opacity(0.46), lineWidth: 1) }
    }
}

private struct ChannelTrustLink: View {
    let ready: Bool

    var body: some View {
        Rectangle()
            .fill(ready ? AppPalette.terminalGreen : Color(red: 0.38, green: 0.44, blue: 0.47))
            .frame(width: 12, height: 1)
    }
}

private struct ChannelHostKeyRow: View {
    let key: SSHHostKey
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(selected ? AppPalette.ibmBlue : Color.clear)
                .frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(key.algorithm.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                    Spacer()
                    Text(selected ? "SELECTED" : "CANDIDATE")
                        .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.muted)
                }
                Text(key.fingerprint)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(selected ? AppPalette.ibmBlue.opacity(0.07) : AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct ChannelCapability: Identifiable {
    let id: String
    let detail: String
    let state: String
    let color: Color

    static let defaults: [Self] = [
        .init(id: "PASE DIAGNOSTICS", detail: "Read after trust", state: "READ", color: AppPalette.success),
        .init(id: "IFS BROWSE", detail: "Read after auth", state: "READ", color: AppPalette.success),
        .init(id: "IFS DOWNLOAD", detail: "Read after auth", state: "READ", color: AppPalette.success),
        .init(id: "IFS UPLOAD", detail: "Compare gate", state: "WRITE", color: AppPalette.warning),
        .init(id: "SOURCE MEMBERS", detail: "Separate Db2 capability", state: "SEPARATE", color: AppPalette.ibmBlue),
        .init(id: "PORT FORWARDING", detail: "Policy", state: "OFF", color: AppPalette.danger),
        .init(id: "REMOTE SHELL", detail: "No interactive shell", state: "OFF", color: AppPalette.danger)
    ]
}

private struct ChannelCapabilityRow: View {
    let capability: ChannelCapability

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(capability.color).frame(width: 4, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.id)
                    .font(.system(size: 7.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Text(capability.detail)
                    .font(.system(size: 7.7))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            Text(capability.state)
                .font(.system(size: 6.4, weight: .bold, design: .monospaced))
                .foregroundStyle(capability.color)
        }
        .padding(.horizontal, 11)
        .frame(height: 47)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct ChannelBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 4, height: 12)
            Text(label)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .tracking(0.45)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(color.opacity(0.08))
        .overlay { Rectangle().stroke(color.opacity(0.42), lineWidth: 1) }
    }
}

private struct ChannelEnvironmentButtonStyle: ButtonStyle {
    let selected: Bool
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .foregroundStyle(selected ? Color.white : AppPalette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? color : AppPalette.raised)
            .overlay { Rectangle().stroke(selected ? color : AppPalette.border, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct ChannelSegmentButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(selected ? AppPalette.ibmBlue.opacity(0.09) : AppPalette.panel)
            .overlay { Rectangle().stroke(selected ? AppPalette.ibmBlue : AppPalette.borderStrong, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct ChannelOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(AppPalette.text)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(configuration.isPressed ? AppPalette.raised : AppPalette.panel)
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
    }
}

private struct ChannelBlackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(AppPalette.instrument.opacity(configuration.isPressed ? 0.76 : 1))
    }
}

private struct ChannelGateButtonStyle: ButtonStyle {
    let ready: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(ready ? Color.white : Color.white.opacity(0.43))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(ready ? AppPalette.instrument : AppPalette.instrument.opacity(0.94))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private struct SecureChannelConduitGlyph: View {
    var body: some View {
        Canvas { context, size in
            let shell = Path(CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1))
            context.fill(shell, with: .color(AppPalette.instrument))
            context.stroke(shell, with: .color(AppPalette.borderStrong), lineWidth: 1)
            var path = Path()
            path.move(to: CGPoint(x: 6, y: 7))
            path.addLine(to: CGPoint(x: 13, y: 7))
            path.addLine(to: CGPoint(x: 13, y: 14))
            path.addLine(to: CGPoint(x: 22, y: 14))
            path.addLine(to: CGPoint(x: 22, y: 22))
            path.addLine(to: CGPoint(x: 16, y: 22))
            path.addLine(to: CGPoint(x: 16, y: 17))
            path.addLine(to: CGPoint(x: 9, y: 17))
            path.addLine(to: CGPoint(x: 9, y: 11))
            path.addLine(to: CGPoint(x: 6, y: 11))
            path.closeSubpath()
            context.stroke(path, with: .color(AppPalette.registrationBlue), lineWidth: 1.4)
        }
    }
}

private struct ChannelCautionGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + 1))
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - 3))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 2))
        return path
    }
}

private struct SecureChannelEmptyGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: 2, dy: 2))
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.minY + 11))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 11))
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.midY))
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 11))
        path.addLine(to: CGPoint(x: rect.maxX - 14, y: rect.maxY - 11))
        return path
    }
}
