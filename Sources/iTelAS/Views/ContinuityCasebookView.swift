import SwiftUI
import UniformTypeIdentifiers
import iTelASCore

struct ContinuityCasebookView: View {
    @Environment(AppModel.self) private var model
    @State private var timelineFilter: ContinuityTimelineFilter = .all
    @State private var editingCase: ContinuityCase?

    var body: some View {
        @Bindable var model = model

        GeometryReader { geometry in
            let leftWidth = min(286, max(230, geometry.size.width * 0.215))
            let rightWidth = min(400, max(310, geometry.size.width * 0.285))

            VStack(spacing: 0) {
                header

                HStack(spacing: 0) {
                    caseRail
                        .frame(width: leftWidth)
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    continuityWorkspace
                        .frame(maxWidth: .infinity)
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    custodyColumn
                        .frame(width: rightWidth)
                }

                footer
            }
            .background(AppPalette.window)
        }
        .fileImporter(
            isPresented: $model.isContinuityReferenceImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.importContinuityReference(at: url) }
            case .failure(let error):
                model.continuityCasebookDiagnostic = "Reference selection failed: \(error.localizedDescription)"
            }
        }
        .sheet(item: $editingCase) { continuityCase in
            ContinuityCaseEditorView(continuityCase: continuityCase)
                .environment(model)
                .frame(width: 720, height: 670)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ContinuityRelayMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("iTelAS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("CONTINUITY CASEBOOK · HANDOFF + ASSIST LEDGER")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            Spacer(minLength: 8)

            if let continuityCase = model.selectedContinuityCase {
                casebookBadge(
                    "\(continuityCase.code) · \(continuityCase.phase.label.uppercased())",
                    color: model.continuityCasebookUsesReplay ? AppPalette.warning : AppPalette.ibmBlue
                )
                casebookBadge(
                    "\(continuityCase.artifacts.count) ARTIFACTS · \(continuityCase.answers.count) ANSWERS",
                    color: AppPalette.success
                )
            }

            Button {
                model.isContinuityReferenceImporterPresented = true
            } label: {
                Text("IMPORT REFERENCE")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                model.createContinuityHandoffSnapshot()
            } label: {
                HStack(spacing: 7) {
                    ContinuityRelayMark(size: 15, framed: false)
                    Text("CREATE HANDOFF SNAPSHOT")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.continuityCasebookUsesReplay || model.selectedContinuityCase == nil)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var caseRail: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOCAL CASES")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Continuity queue")
                        .font(.system(size: 18, weight: .bold))
                    Text("Draft, snapshot, export, or reopen a bounded local handoff.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Menu {
                    ForEach(ContinuityCaseKind.allCases) { kind in
                        Button(kind.label) { model.createContinuityCase(kind: kind) }
                    }
                } label: {
                    Text("+")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.terminalGreen)
                        .frame(width: 31, height: 31)
                        .background(AppPalette.instrument)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Create a local continuity case")
            }
            .padding(15)
            .frame(height: 104)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.continuityCasebook.cases) { continuityCase in
                        CasebookCaseRow(
                            continuityCase: continuityCase,
                            selected: model.selectedContinuityCase?.id == continuityCase.id,
                            isReplay: model.continuityCasebookUsesReplay
                        ) {
                            model.selectContinuityCase(continuityCase.id)
                        }
                    }
                }
            }

            reviewedReferenceInbox
            localCustodySummary
        }
        .background(AppPalette.panel)
    }

    private var reviewedReferenceInbox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REVIEWED REFERENCE INBOX")
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .tracking(0.65)
                .foregroundStyle(AppPalette.ibmBlue)
            Text("Local source, chosen explicitly")
                .font(.system(size: 12, weight: .bold))

            if let references = model.selectedContinuityCase?.references, !references.isEmpty {
                ForEach(references.prefix(2)) { reference in
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(reference.kind == .runbook ? AppPalette.success : AppPalette.ibmBlue)
                            .frame(width: 3, height: 31)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reference.kind.label.uppercased())
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(reference.kind == .runbook ? AppPalette.success : AppPalette.ibmBlue)
                            Text(reference.title)
                                .font(.system(size: 8.2, weight: .semibold))
                                .lineLimit(1)
                            Text("\(reference.entries.count) ENTRIES · \(short(reference.fingerprint))")
                                .font(.system(size: 6.3, design: .monospaced))
                                .foregroundStyle(AppPalette.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 52)
                    .background(AppPalette.panel)
                    .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 0.7) }
                }
            } else {
                Text("No reviewed runbook or repository pack is attached.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }
        }
        .padding(13)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var localCustodySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOCAL CUSTODY")
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.ibmBlue)
            HStack(spacing: 1) {
                custodyMetric("\(model.continuityCasebook.cases.count)", "CASES")
                custodyMetric("\(model.continuityCasebook.snapshots.count)", "SNAPSHOTS")
                custodyMetric("0", "HOST OPS", color: AppPalette.success)
            }
            .background(AppPalette.border)
            Text(model.continuityCasebookUsesReplay
                 ? "BUNDLED REPLAY · CREATE OR CAPTURE TO PERSIST"
                 : "APPLICATION SUPPORT · MODE 0600 · NO AMBIENT CAPTURE")
                .font(.system(size: 6.2, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
        }
        .padding(13)
        .background(AppPalette.panel)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var continuityWorkspace: some View {
        VStack(spacing: 0) {
            if let continuityCase = model.selectedContinuityCase {
                activeCaseFocus(continuityCase)
                timelineHeader(continuityCase)
                timeline(continuityCase)
                openQuestions(continuityCase)
            } else {
                ContentUnavailableView(
                    "No continuity case",
                    systemImage: "tray",
                    description: Text("Create a local case or capture reviewed Context Shelf evidence.")
                )
            }
        }
        .background(AppPalette.window)
    }

    private func activeCaseFocus(_ continuityCase: ContinuityCase) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ACTIVE HANDOFF · \(continuityCase.environment.label)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.terminalGreen)
                Text(continuityCase.code)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(continuityCase.target.uppercased())
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
                    .lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                Text("DOMINANT QUESTION")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.56))
                Text(continuityCase.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(continuityCase.summary)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            readinessInstrument(continuityCase)
                .frame(width: 178)
        }
        .padding(.horizontal, 18)
        .frame(height: 116)
        .background(AppPalette.terminal)
    }

    private func readinessInstrument(_ continuityCase: ContinuityCase) -> some View {
        let total = 4
        let ready = total - continuityCase.readinessGaps.count
        return VStack(alignment: .leading, spacing: 5) {
            Text("HANDOFF READINESS")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.terminalGreen)
            Text("\(ready) / \(total) GATES")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(continuityCase.readinessGaps.isEmpty ? "READY SNAPSHOT" : "\(continuityCase.readinessGaps.count) OPEN")
                .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                .foregroundStyle(continuityCase.readinessGaps.isEmpty ? AppPalette.terminalGreen : Color(red: 0.91, green: 0.66, blue: 0.45))
        }
        .padding(12)
        .frame(height: 74, alignment: .leading)
        .background(AppPalette.terminalRaised)
        .overlay { Rectangle().stroke(AppPalette.success, lineWidth: 0.9) }
    }

    private func timelineHeader(_ continuityCase: ContinuityCase) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("EVIDENCE RELAY")
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("What changed, what was learned, what remains open")
                    .font(.system(size: 14, weight: .bold))
            }
            Spacer()
            ForEach(ContinuityTimelineFilter.allCases) { filter in
                Button {
                    timelineFilter = filter
                } label: {
                    Text("\(filter.label) \(filter.count(in: continuityCase))")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(timelineFilter == filter ? AppPalette.ibmBlue : AppPalette.secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 27)
                        .background(timelineFilter == filter ? AppPalette.ibmBlue.opacity(0.08) : AppPalette.panel)
                        .overlay { Rectangle().stroke(timelineFilter == filter ? AppPalette.ibmBlue : AppPalette.borderStrong, lineWidth: 0.8) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func timeline(_ continuityCase: ContinuityCase) -> some View {
        let entries = ContinuityTimelineEntry.entries(for: continuityCase)
            .filter { timelineFilter.includes($0) }
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    ContinuityTimelineRow(entry: entry)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
        .background(AppPalette.window)
    }

    private func openQuestions(_ continuityCase: ContinuityCase) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("OPEN QUESTIONS · \(continuityCase.openQuestions.count)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.warning)
                if continuityCase.openQuestions.isEmpty {
                    Text("No open questions recorded.")
                        .font(.system(size: 8))
                        .foregroundStyle(AppPalette.muted)
                } else {
                    ForEach(Array(continuityCase.openQuestions.enumerated()), id: \.offset) { _, question in
                        HStack(alignment: .top, spacing: 7) {
                            Rectangle()
                                .fill(.clear)
                                .frame(width: 7, height: 7)
                                .overlay { Rectangle().stroke(AppPalette.warning, lineWidth: 1) }
                                .padding(.top, 2)
                            Text(question)
                                .font(.system(size: 8))
                                .foregroundStyle(AppPalette.text)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text("NEXT VERIFIED ACTION")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
                Text(continuityCase.nextAction.isEmpty ? "Not recorded" : continuityCase.nextAction)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(2)
                Text(continuityCase.staleBoundary.isEmpty ? "No stale-evidence boundary recorded." : continuityCase.staleBoundary)
                    .font(.system(size: 7.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: 240, alignment: .leading)
            .background(AppPalette.raised)
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 0.7) }
        }
        .padding(14)
        .frame(minHeight: 122)
        .background(AppPalette.panel)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var custodyColumn: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let continuityCase = model.selectedContinuityCase {
                    custodyHeader(continuityCase)
                    readinessGates(continuityCase)
                    answerLedger(continuityCase)
                    caseReferences(continuityCase)
                    snapshotActions(continuityCase)
                }
            }
        }
        .background(AppPalette.panel)
    }

    private func custodyHeader(_ continuityCase: ContinuityCase) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CUSTODY + TRACEABILITY")
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.ibmBlue)
            Text("Can the next professional continue safely?")
                .font(.system(size: 16, weight: .bold))
            Text("Every claim links to a local receipt or stays visibly open.")
                .font(.system(size: 8))
                .foregroundStyle(AppPalette.secondary)
            if model.continuityCasebookUsesReplay {
                Text("DETERMINISTIC LOCAL REPLAY")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.warning)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.panel)
    }

    private func readinessGates(_ continuityCase: ContinuityCase) -> some View {
        VStack(spacing: 7) {
            custodyGate("Exact target + environment", state: "BOUND", ready: true)
            custodyGate("Evidence artifacts fingerprinted", state: "\(continuityCase.artifacts.count)", ready: !continuityCase.artifacts.isEmpty)
            custodyGate("AI answers linked to request", state: "\(continuityCase.answers.count)", ready: true)
            custodyGate("Open questions retained", state: "\(continuityCase.openQuestions.count) OPEN", ready: true)
            custodyGate("Next action + stale boundary", state: continuityCase.nextAction.isEmpty || continuityCase.staleBoundary.isEmpty ? "OPEN" : "READY", ready: !continuityCase.nextAction.isEmpty && !continuityCase.staleBoundary.isEmpty)
            custodyGate("Receiving owner acknowledgement", state: continuityCase.receiverAcknowledged ? "LOCAL ACK" : "OPEN", ready: continuityCase.receiverAcknowledged)
        }
        .padding(14)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func answerLedger(_ continuityCase: ContinuityCase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ASSIST ANSWER LEDGER")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Response provenance")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                Text("\(continuityCase.answers.count) ENTRIES")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }

            if continuityCase.answers.isEmpty {
                Text("Record an Assist response from the assistant panel to retain its exact context receipt and completion state.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.muted)
            } else {
                ForEach(continuityCase.answers.suffix(2).reversed()) { answer in
                    AnswerLedgerCard(answer: answer)
                }
            }
        }
        .padding(14)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func caseReferences(_ continuityCase: ContinuityCase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REVIEWED REFERENCES")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Imported locally, never ambient")
                        .font(.system(size: 12, weight: .bold))
                }
                Spacer()
                Text("\(continuityCase.references.count) PINNED")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            ForEach(continuityCase.references.prefix(3)) { reference in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(reference.kind.label.uppercased())
                            .foregroundStyle(AppPalette.ibmBlue)
                        Spacer()
                        Text(short(reference.fingerprint))
                            .foregroundStyle(AppPalette.muted)
                    }
                    .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                    Text(reference.title)
                        .font(.system(size: 8.5, weight: .semibold))
                    Text("\(reference.entries.count) selected entr\(reference.entries.count == 1 ? "y" : "ies") · \(reference.revision)")
                        .font(.system(size: 7))
                        .foregroundStyle(AppPalette.secondary)
                    Menu {
                        ForEach(reference.entries) { entry in
                            Button(entry.locator) {
                                model.prepareContinuityReferenceForAssist(
                                    referenceID: reference.id,
                                    entryID: entry.id
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            UtilityGlyph(kind: .contextShelf, color: AppPalette.ibmBlue, size: 11)
                            Text(reference.entries.count == 1 ? "PIN ENTRY FOR ASSIST" : "CHOOSE ENTRY FOR ASSIST")
                                .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(AppPalette.ibmBlue)
                        .padding(.top, 3)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Pin one explicitly reviewed reference entry to the local Context Shelf")
                }
                .padding(9)
                .background(AppPalette.panel)
                .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 0.7) }
            }
        }
        .padding(14)
        .background(AppPalette.ibmBlue.opacity(0.035))
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func snapshotActions(_ continuityCase: ContinuityCase) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.selectedContinuitySnapshots.isEmpty
                 ? "SNAPSHOT NOT YET CREATED"
                 : "\(model.selectedContinuitySnapshots.count) IMMUTABLE SNAPSHOT\(model.selectedContinuitySnapshots.count == 1 ? "" : "S")")
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(model.selectedContinuitySnapshots.isEmpty ? AppPalette.warning : AppPalette.success)
            Text(model.continuityCasebookDiagnostic)
                .font(.system(size: 8))
                .foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("EDIT CASE") { editingCase = continuityCase }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.continuityCasebookUsesReplay)
                Button("PREVIEW MANIFEST") { model.previewLatestContinuitySnapshot() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.selectedContinuitySnapshots.isEmpty)
            }
            Button("EXPORT LATEST SNAPSHOT") { model.exportLatestContinuitySnapshot() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.selectedContinuitySnapshots.isEmpty)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.panel)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("CASE: \(model.selectedContinuityCase?.phase.label.uppercased() ?? "NONE") · \(model.selectedContinuityCase?.artifacts.count ?? 0) ARTIFACTS")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("PROVIDER: IDLE · HOST EFFECT: NONE")
                .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.45))
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .font(.system(size: 8).italic())
                .foregroundStyle(Color(red: 0.62, green: 0.69, blue: 0.65))
                .lineLimit(1)
            Text("ARM64 · LOCAL CUSTODY")
                .foregroundStyle(.white)
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private func casebookBadge(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 3, height: 15)
            Text(text)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(color.opacity(0.07))
        .overlay { Rectangle().stroke(color.opacity(0.75), lineWidth: 0.8) }
    }

    private func custodyMetric(_ value: String, _ label: String, color: Color = AppPalette.text) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 5.8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 45)
        .background(AppPalette.panel)
    }

    private func custodyGate(_ label: String, state: String, ready: Bool) -> some View {
        let color = ready ? AppPalette.success : AppPalette.warning
        return HStack(spacing: 8) {
            Rectangle()
                .fill(ready ? color : .clear)
                .frame(width: 8, height: 8)
                .overlay { Rectangle().stroke(color, lineWidth: 1) }
            Text(label)
                .font(.system(size: 7.7))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(state)
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func short(_ fingerprint: String) -> String {
        String(fingerprint.prefix(6)).uppercased() + "…" + String(fingerprint.suffix(4)).uppercased()
    }
}

struct ContinuityReferenceReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var previewEntryID: UUID?

    var body: some View {
        let draft = model.pendingContinuityReferenceReview
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ContinuityRelayMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reviewed Reference Intake")
                        .font(.system(size: 16, weight: .bold))
                    Text("EXPLICIT LOCAL SELECTION · NO AMBIENT REPOSITORY ACCESS")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                }
                Spacer()
                Button("CANCEL") {
                    model.discardContinuityReferenceReview()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("ATTACH SELECTED") {
                    model.attachReviewedContinuityReference()
                    if model.pendingContinuityReferenceReview == nil { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(draft?.selectedEntryIDs.isEmpty != false)
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if let draft {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        referencePackDossier(draft)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(draft.pack.entries) { entry in
                                    Button {
                                        previewEntryID = entry.id
                                    } label: {
                                        HStack(spacing: 10) {
                                            Button {
                                                model.toggleContinuityReferenceEntry(entry.id)
                                            } label: {
                                                Rectangle()
                                                    .fill(draft.selectedEntryIDs.contains(entry.id) ? AppPalette.ibmBlue : .clear)
                                                    .frame(width: 12, height: 12)
                                                    .overlay { Rectangle().stroke(AppPalette.ibmBlue, lineWidth: 1) }
                                            }
                                            .buttonStyle(.plain)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(entry.locator)
                                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(AppPalette.text)
                                                    .lineLimit(1)
                                                Text("\(entry.content.utf8.count) BYTES · \(shortReference(entry.contentSHA256))")
                                                    .font(.system(size: 6.5, design: .monospaced))
                                                    .foregroundStyle(AppPalette.muted)
                                            }
                                            Spacer()
                                        }
                                        .padding(12)
                                        .background(previewEntryID == entry.id ? AppPalette.ibmBlue.opacity(0.07) : AppPalette.panel)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Rectangle().fill(AppPalette.border).frame(height: 1)
                                }
                            }
                        }
                    }
                    .frame(width: 360)
                    .background(AppPalette.panel)

                    Rectangle().fill(AppPalette.border).frame(width: 1)

                    referencePreview(draft)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("No reference pack", systemImage: "doc")
            }

            HStack {
                Text("REFERENCE DATA STAYS LOCAL UNTIL A LATER, SEPARATE ASSIST REVIEW")
                    .foregroundStyle(AppPalette.terminalGreen)
                Spacer()
                Text("NO API KEY · NO PROVIDER · NO HOST")
                    .foregroundStyle(.white)
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(AppPalette.terminal)
        }
        .background(AppPalette.window)
        .onAppear { previewEntryID = draft?.pack.entries.first?.id }
    }

    private func referencePackDossier(_ draft: ContinuityReferenceReviewDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.pack.kind.label.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.ibmBlue)
            Text(draft.pack.title)
                .font(.system(size: 14, weight: .bold))
            Text("\(draft.sourceName) · revision \(draft.pack.revision)")
                .font(.system(size: 8))
                .foregroundStyle(AppPalette.secondary)
            Text("PACK \(shortReference(draft.pack.fingerprint)) · \(draft.selectedEntryIDs.count)/\(draft.pack.entries.count) SELECTED")
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.success)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func referencePreview(_ draft: ContinuityReferenceReviewDraft) -> some View {
        let entry = draft.pack.entries.first(where: { $0.id == previewEntryID }) ?? draft.pack.entries.first
        return VStack(alignment: .leading, spacing: 10) {
            Text("EXACT ENTRY PREVIEW")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.ibmBlue)
            if let entry {
                Text(entry.locator)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                Text("SHA-256 \(entry.contentSHA256.uppercased())")
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .textSelection(.enabled)
                ScrollView([.vertical, .horizontal]) {
                    Text(entry.content)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppPalette.terminalGreen)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .background(AppPalette.terminal)
                .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 0.8) }
            }
            Text("Review selection changes only this local intake draft. Attaching creates an immutable reference receipt inside the selected case.")
                .font(.system(size: 8))
                .foregroundStyle(AppPalette.secondary)
        }
        .padding(18)
    }

    private func shortReference(_ value: String) -> String {
        String(value.prefix(8)).uppercased() + "…" + String(value.suffix(4)).uppercased()
    }
}

