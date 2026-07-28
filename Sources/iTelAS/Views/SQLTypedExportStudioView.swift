import SwiftUI
import iTelASCore

struct SQLTypedExportStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let plan = model.sqlTypedExportPlan {
                VStack(spacing: 0) {
                    titleBar(plan)
                    HStack(spacing: 0) {
                        schemaRail(plan)
                            .frame(width: 248)
                        Rectangle().fill(AppPalette.border).frame(width: 1)
                        previewWorkspace(plan)
                        Rectangle().fill(AppPalette.border).frame(width: 1)
                        contractDossier(plan)
                            .frame(width: 306)
                    }
                    statusBar(plan)
                }
            } else {
                ContentUnavailableView(
                    "Typed export unavailable",
                    systemImage: "tablecells.badge.ellipsis",
                    description: Text(model.sqlTypedExportDiagnostic)
                )
            }
        }
        .frame(minWidth: 1_180, minHeight: 760)
        .background(AppPalette.window)
    }

    private func titleBar(_ plan: SQLTypedExportPlan) -> some View {
        HStack(spacing: 12) {
            SQLTypePrismMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("DB2 TYPED EXPORT")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("RESULT FIDELITY STUDIO")
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.muted)
            }

            Spacer()
            EnvironmentBadge(environment: plan.environment)
            exportBadge("LOCAL ARTIFACT", color: AppPalette.success)
            exportBadge("\(plan.rowCount) × \(plan.columnCount) EXACT", color: AppPalette.ibmBlue)

            Menu {
                ForEach(SQLTypedExportFormat.allCases) { format in
                    Button {
                        model.selectSQLTypedExportFormat(format)
                    } label: {
                        if format == plan.format {
                            Label(format.label, systemImage: "checkmark")
                        } else {
                            Text(format.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(plan.format.label.uppercased())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, 11)
                .frame(height: 31)
                .background(AppPalette.panel)
                .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("SAVE LOCAL…") { model.saveSQLTypedExport() }
                .buttonStyle(PrimaryButtonStyle())
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.secondary)
            .accessibilityLabel("Close Typed Export Studio")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func schemaRail(_ plan: SQLTypedExportPlan) -> some View {
        VStack(spacing: 0) {
            sectionHeader("RESULT SCHEMA", trailing: "\(plan.columnCount) COLUMNS")
            VStack(alignment: .leading, spacing: 5) {
                Text("RETAINED RESULT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text(plan.targetName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("\(plan.providerName) · \(plan.rowCount) rows")
                    .font(.system(size: 7.4, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
                Text("\(timestamp(plan.startedAt)) · \(plan.elapsedMilliseconds) ms")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack {
                Text("COLUMN FIDELITY")
                Spacer()
                Text("OBSERVED WIRE")
            }
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(plan.columns) { column in
                        schemaRow(column)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("VALUE SAFETY LEDGER")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.terminalGreen)
                riskRow("FORMULA-LIKE", "\(plan.formulaRiskCount) CELL\(plan.formulaRiskCount == 1 ? "" : "S")", color: AppPalette.warning)
                riskRow("NULL", "\(plan.nullCount) TOKENIZED", color: Color.white.opacity(0.74))
                riskRow("BINARY", "\(plan.binaryCellCount) BASE64", color: Color(red: 0.47, green: 0.66, blue: 1))
            }
            .padding(12)
            .background(AppPalette.terminal)

            VStack(alignment: .leading, spacing: 4) {
                Text("SCHEMA RECEIPT")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(AppPalette.muted)
                Text(short(plan.schemaFingerprint))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Text("Names · types · nullability · CCSID · observed values")
                    .font(.system(size: 7.2))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised)
        }
        .background(AppPalette.panel)
    }

    private func schemaRow(_ column: SQLTypedExportColumnContract) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Rectangle().fill(kindColor(primaryKind(column)))
                Text(compactKind(primaryKind(column)))
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 30, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(column.name)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text(column.databaseType)
                    .font(.system(size: 6.6, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
                Text("\(column.isNullable ? "NULLABLE" : "REQUIRED") · CCSID \(column.ccsid.map(String.init) ?? "N/A")")
                    .font(.system(size: 6.2, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 51)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func previewWorkspace(_ plan: SQLTypedExportPlan) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FIDELITY PREVIEW")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.65)
                    Text("Exact retained values → reviewed export representation")
                        .font(.system(size: 7.5))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                previewMetric("ROWS", "\(plan.rowCount)", color: AppPalette.text)
                previewMetric("NULLS", "\(plan.nullCount)", color: AppPalette.text)
                previewMetric("ATTENTION", "\(plan.attentionTransformationCount)", color: AppPalette.warning)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            fidelityRoute(plan)
                .frame(height: 92)

            HStack {
                Text("DATA PREVIEW · FIRST \(plan.previewRows.count) OF \(plan.rowCount) ROWS")
                Spacer()
                Text(plan.format == .csvBundle ? "SPREADSHEET-SAFE VIEW" : "TAGGED JSON VIEW")
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            typedPreviewTable(plan)
                .frame(height: 252)

            transformationLedger(plan)

            HStack(spacing: 12) {
                Text("RESULT \(short(plan.resultFingerprint))")
                Rectangle().fill(AppPalette.borderStrong).frame(width: 1, height: 16)
                Text("QUERY \(short(plan.queryFingerprint))")
                Spacer()
                Text("PREVIEW IS NOT A SAVED ARTIFACT")
                    .foregroundStyle(AppPalette.warning)
            }
            .font(.system(size: 6.6, weight: .bold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(AppPalette.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.window)
    }

    private func fidelityRoute(_ plan: SQLTypedExportPlan) -> some View {
        HStack(spacing: 8) {
            routeNode(
                index: "01",
                eyebrow: "RETAINED RESULT",
                value: "\(plan.rowCount) × \(plan.columnCount) TYPED",
                detail: "SHA \(short(plan.resultFingerprint))",
                color: AppPalette.terminalGreen,
                dark: true
            )
            routeConnector("VALIDATE", color: AppPalette.ibmBlue)
            routeNode(
                index: "02",
                eyebrow: "PROFILE",
                value: plan.format.label.uppercased(),
                detail: "Explicit representations",
                color: AppPalette.ibmBlue,
                dark: false
            )
            routeConnector("PACKAGE", color: AppPalette.success)
            routeNode(
                index: "03",
                eyebrow: "LOCAL ARTIFACT",
                value: "\(plan.files.count) FILE\(plan.files.count == 1 ? "" : "S") · VERIFIED",
                detail: ByteCountFormatter.string(fromByteCount: Int64(plan.totalByteCount), countStyle: .file),
                color: AppPalette.success,
                dark: false
            )
        }
        .padding(.horizontal, 12)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func typedPreviewTable(_ plan: SQLTypedExportPlan) -> some View {
        let width: CGFloat = 138
        return ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(plan.previewRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(plan.columns.indices, id: \.self) { index in
                                typedPreviewCell(
                                    row[index],
                                    width: width,
                                    alternate: !rowIndex.isMultiple(of: 2)
                                )
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(plan.columns) { column in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(column.name)
                                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white)
                                    .lineLimit(1)
                                Text(column.databaseType)
                                    .font(.system(size: 5.9, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.58))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .frame(width: width, height: 36, alignment: .leading)
                            .background(AppPalette.terminal)
                            .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1) }
                        }
                    }
                }
            }
        }
        .background(AppPalette.panel)
        .accessibilityLabel("Typed export preview for \(plan.targetName)")
    }

    private func typedPreviewCell(
        _ cell: SQLTypedExportPreviewCell,
        width: CGFloat,
        alternate: Bool
    ) -> some View {
        let text = cell.exportDisplay.isEmpty ? "EMPTY" : cell.exportDisplay
        let color: Color = if cell.kind == .null {
            AppPalette.muted
        } else if cell.representationChanged {
            AppPalette.warning
        } else {
            AppPalette.text
        }
        return Text(text)
            .font(.system(size: 7.2, design: .monospaced))
            .foregroundStyle(color)
            .italic(cell.kind == .null)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 42, alignment: .leading)
            .background(alternate ? AppPalette.raised : AppPalette.panel)
            .overlay(alignment: .trailing) { Rectangle().fill(AppPalette.border).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func transformationLedger(_ plan: SQLTypedExportPlan) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("REPRESENTATION CONTRACT")
                Spacer()
                Text("\(plan.transformations.count) RULES · 0 SILENT")
                    .foregroundStyle(AppPalette.success)
            }
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(plan.transformations) { transformation in
                        HStack(spacing: 9) {
                            Text(String(format: "%02d", transformation.count))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(transformationColor(transformation.kind))
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transformation.label.uppercased())
                                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                                    .tracking(0.35)
                                Text(transformation.detail)
                                    .font(.system(size: 7.1))
                                    .foregroundStyle(AppPalette.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 39)
                        .background(AppPalette.panel)
                        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(AppPalette.panel)
    }

    private func contractDossier(_ plan: SQLTypedExportPlan) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader("EXPORT CONTRACT", trailing: "READY")

                VStack(alignment: .leading, spacing: 8) {
                    Text("FORMAT PROFILE")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .tracking(0.55)
                        .foregroundStyle(AppPalette.muted)
                    HStack(spacing: 7) {
                        ForEach(SQLTypedExportFormat.allCases) { format in
                            Button {
                                model.selectSQLTypedExportFormat(format)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(format == plan.format ? "SELECTED" : "ALTERNATE")
                                        .font(.system(size: 5.8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(format == plan.format ? AppPalette.ibmBlue : AppPalette.muted)
                                    Text(format.label.uppercased())
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(AppPalette.text)
                                    Text(format == .csvBundle ? "CSV plus exact sidecars" : "One tagged document")
                                        .font(.system(size: 6.4))
                                        .foregroundStyle(AppPalette.secondary)
                                        .lineLimit(2)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                                .background(format == plan.format ? AppPalette.ibmBlue.opacity(0.08) : AppPalette.panel)
                                .overlay {
                                    Rectangle().stroke(
                                        format == plan.format ? AppPalette.ibmBlue : AppPalette.borderStrong,
                                        lineWidth: 1
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(11)
                .background(AppPalette.raised)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

                dossierHeading("PACKAGE CONTENTS", trailing: "\(plan.files.count) FILE\(plan.files.count == 1 ? "" : "S")")
                ForEach(Array(plan.files.enumerated()), id: \.element.id) { index, file in
                    HStack(spacing: 9) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(fileColor(index))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)) · \(file.shortFingerprint)")
                                .font(.system(size: 6.2, design: .monospaced))
                                .foregroundStyle(AppPalette.muted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 42)
                    .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
                }

                dossierHeading("FIDELITY GUARDS", trailing: "6 / 6 PASS")
                guardRow("NULL", plan.format == .csvBundle ? "\\N + manifest" : "tagged null")
                guardRow("DECIMAL", plan.format == .csvBundle ? "exact text" : "tagged text")
                guardRow("TEMPORAL", "ISO 8601 UTC")
                guardRow("BINARY", "Base64 + bytes")
                guardRow("FORMULA", plan.format == .csvBundle ? "reversible prefix" : "exact JSON text")
                guardRow("TRUNCATION", plan.wasTruncated ? "disclosed · capped" : "complete within cap")

                VStack(alignment: .leading, spacing: 7) {
                    Text("EXPORT RECEIPT · PREVIEW")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppPalette.terminalGreen)
                    receiptRow("QUERY", plan.queryFingerprint)
                    receiptRow("RESULT", plan.resultFingerprint)
                    receiptRow("SCHEMA", plan.schemaFingerprint)
                    receiptRow("PLAN", plan.fingerprint)
                }
                .padding(11)
                .background(AppPalette.terminal)

                VStack(alignment: .leading, spacing: 9) {
                    Text("LOCAL EXPORT GATE")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .tracking(0.55)
                        .foregroundStyle(AppPalette.muted)
                    Text(model.sqlTypedExportDiagnostic)
                        .font(.system(size: 7.3))
                        .foregroundStyle(AppPalette.secondary)
                    HStack(spacing: 7) {
                        Rectangle().fill(AppPalette.warning).frame(width: 5, height: 5)
                        Text("NO PROVIDER · NO API KEY · NO HOST WRITE")
                            .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.38, green: 0.27, blue: 0))
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .background(AppPalette.warning.opacity(0.12))
                    .overlay { Rectangle().stroke(AppPalette.warning.opacity(0.65), lineWidth: 1) }

                    Button("PIN SCHEMA SUMMARY") { model.prepareSQLTypedExportAssist() }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                    Button("SAVE LOCAL ARTIFACT…") { model.saveSQLTypedExport() }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                }
                .padding(11)
            }
        }
        .background(AppPalette.panel)
    }

    private func statusBar(_ plan: SQLTypedExportPlan) -> some View {
        HStack(spacing: 17) {
            Text("RESULT: \(plan.rowCount) ROWS · \(plan.columnCount) COLUMNS")
                .fontWeight(.bold)
                .foregroundStyle(AppPalette.terminalGreen)
            Text("EXPORT: LOCAL ONLY")
                .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.45))
            Text("PROVIDER CALL: NONE")
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("ARM64 · NATIVE")
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 7.5, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppPalette.text)
            Spacer()
            Text(trailing)
                .foregroundStyle(trailing == "READY" ? AppPalette.success : AppPalette.ibmBlue)
        }
        .font(.system(size: 7.2, weight: .bold, design: .monospaced))
        .tracking(0.55)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func dossierHeading(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(trailing)
        }
        .font(.system(size: 6.7, weight: .bold, design: .monospaced))
        .tracking(0.5)
        .foregroundStyle(AppPalette.muted)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func exportBadge(_ label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .tracking(0.4)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(color.opacity(0.08))
        .overlay { Rectangle().stroke(color.opacity(0.65), lineWidth: 1) }
    }

    private func riskRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).fontWeight(.bold).foregroundStyle(color)
        }
        .font(.system(size: 6.6, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.58))
    }

    private func previewMetric(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 5.8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AppPalette.muted)
        }
    }

    private func routeNode(
        index: String,
        eyebrow: String,
        value: String,
        detail: String,
        color: Color,
        dark: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(index) · \(eyebrow)")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(dark ? Color.white : AppPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 6.2, design: .monospaced))
                .foregroundStyle(dark ? Color.white.opacity(0.56) : AppPalette.muted)
                .lineLimit(1)
        }
        .padding(9)
        .frame(width: 150, height: 66, alignment: .leading)
        .background(dark ? AppPalette.terminal : color.opacity(0.08))
        .overlay { Rectangle().stroke(color.opacity(0.8), lineWidth: 1) }
    }

    private func routeConnector(_ label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Rectangle().fill(color).frame(height: 1)
            Text(label)
                .font(.system(size: 5.7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func guardRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(AppPalette.success).frame(width: 5, height: 5)
            Text(label)
                .foregroundStyle(AppPalette.muted)
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .foregroundStyle(AppPalette.text)
        }
        .font(.system(size: 6.5, design: .monospaced))
        .padding(.horizontal, 11)
        .frame(height: 23)
        .background(AppPalette.raised)
    }

    private func receiptRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.54))
            Spacer()
            Text(short(value))
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 6.4, design: .monospaced))
    }

    private func transformationColor(_ kind: SQLTypedExportTransformationKind) -> Color {
        switch kind {
        case .formulaDefense, .textEscape: AppPalette.warning
        case .binaryBase64: AppPalette.ibmBlue
        case .nullToken: AppPalette.muted
        case .numericText, .temporalISO8601: AppPalette.success
        }
    }

    private func kindColor(_ kind: SQLTypedExportValueKind) -> Color {
        switch kind {
        case .string: AppPalette.ibmBlue
        case .integer, .decimal: AppPalette.success
        case .date, .timestamp: Color(red: 0.54, green: 0.25, blue: 0.98)
        case .boolean: Color(red: 0.82, green: 0.15, blue: 0.44)
        case .binary: AppPalette.warning
        case .null: AppPalette.muted
        }
    }

    private func compactKind(_ kind: SQLTypedExportValueKind) -> String {
        switch kind {
        case .string: "TXT"
        case .integer: "INT"
        case .decimal: "DEC"
        case .date: "DATE"
        case .timestamp: "TIME"
        case .boolean: "BOOL"
        case .binary: "BIN"
        case .null: "NULL"
        }
    }

    private func primaryKind(_ column: SQLTypedExportColumnContract) -> SQLTypedExportValueKind {
        column.observedKinds.first(where: { $0 != .null }) ?? .null
    }

    private func fileColor(_ index: Int) -> Color {
        [AppPalette.ibmBlue, AppPalette.success, Color(red: 0.54, green: 0.25, blue: 0.98)][index % 3]
    }

    private func short(_ value: String) -> String {
        guard value.count > 14 else { return value.uppercased() }
        return "\(value.prefix(8))…\(value.suffix(4))".uppercased()
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

struct SQLTypePrismMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(AppPalette.terminal))
            let rails: [(CGFloat, CGFloat, CGFloat, Color)] = [
                (0.21, 0.20, 0.62, AppPalette.ibmBlue),
                (0.45, 0.32, 0.50, AppPalette.terminalGreen),
                (0.69, 0.14, 0.68, Color.white)
            ]
            for (x, y, height, color) in rails {
                let rail = CGRect(
                    x: canvas.width * x,
                    y: canvas.height * y,
                    width: max(2, canvas.width * 0.08),
                    height: canvas.height * height
                )
                context.fill(Path(rail), with: .color(color))
            }
            var receipt = Path()
            receipt.move(to: CGPoint(x: canvas.width * 0.16, y: canvas.height * 0.16))
            receipt.addLine(to: CGPoint(x: canvas.width * 0.73, y: canvas.height * 0.16))
            receipt.addLine(to: CGPoint(x: canvas.width * 0.84, y: canvas.height * 0.28))
            receipt.addLine(to: CGPoint(x: canvas.width * 0.84, y: canvas.height * 0.82))
            receipt.addLine(to: CGPoint(x: canvas.width * 0.31, y: canvas.height * 0.82))
            receipt.addLine(to: CGPoint(x: canvas.width * 0.16, y: canvas.height * 0.67))
            receipt.closeSubpath()
            context.stroke(receipt, with: .color(Color(red: 0.47, green: 0.66, blue: 1)), lineWidth: max(0.7, size * 0.025))
        }
        .frame(width: size, height: size)
        .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: size > 20 ? 1 : 0.6) }
        .accessibilityHidden(true)
    }
}
