import SwiftUI
import iTelASCore

struct SourceWorkspaceHostIncludeReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            custodyBand
            HStack(spacing: 0) {
                routeLedger
                    .frame(width: 252)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                contentDestination
                Rectangle().fill(AppPalette.border).frame(width: 1)
                reviewGate
                    .frame(width: 342)
            }
            footer
        }
        .background(AppPalette.window)
        .interactiveDismissDisabled(model.sourceWorkspaceHostIncludePhase.isReading)
        .onAppear { proverb = .random(excluding: proverb.id) }
    }

    private var review: ReviewedSourceWorkspaceHostInclude? {
        model.sourceWorkspaceHostIncludeReview
    }

    private var header: some View {
        HStack(spacing: 12) {
            HostIncludeRelayMark()
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("iTelAS")
                    .font(.system(size: 17, weight: .bold))
                Text("SOURCE ATLAS")
                    .hostEyebrow(color: AppPalette.ibmBlue)
            }
            .frame(width: 150, alignment: .leading)
            Rectangle().fill(AppPalette.borderStrong).frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("REVIEWED HOST INCLUDE INTAKE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Resolve one exact /COPY or /INCLUDE without crawling the host")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            HostIncludeBadge(label: "READ ONLY", color: AppPalette.success)
            HostIncludeBadge(label: model.sourceWorkspaceHostIncludeProviderLabel, color: AppPalette.ibmBlue)
            Button("Close") {
                model.cancelSourceWorkspaceHostIncludeReview()
                dismiss()
            }
            .buttonStyle(HostIncludeOutlineButtonStyle())
            .frame(width: 64)
            .disabled(model.sourceWorkspaceHostIncludePhase.isReading)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var custodyBand: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LOCAL DEPENDENCY")
                    .hostEyebrow(color: AppPalette.terminalGreen)
                Text(sourceDisplayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(review.map { "LINE \($0.dependencyRange.startLine) · /\($0.dependencyKind.label)" } ?? "Review unavailable")
                    .font(.system(size: 7.2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 250, alignment: .leading)
            HostIncludeRouteArrow()
                .frame(width: 150, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("EXACT HOST TARGET")
                    .hostEyebrow(color: AppPalette.terminal(.blue))
                Text(review?.target.displayName ?? "TARGET UNAVAILABLE")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(model.sourceWorkspaceHostIncludeProviderLabel) READ · REVISION CAPTURED AFTER READ")
                    .font(.system(size: 7.2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 300, alignment: .leading)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 10) {
                    Text(model.sourceWorkspaceHostIncludePhase.label)
                        .foregroundStyle(model.sourceWorkspaceHostIncludePhase == .failed ? AppPalette.warning : AppPalette.terminalGreen)
                    Text("ARM64 · LOCAL OVERLAY")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                Text("INDEX \(model.sourceWorkspaceIndex.shortFingerprint) · REQUEST \(review?.shortFingerprint ?? "NONE")")
                    .font(.system(size: 8.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Provider idle until Apply · API key unread · no write route")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(AppPalette.instrument)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
    }

    private var routeLedger: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ROUTE LEDGER / 01")
                    .hostEyebrow(color: AppPalette.ibmBlue)
                Text("One edge, one target")
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 5) {
                Text("/\(review?.dependencyKind.label ?? "INCLUDE") · HOST CONTENT")
                    .hostEyebrow(color: AppPalette.ibmBlue)
                Text(review?.target.displayName ?? "No exact target")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .lineLimit(2)
                Text(review.map { "\($0.sourcePath) · \($0.dependencyRange.startLine):\($0.dependencyRange.startColumn)" } ?? "No current source edge")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(AppPalette.selection)
            .overlay(alignment: .leading) { Rectangle().fill(AppPalette.ibmBlue).frame(width: 4) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            Text("PROVIDER ROUTE")
                .hostEyebrow(color: AppPalette.muted)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(AppPalette.raised)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            providerRow(
                number: "01",
                title: "Source member",
                detail: "DB2 · READ CAPABILITY",
                selected: review?.target.providerKind == .sourceMember
            )
            providerRow(
                number: "02",
                title: "IFS path",
                detail: "SFTP · EXACT PATH ONLY",
                selected: review?.target.providerKind == .ifs
            )

            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("BOUNDARY")
                    .hostEyebrow(color: AppPalette.warning)
                Text("No library scan, directory walk, fallback search, compile, host write, or Assist request.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        .background(AppPalette.panel)
    }

    private func providerRow(number: String, title: String, detail: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? Color.white : AppPalette.muted)
                .frame(width: 26, height: 26)
                .background(selected ? AppPalette.success : AppPalette.raised)
                .overlay { Rectangle().stroke(selected ? AppPalette.success : AppPalette.borderStrong, lineWidth: 1) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                Text(detail)
                    .font(.system(size: 6.6, design: .monospaced))
                    .foregroundStyle(selected ? AppPalette.success : AppPalette.muted)
            }
            Spacer()
            if selected {
                Text("✓")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var contentDestination: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HostIncludeDocumentMark()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REVIEWED READ DESTINATION")
                        .hostEyebrow(color: AppPalette.ibmBlue)
                    Text("\(review?.target.displayName ?? "Host content") — content not read")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                }
                Spacer()
                HostIncludeBadge(label: "NOT READ", color: AppPalette.warning)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 0) {
                VStack(spacing: 8) {
                    ForEach(1...9, id: \.self) { line in
                        Text(String(format: "%02d", line))
                    }
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.34))
                .padding(.vertical, 16)
                .frame(width: 46)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(AppPalette.instrument)
                .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("No host content has been read.")
                        .foregroundStyle(AppPalette.terminal(.blue))
                    Text(" ")
                    Text("AFTER REVIEW")
                        .fontWeight(.bold)
                        .foregroundStyle(AppPalette.terminalGreen)
                    Text("• read one exact host target")
                    Text("• capture revision, CCSID, and size")
                    Text("• build a bounded local memory overlay")
                    Text(" ")
                    Text("No fallback search.")
                        .foregroundStyle(AppPalette.terminalGreen)
                    Text("No host write.")
                        .foregroundStyle(AppPalette.terminalGreen)
                }
                .font(.system(size: 8.2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 320)
            .background(AppPalette.terminal)

            HStack(spacing: 0) {
                destinationMetric("SYMBOLS", "—", color: AppPalette.muted)
                destinationMetric("CCSID", "—", color: AppPalette.muted)
                destinationMetric("SIZE LIMIT", byteLabel(review?.maximumContentUTF8Bytes ?? 0), color: AppPalette.warning)
            }
            .frame(height: 52)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 5) {
                Text("LOCAL OVERLAY EFFECT")
                    .hostEyebrow(color: AppPalette.ibmBlue)
                Text("After a verified receipt, search, inbound references, and reviewed completion may use the snapshot. Local rename never targets host content.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppPalette.window)
    }

    private func destinationMetric(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).hostEyebrow(color: AppPalette.muted)
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(AppPalette.border).frame(width: 1) }
    }

    private var reviewGate: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                HostIncludeReviewMark()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("HOST READ REVIEW")
                        .hostEyebrow(color: AppPalette.ibmBlue)
                    Text("Exact intake manifest")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
                HostIncludeBadge(
                    label: model.sourceWorkspaceHostIncludeReviewIsCurrent ? "CURRENT" : "STALE",
                    color: model.sourceWorkspaceHostIncludeReviewIsCurrent ? AppPalette.success : AppPalette.warning
                )
            }
            .padding(.horizontal, 13)
            .frame(height: 64)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 7) {
                Text("1 TARGET").hostEyebrow(color: AppPalette.ibmBlue)
                Text("·").foregroundStyle(AppPalette.muted)
                Text("REQUEST \(review?.shortFingerprint ?? "NONE")")
                    .hostEyebrow(color: AppPalette.text)
                Spacer()
                Text(model.sourceWorkspaceHostIncludePhase.label)
                    .hostEyebrow(color: model.sourceWorkspaceHostIncludePhase == .failed ? AppPalette.warning : AppPalette.success)
            }
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            manifestRow("SOURCE EDGE", review.map { "\($0.sourcePath) · \($0.dependencyRange.startLine):\($0.dependencyRange.startColumn)" } ?? "Unavailable")
            manifestRow("HOST TARGET", review?.target.displayName ?? "Unavailable", detail: model.sourceWorkspaceHostIncludeProviderLabel)
            manifestRow("LIMITS", "1 exact object · \(byteLabel(review?.maximumContentUTF8Bytes ?? 0)) · no fallback")

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $model.sourceWorkspaceHostIncludeAttested) {
                    Text("I reviewed the exact source edge, provider, target, and local-overlay boundary.")
                        .font(.system(size: 8, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                .disabled(!model.sourceWorkspaceHostIncludeReviewIsCurrent || model.sourceWorkspaceHostIncludePhase.isReading)
                Text("READ ONLY · CONTENT MAY BE SENSITIVE")
                    .hostEyebrow(color: Color(red: 0.55, green: 0.38, blue: 0))
            }
            .padding(13)
            .frame(height: 100, alignment: .top)
            .background(AppPalette.warning.opacity(0.09))
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.warning.opacity(0.55)).frame(height: 1) }

            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Button(actionLabel) {
                    model.readReviewedSourceWorkspaceHostInclude()
                }
                .buttonStyle(HostIncludePrimaryButtonStyle())
                .disabled(!model.sourceWorkspaceHostIncludeCanRead)

                Button("Cancel Review") {
                    model.cancelSourceWorkspaceHostIncludeReview()
                    dismiss()
                }
                .buttonStyle(HostIncludeOutlineButtonStyle())
                .disabled(model.sourceWorkspaceHostIncludePhase.isReading)

                Text(actionBoundary)
                    .font(.system(size: 7.5))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
        }
        .background(AppPalette.panel)
    }

    private func manifestRow(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).hostEyebrow(color: AppPalette.muted)
            Text(value)
                .font(.system(size: 8.4, weight: .bold, design: .monospaced))
                .lineLimit(2)
            if let detail {
                Text(detail).hostEyebrow(color: AppPalette.ibmBlue)
            }
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: detail == nil ? 55 : 64, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var actionLabel: String {
        if model.sourceWorkspaceHostIncludePhase.isReading { return "READING EXACT TARGET…" }
        return model.sourceWorkspaceIndexPhase == .localReplay
            ? "INSTALL BUNDLED REPLAY"
            : "READ EXACT HOST INCLUDE"
    }

    private var sourceDisplayName: String {
        guard let sourcePath = review?.sourcePath else { return "NO CURRENT EDGE" }
        return URL(fileURLWithPath: sourcePath).lastPathComponent.uppercased()
    }

    private var actionBoundary: String {
        model.sourceWorkspaceIndexPhase == .localReplay
            ? "Installs deterministic in-memory content. No provider or host is contacted."
            : "Performs one reviewed read-only request. It does not compile, write, or contact Assist."
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("INDEX: \(model.sourceWorkspaceIndex.shortFingerprint) · \(model.sourceWorkspaceIndex.localFileCount) LOCAL · \(model.sourceWorkspaceIndex.hostIncludeFileCount) HOST")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("PROVIDER: \(model.sourceWorkspaceHostIncludeProviderLabel) · READ ONLY")
                .foregroundStyle(Color(red: 0.92, green: 0.64, blue: 0.32))
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .italic()
                .foregroundStyle(.white.opacity(0.5))
            Text("ARM64 · REVIEWED INTAKE")
                .foregroundStyle(.white)
        }
        .font(.system(size: 6.8, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(AppPalette.instrument)
    }

    private func byteLabel(_ count: Int) -> String {
        if count >= 1_024 * 1_024 { return String(format: "%.1f MiB", Double(count) / 1_048_576) }
        if count >= 1_024 { return String(format: "%.1f KiB", Double(count) / 1_024) }
        return "\(count) B"
    }
}

