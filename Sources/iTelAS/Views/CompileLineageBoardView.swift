import SwiftUI
import iTelASCore

struct CompileLineageBoardView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                objectHistory
                    .frame(width: 220)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                lineageWorkspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                decisionDossier
                    .frame(width: 286)
            }
            footer
        }
        .frame(width: 1_180, height: 760)
        .background(AppPalette.window)
        .onAppear {
            proverb = .random(excluding: proverb.id)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            LineageRailSwitchMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("DELIVERY / COMPILE LINEAGE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Compile Lineage Board")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            Spacer()
            if let run = model.compileLineageCurrentRun {
                EnvironmentBadge(environment: run.recipe.environment)
            }
            localEvidenceBadge
            baselineMenu
            Button {
                model.prepareCompileLineageAssist()
            } label: {
                Label("Pin comparison", systemImage: "rectangle.stack.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.compileLineageComparison == nil)
            .help("Pin this exact local comparison to the Assist Context Shelf without sending it")
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var localEvidenceBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(AppPalette.success).frame(width: 6, height: 6)
            Text("LOCAL EVIDENCE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.45)
        }
        .foregroundStyle(AppPalette.success)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(AppPalette.success.opacity(0.07))
        .clipShape(ChamferedRectangle(cut: 3))
        .overlay {
            ChamferedRectangle(cut: 3).stroke(AppPalette.success, lineWidth: 0.8)
        }
    }

    private var baselineMenu: some View {
        Menu {
            ForEach(model.compileLineageBaselineCandidates) { run in
                Button {
                    model.selectCompileLineageBaseline(run.id)
                } label: {
                    Text("\(run.displaySequence) · \(run.outcome.label) · \(run.startedAtLabel)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.compileLineageBaselineRun.map { "Baseline \($0.displaySequence)" } ?? "No baseline")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(AppPalette.text)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(AppPalette.panel)
            .clipShape(ChamferedRectangle(cut: 3))
            .overlay {
                ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.8)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.compileLineageBaselineCandidates.isEmpty)
        .help("Choose another retained run for the same exact target")
    }

    private var objectHistory: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OBJECT HISTORY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.muted)
                    Text("\(model.compileRuns.count) retained local runs")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                MiniLineageGlyph(color: AppPalette.registrationBlue, size: 20)
            }
            .padding(.horizontal, 13)
            .frame(height: 52)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                TextField("Object, source, run", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5))
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(objectGroups) { group in
                        objectGroupHeader(group)
                        ForEach(group.runs) { run in
                            Button {
                                model.selectCompileLineageCurrent(run.id)
                            } label: {
                                lineageRunRow(run)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("RETAINED EVIDENCE ONLY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.muted)
                Label("Local comparison boundary", systemImage: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text("No host read, compile submission, object mutation, or source body is added by this view.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineSpacing(2)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }
        }
        .background(AppPalette.panel)
    }

    private var filteredRuns: [CompileRunRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.compileRuns }
        return model.compileRuns.filter { run in
            [
                run.displaySequence,
                run.objectName,
                run.recipe.targetIdentity,
                run.recipe.sourceIdentity,
                run.outcome.label,
                run.jobIdentity
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var objectGroups: [LineageObjectGroup] {
        var groups: [LineageObjectGroup] = []
        for run in filteredRuns {
            if let index = groups.firstIndex(where: { $0.identity == run.recipe.targetIdentity }) {
                groups[index].runs.append(run)
            } else {
                groups.append(LineageObjectGroup(identity: run.recipe.targetIdentity, runs: [run]))
            }
        }
        return groups
    }

    private func objectGroupHeader(_ group: LineageObjectGroup) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(group.identity == model.compileLineageCurrentRun?.recipe.targetIdentity
                      ? AppPalette.ibmBlue : AppPalette.muted)
                .frame(width: 5, height: 5)
            Text(group.identity)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("\(group.runs.count) RUN\(group.runs.count == 1 ? "" : "S")")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 11)
        .frame(height: 29)
        .background(AppPalette.window)
    }

    private func lineageRunRow(_ run: CompileRunRecord) -> some View {
        let selected = run.id == model.compileLineageCurrentRunID
        let baseline = run.id == model.compileLineageBaselineRunID
        return HStack(spacing: 9) {
            RunPulseMark(color: outcomeColor(run.outcome), size: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(run.displaySequence)
                        .foregroundStyle(outcomeColor(run.outcome))
                    if baseline {
                        Text("BASELINE")
                            .foregroundStyle(AppPalette.success)
                    }
                    Spacer()
                    Text(run.startedAtLabel)
                        .foregroundStyle(AppPalette.muted)
                }
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                Text("\(run.outcome.label) · SEV \(run.evidence.maximumSeverity)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text("\(run.sourceRevision.map { String($0.prefix(8)).uppercased() } ?? "REV UNRECORDED") · \(run.evidence.diagnostics.count) MSG")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 66)
        .background(selected ? AppPalette.selection : AppPalette.panel)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(selected ? AppPalette.ibmBlue : Color.clear)
                .frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var lineageWorkspace: some View {
        if let comparison = model.compileLineageComparison,
           let current = model.compileLineageCurrentRun,
           let baseline = model.compileLineageBaselineRun {
            VStack(spacing: 0) {
                selectedObjectHeader(current, comparison: comparison)
                runTrack(baseline: baseline, current: current, comparison: comparison)
                evidenceMatrix(comparison)
                diagnosticDelta(comparison)
            }
            .background(AppPalette.window)
        } else {
            lineageEmptyState
        }
    }

    private func selectedObjectHeader(
        _ current: CompileRunRecord,
        comparison: CompileLineageComparison
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("SELECTED LINEAGE · PROGRAM OBJECT")
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text(current.recipe.environment.label.uppercased())
                        .foregroundStyle(AppPalette.success)
                }
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                Text(current.recipe.targetIdentity)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text(current.recipe.sourceIdentity)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            LineageMetric(label: "RUNS", value: "\(comparison.runs.count)", color: AppPalette.text)
            LineageMetric(label: "EXACT", value: "\(comparison.exactFieldCount)", color: AppPalette.success)
            LineageMetric(label: "CHANGED", value: "\(comparison.changedFieldCount)", color: AppPalette.warning)
        }
        .padding(.horizontal, 14)
        .frame(height: 70)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func runTrack(
        baseline: CompileRunRecord,
        current: CompileRunRecord,
        comparison: CompileLineageComparison
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text("RUN ROUTE · BASELINE TO CURRENT")
                Spacer()
                Text("SAME EXACT TARGET")
                    .foregroundStyle(AppPalette.success)
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(AppPalette.muted)

            HStack(spacing: 10) {
                LineageRunBlock(run: baseline, role: "BASELINE", color: AppPalette.success)
                VStack(spacing: 5) {
                    Text("SOURCE / EVIDENCE DELTA")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.warning)
                    HStack(spacing: 0) {
                        Rectangle().fill(AppPalette.borderStrong).frame(height: 1)
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(AppPalette.warning)
                    }
                }
                .frame(maxWidth: .infinity)
                LineageRunBlock(run: current, role: "CURRENT", color: trendColor(comparison.trend))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(height: 100)
        .background(AppPalette.window)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func evidenceMatrix(_ comparison: CompileLineageComparison) -> some View {
        VStack(spacing: 0) {
            LineageMatrixHeader()
            ForEach(matrixFields(comparison)) { item in
                LineageMatrixRow(item: item, color: deltaColor(item.state))
            }
        }
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func matrixFields(_ comparison: CompileLineageComparison) -> [CompileLineageFieldDelta] {
        let visible = [
            "source", "revision", "toolchain", "command", "release",
            "outcome", "object", "severity", "event-receipt"
        ]
        return visible.compactMap { id in comparison.fields.first(where: { $0.id == id }) }
    }

    private func diagnosticDelta(_ comparison: CompileLineageComparison) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MESSAGE DELTA · EXACT IDENTITIES")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(AppPalette.muted)
                    Text("What appeared, disappeared, or persisted")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppPalette.text)
                }
                Spacer()
                Text("DELTA IS NOT CAUSAL PROOF")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.warning)
            }
            HStack(spacing: 9) {
                DiagnosticDeltaLane(
                    label: "INTRODUCED",
                    items: comparison.diagnostics.introduced,
                    color: AppPalette.danger
                )
                DiagnosticDeltaLane(
                    label: "RESOLVED",
                    items: comparison.diagnostics.resolved,
                    color: AppPalette.success
                )
                DiagnosticDeltaLane(
                    label: "PERSISTENT",
                    items: comparison.diagnostics.persistent,
                    color: AppPalette.ibmBlue
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxHeight: .infinity)
        .background(AppPalette.window)
    }

    private var lineageEmptyState: some View {
        VStack(spacing: 15) {
            LineageRailSwitchMark(size: 52)
            Text("Two exact-target runs are required")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppPalette.text)
            Text(model.compileLineageValidationMessage
                 ?? "Select another retained run or load compatible local evidence.")
                .font(.system(size: 10.5))
                .foregroundStyle(AppPalette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("No fallback object match is attempted.")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.warning)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.window)
    }

    @ViewBuilder
    private var decisionDossier: some View {
        if let comparison = model.compileLineageComparison {
            ScrollView {
                VStack(spacing: 0) {
                    dossierHeader
                    verdictPanel(comparison)
                    factLedger(comparison)
                    evidenceBoundary
                    receiptPanel(comparison)
                    assistBoundary
                }
            }
            .background(AppPalette.panel)
        } else {
            emptyDossier
        }
    }

    private var dossierHeader: some View {
        HStack(spacing: 10) {
            ComparisonLedgerMark(size: 31)
            VStack(alignment: .leading, spacing: 2) {
                Text("COMPARISON DOSSIER")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.muted)
                Text("Evidence verdict")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func verdictPanel(_ comparison: CompileLineageComparison) -> some View {
        let color = trendColor(comparison.trend)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("OBSERVED OUTCOME")
                Spacer()
                Text("\(comparison.changedFieldCount) CHANGED")
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            Text(comparison.trend.label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppPalette.text)
            Text(trendDescription(comparison.trend))
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.secondary)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.065))
        .overlay(alignment: .bottom) {
            Rectangle().fill(color).frame(height: 2)
        }
    }

    private func factLedger(_ comparison: CompileLineageComparison) -> some View {
        VStack(spacing: 0) {
            Text("RETAINED FACTS")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(AppPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 5)
            ForEach(matrixFields(comparison).prefix(7)) { item in
                HStack(spacing: 7) {
                    Rectangle().fill(deltaColor(item.state)).frame(width: 3, height: 17)
                    Text(item.label)
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                    Spacer()
                    Text(item.state.label)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(deltaColor(item.state))
                }
                .frame(height: 30)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppPalette.border).frame(height: 1)
                }
            }
        }
        .padding(12)
    }

    private var evidenceBoundary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("EVIDENCE BOUNDARY", systemImage: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.danger)
            LineageBoundaryRow(label: "Complete job log", value: "MISSING", color: AppPalette.danger)
            LineageBoundaryRow(label: "Remote execution", value: "NONE", color: AppPalette.success)
            LineageBoundaryRow(label: "Object authority", value: "UNVERIFIED", color: AppPalette.warning)
            LineageBoundaryRow(label: "Runtime behavior", value: "UNVERIFIED", color: AppPalette.warning)
        }
        .padding(12)
        .background(AppPalette.danger.opacity(0.035))
        .overlay {
            Rectangle().stroke(AppPalette.border, lineWidth: 1)
        }
    }

    private func receiptPanel(_ comparison: CompileLineageComparison) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LOCAL COMPARISON RECEIPT")
                Spacer()
                Text("BOUND")
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.terminalGreen)
            Text(comparison.fingerprint.uppercased())
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .textSelection(.enabled)
            Text("\(comparison.runs.count) exact run fingerprints · \(comparison.fields.count) field comparisons")
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.68))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.terminal)
    }

    private var assistBoundary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("ASSIST CONTEXT", systemImage: "rectangle.stack.badge.plus")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.ibmBlue)
            Text("Pinning freezes this local comparison for review. It does not send, compile, or execute.")
                .font(.system(size: 8.5))
                .foregroundStyle(AppPalette.secondary)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyDossier: some View {
        VStack(alignment: .leading, spacing: 12) {
            dossierHeader
            Text("NO COMPARISON RECEIPT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.warning)
            Text("A receipt appears only after two distinct retained runs share the exact target identity.")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.secondary)
                .lineSpacing(3)
            evidenceBoundary
            Spacer()
        }
        .padding(.horizontal, 12)
        .background(AppPalette.panel)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Text("LINEAGE: LOCAL · \(model.compileLineageScopedRuns.count) RUNS")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("REMOTE EXECUTION: NONE")
                .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.45))
            Text(model.compileLineageComparison.map { "RECEIPT: \($0.shortFingerprint)" } ?? "RECEIPT: UNAVAILABLE")
                .foregroundStyle(Color.white.opacity(0.68))
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .italic()
                .foregroundStyle(Color.white.opacity(0.58))
            Text("ARM64 · NATIVE")
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 13)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private func outcomeColor(_ outcome: CompileRunOutcome) -> Color {
        switch outcome {
        case .passed: AppPalette.success
        case .failed: AppPalette.danger
        case .evidenceOnly: AppPalette.ibmBlue
        }
    }

    private func deltaColor(_ state: CompileLineageDeltaState) -> Color {
        switch state {
        case .exact: AppPalette.success
        case .changed: AppPalette.warning
        case .relative: AppPalette.ibmBlue
        case .unavailable: AppPalette.danger
        }
    }

    private func trendColor(_ trend: CompileLineageTrend) -> Color {
        switch trend {
        case .regressionObserved: AppPalette.danger
        case .recoveryObserved: AppPalette.success
        case .outcomeChanged: AppPalette.warning
        case .outcomeStable: AppPalette.ibmBlue
        case .outcomeUnverified: AppPalette.muted
        }
    }

    private func trendDescription(_ trend: CompileLineageTrend) -> String {
        switch trend {
        case .regressionObserved:
            "The retained baseline passed and the current run failed. Chronology is exact; causality remains unproven."
        case .recoveryObserved:
            "The retained baseline failed and the current run passed. The evidence records recovery, not a root-cause claim."
        case .outcomeChanged:
            "The retained outcome changed between the selected runs."
        case .outcomeStable:
            "Both retained runs carry the same outcome; other evidence may still differ."
        case .outcomeUnverified:
            "At least one retained run contains evidence without an asserted compile outcome."
        }
    }
}

