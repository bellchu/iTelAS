import SwiftUI
import iTelASCore

struct AuthorityPathAtlasView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        GeometryReader { geometry in
            VStack(spacing: 0) {
                workspaceHeader
                focusBand
                HStack(spacing: 0) {
                    evidenceRail
                        .frame(width: geometry.size.width >= 1_260 ? 276 : 234)
                    divider
                    accessField
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if geometry.size.width >= 930 {
                        divider
                        reviewDossier
                            .frame(width: geometry.size.width >= 1_260 ? 318 : 282)
                    }
                }
                statusStrip
            }
            .background(AppPalette.window)
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 11) {
            AuthorityRouteMark(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("GOVERNANCE / ACCESS PATH LENS")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Authority Path Atlas")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }

            Rectangle()
                .fill(AppPalette.border)
                .frame(width: 1, height: 32)

            scopeField("PROFILE", text: Bindable(model).authoritySubjectText, width: 84)
            scopeField("LIBRARY", text: Bindable(model).authorityLibraryText, width: 78)
            scopeField("OBJECT", text: Bindable(model).authorityObjectText, width: 94)

            VStack(alignment: .leading, spacing: 3) {
                Text("TYPE")
                    .fieldLabel
                Picker("Object type", selection: Bindable(model).authorityObjectType) {
                    ForEach(IBMObjectType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 104)
                .onChange(of: model.authorityObjectType) {
                    model.authorityInsightScopeDraftDidChange()
                }
            }

            Spacer(minLength: 6)
            phaseBadge

            Button {
                model.restoreAuthorityInsightReplay()
            } label: {
                AuthorityActionLabel(kind: .replay, title: "Replay")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Restore the deterministic local authority fixture")

            Button {
                model.refreshAuthorityInsightEvidence()
            } label: {
                HStack(spacing: 7) {
                    if model.authorityInsightPhase.isCollecting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        AuthorityActionGlyph(kind: .collect, color: .white, size: 14)
                    }
                    Text(model.authorityInsightPhase.isCollecting ? "Collecting" : "Collect Evidence")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.authorityInsightPhase.isCollecting)
            .help("Run bounded read-only IBM i security-service queries; no authority state is changed")
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func scopeField(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).fieldLabel
            TextField(label.capitalized, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, 8)
                .frame(width: width, height: 27)
                .background(AppPalette.raised)
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.8) }
                .clipShape(ChamferedRectangle(cut: 3))
                .onChange(of: text.wrappedValue) {
                    model.authorityInsightScopeDraftDidChange()
                }
        }
    }

    private var phaseBadge: some View {
        HStack(spacing: 6) {
            Rectangle().fill(phaseColor).frame(width: 6, height: 6)
            Text(model.authorityInsightPhase.label)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .tracking(0.35)
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(phaseColor.opacity(0.07), in: ChamferedRectangle(cut: 3))
        .overlay { ChamferedRectangle(cut: 3).stroke(phaseColor.opacity(0.5), lineWidth: 0.8) }
    }

    private var focusBand: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SUBJECT PROFILE").atlasEyebrow
                HStack(spacing: 8) {
                    Text(model.authorityInsightSnapshot.subject.description)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(model.authorityInsightSnapshot.profile?.status ?? "UNAVAILABLE")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.terminalGreen)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.terminalGreen.opacity(0.65), lineWidth: 0.8) }
                }
                Text(subjectGroupSummary)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.57))
                    .lineLimit(1)
            }
            .padding(.horizontal, 17)
            .frame(width: 270, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)

            VStack(alignment: .leading, spacing: 5) {
                Text("EXACT OBJECT SCOPE").atlasEyebrow
                Text(model.authorityInsightSnapshot.target.description)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.authorityInsightDiagnostic)
                    .font(.system(size: 8.3))
                    .foregroundStyle(Color.white.opacity(0.63))
                    .lineLimit(2)
            }
            .padding(.horizontal, 19)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("DECISION POSTURE").atlasEyebrow
                Text(model.authorityInsightSnapshot.assessment.verdict)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(.white)
                Text("\(model.authorityInsightSnapshot.assessment.reachableStaticPathCount) static paths · \(model.authorityInsightSnapshot.observations.count) observed checks")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .padding(.horizontal, 17)
            .frame(width: 250, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(AppPalette.ibmBlue)
        }
        .frame(height: 96)
        .background(AppPalette.terminal)
        .overlay(alignment: .leading) { Rectangle().fill(AppPalette.registrationBlue).frame(width: 3) }
    }

    private var evidenceRail: some View {
        ScrollView {
            VStack(spacing: 0) {
                railHeader("EXACT SCOPE", detail: "READ ONLY")
                metadataRow("SYSTEM", model.authorityInsightSnapshot.targetName)
                metadataRow("PROFILE", model.authorityInsightSnapshot.subject.description)
                metadataRow("CLASS", model.authorityInsightSnapshot.profile?.userClass ?? "UNAVAILABLE")
                metadataRow("OBJECT", model.authorityInsightSnapshot.target.description)
                metadataRow("OWNER", model.authorityInsightSnapshot.objectGrants.first?.owner ?? "UNAVAILABLE")
                metadataRow("AUTL", model.authorityInsightSnapshot.authorizationList ?? "NONE REPORTED")

                railHeader("EVIDENCE LEDGER", detail: "\(collectedSourceCount) / 6")
                ForEach(model.authorityInsightSnapshot.receipts) { receipt in
                    receiptRow(receipt)
                }

                railHeader("SUBJECT SIGNALS", detail: "STATIC")
                metadataRow("PRIMARY", model.authorityInsightSnapshot.profile?.primaryGroup ?? "NONE")
                metadataRow("GROUPS", String(model.authorityInsightSnapshot.groups.count))
                metadataRow("*ALLOBJ", model.authorityInsightSnapshot.assessment.hasAllObjectSignal ? "REPORTED" : "NOT REPORTED")
                metadataRow("AUTCOL", model.authorityInsightSnapshot.profile?.authorityCollectionActive == true ? "ACTIVE" : "NOT ACTIVE")

                VStack(alignment: .leading, spacing: 5) {
                    Text("VISIBILITY IS CALLER-DEPENDENT")
                        .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                        .tracking(0.35)
                        .foregroundStyle(Color(red: 0.47, green: 0.34, blue: 0.02))
                    Text("Missing rows remain an evidence gap; they never prove that access is absent.")
                        .font(.system(size: 8.3))
                        .foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.warning.opacity(0.12))
                .overlay(alignment: .leading) { Rectangle().fill(AppPalette.warning).frame(width: 2) }
                .padding(10)
            }
        }
        .background(AppPalette.panel)
    }

    private func railHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(AppPalette.text)
            Spacer()
            Text(detail)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 11)
        .padding(.top, 13)
        .padding(.bottom, 8)
        .background(AppPalette.raised.opacity(0.52))
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 6.4, weight: .bold, design: .monospaced))
                .tracking(0.25)
                .foregroundStyle(AppPalette.muted)
                .frame(width: 48, alignment: .leading)
            Rectangle().fill(AppPalette.border).frame(height: 1)
            Text(value)
                .font(.system(size: 7.3, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
                .help(value)
        }
        .padding(.horizontal, 11)
        .frame(height: 27)
        .overlay(alignment: .bottom) { divider.opacity(0.55).frame(height: 1) }
    }

    private func receiptRow(_ receipt: AuthorityEvidenceReceipt) -> some View {
        let collected = receipt.outcome.isCollected
        return HStack(spacing: 8) {
            AuthorityEvidenceSignal(collected: collected, boundWasReached: receipt.boundWasReached)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.source.rawValue)
                    .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text(receiptDetail(receipt))
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 3)
            Text(collected ? "\(receipt.rowCount)" : "GAP")
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(collected ? AppPalette.success : AppPalette.warning)
        }
        .padding(.horizontal, 11)
        .frame(height: 42)
        .overlay(alignment: .bottom) { divider.opacity(0.55).frame(height: 1) }
    }

    private var accessField: some View {
        VStack(spacing: 0) {
            fieldHeader
            metricStrip
            staticPathLattice
                .frame(maxHeight: .infinity)
            authoritySurfaceMatrix
            observedEvidenceStrip
        }
        .background(AppPalette.window)
    }

    private var fieldHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACCESS PATH LATTICE")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("Static reachability and observed checks remain separate evidence languages.")
                    .font(.system(size: 7.8))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            legendItem("STATIC", AppPalette.ibmBlue)
            legendItem("OBSERVED", AppPalette.success)
            legendItem("GAP", AppPalette.warning)
        }
        .padding(.horizontal, 13)
        .frame(height: 50)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 0) {
            metric("REACHABLE", model.authorityInsightSnapshot.assessment.reachableStaticPathCount, AppPalette.ibmBlue)
            metric("WRITE SURFACE", model.authorityInsightSnapshot.assessment.dataChangePathCount, AppPalette.warning)
            metric("OBSERVED", model.authorityInsightSnapshot.observations.count, AppPalette.success)
            metric("GAPS", model.authorityInsightSnapshot.assessment.gapCount, AppPalette.danger)
        }
        .frame(height: 52)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func metric(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(value))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { divider }
    }

    private var staticPathLattice: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PRINCIPAL / SOURCE")
                Spacer()
                Text("RESOLUTION PATH")
                Spacer()
                Text("TARGET / AUTHORITY")
            }
            .font(.system(size: 6.2, weight: .bold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 13)
            .frame(height: 27)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(model.authorityInsightSnapshot.staticPaths) { path in
                        pathRow(path)
                    }
                    if model.authorityInsightSnapshot.staticPaths.isEmpty {
                        emptyEvidence("No caller-visible static path rows were returned. This is not proof of no access.")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(AppPalette.window)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func pathRow(_ path: AuthorityPath) -> some View {
        let isExcluded = model.authoritySimulationRemovedPathIDs.contains(path.id)
        let color = pathColor(path)
        return Button {
            model.toggleAuthoritySimulationPath(path.id)
        } label: {
            HStack(spacing: 8) {
                AuthorityPathGlyph(kind: path.kind, color: color, size: 25)
                VStack(alignment: .leading, spacing: 2) {
                    Text(path.kind.label)
                        .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                        .tracking(0.35)
                        .foregroundStyle(color)
                    Text(path.principal)
                        .font(.system(size: 8.7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(1)
                }
                .frame(width: 98, alignment: .leading)

                HStack(spacing: 0) {
                    Rectangle().fill(color.opacity(0.78)).frame(height: 1)
                    Text(path.via)
                        .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .frame(height: 21)
                        .background(AppPalette.panel)
                        .overlay { Rectangle().stroke(color.opacity(0.68), lineWidth: 0.8) }
                        .lineLimit(1)
                    Rectangle().fill(color.opacity(0.78)).frame(height: 1)
                    AuthorityRouteArrow(color: color)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.authorityInsightSnapshot.target.name.value)
                        .font(.system(size: 7.1, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                    Text(path.authority)
                        .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                        .foregroundStyle(path.grantsAccess ? color : AppPalette.muted)
                }
                .frame(width: 74, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .frame(height: 49)
            .background(pathBackground(path).opacity(isExcluded ? 0.32 : 1))
            .overlay(alignment: .leading) { Rectangle().fill(isExcluded ? AppPalette.danger : color).frame(width: 2) }
            .overlay { Rectangle().stroke(isExcluded ? AppPalette.danger.opacity(0.45) : AppPalette.border, lineWidth: 0.8) }
            .overlay(alignment: .topTrailing) {
                if isExcluded {
                    Text("WHAT-IF EXCLUDED")
                        .font(.system(size: 5.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.danger)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Toggle this evidence path in the local what-if. No host change is made. \(path.note)")
        .accessibilityLabel("\(path.kind.label) path from \(path.principal), authority \(path.authority)")
    }

    private var authoritySurfaceMatrix: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AUTHORITY SURFACE")
                    .font(.system(size: 7.3, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(AppPalette.text)
                Spacer()
                Text("reported bits · not cumulative proof")
                    .font(.system(size: 6.7))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    surfaceHeader
                    ForEach(Array(model.authorityInsightSnapshot.staticPaths.prefix(5))) { path in
                        surfaceRow(path)
                    }
                }
                .frame(minWidth: 610)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(height: min(258, 75 + CGFloat(min(5, model.authorityInsightSnapshot.staticPaths.count)) * 31))
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var surfaceHeader: some View {
        HStack(spacing: 0) {
            surfaceTextCell("PATH", width: 142, alignment: .leading, isHeader: true)
            ForEach(["OBJ", "READ", "ADD", "UPDATE", "DELETE", "EXEC"], id: \.self) { label in
                surfaceTextCell(label, width: 72, alignment: .center, isHeader: true)
            }
        }
        .frame(height: 28)
        .background(AppPalette.raised)
        .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 0.8) }
    }

    private func surfaceRow(_ path: AuthorityPath) -> some View {
        let bits = [
            path.surface.objectOperational,
            path.surface.dataRead,
            path.surface.dataAdd,
            path.surface.dataUpdate,
            path.surface.dataDelete,
            path.surface.dataExecute
        ]
        let color = pathColor(path)
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Rectangle().fill(color).frame(width: 4, height: 12)
                Text("\(path.kind.label) · \(path.authority)")
                    .font(.system(size: 6.7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: 142, height: 31, alignment: .leading)
            .overlay(alignment: .trailing) { divider }
            ForEach(Array(bits.enumerated()), id: \.offset) { _, enabled in
                AuthorityBitMark(enabled: enabled, color: enabled ? color : AppPalette.muted)
                    .frame(width: 72, height: 31)
                    .overlay(alignment: .trailing) { divider }
            }
        }
        .overlay(alignment: .bottom) { divider.opacity(0.72).frame(height: 1) }
    }

    private func surfaceTextCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment,
        isHeader: Bool
    ) -> some View {
        Text(text)
            .font(.system(size: 6.2, weight: isHeader ? .bold : .regular, design: .monospaced))
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity, alignment: alignment)
            .overlay(alignment: .trailing) { divider }
    }

    private var observedEvidenceStrip: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    HStack(spacing: 5) {
                        Rectangle().fill(AppPalette.success).frame(width: 6, height: 6)
                        Text("OBSERVED")
                    }
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
                    Text(observedTitle)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                    Spacer()
                    Text("\(model.authorityInsightSnapshot.observations.count) CHECKS")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.success)
                }
                if let observation = model.authorityInsightSnapshot.observations.first {
                    HStack(spacing: 7) {
                        Text("required \(observation.requiredAuthority ?? "UNAVAILABLE")")
                        Rectangle().fill(AppPalette.success).frame(height: 1)
                        Text(observation.authoritySource ?? "SOURCE UNAVAILABLE")
                        Rectangle().fill(AppPalette.success).frame(height: 1)
                        Text("current \(observation.currentAuthority ?? "UNAVAILABLE")")
                    }
                    .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                } else {
                    Text("No runtime rows were returned; absence is not inferred.")
                        .font(.system(size: 7.2))
                        .foregroundStyle(AppPalette.secondary)
                }
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle().fill(AppPalette.border).frame(width: 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("COLLECTION COVERAGE")
                    Spacer()
                    Text("UNKNOWN")
                }
                .font(.system(size: 6.4, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.47, green: 0.34, blue: 0.02))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(AppPalette.warning.opacity(0.24))
                        Rectangle().fill(AppPalette.warning).frame(width: geometry.size.width * 0.38)
                    }
                }
                .frame(height: 4)
                Text("Unexercised code paths remain unknown.")
                    .font(.system(size: 6.7))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(.horizontal, 12)
            .frame(width: 208, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(AppPalette.warning.opacity(0.12))
        }
        .frame(height: 82)
        .background(AppPalette.panel)
    }

    private var reviewDossier: some View {
        ScrollView {
            VStack(spacing: 0) {
                dossierHeader
                findingSection
                simulationSection
                gapSection
                assistSection
            }
        }
        .background(AppPalette.panel)
    }

    private var dossierHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REVIEW DOSSIER")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("evidence before inference")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
            Text("REVIEW")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.47, green: 0.34, blue: 0.02))
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(AppPalette.warning.opacity(0.12))
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.warning, lineWidth: 0.8) }
        }
        .padding(.horizontal, 13)
        .frame(height: 50)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var findingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            dossierSectionHeader("PATH FINDINGS", detail: "03")
            findingRow(
                index: "01",
                title: "Write-capable static surface",
                detail: "\(model.authorityInsightSnapshot.assessment.dataChangePathCount) path(s) report add, update, or delete",
                color: AppPalette.warning
            )
            findingRow(
                index: "02",
                title: "Overlapping access paths",
                detail: "Direct, group, and AUTL evidence need joint review",
                color: AppPalette.ibmBlue
            )
            findingRow(
                index: "03",
                title: publicFindingTitle,
                detail: publicFinding,
                color: AppPalette.success
            )
        }
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func findingRow(index: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Text(index)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 23, height: 23)
                .background(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8.2, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 43, alignment: .leading)
        .overlay(alignment: .bottom) { divider.opacity(0.55).frame(height: 1) }
    }

    private var simulationSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            dossierSectionHeader("LOCAL WHAT-IF", detail: "NO HOST WRITE")
                .padding(.horizontal, -13)
            Text("Select any lattice path to exclude or restore it locally.")
                .font(.system(size: 7.4))
                .foregroundStyle(AppPalette.secondary)

            let result = model.authorityInsightSnapshot.simulate(
                removing: model.authoritySimulationRemovedPathIDs
            )
            HStack(spacing: 10) {
                AuthoritySimulationMark(accessRemains: result.accessRemains)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.accessRemains ? "ACCESS REMAINS" : "NO REPORTED PATH REMAINS")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .foregroundStyle(result.accessRemains ? AppPalette.ibmBlue : AppPalette.danger)
                    Text("\(result.remainingPaths.filter(\.grantsAccess).count) reported-access path(s) · local model only")
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 57, alignment: .leading)
            .background(AppPalette.ibmBlue.opacity(0.06))
            .overlay(alignment: .leading) { Rectangle().fill(result.accessRemains ? AppPalette.ibmBlue : AppPalette.danger).frame(width: 2) }

            HStack(spacing: 7) {
                Text("\(result.removedPathIDs.count) EXCLUDED")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(result.removedPathIDs.isEmpty ? AppPalette.muted : AppPalette.danger)
                Spacer()
                Button {
                    model.clearAuthoritySimulation()
                } label: {
                    AuthorityActionLabel(kind: .reset, title: "Reset")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(result.removedPathIDs.isEmpty)
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 12)
        .background(AppPalette.raised.opacity(0.45))
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var gapSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            dossierSectionHeader("INTERPRETATION GAPS", detail: "OPEN")
            if model.authorityInsightSnapshot.gaps.isEmpty {
                gapRow("Runtime coverage", "Every relevant code path still needs exercise.")
            } else {
                ForEach(model.authorityInsightSnapshot.gaps) { receipt in
                    gapRow(receipt.source.rawValue, gapReason(receipt))
                }
            }
            gapRow("Authority collection coverage", "Cached and unexercised checks remain unknown.")
            gapRow("Function usage", "Static object rows do not resolve every function ID.")
        }
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func gapRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AuthorityGapMark(color: AppPalette.warning)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 7.3, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text(detail)
                    .font(.system(size: 6.3, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
    }

    private var assistSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            dossierSectionHeader("ASSIST & HANDOFF", detail: model.aiConfiguration.isEnabled ? "ENABLED" : "OFF")
                .padding(.horizontal, -13)

            VStack(alignment: .leading, spacing: 3) {
                Text("IDENTITIES ALIASED LOCALLY")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Gaps stay attached; host, profile, object, group, owner, AUTL, timestamps, diagnostics, and fingerprints are withheld.")
                    .font(.system(size: 7))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .background(AppPalette.window)
            .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 0.8) }

            HStack(spacing: 7) {
                Button {
                    model.prepareAuthorityInsightAssist()
                } label: {
                    AuthorityActionLabel(kind: .assist, title: "Pin to Assist Shelf")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    model.exportAuthorityInsightSnapshot()
                } label: {
                    AuthorityActionLabel(kind: .export, title: "Export")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 13)
    }

    private func dossierSectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AppPalette.text)
            Spacer()
            Text(detail)
                .font(.system(size: 6.4, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 13)
        .frame(height: 34)
    }

    private func emptyEvidence(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 8.5))
            .foregroundStyle(AppPalette.muted)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity)
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Text("\(model.authorityInsightSnapshot.assessment.reachableStaticPathCount) REACHABLE PATHS")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("\(collectedSourceCount) SOURCES · \(model.authorityInsightSnapshot.gaps.count) GAP\(model.authorityInsightSnapshot.gaps.count == 1 ? "" : "S")")
                .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
            Text("HOST WRITES: NONE")
                .foregroundStyle(.white)
            Spacer()
            Text("“\(model.proverb.text)” — \(model.proverb.source)")
                .font(.system(size: 7.2, design: .default).italic())
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
            Text("ARM64 NATIVE")
                .foregroundStyle(AppPalette.terminalGreen)
        }
        .font(.system(size: 6.7, weight: .bold, design: .monospaced))
        .tracking(0.28)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(AppPalette.terminal)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
    }

    private var subjectGroupSummary: String {
        let userClass = model.authorityInsightSnapshot.profile?.userClass ?? "CLASS UNAVAILABLE"
        let groups = model.authorityInsightSnapshot.groups.map(\.groupProfile)
        guard !groups.isEmpty else { return "\(userClass) · GROUPS UNAVAILABLE" }
        let first = groups.prefix(2).joined(separator: " + ")
        let remainder = groups.count > 2 ? " + \(groups.count - 2)" : ""
        return "\(userClass) · \(first)\(remainder)"
    }

    private var collectedSourceCount: Int {
        model.authorityInsightSnapshot.receipts.filter { $0.outcome.isCollected }.count
    }

    private var observedTitle: String {
        guard let observation = model.authorityInsightSnapshot.observations.first else {
            return "No runtime evidence returned"
        }
        return "Runtime \(observation.requiredAuthority ?? "check") via \(observation.authoritySource ?? "unknown source")"
    }

    private var publicFinding: String {
        guard let path = model.authorityInsightSnapshot.staticPaths.first(where: { $0.kind == .publicAuthority }) else {
            return "No caller-visible public row returned"
        }
        return "*PUBLIC · \(path.authority)"
    }

    private var publicFindingTitle: String {
        model.authorityInsightSnapshot.staticPaths.contains(where: { $0.kind == .publicAuthority })
            ? "Public authority row retained"
            : "Public authority remains unknown"
    }

    private func receiptDetail(_ receipt: AuthorityEvidenceReceipt) -> String {
        switch receipt.outcome {
        case .collected:
            return receipt.boundWasReached ? "BOUND REACHED" : "COLLECTED"
        case .unavailable:
            return "UNAVAILABLE"
        }
    }

    private func gapReason(_ receipt: AuthorityEvidenceReceipt) -> String {
        if case .unavailable(let reason) = receipt.outcome { return reason }
        return "No gap was reported."
    }

    private func pathColor(_ path: AuthorityPath) -> Color {
        if !path.grantsAccess { return AppPalette.success }
        if path.surface.carriesDataChange { return AppPalette.warning }
        switch path.kind {
        case .observed: return AppPalette.success
        case .publicAuthority: return AppPalette.success
        default: return AppPalette.ibmBlue
        }
    }

    private func pathBackground(_ path: AuthorityPath) -> Color {
        if !path.grantsAccess { return AppPalette.success.opacity(0.055) }
        if path.surface.carriesDataChange { return AppPalette.warning.opacity(0.075) }
        return AppPalette.ibmBlue.opacity(0.045)
    }

    private var phaseColor: Color {
        switch model.authorityInsightPhase {
        case .localReplay: AppPalette.warning
        case .collecting: AppPalette.ibmBlue
        case .ready: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var divider: some View { Rectangle().fill(AppPalette.border).frame(width: 1) }
}

private extension Text {
    var atlasEyebrow: some View {
        self
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(Color.white.opacity(0.5))
    }

    var fieldLabel: some View {
        self
            .font(.system(size: 6.3, weight: .bold, design: .monospaced))
            .tracking(0.42)
            .foregroundStyle(AppPalette.muted)
    }
}

private struct AuthorityRouteMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let blue = AppPalette.registrationBlue
            let green = AppPalette.terminalGreen
            let stroke = StrokeStyle(lineWidth: max(1.1, w * 0.045), lineCap: .square, lineJoin: .miter)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            var outer = Path()
            outer.move(to: p(0.16, 0.16))
            outer.addLine(to: p(0.84, 0.16))
            outer.addLine(to: p(0.84, 0.39))
            outer.addLine(to: p(0.64, 0.39))
            outer.addLine(to: p(0.64, 0.61))
            outer.addLine(to: p(0.84, 0.61))
            outer.addLine(to: p(0.84, 0.84))
            outer.addLine(to: p(0.16, 0.84))
            outer.addLine(to: p(0.16, 0.61))
            outer.addLine(to: p(0.36, 0.61))
            outer.addLine(to: p(0.36, 0.39))
            outer.addLine(to: p(0.16, 0.39))
            outer.closeSubpath()
            context.stroke(outer, with: .color(blue), style: stroke)
            var diamond = Path()
            diamond.move(to: p(0.50, 0.28))
            diamond.addLine(to: p(0.72, 0.50))
            diamond.addLine(to: p(0.50, 0.72))
            diamond.addLine(to: p(0.28, 0.50))
            diamond.closeSubpath()
            context.stroke(diamond, with: .color(green), style: stroke)
            context.fill(Path(CGRect(x: w * 0.455, y: h * 0.455, width: w * 0.09, height: h * 0.09)), with: .color(AppPalette.warning))
        }
        .frame(width: size, height: size)
        .background(AppPalette.terminal)
        .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 0.8) }
        .accessibilityLabel("Authority Path Atlas route mark")
    }
}

