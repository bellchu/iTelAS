import SwiftUI
import iTelASCore

struct SpoolOutputView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var surface = SpoolOutputSurface.preview
    @State private var previewScale = 1.0

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                workspaceHeader

                HStack(spacing: 0) {
                    outputRunway
                        .frame(width: proxy.size.width < 1_050 ? 278 : 316)

                    Rectangle().fill(AppPalette.border).frame(width: 1)

                    documentWorkspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if proxy.size.width >= 1_150 {
                        Rectangle().fill(AppPalette.border).frame(width: 1)
                        evidenceDossier
                            .frame(width: 344)
                    }
                }

                statusStrip
            }
            .background(AppPalette.window)
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            FanfoldOutputMark()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("iTelAS / OUTPUT RUNWAY")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.registrationBlue)
                Text("Spool & Output")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
            }

            Spacer(minLength: 12)

            SpoolStatusPill(
                text: model.db2Profile.environment.label,
                color: AppPalette.environment(model.db2Profile.environment)
            )
            SpoolStatusPill(
                text: model.spoolInventoryPhase.label,
                color: inventoryPhaseColor
            )

            Button {
                if model.db2Phase.isConnected {
                    model.refreshSpoolOutputInventory()
                } else {
                    model.presentDb2ConnectionDossier()
                }
            } label: {
                HStack(spacing: 7) {
                    FanfoldRefreshGlyph(color: .white)
                        .frame(width: 14, height: 14)
                    Text(refreshLabel)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.spoolInventoryPhase.isCollecting)
            .help(refreshHelp)
        }
        .padding(.horizontal, 15)
        .frame(height: 56)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var outputRunway: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                OutputFeedGlyph(color: AppPalette.registrationBlue)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OUTPUT RUNWAY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.registrationBlue)
                    Text("\(filteredFiles.count) of \(model.spoolOutputSnapshot.files.count) visible files")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                Text("ALL VISIBLE")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 52)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                TextField("file, job, user data, OUTQ…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                Text("⌘F")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }

            HStack(spacing: 0) {
                runwayMetric(value: "\(model.spoolOutputSnapshot.files.count)", label: "ROWS")
                runwayMetric(value: "\(heldCount)", label: "HELD", color: AppPalette.warning)
                runwayMetric(value: "\(messageWaitingCount)", label: "MSGW", color: AppPalette.danger)
                runwayMetric(value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file), label: "SIZE")
            }
            .frame(height: 68)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredFiles) { file in
                        SpoolLedgerRow(
                            file: file,
                            selected: file.identity == model.selectedSpoolFileID
                        ) {
                            model.selectSpooledFile(file)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            queuePressure
                .frame(height: 204)
        }
        .background(AppPalette.panel)
    }

    private func runwayMetric(value: String, label: String, color: Color = AppPalette.text) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppPalette.border).frame(width: 1)
        }
    }

    private var queuePressure: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("QUEUE PRESSURE")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                Spacer()
                Text("AT SNAPSHOT")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }

            ForEach(model.spoolOutputSnapshot.queues.prefix(4)) { queue in
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        Text(queue.identity.id)
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Text("\(queue.numberOfFiles) · \(queue.status.rawValue)")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(queue.status == .held ? AppPalette.danger : AppPalette.success)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(AppPalette.border)
                            Rectangle()
                                .fill(queue.status == .held ? AppPalette.danger : AppPalette.registrationBlue)
                                .frame(width: max(3, geometry.size.width * queueRatio(queue)))
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Text("\(queue.numberOfWriters) writer\(queue.numberOfWriters == 1 ? "" : "s")")
                        Spacer()
                        Text(queue.writerJobStatus ?? "NO WRITER STATE")
                    }
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                }
            }
        }
        .padding(12)
        .background(AppPalette.raised)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var documentWorkspace: some View {
        if let file = model.selectedSpooledFile {
            VStack(spacing: 0) {
                selectedFileHeader(file)
                previewModeTabs

                switch surface {
                case .preview:
                    previewSurface(file)
                case .compare:
                    comparisonSurface(file)
                case .attributes:
                    attributesSurface(file)
                }
            }
            .background(AppPalette.window)
        } else {
            ContentUnavailableView(
                "No spooled file selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Refresh a read-only inventory or choose a visible local replay row.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectedFileHeader(_ file: SpooledFileRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                SpooledDocumentGlyph(color: AppPalette.registrationBlue)
                    .frame(width: 20, height: 23)
                Text(file.identity.file.value)
                    .font(.system(size: 18, weight: .semibold))
                Text("#\(file.identity.number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                SpoolStatusPill(text: file.status.rawValue, color: statusColor(file.status))
                Spacer()
                Text("OPENED \(timestamp(file.creationTimestamp))")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }

            Text("\(file.identity.job.rawValue) · \(file.outputQueue?.id ?? "OUTPUT QUEUE UNAVAILABLE") · USRDTA \(file.userData ?? "UNAVAILABLE")")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .textSelection(.enabled)

            HStack(spacing: 13) {
                fileFact(file.totalPages.map { "\($0) PAGES/RECORDS" } ?? "COUNT UNAVAILABLE", color: AppPalette.registrationBlue)
                fileFact(file.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file).uppercased() } ?? "SIZE UNAVAILABLE")
                fileFact(file.formType ?? "FORM UNAVAILABLE")
                fileFact(file.availability?.rawValue ?? "SCHEDULE UNAVAILABLE")
                fileFact("TEXT RECORD VIEW", color: AppPalette.warning)
                Spacer()

                if model.spoolTextPreview?.identity != file.identity {
                    Button("Load exact text") {
                        if model.db2Phase.isConnected {
                            model.loadSelectedSpoolTextPreview()
                        } else {
                            model.presentDb2ConnectionDossier()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.spoolPreviewPhase.isLoading || !file.isContentAvailable)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(height: 94)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func fileFact(_ text: String, color: Color = AppPalette.secondary) -> some View {
        Text(text)
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var previewModeTabs: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(SpoolOutputSurface.allCases) { candidate in
                Button {
                    surface = candidate
                } label: {
                    Text(candidate.label)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(surface == candidate ? AppPalette.registrationBlue : AppPalette.muted)
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(surface == candidate ? AppPalette.registrationBlue : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Circle()
                .fill(previewPhaseColor)
                .frame(width: 6, height: 6)
            Text(model.spoolPreviewPhase.label)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(previewPhaseColor)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private func previewSurface(_ file: SpooledFileRecord) -> some View {
        VStack(spacing: 0) {
            if let preview = model.spoolTextPreview, preview.identity == file.identity {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("ORDERED TEXT RECORDS")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.55)
                            .foregroundStyle(AppPalette.registrationBlue)
                        Text("\(preview.records.count) RECORDS")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                        Text(preview.isComplete ? "COMPLETE WITHIN BOUND" : "BOUND REACHED")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(preview.isComplete ? AppPalette.success : AppPalette.warning)
                        Spacer()
                        Button { previewScale = max(0.75, previewScale - 0.1) } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.plain)
                        Text("\(Int(previewScale * 100))%")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .frame(width: 36)
                        Button { previewScale = min(1.4, previewScale + 0.1) } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(AppPalette.panel)

                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                Text("REC")
                                    .frame(width: 49, alignment: .trailing)
                                Rectangle().fill(AppPalette.terminalGreen).frame(width: 12)
                                Text("SPOOLED DATA · TEXT-RECORD VIEW")
                                    .padding(.leading, 10)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 7 * previewScale, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.terminalGreen)
                            .frame(minWidth: 760)
                            .frame(height: 24)
                            .background(AppPalette.terminal)

                            ForEach(preview.records) { record in
                                spoolRecordRow(record)
                                    .frame(minWidth: 760)
                            }
                        }
                        .background(AppPalette.panel)
                        .overlay {
                            Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1)
                        }
                        .padding(16)
                    }
                    .background(AppPalette.raised)
                }

                comparisonStrip
                    .frame(height: 76)
            } else if model.spoolPreviewPhase.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening bounded text records")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.spoolPreviewDiagnostic)
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 13) {
                    SpooledDocumentGlyph(color: AppPalette.muted)
                        .frame(width: 42, height: 48)
                    Text("Content remains unopened")
                        .font(.system(size: 17, weight: .semibold))
                    Text(model.spoolPreviewDiagnostic)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 540)
                    Button(model.db2Phase.isConnected ? "Load exact text preview" : "Connect read-only provider") {
                        if model.db2Phase.isConnected {
                            model.loadSelectedSpoolTextPreview()
                        } else {
                            model.presentDb2ConnectionDossier()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!file.isContentAvailable)
                    Text("SYSTOOLS.SPOOLED_FILE_DATA is invoked only by this explicit action and may be audited on IBM i.")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppPalette.raised)
            }
        }
    }

    private func spoolRecordRow(_ record: SpooledTextRecord) -> some View {
        let tone = recordTone(record.text)
        return HStack(spacing: 0) {
            Text(String(format: "%05d", record.ordinalPosition))
                .font(.system(size: 7.5 * previewScale, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .frame(width: 49, alignment: .trailing)
            Rectangle()
                .fill(tone.rail)
                .frame(width: 12)
            Text(record.text.isEmpty ? " " : record.text)
                .font(.system(size: 8.5 * previewScale, weight: .medium, design: .monospaced))
                .foregroundStyle(tone.text)
                .padding(.leading, 10)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .frame(height: max(20, 23 * previewScale))
        .background(tone.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border.opacity(0.7)).frame(height: 0.5)
        }
    }

    private func comparisonSurface(_ file: SpooledFileRecord) -> some View {
        Group {
            if let baseline = model.spoolComparisonBaseline,
               let current = model.spoolTextPreview,
               current.identity == file.identity,
               let comparison = model.spoolTextComparison {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        ComparisonTraceGlyph(color: AppPalette.registrationBlue)
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(comparison.isIdentical ? "TEXT RECORDS MATCH" : "TEXT RECORDS DIFFER")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(comparison.isIdentical ? AppPalette.success : AppPalette.warning)
                            Text("Two exact spool identities · ordinal-aligned local comparison")
                                .font(.system(size: 13, weight: .semibold))
                            Text(comparison.comparisonBasis)
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppPalette.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        compareMetric("\(comparison.changedOrdinalCount)", "CHANGED", AppPalette.registrationBlue)
                        compareMetric("+\(comparison.addedRecordCount)", "ADDED", AppPalette.success)
                        compareMetric("−\(comparison.removedRecordCount)", "REMOVED", AppPalette.danger)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 84)
                    .background(AppPalette.panel)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(AppPalette.border).frame(height: 1)
                    }

                    HStack(spacing: 1) {
                        comparisonPane(title: "BASELINE", preview: baseline, accent: AppPalette.muted)
                        comparisonPane(title: "CURRENT", preview: current, accent: AppPalette.registrationBlue)
                    }
                    .background(AppPalette.border)
                }
            } else {
                VStack(spacing: 13) {
                    ComparisonTraceGlyph(color: AppPalette.muted)
                        .frame(width: 48, height: 48)
                    Text("Freeze a local baseline")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Load the selected text, then freeze it in device memory. A later preview with the same spooled-file name can be compared without changing the host.")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 540)
                    Button("Freeze current preview") {
                        model.freezeSpoolPreviewAsBaseline()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.spoolTextPreview?.identity != file.identity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppPalette.raised)
            }
        }
    }

    private func comparisonPane(title: String, preview: SpooledTextPreview, accent: Color) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(accent)
                    Spacer()
                    Text("\(preview.records.count) RECORDS")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Text(preview.identity.description)
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(timestamp(preview.capturedAt))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(AppPalette.panel)

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(preview.records) { record in
                        HStack(spacing: 8) {
                            Text(String(format: "%05d", record.ordinalPosition))
                                .foregroundStyle(AppPalette.muted)
                                .frame(width: 42, alignment: .trailing)
                            Text(record.text.isEmpty ? " " : record.text)
                                .foregroundStyle(AppPalette.text)
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 7.5, design: .monospaced))
                        .frame(minWidth: 640, minHeight: 21, alignment: .leading)
                        .background(record.ordinalPosition == model.spoolTextComparison?.firstDifferenceOrdinal ? AppPalette.warning.opacity(0.13) : AppPalette.panel)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(AppPalette.border.opacity(0.55)).frame(height: 0.5)
                        }
                    }
                }
                .padding(12)
            }
            .background(AppPalette.raised)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compareMetric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(width: 58)
    }

    private func attributesSurface(_ file: SpooledFileRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                attributeSection("EXACT SPOOLED FILE IDENTITY", rows: [
                    ("Job", file.identity.job.rawValue),
                    ("File", file.identity.file.value),
                    ("Number", String(file.identity.number)),
                    ("System", file.identity.system?.value ?? "UNAVAILABLE"),
                    ("Output queue", file.outputQueue?.id ?? "UNAVAILABLE")
                ])
                attributeSection("FILE ATTRIBUTES", rows: [
                    ("Status", file.status.rawValue),
                    ("Created", timestamp(file.creationTimestamp)),
                    ("User data", file.userData ?? "UNAVAILABLE"),
                    ("Form type", file.formType ?? "UNAVAILABLE"),
                    ("Schedule", file.availability?.rawValue ?? "UNAVAILABLE"),
                    ("Output priority", file.outputPriority.map(String.init) ?? "UNAVAILABLE"),
                    ("Copies remaining", file.copies.map(String.init) ?? "UNAVAILABLE"),
                    ("Pages or records", file.totalPages.map(String.init) ?? "UNAVAILABLE"),
                    ("Size", file.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "UNAVAILABLE"),
                    ("ASP", file.aspNumber.map(String.init) ?? "UNAVAILABLE"),
                    ("IPP job ID", file.ippJobID.map(String.init) ?? "UNAVAILABLE")
                ])
                if let queue = model.selectedSpoolOutputQueue {
                    attributeSection("OUTPUT QUEUE AND FIRST WRITER", rows: [
                        ("Queue", queue.identity.id),
                        ("Queue status", queue.status.rawValue),
                        ("Files", String(queue.numberOfFiles)),
                        ("Writers", String(queue.numberOfWriters)),
                        ("Order", queue.orderOfFiles),
                        ("Display any file", queue.displayAnyFile),
                        ("Operator controlled", queue.operatorControlled ? "YES" : "NO"),
                        ("Authority check", queue.authorityToCheck),
                        ("First writer job", queue.writerJob?.rawValue ?? "UNAVAILABLE"),
                        ("Writer state", queue.writerJobStatus ?? "UNAVAILABLE"),
                        ("Writer type", queue.writerType ?? "UNAVAILABLE")
                    ])
                }
            }
            .padding(18)
        }
        .background(AppPalette.raised)
    }

    private func attributeSection(_ title: String, rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.registrationBlue)
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 1)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(row.0.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .frame(width: 140, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 34)
                .background(AppPalette.panel)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppPalette.border.opacity(0.75)).frame(height: 0.5)
                }
            }
        }
        .overlay {
            Rectangle().stroke(AppPalette.border, lineWidth: 1)
        }
    }

    private var comparisonStrip: some View {
        HStack(spacing: 14) {
            ComparisonTraceGlyph(color: Color(red: 0.47, green: 0.66, blue: 1))
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.spoolComparisonBaseline == nil ? "NO LOCAL BASELINE" : "LOCAL BASELINE AVAILABLE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
                Text(comparisonTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Text records only · exact spool identities remain visible")
                    .font(.system(size: 7.5))
                    .foregroundStyle(Color(red: 0.58, green: 0.67, blue: 0.62))
            }
            Spacer()
            if let comparison = model.spoolTextComparison {
                compareMetric("\(comparison.changedOrdinalCount)", "CHANGED", Color(red: 0.47, green: 0.66, blue: 1))
                compareMetric("+\(comparison.addedRecordCount)", "ADDED", AppPalette.terminalGreen)
                compareMetric("−\(comparison.removedRecordCount)", "REMOVED", Color(red: 1, green: 0.55, blue: 0.55))
            } else {
                Button("Freeze baseline") {
                    model.freezeSpoolPreviewAsBaseline()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .background(AppPalette.terminal)
        .onTapGesture {
            if model.spoolTextComparison != nil { surface = .compare }
        }
    }

    private var evidenceDossier: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SpoolEvidenceSeal()
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EVIDENCE DOSSIER")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(AppPalette.registrationBlue)
                        Text("Exact output identity")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle().fill(previewPhaseColor).frame(width: 7, height: 7)
                        Text(model.spoolPreviewPhase.label)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(previewPhaseColor)
                    }
                    Text("Inventory is passive; opening file content is an explicit, auditable read.")
                        .font(.system(size: 12, weight: .semibold))
                    Text("No hold, release, move, host spool-copy, writer, print, send, or delete operation is available here.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                        .lineSpacing(2)
                }
                .padding(12)
                .background(AppPalette.warning.opacity(0.11))
                .overlay {
                    Rectangle().stroke(AppPalette.warning.opacity(0.4), lineWidth: 1)
                }

                if let file = model.selectedSpooledFile {
                    dossierDivider("EXACT FILE IDENTITY")
                    dossierRow("JOB", file.identity.job.rawValue)
                    dossierRow("FILE", file.identity.file.value)
                    dossierRow("NUMBER", String(file.identity.number))
                    dossierRow("OUTQ", file.outputQueue?.id ?? "UNAVAILABLE")
                    dossierRow("SYSTEM", file.identity.system?.value ?? "UNAVAILABLE")

                    dossierDivider("PRINT ATTRIBUTES")
                    HStack(spacing: 12) {
                        dossierFact(file.formType ?? "—", "FORM")
                        dossierFact(file.availability?.rawValue ?? "—", "SCHEDULE")
                        dossierFact(file.outputPriority.map(String.init) ?? "—", "PRIORITY")
                        dossierFact(file.copies.map(String.init) ?? "—", "COPIES")
                    }

                    if let queue = model.selectedSpoolOutputQueue {
                        dossierDivider("QUEUE & FIRST WRITER")
                        dossierRow("STATE", queue.status.rawValue, color: queue.status == .held ? AppPalette.danger : AppPalette.success)
                        dossierRow("FILES", String(queue.numberOfFiles))
                        dossierRow("WRITERS", String(queue.numberOfWriters))
                        dossierRow("FIRST", queue.writerJob?.rawValue ?? "UNAVAILABLE")
                        dossierRow("WTR STATE", queue.writerJobStatus ?? "UNAVAILABLE")
                    }
                }

                dossierDivider("EVIDENCE RECEIPTS")
                ForEach(model.spoolOutputSnapshot.receipts) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Rectangle()
                                .fill(receipt.outcome.isCollected ? AppPalette.success : AppPalette.warning)
                                .frame(width: 3, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.source.rawValue)
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                Text(receipt.outcome.isCollected ? "\(receipt.rowCount) rows" : "Not collected")
                                    .font(.system(size: 7.5))
                                    .foregroundStyle(AppPalette.muted)
                            }
                            Spacer()
                            Text(receipt.boundWasReached ? "BOUND" : String(receipt.queryFingerprint.prefix(8)).uppercased())
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(receipt.boundWasReached ? AppPalette.warning : AppPalette.muted)
                        }
                        if case .unavailable(let reason) = receipt.outcome {
                            Text(reason)
                                .font(.system(size: 7.5))
                                .foregroundStyle(AppPalette.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 3)
                }

                dossierDivider("REVIEWED ACTIONS")
                Button {
                    if model.db2Phase.isConnected {
                        model.loadSelectedSpoolTextPreview()
                    } else {
                        model.presentDb2ConnectionDossier()
                    }
                } label: {
                    HStack(spacing: 7) {
                        OutputFeedGlyph(color: .white)
                            .frame(width: 15, height: 15)
                        Text(loadPreviewLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.spoolPreviewPhase.isLoading || model.selectedSpooledFile?.isContentAvailable == false)

                HStack(spacing: 8) {
                    Button("Copy text") { model.copySpoolPreviewText() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Export .txt") { model.exportSpoolPreviewText() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .disabled(model.spoolTextPreview?.identity != model.selectedSpoolFileID)

                Button {
                    model.prepareSpoolAssist()
                } label: {
                    HStack(spacing: 7) {
                        UtilityGlyph(kind: .assistant, color: .white, size: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Pin to Assist Shelf")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Exact evidence · local until send")
                                .font(.system(size: 6.8, design: .monospaced))
                                .opacity(0.82)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Text("Pinned evidence remains local until you send from Assist. Text-record fidelity limits remain attached.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.muted)
                    .lineSpacing(2)
            }
            .padding(13)
        }
        .background(AppPalette.panel)
    }

    private func dossierDivider(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.65)
                .foregroundStyle(AppPalette.muted)
        }
    }

    private func dossierRow(_ label: String, _ value: String, color: Color = AppPalette.text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    private func dossierFact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 5.8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusStrip: some View {
        HStack(spacing: 15) {
            Text("INVENTORY: \(model.spoolInventoryPhase.label)")
                .foregroundStyle(inventoryPhaseColor)
            Text("PREVIEW: \(model.spoolPreviewPhase.label)")
                .foregroundStyle(previewPhaseColor)
            Text("HOST WRITE: NONE")
                .foregroundStyle(AppPalette.terminalGreen)
            Text(model.spoolPreviewPhase == .failed ? model.spoolPreviewDiagnostic : model.spoolInventoryDiagnostic)
                .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("ARM64 · NATIVE")
                .foregroundStyle(.white)
        }
        .font(.system(size: 7.5, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }

    private var filteredFiles: [SpooledFileRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.spoolOutputSnapshot.files }
        return model.spoolOutputSnapshot.files.filter { file in
            [
                file.identity.job.rawValue,
                file.identity.file.value,
                String(file.identity.number),
                file.identity.system?.value ?? "",
                file.status.rawValue,
                file.outputQueue?.id ?? "",
                file.userData ?? "",
                file.formType ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var heldCount: Int {
        model.spoolOutputSnapshot.files.filter { $0.status == .held }.count
    }

    private var messageWaitingCount: Int {
        model.spoolOutputSnapshot.files.filter { $0.status == .messageWaiting }.count
    }

    private var totalBytes: Int64 {
        model.spoolOutputSnapshot.files.compactMap(\.sizeBytes).reduce(0, +)
    }

    private var inventoryPhaseColor: Color {
        switch model.spoolInventoryPhase {
        case .localReplay: AppPalette.registrationBlue
        case .collecting: AppPalette.warning
        case .ready: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var previewPhaseColor: Color {
        switch model.spoolPreviewPhase {
        case .localReplay: AppPalette.registrationBlue
        case .notLoaded: AppPalette.warning
        case .loading: AppPalette.warning
        case .ready: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var refreshLabel: String {
        if model.spoolInventoryPhase.isCollecting { return "Collecting…" }
        return model.db2Phase.isConnected ? "Refresh inventory" : "Connect Read-only"
    }

    private var refreshHelp: String {
        model.db2Phase.isConnected
            ? "Run bounded SPOOLED_FILE_INFO and OUTPUT_QUEUE_INFO requests without opening file content"
            : "Open the Db2 connection dossier; no query runs automatically"
    }

    private var loadPreviewLabel: String {
        if model.spoolPreviewPhase.isLoading { return "Opening text…" }
        if model.db2Phase.isConnected { return "Load exact text preview" }
        return "Connect for exact text"
    }

    private var comparisonTitle: String {
        guard let comparison = model.spoolTextComparison else {
            return "Freeze the current text to compare a later run."
        }
        return comparison.isIdentical
            ? "Current records match the frozen baseline."
            : "Content changed across the two exact spool identities."
    }

    private func queueRatio(_ queue: OutputQueueRecord) -> CGFloat {
        let maximum = max(1, model.spoolOutputSnapshot.queues.map(\.numberOfFiles).max() ?? 1)
        return min(1, CGFloat(queue.numberOfFiles) / CGFloat(maximum))
    }

    private func timestamp(_ date: Date?) -> String {
        guard let date else { return "TIME UNAVAILABLE" }
        return date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
    }

    private func statusColor(_ status: SpooledFileStatus) -> Color {
        switch status {
        case .held, .deferred, .pending: AppPalette.warning
        case .messageWaiting, .deleted: AppPalette.danger
        case .ready, .saved: AppPalette.success
        case .closed, .open, .printing, .sending, .writing: AppPalette.registrationBlue
        }
    }

    private func recordTone(_ text: String) -> (background: Color, rail: Color, text: Color) {
        let upper = text.uppercased()
        if upper.contains(" ESCAPE ") || upper.hasPrefix("CPF") {
            return (AppPalette.danger.opacity(0.08), AppPalette.danger, Color(red: 0.55, green: 0.07, blue: 0.09))
        }
        if upper.contains(" INQUIRY ") || upper.hasPrefix("RNQ") {
            return (AppPalette.warning.opacity(0.10), AppPalette.warning, AppPalette.text)
        }
        return (AppPalette.panel, AppPalette.raised, AppPalette.text)
    }
}

private enum SpoolOutputSurface: String, CaseIterable, Identifiable {
    case preview
    case compare
    case attributes

    var id: Self { self }

    var label: String {
        switch self {
        case .preview: "TEXT PREVIEW"
        case .compare: "COMPARE"
        case .attributes: "ATTRIBUTES"
        }
    }
}

private struct SpoolStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: ChamferedRectangle(cut: 3))
        .overlay {
            ChamferedRectangle(cut: 3).stroke(color.opacity(0.35), lineWidth: 0.7)
        }
    }
}

private struct SpoolLedgerRow: View {
    let file: SpooledFileRecord
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: selected ? 4 : 3, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(file.identity.file.value)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        Text("#\(file.identity.number)")
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                        Spacer()
                        Text(shortTime(file.creationTimestamp))
                            .font(.system(size: 6.8, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    }
                    Text(file.identity.job.rawValue)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(file.status.rawValue)
                            .foregroundStyle(statusColor)
                        if let queue = file.outputQueue {
                            Text("· \(queue.id)")
                                .foregroundStyle(AppPalette.muted)
                        }
                    }
                    .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 56)
            .background(selected ? AppPalette.registrationBlue.opacity(0.09) : AppPalette.panel)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette.border).frame(height: 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(file.identity.file.value) number \(file.identity.number), \(file.identity.job.rawValue), \(file.status.rawValue)")
    }

    private var statusColor: Color {
        switch file.status {
        case .held, .deferred, .pending: AppPalette.warning
        case .messageWaiting, .deleted: AppPalette.danger
        case .ready, .saved: AppPalette.success
        case .closed, .open, .printing, .sending, .writing: AppPalette.registrationBlue
        }
    }

    private func shortTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct FanfoldOutputMark: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AppPalette.terminal))
            let stroke = StrokeStyle(lineWidth: 1.4, lineCap: .square, lineJoin: .bevel)
            var paper = Path()
            paper.move(to: CGPoint(x: size.width * 0.27, y: size.height * 0.12))
            paper.addLine(to: CGPoint(x: size.width * 0.68, y: size.height * 0.12))
            paper.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.29))
            paper.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.86))
            paper.addLine(to: CGPoint(x: size.width * 0.27, y: size.height * 0.86))
            paper.closeSubpath()
            context.stroke(paper, with: .color(AppPalette.terminalGreen), style: stroke)
            for y in [0.39, 0.56, 0.72] {
                var line = Path()
                line.move(to: CGPoint(x: size.width * 0.39, y: size.height * y))
                line.addLine(to: CGPoint(x: size.width * (y == 0.72 ? 0.63 : 0.72), y: size.height * y))
                context.stroke(line, with: .color(AppPalette.terminalGreen.opacity(0.8)), style: StrokeStyle(lineWidth: 1))
            }
            for y in [0.28, 0.5, 0.72] {
                context.fill(
                    Path(ellipseIn: CGRect(x: size.width * 0.08, y: size.height * y, width: 3, height: 3)),
                    with: .color(AppPalette.warning)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SpooledDocumentGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: max(1, size.width * 0.07), lineCap: .square, lineJoin: .bevel)
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.04))
            path.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.04))
            path.addLine(to: CGPoint(x: size.width * 0.9, y: size.height * 0.26))
            path.addLine(to: CGPoint(x: size.width * 0.9, y: size.height * 0.96))
            path.addLine(to: CGPoint(x: size.width * 0.12, y: size.height * 0.96))
            path.closeSubpath()
            context.stroke(path, with: .color(color), style: stroke)
            for y in [0.44, 0.62, 0.8] {
                var line = Path()
                line.move(to: CGPoint(x: size.width * 0.31, y: size.height * y))
                line.addLine(to: CGPoint(x: size.width * (y == 0.8 ? 0.65 : 0.73), y: size.height * y))
                context.stroke(line, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OutputFeedGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.1, lineCap: .square)
            for y in [0.2, 0.5, 0.8] {
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.08, y: size.height * y))
                path.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * y))
                context.stroke(path, with: .color(color.opacity(y == 0.5 ? 1 : 0.55)), style: stroke)
            }
            for x in [0.28, 0.72] {
                var path = Path()
                path.move(to: CGPoint(x: size.width * x, y: size.height * 0.05))
                path.addLine(to: CGPoint(x: size.width * x, y: size.height * 0.95))
                context.stroke(path, with: .color(color), style: stroke)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FanfoldRefreshGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.2, lineCap: .square, lineJoin: .miter)
            var path = Path()
            path.addArc(
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.52),
                radius: size.width * 0.32,
                startAngle: .degrees(-55),
                endAngle: .degrees(250),
                clockwise: false
            )
            context.stroke(path, with: .color(color), style: stroke)
            var arrow = Path()
            arrow.move(to: CGPoint(x: size.width * 0.17, y: size.height * 0.55))
            arrow.addLine(to: CGPoint(x: size.width * 0.16, y: size.height * 0.82))
            arrow.addLine(to: CGPoint(x: size.width * 0.39, y: size.height * 0.72))
            context.stroke(arrow, with: .color(color), style: stroke)
        }
        .accessibilityHidden(true)
    }
}

private struct ComparisonTraceGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: max(1, size.width * 0.045), lineCap: .square, lineJoin: .miter)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
            var path = Path()
            path.move(to: point(0.06, 0.22))
            path.addLine(to: point(0.36, 0.22))
            path.addLine(to: point(0.5, 0.08))
            path.move(to: point(0.36, 0.22))
            path.addLine(to: point(0.5, 0.36))
            path.move(to: point(0.94, 0.78))
            path.addLine(to: point(0.64, 0.78))
            path.addLine(to: point(0.5, 0.64))
            path.move(to: point(0.64, 0.78))
            path.addLine(to: point(0.5, 0.92))
            path.move(to: point(0.2, 0.5))
            path.addLine(to: point(0.8, 0.5))
            context.stroke(path, with: .color(color), style: stroke)
        }
        .accessibilityHidden(true)
    }
}

private struct SpoolEvidenceSeal: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FanfoldOutputMark()
            Rectangle()
                .fill(AppPalette.warning)
                .frame(width: 6, height: 6)
                .offset(x: -2, y: 2)
        }
        .accessibilityHidden(true)
    }
}
