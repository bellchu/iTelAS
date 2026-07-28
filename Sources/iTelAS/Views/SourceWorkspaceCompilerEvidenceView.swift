import SwiftUI
import iTelASCore

struct SourceWorkspaceCompilerEvidenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var observedReleaseDraft = ""
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            custodyBand
            HStack(spacing: 0) {
                compileRunRail
                    .frame(width: 252)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                mappingStage
                Rectangle().fill(AppPalette.border).frame(width: 1)
                attachmentGate
                    .frame(width: 326)
            }
            footer
        }
        .background(AppPalette.window)
        .onAppear {
            observedReleaseDraft = model.sourceWorkspaceCompileObservedRelease
            proverb = .random(excluding: proverb.id)
        }
        .onChange(of: observedReleaseDraft) { _, value in
            guard value != model.sourceWorkspaceCompileObservedRelease else { return }
            model.updateSourceWorkspaceCompileObservedRelease(value)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CompilerBridgeRouteMark()
                .frame(width: 42, height: 42)
            BrandWordmark(compact: true)
                .frame(width: 150, alignment: .leading)
            Rectangle().fill(AppPalette.borderStrong).frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("COMPILER EVIDENCE BRIDGE")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Map EVFEVENT to the exact indexed source")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            CompilerBridgeBadge(label: "LOCAL EVIDENCE", color: AppPalette.success)
            CompilerBridgeBadge(
                label: releaseEvidence?.effectiveTargetLabel ?? "RELEASE UNRESOLVED",
                color: releaseEvidence?.resolution == .exact ? AppPalette.ibmBlue : AppPalette.warning
            )
            Button("Close") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var custodyBand: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SELECTED COMPILE RUN")
                    .compilerBridgeEyebrow(color: AppPalette.terminalGreen)
                Text("\(run?.displaySequence ?? "—") · \(run?.objectName ?? "NO RUN")")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Text(run.map {
                    "\($0.origin.label) · \($0.outcome.label) · SEV \($0.evidence.maximumSeverity)"
                } ?? "Choose retained evidence")
                    .font(.system(size: 7.2, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(width: 240, alignment: .leading)
            CompilerEvidenceRouteDiagram(
                indexValue: model.sourceWorkspaceIndex.shortFingerprint,
                mappingValue: review?.mappings.isEmpty == false ? "EXACT" : "GAP",
                diagnosticValue: String(review?.diagnostics.count ?? 0)
            )
            .frame(width: 390, height: 56)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("EVIDENCE RECEIPT")
                    .compilerBridgeEyebrow(color: AppPalette.registrationBlue)
                Text("INDEX \(model.sourceWorkspaceIndex.shortFingerprint) · EVENT \(run.map { String($0.evidence.fingerprint.prefix(10)).uppercased() } ?? "—")")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("No compile · no host contact · no Assist send")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 290, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(AppPalette.terminal)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
    }

    private var compileRunRail: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EVIDENCE LEDGER / \(model.compileRuns.count)")
                        .compilerBridgeEyebrow(color: AppPalette.ibmBlue)
                    Text("Compile runs")
                        .font(.system(size: 17, weight: .bold))
                }
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(height: 64)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ForEach(model.compileRuns.prefix(3)) { compileRun in
                Button {
                    model.selectSourceWorkspaceCompileRun(compileRun.id)
                    observedReleaseDraft = model.sourceWorkspaceCompileObservedRelease
                } label: {
                    CompilerRunMappingRow(
                        run: compileRun,
                        selected: compileRun.id == model.sourceWorkspaceCompileRunID
                    )
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("TARGET-RELEASE CONTEXT")
                        .compilerBridgeEyebrow(color: AppPalette.ibmBlue)
                    Spacer()
                    Text(releaseEvidence?.resolution.label ?? "INVALID")
                        .compilerBridgeEyebrow(color: releaseEvidence?.resolution == .exact ? AppPalette.success : AppPalette.warning)
                }
                CompilerReleaseFact(label: "COMMAND TOKEN", value: releaseEvidence?.commandToken.label ?? "UNAVAILABLE")
                HStack {
                    Text("OBSERVED HOST")
                        .compilerBridgeEyebrow(color: AppPalette.muted)
                    Spacer()
                    TextField("V7R6M0", text: $observedReleaseDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 82)
                        .padding(.horizontal, 7)
                        .frame(height: 25)
                        .background(AppPalette.panel)
                        .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
                }
                CompilerReleaseFact(label: "EFFECTIVE TARGET", value: releaseEvidence?.effectiveTargetLabel ?? "UNRESOLVED")
                Rectangle().fill(AppPalette.border).frame(height: 1)
                Text("Release context identifies the retained target. It does not prove this source compiles on that release.")
                    .font(.system(size: 8.2))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppPalette.window)
        }
        .background(AppPalette.panel)
    }

    private var mappingStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CompilerFileMappingMark()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ONE SOURCE IDENTITY · ONE INDEX DOCUMENT")
                        .compilerBridgeEyebrow(color: AppPalette.ibmBlue)
                    Text("Exact file reconciliation")
                        .font(.system(size: 17, weight: .bold))
                }
                Spacer()
                CompilerBridgeBadge(
                    label: primaryMapping?.revisionState.label ?? "NO MAPPING",
                    color: primaryMapping?.revisionState == .exact ? AppPalette.success : AppPalette.warning
                )
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            mappingRoute

            HStack(spacing: 10) {
                Rectangle()
                    .fill(primaryMapping?.revisionState == .exact ? AppPalette.success : AppPalette.warning)
                    .frame(width: 4, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryMapping?.revisionState == .exact
                         ? "SOURCE SNAPSHOT MATCHES RETAINED COMPILE REVISION"
                         : "SOURCE REVISION IS NOT AN EXACT RETAINED MATCH")
                        .compilerBridgeEyebrow(color: primaryMapping?.revisionState == .exact ? AppPalette.success : AppPalette.warning)
                    Text(primaryMapping?.revisionState == .exact
                         ? "Diagnostics may navigate. Any index or evidence change makes this attachment stale."
                         : "Diagnostics remain visible, but navigation stays blocked until exact source-revision evidence exists.")
                        .font(.system(size: 8.4))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                Text(primaryMapping?.shortFingerprint ?? "NO RECEIPT")
                    .compilerBridgeEyebrow(color: primaryMapping?.revisionState == .exact ? AppPalette.success : AppPalette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background((primaryMapping?.revisionState == .exact ? AppPalette.success : AppPalette.warning).opacity(0.08))
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack {
                Text("MAPPED COMPILER DIAGNOSTICS")
                    .compilerBridgeEyebrow(color: AppPalette.text)
                Spacer()
                Text("\(displayEvidence?.exactNavigationCount ?? 0) EXACT · \(displayEvidence?.blockedNavigationCount ?? 0) BLOCKED · \(displayEvidence?.unlinkedDiagnosticCount ?? 0) UNLINKED")
                    .compilerBridgeEyebrow(color: AppPalette.ibmBlue)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayEvidence?.diagnostics ?? []) { diagnostic in
                        CompilerMappedDiagnosticRow(
                            diagnostic: diagnostic,
                            selected: diagnostic.id == model.selectedSourceWorkspaceCompileDiagnosticID,
                            attachmentCurrent: model.sourceWorkspaceCompileAttachmentIsCurrent
                        ) {
                            model.selectedSourceWorkspaceCompileDiagnosticID = diagnostic.id
                        } open: {
                            model.openSourceWorkspaceCompileDiagnostic(diagnostic.id)
                        }
                    }
                    if displayEvidence?.diagnostics.isEmpty != false {
                        ContentUnavailableView(
                            "No mapped diagnostics",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("Choose one exact compile-file to indexed-document mapping.")
                        )
                        .padding(.top, 30)
                    }
                }
            }
            .background(AppPalette.panel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mappingRoute: some View {
        VStack(spacing: 0) {
            if let run, let file = run.evidence.sourceFiles.first {
                let fileID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: file)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EVFEVENT FILEID · \(file.fileIdentifier)")
                            .compilerBridgeEyebrow(color: AppPalette.danger)
                        Text(file.path)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .lineLimit(2)
                        Text("\(run.evidence.diagnostics.filter { $0.filePath == file.path }.count) retained diagnostics · processor \(file.processorSequence)")
                            .font(.system(size: 8.1))
                            .foregroundStyle(AppPalette.secondary)
                    }
                    .padding(11)
                    .frame(width: 220, height: 112, alignment: .topLeading)
                    .background(AppPalette.window)
                    .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }

                    VStack(spacing: 5) {
                        Text("······›")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.registrationBlue)
                        Text(primaryMapping?.basis.label ?? "REVIEW")
                            .font(.system(size: 6.4, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    .frame(width: 72)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("INDEX DOCUMENT")
                                .compilerBridgeEyebrow(color: AppPalette.ibmBlue)
                            Spacer()
                            Text(primaryMapping?.revisionState.label ?? "SELECT")
                                .compilerBridgeEyebrow(color: primaryMapping?.revisionState == .exact ? AppPalette.success : AppPalette.warning)
                        }
                        Picker("Indexed document", selection: Binding(
                            get: { model.sourceWorkspaceCompileMappings[fileID] ?? "" },
                            set: { model.selectSourceWorkspaceCompileMapping(compileFileID: fileID, documentPath: $0) }
                        )) {
                            Text("Choose document").tag("")
                            ForEach(model.sourceWorkspaceIndex.documents) { document in
                                Text("\(document.relativePath) · \(document.origin.label)").tag(document.relativePath)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        Text(primaryMapping.map {
                            "SHA-256 \($0.documentFingerprint.prefix(12).uppercased()) · \(model.sourceWorkspaceIndex.document(at: $0.documentPath)?.lineCount ?? 0) lines"
                        } ?? "Choose one current indexed document. A suggested base-name match still requires review.")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                            .lineLimit(2)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .background(AppPalette.selection)
                    .overlay { Rectangle().stroke(AppPalette.ibmBlue, lineWidth: 1) }
                }
                .padding(14)
            } else {
                ContentUnavailableView("No compile source identity", systemImage: "doc.badge.ellipsis")
            }
        }
        .frame(height: 148)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var attachmentGate: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CompilerAttachmentShieldMark()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOCAL ATTACHMENT GATE")
                        .compilerBridgeEyebrow(color: AppPalette.success)
                    Text("Review & attach")
                        .font(.system(size: 17, weight: .bold))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 72)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("FROZEN ATTACHMENT")
                        .compilerBridgeEyebrow(color: AppPalette.ibmBlue)
                    Spacer()
                    Text(model.sourceWorkspaceCompileStatusLabel)
                        .compilerBridgeEyebrow(color: model.sourceWorkspaceCompileAttachmentIsCurrent ? AppPalette.success : AppPalette.warning)
                }
                CompilerReleaseFact(label: "INDEX", value: model.sourceWorkspaceIndex.shortFingerprint)
                CompilerReleaseFact(label: "EVIDENCE", value: run?.shortFingerprint ?? "—")
                CompilerReleaseFact(label: "REVIEW", value: review?.shortFingerprint ?? "NOT RECORDED")
            }
            .padding(12)
            .frame(height: 91, alignment: .top)
            .background(AppPalette.window)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TARGET RELEASE")
                        .compilerBridgeEyebrow(color: AppPalette.ibmBlue)
                    Spacer()
                    Text(releaseEvidence?.effectiveTargetLabel ?? "UNRESOLVED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                }
                Text("\(releaseEvidence?.commandToken.label ?? "No TGTRLS token") · observed host \(releaseEvidence?.observedHostRelease?.value ?? "not recorded")")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
                Text("Context only — not a language compatibility verdict.")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppPalette.warning)
            }
            .padding(12)
            .frame(height: 84, alignment: .top)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 7) {
                Text("EVIDENCE BOUNDARIES")
                    .compilerBridgeEyebrow(color: AppPalette.danger)
                CompilerEvidenceBoundary(number: "01", text: "EXPANSION lines are not remapped.", color: AppPalette.warning)
                CompilerEvidenceBoundary(number: "02", text: "EVFEVENT is not a complete job log.", color: AppPalette.warning)
                CompilerEvidenceBoundary(number: "03", text: "No compile, provider, or host action.", color: AppPalette.success)
            }
            .padding(12)
            .frame(height: 124, alignment: .top)
            .background(AppPalette.window)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            Toggle(isOn: Binding(
                get: { model.sourceWorkspaceCompileAttested },
                set: { model.sourceWorkspaceCompileAttested = $0 }
            )) {
                Text("I reviewed the exact file mapping, source revision, and target-release context.")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .padding(12)
            .frame(height: 72, alignment: .top)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 8) {
                Button(model.sourceWorkspaceCompileAttachmentIsCurrent ? "Reattach Current Evidence" : "Attach Evidence Locally") {
                    model.attachReviewedSourceWorkspaceCompileEvidence()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.sourceWorkspaceCompileCanAttach)
                .opacity(model.sourceWorkspaceCompileCanAttach ? 1 : 0.42)
                if model.sourceWorkspaceCompileAttachment != nil {
                    Button("Remove Attachment") { model.removeSourceWorkspaceCompileEvidenceAttachment() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Text(model.sourceWorkspaceCompileDiagnostic)
                    .font(.system(size: 7.8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("NOTHING EXECUTES · NOTHING LEAVES THIS MAC")
                    .compilerBridgeEyebrow(color: AppPalette.success)
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppPalette.window)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("INDEX: \(model.sourceWorkspaceIndexPhase.label) · \(model.sourceWorkspaceIndex.localFileCount) LOCAL · \(model.sourceWorkspaceIndex.hostIncludeFileCount) HOST")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("EVIDENCE: \(model.sourceWorkspaceCompileStatusLabel) · \(displayEvidence?.exactNavigationCount ?? 0) EXACT")
                .foregroundStyle(Color(red: 0.92, green: 0.64, blue: 0.32))
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .italic()
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Text("ARM64 · LOCAL EVIDENCE")
                .foregroundStyle(.white)
        }
        .font(.system(size: 6.8, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(AppPalette.terminal)
    }

    private var run: CompileRunRecord? { model.selectedSourceWorkspaceCompileRun }

    private var releaseEvidence: CompileTargetReleaseEvidence? {
        guard let run else { return nil }
        return try? CompileTargetReleaseEvidence(
            commandText: "\(run.recipe.compiler)\n\(run.recipe.commandPreview)",
            observedHostRelease: model.sourceWorkspaceCompileObservedRelease
        )
    }

    private var review: ReviewedSourceWorkspaceCompileEvidence? {
        model.sourceWorkspaceCompileReview
    }

    private var displayEvidence: ReviewedSourceWorkspaceCompileEvidence? {
        model.sourceWorkspaceCompileAttachmentIsCurrent
            ? model.sourceWorkspaceCompileAttachment
            : model.sourceWorkspaceCompileReview
    }

    private var primaryMapping: SourceWorkspaceCompileFileMapping? {
        displayEvidence?.mappings.first
    }
}

private struct CompilerRunMappingRow: View {
    let run: CompileRunRecord
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(outcomeColor)
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(run.displaySequence)
                        .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.secondary)
                    Spacer()
                    Text(run.objectName)
                        .foregroundStyle(AppPalette.text)
                }
                .font(.system(size: 8.3, weight: .bold, design: .monospaced))
                Text("\(run.startedAtLabel) · \(run.outcome.label) · SEV \(run.evidence.maximumSeverity)")
                    .font(.system(size: 6.6, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 70)
        .background(selected ? AppPalette.selection : AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var outcomeColor: Color {
        switch run.outcome {
        case .passed: AppPalette.success
        case .failed: run.evidence.maximumSeverity >= 30 ? AppPalette.danger : AppPalette.warning
        case .evidenceOnly: AppPalette.registrationBlue
        }
    }
}

private struct CompilerMappedDiagnosticRow: View {
    let diagnostic: SourceWorkspaceCompileDiagnosticLink
    let selected: Bool
    let attachmentCurrent: Bool
    let select: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(color).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.messageID)
                    .foregroundStyle(color)
                Text("SEV \(diagnostic.severity)")
                    .foregroundStyle(AppPalette.muted)
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("LINE")
                    .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                Text("\(diagnostic.range.startLine):\(diagnostic.range.startColumn)")
                    .font(.system(size: 7.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.message)
                    .font(.system(size: 8.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(2)
                Text(diagnostic.navigationState.label)
                    .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                    .foregroundStyle(diagnostic.canNavigate ? AppPalette.success : AppPalette.warning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionLabel, action: open)
                .buttonStyle(SecondaryButtonStyle())
                .controlSize(.mini)
                .disabled(!attachmentCurrent || !diagnostic.canNavigate)
                .opacity(attachmentCurrent && diagnostic.canNavigate ? 1 : 0.58)
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(selected ? color.opacity(0.07) : AppPalette.panel)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var color: Color {
        switch diagnostic.severity {
        case 30...: AppPalette.danger
        case 20...: Color(red: 0.91, green: 0.38, blue: 0.12)
        case 10...: AppPalette.warning
        default: AppPalette.registrationBlue
        }
    }

    private var actionLabel: String {
        if !diagnostic.canNavigate { return "Evidence only" }
        return attachmentCurrent ? "Open" : "Attach first"
    }
}

private struct CompilerReleaseFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .compilerBridgeEyebrow(color: AppPalette.muted)
            Spacer()
            Text(value)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
        }
    }
}

private struct CompilerEvidenceBoundary: View {
    let number: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .overlay { Rectangle().stroke(color, lineWidth: 1) }
            Text(text)
                .font(.system(size: 8.1))
                .foregroundStyle(AppPalette.secondary)
            Spacer()
        }
    }
}

