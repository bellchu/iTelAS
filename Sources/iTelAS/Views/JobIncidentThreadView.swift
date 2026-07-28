import SwiftUI
import iTelASCore

struct JobIncidentThreadView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var selectedSurface: JobIncidentSurface = .incident

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    jobLedger
                        .frame(width: proxy.size.width < 1_050 ? 246 : 278)
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    selectedWorkspace(compact: proxy.size.width < 1_050)
                }
            }
            statusStrip
        }
        .background(AppPalette.window)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            IncidentThreadKnotMark(size: 35)
            VStack(alignment: .leading, spacing: 2) {
                Text("OPERATIONS / INCIDENT THREAD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.75)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Jobs & Queues")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            Spacer(minLength: 12)
            headerMetric("ACTIVE", value: activeJobCount, color: AppPalette.success)
            headerMetric("WAITING", value: waitingJobCount, color: AppPalette.warning)
            headerMetric("JOBQ", value: queuedJobCount, color: AppPalette.registrationBlue)
            IncidentBadge(
                text: model.jobIncidentPhase.label,
                color: incidentPhaseColor,
                prominent: false
            )
            Button {
                if model.db2Phase.isConnected {
                    model.refreshJobIncidentSnapshot()
                } else {
                    model.presentDb2ConnectionDossier()
                }
            } label: {
                HStack(spacing: 8) {
                    IncidentScopeMark(
                        color: model.jobIncidentPhase.isCollecting ? AppPalette.warning : .white,
                        size: 15
                    )
                    Text(refreshButtonLabel)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.jobIncidentPhase.isCollecting)
            .help(refreshButtonHelp)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func headerMetric(_ label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AppPalette.muted)
            Text(String(value))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(minWidth: 48, alignment: .leading)
    }

    private var jobLedger: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKLOAD QUEUE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.muted)
                    Text("\(filteredJobs.count) of \(model.jobIncidentSnapshot.jobs.count) jobs")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                WorkbenchGlyph(tool: .jobsAndQueues, color: AppPalette.registrationBlue, size: 18)
            }
            .padding(.horizontal, 13)
            .frame(height: 50)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                TextField("Job, user, queue, subsystem", text: $searchText)
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
                    ForEach(filteredJobs) { job in
                        IncidentJobRow(
                            job: job,
                            waitCount: waitCount(for: job),
                            selected: model.selectedIncidentJobID == job.qualifiedName
                        ) {
                            model.selectIncidentJob(job)
                            selectedSurface = .incident
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            queuePressure
        }
        .background(AppPalette.panel)
    }

    private var queuePressure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
            HStack {
                Text("QUEUE PRESSURE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                Text("OLDEST")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            ForEach(model.jobIncidentSnapshot.queueSummaries.prefix(3)) { summary in
                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.identity.id)
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppPalette.text)
                            .lineLimit(1)
                        Text("\(summary.queuedCount) queued · \(summary.heldCount) held · \(summary.scheduledCount) scheduled")
                            .font(.system(size: 7.5))
                            .foregroundStyle(AppPalette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 3)
                    Text(queueAge(summary.oldestQueueTime))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(summary.heldCount > 0 ? AppPalette.warning : AppPalette.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
        .frame(height: 134)
    }

    @ViewBuilder
    private func selectedWorkspace(compact: Bool) -> some View {
        if let job = model.selectedIncidentJob, let analysis = model.jobIncidentAnalysis {
            VStack(spacing: 0) {
                selectedJobHeader(job, analysis: analysis)
                HStack(spacing: 0) {
                    evidenceSurface(job, analysis: analysis)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                    if !compact {
                        Rectangle().fill(AppPalette.border).frame(width: 1)
                        incidentDossier(analysis)
                            .frame(width: 314)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No job selected",
                systemImage: "waveform.path.ecg.rectangle",
                description: Text("Select an accessible job from the workload queue.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectedJobHeader(
        _ job: JobInventoryRecord,
        analysis: JobIncidentAnalysis
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    IncidentBadge(text: job.status.label.uppercased(), color: statusColor(job.status), prominent: false)
                    if !job.informationAvailable {
                        IncidentBadge(text: "INFORMATION UNAVAILABLE", color: AppPalette.warning, prominent: false)
                    }
                    Text(model.jobIncidentSnapshot.targetName)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                }
                Text(job.qualifiedName.rawValue)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .textSelection(.enabled)
                Text("Exact qualified job identity · captured \(isoTimestamp(model.jobIncidentSnapshot.capturedAt))")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer(minLength: 10)
            IncidentFact(label: "SUBSYSTEM", value: job.subsystem?.value ?? "UNAVAILABLE")
            IncidentFact(label: "JOB QUEUE", value: job.jobQueue?.id ?? "UNAVAILABLE")
            IncidentFact(label: "LOCK WAITS", value: String(analysis.waitingLocks.count))
            IncidentConfidencePlate(confidence: analysis.confidence)
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func evidenceSurface(
        _ job: JobInventoryRecord,
        analysis: JobIncidentAnalysis
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(JobIncidentSurface.allCases) { surface in
                    Button {
                        selectedSurface = surface
                    } label: {
                        Text(surface.label(counts: surfaceCounts))
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
                Text("READ ONLY · 4 BOUNDED SOURCES")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
                    .padding(.trailing, 12)
            }
            .frame(height: 38)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }

            Group {
                switch selectedSurface {
                case .incident:
                    incidentSurface(job, analysis: analysis)
                case .jobLog:
                    jobLogSurface(job, analysis: analysis)
                case .locks:
                    lockSurface(analysis)
                case .receipts:
                    receiptSurface
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppPalette.panel)
    }

    private func incidentSurface(
        _ job: JobInventoryRecord,
        analysis: JobIncidentAnalysis
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(analysis.waitingLocks.isEmpty ? AppPalette.success : AppPalette.warning)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(analysis.waitingLocks.isEmpty ? "NO VISIBLE LOCK WAIT" : "WAITING STATE OBSERVED")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(analysis.waitingLocks.isEmpty ? AppPalette.success : AppPalette.warning)
                        Text(analysis.relationshipBasis)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AppPalette.text)
                            .lineSpacing(2)
                    }
                }
                .padding(.vertical, 10)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((analysis.waitingLocks.isEmpty ? AppPalette.success : AppPalette.warning).opacity(0.055))
                .overlay {
                    ChamferedRectangle(cut: 4)
                        .stroke((analysis.waitingLocks.isEmpty ? AppPalette.success : AppPalette.warning).opacity(0.35), lineWidth: 0.8)
                }
                .clipShape(ChamferedRectangle(cut: 4))

                IncidentSectionTitle(
                    title: "EXACT WAIT CHAIN",
                    detail: "Candidate relationship; compatibility and causality require operator review"
                )
                waitChain(job, analysis: analysis)

                IncidentSectionTitle(
                    title: "STATE + MESSAGE THREAD",
                    detail: "Lock state is sampled; only messages with timestamps are chronological"
                )
                evidenceThread(analysis)
            }
            .padding(14)
        }
    }

    private func waitChain(
        _ job: JobInventoryRecord,
        analysis: JobIncidentAnalysis
    ) -> some View {
        let waiting = analysis.waitingLocks.first
        let correlation = analysis.holderCandidates.first
        return HStack(spacing: 8) {
            IncidentChainNode(
                index: "01",
                label: "WAITER",
                title: job.qualifiedName.name,
                detail: job.qualifiedName.rawValue,
                color: AppPalette.warning
            )
            IncidentChainLink(label: waiting == nil ? "NO WAIT" : "REQUESTS")
            IncidentChainNode(
                index: "02",
                label: "RESOURCE",
                title: waiting?.object.object.value ?? "NOT VISIBLE",
                detail: waiting?.object.displayName ?? "No exact lock record",
                color: AppPalette.registrationBlue
            )
            IncidentChainLink(label: correlation == nil ? "NO MATCH" : "HELD BY?")
            IncidentChainNode(
                index: "03",
                label: "CANDIDATE",
                title: correlation?.holder.job.name ?? "NOT VISIBLE",
                detail: correlation?.holder.job.rawValue ?? "No exact-object holder",
                color: correlation == nil ? AppPalette.muted : AppPalette.danger
            )
        }
    }

    private func evidenceThread(_ analysis: JobIncidentAnalysis) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(analysis.waitingLocks.prefix(1))) { lock in
                IncidentThreadRow(
                    stamp: "AT SNAPSHOT",
                    marker: "LOCK",
                    title: "\(lock.status.rawValue) \(lock.object.displayName)",
                    detail: "\(lock.state) · \(lock.scope) scope · thread \(lock.threadID.map(String.init) ?? "unavailable")",
                    color: AppPalette.warning
                )
            }
            ForEach(Array(analysis.holderCandidates.prefix(1))) { correlation in
                IncidentThreadRow(
                    stamp: "AT SNAPSHOT",
                    marker: "CANDIDATE",
                    title: correlation.holder.job.rawValue,
                    detail: "HELD \(correlation.holder.object.displayName) · correlation, not causal proof",
                    color: AppPalette.danger
                )
            }
            ForEach(jobMessages(for: analysis.selectedJob).suffix(4)) { message in
                IncidentThreadRow(
                    stamp: isoTimestamp(message.timestamp),
                    marker: message.messageID ?? "MESSAGE",
                    title: message.text ?? "Message text unavailable",
                    detail: "\(message.type) · severity \(message.severity)",
                    color: message.isInquiry ? AppPalette.warning : severityColor(message.severity)
                )
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppPalette.borderStrong)
                .frame(width: 1)
                .padding(.leading, 85)
                .padding(.vertical, 19)
        }
    }

    private func jobLogSurface(
        _ job: JobInventoryRecord,
        analysis: JobIncidentAnalysis
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                IncidentSectionTitle(
                    title: "READABLE JOB LOG",
                    detail: "Exact first- and second-level text; no message noise was silently discarded"
                )
                ForEach(jobMessages(for: job)) { message in
                    IncidentMessageCard(
                        message: message,
                        selected: analysis.selectedMessage?.id == message.id
                    )
                }
            }
            .padding(14)
        }
    }

    private func lockSurface(_ analysis: JobIncidentAnalysis) -> some View {
        let relevantIDs = Set(analysis.waitingLocks.map(\.object))
        let records = model.jobIncidentSnapshot.locks.filter {
            $0.job == analysis.selectedJob.qualifiedName || relevantIDs.contains($0.object)
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                IncidentSectionTitle(
                    title: "LOCK RECORDS",
                    detail: "Exact object identities and snapshot states; the service does not timestamp lock rows"
                )
                ForEach(records) { lock in
                    IncidentLockCard(
                        lock: lock,
                        role: lock.job == analysis.selectedJob.qualifiedName ? "SELECTED JOB" : "CANDIDATE HOLDER"
                    )
                }
                if records.isEmpty {
                    Text("No accessible lock rows matched the selected job or its requested objects.")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.secondary)
                }
            }
            .padding(14)
        }
    }

    private var receiptSurface: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                IncidentSectionTitle(
                    title: "QUERY RECEIPTS",
                    detail: "Every source is bounded and fingerprinted; unavailable evidence remains visible"
                )
                ForEach(model.jobIncidentSnapshot.receipts) { receipt in
                    IncidentReceiptRow(receipt: receipt)
                }
                Text("Fingerprints identify the exact local SQL text used for each evidence surface. They do not attest to host state beyond this snapshot.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.muted)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }
            .padding(14)
        }
    }

    private func incidentDossier(_ analysis: JobIncidentAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 9) {
                    EvidenceScopeMark(color: AppPalette.registrationBlue, size: 31)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INCIDENT DOSSIER")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(AppPalette.muted)
                        Text("What the evidence supports")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppPalette.text)
                    }
                }

                IncidentConfidencePlate(confidence: analysis.confidence)
                Text(analysis.relationshipBasis)
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
                    .lineSpacing(3)

                dossierDivider("SELECTED MESSAGE")
                if let message = analysis.selectedMessage {
                    HStack {
                        IncidentBadge(
                            text: message.messageID ?? "NO ID",
                            color: message.isInquiry ? AppPalette.warning : severityColor(message.severity),
                            prominent: false
                        )
                        Spacer()
                        Text("SEV \(message.severity)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                    }
                    Text(message.text ?? "Message text unavailable")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                        .textSelection(.enabled)
                    Text(message.secondLevelText ?? "Second-level text unavailable")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                    Text(analysis.messageSelectionBasis)
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.muted)
                        .italic()
                } else {
                    Text("No accessible job-log message was present for this job.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppPalette.secondary)
                }

                dossierDivider("EVIDENCE COVERAGE")
                ForEach(model.jobIncidentSnapshot.receipts) { receipt in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(receipt.outcome.isCollected ? AppPalette.success : AppPalette.warning)
                            .frame(width: 6, height: 6)
                        Text(receipt.source.rawValue)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppPalette.text)
                        Spacer()
                        Text(receipt.outcome.isCollected ? "\(receipt.rowCount) ROWS" : "GAP")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(receipt.outcome.isCollected ? AppPalette.success : AppPalette.warning)
                    }
                }

                Button {
                    model.prepareIncidentAssist()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            IncidentSparkMark(color: .white, size: 15)
                            Text("Pin to Assist Shelf")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        Text("Exact evidence · local until send")
                            .font(.system(size: 7.5, design: .monospaced))
                            .opacity(0.82)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PrimaryButtonStyle())

                Text("Pinned evidence remains local until you send from Assist. It cannot reply to messages, hold, release, or end jobs.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.muted)
                    .lineSpacing(2)
            }
            .padding(14)
        }
        .background(AppPalette.panel)
    }

    private func dossierDivider(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.muted)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Text("EVIDENCE: \(model.jobIncidentPhase.label)")
                .foregroundStyle(incidentPhaseColor)
            Text("TARGET: \(model.jobIncidentSnapshot.targetName)")
            Text("HOST WRITE: NONE")
                .foregroundStyle(AppPalette.terminalGreen)
            Text(model.jobIncidentDiagnostic)
                .lineLimit(1)
                .foregroundStyle(model.jobIncidentPhase == .failed ? AppPalette.warning : Color(red: 0.67, green: 0.74, blue: 0.70))
            Spacer(minLength: 6)
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("ARM64 · NATIVE")
                .foregroundStyle(.white)
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }

    private var filteredJobs: [JobInventoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.jobIncidentSnapshot.jobs }
        return model.jobIncidentSnapshot.jobs.filter { job in
            [
                job.qualifiedName.rawValue,
                job.status.rawValue,
                job.type ?? "",
                job.enhancedType ?? "",
                job.subsystem?.value ?? "",
                job.jobQueue?.id ?? "",
                job.outputQueue?.id ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var activeJobCount: Int {
        model.jobIncidentSnapshot.jobs.filter { $0.status == .active }.count
    }

    private var waitingJobCount: Int {
        Set(model.jobIncidentSnapshot.locks.filter {
            $0.status == .waiting || $0.status == .requested
        }.map(\.job)).count
    }

    private var queuedJobCount: Int {
        model.jobIncidentSnapshot.jobs.filter { $0.status == .jobQueue }.count
    }

    private var surfaceCounts: JobIncidentSurfaceCounts {
        JobIncidentSurfaceCounts(
            messages: model.selectedIncidentJob.map { jobMessages(for: $0).count } ?? 0,
            locks: model.jobIncidentAnalysis.map {
                $0.waitingLocks.count + $0.holderCandidates.count
            } ?? 0,
            receipts: model.jobIncidentSnapshot.receipts.count
        )
    }

    private var incidentPhaseColor: Color {
        switch model.jobIncidentPhase {
        case .localReplay: AppPalette.registrationBlue
        case .collecting: AppPalette.warning
        case .ready: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var refreshButtonLabel: String {
        if model.jobIncidentPhase.isCollecting { return "Collecting…" }
        return model.db2Phase.isConnected ? "Refresh Snapshot" : "Connect Read-only"
    }

    private var refreshButtonHelp: String {
        model.db2Phase.isConnected
            ? "Run four bounded read-only IBM i Services queries; optional failures remain visible as evidence gaps"
            : "Open the native Db2 connection dossier; no query runs automatically"
    }

    private func waitCount(for job: JobInventoryRecord) -> Int {
        model.jobIncidentSnapshot.locks.filter {
            $0.job == job.qualifiedName && ($0.status == .waiting || $0.status == .requested)
        }.count
    }

    private func jobMessages(for job: JobInventoryRecord) -> [JobLogMessage] {
        model.jobIncidentSnapshot.jobLogMessages.filter {
            $0.qualifiedJobName == job.qualifiedName
        }
    }

    private func queueAge(_ date: Date?) -> String {
        guard let date else { return "—" }
        let minutes = max(0, Int(model.jobIncidentSnapshot.capturedAt.timeIntervalSince(date) / 60))
        return minutes >= 60 ? "\(minutes / 60)H \(minutes % 60)M" : "\(minutes)M"
    }

    private func isoTimestamp(_ date: Date?) -> String {
        guard let date else { return "TIME UNAVAILABLE" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func statusColor(_ status: JobInventoryStatus) -> Color {
        switch status {
        case .active: AppPalette.success
        case .jobQueue: AppPalette.registrationBlue
        case .outputQueue: AppPalette.secondary
        case .unavailable: AppPalette.warning
        }
    }

    private func severityColor(_ severity: Int) -> Color {
        switch severity {
        case 40...: AppPalette.danger
        case 20...: AppPalette.warning
        default: AppPalette.registrationBlue
        }
    }
}

private enum JobIncidentSurface: String, CaseIterable, Identifiable {
    case incident
    case jobLog
    case locks
    case receipts

    var id: Self { self }

    func label(counts: JobIncidentSurfaceCounts) -> String {
        switch self {
        case .incident: "INCIDENT THREAD"
        case .jobLog: "JOB LOG \(counts.messages)"
        case .locks: "LOCKS \(counts.locks)"
        case .receipts: "RECEIPTS \(counts.receipts)"
        }
    }
}

private struct JobIncidentSurfaceCounts {
    let messages: Int
    let locks: Int
    let receipts: Int
}

private struct IncidentJobRow: View {
    let job: JobInventoryRecord
    let waitCount: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                VStack(spacing: 3) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Rectangle()
                        .fill(statusColor.opacity(0.35))
                        .frame(width: 1, height: 22)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(job.qualifiedName.name)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppPalette.text)
                        if waitCount > 0 {
                            Text("WAIT \(waitCount)")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppPalette.warning)
                                .padding(.horizontal, 5)
                                .frame(height: 16)
                                .overlay {
                                    ChamferedRectangle(cut: 2).stroke(AppPalette.warning, lineWidth: 0.7)
                                }
                        }
                    }
                    Text(job.qualifiedName.rawValue)
                        .font(.system(size: 7.8, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(job.status.label.uppercased())
                        Text("·")
                        Text(job.subsystem?.value ?? job.jobQueue?.name.value ?? "UNAVAILABLE")
                        if job.jobQueueStatus == "HELD" {
                            Text("· HELD").foregroundStyle(AppPalette.warning)
                        }
                    }
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AppPalette.ibmBlue.opacity(0.085) : Color.clear)
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle().fill(AppPalette.registrationBlue).frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border.opacity(0.72)).frame(height: 1)
        }
    }

    private var statusColor: Color {
        if waitCount > 0 { return AppPalette.warning }
        return switch job.status {
        case .active: AppPalette.success
        case .jobQueue: AppPalette.registrationBlue
        case .outputQueue: AppPalette.secondary
        case .unavailable: AppPalette.warning
        }
    }
}

