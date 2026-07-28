import SwiftUI
import iTelASCore

struct ProviderBayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var snapshot: ProviderRuntimeSnapshot {
        model.providerRuntimeSnapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                registry
                    .frame(width: 286)

                Rectangle().fill(AppPalette.border).frame(width: 1)

                VStack(spacing: 0) {
                    workspaceHeader
                    providerLoom

                    HStack(spacing: 0) {
                        readinessMatrix
                        Rectangle().fill(AppPalette.border).frame(width: 1)
                        setupDossier
                            .frame(width: 310)
                    }
                }
            }

            statusStrip
        }
        .background(AppPalette.window)
        .foregroundStyle(AppPalette.text)
        .onAppear { model.refreshProviderRuntimeProbe() }
    }

    private var titleBar: some View {
        HStack(spacing: 13) {
            ProviderConduitMark()
                .frame(width: 29, height: 29)

            VStack(alignment: .leading, spacing: 1) {
                Text("iTelAS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("SYSTEM PROVIDER BAY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(1.05)
                    .foregroundStyle(AppPalette.ibmBlue)
            }

            Spacer()

            ProviderTopBadge(label: "TARGET: UNASSIGNED", color: AppPalette.ibmBlue)
            ProviderTopBadge(label: "KEYCHAIN READY", color: AppPalette.success)

            Button("CLOSE") { dismiss() }
                .buttonStyle(ProviderOutlineButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var registry: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ACCESS SURFACES")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Provider registry")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .frame(height: 64)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 4) {
                Text("THIS MAC")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.muted)
                Text("Apple Silicon · macOS 15+")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text("Discovery checks fixed local paths only. No credential is loaded.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ProviderRegistryRow(
                title: "TN5250",
                detail: "TLS display sessions",
                metadata: "Built-in native core",
                state: .ready
            )
            ProviderRegistryRow(
                title: "SSH",
                detail: "PASE commands + diagnostics",
                metadata: snapshot.component(.ssh).resolvedPath ?? "Not detected",
                state: snapshot.component(.ssh).state
            )
            ProviderRegistryRow(
                title: "SFTP",
                detail: "IFS stream files",
                metadata: snapshot.component(.sftp).resolvedPath ?? "Not detected",
                state: snapshot.component(.sftp).state
            )
            ProviderRegistryRow(
                title: "DB2 ODBC",
                detail: "SQL + IBM i Services",
                metadata: snapshot.secureDb2PrerequisitesReady ? "Secure runtime ready" : "Prerequisites missing",
                state: snapshot.secureDb2PrerequisitesReady ? .ready : .missing,
                selected: true
            )
            ProviderRegistryRow(
                title: "SOURCE MEMBER",
                detail: "Db2 source-record access",
                metadata: model.sourceMemberCapabilityConnected
                    ? model.db2Receipt?.accessMode.label ?? "Member capability active"
                    : snapshot.secureDb2PrerequisitesReady ? "Choose a capability in Db2 Dossier" : "Db2 runtime missing",
                state: snapshot.secureDb2PrerequisitesReady ? .ready : .missing
            )

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 5) {
                Text("DISCOVERY IS READ-ONLY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.success)
                Text("No host probe, package installation, or password request occurs here.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(12)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CONNECTION CONTROL PLANE")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.95)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Access Broker")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("Prove runtime, trust, identity, and target before a host capability becomes active.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            Button("CONFIGURE SSH / SFTP") {
                model.transitionFromProviderBayToSecureChannelDossier()
            }
            .buttonStyle(ProviderOutlineButtonStyle())
            .help("Open the host-identity and known-host trust workflow")
            Button("CONFIGURE DB2") {
                model.transitionFromProviderBayToDb2ConnectionDossier()
            }
            .buttonStyle(ProviderOutlineButtonStyle())
            .help("Open the TLS, identity, and least-privilege Db2 connection workflow")
            Button("REFRESH LOCAL PROBE") {
                model.refreshProviderRuntimeProbe()
                model.showNotice("Local provider prerequisites refreshed. No host was contacted.")
            }
            .buttonStyle(ProviderBlackButtonStyle())
            .help("Checks fixed local executable and library paths only")
        }
        .padding(.horizontal, 16)
        .frame(height: 78)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var providerLoom: some View {
        VStack(spacing: 8) {
            HStack {
                Text("PROVIDER LOOM")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(Color.white)
                Text("Local runtime → trust gate → IBM i capability")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Text("DISCOVERY ONLY")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(AppPalette.terminalGreen)
            }

            ProviderLoomLane(
                kind: "SSH / SFTP",
                runtime: "SYSTEM OPENSSH",
                gate: "KNOWN HOST",
                capability: "IFS + PASE",
                ready: snapshot.sshReady && snapshot.sftpReady
            )
            ProviderLoomLane(
                kind: "DB2",
                runtime: "UNIXODBC",
                gate: "DRIVER + TLS",
                capability: "SQL SERVICES",
                ready: snapshot.secureDb2PrerequisitesReady
            )
            ProviderLoomLane(
                kind: "SOURCE MEMBER",
                runtime: "DB2 RECORD API",
                gate: "REVISION + JOURNAL",
                capability: "QSYS MEMBERS",
                ready: snapshot.secureDb2PrerequisitesReady
            )
        }
        .padding(13)
        .frame(height: 220)
        .background(AppPalette.instrument)
    }

    private var readinessMatrix: some View {
        VStack(spacing: 0) {
            HStack {
                Text("READINESS MATRIX")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.text)
                Spacer()
                Text("\(snapshot.readyCount) OF \(snapshot.evidence.count) LOCAL GATES READY")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(snapshot.secureDb2PrerequisitesReady ? AppPalette.success : AppPalette.warning)
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 8) {
                Text("GATE").frame(maxWidth: .infinity, alignment: .leading)
                Text("EVIDENCE").frame(width: 170, alignment: .leading)
                Text("STATE").frame(width: 55, alignment: .trailing)
            }
            .font(.system(size: 6.7, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 13)
            .frame(height: 29)
            .background(AppPalette.raised)

            ForEach(snapshot.evidence) { evidence in
                ProviderEvidenceRow(evidence: evidence)
            }

            Spacer(minLength: 5)

            HStack(spacing: 9) {
                ProviderCautionGlyph()
                    .stroke(AppPalette.warning, lineWidth: 1.1)
                    .frame(width: 14, height: 14)
                Text("A detected executable proves local availability, not host trust or authority.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color(red: 0.40, green: 0.33, blue: 0.14))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(AppPalette.warning.opacity(0.10))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.warning.opacity(0.45)).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var setupDossier: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                ProviderDatabaseGlyph(color: AppPalette.warning)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DB2 ODBC")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.text)
                    Text(snapshot.secureDb2PrerequisitesReady ? "LOCAL RUNTIME READY" : "PREREQUISITE REQUIRED")
                        .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                        .tracking(0.65)
                        .foregroundStyle(snapshot.secureDb2PrerequisitesReady ? AppPalette.success : AppPalette.warning)
                }
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(height: 54)
            .background(AppPalette.warning.opacity(0.08))
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.warning.opacity(0.45)).frame(height: 1) }

            VStack(alignment: .leading, spacing: 10) {
                Text("What must be true before Db2 can connect?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppPalette.text)

                ProviderDossierStep(number: "01", title: "Install unixODBC", detail: "Operator-controlled driver manager install")
                ProviderDossierStep(number: "02", title: "Install IBM ACS package", detail: "Apple Silicon supported; entitlement may apply")
                ProviderDossierStep(number: "03", title: "Register and verify", detail: "Resolve exact driver and version before loading")
                ProviderDossierStep(number: "04", title: "Choose target + TLS", detail: "Environment, certificate, user, schema, library list")
                ProviderDossierStep(number: "05", title: "Store only on request", detail: "Device-only Keychain; never project files")

                VStack(alignment: .leading, spacing: 4) {
                    Text("CREDENTIAL POLICY")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppPalette.success)
                    Text("Discovery never reads devenv files, shell history, environment variables, or another app's credential store.")
                        .font(.system(size: 8.2))
                        .foregroundStyle(AppPalette.secondary)
                }
                .padding(9)
                .background(AppPalette.success.opacity(0.07))
                .overlay { Rectangle().stroke(AppPalette.success.opacity(0.42), lineWidth: 1) }

                Spacer(minLength: 4)

                Button("OPEN DB2 CONNECTION DOSSIER") {
                    model.transitionFromProviderBayToDb2ConnectionDossier()
                }
                .buttonStyle(ProviderBlackButtonStyle())

                Link(
                    "OPEN OFFICIAL IBM INSTALL GUIDE",
                    destination: URL(string: "https://www.ibm.com/support/pages/ibm-i-access-acs-updates-mac")!
                )
                .buttonStyle(ProviderOutlineButtonStyle())

                Text(snapshot.secureDb2PrerequisitesReady
                     ? "LOCAL RUNTIME READY · TARGET STILL REQUIRED"
                     : "CONNECTION BLOCKED · LOCAL PREREQUISITES")
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(AppPalette.instrument)
            }
            .padding(13)
        }
        .background(AppPalette.panel)
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Text("PROVIDER: PREFLIGHT")
                .fontWeight(.bold)
                .foregroundStyle(AppPalette.terminalGreen)
            Text("SSH: \(snapshot.sshReady ? "AVAILABLE" : "MISSING")")
            Text("ODBC: \(snapshot.secureDb2PrerequisitesReady ? "AVAILABLE" : "MISSING")")
                .foregroundStyle(snapshot.secureDb2PrerequisitesReady ? Color(red: 0.67, green: 0.74, blue: 0.70) : Color(red: 1, green: 0.70, blue: 0.52))
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("\(snapshot.architecture.uppercased()) · NATIVE")
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }
}

