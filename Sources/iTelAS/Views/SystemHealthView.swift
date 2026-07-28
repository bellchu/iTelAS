import SwiftUI
import iTelASCore

struct SystemHealthView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                workspaceHeader
                pulseBand
                if geometry.size.width >= 1_180 {
                    HStack(spacing: 0) {
                        limitLedger
                        divider
                        maintenanceDossier
                            .frame(width: min(390, max(340, geometry.size.width * 0.31)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            limitLedger.frame(height: 610)
                            divider.frame(height: 1)
                            maintenanceDossier.frame(height: 720)
                        }
                    }
                }
                statusStrip
            }
            .background(AppPalette.window)
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            SystemPulseMark(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("OPERATIONS / EVIDENCE COCKPIT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("System Health")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }
            Spacer()
            EnvironmentBadge(environment: model.db2Receipt?.environment ?? .development)
            phaseBadge
            Button {
                if model.db2Phase.isConnected {
                    model.refreshSystemHealthEvidence()
                } else {
                    model.presentDb2ConnectionDossier()
                }
            } label: {
                Label(refreshActionLabel, systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.systemHealthPhase.isCollecting)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private var phaseBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(phaseColor).frame(width: 6, height: 6)
            Text(model.systemHealthPhase.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.45)
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(phaseColor.opacity(0.08))
        .overlay { ChamferedRectangle(cut: 3).stroke(phaseColor, lineWidth: 0.8) }
        .clipShape(ChamferedRectangle(cut: 3))
    }

    private var pulseBand: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SYSTEM PULSE / LOCAL INDEX")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.terminalGreen)
                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text("\(model.systemHealthSnapshot.assessment.score)")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("/ 100")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.54))
                    Text(assessmentLabel)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(assessmentColor)
                }
                HealthPulseTrace()
                    .stroke(AppPalette.terminalGreen, style: StrokeStyle(lineWidth: 1.2, lineCap: .square, lineJoin: .miter))
                    .frame(height: 24)
                Text("Transparent evidence penalties; never an outage forecast.")
                    .font(.system(size: 7.5))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .frame(width: 270, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(Color(red: 0.025, green: 0.075, blue: 0.055))
            .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.13)).frame(width: 1) }

            pulseMetric(
                "CPU · 1s SAMPLE",
                value: model.systemHealthSnapshot.cpu?.averageCPUUtilization.map(decimalText) ?? "—",
                suffix: "%",
                detail: model.systemHealthSnapshot.cpu == nil ? "authority gap" : "SYSTEM_ACTIVITY_INFO",
                color: .white
            )
            pulseMetric(
                "SYSTEM ASP",
                value: systemASPUsedText,
                suffix: "%",
                detail: systemASPDetail,
                color: AppPalette.warning
            )
            pulseMetric(
                "JOB TABLE",
                value: model.systemHealthSnapshot.status.map { compactCount($0.inUseJobTableEntries) } ?? "—",
                suffix: "",
                detail: jobTableDetail,
                color: .white
            )
            pulseMetric(
                "TEMP STORAGE",
                value: model.systemHealthSnapshot.status.map { storageText($0.currentTemporaryStorageMB) } ?? "—",
                suffix: "",
                detail: temporaryStorageDetail,
                color: .white
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("LIMITS AT RISK")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.78))
                Text("\(model.systemHealthSnapshot.assessment.limitsAtRisk)")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("warning + critical")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .padding(.horizontal, 18)
            .frame(width: 176, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(Color(red: 0.18, green: 0.53, blue: 0.78))
        }
        .frame(height: 154)
        .background(AppPalette.terminal)
    }

    private func pulseMetric(
        _ label: String,
        value: String,
        suffix: String,
        detail: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.54))
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 23, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text(suffix)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Text(detail)
                .font(.system(size: 6.8, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.46))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1) }
    }

    private var limitLedger: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SYSTEM LIMIT RISK LEDGER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppPalette.text)
                    Text("Highest pressure first · bounded read-only evidence")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    DiamondSignal()
                        .fill(AppPalette.warning)
                        .frame(width: 10, height: 10)
                    Text("HIGH-WATER · NOT TREND")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.55, green: 0.40, blue: 0))
                }
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(AppPalette.warning.opacity(0.12))
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.warning.opacity(0.6), lineWidth: 0.8) }
                .clipShape(ChamferedRectangle(cut: 3))
            }
            .padding(.horizontal, 15)
            .frame(height: 65)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { divider.frame(height: 1) }

            limitTableHeader
            let visibleLimits = Array(model.systemHealthSnapshot.limits.prefix(5))
            if visibleLimits.isEmpty {
                ContentUnavailableView(
                    "System-limit evidence unavailable",
                    systemImage: "gauge.with.dots.needle.0percent",
                    description: Text("Review the SYSLIMITS receipt; other health sources remain independent.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(visibleLimits) { limit in
                    limitRow(limit)
                }
                if model.systemHealthSnapshot.limits.count > visibleLimits.count {
                    Text("TOP 5 OF \(model.systemHealthSnapshot.limits.count) BOUNDED HIGH-WATER ROWS")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                }
                capacityCorrelationStrip
                    .frame(maxHeight: .infinity)
            }
        }
        .background(AppPalette.panel)
    }

    private var limitTableHeader: some View {
        HStack(spacing: 0) {
            tableHeader("SIGNAL", width: 58)
            tableHeader("LIMIT / EVIDENCE", width: nil)
            tableHeader("IDENTITY", width: 170)
            tableHeader("CURRENT", width: 86)
            tableHeader("MAXIMUM", width: 86)
            tableHeader("PRESSURE", width: 128)
        }
        .frame(height: 31)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
    }

    private func tableHeader(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.system(size: 6.6, weight: .bold, design: .monospaced))
            .tracking(0.3)
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 9)
            .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: .infinity, alignment: .leading)
            .frame(width: width)
    }

    private func limitRow(_ limit: SystemLimitOccurrence) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Rectangle().fill(severityColor(limit.severity)).frame(width: 26, height: 3)
                Text(limit.severity.label)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(severityColor(limit.severity))
            }
            .padding(.horizontal, 9)
            .frame(width: 58, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(limit.sizingName)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text("LIMIT \(limit.limitID) · \(limit.category) · \(limit.type)")
                    .font(.system(size: 6.6, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Text(limit.identityLabel)
                .font(.system(size: 7.2, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .lineLimit(2)
                .padding(.horizontal, 9)
                .frame(width: 170, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
            Text(compactDecimal(limit.currentValue))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, 9)
                .frame(width: 86, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
            Text(compactDecimal(limit.maximumValue))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .padding(.horizontal, 9)
                .frame(width: 86, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(percent(limit.pressure))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(severityColor(limit.severity))
                    Spacer()
                    Text("HWM")
                        .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                gauge(value: limit.pressure, color: severityColor(limit.severity))
            }
            .padding(.horizontal, 9)
            .frame(width: 128)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 60)
        .background(limit.rowIndex.isMultiple(of: 2) ? AppPalette.raised.opacity(0.6) : AppPalette.panel)
        .overlay(alignment: .bottom) { divider.frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(limit.severity.label), limit \(limit.limitID), \(limit.sizingName), \(percent(limit.pressure)), high-water occurrence")
    }

    private var capacityCorrelationStrip: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OPERATOR CUE / CORRELATION")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(AppPalette.terminalGreen)
                Text("Index headroom is the first review.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Ranks current high-water evidence; it cannot prove growth rate, outage time, or cause.")
                    .font(.system(size: 7.5))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    DiamondSignal().fill(AppPalette.terminalGreen).frame(width: 7, height: 7)
                    Text("VERIFY WITH THE OWNING TEAM")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .padding(15)
            .frame(width: 272, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(Color(red: 0.025, green: 0.075, blue: 0.055))

            capacityColumn(
                "SYSTEM ASP",
                value: model.systemHealthSnapshot.systemASP?.usedPercent.map { $0 / 100 },
                valueLabel: systemASPUsedText + "%",
                detail: "\(model.systemHealthSnapshot.systemASP?.storageThresholdPercent ?? 0)% message threshold",
                note: model.systemHealthSnapshot.systemASP?.totalCapacityMB.map(storageText) ?? "capacity unavailable",
                color: AppPalette.warning
            )
            capacityColumn(
                "JOB TABLE",
                value: model.systemHealthSnapshot.status?.jobTablePressure,
                valueLabel: model.systemHealthSnapshot.status.map { percent($0.jobTablePressure) } ?? "—",
                detail: jobTableDetail,
                note: model.systemHealthSnapshot.status.map { "\(compactCount($0.availableJobTableEntries)) entries free" } ?? "evidence unavailable",
                color: AppPalette.success
            )
            capacityColumn(
                "TEMPORARY",
                value: model.systemHealthSnapshot.status?.temporaryStoragePressureAgainstPeak,
                valueLabel: model.systemHealthSnapshot.status?.temporaryStoragePressureAgainstPeak.map(percent) ?? "—",
                detail: temporaryStorageDetail,
                note: "peak since IPL · not a configured limit",
                color: AppPalette.ibmBlue
            )
        }
        .frame(minHeight: 126)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.borderStrong).frame(height: 1) }
    }

    private func capacityColumn(
        _ label: String,
        value: Double?,
        valueLabel: String,
        detail: String,
        note: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(AppPalette.muted)
            Text(valueLabel)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            gauge(value: value ?? 0, color: color)
            Text(detail)
                .font(.system(size: 7.2, weight: .semibold))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
            Text(note)
                .font(.system(size: 6.5, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppPalette.panel)
        .overlay(alignment: .trailing) { divider }
    }

    private func gauge(value: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(AppPalette.border)
                Rectangle()
                    .fill(color)
                    .frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 5)
    }

    private var maintenanceDossier: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAINTENANCE POSTURE")
                        .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Readiness evidence")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                }
                Spacer()
                Text("NOT INTERNET CURRENCY")
                    .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(AppPalette.ibmBlue.opacity(0.08))
                    .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.ibmBlue.opacity(0.55), lineWidth: 0.8) }
                    .clipShape(ChamferedRectangle(cut: 3))
            }
            .padding(.horizontal, 13)
            .frame(height: 65)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { divider.frame(height: 1) }

            ptfSection
            certificateBoundary
            receiptSection
                .frame(maxHeight: .infinity)
            dossierActions
        }
        .background(AppPalette.panel)
    }

    private var ptfSection: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PTF group status")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                    Text("QSYS2.GROUP_PTF_INFO")
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Text(model.systemHealthSnapshot.isBundledReplay ? "REPLAY" : "READ-ONLY")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
            }
            .padding(.horizontal, 13)
            .frame(height: 43)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { divider.frame(height: 1) }

            let visibleGroups = Array(model.systemHealthSnapshot.ptfGroups.prefix(3))
            if visibleGroups.isEmpty {
                Text("PTF group status unavailable; review the evidence receipt.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 135, alignment: .center)
                    .padding(.horizontal, 13)
            } else {
                ForEach(visibleGroups) { group in
                    HStack(spacing: 9) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(group.name) · \(group.description ?? "Group PTF")")
                                .font(.system(size: 8.3, weight: .semibold))
                                .foregroundStyle(AppPalette.text)
                                .lineLimit(1)
                            Text("LEVEL \(group.level.map(String.init) ?? "—") · TARGET \(group.targetRelease ?? "—")")
                                .font(.system(size: 6.3, design: .monospaced))
                                .foregroundStyle(AppPalette.muted)
                        }
                        Spacer(minLength: 5)
                        Text(group.state.label)
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(ptfColor(group.state))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 45)
                    .overlay(alignment: .bottom) { divider.frame(height: 1) }
                }
            }
        }
        .frame(minHeight: 178)
    }

    private var certificateBoundary: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CERTIFICATES")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(AppPalette.terminalGreen)
                Spacer()
                Text("NOT COLLECTED")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.warning)
            }
            HStack(spacing: 11) {
                CertificateBoundaryMark()
                    .stroke(AppPalette.terminalGreen, style: StrokeStyle(lineWidth: 1.2, lineCap: .square, lineJoin: .miter))
                    .frame(width: 31, height: 31)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Separate privileged DCM capability")
                        .font(.system(size: 9.2, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("No store password or elevated authority is requested here.")
                        .font(.system(size: 7.2))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(minHeight: 94)
        .background(Color(red: 0.025, green: 0.075, blue: 0.055))
    }

    private var receiptSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("EVIDENCE RECEIPTS")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(AppPalette.secondary)
                Spacer()
                Text("\(collectedReceiptCount) / \(model.systemHealthSnapshot.receipts.count) SOURCES")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { divider.frame(height: 1) }

            ForEach(model.systemHealthSnapshot.receipts) { receipt in
                HStack(spacing: 7) {
                    Circle()
                        .fill(receipt.outcome.isCollected ? AppPalette.success : AppPalette.warning)
                        .frame(width: 5, height: 5)
                    Text(receipt.source.rawValue)
                        .font(.system(size: 6.6, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                    Spacer(minLength: 5)
                    Text(receiptStatus(receipt))
                        .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                        .foregroundStyle(receipt.outcome.isCollected ? AppPalette.success : AppPalette.warning)
                        .lineLimit(1)
                }
                .padding(.horizontal, 13)
                .frame(height: 25)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.55)).frame(height: 1) }
            }
        }
    }

    private var dossierActions: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ADVICE ONLY · NO HOST MUTATION")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Text("Exports stay local until you choose otherwise.")
                    .font(.system(size: 6.8))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer(minLength: 4)
            Button("Replay") { model.restoreSystemHealthReplay() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Export") { model.exportSystemHealthSnapshot() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Pin to Assist Shelf") { model.prepareSystemHealthAssist() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 11)
        .frame(height: 74)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { divider.frame(height: 1) }
    }

    private var statusStrip: some View {
        HStack(spacing: 15) {
            Text("EVIDENCE: \(collectedReceiptCount) SOURCES")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("HOST WRITES: NONE")
                .foregroundStyle(.white)
            Text(model.systemHealthDiagnostic)
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
            Text("ARM64 · NATIVE")
                .foregroundStyle(AppPalette.terminalGreen)
        }
        .font(.system(size: 7.2, weight: .bold, design: .monospaced))
        .padding(.horizontal, 13)
        .frame(height: 30)
        .background(AppPalette.terminal)
    }

    private var divider: some View {
        Rectangle().fill(AppPalette.border).frame(width: 1)
    }

    private var refreshActionLabel: String {
        if model.systemHealthPhase.isCollecting { return "Collecting…" }
        return model.db2Phase.isConnected ? "Refresh evidence" : "Connect for evidence"
    }

    private var phaseColor: Color {
        switch model.systemHealthPhase {
        case .localReplay: AppPalette.registrationBlue
        case .collecting: AppPalette.warning
        case .ready: AppPalette.success
        case .failed: AppPalette.danger
        }
    }

    private var assessmentLabel: String {
        model.systemHealthSnapshot.assessment.score >= 85 ? "STABLE" : "ATTENTION"
    }

    private var assessmentColor: Color {
        model.systemHealthSnapshot.assessment.score >= 85 ? AppPalette.terminalGreen : AppPalette.warning
    }

    private var collectedReceiptCount: Int {
        model.systemHealthSnapshot.receipts.filter { $0.outcome.isCollected }.count
    }

    private var systemASPUsedText: String {
        if let used = model.systemHealthSnapshot.systemASP?.usedPercent {
            return String(format: "%.1f", used)
        }
        guard let value = model.systemHealthSnapshot.status?.systemASPUsedPercent else { return "—" }
        return decimalText(value)
    }

    private var systemASPDetail: String {
        guard let asp = model.systemHealthSnapshot.systemASP else { return "ASP_INFO unavailable" }
        return "threshold \(asp.storageThresholdPercent)% · disks \(asp.diskUnitsPresent)"
    }

    private var jobTableDetail: String {
        guard let status = model.systemHealthSnapshot.status else { return "SYSTEM_STATUS_INFO unavailable" }
        return "of \(compactCount(status.totalJobTableEntries)) entries"
    }

    private var temporaryStorageDetail: String {
        guard let status = model.systemHealthSnapshot.status else { return "SYSTEM_STATUS_INFO unavailable" }
        return "of \(storageText(status.maximumTemporaryStorageMB)) peak"
    }

    private func severityColor(_ severity: SystemHealthSeverity) -> Color {
        switch severity {
        case .stable: AppPalette.success
        case .watch: AppPalette.registrationBlue
        case .warning: AppPalette.warning
        case .critical: AppPalette.danger
        }
    }

    private func ptfColor(_ state: PTFGroupState) -> Color {
        switch state {
        case .installed, .notApplicable, .supportedOnly, .relatedGroup: AppPalette.success
        case .applyAtNextIPL, .onOrder, .unknown, .other: AppPalette.warning
        case .notInstalled, .error: AppPalette.danger
        }
    }

    private func receiptStatus(_ receipt: SystemHealthEvidenceReceipt) -> String {
        switch receipt.outcome {
        case .collected:
            if receipt.source == .systemActivity { return "1s SAMPLE" }
            if receipt.source == .systemLimits { return "HIGH-WATER" }
            return receipt.boundWasReached ? "BOUNDED" : "COLLECTED"
        case .unavailable:
            return "UNAVAILABLE"
        }
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func compactDecimal(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        switch number {
        case 1_000_000_000...: return String(format: "%.2fB", number / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", number / 1_000_000)
        case 10_000...: return String(format: "%.1fK", number / 1_000)
        default: return NSDecimalNumber(decimal: value).stringValue
        }
    }

    private func compactCount(_ value: Int) -> String {
        compactDecimal(Decimal(value))
    }

    private func percent(_ ratio: Double) -> String {
        String(format: "%.1f%%", ratio * 100)
    }

    private func storageText(_ megabytes: Int64) -> String {
        let amount = Double(megabytes)
        if amount >= 1_000_000 { return String(format: "%.1f TB", amount / 1_000_000) }
        if amount >= 1_000 { return String(format: "%.1f GB", amount / 1_000) }
        return "\(megabytes) MB"
    }
}

private struct SystemPulseMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let w = canvas.width
            let h = canvas.height
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(AppPalette.terminal))
            var pulse = Path()
            pulse.move(to: CGPoint(x: w * 0.12, y: h * 0.58))
            pulse.addLine(to: CGPoint(x: w * 0.34, y: h * 0.58))
            pulse.addLine(to: CGPoint(x: w * 0.43, y: h * 0.25))
            pulse.addLine(to: CGPoint(x: w * 0.54, y: h * 0.76))
            pulse.addLine(to: CGPoint(x: w * 0.64, y: h * 0.44))
            pulse.addLine(to: CGPoint(x: w * 0.88, y: h * 0.44))
            context.stroke(pulse, with: .color(AppPalette.terminalGreen), style: StrokeStyle(lineWidth: max(1.2, w * 0.045), lineCap: .square, lineJoin: .miter))
            for point in [CGPoint(x: w * 0.12, y: h * 0.58), CGPoint(x: w * 0.43, y: h * 0.25), CGPoint(x: w * 0.88, y: h * 0.44)] {
                context.fill(Path(CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(.white))
            }
        }
        .frame(width: size, height: size)
        .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

private struct HealthPulseTrace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.12, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.19, y: rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.width * 0.27, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.63))
        path.addLine(to: CGPoint(x: rect.width * 0.46, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.69, y: rect.height * 0.34))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.67))
        path.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct CertificateBoundaryMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.height * 0.34)
        path.addEllipse(in: CGRect(x: center.x - rect.width * 0.18, y: center.y - rect.height * 0.18, width: rect.width * 0.36, height: rect.height * 0.36))
        path.move(to: CGPoint(x: center.x - rect.width * 0.09, y: rect.height * 0.49))
        path.addLine(to: CGPoint(x: rect.width * 0.37, y: rect.height * 0.88))
        path.addLine(to: CGPoint(x: rect.width * 0.63, y: rect.height * 0.88))
        path.addLine(to: CGPoint(x: center.x + rect.width * 0.09, y: rect.height * 0.49))
        return path
    }
}

private struct DiamondSignal: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