private struct IncidentBadge: View {
    let text: String
    let color: Color
    let prominent: Bool

    var body: some View {
        Text(text)
            .font(.system(size: prominent ? 9 : 7.5, weight: .bold, design: .monospaced))
            .tracking(0.45)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: prominent ? 28 : 23)
            .background(color.opacity(0.07))
            .overlay {
                ChamferedRectangle(cut: 3).stroke(color.opacity(0.75), lineWidth: 0.8)
            }
            .clipShape(ChamferedRectangle(cut: 3))
    }
}

private struct IncidentFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
        }
        .frame(minWidth: 70, maxWidth: 120, alignment: .leading)
    }
}

private struct IncidentConfidencePlate: View {
    let confidence: JobIncidentConfidence

    var body: some View {
        HStack(spacing: 7) {
            EvidenceScopeMark(color: color, size: 21)
            VStack(alignment: .leading, spacing: 1) {
                Text("CORRELATION")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                Text("\(confidence.label) CONFIDENCE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(color.opacity(0.06))
        .overlay {
            ChamferedRectangle(cut: 3).stroke(color.opacity(0.7), lineWidth: 0.8)
        }
        .clipShape(ChamferedRectangle(cut: 3))
    }

    private var color: Color {
        switch confidence {
        case .high: AppPalette.warning
        case .medium: AppPalette.registrationBlue
        case .low: AppPalette.muted
        }
    }
}

private struct IncidentSectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.muted)
            Text(detail)
                .font(.system(size: 8.5))
                .foregroundStyle(AppPalette.secondary)
            Spacer()
        }
    }
}