private struct CompilerBridgeBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 6.9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(color.opacity(0.08))
            .overlay { Rectangle().stroke(color.opacity(0.75), lineWidth: 1) }
    }
}

private struct CompilerBridgeRouteMark: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(AppPalette.terminal))
            context.stroke(Path(bounds), with: .color(AppPalette.ibmBlue), lineWidth: 1)
            var route = Path()
            route.move(to: CGPoint(x: size.width * 0.17, y: size.height * 0.77))
            route.addLine(to: CGPoint(x: size.width * 0.37, y: size.height * 0.55))
            route.addLine(to: CGPoint(x: size.width * 0.37, y: size.height * 0.25))
            route.addLine(to: CGPoint(x: size.width * 0.58, y: size.height * 0.25))
            route.addLine(to: CGPoint(x: size.width * 0.58, y: size.height * 0.55))
            route.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.77))
            context.stroke(route, with: .color(AppPalette.terminalGreen), lineWidth: 2)
            var pulse = Path()
            pulse.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.48))
            pulse.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.48))
            pulse.addLine(to: CGPoint(x: size.width * 0.43, y: size.height * 0.34))
            pulse.addLine(to: CGPoint(x: size.width * 0.52, y: size.height * 0.66))
            pulse.addLine(to: CGPoint(x: size.width * 0.61, y: size.height * 0.48))
            pulse.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.48))
            context.stroke(pulse, with: .color(AppPalette.registrationBlue), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

private struct CompilerFileMappingMark: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(AppPalette.terminal))
            context.stroke(Path(bounds), with: .color(AppPalette.registrationBlue), lineWidth: 1)
            let left = CGRect(x: 6, y: 7, width: 9, height: size.height - 14)
            let right = CGRect(x: size.width - 15, y: 7, width: 9, height: size.height - 14)
            context.stroke(Path(left), with: .color(.white), lineWidth: 1)
            context.stroke(Path(right), with: .color(AppPalette.terminalGreen), lineWidth: 1)
            var bridge = Path()
            bridge.move(to: CGPoint(x: 14, y: size.height / 2))
            bridge.addLine(to: CGPoint(x: size.width - 13, y: size.height / 2))
            bridge.addLine(to: CGPoint(x: size.width - 17, y: size.height / 2 - 4))
            bridge.move(to: CGPoint(x: size.width - 13, y: size.height / 2))
            bridge.addLine(to: CGPoint(x: size.width - 17, y: size.height / 2 + 4))
            context.stroke(bridge, with: .color(AppPalette.registrationBlue), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

private struct CompilerAttachmentShieldMark: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(AppPalette.terminal))
            context.stroke(Path(bounds), with: .color(AppPalette.success), lineWidth: 1)
            var shield = Path()
            shield.move(to: CGPoint(x: size.width / 2, y: 5))
            shield.addLine(to: CGPoint(x: size.width - 8, y: 10))
            shield.addLine(to: CGPoint(x: size.width - 10, y: size.height - 12))
            shield.addLine(to: CGPoint(x: size.width / 2, y: size.height - 5))
            shield.addLine(to: CGPoint(x: 10, y: size.height - 12))
            shield.addLine(to: CGPoint(x: 8, y: 10))
            shield.closeSubpath()
            context.stroke(shield, with: .color(AppPalette.terminalGreen), lineWidth: 1.4)
            var mark = Path()
            mark.move(to: CGPoint(x: 13, y: 24))
            mark.addLine(to: CGPoint(x: 18, y: 19))
            mark.addLine(to: CGPoint(x: 23, y: 24))
            mark.addLine(to: CGPoint(x: 29, y: 14))
            context.stroke(mark, with: .color(AppPalette.registrationBlue), lineWidth: 1.6)
        }
        .accessibilityHidden(true)
    }
}

private struct CompilerEvidenceRouteDiagram: View {
    let indexValue: String
    let mappingValue: String
    let diagnosticValue: String

    var body: some View {
        HStack(spacing: 8) {
            routeNode(label: "INDEX", value: indexValue, color: AppPalette.registrationBlue)
            connector
            routeNode(label: "REVIEW", value: mappingValue, color: AppPalette.warning)
            connector
            routeNode(label: "EVFEVENT", value: "\(diagnosticValue) LINKED", color: AppPalette.terminalGreen)
        }
    }

    private func routeNode(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(width: 104, height: 44)
        .background(AppPalette.terminalRaised)
        .overlay { Rectangle().stroke(color, lineWidth: 1) }
    }

    private var connector: some View {
        Text("···›")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.28))
    }
}

private extension View {
    func compilerBridgeEyebrow(color: Color) -> some View {
        font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(color)
    }
}