private struct ProviderTopBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 4, height: 12)
            Text(label)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .tracking(0.5)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(color.opacity(0.08))
        .overlay { Rectangle().stroke(color.opacity(0.42), lineWidth: 1) }
    }
}

private struct ProviderRegistryRow: View {
    let title: String
    let detail: String
    let metadata: String
    let state: ProviderRuntimeState
    var selected = false

    private var color: Color { state == .ready ? AppPalette.success : AppPalette.warning }

    var body: some View {
        HStack(spacing: 9) {
            ProviderDatabaseGlyph(color: color)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 8.7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                    Spacer()
                    Text(state == .ready ? "READY" : "BLOCKED")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(color)
                }
                Text(detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                Text(metadata)
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(selected ? AppPalette.warning.opacity(0.07) : AppPalette.panel)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(AppPalette.warning).frame(width: 3) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct ProviderLoomLane: View {
    let kind: String
    let runtime: String
    let gate: String
    let capability: String
    let ready: Bool
    var planned = false

    private var color: Color {
        if planned { return Color(red: 0.54, green: 0.60, blue: 0.64) }
        return ready ? AppPalette.terminalGreen : Color(red: 1, green: 0.61, blue: 0.37)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(kind)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(width: 82, alignment: .leading)
            ProviderLoomNode(label: "LOCAL RUNTIME", value: runtime, color: color)
            Rectangle().fill(color).frame(maxWidth: .infinity).frame(height: 1)
            ProviderLoomNode(label: "TRUST GATE", value: gate, color: color)
            Rectangle().fill(color).frame(maxWidth: .infinity).frame(height: 1)
            ProviderLoomNode(label: "HOST SURFACE", value: capability, color: color)
            Text(planned ? "PLANNED" : ready ? "AVAILABLE" : "BLOCKED")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(color)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
        .background(Color.white.opacity(0.025))
        .overlay { Rectangle().stroke(color.opacity(0.30), lineWidth: 1) }
    }
}

private struct ProviderLoomNode: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 5.8, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(Color.white.opacity(0.42))
            Text(value)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(width: 104, height: 32, alignment: .leading)
        .background(Color.black.opacity(0.16))
        .overlay { Rectangle().stroke(color.opacity(0.48), lineWidth: 1) }
    }
}

private struct ProviderEvidenceRow: View {
    let evidence: ProviderRuntimeEvidence