struct ContinuityHandoffSnapshotView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ContinuityRelayMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Immutable Handoff Snapshot")
                        .font(.system(size: 16, weight: .bold))
                    Text("LOCAL MANIFEST · EXACT RECEIPTS · NO AUTHORITY CLAIM")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                }
                Spacer()
                Button("EXPORT JSON") { model.exportLatestContinuitySnapshot() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("CLOSE") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if let snapshot = model.latestContinuitySnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            snapshotMetric(snapshot.caseRecord.code, "CASE")
                            snapshotMetric("\(snapshot.caseRecord.artifacts.count)", "ARTIFACTS")
                            snapshotMetric("\(snapshot.caseRecord.answers.count)", "AI ANSWERS")
                            snapshotMetric("\(snapshot.caseRecord.references.count)", "REFERENCES")
                            snapshotMetric("\(snapshot.readinessGaps.count)", "OPEN GATES", color: snapshot.readinessGaps.isEmpty ? AppPalette.success : AppPalette.warning)
                        }
                        Text(snapshot.caseRecord.title)
                            .font(.system(size: 22, weight: .bold))
                        Text(snapshot.caseRecord.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.secondary)
                        receiptBlock("SNAPSHOT SHA-256", snapshot.fingerprint)
                        receiptBlock("CASE SHA-256", snapshot.caseRecord.fingerprint)

                        manifestSection("ARTIFACT MANIFEST") {
                            ForEach(snapshot.caseRecord.artifacts) { artifact in
                                manifestRow(
                                    artifact.kind.label,
                                    artifact.title,
                                    "\(artifact.content.utf8.count) bytes · \(shortSnapshot(artifact.fingerprint))"
                                )
                            }
                        }
                        manifestSection("ASSIST ANSWER LEDGER") {
                            if snapshot.caseRecord.answers.isEmpty {
                                Text("No Assist answers recorded.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppPalette.muted)
                            } else {
                                ForEach(snapshot.caseRecord.answers) { answer in
                                    manifestRow(
                                        answer.state.label,
                                        answer.question,
                                        "\(answer.model) · context \(answer.contextItemCount) · \(shortSnapshot(answer.fingerprint))"
                                    )
                                }
                            }
                        }
                        manifestSection("REVIEWED REFERENCES") {
                            if snapshot.caseRecord.references.isEmpty {
                                Text("No reviewed reference packs recorded.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppPalette.muted)
                            } else {
                                ForEach(snapshot.caseRecord.references) { reference in
                                    manifestRow(
                                        reference.kind.label,
                                        reference.title,
                                        "\(reference.entries.count) entries · \(shortSnapshot(reference.fingerprint))"
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }

            HStack {
                Text("SNAPSHOT IS IMMUTABLE LOCAL EVIDENCE, NOT AN AUTHENTICATED APPROVAL")
                    .foregroundStyle(AppPalette.terminalGreen)
                Spacer()
                Text("HOST EFFECT: NONE")
                    .foregroundStyle(.white)
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(AppPalette.terminal)
        }
        .background(AppPalette.window)
    }

    private func snapshotMetric(_ value: String, _ label: String, color: Color = AppPalette.text) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.panel)
        .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 0.8) }
    }

    private func receiptBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.terminalGreen)
            Text(value.uppercased())
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.terminal)
    }

    private func manifestSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.ibmBlue)
            content()
        }
        .padding(13)
        .background(AppPalette.panel)
        .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 0.8) }
    }

    private func manifestRow(_ kind: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(AppPalette.ibmBlue).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.uppercased())
                    .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func shortSnapshot(_ value: String) -> String {
        String(value.prefix(8)).uppercased() + "…" + String(value.suffix(4)).uppercased()
    }
}

