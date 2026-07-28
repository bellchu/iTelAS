import SwiftUI
import iTelASCore

struct SQLExplainPlanStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let review = model.sqlExplainReview {
                VStack(spacing: 0) {
                    titleBar(review)
                    HStack(spacing: 0) {
                        sourceRail(review)
                            .frame(width: 248)
                        Rectangle().fill(AppPalette.border).frame(width: 1)
                        planCanvas(review)
                        Rectangle().fill(AppPalette.border).frame(width: 1)
                        dossier(review)
                            .frame(width: 298)
                    }
                    statusStrip(review)
                }
            } else {
                ContentUnavailableView(
                    "Local SQL review unavailable",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(model.sqlExplainDiagnostic)
                )
            }
        }
        .frame(minWidth: 1_180, minHeight: 760)
        .background(AppPalette.window)
    }

    private func titleBar(_ review: SQLExplainReview) -> some View {
        HStack(spacing: 12) {
            ITelASMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("DB2 EXPLAIN PLAN")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("LOCAL STATIC REVIEW · NO PROVIDER CALL")
                    .font(.system(size: 7.4, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.muted)
            }

            Spacer()

            if let environment = model.db2Receipt?.environment {
                EnvironmentBadge(environment: environment)
            } else {
                ExplainBadge(label: "NO TARGET CONTACT", color: AppPalette.success)
            }
            ExplainBadge(label: "1 READ-ONLY STATEMENT", color: AppPalette.success)
            ExplainBadge(label: review.shortFingerprint, color: AppPalette.registrationBlue)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.secondary)
            .accessibilityLabel("Close Db2 Explain Plan Studio")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func sourceRail(_ review: SQLExplainReview) -> some View {
        VStack(spacing: 0) {
            sectionHeader("QUERY CONTEXT", trailing: "\(review.queryUTF8ByteCount) B")

            VStack(alignment: .leading, spacing: 6) {
                Text("STATIC INPUT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("One local SQL draft")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text("\(review.analysis.leadingKeyword ?? "UNKNOWN") · \(review.analysis.statementClass.label.uppercased())")
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(spacing: 0) {
                contextRow(label: "SYNTAX", value: "READ-ONLY", color: AppPalette.success)
                contextRow(
                    label: "LIMIT",
                    value: review.analysis.explicitRowLimit.map { "FETCH \($0)" } ?? "CAP \(review.providerRowCap)",
                    color: review.analysis.explicitRowLimit == nil ? AppPalette.warning : AppPalette.success
                )
                contextRow(label: "STAGES", value: "\(review.stages.count) LOCAL", color: AppPalette.ibmBlue)
            }
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack {
                Text("LOCAL SOURCE REFERENCES")
                Spacer()
                Text("LEXICAL")
            }
            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 13)
            .frame(height: 31)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if review.sourceReferences.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("UNRESOLVED")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppPalette.warning)
                            Text("The draft may use a CTE, derived table, table function, or quoted identifier. Host optimizer evidence remains required.")
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(review.sourceReferences.enumerated()), id: \.element) { index, source in
                            HStack(spacing: 9) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AppPalette.ibmBlue)
                                    .frame(width: 22, height: 22)
                                    .background(AppPalette.ibmBlue.opacity(0.09), in: ChamferedRectangle(cut: 3))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(AppPalette.text)
                                        .lineLimit(2)
                                    Text("LEXICAL REFERENCE · ALIAS/RESOLUTION UNVERIFIED")
                                        .font(.system(size: 6.2, weight: .semibold, design: .monospaced))
                                        .tracking(0.3)
                                        .foregroundStyle(AppPalette.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("HOST BOUNDARY")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.terminalGreen)
                Text("No provider receipt, plan cache, optimizer estimate, or index data is present.")
                    .font(.system(size: 8.2))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.terminal)
        }
        .background(AppPalette.panel)
    }

    private func planCanvas(_ review: SQLExplainReview) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppPalette.registrationBlue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LOCAL EXECUTION SHAPE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                    Text("Syntax-derived sequence · not an access plan")
                        .font(.system(size: 8.2))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                Text("\(review.stages.count) STAGES")
                    .font(.system(size: 7.4, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STATIC FLOW")
                    Spacer()
                    Text("NO COSTS · NO ROW ESTIMATES · NO INDEX CLAIMS")
                }
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .tracking(0.55)
                .foregroundStyle(Color.white.opacity(0.58))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(review.stages) { stage in
                            ExplainStageCard(stage: stage, color: stageColor(stage.kind))
                            if stage.position != review.stages.last?.position {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.42))
                                    .frame(width: 14)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(14)
            .frame(height: 226, alignment: .top)
            .background(AppPalette.instrument)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.borderStrong.opacity(0.45)).frame(height: 1) }

            HStack {
                Text("INSIGHT LEDGER")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                Spacer()
                Text("\(review.findings.count) LOCAL NOTES")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 37)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(review.findings) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Text(finding.severity.label)
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .tracking(0.35)
                                .foregroundStyle(findingColor(finding.severity))
                                .frame(width: 42, height: 20)
                                .background(findingColor(finding.severity).opacity(0.09), in: ChamferedRectangle(cut: 3))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(finding.title)
                                    .font(.system(size: 9.4, weight: .semibold))
                                    .foregroundStyle(AppPalette.text)
                                Text(finding.detail)
                                    .font(.system(size: 8.2))
                                    .foregroundStyle(AppPalette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.78)).frame(height: 1) }
                    }
                }
            }
        }
        .background(AppPalette.window)
    }

    private func dossier(_ review: SQLExplainReview) -> some View {
        VStack(spacing: 0) {
            sectionHeader("REVIEW DOSSIER", trailing: "LOCAL")

            VStack(alignment: .leading, spacing: 7) {
                Text("REQUEST RECEIPT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text(review.shortFingerprint)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Text("\(review.queryUTF8ByteCount) UTF-8 bytes · current local draft")
                    .font(.system(size: 7.3, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                Text(review.fingerprint)
                    .font(.system(size: 6.2, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            dossierSection(
                label: "PROVIDER",
                title: model.db2Phase.isConnected ? "Connected but idle" : "Not contacted",
                detail: model.db2Phase.isConnected
                    ? "The configured Db2 connection was not used for this review."
                    : "No DB2 provider, system, or credential was contacted."
            )
            dossierSection(
                label: "PLAN OUTPUT",
                title: "Static syntax shape",
                detail: "The graph shows local clause order, not an optimizer-selected plan."
            )
            dossierSection(
                label: "ASSIST BOUNDARY",
                title: "Explicit SQL dossier",
                detail: "Assist opens its own exact-context review before anything is sent."
            )

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT REVIEW")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.terminalGreen)
                Text("Use Assist for a read-only query review, or collect a provider-backed explain separately when the connection is qualified.")
                    .font(.system(size: 8.3))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Button("PREPARE ASSIST REVIEW") {
                    model.prepareSQLAssistReview()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .help("Open a separate dossier that previews the exact SQL context before any AI request")
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.terminal)
        }
        .background(AppPalette.panel)
    }

    private func statusStrip(_ review: SQLExplainReview) -> some View {
        HStack(spacing: 17) {
            Text("DB2 PROVIDER: \(model.db2Phase.isConnected ? "IDLE" : "OFFLINE")")
                .foregroundStyle(model.db2Phase.isConnected ? AppPalette.terminalGreen : Color(red: 1, green: 0.61, blue: 0.61))
            Text("REVIEW: LOCAL STATIC")
            Text("STATEMENT: \(review.analysis.statementCount)")
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text("RECEIPT \(review.shortFingerprint)")
                .foregroundStyle(.white)
        }
        .font(.system(size: 7.7, weight: .bold, design: .monospaced))
        .tracking(0.35)
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 13)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 8.2, weight: .bold, design: .monospaced))
                .tracking(0.7)
            Spacer()
            Text(trailing)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.ibmBlue)
        }
        .foregroundStyle(AppPalette.text)
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func contextRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(AppPalette.muted)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(height: 31)
    }

    private func dossierSection(label: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .tracking(0.55)
                .foregroundStyle(AppPalette.muted)
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppPalette.text)
            Text(detail)
                .font(.system(size: 8))
                .foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func stageColor(_ kind: SQLExplainStageKind) -> Color {
        switch kind {
        case .source: AppPalette.registrationBlue
        case .join: Color(red: 0.49, green: 0.55, blue: 1)
        case .filter: AppPalette.terminalGreen
        case .grouping: Color(red: 0.82, green: 0.56, blue: 1)
        case .ordering: AppPalette.warning
        case .limit: AppPalette.success
        case .projection: Color.white
        }
    }

    private func findingColor(_ severity: SQLExplainFindingSeverity) -> Color {
        switch severity {
        case .ready: AppPalette.success
        case .review: AppPalette.warning
        case .note: AppPalette.ibmBlue
        }
    }
}

private struct ExplainBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
        .font(.system(size: 7.1, weight: .bold, design: .monospaced))
        .tracking(0.4)
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(color.opacity(0.08), in: ChamferedRectangle(cut: 4))
        .overlay { ChamferedRectangle(cut: 4).stroke(color.opacity(0.34), lineWidth: 0.8) }
    }
}

private struct ExplainStageCard: View {
    let stage: SQLExplainStage
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(String(format: "%02d", stage.position))
                    .font(.system(size: 6.6, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Spacer()
                Text(stage.kind.label.uppercased())
                    .font(.system(size: 6.1, weight: .bold, design: .monospaced))
                    .tracking(0.35)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Text(stage.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(stage.detail)
                .font(.system(size: 7.1))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(3)
            Text(stage.evidence)
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .tracking(0.25)
                .foregroundStyle(color)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 108, height: 145, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: ChamferedRectangle(cut: 5))
        .overlay {
            ChamferedRectangle(cut: 5)
                .stroke(color.opacity(0.5), lineWidth: 0.9)
        }
    }
}
