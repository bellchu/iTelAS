import SwiftUI
import iTelASCore

struct SQLWorkspaceView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var catalogScope = SQLCatalogScope.all
    @State private var resultTab = SQLResultTab.results

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                servicesCatalog
                    .frame(width: 286)

                Rectangle().fill(AppPalette.border).frame(width: 1)

                VStack(spacing: 0) {
                    queryTabs
                    queryWorkspace
                    resultPlane
                }
            }

            statusStrip
        }
        .background(AppPalette.window)
        .sheet(isPresented: Binding(
            get: { model.isSQLTypedExportPresented },
            set: { model.isSQLTypedExportPresented = $0 }
        )) {
            SQLTypedExportStudioView()
        }
        .sheet(isPresented: Binding(
            get: { model.isSQLExplainPresented },
            set: { model.isSQLExplainPresented = $0 }
        )) {
            SQLExplainPlanStudioView()
        }
    }

    private var filteredQueries: [IBMServiceQuery] {
        IBMIServicesCatalog.queries.filter { query in
            let scopeMatches = catalogScope == .all || catalogScope.category == query.category
            let searchMatches = searchText.isEmpty
                || query.title.localizedCaseInsensitiveContains(searchText)
                || query.serviceName.localizedCaseInsensitiveContains(searchText)
                || query.summary.localizedCaseInsensitiveContains(searchText)
            return scopeMatches && searchMatches
        }
    }

    private var servicesCatalog: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("IBM i SERVICES")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                Spacer()
                Text("\(IBMIServicesCatalog.queries.count) READ-ONLY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 8) {
                SQLSearchReticle()
                    .stroke(AppPalette.muted, lineWidth: 1.2)
                    .frame(width: 15, height: 15)
                TextField("Search jobs, locks, output, health", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5))
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 0) {
                ForEach(SQLCatalogScope.allCases) { scope in
                    Button {
                        catalogScope = scope
                    } label: {
                        Text(scope.rawValue)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(0.45)
                            .foregroundStyle(catalogScope == scope ? Color.white : AppPalette.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(catalogScope == scope ? AppPalette.instrument : AppPalette.raised)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(catalogScope == scope ? .isSelected : [])
                }
            }
            .frame(height: 34)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredQueries) { query in
                        SQLServiceQueryRow(
                            query: query,
                            selected: model.sqlSelectedServiceID == query.id
                        ) {
                            model.selectSQLService(query)
                        }
                    }

                    if filteredQueries.isEmpty {
                        Text("No IBM i Service template matches this filter.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppPalette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(providerStatusTitle)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(providerStatusColor)
                Text(providerStatusDetail)
                    .font(.system(size: 8.7))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(providerStatusColor.opacity(0.055))
            .overlay(alignment: .top) { Rectangle().fill(providerStatusColor.opacity(0.34)).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var queryTabs: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(model.sqlText == model.sqlBaselineText ? AppPalette.success : AppPalette.warning)
                    .frame(width: 6, height: 6)
                Text(model.selectedSQLService.map { "\($0.id).sql" } ?? "active-query.sql")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                Text("×")
                    .font(.system(size: 13))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.registrationBlue).frame(height: 2) }
            .overlay(alignment: .trailing) { Rectangle().fill(AppPalette.border).frame(width: 1) }

            Spacer()

            Text(model.sqlSaveState.label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(sqlSaveColor)
                .padding(.trailing, 14)
        }
        .frame(height: 44)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var queryWorkspace: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                editorToolbar

                PrecisionTextEditor(
                    text: Binding(
                        get: { model.sqlText },
                        set: { model.updateSQLText($0) }
                    ),
                    accessibilityLabel: "Local Db2 SQL editor",
                    onCursorChange: { model.updateSQLCursor(line: $0, column: $1) },
                    onSelectionChange: { model.updateSQLSelection($0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                HStack(spacing: 9) {
                    SQLSafetyCheckGlyph()
                        .stroke(analysisColor, lineWidth: 1.3)
                        .frame(width: 14, height: 14)
                    Text(editorSafetyMessage)
                        .font(.system(size: 9))
                        .foregroundStyle(analysisColor.opacity(0.82))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(model.sqlText.lengthOfBytes(using: .utf8)), countStyle: .file))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(analysisColor.opacity(0.82))
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(analysisColor.opacity(0.09))
                .overlay(alignment: .top) { Rectangle().fill(analysisColor.opacity(0.45)).frame(height: 1) }
            }

            Rectangle().fill(AppPalette.border).frame(width: 1)

            executionGate
                .frame(width: 304)
        }
        .frame(height: 430)
        .background(AppPalette.panel)
    }

    private var editorToolbar: some View {
        let analysis = model.sqlAnalysis
        return HStack(spacing: 17) {
            SQLMetadata(label: "STATEMENT", value: analysis.leadingKeyword ?? "EMPTY")
            SQLMetadata(label: "CLASS", value: analysis.statementClass.label.uppercased(), color: analysisColor)
            SQLMetadata(label: "SERVICE", value: model.selectedSQLService?.serviceName.replacingOccurrences(of: "QSYS2.", with: "") ?? "CUSTOM")

            Menu {
                ForEach([100, 500, 1_000], id: \.self) { cap in
                    Button("\(cap) rows") { model.sqlPolicy.maximumRows = cap }
                }
            } label: {
                SQLMetadata(label: "CAP", value: "\(model.sqlPolicy.maximumRows) ROWS")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Button("EXPLAIN") {
                model.presentSQLExplainStudio()
            }
            .buttonStyle(SQLOutlineButtonStyle())
            .help("Build a local static review; no Db2 provider call or SQL execution occurs")

            Button(model.sqlExecutionPreflight.isReady ? "RUN READ-ONLY" : "RUN BLOCKED") {
                model.requestSQLExecution()
            }
            .buttonStyle(SQLRunButtonStyle(ready: model.sqlExecutionPreflight.isReady))
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var executionGate: some View {
        let preflight = model.sqlExecutionPreflight
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                SQLExecutionGateGlyph()
                    .stroke(AppPalette.registrationBlue, lineWidth: 1.25)
                    .frame(width: 18, height: 18)
                Text("EXECUTION GATE")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.75)
                Spacer()
                Text(preflight.isReady ? "READY" : "BLOCKED")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(preflight.isReady ? AppPalette.success : AppPalette.danger)
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 7) {
                Text("TARGET IDENTITY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.75)
                    .foregroundStyle(AppPalette.muted)
                Text(model.db2Receipt?.targetName ?? "No Db2 connection selected")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(targetIdentityDetail)
                    .font(.system(size: 8.8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 8) {
                Text("QUERY POLICY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.75)
                    .foregroundStyle(AppPalette.muted)
                ForEach(preflight.checks) { check in
                    SQLPreflightRow(check: check)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Button("PREPARE ASSIST REVIEW") {
                    model.prepareSQLAssistReview()
                }
                .buttonStyle(SQLOutlineButtonStyle())
                .help("Open the Assist dossier to choose, preview, and explicitly send SQL context")

                Button(model.db2Phase.isConnected ? "REVIEW DB2 CONNECTION" : "CONNECT DB2 PROVIDER") {
                    model.presentDb2ConnectionDossier()
                }
                .buttonStyle(SQLBlackButtonStyle())
            }
            .padding(12)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var resultPlane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SQLResultTab.allCases) { tab in
                    Button {
                        resultTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(resultTab == tab ? AppPalette.ibmBlue : AppPalette.muted)
                            .padding(.horizontal, 14)
                            .frame(maxHeight: .infinity)
                            .background(resultTab == tab ? AppPalette.panel : AppPalette.raised)
                            .overlay(alignment: .bottom) {
                                if resultTab == tab {
                                    Rectangle().fill(AppPalette.registrationBlue).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                Text(resultSummary)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(model.sqlExecutionPhase == .failed ? AppPalette.danger : AppPalette.muted)
                    .padding(.trailing, 14)
                Button {
                    model.presentSQLTypedExportStudio()
                } label: {
                    HStack(spacing: 6) {
                        SQLTypePrismMark(size: 13)
                        Text("Typed Export")
                    }
                }
                .buttonStyle(SQLOutlineButtonStyle())
                .disabled(model.sqlResult == nil)
                .help("Review a type-preserving local export; this does not re-run the query")
                .padding(.trailing, 12)
            }
            .frame(height: 40)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if resultTab == .results, let result = model.sqlResult {
                SQLTypedResultTable(result: result)
            } else if resultTab == .results {
                resultTableEmptyState
            } else if resultTab == .plan {
                sqlExplainPlanState
            } else {
                VStack(spacing: 8) {
                    Text(messagePlaneTitle)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                    Text(model.sqlExecutionDiagnostic ?? "No Db2 diagnostic has been recorded for this session.")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 18) {
                Text(model.sqlResult == nil ? "TYPES: PENDING" : "TYPES: PRESERVED")
                Text("NULLS: PRESERVE")
                Text("TIMESTAMPS: HOST + UTC RECEIPT")
                Spacer()
                Text(model.sqlResult == nil ? "EXPORT: WAITING" : "EXPORT: REVIEW READY")
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.panel)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var resultTableEmptyState: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach([
                    "JOB_NAME", "AUTHORIZATION_NAME", "ELAPSED_CPU_%", "TEMPORARY_STORAGE", "SQL_STATEMENT_TEXT"
                ], id: \.self) { column in
                    Text(column)
                        .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(AppPalette.secondary)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) { Rectangle().fill(AppPalette.border).frame(width: 1) }
                }
            }
            .frame(height: 32)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(spacing: 9) {
                SQLResultPlaneGlyph()
                    .stroke(AppPalette.registrationBlue, lineWidth: 1.1)
                    .frame(width: 52, height: 43)
                Text(resultEmptyTitle)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                Text(resultEmptyDetail)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sqlExplainPlanState: some View {
        VStack(spacing: 9) {
            Image(systemName: model.sqlExplainReview == nil ? "point.3.connected.trianglepath.dotted" : "checkmark.seal")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(model.sqlExplainReview == nil ? AppPalette.registrationBlue : AppPalette.success)
            Text(model.sqlExplainReview == nil ? "LOCAL STATIC REVIEW NOT BUILT" : "LOCAL STATIC REVIEW READY")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
            Text(model.sqlExplainDiagnostic)
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            Button(model.sqlExplainReview == nil ? "BUILD LOCAL REVIEW" : "OPEN EXPLAIN STUDIO") {
                model.presentSQLExplainStudio()
            }
            .buttonStyle(SQLOutlineButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusStrip: some View {
        HStack(spacing: 18) {
            Text("DB2 PROVIDER: \(model.db2Phase.label)")
                .fontWeight(.bold)
                .foregroundStyle(providerStatusColor)
            Text("TRANSACTION: READ ONLY")
            Text("ROW CAP: \(model.sqlPolicy.maximumRows)")
            Text("TIME LIMIT: \(model.sqlPolicy.timeoutSeconds)S")
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("Ln \(model.sqlCursorLine)  Col \(model.sqlCursorColumn)")
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 8.5, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 13)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }

    private var analysisColor: Color {
        switch model.sqlAnalysis.statementClass {
        case .readOnly where model.sqlAnalysis.isSingleReadOnlyStatement: AppPalette.success
        case .unknown: AppPalette.warning
        default: AppPalette.danger
        }
    }

    private var editorSafetyMessage: String {
        let analysis = model.sqlAnalysis
        if analysis.statementCount != 1 {
            return "Execution blocked: split the script into exactly one statement."
        }
        if !analysis.isSingleReadOnlyStatement {
            return "Execution blocked: statement class is \(analysis.statementClass.label.lowercased())."
        }
        let limit = analysis.explicitRowLimit.map { "explicit \($0)-row cap" }
            ?? "provider-enforced \(model.sqlPolicy.maximumRows)-row cap"
        let provider = model.db2Phase.isConnected ? "provider receipt ready" : "provider remains offline"
        return "Single read-only statement detected · \(limit) · \(provider)."
    }

    private var providerStatusColor: Color {
        switch model.db2Phase {
        case .idle: AppPalette.muted
        case .connecting: AppPalette.warning
        case .connected: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var providerStatusTitle: String {
        switch model.db2Phase {
        case .connected: "DB2 PROVIDER READY · \(model.db2Receipt?.targetName.uppercased() ?? "VERIFIED TARGET")"
        case .connecting: "DB2 PROVIDER CONNECTING"
        case .failed: "DB2 PROVIDER BLOCKED"
        case .idle: "DB2 PROVIDER OFFLINE"
        }
    }

    private var providerStatusDetail: String {
        if let receipt = model.db2Receipt {
            return "TLS is active with the \(receipt.environment.label) target and a read-only capability receipt."
        }
        return model.db2Diagnostic
            ?? "Templates remain editable. Execution stays unavailable until the native provider contract is ready."
    }

    private var targetIdentityDetail: String {
        guard let receipt = model.db2Receipt else {
            return "System, environment, capability, and TLS state remain visible before execution."
        }
        return "\(receipt.environment.label) · \(receipt.accessMode.label) · TLS \(receipt.tlsEnabled ? "ON" : "OFF") · \(receipt.driverName)"
    }

    private var resultSummary: String {
        if model.sqlExecutionPhase == .running { return "QUERY RUNNING · BOUNDED" }
        guard let result = model.sqlResult else { return "\(model.sqlExecutionPhase.label) · NO ROWS" }
        return "\(result.rows.count) ROWS · \(result.elapsedMilliseconds) MS\(result.wasTruncated ? " · CAPPED" : "")"
    }

    private var messagePlaneTitle: String {
        switch model.sqlExecutionPhase {
        case .failed: "DB2 DIAGNOSTIC"
        case .running: "QUERY IN PROGRESS"
        case .succeeded: "EXECUTION RECEIPT"
        case .idle: "NO DB2 MESSAGES"
        }
    }

    private var resultEmptyTitle: String {
        switch model.sqlExecutionPhase {
        case .running: "BOUNDED READ-ONLY QUERY IN PROGRESS"
        case .failed: "QUERY STOPPED WITHOUT RESULT ROWS"
        case .succeeded: "QUERY RETURNED NO ROWS"
        case .idle: model.db2Phase.isConnected ? "RESULT PLANE ARMED" : "RESULT PLANE ARMED, PROVIDER OFFLINE"
        }
    }

    private var resultEmptyDetail: String {
        if let diagnostic = model.sqlExecutionDiagnostic { return diagnostic }
        if model.db2Phase.isConnected {
            return "The target receipt is ready. Run one reviewed read-only statement; types, nulls, decimals, timestamps, CCSID, and provenance remain intact."
        }
        return "Connect a trusted Db2 provider, confirm the target, then run this read-only query. Host access remains blocked until the contract is ready."
    }

    private var sqlSaveColor: Color {
        switch model.sqlSaveState {
        case .clean, .saved, .remoteClean: AppPalette.success
        case .saving, .remoteDraft: AppPalette.warning
        case .failed: AppPalette.danger
        }
    }
}

private struct SQLTypedResultTable: View {
    let result: SQLResult

    private var widths: [CGFloat] {
        result.columns.map { column in
            let labelWidth = CGFloat(max(column.name.count, column.databaseType.count)) * 7.2 + 34
            return min(280, max(132, labelWidth))
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(result.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(result.columns.indices, id: \.self) { columnIndex in
                                let value = row.indices.contains(columnIndex) ? row[columnIndex] : SQLValue.null
                                SQLTypedResultCell(
                                    text: displayValue(value),
                                    color: valueColor(value),
                                    width: widths[columnIndex],
                                    isAlternate: !rowIndex.isMultiple(of: 2)
                                )
                            }
                        }
                        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.75)).frame(height: 1) }
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(result.columns.indices, id: \.self) { index in
                            let column = result.columns[index]
                            VStack(alignment: .leading, spacing: 2) {
                                Text(column.name)
                                    .font(.system(size: 7.4, weight: .bold, design: .monospaced))
                                    .tracking(0.45)
                                    .foregroundStyle(AppPalette.text)
                                Text("\(column.databaseType) · \(column.isNullable ? "NULL" : "REQUIRED")")
                                    .font(.system(size: 6.4, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppPalette.muted)
                            }
                            .padding(.horizontal, 9)
                            .frame(width: widths[index], height: 38, alignment: .leading)
                            .background(AppPalette.raised)
                            .overlay(alignment: .trailing) { Rectangle().fill(AppPalette.borderStrong).frame(width: 1) }
                        }
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.borderStrong).frame(height: 1) }
                }
            }
        }
        .background(AppPalette.panel)
        .accessibilityLabel("Db2 query results from \(result.targetName)")
    }

    private func displayValue(_ value: SQLValue) -> String {
        switch value {
        case .null: "NULL"
        case .string(let text): text
        case .integer(let number): String(number)
        case .decimal(let number): number
        case .date(let date): ISO8601DateFormatter().string(from: date).prefix(10).description
        case .timestamp(let date): ISO8601DateFormatter().string(from: date)
        case .boolean(let value): value ? "TRUE" : "FALSE"
        case .binary(let data): "<\(data.count) BYTES>"
        }
    }

    private func valueColor(_ value: SQLValue) -> Color {
        switch value {
        case .null: AppPalette.muted
        case .boolean: AppPalette.ibmBlue
        case .binary: AppPalette.warning
        default: AppPalette.text
        }
    }
}

private struct SQLTypedResultCell: View {
    let text: String
    let color: Color
    let width: CGFloat
    let isAlternate: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 8.6, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(2)
            .textSelection(.enabled)
            .padding(.horizontal, 9)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 31, alignment: .leading)
            .background(isAlternate ? AppPalette.raised.opacity(0.7) : AppPalette.panel)
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppPalette.border).frame(width: 1)
            }
    }
}

private enum SQLCatalogScope: String, CaseIterable, Identifiable {
    case all = "ALL"
    case jobs = "JOBS"
    case locks = "LOCKS"
    case output = "OUTPUT"
    case system = "SYSTEM"

    var id: Self { self }

    var category: IBMServiceQuery.Category? {
        switch self {
        case .all: nil
        case .jobs: .jobs
        case .locks: .locks
        case .output: .output
        case .system: .system
        }
    }
}

private enum SQLResultTab: String, CaseIterable, Identifiable {
    case results = "RESULTS"
    case plan = "PLAN"
    case messages = "MESSAGES"
    var id: Self { self }
}

private struct SQLServiceQueryRow: View {
    let query: IBMServiceQuery
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SQLDatabaseGlyph(color: selected ? AppPalette.registrationBlue : AppPalette.muted)
                    .frame(width: 24, height: 29)
                    .padding(4)
                    .background(selected ? AppPalette.ibmBlue.opacity(0.09) : AppPalette.raised)

                VStack(alignment: .leading, spacing: 3) {
                    Text(query.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                    Text(query.serviceName)
                        .font(.system(size: 7.4, design: .monospaced))
                        .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.muted)
                    Text(query.summary.uppercased())
                        .font(.system(size: 6.7, design: .monospaced))
                        .tracking(0.35)
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 66)
            .background(selected ? AppPalette.ibmBlue.opacity(0.09) : AppPalette.panel)
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(AppPalette.registrationBlue).frame(width: 3) }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Load \(query.serviceName) into the local editor; this does not execute it")
    }
}

private struct SQLMetadata: View {
    let label: String
    let value: String
    var color = AppPalette.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .tracking(0.65)
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

private struct SQLPreflightRow: View {
    let check: SQLPreflightCheck

    private var color: Color {
        switch check.state {
        case .ready: AppPalette.success
        case .waiting: AppPalette.muted
        case .blocked: AppPalette.danger
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: 4, height: 14)
            Text(check.kind.label)
                .font(.system(size: 8.7))
                .foregroundStyle(AppPalette.text)
            Spacer(minLength: 4)
            Text(check.state.rawValue.uppercased())
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(color)
        }
        .help(check.detail)
    }
}

private struct SQLOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.65)
            .foregroundStyle(AppPalette.text)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(configuration.isPressed ? AppPalette.raised : AppPalette.panel)
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
            .contentShape(Rectangle())
    }
}

