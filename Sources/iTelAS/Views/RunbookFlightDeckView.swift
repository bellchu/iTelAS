import Foundation
import SwiftUI
import UniformTypeIdentifiers
import iTelASCore

struct RunbookFlightDeckView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var isImporterPresented = false
    @State private var reviewerAlias = "OPS-ONCALL"

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                workspaceHeader
                reviewBand
                HStack(spacing: 0) {
                    libraryAndParameters
                        .frame(width: geometry.size.width >= 1_340 ? 292 : 258)
                    divider
                    executionMap
                    if geometry.size.width >= 1_050 {
                        divider
                        preflightDossier
                            .frame(width: geometry.size.width >= 1_390 ? 354 : 318)
                    }
                }
                statusStrip
            }
            .background(AppPalette.window)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json, .data]
        ) { result in
            importBlueprint(result)
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            ProcedureCompassMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("AUTOMATION & SAFETY / PROCEDURE COMPASS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.72)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Runbook Flight Deck")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }

            Spacer(minLength: 12)

            EnvironmentBadge(environment: model.runbookEnvironment)
            phaseBadge

            Button {
                model.restoreRunbookReplay()
            } label: {
                RunbookActionLabel(kind: .restore, title: "Restore")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Restore the deterministic local review fixture")

            Button {
                isImporterPresented = true
            } label: {
                RunbookActionLabel(kind: .importFile, title: "Import")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Import a bounded local JSON blueprint; nothing is sent")

            Button {
                model.validateSelectedRunbook()
            } label: {
                RunbookActionLabel(kind: .validate, title: "Validate locally")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.selectedRunbookBlueprint == nil || model.runbookPhase == .validating)
            .help("Resolve typed parameters and safety checks locally")
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var phaseBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(phaseColor).frame(width: 6, height: 6)
            Text(model.runbookPhase.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.42)
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(phaseColor.opacity(0.07), in: ChamferedRectangle(cut: 3))
        .overlay { ChamferedRectangle(cut: 3).stroke(phaseColor.opacity(0.62), lineWidth: 0.8) }
    }

    private var reviewBand: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.selectedRunbookBlueprint?.id.rawValue ?? "NO_BLUEPRINT")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.75)
                        .foregroundStyle(AppPalette.terminalGreen)
                    if let revision = model.selectedRunbookBlueprint?.revision {
                        Text("REV \(revision)")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.54))
                    }
                }
                Text(model.selectedRunbookBlueprint?.name ?? "Select an implemented blueprint")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.selectedRunbookBlueprint?.summary ?? "Blueprint studies are visible, but only validated local documents can be resolved.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.67))
                    .lineLimit(2)
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 7) {
                Text(model.runbookResolution?.assessment.verdict ?? "VALIDATION REQUIRED")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(model.runbookResolution == nil ? AppPalette.warning : Color.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(AppPalette.warning.opacity(model.runbookResolution == nil ? 0.12 : 0.2), in: ChamferedRectangle(cut: 4))
                    .overlay { ChamferedRectangle(cut: 4).stroke(AppPalette.warning.opacity(0.72), lineWidth: 0.8) }
                HStack(spacing: 7) {
                    RunbookActionGlyph(kind: .locked, color: AppPalette.warning, size: 13)
                    Text("NO EXECUTION CONNECTOR · REVIEW ARTIFACT ONLY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.48)
                }
                .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 106)
        .background(AppPalette.instrument)
        .overlay(alignment: .leading) {
            Rectangle().fill(AppPalette.registrationBlue).frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var libraryAndParameters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                railHeader("RUNBOOK LIBRARY", detail: "LOCAL BLUEPRINTS")

                TextField("Filter procedures", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(AppPalette.panel)
                    .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.8) }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)

                VStack(spacing: 5) {
                    ForEach(filteredRunbooks) { item in
                        runbookRow(item)
                    }
                }
                .padding(.horizontal, 8)

                Rectangle().fill(AppPalette.border).frame(height: 1).padding(.vertical, 12)
                railHeader("PARAMETER RACK", detail: parameterCountLabel)

                if let blueprint = model.selectedRunbookBlueprint {
                    targetControls(blueprint)
                    VStack(spacing: 9) {
                        ForEach(blueprint.parameters) { definition in
                            parameterControl(definition)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                } else {
                    Text("Select an implemented or imported blueprint to expose its typed parameter contract.")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(AppPalette.raised.opacity(0.56))
    }

    private func railHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.75)
                .foregroundStyle(AppPalette.text)
            Spacer()
            Text(detail)
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 12)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    private func runbookRow(_ item: RunbookCatalogItem) -> some View {
        let selected = item.id == model.selectedRunbookID
        let accent = item.isAvailable ? AppPalette.registrationBlue : AppPalette.muted
        return Button {
            model.selectRunbook(item.id)
        } label: {
            HStack(spacing: 9) {
                ProcedureRouteGlyph(
                    color: selected ? AppPalette.registrationBlue : accent.opacity(0.75),
                    size: 22,
                    isAvailable: item.isAvailable
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(item.isAvailable ? AppPalette.text : AppPalette.secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(item.category)
                        Text("\(item.stepCount) STEPS")
                        Text(item.status)
                            .foregroundStyle(item.isAvailable ? AppPalette.ibmBlue : AppPalette.muted)
                    }
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.38)
                    .foregroundStyle(AppPalette.muted)
                }
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AppPalette.panel : Color.clear, in: ChamferedRectangle(cut: 4))
            .overlay {
                ChamferedRectangle(cut: 4)
                    .stroke(selected ? AppPalette.registrationBlue.opacity(0.58) : Color.clear, lineWidth: 0.8)
            }
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(AppPalette.registrationBlue).frame(width: 2) }
            }
        }
        .buttonStyle(.plain)
        .help(item.isAvailable ? item.origin.label : "Design study only; no implemented blueprint is attached")
    }

    private func targetControls(_ blueprint: RunbookBlueprint) -> some View {
        VStack(spacing: 9) {
            runbookTextField(
                label: "EXACT TARGET",
                value: Binding(
                    get: { model.runbookTargetName },
                    set: { model.editRunbookTargetName($0) }
                )
            )

            VStack(alignment: .leading, spacing: 5) {
                controlLabel("ENVIRONMENT", suffix: "EXACT")
                Picker(
                    "",
                    selection: Binding(
                        get: { model.runbookEnvironment },
                        set: { model.editRunbookEnvironment($0) }
                    )
                ) {
                    ForEach(blueprint.allowedEnvironments, id: \.self) { environment in
                        Text(environment.label).tag(environment)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            runbookTextField(
                label: "OPERATOR REASON",
                suffix: "240 CHAR MAX",
                prompt: "Required for mutating preview",
                value: Binding(
                    get: { model.runbookOperatorReason },
                    set: { model.editRunbookOperatorReason($0) }
                )
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func parameterControl(_ definition: RunbookParameterDefinition) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            controlLabel(definition.label.uppercased(), suffix: definition.kind.label)
            if definition.kind == .choice {
                Picker(
                    "",
                    selection: parameterBinding(definition)
                ) {
                    ForEach(definition.allowedValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(definition.required ? "Required" : "Optional", text: parameterBinding(definition))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(AppPalette.panel)
                    .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.75) }
            }
        }
    }

    private func runbookTextField(
        label: String,
        suffix: String? = nil,
        prompt: String = "Required",
        value: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            controlLabel(label, suffix: suffix)
            TextField(prompt, text: value)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(AppPalette.panel)
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.75) }
        }
    }

    private func controlLabel(_ label: String, suffix: String? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let suffix { Text(suffix).foregroundStyle(AppPalette.ibmBlue) }
        }
        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        .tracking(0.42)
        .foregroundStyle(AppPalette.muted)
    }

    private var executionMap: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RESOLVED EXECUTION MAP")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.75)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text(model.runbookResolution.map { "\($0.steps.count) typed steps · deterministic review sequence" } ?? "Awaiting local validation")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                }
                Spacer()
                if let resolution = model.runbookResolution {
                    Text("SHA-256  \(shortFingerprint(resolution.planFingerprint))")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { divider.frame(height: 1) }

            if let resolution = model.runbookResolution {
                ScrollView {
                    VStack(spacing: 12) {
                        VStack(spacing: 0) {
                            ForEach(resolution.steps) { step in
                                stepRow(step, resolution: resolution)
                                if step.number != resolution.steps.last?.number {
                                    HStack {
                                        Rectangle()
                                            .fill(AppPalette.borderStrong)
                                            .frame(width: 1, height: 12)
                                            .padding(.leading, 25)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        selectedStepInspector(resolution)
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 14) {
                    ProcedureCompassMark(size: 66)
                    Text(model.runbookPhase == .failed ? "Blueprint blocked" : "Resolve the local plan")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppPalette.text)
                    Text(model.runbookDiagnostic)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    Button {
                        model.validateSelectedRunbook()
                    } label: {
                        RunbookActionLabel(kind: .validate, title: "Validate locally")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.selectedRunbookBlueprint == nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            }
        }
        .background(AppPalette.window)
    }

    private func stepRow(_ step: ResolvedRunbookStep, resolution: ResolvedRunbook) -> some View {
        let selected = step.number == model.selectedRunbookStepNumber
        let state = displayState(for: step, resolution: resolution)
        let accent = color(for: state)
        return Button {
            model.selectRunbookStep(step.number)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    ChamferedRectangle(cut: 4)
                        .fill(selected ? AppPalette.instrument : AppPalette.raised)
                    ChamferedRectangle(cut: 4)
                        .stroke(selected ? AppPalette.registrationBlue : AppPalette.borderStrong, lineWidth: 0.8)
                    Text(String(format: "%02d", step.number))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? .white : AppPalette.secondary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(step.kind.label)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.48)
                            .foregroundStyle(AppPalette.ibmBlue)
                        Text(step.risk.label)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(riskColor(step.risk))
                    }
                    Text(step.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                    Text(step.detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(state.rawValue)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .frame(height: 23)
                    .background(accent.opacity(0.08), in: ChamferedRectangle(cut: 3))
                    .overlay { ChamferedRectangle(cut: 3).stroke(accent.opacity(0.5), lineWidth: 0.7) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AppPalette.panel : AppPalette.panel.opacity(0.72), in: ChamferedRectangle(cut: 5))
            .overlay {
                ChamferedRectangle(cut: 5)
                    .stroke(selected ? AppPalette.registrationBlue.opacity(0.62) : AppPalette.border, lineWidth: selected ? 1 : 0.8)
            }
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(AppPalette.registrationBlue).frame(width: 3).padding(.vertical, 6) }
            }
        }
        .buttonStyle(.plain)
    }

    private func selectedStepInspector(_ resolution: ResolvedRunbook) -> some View {
        let step = resolution.steps.first(where: { $0.number == model.selectedRunbookStepNumber })
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SELECTED STEP DOSSIER")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.72)
                        .foregroundStyle(AppPalette.terminalGreen)
                    Text(step.map { "\(String(format: "%02d", $0.number)) · \($0.title)" } ?? "No step selected")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                if step?.resolvedAction != nil {
                    Button {
                        model.copySelectedRunbookAction()
                    } label: {
                        RunbookActionLabel(kind: .copy, title: "Copy preview", tint: .white)
                    }
                    .buttonStyle(RunbookDarkButtonStyle())
                    .help("Copy resolved text locally; nothing is submitted")
                }
            }

            if let step {
                Text(step.resolvedAction ?? step.detail)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(step.resolvedAction == nil ? Color.white.opacity(0.7) : .white)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    if let maximumRows = step.maximumRows { inspectorMetric("ROW CAP", "\(maximumRows)") }
                    if let timeoutSeconds = step.timeoutSeconds { inspectorMetric("TIMEOUT", "\(timeoutSeconds)s") }
                    inspectorMetric("RISK", step.risk.label)
                    inspectorMetric("EVIDENCE", "\(step.evidence.count)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.instrument, in: ChamferedRectangle(cut: 6))
        .overlay { ChamferedRectangle(cut: 6).stroke(AppPalette.registrationBlue.opacity(0.45), lineWidth: 0.8) }
    }

    private func inspectorMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.48)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
        }
    }

    private var preflightDossier: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dossierHeading("PREFLIGHT DOSSIER", detail: "FAIL CLOSED")

                if let resolution = model.runbookResolution {
                    verdictPlate(resolution)
                    dossierSection("LOCAL CHECKS") {
                        VStack(spacing: 8) {
                            ForEach(resolution.assessment.checks) { check in
                                checkRow(check)
                            }
                        }
                    }
                    dossierSection("REVIEW ATTESTATIONS") {
                        approvalLedger(resolution)
                    }
                    dossierSection("DECLARED EVIDENCE") {
                        evidenceLedger(resolution)
                    }
                    dossierActions
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No current plan")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppPalette.text)
                        Text("Preflight checks, plan-bound attestations, and evidence requirements appear only after local validation.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppPalette.secondary)
                    }
                    .padding(14)
                }
            }
        }
        .background(AppPalette.panel)
    }

    private func dossierHeading(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.75)
                .foregroundStyle(AppPalette.text)
            Spacer()
            Text(detail)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.danger)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func verdictPlate(_ resolution: ResolvedRunbook) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolution.assessment.verdict)
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .tracking(0.48)
                        .foregroundStyle(AppPalette.text)
                    Text("\(resolution.assessment.openCheckCount) OPEN CHECKS · \(resolution.assessment.mutatingStepCount) MUTATING PREVIEW")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                RunbookActionGlyph(kind: .locked, color: AppPalette.danger, size: 26)
            }
            Text("Validation is local analysis. It is not authority, approval, current host state, or permission to run.")
                .font(.system(size: 9.5))
                .foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(AppPalette.warning.opacity(0.08), in: ChamferedRectangle(cut: 4))
        .overlay { ChamferedRectangle(cut: 4).stroke(AppPalette.warning.opacity(0.5), lineWidth: 0.8) }
        .padding(12)
    }

    private func dossierSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.65)
                .foregroundStyle(AppPalette.ibmBlue)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .top) { divider.frame(height: 1) }
    }

    private func checkRow(_ check: RunbookCheck) -> some View {
        let color = checkColor(check.state)
        return HStack(alignment: .top, spacing: 8) {
            ZStack {
                Rectangle().fill(color.opacity(0.12))
                Rectangle().stroke(color.opacity(0.55), lineWidth: 0.7)
                Rectangle().fill(color).frame(width: 4, height: 4)
            }
            .frame(width: 15, height: 15)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(check.kind.label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                    Spacer()
                    Text(check.state.label)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }
                Text(check.detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(3)
            }
        }
        .help(check.code)
    }

    private func approvalLedger(_ resolution: ResolvedRunbook) -> some View {
        let roles = requiredApprovalRoles(resolution)
        return VStack(alignment: .leading, spacing: 9) {
            if roles.isEmpty {
                Text("No review roles declared for this blueprint.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.muted)
            } else {
                ForEach(roles, id: \.self) { role in
                    let attestation = resolution.approvals.first(where: { $0.role == role })
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(attestation == nil ? AppPalette.warning : AppPalette.success)
                            .frame(width: 4, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(role.label)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppPalette.text)
                            Text(attestation?.reviewerAlias ?? "Local attestation missing")
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppPalette.muted)
                        }
                        Spacer()
                        if attestation != nil {
                            Button("Remove") { model.removeRunbookLocalAttestation(role: role) }
                                .buttonStyle(.plain)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(AppPalette.secondary)
                        } else {
                            Button("Record") {
                                model.recordRunbookLocalAttestation(role: role, reviewerAlias: reviewerAlias)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AppPalette.ibmBlue)
                        }
                    }
                }
                TextField("Reviewer alias", text: $reviewerAlias)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(AppPalette.raised)
                    .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.7) }
                Text("Local record only · identity is not cryptographically verified")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.muted)
            }
        }
    }

    private func evidenceLedger(_ resolution: ResolvedRunbook) -> some View {
        let evidence = resolution.steps.flatMap { step in
            step.evidence.map { (step.number, $0) }
        }
        return VStack(spacing: 7) {
            ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 7) {
                    Text(String(format: "%02d", item.0))
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.1.kind.label)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.text)
                        Text(item.1.label)
                            .font(.system(size: 8.5))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(item.1.required ? "REQ" : "OPT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(item.1.required ? AppPalette.warning : AppPalette.muted)
                }
            }
        }
    }

    private var dossierActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    model.exportRunbookReviewArtifact()
                } label: {
                    RunbookActionLabel(kind: .export, title: "Export review")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    model.prepareRunbookAssist()
                } label: {
                    RunbookActionLabel(kind: .assist, title: "Pin to Assist Shelf")
                }
                .buttonStyle(SecondaryButtonStyle())
                .help("Pin identity-withheld local evidence and inspect the exact Context Shelf before sending")
            }

            Button {} label: {
                RunbookActionLabel(kind: .locked, title: "Execution connector unavailable")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RunbookLockedButtonStyle())
            .disabled(true)
            .help("This milestone intentionally has no executor, scheduler, submitter, or automatic resume path")
        }
        .padding(14)
        .overlay(alignment: .top) { divider.frame(height: 1) }
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Text("LOCAL REVIEW PLANE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.65)
                .foregroundStyle(AppPalette.terminalGreen)
            Text(model.runbookDiagnostic)
                .lineLimit(1)
            Spacer(minLength: 10)
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
        }
        .font(.system(size: 8.5, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 13)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private var divider: some View {
        Rectangle().fill(AppPalette.border).frame(width: 1)
    }

    private var filteredRunbooks: [RunbookCatalogItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.runbookLibrary }
        return model.runbookLibrary.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.category.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var parameterCountLabel: String {
        guard let blueprint = model.selectedRunbookBlueprint else { return "NONE" }
        return "\(blueprint.parameters.count) TYPED"
    }

    private var phaseColor: Color {
        switch model.runbookPhase {
        case .localReplay, .ready: AppPalette.success
        case .draft, .validating: AppPalette.warning
        case .failed: AppPalette.danger
        }
    }

    private func parameterBinding(_ definition: RunbookParameterDefinition) -> Binding<String> {
        Binding(
            get: { model.runbookParameterValues[definition.key] ?? "" },
            set: { model.editRunbookParameter(definition.key, value: $0) }
        )
    }

    private func displayState(
        for step: ResolvedRunbookStep,
        resolution: ResolvedRunbook
    ) -> RunbookDisplayStepState {
        if step.risk == .destructive || step.risk == .unknown { return .blocked }
        if step.kind == .approvalGate {
            let approved = Set(resolution.approvals.map(\.role))
            return step.approvalRoles.allSatisfy(approved.contains) ? .pass : .waiting
        }
        if step.risk == .mutating { return .review }
        return .pass
    }

    private func color(for state: RunbookDisplayStepState) -> Color {
        switch state {
        case .pass: AppPalette.success
        case .review, .waiting: AppPalette.warning
        case .pending: AppPalette.muted
        case .blocked: AppPalette.danger
        }
    }

    private func riskColor(_ risk: RunbookRisk) -> Color {
        switch risk {
        case .none: AppPalette.muted
        case .readOnly: AppPalette.success
        case .mutating: AppPalette.warning
        case .destructive, .unknown: AppPalette.danger
        }
    }

    private func checkColor(_ state: RunbookCheckState) -> Color {
        switch state {
        case .pass: AppPalette.success
        case .review: AppPalette.warning
        case .blocked: AppPalette.danger
        }
    }

    private func requiredApprovalRoles(_ resolution: ResolvedRunbook) -> [RunbookApprovalRole] {
        Array(Set(resolution.steps.flatMap(\.approvalRoles))).sorted { $0.rawValue < $1.rawValue }
    }

    private func shortFingerprint(_ fingerprint: String) -> String {
        guard fingerprint.count > 17 else { return fingerprint }
        return "\(fingerprint.prefix(8))…\(fingerprint.suffix(8))"
    }

    private func importBlueprint(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            model.runbookPhase = .failed
            model.runbookDiagnostic = "Local blueprint selection failed: \(error.localizedDescription)"
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = values.fileSize,
                   fileSize > RunbookLimits.standard.maximumDocumentBytes {
                    throw RunbookError.inputTooLarge(maximum: RunbookLimits.standard.maximumDocumentBytes)
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let maximum = RunbookLimits.standard.maximumDocumentBytes
                let data = try handle.read(upToCount: maximum + 1) ?? Data()
                guard data.count <= maximum else {
                    throw RunbookError.inputTooLarge(maximum: maximum)
                }
                model.importRunbookBlueprint(data, fileName: url.lastPathComponent)
            } catch {
                model.runbookPhase = .failed
                model.runbookDiagnostic = "Local runbook import was blocked: \(error.localizedDescription)"
                model.showNotice("The local runbook document was rejected.")
            }
        }
    }
}