private struct IncidentChainNode: View {
    let index: String
    let label: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(index)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Spacer()
                Text(label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .lineLimit(2)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 75, alignment: .topLeading)
        .background(AppPalette.raised.opacity(0.72))
        .overlay(alignment: .top) {
            Rectangle().fill(color).frame(height: 2)
        }
        .overlay {
            ChamferedRectangle(cut: 4).stroke(AppPalette.border, lineWidth: 0.8)
        }
        .clipShape(ChamferedRectangle(cut: 4))
    }
}

private struct IncidentChainLink: View {
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Rectangle().fill(AppPalette.borderStrong).frame(height: 1)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 5, y: 4))
                    path.addLine(to: CGPoint(x: 0, y: 8))
                }
                .stroke(AppPalette.borderStrong, lineWidth: 1)
                .frame(width: 5, height: 8)
            }
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .fixedSize()
        }
        .frame(width: 42)
    }
}

private struct IncidentThreadRow: View {
    let stamp: String
    let marker: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(stamp)
                .font(.system(size: 7.2, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .frame(width: 74, alignment: .trailing)
                .lineLimit(2)
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 2)
                .zIndex(2)
            VStack(alignment: .leading, spacing: 3) {
                Text(marker)
                    .font(.system(size: 7.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 7)
    }
}

private struct IncidentMessageCard: View {
    let message: JobLogMessage
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                IncidentBadge(
                    text: message.messageID ?? "NO ID",
                    color: message.isInquiry ? AppPalette.warning : severityColor,
                    prominent: false
                )
                Text(message.type)
                Text("SEV \(message.severity)")
                Spacer()
                Text(timestamp)
            }
            .font(.system(size: 7.8, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppPalette.muted)
            Text(message.text ?? "Message text unavailable")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppPalette.text)
                .textSelection(.enabled)
            if let secondLevelText = message.secondLevelText {
                Text(secondLevelText)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
        }
        .padding(11)
        .background(selected ? AppPalette.warning.opacity(0.055) : AppPalette.raised.opacity(0.55))
        .overlay(alignment: .leading) {
            Rectangle().fill(selected ? AppPalette.warning : AppPalette.borderStrong).frame(width: 3)
        }
        .overlay {
            ChamferedRectangle(cut: 4).stroke(selected ? AppPalette.warning.opacity(0.5) : AppPalette.border, lineWidth: 0.8)
        }
        .clipShape(ChamferedRectangle(cut: 4))
    }