private struct SQLRunButtonStyle: ButtonStyle {
    let ready: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.65)
            .foregroundStyle(ready ? Color.white : AppPalette.muted)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(ready ? AppPalette.registrationBlue : AppPalette.borderStrong.opacity(0.55))
            .contentShape(Rectangle())
    }
}

private struct SQLBlackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.65)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(AppPalette.instrument.opacity(configuration.isPressed ? 0.8 : 1))
            .contentShape(Rectangle())
    }
}

private struct SQLSearchReticle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.34
        let center = CGPoint(x: rect.minX + radius + 1, y: rect.minY + radius + 1)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: center.x + radius * 0.72, y: center.y + radius * 0.72))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct SQLSafetyCheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.34, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct SQLExecutionGateGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: 2, dy: 1))
        path.move(to: CGPoint(x: rect.width * 0.42, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.maxY - 1))
        path.move(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.width * 0.80, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.72))
        return path
    }
}

private struct SQLResultPlaneGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: 1, dy: 1))
        for fraction in [0.28, 0.55, 0.78] {
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.height * fraction))
        }
        for fraction in [0.34, 0.68] {
            path.move(to: CGPoint(x: rect.width * fraction, y: rect.height * 0.28))
            path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.maxY - 1))
        }
        path.move(to: CGPoint(x: rect.width * 0.34, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.49))
        path.addLine(to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.67))
        path.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.55))
        return path
    }
}