    private var color: Color { evidence.state == .ready ? AppPalette.success : AppPalette.danger }

    var body: some View {
        HStack(spacing: 8) {
            Text(evidence.state == .ready ? "✓" : "×")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 16, height: 16)
                .background(color.opacity(0.08))
                .overlay { Rectangle().stroke(color.opacity(0.50), lineWidth: 1) }
            VStack(alignment: .leading, spacing: 1) {
                Text(evidence.title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text(evidence.purpose)
                    .font(.system(size: 6.8))
                    .foregroundStyle(AppPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(evidence.resolvedPath ?? evidence.evidence)
                .font(.system(size: 6.8, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            Text(evidence.state.rawValue.uppercased())
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct ProviderDossierStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.warning)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text(detail)
                    .font(.system(size: 7.5))
                    .foregroundStyle(AppPalette.secondary)
            }
        }
    }
}

private struct ProviderOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.45)
            .foregroundStyle(AppPalette.text)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(configuration.isPressed ? AppPalette.raised : AppPalette.panel)
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
    }
}

private struct ProviderBlackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.45)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(AppPalette.instrument.opacity(configuration.isPressed ? 0.78 : 1))
    }
}

private struct ProviderConduitMark: View {
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

private struct ProviderDatabaseGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 2
            let width = size.width - inset * 2
            let ellipse = CGRect(x: inset, y: inset, width: width, height: size.height * 0.28)
            context.stroke(Path(ellipseIn: ellipse), with: .color(color), lineWidth: 1.1)
            var body = Path()
            body.move(to: CGPoint(x: inset, y: ellipse.midY))
            body.addLine(to: CGPoint(x: inset, y: size.height - inset - ellipse.height / 2))
            body.addCurve(
                to: CGPoint(x: size.width - inset, y: size.height - inset - ellipse.height / 2),
                control1: CGPoint(x: inset, y: size.height - inset),
                control2: CGPoint(x: size.width - inset, y: size.height - inset)
            )
            body.addLine(to: CGPoint(x: size.width - inset, y: ellipse.midY))
            context.stroke(body, with: .color(color), lineWidth: 1.1)
            for fraction in [0.48, 0.70] {
                var ring = Path()
                let y = size.height * fraction
                ring.move(to: CGPoint(x: inset, y: y))
                ring.addCurve(
                    to: CGPoint(x: size.width - inset, y: y),
                    control1: CGPoint(x: size.width * 0.28, y: y + 4),
                    control2: CGPoint(x: size.width * 0.72, y: y + 4)
                )
                context.stroke(ring, with: .color(color.opacity(0.72)), lineWidth: 0.9)
            }
        }
    }
}

private struct ProviderCautionGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.midX, y: rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.60))
        path.move(to: CGPoint(x: rect.midX, y: rect.height * 0.74))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.76))
        return path
    }
}