private enum AuthorityActionKind {
    case replay
    case collect
    case reset
    case assist
    case export
}

private struct AuthorityActionLabel: View {
    let kind: AuthorityActionKind
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            AuthorityActionGlyph(kind: kind, color: kind == .export ? .white : AppPalette.registrationBlue, size: 13)
            Text(title)
        }
    }
}

private struct AuthorityActionGlyph: View {
    let kind: AuthorityActionKind
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.085), lineCap: .square, lineJoin: .miter)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func line(_ points: [CGPoint], opacity: Double = 1) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color.opacity(opacity)), style: stroke)
            }
            switch kind {
            case .replay:
                line([p(0.78, 0.24), p(0.35, 0.24), p(0.19, 0.48), p(0.35, 0.73), p(0.76, 0.73)])
                line([p(0.58, 0.10), p(0.78, 0.24), p(0.61, 0.40)])
            case .collect:
                line([p(0.12, 0.24), p(0.88, 0.24)])
                line([p(0.12, 0.50), p(0.69, 0.50)])
                line([p(0.12, 0.76), p(0.54, 0.76)])
                line([p(0.78, 0.55), p(0.78, 0.90)])
                line([p(0.61, 0.72), p(0.95, 0.72)])
            case .reset:
                line([p(0.79, 0.31), p(0.62, 0.16), p(0.33, 0.18), p(0.15, 0.42), p(0.21, 0.71), p(0.47, 0.84), p(0.73, 0.71)])
                line([p(0.61, 0.31), p(0.79, 0.31), p(0.79, 0.13)])
            case .assist:
                line([p(0.18, 0.20), p(0.82, 0.20), p(0.82, 0.69), p(0.49, 0.69), p(0.28, 0.86), p(0.28, 0.69), p(0.18, 0.69), p(0.18, 0.20)])
                line([p(0.37, 0.42), p(0.63, 0.42)])
            case .export:
                line([p(0.50, 0.10), p(0.50, 0.68)])
                line([p(0.29, 0.29), p(0.50, 0.10), p(0.71, 0.29)])
                line([p(0.16, 0.57), p(0.16, 0.86), p(0.84, 0.86), p(0.84, 0.57)])
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct AuthorityEvidenceSignal: View {
    let collected: Bool
    let boundWasReached: Bool

    var body: some View {
        let color = !collected || boundWasReached ? AppPalette.warning : AppPalette.success
        ZStack {
            Rectangle().stroke(color, lineWidth: 0.9)
            Rectangle().fill(color).frame(width: 5, height: 5)
        }
        .frame(width: 17, height: 17)
        .accessibilityHidden(true)
    }
}

private struct AuthorityPathGlyph: View {
    let kind: AuthorityPathKind
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .square, lineJoin: .miter)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func line(_ points: [CGPoint]) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color), style: stroke)
            }
            switch kind {
            case .direct:
                line([p(0.15, 0.50), p(0.85, 0.50)])
            case .primaryGroup, .supplementalGroup:
                line([p(0.12, 0.28), p(0.42, 0.28), p(0.42, 0.72), p(0.88, 0.72)])
                line([p(0.42, 0.50), p(0.72, 0.50)])
            case .publicAuthority:
                line([p(0.15, 0.22), p(0.50, 0.50), p(0.15, 0.78)])
                line([p(0.50, 0.50), p(0.88, 0.50)])
            case .owner:
                line([p(0.18, 0.76), p(0.18, 0.24), p(0.82, 0.24), p(0.82, 0.76), p(0.18, 0.76)])
                line([p(0.37, 0.50), p(0.63, 0.50)])
            case .authorizationList:
                line([p(0.13, 0.25), p(0.43, 0.25), p(0.43, 0.50), p(0.86, 0.50)])
                line([p(0.13, 0.75), p(0.43, 0.75), p(0.43, 0.50)])
            case .allObject:
                line([p(0.50, 0.10), p(0.50, 0.90)])
                line([p(0.10, 0.50), p(0.90, 0.50)])
                line([p(0.22, 0.22), p(0.78, 0.78)])
                line([p(0.78, 0.22), p(0.22, 0.78)])
            case .observed:
                var ring = Path()
                ring.addEllipse(in: CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.64, height: h * 0.64))
                context.stroke(ring, with: .color(color), style: stroke)
                context.fill(Path(CGRect(x: w * 0.43, y: h * 0.43, width: w * 0.14, height: h * 0.14)), with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct AuthorityRouteArrow: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
        .frame(width: 6, height: 9)
        .accessibilityHidden(true)
    }
}

