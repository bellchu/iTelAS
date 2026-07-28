import SwiftUI
import UniformTypeIdentifiers
import iTelASCore

struct CompileEvidenceTimelineView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var selectedSurface: CompileEvidenceSurface = .source
    @State private var isImporterPresented = false

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            HStack(spacing: 0) {
                runLedger
                    .frame(width: 258)
                Rectangle()
                    .fill(AppPalette.border)
                    .frame(width: 1)
                if let run = model.selectedCompileRun {
                    evidenceWorkspace(run)
                } else {
                    ContentUnavailableView(
                        "No compile evidence",
                        systemImage: "hammer",
                        description: Text("Load a local EVFEVENT export to begin.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            statusStrip
        }
        .background(AppPalette.window)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.plainText, .data]
        ) { result in
            importEvidence(result)
        }
        .sheet(isPresented: Binding(
            get: { model.isCompileRecipeStudioPresented },
            set: { model.isCompileRecipeStudioPresented = $0 }
        )) {
            CompileRecipeStudioView()
        }
        .sheet(isPresented: Binding(
            get: { model.isCompileLineagePresented },
            set: { model.isCompileLineagePresented = $0 }
        )) {
            CompileLineageBoardView()
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            CompileEvidenceLoomMark(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("DELIVERY / EVIDENCE LOOM")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Compile Evidence Timeline")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            Spacer()
            if let run = model.selectedCompileRun {
                EnvironmentBadge(environment: run.recipe.environment)
                evidenceModeBadge(run)
            }
            Button {
                model.presentCompileLineage()
            } label: {
                HStack(spacing: 6) {
                    LineageRailSwitchMark(size: 13)
                    Text("Lineage")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.selectedCompileRun == nil)
            .help("Compare retained runs for one exact target without contacting a host")
            Button {
                model.presentCompileRecipeStudio()
            } label: {
                HStack(spacing: 6) {
                    CompileRecipeHeaderGlyph(size: 13)
                    Text("Recipe Studio")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Open typed, persistent local compile recipes and compare them with retained run evidence")
            Button {
                model.prepareCompileAssist()
            } label: {
                HStack(spacing: 6) {
                    UtilityGlyph(kind: .contextShelf, color: AppPalette.secondary, size: 13)
                    Text("Pin to Assist Shelf")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.selectedCompileRun == nil)
            .help("Pin a local, redacted evidence item. This does not send a request.")

            Button {
                isImporterPresented = true
            } label: {
                Label("Load EVFEVENT", systemImage: "folder.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .help("Import a bounded UTF-8 EVFEVENT export from this Mac")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func evidenceModeBadge(_ run: CompileRunRecord) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(run.origin == .bundledReplay ? AppPalette.success : AppPalette.ibmBlue)
                .frame(width: 6, height: 6)
            Text(run.origin.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
        }
        .foregroundStyle(run.origin == .bundledReplay ? AppPalette.success : AppPalette.ibmBlue)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            (run.origin == .bundledReplay ? AppPalette.success : AppPalette.ibmBlue).opacity(0.07)
        )
        .overlay {
            ChamferedRectangle(cut: 3)
                .stroke(run.origin == .bundledReplay ? AppPalette.success : AppPalette.ibmBlue, lineWidth: 0.8)
        }
        .clipShape(ChamferedRectangle(cut: 3))
    }

    private var runLedger: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RUN LEDGER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.muted)
                    Text("\(model.compileRuns.count) local records")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                WorkbenchGlyph(tool: .buildAndTest, color: AppPalette.registrationBlue, size: 18)
            }
            .padding(.horizontal, 13)
            .frame(height: 50)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                TextField("Object, job, message", text: $searchText)
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
                    ForEach(filteredRuns) { run in
                        CompileRunLedgerRow(
                            run: run,
                            isSelected: run.id == model.selectedCompileRunID
                        ) {
                            model.selectCompileRun(run.id)
                            selectedSurface = .source
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if let run = model.selectedCompileRun {
                recipePanel(run)
            }
        }
        .background(AppPalette.panel)
    }

    private var filteredRuns: [CompileRunRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.compileRuns }
        return model.compileRuns.filter { run in
            [
                run.objectName,
                run.jobIdentity,
                run.recipe.sourceIdentity,
                run.recipe.targetIdentity,
                run.evidence.diagnostics.map(\.messageID).joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private func recipePanel(_ run: CompileRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
            Text("RECIPE EVIDENCE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.muted)
            CompileFact(label: "SOURCE", value: run.recipe.sourceIdentity)
            CompileFact(label: "TARGET", value: run.recipe.targetIdentity)
            CompileFact(label: "COMPILER", value: run.recipe.compiler)
            CompileFact(label: "EVENT FILE", value: run.recipe.eventFileIdentity)
            Text(run.recipe.commandPreview)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(AppPalette.terminalGreen)
                .textSelection(.enabled)
                .lineLimit(4)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.terminal, in: ChamferedRectangle(cut: 3))
            CompileGateRow(label: "Environment", value: run.recipe.environment.label, color: AppPalette.environment(run.recipe.environment))
            CompileGateRow(label: "Remote execution", value: "NOT WIRED", color: AppPalette.danger)
            CompileGateRow(label: "Host writes", value: "NONE", color: AppPalette.success)
        }
        .padding(13)
    }

    private func evidenceWorkspace(_ run: CompileRunRecord) -> some View {
        VStack(spacing: 0) {
            runSummary(run)
            HStack(spacing: 0) {
                sourceAndEvidencePanel(run)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                diagnosticDossier(run)
                    .frame(width: 320)
            }
            evidenceTimeline(run)
                .frame(height: 142)
        }
        .background(AppPalette.window)
    }

    private func runSummary(_ run: CompileRunRecord) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(run.displaySequence)
                        .foregroundStyle(outcomeColor(run.outcome))
                    Text(run.origin.label)
                        .foregroundStyle(AppPalette.muted)
                }
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                Text("\(run.objectName) · source-linked evidence")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("\(run.recipe.sourceIdentity) → \(run.recipe.targetIdentity)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            CompileFact(label: "JOB", value: run.jobIdentity, width: 185)
            CompileFact(label: "DURATION", value: run.durationLabel, width: 76)
            CompileFact(label: "EVIDENCE", value: "\(run.evidence.diagnostics.count) messages", width: 86)
            HStack(spacing: 7) {
                DiagnosticPulseMark(color: outcomeColor(run.outcome), size: 25)
                Text(run.outcome.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(outcomeColor(run.outcome))
            }
            .padding(.horizontal, 9)
            .frame(height: 31)
            .background(outcomeColor(run.outcome).opacity(0.07))
            .overlay {
                ChamferedRectangle(cut: 3)
                    .stroke(outcomeColor(run.outcome), lineWidth: 0.8)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func sourceAndEvidencePanel(_ run: CompileRunRecord) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(CompileEvidenceSurface.allCases) { surface in
                    Button {
                        selectedSurface = surface
                    } label: {
                        Text(surface.label(run: run))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(selectedSurface == surface ? AppPalette.ibmBlue : AppPalette.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 35)
                            .overlay(alignment: .bottom) {
                                if selectedSurface == surface {
                                    Rectangle().fill(AppPalette.ibmBlue).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Label(
                    "\(run.evidence.recordCount) records · \(String(run.evidence.fingerprint.prefix(10)).uppercased())",
                    systemImage: "link"
                )
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.success)
                .padding(.trailing, 12)
            }
            .frame(height: 38)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }

            if let diagnostic = model.selectedCompileDiagnostic ?? run.analysis.primaryDiagnostic {
                diagnosticBanner(diagnostic, analysis: run.analysis)
            } else {
                cleanBanner(run)
            }

            Group {
                switch selectedSurface {
                case .source:
                    sourceSurface(run)
                case .eventFile:
                    eventSurface(run)
                case .jobLog:
                    jobLogSurface(run)
                case .command:
                    commandSurface(run)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppPalette.panel)
    }

    private func diagnosticBanner(
        _ diagnostic: CompileDiagnostic,
        analysis: CompileEvidenceAnalysis
    ) -> some View {
        HStack(spacing: 11) {
            Rectangle()
                .fill(diagnostic.band.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(diagnostic.messageID)
                        .foregroundStyle(diagnostic.band.color)
                    Text("SEV \(diagnostic.severity)")
                        .foregroundStyle(AppPalette.secondary)
                    if diagnostic.id == analysis.primaryDiagnostic?.id {
                        Text("FIRST ACTIONABLE · INFERRED")
                            .foregroundStyle(AppPalette.warning)
                    }
                }
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                Text(diagnostic.message)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(2)
                Text(diagnosticLocation(diagnostic))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            if diagnostic.startLine > 0 {
                Text("LINE \(diagnostic.startLine)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .background(AppPalette.ibmBlue.opacity(0.07))
                    .overlay {
                        ChamferedRectangle(cut: 3).stroke(AppPalette.ibmBlue, lineWidth: 0.8)
                    }
            }
        }
        .padding(.trailing, 12)
        .frame(minHeight: 68)
        .background(diagnostic.band.color.opacity(0.045))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func cleanBanner(_ run: CompileRunRecord) -> some View {
        HStack(spacing: 10) {
            DiagnosticPulseMark(color: AppPalette.success, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("NO COMPILER DIAGNOSTICS")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
                Text(run.outcome == .passed
                     ? "The retained event evidence contains no ERROR records."
                     : "The imported evidence contains no diagnostic records.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(height: 62)
        .background(AppPalette.success.opacity(0.045))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private func sourceSurface(_ run: CompileRunRecord) -> some View {
        if let sourceText = run.sourceText {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sourceExcerpt(sourceText, run: run)) { line in
                        let selected = line.number == model.selectedCompileDiagnostic?.startLine
                            || (model.selectedCompileDiagnostic == nil
                                && line.number == run.analysis.primaryDiagnostic?.startLine)
                        HStack(spacing: 10) {
                            Text(String(format: "%05d", line.number))
                                .foregroundStyle(selected ? Color.white : Color(red: 0.46, green: 0.57, blue: 0.52))
                                .frame(width: 46, alignment: .trailing)
                            Rectangle()
                                .fill(selected ? AppPalette.danger : AppPalette.terminalRaised)
                                .frame(width: 3, height: 17)
                            Text(line.text.isEmpty ? " " : line.text)
                                .foregroundStyle(selected ? Color.white : Color(red: 0.83, green: 0.9, blue: 0.86))
                                .textSelection(.enabled)
                                .frame(minWidth: 620, alignment: .leading)
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .padding(.horizontal, 11)
                        .frame(height: 25)
                        .background(selected ? AppPalette.danger.opacity(0.34) : AppPalette.terminal)
                    }
                }
                .padding(.vertical, 9)
            }
            .background(AppPalette.terminal)
        } else {
            ContentUnavailableView(
                "Source snapshot not attached",
                systemImage: "doc.text.magnifyingglass",
                description: Text("The diagnostic identity remains exact. Load the matching source revision separately before showing line content.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.terminal.opacity(0.035))
        }
    }

    private func eventSurface(_ run: CompileRunRecord) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if run.evidence.diagnostics.isEmpty {
                    ContentUnavailableView(
                        "No ERROR records",
                        systemImage: "checkmark.seal",
                        description: Text("The retained EVFEVENT evidence has no compiler diagnostics.")
                    )
                    .padding(.top, 50)
                } else {
                    ForEach(run.evidence.diagnostics) { diagnostic in
                        Button {
                            model.selectCompileDiagnostic(diagnostic.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                DiagnosticPulseMark(color: diagnostic.band.color, size: 18)
                                Text(diagnostic.messageID)
                                    .frame(width: 68, alignment: .leading)
                                Text("SEV \(diagnostic.severity)")
                                    .foregroundStyle(diagnostic.band.color)
                                    .frame(width: 48, alignment: .leading)
                                Text(diagnosticLocation(diagnostic))
                                    .foregroundStyle(AppPalette.secondary)
                                    .frame(width: 210, alignment: .leading)
                                Text(diagnostic.message)
                                    .foregroundStyle(AppPalette.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(2)
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                diagnostic.id == model.selectedCompileDiagnosticID
                                ? diagnostic.band.color.opacity(0.07)
                                : Color.clear
                            )
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(AppPalette.border).frame(height: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func jobLogSurface(_ run: CompileRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DiagnosticPulseMark(color: AppPalette.warning, size: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("JOB LOG EVIDENCE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.warning)
                    Text(run.jobIdentity)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                }
            }
            Text("EVFEVENT does not contain a complete job log. Only unlocated compiler summary records are shown here; iTelAS does not invent missing cause or recovery text.")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.secondary)
                .lineSpacing(3)
            Rectangle().fill(AppPalette.border).frame(height: 1)
            ForEach(run.analysis.unlocatedDiagnostics) { diagnostic in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(diagnostic.messageID)
                        Text("SEV \(diagnostic.severity)")
                            .foregroundStyle(diagnostic.band.color)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    Text(diagnostic.message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppPalette.text)
                }
            }
            if run.analysis.unlocatedDiagnostics.isEmpty {
                Text("No unlocated summary records were retained.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
        }
        .padding(16)
    }

    private func commandSurface(_ run: CompileRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("EXACT RETAINED COMMAND")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.muted)
            Text(run.recipe.commandPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppPalette.terminalGreen)
                .textSelection(.enabled)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.terminal, in: ChamferedRectangle(cut: 4))
            Label("Preview only · iTelAS did not execute this command", systemImage: "hand.raised.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppPalette.success)
            Text("A future compile connector must bind the command to an explicit non-production target, reviewed library list, source revision, and event-file collection plan.")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.secondary)
                .lineSpacing(3)
            Spacer()
        }
        .padding(16)
    }

    private func diagnosticDossier(_ run: CompileRunRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    CompileEvidenceLoomMark(size: 31)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DIAGNOSTIC DOSSIER")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(AppPalette.muted)
                        Text("Why this needs attention")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppPalette.text)
                    }
                }
                Rectangle().fill(AppPalette.border).frame(height: 1)

                if let diagnostic = model.selectedCompileDiagnostic ?? run.analysis.primaryDiagnostic {
                    HStack {
                        Text("TRIAGE CONFIDENCE")
                        Spacer()
                        Text(run.analysis.confidence.label)
                            .foregroundStyle(confidenceColor(run.analysis.confidence))
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))

                    CompileDossierSection(
                        label: diagnostic.id == run.analysis.primaryDiagnostic?.id ? "FIRST ACTIONABLE" : "SELECTED EVIDENCE",
                        title: "\(diagnostic.messageID) · severity \(diagnostic.severity)",
                        detail: diagnostic.message,
                        color: diagnostic.band.color
                    )
                    CompileDossierSection(
                        label: "EXACT LOCATION",
                        title: diagnostic.filePath ?? "File identity unresolved",
                        detail: diagnostic.startLine > 0
                            ? "Lines \(diagnostic.startLine)–\(diagnostic.endLine), columns \(diagnostic.startColumn)–\(diagnostic.endColumn)"
                            : "This record carries no source line.",
                        color: AppPalette.ibmBlue
                    )
                    CompileDossierSection(
                        label: "RANKING CONTRACT",
                        title: "Inference is visibly labeled",
                        detail: run.analysis.selectionBasis,
                        color: AppPalette.warning
                    )
                } else {
                    CompileDossierSection(
                        label: "EVIDENCE STATE",
                        title: "No diagnostic records",
                        detail: "The event evidence remains available for identity and build-history review.",
                        color: AppPalette.success
                    )
                }

                Rectangle().fill(AppPalette.border).frame(height: 1)
                Text("PINNED EVIDENCE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.muted)
                CompileFact(label: "EVENT FILE", value: run.recipe.eventFileIdentity)
                CompileFact(label: "JOB", value: run.jobIdentity)
                CompileFact(label: "EVIDENCE SHA-256", value: run.evidence.fingerprint.uppercased())
                CompileFact(label: "SOURCE REVISION", value: run.sourceRevision?.uppercased() ?? "NOT ATTACHED")

                if run.evidence.hasExpansionMappings {
                    Label(
                        "EXPANSION records detected. Generated-line remapping is not implemented in this milestone.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.warning)
                    .padding(10)
                    .background(AppPalette.warning.opacity(0.08), in: ChamferedRectangle(cut: 3))
                }

                Button {
                    model.prepareCompileAssist()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            UtilityGlyph(kind: .contextShelf, color: .white, size: 14)
                            Text("Pin diagnosis to Assist Shelf")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        Text("Exact evidence · local until send")
                            .font(.system(size: 8, design: .monospaced))
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PrimaryButtonStyle())

                Text("Assist cannot compile, save, upload, or execute. Pinned evidence stays local until you send or clear it.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.muted)
                    .lineSpacing(2)
            }
            .padding(14)
        }
        .background(AppPalette.panel)
    }

    private func evidenceTimeline(_ run: CompileRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EVIDENCE CHAIN")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.muted)
                    Text("Chronological records; causal ranking remains explicit inference")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                }
                Spacer()
                Text(run.origin.detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CompileTimelineStep(
                        index: "01",
                        title: "Evidence loaded",
                        detail: "\(run.evidence.recordCount) bounded records",
                        color: AppPalette.ibmBlue,
                        isSelected: false
                    )
                    ForEach(Array(run.evidence.diagnostics.prefix(5).enumerated()), id: \.element.id) { index, diagnostic in
                        Rectangle().fill(AppPalette.borderStrong).frame(width: 18, height: 1)
                        Button {
                            model.selectCompileDiagnostic(diagnostic.id)
                            selectedSurface = .source
                        } label: {
                            CompileTimelineStep(
                                index: String(format: "%02d", index + 2),
                                title: diagnostic.messageID,
                                detail: diagnostic.startLine > 0
                                    ? "Line \(diagnostic.startLine) · severity \(diagnostic.severity)"
                                    : "Summary · severity \(diagnostic.severity)",
                                color: diagnostic.band.color,
                                isSelected: diagnostic.id == model.selectedCompileDiagnosticID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Rectangle().fill(AppPalette.borderStrong).frame(width: 18, height: 1)
                    CompileTimelineStep(
                        index: String(format: "%02d", min(99, run.evidence.diagnostics.count + 2)),
                        title: run.outcome.label,
                        detail: run.objectWasChanged.map { $0 ? "Object changed" : "Object unchanged" } ?? "Object state not asserted",
                        color: outcomeColor(run.outcome),
                        isSelected: false
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(AppPalette.window)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 17) {
            Text("EVIDENCE: \(model.selectedCompileRun?.origin.label ?? "NONE")")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("REMOTE EXECUTION: NOT WIRED")
                .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.45))
            Text("HOST WRITE: NONE")
            if let diagnostic = model.compileImportDiagnostic {
                Text(diagnostic)
                    .lineLimit(1)
                    .foregroundStyle(AppPalette.warning)
            }
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("ARM64 · NATIVE")
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }

    private func sourceExcerpt(_ source: String, run: CompileRunRecord) -> [CompileSourceLine] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return [] }
        let focus = model.selectedCompileDiagnostic?.startLine
            ?? run.analysis.primaryDiagnostic?.startLine
            ?? 1
        let lower = max(1, focus - 9)
        let upper = min(lines.count, focus + 11)
        guard lower <= upper else { return [] }
        return (lower...upper).map { CompileSourceLine(number: $0, text: lines[$0 - 1]) }
    }

    private func diagnosticLocation(_ diagnostic: CompileDiagnostic) -> String {
        let identity = diagnostic.filePath ?? "file-id \(diagnostic.fileIdentifier)"
        guard diagnostic.startLine > 0 else { return "\(identity) · no source line" }
        return "\(identity) · \(diagnostic.startLine):\(diagnostic.startColumn)"
    }

    private func importEvidence(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            model.compileImportDiagnostic = error.localizedDescription
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = values.fileSize,
                   fileSize > CompileEvidenceLimits.standard.maximumUTF8Bytes {
                    throw CompileEvidenceError.inputTooLarge(
                        maximum: CompileEvidenceLimits.standard.maximumUTF8Bytes
                    )
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                model.importCompileEvidence(data, fileName: url.lastPathComponent)
            } catch {
                model.compileImportDiagnostic = error.localizedDescription
                model.showNotice("Compile evidence import was blocked.")
            }
        }
    }

    private func outcomeColor(_ outcome: CompileRunOutcome) -> Color {
        switch outcome {
        case .passed: AppPalette.success
        case .failed: AppPalette.danger
        case .evidenceOnly: AppPalette.ibmBlue
        }
    }

    private func confidenceColor(_ confidence: CompileEvidenceConfidence) -> Color {
        switch confidence {
        case .high: AppPalette.success
        case .medium: AppPalette.warning
        case .low: AppPalette.muted
        }
    }
}

private struct CompileRecipeHeaderGlyph: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            var first = Path()
            first.move(to: CGPoint(x: 1, y: 2))
            first.addLine(to: CGPoint(x: canvasSize.width * 0.42, y: 2))
            first.addLine(to: CGPoint(x: canvasSize.width * 0.42, y: canvasSize.height * 0.52))
            first.addLine(to: CGPoint(x: canvasSize.width - 1, y: canvasSize.height * 0.52))
            context.stroke(first, with: .color(AppPalette.registrationBlue), lineWidth: 1.4)

            var second = Path()
            second.move(to: CGPoint(x: 1, y: canvasSize.height - 2))
            second.addLine(to: CGPoint(x: canvasSize.width * 0.3, y: canvasSize.height - 2))
            second.addLine(to: CGPoint(x: canvasSize.width * 0.3, y: canvasSize.height * 0.72))
            second.addLine(to: CGPoint(x: canvasSize.width * 0.72, y: canvasSize.height * 0.72))
            second.addLine(to: CGPoint(x: canvasSize.width * 0.72, y: 1))
            second.addLine(to: CGPoint(x: canvasSize.width - 1, y: 1))
            context.stroke(second, with: .color(AppPalette.success), lineWidth: 1.4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum CompileEvidenceSurface: String, CaseIterable, Identifiable {
    case source
    case eventFile
    case jobLog
    case command

    var id: Self { self }

    func label(run: CompileRunRecord) -> String {
        switch self {
        case .source: "SOURCE"
        case .eventFile: "EVENT FILE · \(run.evidence.diagnostics.count)"
        case .jobLog: "JOB LOG · \(run.analysis.unlocatedDiagnostics.count)"
        case .command: "COMMAND · 1"
        }
    }
}

private struct CompileSourceLine: Identifiable {
    let number: Int
    let text: String
    var id: Int { number }
}

private struct CompileRunLedgerRow: View {
    let run: CompileRunRecord
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(run.startedAtLabel)
                        .foregroundStyle(isSelected ? AppPalette.ibmBlue : AppPalette.muted)
                    Spacer()
                    Text(run.outcome.label)
                        .foregroundStyle(outcomeColor)
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                Text("\(run.displaySequence) · \(run.objectName)")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("\(run.durationLabel) · \(run.evidence.diagnostics.count) diagnostics")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppPalette.ibmBlue.opacity(0.07) : AppPalette.panel)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? AppPalette.ibmBlue : Color.clear)
                    .frame(width: 3)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var outcomeColor: Color {
        switch run.outcome {
        case .passed: AppPalette.success
        case .failed: AppPalette.danger
        case .evidenceOnly: AppPalette.ibmBlue
        }
    }
}

private struct CompileFact: View {
    let label: String
    let value: String
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

private struct CompileGateRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(AppPalette.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(color)
        }
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
    }
}

private struct CompileDossierSection: View {
    let label: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(AppPalette.text)
                .textSelection(.enabled)
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(AppPalette.secondary)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
    }
}

private struct CompileTimelineStep: View {
    let index: String
    let title: String
    let detail: String
    let color: Color
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white : color)
                .frame(width: 22, height: 22)
                .background(isSelected ? color : AppPalette.panel)
                .overlay {
                    Rectangle().stroke(color, lineWidth: 0.8)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text(detail)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .frame(width: 166, height: 56, alignment: .topLeading)
        .background(isSelected ? color.opacity(0.07) : AppPalette.panel)
        .overlay {
            Rectangle().stroke(isSelected ? color : AppPalette.border, lineWidth: 0.8)
        }
    }
}

private struct CompileEvidenceLoomMark: View {
    var size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let width = canvas.width
            let height = canvas.height
            var upper = Path()
            upper.move(to: CGPoint(x: width * 0.16, y: height * 0.24))
            upper.addLine(to: CGPoint(x: width * 0.34, y: height * 0.24))
            upper.addLine(to: CGPoint(x: width * 0.48, y: height * 0.46))
            upper.addLine(to: CGPoint(x: width * 0.68, y: height * 0.46))
            upper.addLine(to: CGPoint(x: width * 0.82, y: height * 0.62))
            context.stroke(
                upper,
                with: .color(Color(red: 0.47, green: 0.66, blue: 1)),
                style: StrokeStyle(lineWidth: max(1.2, width * 0.045), lineCap: .square)
            )
            var lower = Path()
            lower.move(to: CGPoint(x: width * 0.16, y: height * 0.76))
            lower.addLine(to: CGPoint(x: width * 0.34, y: height * 0.76))
            lower.addLine(to: CGPoint(x: width * 0.48, y: height * 0.54))
            lower.addLine(to: CGPoint(x: width * 0.68, y: height * 0.54))
            lower.addLine(to: CGPoint(x: width * 0.82, y: height * 0.38))
            context.stroke(
                lower,
                with: .color(AppPalette.terminalGreen),
                style: StrokeStyle(lineWidth: max(1.2, width * 0.045), lineCap: .square)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: width * 0.43, y: height * 0.43, width: width * 0.14, height: height * 0.14)),
                with: .color(AppPalette.danger)
            )
        }
        .frame(width: size, height: size)
        .padding(3)
        .background(AppPalette.terminal, in: ChamferedRectangle(cut: 4))
        .overlay {
            ChamferedRectangle(cut: 4).stroke(AppPalette.borderStrong, lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }
}

private struct DiagnosticPulseMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            var ring = Path()
            ring.addEllipse(in: CGRect(
                x: center.x - canvas.width * 0.34,
                y: center.y - canvas.height * 0.34,
                width: canvas.width * 0.68,
                height: canvas.height * 0.68
            ))
            context.stroke(ring, with: .color(color.opacity(0.45)), lineWidth: 1)
            var pulse = Path()
            pulse.move(to: CGPoint(x: canvas.width * 0.12, y: center.y))
            pulse.addLine(to: CGPoint(x: canvas.width * 0.35, y: center.y))
            pulse.addLine(to: CGPoint(x: canvas.width * 0.44, y: canvas.height * 0.28))
            pulse.addLine(to: CGPoint(x: canvas.width * 0.57, y: canvas.height * 0.72))
            pulse.addLine(to: CGPoint(x: canvas.width * 0.66, y: center.y))
            pulse.addLine(to: CGPoint(x: canvas.width * 0.88, y: center.y))
            context.stroke(
                pulse,
                with: .color(color),
                style: StrokeStyle(lineWidth: max(1.1, canvas.width * 0.075), lineCap: .square, lineJoin: .miter)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension CompileDiagnosticBand {
    var color: Color {
        switch self {
        case .information: AppPalette.muted
        case .warning: AppPalette.warning
        case .error: Color(red: 0.93, green: 0.45, blue: 0.18)
        case .severe, .terminal: AppPalette.danger
        }
    }
}