private struct LineageObjectGroup: Identifiable {
    let identity: String
    var runs: [CompileRunRecord]
    var id: String { identity }
}

private struct LineageMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

private struct LineageRunBlock: View {
    let run: CompileRunRecord
    let role: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            RunPulseMark(color: color, size: 21)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(role) · \(run.displaySequence)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text("\(run.outcome.label) · OBJECT \(objectResult)")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("\(run.shortFingerprint) · \(run.evidence.diagnostics.count) MSG")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 192, height: 59, alignment: .leading)
        .background(AppPalette.panel)
        .clipShape(ChamferedRectangle(cut: 3))
        .overlay {
            ChamferedRectangle(cut: 3).stroke(color, lineWidth: 0.8)
        }
    }

    private var objectResult: String {
        switch run.objectWasChanged {
        case true: "CHANGED"
        case false: "UNCHANGED"
        case nil: "UNRECORDED"
        }
    }
}

private struct LineageMatrixHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            cell("EVIDENCE FACTOR", width: 116)
            cell("BASELINE", width: 142)
            cell("CURRENT", width: 142)
            cell("COMPARISON", width: nil)
        }
        .frame(height: 27)
        .background(AppPalette.terminal)
    }

    private func cell(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(Color.white.opacity(0.68))
            .padding(.horizontal, 8)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
            }
    }
}