private struct ContinuityCaseEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let continuityCase: ContinuityCase
    @State private var title: String
    @State private var summary: String
    @State private var questionsText: String
    @State private var nextAction: String
    @State private var staleBoundary: String
    @State private var receiverAcknowledged: Bool

    init(continuityCase: ContinuityCase) {
        self.continuityCase = continuityCase
        _title = State(initialValue: continuityCase.title)
        _summary = State(initialValue: continuityCase.summary)
        _questionsText = State(initialValue: continuityCase.openQuestions.joined(separator: "\n"))
        _nextAction = State(initialValue: continuityCase.nextAction)
        _staleBoundary = State(initialValue: continuityCase.staleBoundary)
        _receiverAcknowledged = State(initialValue: continuityCase.receiverAcknowledged)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ContinuityRelayMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit \(continuityCase.code)")
                        .font(.system(size: 16, weight: .bold))
                    Text("LOCAL WORKFLOW DETAILS · SNAPSHOTS REMAIN IMMUTABLE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                }
                Spacer()
                Button("CANCEL") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("SAVE CASE") {
                    let questions = questionsText
                        .split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    model.updateSelectedContinuityWorkflow(
                        title: title,
                        summary: summary,
                        openQuestions: questions,
                        nextAction: nextAction,
                        staleBoundary: staleBoundary,
                        receiverAcknowledged: receiverAcknowledged
                    )
                    if model.selectedContinuityCase?.title == title.trimmingCharacters(in: .whitespacesAndNewlines) {
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            Form {
                Section("CASE QUESTION") {
                    TextField("What must the next professional understand?", text: $title)
                    TextEditor(text: $summary)
                        .frame(minHeight: 70)
                }
                Section("OPEN QUESTIONS") {
                    TextEditor(text: $questionsText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 90)
                    Text("One question per line; empty lines are ignored.")
                        .font(.system(size: 8))
                        .foregroundStyle(AppPalette.muted)
                }
                Section("NEXT VERIFIED ACTION") {
                    TextEditor(text: $nextAction).frame(minHeight: 62)
                    TextEditor(text: $staleBoundary).frame(minHeight: 62)
                }
                Section("LOCAL ACKNOWLEDGEMENT") {
                    Toggle("Receiving professional reviewed this local handoff", isOn: $receiverAcknowledged)
                    Text("This is a local workflow marker, not authenticated identity, authority, or approval.")
                        .font(.system(size: 8))
                        .foregroundStyle(AppPalette.warning)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct CasebookCaseRow: View {
    let continuityCase: ContinuityCase
    let selected: Bool
    let isReplay: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 4, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(continuityCase.code) · \(continuityCase.title)")
                        .font(.system(size: 8.2, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(1)
                    Text("\(continuityCase.target) · \(continuityCase.artifacts.count) artifacts")
                        .font(.system(size: 8))
                        .foregroundStyle(AppPalette.secondary)
                        .lineLimit(1)
                    Text("\(continuityCase.phase.label.uppercased())\(isReplay ? " · REPLAY" : "")")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .frame(height: 84)
            .background(selected ? AppPalette.ibmBlue.opacity(0.08) : AppPalette.panel)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var statusColor: Color {
        switch continuityCase.phase {
        case .draft: AppPalette.ibmBlue
        case .handedOff: AppPalette.success
        case .reopened: AppPalette.warning
        case .closed: AppPalette.muted
        }
    }
}

private struct AnswerLedgerCard: View {
    let answer: ContinuityAssistAnswer

    var body: some View {
        let color = answer.state == .complete ? AppPalette.ibmBlue : AppPalette.warning
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(answer.state.label)
                    .foregroundStyle(color)
                Spacer()
                Text(answer.state == .complete ? (answer.commandRisk?.rawValue.uppercased() ?? "NO COMMAND") : "NO COMPLETED RISK LABEL")
                    .foregroundStyle(AppPalette.muted)
            }
            .font(.system(size: 6.2, weight: .bold, design: .monospaced))
            Text(answer.question)
                .font(.system(size: 8.3, weight: .semibold))
                .lineLimit(2)
            Text("\(answer.model) · CTX \(answer.contextItemCount) · \(shortAnswer(answer.fingerprint))")
                .font(.system(size: 6.3, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(9)
        .background(color.opacity(0.07))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .overlay { Rectangle().stroke(color.opacity(0.75), lineWidth: 0.7) }
    }

    private func shortAnswer(_ value: String) -> String {
        String(value.prefix(6)).uppercased() + "…" + String(value.suffix(4)).uppercased()
    }
}

private struct ContinuityTimelineRow: View {
    let entry: ContinuityTimelineEntry

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .frame(width: 46, alignment: .trailing)
            VStack(spacing: 0) {
                Rectangle().fill(AppPalette.borderStrong).frame(width: 2, height: 26)
                Rectangle().fill(entry.color).frame(width: 9, height: 9)
                Rectangle().fill(AppPalette.borderStrong).frame(width: 2, height: 26)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.kind.uppercased())
                        .foregroundStyle(entry.color)
                    Spacer()
                    Text(entry.receipt)
                        .foregroundStyle(AppPalette.muted)
                }
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                Text(entry.title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                Text(entry.detail)
                    .font(.system(size: 7.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(AppPalette.panel)
            .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 0.7) }
        }
    }
}

private struct ContinuityTimelineEntry: Identifiable {
    enum Category { case evidence, answer, reference }

    let id: String
    let date: Date
    let category: Category
    let kind: String
    let title: String
    let detail: String
    let receipt: String
    let color: Color

    static func entries(for continuityCase: ContinuityCase) -> [ContinuityTimelineEntry] {
        let artifacts = continuityCase.artifacts.map { artifact in
            ContinuityTimelineEntry(
                id: "artifact-\(artifact.id)",
                date: artifact.createdAt,
                category: .evidence,
                kind: artifact.kind.label,
                title: artifact.title,
                detail: artifact.summary,
                receipt: shortTimeline(artifact.fingerprint),
                color: color(for: artifact.kind)
            )
        }
        let answers = continuityCase.answers.map { answer in
            ContinuityTimelineEntry(
                id: "answer-\(answer.id)",
                date: answer.createdAt,
                category: .answer,
                kind: "Assist answer · \(answer.state.label)",
                title: answer.question,
                detail: "\(answer.model) · context \(answer.contextItemCount) · \(answer.state == .complete ? "completed response" : "not relied on as complete")",
                receipt: shortTimeline(answer.fingerprint),
                color: answer.state == .complete ? AppPalette.ibmBlue : AppPalette.warning
            )
        }
        let references = continuityCase.references.map { reference in
            ContinuityTimelineEntry(
                id: "reference-\(reference.id)",
                date: reference.reviewedAt,
                category: .reference,
                kind: "Reviewed \(reference.kind.label)",
                title: reference.title,
                detail: "\(reference.entries.count) selected entr\(reference.entries.count == 1 ? "y" : "ies") · \(reference.revision)",
                receipt: shortTimeline(reference.fingerprint),
                color: AppPalette.success
            )
        }
        return (artifacts + answers + references).sorted { $0.date < $1.date }
    }

    private static func color(for kind: ContinuityArtifactKind) -> Color {
        switch kind {
        case .operatorNote: AppPalette.warning
        case .terminalScreen, .systemHealth: Color(red: 0.47, green: 0.66, blue: 1)
        case .jobIncident, .objectImpact, .authorityReview: AppPalette.success
        default: AppPalette.ibmBlue
        }
    }

    private static func shortTimeline(_ value: String) -> String {
        String(value.prefix(6)).uppercased() + "…" + String(value.suffix(4)).uppercased()
    }
}

private enum ContinuityTimelineFilter: String, CaseIterable, Identifiable {
    case all
    case answers
    case open

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "ALL"
        case .answers: "AI"
        case .open: "OPEN"
        }
    }

    func includes(_ entry: ContinuityTimelineEntry) -> Bool {
        switch self {
        case .all: true
        case .answers: entry.category == .answer
        case .open: entry.kind.localizedCaseInsensitiveContains("stopped")
            || entry.kind.localizedCaseInsensitiveContains("note")
        }
    }

    func count(in continuityCase: ContinuityCase) -> Int {
        switch self {
        case .all: ContinuityTimelineEntry.entries(for: continuityCase).count
        case .answers: continuityCase.answers.count
        case .open: continuityCase.openQuestions.count
        }
    }
}

private struct ContinuityRelayMark: View {
    var size: CGFloat
    var framed = true

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.075), lineCap: .square, lineJoin: .miter)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func route(_ points: [CGPoint], color: Color, opacity: Double = 1) {
                var path = Path()
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color.opacity(opacity)), style: stroke)
            }
            route([p(0.10, 0.25), p(0.36, 0.25), p(0.50, 0.50), p(0.70, 0.50), p(0.90, 0.75)], color: AppPalette.terminalGreen)
            route([p(0.10, 0.75), p(0.36, 0.75), p(0.50, 0.50), p(0.70, 0.50), p(0.90, 0.25)], color: .white, opacity: 0.78)
            context.stroke(
                Path(CGRect(x: w * 0.43, y: h * 0.43, width: w * 0.14, height: h * 0.14)),
                with: .color(AppPalette.registrationBlue),
                style: stroke
            )
        }
        .frame(width: size, height: size)
        .background(framed ? AppPalette.instrument : .clear)
        .overlay {
            if framed { Rectangle().stroke(AppPalette.registrationBlue, lineWidth: 0.9) }
        }
        .accessibilityHidden(true)
    }
}