    private var severityColor: Color {
        message.severity >= 40 ? AppPalette.danger : message.severity >= 20 ? AppPalette.warning : AppPalette.ibmBlue
    }

    private var timestamp: String {
        guard let date = message.timestamp else { return "TIME UNAVAILABLE" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private struct IncidentLockCard: View {
    let lock: JobLockRecord
    let role: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            EvidenceScopeMark(color: statusColor, size: 27)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    IncidentBadge(text: lock.status.rawValue, color: statusColor, prominent: false)
                    Text(role)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                    Spacer()
                    Text("AT SNAPSHOT")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                }
                Text(lock.object.displayName)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .textSelection(.enabled)
                Text("\(lock.job.rawValue) · \(lock.state) · \(lock.scope) scope · thread \(lock.threadID.map(String.init) ?? "unavailable")")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .textSelection(.enabled)
                if lock.program != nil || lock.procedure != nil {
                    Text("\(lock.programLibrary?.value ?? "?")/\(lock.program?.value ?? "?") · \(lock.module?.value ?? "?") · \(lock.procedure ?? "procedure unavailable") · statement \(lock.statementID ?? "?")")
                        .font(.system(size: 8))
                        .foregroundStyle(AppPalette.muted)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(11)
        .background(AppPalette.raised.opacity(0.56))
        .overlay {
            ChamferedRectangle(cut: 4).stroke(AppPalette.border, lineWidth: 0.8)
        }
        .clipShape(ChamferedRectangle(cut: 4))
    }

    private var statusColor: Color {
        switch lock.status {
        case .held: AppPalette.danger
        case .requested, .waiting: AppPalette.warning
        }
    }
}

private struct IncidentReceiptRow: View {
    let receipt: JobIncidentEvidenceReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                EvidenceScopeMark(color: color, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.source.rawValue)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                    Text(receipt.outcome.isCollected ? "COLLECTED" : "UNAVAILABLE")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }
                Spacer()
                Text("\(receipt.rowCount) ROWS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                if receipt.wasTruncated {
                    IncidentBadge(text: "AT CAP", color: AppPalette.warning, prominent: false)
                }
            }
            if case .unavailable(let reason) = receipt.outcome {
                Text(reason)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                    .textSelection(.enabled)
            }
            Text("SQL SHA-256 · \(receipt.queryFingerprint.uppercased())")
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(11)
        .background(AppPalette.raised.opacity(0.5))
        .overlay {
            ChamferedRectangle(cut: 4).stroke(AppPalette.border, lineWidth: 0.8)
        }
        .clipShape(ChamferedRectangle(cut: 4))
    }

    private var color: Color {
        receipt.outcome.isCollected ? AppPalette.success : AppPalette.warning
    }
}

