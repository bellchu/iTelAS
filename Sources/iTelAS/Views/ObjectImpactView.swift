import SwiftUI
import iTelASCore

struct ObjectImpactView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            atlasHeader
            focusBand

            HStack(spacing: 0) {
                objectSpine
                    .frame(width: 270)
                divider
                dependencyField
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                divider
                decisionDossier
                    .frame(width: 310)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .background(AppPalette.window)
    }

    private var atlasHeader: some View {
        HStack(spacing: 13) {
            ImpactLatticeMark(size: 35)

            VStack(alignment: .leading, spacing: 1) {
                Text("DEPENDENCY ATLAS")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.text)
                Text("DIRECT EVIDENCE · EXACT IDENTITY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.muted)
            }

            Rectangle()
                .fill(AppPalette.border)
                .frame(width: 1, height: 31)
                .padding(.horizontal, 2)

            targetField("LIBRARY", text: Bindable(model).objectImpactLibraryText, width: 92)
            targetField("OBJECT", text: Bindable(model).objectImpactNameText, width: 104)

            VStack(alignment: .leading, spacing: 3) {
                Text("TYPE")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(AppPalette.muted)
                Picker("Object type", selection: Bindable(model).objectImpactType) {
                    ForEach(IBMObjectType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 112)
                .onChange(of: model.objectImpactType) {
                    model.objectImpactTargetDraftDidChange()
                }
            }

            Spacer(minLength: 10)

            phaseBadge

            Button("Replay") {
                model.restoreObjectImpactReplay()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                model.refreshObjectImpactEvidence()
            } label: {
                HStack(spacing: 7) {
                    if model.objectImpactPhase.isCollecting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "dot.scope")
                    }
                    Text(model.objectImpactPhase.isCollecting ? "Collecting" : "Collect Evidence")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.objectImpactPhase.isCollecting)
            .help("Run exact or tightly bounded read-only IBM i catalog queries")
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func targetField(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.muted)
            TextField(label.capitalized, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, 9)
                .frame(width: width, height: 27)
                .background(AppPalette.raised)
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.8) }
                .clipShape(ChamferedRectangle(cut: 3))
                .onChange(of: text.wrappedValue) {
                    model.objectImpactTargetDraftDidChange()
                }
        }
    }

    private var phaseBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phaseColor)
                .frame(width: 6, height: 6)
            Text(model.objectImpactPhase.label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(phaseColor.opacity(0.08))
        .overlay { ChamferedRectangle(cut: 3).stroke(phaseColor.opacity(0.45), lineWidth: 0.8) }
        .clipShape(ChamferedRectangle(cut: 3))
    }

    private var focusBand: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FOCUS OBJECT")
                    .focusEyebrow
                Text(model.objectImpactSnapshot.target.description)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.objectImpactSnapshot.isBundledReplay ? "Bundled deterministic evidence" : model.objectImpactSnapshot.targetName)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }
            .padding(.horizontal, 19)
            .frame(width: 310, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.13)).frame(width: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("CHANGE QUESTION")
                    .focusEyebrow
                Text("What must be reviewed before changing this object?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(model.objectImpactDiagnostic)
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(2)
            }
            .padding(.horizontal, 21)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.13)).frame(width: 1)

            VStack(alignment: .leading, spacing: 5) {
                Text("CHANGE GATE")
                    .focusEyebrow
                Text(model.objectImpactSnapshot.assessment.verdict)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Evidence supports review, never automatic approval")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(2)
            }
            .padding(.horizontal, 19)
            .frame(width: 275, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(AppPalette.ibmBlue)
        }
        .frame(height: 92)
        .background(AppPalette.terminal)
    }

    private var objectSpine: some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader("OBJECT SPINE", subtitle: "Exact returned metadata", tone: AppPalette.ibmBlue)

                VStack(spacing: 0) {
                    metadataRow("SYSTEM", model.objectImpactSnapshot.targetName)
                    metadataRow("LIBRARY", model.objectImpactSnapshot.target.library.value)
                    metadataRow("OBJECT", model.objectImpactSnapshot.target.name.value)
                    metadataRow("TYPE", model.objectImpactSnapshot.target.type.rawValue)
                    metadataRow("OWNER", model.objectImpactSnapshot.metadata?.owner ?? "UNAVAILABLE")
                    metadataRow("ATTRIBUTE", model.objectImpactSnapshot.metadata?.attribute ?? "UNAVAILABLE")
                    metadataRow("SIZE", objectSizeText)
                    metadataRow("CREATED", dateText(model.objectImpactSnapshot.metadata?.createdAt))
                    metadataRow("CHANGED", dateText(model.objectImpactSnapshot.metadata?.changedAt))
                    metadataRow("LAST USED", dateText(model.objectImpactSnapshot.metadata?.lastUsedAt))
                    metadataRow("SOURCE", sourceText)
                }

                evidenceContract
                evidenceLegend
            }
        }
        .background(AppPalette.panel)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(AppPalette.muted)
                .frame(width: 61, alignment: .leading)
            Rectangle().fill(AppPalette.border).frame(height: 1)
            Text(value)
                .font(.system(size: 7.7, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
                .help(value)
        }
        .padding(.horizontal, 13)
        .frame(height: 29)
        .overlay(alignment: .bottom) { divider.opacity(0.55).frame(height: 1) }
    }

    private var evidenceContract: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DIRECT-EVIDENCE CONTRACT")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.ibmBlue)
            Text("Every edge carries its IBM source and exact returned endpoint tokens. *LIBL remains unresolved. Missing rows do not prove absence; authority and row bounds can hide evidence.")
                .font(.system(size: 8.3))
                .foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("No transitive or runtime-frequency claim", systemImage: "scope")
                .font(.system(size: 7.2, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.danger)
        }
        .padding(13)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { divider.frame(height: 1) }
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var evidenceLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EDGE LANGUAGE")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.muted)
            ForEach(ObjectImpactEvidenceClass.allCases, id: \.self) { evidenceClass in
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(evidenceColor(evidenceClass))
                        .frame(width: 16, height: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(evidenceClass.label)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.text)
                        Text(legendDescription(evidenceClass))
                            .font(.system(size: 7.2))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dependencyField: some View {
        VStack(spacing: 0) {
            sectionHeader("DEPENDENCY FIELD", subtitle: "Observed direct relationships", tone: AppPalette.success)
            metricStrip
            directGraph
                .frame(height: 276)
            ledgerHeader
            edgeLedger
                .frame(maxHeight: .infinity)
            programReferenceGap
        }
        .background(AppPalette.window)
    }

    private var metricStrip: some View {
        HStack(spacing: 0) {
            impactMetric("INBOUND", model.objectImpactSnapshot.assessment.incomingCount, AppPalette.ibmBlue)
            impactMetric("OUTBOUND", model.objectImpactSnapshot.assessment.outgoingCount, AppPalette.success)
            impactMetric("BOUND", model.objectImpactSnapshot.assessment.boundCount, AppPalette.text)
            impactMetric("GAPS", model.objectImpactSnapshot.assessment.gapCount, AppPalette.danger)
        }
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func impactMetric(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(value))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { divider }
    }

    private var directGraph: some View {
        HStack(spacing: 10) {
            graphColumn(Array(model.objectImpactSnapshot.incomingEdges.prefix(3)), title: "REFERENCED BY", alignRight: true)

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.ibmBlue)

            focusNode

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.success)

            graphColumn(Array(model.objectImpactSnapshot.outgoingEdges.prefix(3)), title: "REFERENCES", alignRight: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background {
            ImpactConstructionGrid()
                .opacity(0.55)
        }
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func graphColumn(_ edges: [ObjectImpactEdge], title: String, alignRight: Bool) -> some View {
        VStack(alignment: alignRight ? .trailing : .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(AppPalette.muted)
            ForEach(edges) { edge in
                let node = alignRight ? edge.from : edge.to
                GraphNode(edge: edge, node: node, alignRight: alignRight)
            }
            let total = alignRight ? model.objectImpactSnapshot.incomingEdges.count : model.objectImpactSnapshot.outgoingEdges.count
            if total > edges.count {
                Text("+\(total - edges.count) in ledger")
                    .font(.system(size: 6.7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignRight ? .trailing : .leading)
    }

    private var focusNode: some View {
        VStack(spacing: 6) {
            ImpactLatticeMark(size: 28)
            Text(model.objectImpactSnapshot.target.name.value)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text("\(model.objectImpactSnapshot.target.library.value) · \(model.objectImpactSnapshot.target.type.rawValue)")
                .font(.system(size: 6.8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.66))
            Text("EXACT FOCUS")
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(AppPalette.terminalGreen)
        }
        .padding(.horizontal, 13)
        .frame(width: 154, height: 116)
        .background(AppPalette.terminal, in: ChamferedRectangle(cut: 7))
        .overlay {
            ChamferedRectangle(cut: 7)
                .stroke(AppPalette.ibmBlue, lineWidth: 1.2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus object \(model.objectImpactSnapshot.target.description)")
    }

    private var ledgerHeader: some View {
        HStack {
            Text("EVIDENCE LEDGER")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.ibmBlue)
            Spacer()
            Text("CLASS · DIRECTION · ENDPOINT · SOURCE")
                .font(.system(size: 6.3, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 13)
        .frame(height: 31)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var edgeLedger: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.objectImpactSnapshot.edges.isEmpty {
                    Text("No direct edges were returned within the collected evidence. This does not prove there are no dependencies.")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(model.objectImpactSnapshot.edges) { edge in
                        EdgeLedgerRow(edge: edge)
                    }
                }
            }
        }
        .background(AppPalette.panel)
    }

    private var programReferenceGap: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppPalette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("PROGRAM-REFERENCE COVERAGE UNAVAILABLE")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(AppPalette.text)
                Text("DSPPGMREF outfile creation is intentionally excluded from this read-only milestone.")
                    .font(.system(size: 7.4))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 47)
        .background(AppPalette.warning.opacity(0.1))
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.warning.opacity(0.6)).frame(height: 1) }
    }

    private var decisionDossier: some View {
        VStack(spacing: 0) {
            sectionHeader("DECISION DOSSIER", subtitle: "Human change gate", tone: AppPalette.danger)
            changeGate
            reviewChecklist
            receiptLedger
                .frame(maxHeight: .infinity)
            assistBoundary
            dossierActions
        }
        .background(AppPalette.panel)
    }

    private var changeGate: some View {
        HStack(spacing: 0) {
            Rectangle().fill(AppPalette.danger).frame(width: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text("REVIEW REQUIRED")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("The atlas proves selected relationships. It does not approve deployment or deletion.")
                    .font(.system(size: 8.2))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppPalette.terminal)
    }

    private var reviewChecklist: some View {
        VStack(spacing: 0) {
            dossierLabel("CHANGE REVIEW CHECKLIST")
            checklistRow("Confirm every BOUND consumer", complete: true)
            checklistRow("Resolve catalog registrations", complete: true)
            checklistRow("Review build candidates manually", complete: false)
            checklistRow("Close program-reference gap", complete: false)
        }
    }

    private func checklistRow(_ text: String, complete: Bool) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Rectangle()
                    .fill(complete ? AppPalette.success.opacity(0.13) : AppPalette.warning.opacity(0.12))
                    .frame(width: 23, height: 23)
                Image(systemName: complete ? "checkmark" : "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(complete ? AppPalette.success : AppPalette.warning)
            }
            Text(text)
                .font(.system(size: 8.3, weight: .medium))
                .foregroundStyle(AppPalette.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(height: 39)
        .overlay(alignment: .bottom) { divider.opacity(0.55).frame(height: 1) }
    }

    private var receiptLedger: some View {
        VStack(spacing: 0) {
            dossierLabel("SOURCE RECEIPTS")
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.objectImpactSnapshot.receipts) { receipt in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(receipt.outcome.isCollected ? AppPalette.success : AppPalette.danger)
                                .frame(width: 6, height: 6)
                            Text(receipt.source.rawValue)
                                .font(.system(size: 7.2, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppPalette.text)
                                .lineLimit(1)
                            Spacer(minLength: 3)
                            Text(receipt.outcome.isCollected ? "\(receipt.rowCount) ROWS" : "GAP")
                                .font(.system(size: 6.6, weight: .bold, design: .monospaced))
                                .foregroundStyle(receipt.outcome.isCollected ? AppPalette.success : AppPalette.danger)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .overlay(alignment: .bottom) { divider.opacity(0.45).frame(height: 1) }
                        .help(receiptHelp(receipt))
                    }
                }
            }
        }
    }

    private var assistBoundary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                UtilityGlyph(kind: .assistant, color: AppPalette.terminalGreen, size: 16)
                Text("ASSIST PRIVACY BOUNDARY")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.35)
                    .foregroundStyle(.white)
            }
            Text("Host and object identities are withheld. Only aliases, edge classes, counts, and receipt states enter the review preview.")
                .font(.system(size: 7.5))
                .foregroundStyle(Color.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(AppPalette.terminal)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.success.opacity(0.6)).frame(height: 1) }
    }

    private var dossierActions: some View {
        HStack(spacing: 8) {
            Button("Export") {
                model.exportObjectImpactSnapshot()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button("Pin to Assist Shelf") {
                model.prepareObjectImpactAssist()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(12)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { divider.frame(height: 1) }
    }

    private func sectionHeader(_ title: String, subtitle: String, tone: Color) -> some View {
        HStack(spacing: 9) {
            Rectangle().fill(tone).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(AppPalette.text)
                Text(subtitle)
                    .font(.system(size: 6.8))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func dossierLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.45)
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var statusBar: some View {
        HStack(spacing: 17) {
            Text("\(model.objectImpactSnapshot.edges.count) EVIDENCED EDGES")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("\(ObjectImpactEvidenceSource.liveSQLSources.count) SOURCES · \(model.objectImpactSnapshot.gaps.count) GAP\(model.objectImpactSnapshot.gaps.count == 1 ? "" : "S")")
                .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
            Text("HOST WRITES: NONE")
                .foregroundStyle(.white)
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("ARM64 NATIVE")
                .foregroundStyle(AppPalette.terminalGreen)
        }
        .font(.system(size: 7.4, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.58))
        .padding(.horizontal, 14)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }

    private var divider: some View { Rectangle().fill(AppPalette.border).frame(width: 1) }

    private var phaseColor: Color {
        switch model.objectImpactPhase {
        case .localReplay: AppPalette.ibmBlue
        case .collecting: AppPalette.warning
        case .ready: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var sourceText: String {
        guard let metadata = model.objectImpactSnapshot.metadata,
              let library = metadata.sourceLibrary,
              let file = metadata.sourceFile,
              let member = metadata.sourceMember else { return "UNAVAILABLE" }
        return "\(library)/\(file)(\(member))"
    }

    private var objectSizeText: String {
        guard let bytes = model.objectImpactSnapshot.metadata?.sizeBytes else { return "UNAVAILABLE" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "UNAVAILABLE" }
        return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
    }

    private func evidenceColor(_ evidenceClass: ObjectImpactEvidenceClass) -> Color {
        switch evidenceClass {
        case .bound: AppPalette.success
        case .catalog: AppPalette.ibmBlue
        case .candidate: AppPalette.warning
        }
    }

    private func legendDescription(_ evidenceClass: ObjectImpactEvidenceClass) -> String {
        switch evidenceClass {
        case .bound: "Executable ILE binding"
        case .catalog: "Db2 registration or dependency"
        case .candidate: "Build input; not proof of use"
        }
    }

    private func receiptHelp(_ receipt: ObjectImpactEvidenceReceipt) -> String {
        let result = switch receipt.outcome {
        case .collected: "Collected \(receipt.rowCount) row(s)."
        case .unavailable(let reason): "Unavailable: \(reason)"
        }
        return result + (receipt.boundWasReached ? " The evidence bound was reached." : "")
    }
}

private struct GraphNode: View {
    let edge: ObjectImpactEdge
    let node: ObjectImpactNode
    let alignRight: Bool

    var body: some View {
        VStack(alignment: alignRight ? .trailing : .leading, spacing: 3) {
            Text(node.name)
                .font(.system(size: 8.2, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
            Text("\(node.library) · \(node.type)")
                .font(.system(size: 6.4, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
            Text(edge.evidenceClass.label)
                .font(.system(size: 5.9, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(edgeColor)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 158, minHeight: 52, alignment: alignRight ? .trailing : .leading)
        .background(AppPalette.panel)
        .overlay {
            ChamferedRectangle(cut: 4).stroke(edgeColor.opacity(0.55), lineWidth: 0.8)
        }
        .clipShape(ChamferedRectangle(cut: 4))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(edge.direction.label) \(edge.evidenceClass.label) edge, \(node.label), source \(edge.source.rawValue)")
    }

    private var edgeColor: Color {
        switch edge.evidenceClass {
        case .bound: AppPalette.success
        case .catalog: AppPalette.ibmBlue
        case .candidate: AppPalette.warning
        }
    }
}

private struct EdgeLedgerRow: View {
    let edge: ObjectImpactEdge

    var body: some View {
        HStack(spacing: 9) {
            Text(edge.evidenceClass.label)
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(edgeColor)
                .frame(width: 58, alignment: .leading)
            Text(edge.direction == .incoming ? "IN" : "OUT")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .frame(width: 24, alignment: .leading)
            Text("\(edge.from.qualifiedName) → \(edge.to.qualifiedName)")
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(edge.source.rawValue)
                .font(.system(size: 6.3, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
                .frame(width: 118, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.6)).frame(height: 1) }
        .help(edge.detail ?? edge.source.rawValue)
    }

    private var edgeColor: Color {
        switch edge.evidenceClass {
        case .bound: AppPalette.success
        case .catalog: AppPalette.ibmBlue
        case .candidate: AppPalette.warning
        }
    }
}

private struct ImpactLatticeMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let thin = StrokeStyle(lineWidth: max(0.7, w * 0.022), lineCap: .square, lineJoin: .miter)
            let strong = StrokeStyle(lineWidth: max(1.2, w * 0.055), lineCap: .square, lineJoin: .miter)

            for value in [0.26, 0.5, 0.74] as [CGFloat] {
                var vertical = Path()
                vertical.move(to: CGPoint(x: w * value, y: h * 0.12))
                vertical.addLine(to: CGPoint(x: w * value, y: h * 0.88))
                context.stroke(vertical, with: .color(Color.white.opacity(0.11)), style: thin)

                var horizontal = Path()
                horizontal.move(to: CGPoint(x: w * 0.12, y: h * value))
                horizontal.addLine(to: CGPoint(x: w * 0.88, y: h * value))
                context.stroke(horizontal, with: .color(Color.white.opacity(0.11)), style: thin)
            }

            let points = [
                CGPoint(x: w * 0.22, y: h * 0.68),
                CGPoint(x: w * 0.48, y: h * 0.30),
                CGPoint(x: w * 0.77, y: h * 0.62)
            ]
            var lattice = Path()
            lattice.move(to: points[0])
            lattice.addLine(to: points[1])
            lattice.addLine(to: points[2])
            lattice.addLine(to: points[0])
            context.stroke(lattice, with: .color(AppPalette.terminalGreen), style: strong)

            for (offset, point) in points.enumerated() {
                let nodeSize = w * (offset == 1 ? 0.18 : 0.13)
                let rect = CGRect(x: point.x - nodeSize / 2, y: point.y - nodeSize / 2, width: nodeSize, height: nodeSize)
                context.fill(Path(rect), with: .color(offset == 1 ? AppPalette.ibmBlue : .white))
            }
        }
        .frame(width: size, height: size)
        .padding(size * 0.08)
        .background(AppPalette.terminal, in: ChamferedRectangle(cut: size * 0.14))
        .overlay {
            ChamferedRectangle(cut: size * 0.14)
                .stroke(AppPalette.ibmBlue.opacity(0.85), lineWidth: max(0.8, size * 0.03))
        }
        .accessibilityHidden(true)
    }
}

private struct ImpactConstructionGrid: View {
    var body: some View {
        Canvas { context, size in
            let style = StrokeStyle(lineWidth: 0.5, dash: [2, 5])
            for x in stride(from: CGFloat(16), through: size.width, by: 32) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(AppPalette.border), style: style)
            }
            for y in stride(from: CGFloat(16), through: size.height, by: 32) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(AppPalette.border), style: style)
            }
        }
        .background(AppPalette.window)
        .accessibilityHidden(true)
    }
}

private extension Text {
    var focusEyebrow: some View {
        self
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(Color.white.opacity(0.52))
    }
}