private struct AuthorityBitMark: View {
    let enabled: Bool
    let color: Color

    var body: some View {
        Canvas { context, size in
            if enabled {
                context.fill(Path(CGRect(x: size.width / 2 - 3, y: size.height / 2 - 3, width: 6, height: 6)), with: .color(color))
            } else {
                var path = Path()
                path.move(to: CGPoint(x: size.width / 2 - 3, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2 + 3, y: size.height / 2))
                context.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 1)
            }
        }
        .accessibilityLabel(enabled ? "Reported" : "Not reported")
    }
}

private struct AuthoritySimulationMark: View {
    let accessRemains: Bool

    var body: some View {
        let color = accessRemains ? AppPalette.ibmBlue : AppPalette.danger
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.4, lineCap: .square, lineJoin: .miter)
            var path = Path()
            path.move(to: CGPoint(x: 5, y: 5))
            path.addLine(to: CGPoint(x: 5, y: size.height - 5))
            path.move(to: CGPoint(x: 5, y: size.height * 0.35))
            path.addLine(to: CGPoint(x: size.width - 5, y: 5))
            path.move(to: CGPoint(x: 5, y: size.height * 0.65))
            path.addLine(to: CGPoint(x: size.width - 5, y: size.height - 5))
            context.stroke(path, with: .color(color), style: stroke)
        }
        .frame(width: 35, height: 35)
        .background(color.opacity(0.08))
        .overlay { Rectangle().stroke(color.opacity(0.65), lineWidth: 0.8) }
        .accessibilityHidden(true)
    }
}

private struct AuthorityGapMark: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)
            context.stroke(Path(rect), with: .color(color), lineWidth: 0.8)
            var path = Path()
            path.move(to: CGPoint(x: 3, y: 3))
            path.addLine(to: CGPoint(x: size.width - 3, y: size.height - 3))
            path.move(to: CGPoint(x: size.width - 3, y: 3))
            path.addLine(to: CGPoint(x: 3, y: size.height - 3))
            context.stroke(path, with: .color(color), lineWidth: 0.8)
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}