private struct SQLDatabaseGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.1)
            let top = CGRect(x: 1, y: 1, width: size.width - 2, height: size.height * 0.28)
            context.stroke(Path(ellipseIn: top), with: .color(color), style: stroke)

            var body = Path()
            body.move(to: CGPoint(x: 1, y: top.midY))
            body.addLine(to: CGPoint(x: 1, y: size.height * 0.82))
            body.addCurve(
                to: CGPoint(x: size.width - 1, y: size.height * 0.82),
                control1: CGPoint(x: 1, y: size.height - 1),
                control2: CGPoint(x: size.width - 1, y: size.height - 1)
            )
            body.addLine(to: CGPoint(x: size.width - 1, y: top.midY))
            context.stroke(body, with: .color(color), style: stroke)

            for fraction in [0.46, 0.66] {
                var ring = Path()
                ring.move(to: CGPoint(x: 1, y: size.height * fraction))
                ring.addCurve(
                    to: CGPoint(x: size.width - 1, y: size.height * fraction),
                    control1: CGPoint(x: size.width * 0.28, y: size.height * (fraction + 0.12)),
                    control2: CGPoint(x: size.width * 0.72, y: size.height * (fraction + 0.12))
                )
                context.stroke(ring, with: .color(color.opacity(0.72)), style: stroke)
            }
        }
    }
}