private struct HostIncludeRelayMark: View {
    var body: some View {
        Canvas { context, size in
            var route = Path()
            route.move(to: CGPoint(x: 7, y: 10))
            route.addLine(to: CGPoint(x: 18, y: 10))
            route.addLine(to: CGPoint(x: 18, y: 21))
            route.addLine(to: CGPoint(x: 30, y: 21))
            route.addLine(to: CGPoint(x: 30, y: 32))
            route.addLine(to: CGPoint(x: 36, y: 32))
            route.move(to: CGPoint(x: 7, y: 30))
            route.addLine(to: CGPoint(x: 18, y: 30))
            route.addLine(to: CGPoint(x: 18, y: 21))
            context.stroke(route, with: .color(AppPalette.terminalGreen), lineWidth: 2)
            context.fill(Path(ellipseIn: CGRect(x: 5, y: 7, width: 7, height: 7)), with: .color(AppPalette.ibmBlue))
            context.fill(Path(ellipseIn: CGRect(x: 32, y: 28, width: 8, height: 8)), with: .color(AppPalette.terminalGreen))
        }
        .background(AppPalette.instrument)
        .overlay { Rectangle().stroke(AppPalette.ibmBlue, lineWidth: 1) }
    }
}

private struct HostIncludeRouteArrow: View {
    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            var route = Path()
            route.move(to: CGPoint(x: 6, y: y))
            route.addLine(to: CGPoint(x: size.width - 18, y: y))
            route.move(to: CGPoint(x: size.width - 29, y: y - 6))
            route.addLine(to: CGPoint(x: size.width - 18, y: y))
            route.addLine(to: CGPoint(x: size.width - 29, y: y + 6))
            context.stroke(route, with: .color(AppPalette.terminal(.blue)), lineWidth: 1.4)
            context.fill(Path(ellipseIn: CGRect(x: 3, y: y - 3.5, width: 7, height: 7)), with: .color(AppPalette.ibmBlue))
            context.fill(Path(ellipseIn: CGRect(x: size.width - 13, y: y - 3.5, width: 7, height: 7)), with: .color(AppPalette.terminalGreen))
            context.draw(
                Text("EXACT REVIEW").font(.system(size: 6.5, weight: .bold, design: .monospaced)).foregroundColor(AppPalette.terminal(.blue)),
                at: CGPoint(x: size.width / 2, y: 7)
            )
        }
    }
}