private enum RunbookActionGlyphKind {
    case restore
    case importFile
    case validate
    case copy
    case export
    case assist
    case locked
}

private struct RunbookActionLabel: View {
    let kind: RunbookActionGlyphKind
    let title: String
    var tint = AppPalette.secondary

    var body: some View {
        HStack(spacing: 7) {
            RunbookActionGlyph(kind: kind, color: tint, size: 14)
            Text(title)
        }
    }
}

private struct RunbookActionGlyph: View {
    let kind: RunbookActionGlyphKind
    var color: Color
    var size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let w = canvas.width
            let h = canvas.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.08), lineCap: .square, lineJoin: .miter)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func line(_ points: [CGPoint], opacity: Double = 1) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color.opacity(opacity)), style: stroke)
            }
            func box(_ rect: CGRect, opacity: Double = 1) {
                context.stroke(Path(rect), with: .color(color.opacity(opacity)), style: stroke)
            }

            switch kind {
            case .restore:
                var arc = Path()
                arc.addArc(center: p(0.52, 0.52), radius: w * 0.32, startAngle: .degrees(-65), endAngle: .degrees(250), clockwise: false)
                context.stroke(arc, with: .color(color), style: stroke)
                line([p(0.18, 0.52), p(0.16, 0.78), p(0.38, 0.68)])
                line([p(0.52, 0.31), p(0.52, 0.53), p(0.69, 0.61)], opacity: 0.7)
            case .importFile:
                box(CGRect(x: w * 0.16, y: h * 0.10, width: w * 0.55, height: h * 0.76), opacity: 0.75)
                line([p(0.44, 0.28), p(0.44, 0.68)])
                line([p(0.29, 0.53), p(0.44, 0.68), p(0.59, 0.53)])
                line([p(0.70, 0.42), p(0.86, 0.42), p(0.86, 0.88), p(0.50, 0.88)])
            case .validate:
                box(CGRect(x: w * 0.10, y: h * 0.10, width: w * 0.80, height: h * 0.80), opacity: 0.52)
                line([p(0.25, 0.51), p(0.42, 0.68), p(0.77, 0.32)])
                context.fill(Path(CGRect(x: w * 0.08, y: h * 0.08, width: w * 0.10, height: h * 0.10)), with: .color(color))
            case .copy:
                box(CGRect(x: w * 0.12, y: h * 0.12, width: w * 0.55, height: h * 0.55), opacity: 0.55)
                box(CGRect(x: w * 0.34, y: h * 0.34, width: w * 0.54, height: h * 0.54))
            case .export:
                box(CGRect(x: w * 0.12, y: h * 0.34, width: w * 0.76, height: h * 0.54), opacity: 0.72)
                line([p(0.50, 0.70), p(0.50, 0.13)])
                line([p(0.31, 0.33), p(0.50, 0.13), p(0.69, 0.33)])
            case .assist:
                var orbit = Path()
                orbit.addEllipse(in: CGRect(x: w * 0.14, y: h * 0.22, width: w * 0.72, height: h * 0.58))
                context.stroke(orbit, with: .color(color), style: stroke)
                line([p(0.22, 0.72), p(0.15, 0.91), p(0.39, 0.79)])
                context.fill(Path(CGRect(x: w * 0.34, y: h * 0.45, width: w * 0.08, height: h * 0.08)), with: .color(color))
                context.fill(Path(CGRect(x: w * 0.58, y: h * 0.45, width: w * 0.08, height: h * 0.08)), with: .color(color))
            case .locked:
                box(CGRect(x: w * 0.17, y: h * 0.43, width: w * 0.66, height: h * 0.47))
                var shackle = Path()
                shackle.addArc(center: p(0.50, 0.43), radius: w * 0.22, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                context.stroke(shackle, with: .color(color), style: stroke)
                line([p(0.28, 0.43), p(0.28, 0.33)], opacity: 0.8)
                line([p(0.72, 0.43), p(0.72, 0.33)], opacity: 0.8)
                context.fill(Path(CGRect(x: w * 0.46, y: h * 0.60, width: w * 0.08, height: h * 0.16)), with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct ProcedureCompassMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let scale = min(canvas.width, canvas.height)
            let rect = CGRect(x: scale * 0.07, y: scale * 0.07, width: scale * 0.86, height: scale * 0.86)
            let stroke = StrokeStyle(lineWidth: max(1, scale * 0.045), lineCap: .square, lineJoin: .miter)
            context.fill(Path(rect), with: .color(AppPalette.instrument))
            context.stroke(Path(rect), with: .color(AppPalette.registrationBlue.opacity(0.9)), style: stroke)

            let center = CGPoint(x: scale * 0.50, y: scale * 0.49)
            var compass = Path()
            compass.addEllipse(in: CGRect(x: scale * 0.24, y: scale * 0.23, width: scale * 0.52, height: scale * 0.52))
            context.stroke(compass, with: .color(Color.white.opacity(0.55)), style: stroke)

            var needle = Path()
            needle.move(to: CGPoint(x: scale * 0.62, y: scale * 0.30))
            needle.addLine(to: CGPoint(x: scale * 0.54, y: scale * 0.54))
            needle.addLine(to: CGPoint(x: scale * 0.37, y: scale * 0.68))
            needle.addLine(to: CGPoint(x: scale * 0.46, y: scale * 0.45))
            needle.closeSubpath()
            context.fill(needle, with: .color(AppPalette.terminalGreen))
            context.fill(Path(CGRect(x: center.x - scale * 0.045, y: center.y - scale * 0.045, width: scale * 0.09, height: scale * 0.09)), with: .color(.white))

            for point in [CGPoint(x: scale * 0.19, y: scale * 0.50), CGPoint(x: scale * 0.81, y: scale * 0.50)] {
                context.fill(Path(CGRect(x: point.x - scale * 0.025, y: point.y - scale * 0.025, width: scale * 0.05, height: scale * 0.05)), with: .color(AppPalette.registrationBlue))
            }
        }
        .frame(width: size, height: size)
        .clipShape(ChamferedRectangle(cut: size * 0.13))
        .accessibilityHidden(true)
    }
}