private struct LineageMatrixRow: View {
    let item: CompileLineageFieldDelta
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            valueCell(item.label.uppercased(), width: 116, muted: true)
            valueCell(compact(item.baselineValue), width: 142)
            valueCell(compact(item.currentValue), width: 142)
            HStack(spacing: 6) {
                Rectangle().fill(color).frame(width: 3, height: 16)
                Text(item.state.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 29)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func valueCell(_ value: String, width: CGFloat, muted: Bool = false) -> some View {
        Text(value)
            .font(.system(size: 7.5, weight: muted ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(muted ? AppPalette.muted : AppPalette.text)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppPalette.border).frame(width: 1)
            }
    }

    private func compact(_ value: String) -> String {
        guard value.count > 25 else { return value }
        return "\(value.prefix(10))…\(value.suffix(8))"
    }
}

private struct DiagnosticDeltaLane: View {
    let label: String
    let items: [CompileLineageDiagnosticIdentity]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(items.count)")
            }
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            if items.isEmpty {
                Text("No exact identities")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.muted)
            } else {
                ForEach(items.prefix(2)) { item in
                    HStack(spacing: 5) {
                        Rectangle().fill(color).frame(width: 3, height: 15)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(item.messageID) · SEV \(item.severity)")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppPalette.text)
                            Text(item.locationLabel)
                                .font(.system(size: 7))
                                .foregroundStyle(AppPalette.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                if items.count > 2 {
                    Text("+\(items.count - 2) more exact identities")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppPalette.panel)
        .clipShape(ChamferedRectangle(cut: 3))
        .overlay {
            ChamferedRectangle(cut: 3).stroke(AppPalette.border, lineWidth: 0.8)
        }
    }
}

private struct LineageBoundaryRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(AppPalette.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(height: 19)
    }
}

struct LineageRailSwitchMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 38
            let trunk = Path(CGRect(x: 8 * scale, y: 7 * scale, width: 2 * scale, height: 24 * scale))
            context.fill(trunk, with: .color(AppPalette.ibmBlue))
            context.fill(
                Path(CGRect(x: 9 * scale, y: 10 * scale, width: 15 * scale, height: 2 * scale)),
                with: .color(AppPalette.terminalGreen)
            )
            context.fill(
                Path(CGRect(x: 9 * scale, y: 25 * scale, width: 18 * scale, height: 2 * scale)),
                with: .color(.white)
            )
            context.fill(
                Path(CGRect(x: 22 * scale, y: 11 * scale, width: 2 * scale, height: 15 * scale)),
                with: .color(AppPalette.ibmBlue)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: 25 * scale, y: 7 * scale, width: 6 * scale, height: 6 * scale)),
                with: .color(AppPalette.terminalGreen)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: 25 * scale, y: 22 * scale, width: 6 * scale, height: 6 * scale)),
                with: .color(.white)
            )
        }
        .frame(width: size, height: size)
        .background(AppPalette.terminal)
        .clipShape(ChamferedRectangle(cut: 4))
        .overlay {
            ChamferedRectangle(cut: 4).stroke(AppPalette.borderStrong, lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }
}