private struct HostIncludeDocumentMark: View {
    var body: some View {
        Canvas { context, size in
            var page = Path()
            page.move(to: CGPoint(x: 9, y: 7))
            page.addLine(to: CGPoint(x: 23, y: 7))
            page.addLine(to: CGPoint(x: 28, y: 12))
            page.addLine(to: CGPoint(x: 28, y: 28))
            page.addLine(to: CGPoint(x: 9, y: 28))
            page.closeSubpath()
            page.move(to: CGPoint(x: 23, y: 7))
            page.addLine(to: CGPoint(x: 23, y: 12))
            page.addLine(to: CGPoint(x: 28, y: 12))
            page.move(to: CGPoint(x: 13, y: 17))
            page.addLine(to: CGPoint(x: 24, y: 17))
            page.move(to: CGPoint(x: 13, y: 22))
            page.addLine(to: CGPoint(x: 24, y: 22))
            context.stroke(page, with: .color(AppPalette.terminalGreen), lineWidth: 1.5)
        }
        .background(AppPalette.instrument)
    }
}

private struct HostIncludeReviewMark: View {
    var body: some View {
        Canvas { context, size in
            var shield = Path()
            shield.move(to: CGPoint(x: size.width / 2, y: 5))
            shield.addLine(to: CGPoint(x: size.width - 6, y: 10))
            shield.addLine(to: CGPoint(x: size.width - 6, y: 20))
            shield.addCurve(
                to: CGPoint(x: size.width / 2, y: size.height - 5),
                control1: CGPoint(x: size.width - 6, y: 28),
                control2: CGPoint(x: size.width - 13, y: 31)
            )
            shield.addCurve(
                to: CGPoint(x: 6, y: 20),
                control1: CGPoint(x: 13, y: 31),
                control2: CGPoint(x: 6, y: 28)
            )
            shield.addLine(to: CGPoint(x: 6, y: 10))
            shield.closeSubpath()
            var check = Path()
            check.move(to: CGPoint(x: 11, y: 19))
            check.addLine(to: CGPoint(x: 16, y: 24))
            check.addLine(to: CGPoint(x: 27, y: 13))
            context.stroke(shield, with: .color(AppPalette.terminalGreen), lineWidth: 1.6)
            context.stroke(check, with: .color(AppPalette.terminalGreen), lineWidth: 1.8)
        }
        .background(AppPalette.instrument)
    }
}

private struct HostIncludeBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(color.opacity(0.08))
        .overlay { Rectangle().stroke(color.opacity(0.85), lineWidth: 1) }
    }
}

private struct HostIncludePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(AppPalette.terminalGreen).frame(width: 4, height: 18)
            configuration.label
                .font(.system(size: 7, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(AppPalette.instrument.opacity(configuration.isPressed ? 0.78 : 1))
        .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct HostIncludeOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.text)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(AppPalette.panel.opacity(configuration.isPressed ? 0.72 : 1))
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
    }
}

private extension View {
    func hostEyebrow(color: Color) -> some View {
        font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(color)
    }
}