private struct IncidentThreadKnotMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1.2, w * 0.055), lineCap: .square, lineJoin: .miter)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            var spine = Path()
            spine.move(to: p(0.17, 0.28))
            spine.addLine(to: p(0.42, 0.28))
            spine.addLine(to: p(0.58, 0.50))
            spine.addLine(to: p(0.42, 0.72))
            spine.addLine(to: p(0.17, 0.72))
            context.stroke(spine, with: .color(.white.opacity(0.94)), style: stroke)
            var branch = Path()
            branch.move(to: p(0.58, 0.50))
            branch.addLine(to: p(0.83, 0.50))
            context.stroke(branch, with: .color(AppPalette.terminalGreen), style: stroke)
            for (point, color) in [(p(0.17, 0.28), AppPalette.registrationBlue), (p(0.17, 0.72), AppPalette.warning), (p(0.58, 0.50), Color.white), (p(0.83, 0.50), AppPalette.danger)] {
                context.fill(Path(CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .background(AppPalette.instrument, in: ChamferedRectangle(cut: 6))
        .overlay {
            ChamferedRectangle(cut: 6).stroke(AppPalette.registrationBlue.opacity(0.8), lineWidth: 0.9)
        }
        .accessibilityHidden(true)
    }
}

private struct IncidentScopeMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.09), lineCap: .square)
            let inset = w * 0.13
            context.stroke(Path(ellipseIn: CGRect(x: inset, y: inset, width: w - 2 * inset, height: h - 2 * inset)), with: .color(color.opacity(0.65)), style: stroke)
            var pointer = Path()
            pointer.move(to: CGPoint(x: w * 0.50, y: h * 0.13))
            pointer.addLine(to: CGPoint(x: w * 0.72, y: h * 0.45))
            pointer.addLine(to: CGPoint(x: w * 0.50, y: h * 0.50))
            context.stroke(pointer, with: .color(color), style: stroke)
            context.fill(Path(CGRect(x: w * 0.45, y: h * 0.45, width: w * 0.1, height: h * 0.1)), with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct EvidenceScopeMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .square)
            context.stroke(Path(CGRect(x: w * 0.16, y: h * 0.16, width: w * 0.68, height: h * 0.68)), with: .color(color.opacity(0.6)), style: stroke)
            var cross = Path()
            cross.move(to: CGPoint(x: w * 0.50, y: h * 0.08))
            cross.addLine(to: CGPoint(x: w * 0.50, y: h * 0.92))
            cross.move(to: CGPoint(x: w * 0.08, y: h * 0.50))
            cross.addLine(to: CGPoint(x: w * 0.92, y: h * 0.50))
            context.stroke(cross, with: .color(color), style: stroke)
            context.fill(Path(CGRect(x: w * 0.43, y: h * 0.43, width: w * 0.14, height: h * 0.14)), with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct IncidentSparkMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.085), lineCap: .square)
            var rays = Path()
            rays.move(to: CGPoint(x: w * 0.5, y: 0))
            rays.addLine(to: CGPoint(x: w * 0.5, y: h))
            rays.move(to: CGPoint(x: 0, y: h * 0.5))
            rays.addLine(to: CGPoint(x: w, y: h * 0.5))
            rays.move(to: CGPoint(x: w * 0.18, y: h * 0.18))
            rays.addLine(to: CGPoint(x: w * 0.82, y: h * 0.82))
            rays.move(to: CGPoint(x: w * 0.82, y: h * 0.18))
            rays.addLine(to: CGPoint(x: w * 0.18, y: h * 0.82))
            context.stroke(rays, with: .color(color), style: stroke)
            context.fill(Path(CGRect(x: w * 0.42, y: h * 0.42, width: w * 0.16, height: h * 0.16)), with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