private struct ProcedureRouteGlyph: View {
    let color: Color
    let size: CGFloat
    let isAvailable: Bool

    var body: some View {
        Canvas { context, canvas in
            let w = canvas.width
            let h = canvas.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.065), lineCap: .square, lineJoin: .miter)
            let points = [
                CGPoint(x: w * 0.20, y: h * 0.24),
                CGPoint(x: w * 0.64, y: h * 0.24),
                CGPoint(x: w * 0.80, y: h * 0.50),
                CGPoint(x: w * 0.42, y: h * 0.76),
                CGPoint(x: w * 0.20, y: h * 0.76)
            ]
            var route = Path()
            route.move(to: points[0])
            for point in points.dropFirst() { route.addLine(to: point) }
            context.stroke(route, with: .color(color.opacity(isAvailable ? 1 : 0.5)), style: stroke)
            for (index, point) in points.enumerated() {
                let side = w * (index == 2 ? 0.14 : 0.11)
                let node = Path(CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
                if index == 0 || (isAvailable && index == points.count - 1) {
                    context.fill(node, with: .color(color))
                } else {
                    context.stroke(node, with: .color(color.opacity(0.8)), style: stroke)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct RunbookDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.13 : 0.07), in: ChamferedRectangle(cut: 3))
            .overlay { ChamferedRectangle(cut: 3).stroke(Color.white.opacity(0.28), lineWidth: 0.7) }
    }
}

private struct RunbookLockedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(AppPalette.raised, in: ChamferedRectangle(cut: 4))
            .overlay { ChamferedRectangle(cut: 4).stroke(AppPalette.borderStrong, lineWidth: 0.8) }
    }
}
