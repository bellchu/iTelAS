import SwiftUI
import UniformTypeIdentifiers
import iTelASCore

struct DataTransferView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var selectedSurface = TransferSurface.mapping
    @State private var isImporterPresented = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                workspaceHeader
                HStack(spacing: 0) {
                    planRail
                        .frame(width: geometry.size.width < 1_250 ? 250 : 282)
                    divider
                    validationWorkspace
                    if geometry.size.width >= 1_180 {
                        divider
                        validationDossier
                            .frame(width: geometry.size.width >= 1_420 ? 336 : 310)
                    }
                }
                statusStrip
            }
            .background(AppPalette.window)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data]
        ) { result in
            importSource(result)
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            TransferIntegrityMark(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("OPERATIONS / TRANSFER INTEGRITY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Data Transfer")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            Spacer()
            EnvironmentBadge(environment: model.db2Receipt?.environment ?? .development)
            stateBadge
            Button {
                if model.db2Phase.isConnected {
                    model.refreshTransferTargetSchema()
                } else {
                    model.presentDb2ConnectionDossier()
                }
            } label: {
                Label(schemaActionLabel, systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.transferSchemaPhase.isCollecting)

            Button {
                isImporterPresented = true
            } label: {
                Label("Profile local CSV", systemImage: "doc.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.transferValidationPhase.isBusy)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var stateBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(validationColor)
                .frame(width: 6, height: 6)
            Text(model.transferValidationPhase.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.45)
        }
        .foregroundStyle(validationColor)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(validationColor.opacity(0.07))
        .overlay { ChamferedRectangle(cut: 3).stroke(validationColor, lineWidth: 0.8) }
        .clipShape(ChamferedRectangle(cut: 3))
    }

    private var planRail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                WorkbenchGlyph(tool: .transferCenter, color: AppPalette.registrationBlue, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FLIGHT PLANS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("1 active dry run · recipe studies below")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                Text("LOCAL")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 58)
            .background(AppPalette.panel)

            searchBar
            metricStrip

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPlans) { plan in
                        transferPlanRow(plan)
                    }
                }
            }
            .frame(maxHeight: 310)
            .background(AppPalette.panel)

            riskAnatomy
        }
        .background(AppPalette.raised)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            TextField("file, table, recipe, issue", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 9.5))
            Text("⌘F")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { divider.frame(height: 1) }
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var metricStrip: some View {
        HStack(spacing: 0) {
            metric("ROWS", value: model.transferValidationReport.source.rowCount.formatted(), color: AppPalette.text)
            divider
            metric("BLOCKERS", value: "\(model.transferValidationReport.blockerCount)", color: model.transferValidationReport.blockerCount == 0 ? AppPalette.success : AppPalette.danger)
            divider
            metric("WARNINGS", value: "\(model.transferValidationReport.warningCount)", color: model.transferValidationReport.warningCount == 0 ? AppPalette.text : AppPalette.warning)
            divider
            metric("COLUMNS", value: "\(model.transferValidationReport.mappings.count)", color: AppPalette.text)
        }
        .frame(height: 70)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func metric(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transferPlanRow(_ plan: TransferPlanSummary) -> some View {
        let selected = plan.id == model.selectedTransferPlanID
        return HStack(spacing: 10) {
            Rectangle()
                .fill(planColor(plan))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(plan.title.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                    Text(plan.direction)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Text(plan.target)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                Text("\(plan.state.rawValue) · \(plan.detail)")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(planColor(plan))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 70)
        .background(selected ? AppPalette.ibmBlue.opacity(0.08) : AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.title), \(plan.direction), \(plan.target), \(plan.state.rawValue), \(plan.detail)")
    }

    private var riskAnatomy: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("RISK ANATOMY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.secondary)
                Spacer()
                Text("DRY RUN")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            riskRow("CCSID / ENCODING", codes: [.unrepresentableText, .unsupportedCCSID], detail: "lossless round-trip required")
            riskRow("DATE CONTRACT", codes: [.ambiguousDate], detail: "ISO YYYY-MM-DD only")
            riskRow("WIDTH / DECIMAL", codes: [.truncation, .decimalOverflow, .integerOverflow], detail: "silent loss rejected")
            riskRow("DOMAIN / NULL", codes: [.domainEvidenceMissing, .blankValuesPreserved], detail: "explicit policy evidence")
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(AppPalette.raised)
    }

    private func riskRow(_ label: String, codes: Set<TransferIssueCode>, detail: String) -> some View {
        let issues = model.transferValidationReport.issues.filter { codes.contains($0.code) }
        let blockers = issues.filter { $0.severity == .blocker }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        let color = blockers > 0 ? AppPalette.danger : warnings > 0 ? AppPalette.warning : AppPalette.success
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Spacer()
                Text(blockers > 0 ? "\(blockers) BLOCK" : warnings > 0 ? "\(warnings) WARN" : "READY")
                    .font(.system(size: 6.6, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppPalette.border).frame(height: 5)
                    Rectangle()
                        .fill(color)
                        .frame(width: proxy.size.width * riskWidth(blockers: blockers, warnings: warnings), height: 5)
                }
            }
            .frame(height: 5)
            Text(detail)
                .font(.system(size: 7.5))
                .foregroundStyle(AppPalette.muted)
        }
    }

    private var validationWorkspace: some View {
        VStack(spacing: 0) {
            selectedTransferHeader
            surfaceTabs
            Group {
                switch selectedSurface {
                case .mapping: mappingSurface
                case .exceptions: exceptionSurface
                case .receipt: receiptSurface
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            validationSummary
                .frame(height: 84)
        }
        .background(AppPalette.panel)
    }

    private var selectedTransferHeader: some View {
        let report = model.transferValidationReport
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                MappingRouteGlyph()
                    .stroke(AppPalette.registrationBlue, style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter))
                    .frame(width: 28, height: 28)
                Text(report.source.fileName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text("CSV → TABLE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                verdictBadge(report.blockerCount == 0 ? .ready : .blocked)
                Spacer()
                Text("PROFILED \(report.createdAt.formatted(date: .numeric, time: .standard))")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 45)

            HStack(spacing: 13) {
                Text(report.source.fileName)
                Text("·")
                Text(report.target.targetName)
                Text("·")
                Text(report.target.table.description)
                Spacer()
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.secondary)
            .padding(.horizontal, 16)
            .frame(height: 22)

            HStack(spacing: 18) {
                fact("\(report.source.rowCount.formatted()) ROWS", AppPalette.ibmBlue)
                fact("\(report.source.columns.count) COLUMNS", AppPalette.secondary)
                fact("UTF-8", AppPalette.secondary)
                fact(report.source.dialect.label, AppPalette.secondary)
                fact("\(report.blockerCount) BLOCKERS", report.blockerCount == 0 ? AppPalette.success : AppPalette.warning)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 25)
        }
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func fact(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(color)
    }

    private var surfaceTabs: some View {
        HStack(spacing: 0) {
            ForEach(TransferSurface.allCases) { surface in
                Button {
                    selectedSurface = surface
                } label: {
                    VStack(spacing: 8) {
                        Text(surface.label(report: model.transferValidationReport))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(selectedSurface == surface ? AppPalette.ibmBlue : AppPalette.muted)
                        Rectangle()
                            .fill(selectedSurface == surface ? AppPalette.ibmBlue : .clear)
                            .frame(height: 1.5)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("NO HOST WRITE · DRY RUN ONLY")
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.warning)
                .padding(.trailing, 14)
        }
        .frame(height: 43)
        .background(AppPalette.raised.opacity(0.55))
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var mappingSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tableHeader("#", width: 38, alignment: .trailing)
                tableHeader("SOURCE / SAMPLE", width: 210)
                tableHeader("INFERRED", width: 112)
                tableHeader("TARGET CONTRACT", width: 245)
                tableHeader("VERDICT", width: 98)
                Spacer(minLength: 0)
            }
            .frame(height: 29)
            .background(AppPalette.terminal)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.transferValidationReport.mappings) { mapping in
                        mappingRow(mapping)
                    }
                }
            }
            .background(AppPalette.panel)
        }
        .padding(16)
        .background(AppPalette.raised)
    }

    private func tableHeader(_ text: String, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(AppPalette.terminalGreen)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 7)
    }

    private func mappingRow(_ mapping: TransferColumnMapping) -> some View {
        let background = mapping.verdict == .blocked
            ? AppPalette.danger.opacity(0.055)
            : mapping.verdict == .warning ? AppPalette.warning.opacity(0.08) : AppPalette.panel
        return HStack(spacing: 0) {
            Text(String(format: "%02d", mapping.source.ordinalPosition))
                .frame(width: 38, alignment: .trailing)
                .foregroundStyle(AppPalette.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(mapping.source.header)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppPalette.text)
                Text(sampleText(mapping.source))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            .frame(width: 210, alignment: .leading)
            .padding(.horizontal, 7)
            Text(mapping.source.inferredKind.label)
                .frame(width: 112, alignment: .leading)
                .foregroundStyle(AppPalette.secondary)
                .padding(.horizontal, 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(mapping.target?.name ?? "NO UNIQUE TARGET")
                    .fontWeight(.semibold)
                    .foregroundStyle(mapping.target == nil ? AppPalette.danger : AppPalette.text)
                Text(mapping.target?.typeDisplay ?? "mapping required")
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            .frame(width: 245, alignment: .leading)
            .padding(.horizontal, 7)
            verdictBadge(mapping.verdict)
                .frame(width: 98, alignment: .leading)
                .padding(.horizontal, 7)
            Spacer(minLength: 0)
        }
        .font(.system(size: 8, design: .monospaced))
        .frame(height: 54)
        .background(background)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source \(mapping.source.header), inferred \(mapping.source.inferredKind.label), target \(mapping.target?.name ?? "not mapped"), verdict \(mapping.verdict.rawValue)")
    }

    private func verdictBadge(_ verdict: TransferMappingVerdict) -> some View {
        let color: Color = switch verdict {
        case .ready: AppPalette.success
        case .warning: AppPalette.warning
        case .blocked: AppPalette.danger
        }
        return Text(verdict.rawValue)
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(color.opacity(0.07))
            .overlay { ChamferedRectangle(cut: 3).stroke(color, lineWidth: 0.7) }
            .clipShape(ChamferedRectangle(cut: 3))
    }

    private var exceptionSurface: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.transferValidationReport.issues.isEmpty {
                    ContentUnavailableView(
                        "No mapping exceptions",
                        systemImage: "checkmark.seal",
                        description: Text("The local profile has no recorded blocker, warning, or information item.")
                    )
                    .frame(height: 260)
                } else {
                    ForEach(model.transferValidationReport.issues) { issue in
                        issueRow(issue)
                    }
                }
            }
            .padding(16)
        }
        .background(AppPalette.raised)
    }

    private func issueRow(_ issue: TransferIssue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle().fill(issueColor(issue.severity)).frame(width: 8, height: 8)
                Rectangle().fill(issueColor(issue.severity).opacity(0.28)).frame(width: 1, height: 44)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(issue.severity.rawValue)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(issueColor(issue.severity))
                    Text(issue.code.rawValue.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                    if let row = issue.rowNumber {
                        Text("ROW \(row)")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.ibmBlue)
                    }
                    Spacer()
                    Text([issue.sourceHeader, issue.targetColumn].compactMap { $0 }.joined(separator: " → "))
                        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                }
                Text(issue.message)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let sample = issue.sampleValue {
                    Text("LOCAL SAMPLE · \(boundedSample(sample))")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(13)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var receiptSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.transferValidationReport.receipts) { receipt in
                receiptRow(receipt, spacious: true)
            }
            Spacer()
            Text("Receipts prove what was profiled and what was not. They do not authorize a target write.")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.secondary)
                .padding(16)
        }
        .background(AppPalette.raised)
    }

    private var validationSummary: some View {
        let report = model.transferValidationReport
        return HStack(spacing: 15) {
            MappingRouteGlyph()
                .stroke(AppPalette.registrationBlue, style: StrokeStyle(lineWidth: 1.4, lineCap: .square))
                .frame(width: 40, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("LOCAL PROFILE · \(short(report.source.sha256))")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
                Text(summaryTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("No ambiguous coercion, lossy substitution, truncation, or target write is available.")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(red: 0.58, green: 0.65, blue: 0.61))
            }
            Spacer()
            summaryMetric(report.source.rowCount.formatted(), "ROWS PROFILED", AppPalette.terminalGreen)
            summaryMetric("\(report.blockerCount)", "BLOCKERS", Color(red: 1, green: 0.62, blue: 0.62))
            summaryMetric("0", "HOST WRITES", Color(red: 0.47, green: 0.66, blue: 1))
        }
        .padding(.horizontal, 18)
        .background(AppPalette.terminal)
    }

    private func summaryMetric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.58, green: 0.65, blue: 0.61))
        }
        .frame(width: 80)
    }

    private var validationDossier: some View {
        @Bindable var model = model
        let report = model.transferValidationReport
        return VStack(spacing: 0) {
            HStack(spacing: 11) {
                TransferIntegrityMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VALIDATION DOSSIER")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Exact transfer contract")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 76)
            .background(AppPalette.panel)

            ScrollView {
                VStack(spacing: 0) {
                    assessmentBlock
                    dossierSection("TRANSFER IDENTITY") {
                        VStack(spacing: 9) {
                            dossierFact("SOURCE", report.source.fileName)
                            HStack(spacing: 8) {
                                targetField("LIBRARY", text: Binding(
                                    get: { model.transferTargetLibraryText },
                                    set: { model.editTransferTargetLibrary($0) }
                                ))
                                targetField("TABLE", text: Binding(
                                    get: { model.transferTargetTableText },
                                    set: { model.editTransferTargetTable($0) }
                                ))
                            }
                            dossierFact("SYSTEM", report.target.targetName)
                            dossierFact("MODE", "SCHEMA-ONLY DRY RUN")
                        }
                    }
                    dossierSection("TARGET SCHEMA") {
                        VStack(spacing: 9) {
                            dossierFact("STATE", model.transferSchemaPhase.label, valueColor: schemaColor)
                            dossierFact("COLUMNS", "\(report.target.columns.count)")
                            dossierFact("TABLE", report.target.table.description)
                            dossierFact("CAPTURED", report.target.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    dossierSection("SOURCE CONTRACT") {
                        HStack(spacing: 0) {
                            contractMetric("CSV", "FORMAT")
                            contractMetric("UTF-8", "ENCODING")
                            contractMetric("COMMA", "DELIMITER")
                            contractMetric("YES", "HEADER")
                        }
                    }
                    dossierSection("EVIDENCE RECEIPTS") {
                        VStack(spacing: 0) {
                            ForEach(report.receipts) { receipt in
                                receiptRow(receipt, spacious: false)
                            }
                        }
                    }
                }
            }

            dossierActions
        }
        .background(AppPalette.panel)
    }

    private var assessmentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(validationColor).frame(width: 7, height: 7)
                Text("DRY RUN · WRITE NOT AUTHORIZED")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.transferValidationReport.blockerCount == 0 ? AppPalette.success : Color(red: 0.54, green: 0.39, blue: 0))
            }
            Text(summaryTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppPalette.text)
            Text("No insert, update, merge, create-table, upload, or IFS write action is available.")
                .font(.system(size: 8.5))
                .foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.warning.opacity(0.14))
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func dossierSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AppPalette.muted)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func dossierFact(_ label: String, _ value: String, valueColor: Color = AppPalette.text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func targetField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(AppPalette.raised)
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.7) }
                .clipShape(ChamferedRectangle(cut: 3))
        }
        .frame(maxWidth: .infinity)
    }

    private func contractMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
            Text(label)
                .font(.system(size: 5.7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func receiptRow(_ receipt: TransferEvidenceReceipt, spacious: Bool) -> some View {
        let collected = receipt.outcome.isCollected
        return HStack(spacing: 10) {
            Rectangle()
                .fill(collected ? AppPalette.success : AppPalette.warning)
                .frame(width: 3, height: spacious ? 42 : 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.source.rawValue)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Text(receiptDetail(receipt))
                    .font(.system(size: 7.5))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(spacious ? 2 : 1)
            }
            Spacer()
            Text(short(receipt.fingerprint))
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .foregroundStyle(collected ? AppPalette.success : AppPalette.warning)
        }
        .padding(.vertical, spacious ? 8 : 6)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var dossierActions: some View {
        VStack(spacing: 8) {
            Button {
                model.exportTransferValidationReport()
            } label: {
                Label("Export validation report", systemImage: "doc.badge.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 8) {
                Button("Restore replay") { model.restoreTransferReplay() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Pin to Assist Shelf") { model.prepareTransferAssist() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)

            Text("Local profiling, export, and Assist never write target data.")
                .font(.system(size: 7.5))
                .foregroundStyle(AppPalette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(AppPalette.panel)
        .overlay(alignment: .top) { divider.frame(height: 1) }
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Text("SOURCE: \(model.transferValidationReport.source.rowCount.formatted()) ROWS")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("TARGET: \(model.transferValidationReport.target.columns.count) COLUMNS")
                .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 1))
            Text("HOST WRITES: NONE")
                .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.45))
            Text(model.transferDiagnostic)
                .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .foregroundStyle(Color(red: 0.58, green: 0.65, blue: 0.61))
                .lineLimit(1)
            Text("ARM64 · NATIVE")
                .foregroundStyle(.white)
        }
        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private var divider: some View {
        Rectangle().fill(AppPalette.border).frame(width: 1)
    }

    private var filteredPlans: [TransferPlanSummary] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return DataTransferSamples.plans }
        return DataTransferSamples.plans.filter {
            "\($0.title) \($0.direction) \($0.target) \($0.state.rawValue) \($0.detail)".lowercased().contains(needle)
        }
    }

    private var validationColor: Color {
        switch model.transferValidationPhase {
        case .localReplay: AppPalette.registrationBlue
        case .profiling: AppPalette.warning
        case .ready: AppPalette.success
        case .blocked, .failed: AppPalette.danger
        }
    }

    private var schemaColor: Color {
        switch model.transferSchemaPhase {
        case .localReplay: AppPalette.registrationBlue
        case .collecting: AppPalette.warning
        case .ready: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var schemaActionLabel: String {
        if model.transferSchemaPhase.isCollecting { return "Reading schema…" }
        return model.db2Phase.isConnected ? "Refresh target schema" : "Connect for schema"
    }

    private var summaryTitle: String {
        let report = model.transferValidationReport
        if report.blockerCount > 0 {
            return "\(report.blockerCount) blocker\(report.blockerCount == 1 ? "" : "s") prevent a trustworthy transfer."
        }
        if !model.transferSchemaIsCurrent {
            return "The mapping is locally valid, but target schema evidence is stale."
        }
        return "The mapping is locally valid; execution remains unavailable."
    }

    private func planColor(_ plan: TransferPlanSummary) -> Color {
        switch plan.state {
        case .blocked: AppPalette.danger
        case .ready: AppPalette.success
        case .validated: AppPalette.registrationBlue
        case .draft: AppPalette.muted
        }
    }

    private func issueColor(_ severity: TransferIssueSeverity) -> Color {
        switch severity {
        case .blocker: AppPalette.danger
        case .warning: AppPalette.warning
        case .information: AppPalette.registrationBlue
        }
    }

    private func riskWidth(blockers: Int, warnings: Int) -> CGFloat {
        if blockers > 0 { return 0.72 }
        if warnings > 0 { return 0.42 }
        return 0.28
    }

    private func sampleText(_ source: TransferSourceColumnProfile) -> String {
        guard let sample = source.sampleValues.first else { return "<blank only>" }
        return "“\(boundedSample(sample))”"
    }

    private func boundedSample(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\r\n", with: "↵")
            .replacingOccurrences(of: "\r", with: "↵")
            .replacingOccurrences(of: "\n", with: "↵")
            .replacingOccurrences(of: "\t", with: "⇥")
        return singleLine.count > 28 ? String(singleLine.prefix(27)) + "…" : singleLine
    }

    private func short(_ fingerprint: String?) -> String {
        guard let fingerprint else { return "—" }
        return "\(fingerprint.prefix(7))…\(fingerprint.suffix(4))"
    }

    private func receiptDetail(_ receipt: TransferEvidenceReceipt) -> String {
        switch receipt.outcome {
        case .collected:
            let elapsed = receipt.elapsedMilliseconds.map { " · \($0) ms" } ?? ""
            return "\(receipt.itemCount.formatted()) item(s)\(elapsed)"
        case .unavailable(let reason):
            return reason
        }
    }

    private func importSource(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            model.transferValidationPhase = .failed
            model.transferDiagnostic = "Local source selection failed: \(error.localizedDescription)"
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = values.fileSize,
                   fileSize > DataTransferLimits.standard.maximumSourceBytes {
                    throw DataTransferError.sourceTooLarge(maximum: DataTransferLimits.standard.maximumSourceBytes)
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                model.importTransferSource(data, fileName: url.lastPathComponent)
            } catch {
                model.transferValidationPhase = .failed
                model.transferDiagnostic = "Local source import was blocked: \(error.localizedDescription)"
                model.showNotice("The local transfer source was rejected.")
            }
        }
    }
}

private enum TransferSurface: String, CaseIterable, Identifiable {
    case mapping
    case exceptions
    case receipt

    var id: Self { self }

    func label(report: TransferValidationReport) -> String {
        switch self {
        case .mapping: "MAPPING MATRIX"
        case .exceptions: "EXCEPTIONS · \(report.issues.count)"
        case .receipt: "RECEIPTS · \(report.receipts.count)"
        }
    }
}

private struct TransferIntegrityMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let scale = min(canvas.width, canvas.height)
            let inset = scale * 0.08
            let rect = CGRect(x: inset, y: inset, width: scale - inset * 2, height: scale - inset * 2)
            context.fill(Path(rect), with: .color(AppPalette.terminal))

            var upper = Path()
            upper.move(to: CGPoint(x: rect.minX + scale * 0.12, y: rect.minY + scale * 0.28))
            upper.addLine(to: CGPoint(x: rect.maxX - scale * 0.13, y: rect.minY + scale * 0.28))
            upper.addLine(to: CGPoint(x: rect.maxX - scale * 0.26, y: rect.minY + scale * 0.16))
            context.stroke(upper, with: .color(AppPalette.registrationBlue), style: StrokeStyle(lineWidth: max(1, scale * 0.055), lineCap: .square, lineJoin: .miter))

            var lower = Path()
            lower.move(to: CGPoint(x: rect.maxX - scale * 0.12, y: rect.maxY - scale * 0.28))
            lower.addLine(to: CGPoint(x: rect.minX + scale * 0.13, y: rect.maxY - scale * 0.28))
            lower.addLine(to: CGPoint(x: rect.minX + scale * 0.26, y: rect.maxY - scale * 0.16))
            context.stroke(lower, with: .color(AppPalette.terminalGreen), style: StrokeStyle(lineWidth: max(1, scale * 0.055), lineCap: .square, lineJoin: .miter))

            let gate = CGRect(x: rect.midX - scale * 0.075, y: rect.midY - scale * 0.075, width: scale * 0.15, height: scale * 0.15)
            context.fill(Path(gate), with: .color(.white))
            context.stroke(Path(gate.insetBy(dx: -scale * 0.035, dy: -scale * 0.035)), with: .color(AppPalette.warning), lineWidth: max(1, scale * 0.025))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct MappingRouteGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX + rect.width * 0.08
        let right = rect.maxX - rect.width * 0.08
        let mid = rect.midY
        path.move(to: CGPoint(x: left, y: rect.minY + rect.height * 0.27))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.minY + rect.height * 0.27))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.08, y: mid))
        path.addLine(to: CGPoint(x: right, y: mid))
        path.move(to: CGPoint(x: right, y: rect.maxY - rect.height * 0.27))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.maxY - rect.height * 0.27))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.08, y: mid))
        path.addLine(to: CGPoint(x: left, y: mid))
        return path
    }
}