private struct MiniLineageGlyph: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: canvasSize.height / 2))
            path.addLine(to: CGPoint(x: canvasSize.width - 3, y: canvasSize.height / 2))
            path.move(to: CGPoint(x: canvasSize.width / 2, y: 2))
            path.addLine(to: CGPoint(x: canvasSize.width / 2, y: canvasSize.height - 2))
            context.stroke(path, with: .color(color), lineWidth: 1.3)
            for point in [
                CGPoint(x: 2, y: canvasSize.height / 2),
                CGPoint(x: canvasSize.width / 2, y: 2),
                CGPoint(x: canvasSize.width / 2, y: canvasSize.height - 2)
            ] {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                    with: .color(color)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct RunPulseMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(color.opacity(0.55), lineWidth: 1)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(45))
            Circle()
                .fill(color)
                .frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct ComparisonLedgerMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 31
            context.fill(
                Path(CGRect(x: 7 * scale, y: 5 * scale, width: 2 * scale, height: 21 * scale)),
                with: .color(AppPalette.terminalGreen)
            )
            context.fill(
                Path(CGRect(x: 22 * scale, y: 5 * scale, width: 2 * scale, height: 21 * scale)),
                with: .color(.white)
            )
            context.fill(
                Path(CGRect(x: 9 * scale, y: 15 * scale, width: 13 * scale, height: 2 * scale)),
                with: .color(AppPalette.ibmBlue)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: 13 * scale, y: 11 * scale, width: 8 * scale, height: 8 * scale)),
                with: .color(AppPalette.warning)
            )
        }
        .frame(width: size, height: size)
        .background(AppPalette.terminal)
        .clipShape(ChamferedRectangle(cut: 3))
        .accessibilityHidden(true)
    }
}
