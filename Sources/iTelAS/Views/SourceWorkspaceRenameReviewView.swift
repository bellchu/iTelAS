import Foundation
import SwiftUI
import iTelASCore

struct SourceWorkspaceRenameReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            if let plan = model.sourceWorkspaceRenamePlan,
               let review = model.sourceWorkspaceRenameReview {
                HStack(spacing: 0) {
                    manifest(plan: plan, review: review)
                        .frame(width: 286)
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    exactChanges(plan: plan)
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    applicationGate(plan: plan, review: review)
                        .frame(width: 332)
                }
            } else {
                unavailableReview
            }
            footer
        }
        .frame(minWidth: 1_180, minHeight: 760)
        .background(AppPalette.window)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reviewed rename application")
        .interactiveDismissDisabled(model.sourceWorkspaceRenameApplyPhase.isApplying)
        .onAppear { proverb = .random(excluding: proverb.id) }
        .onDisappear {
            if model.sourceWorkspaceRenameApplyPhase == .reviewReady {
                model.cancelSourceWorkspaceRenameReview()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            RenameBatchGlyph()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("REVIEWED RENAME APPLY")
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.white)
                Text("Exact baselines · atomic per-file replacement · rollback-protected batch")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(red: 0.72, green: 0.79, blue: 0.83))
            }
            Spacer()
            if let review = model.sourceWorkspaceRenameReview {
                RenameReviewTag(label: "REVIEW \(review.shortFingerprint)", color: AppPalette.terminalGreen)
            }
            RenameReviewTag(
                label: model.sourceWorkspaceRenameApplyPhase.label,
                color: model.sourceWorkspaceRenameApplyPhase == .failed ? AppPalette.danger : AppPalette.warning
            )
        }
        .padding(.horizontal, 20)
        .frame(height: 70)
        .background(AppPalette.instrument)
        .overlay(alignment: .bottom) {
            HStack(spacing: 3) {
                Rectangle().fill(AppPalette.registrationBlue).frame(width: 72, height: 2)
                Rectangle().fill(AppPalette.terminalGreen).frame(width: 18, height: 2)
                Spacer()
            }
        }
    }

    private func manifest(
        plan: SourceWorkspaceRenamePlan,
        review: ReviewedSourceWorkspaceRename
    ) -> some View {
        VStack(spacing: 0) {
            RenameReviewSectionHeader(
                eyebrow: "01 · CUSTODY",
                title: "Affected-file manifest",
                detail: "Every path is frozen to indexed content and modification time."
            )
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(plan.baselines) { baseline in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top, spacing: 8) {
                                RenameFileGlyph()
                                    .frame(width: 18, height: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(baseline.relativePath)
                                        .font(.system(size: 9.2, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AppPalette.text)
                                        .lineLimit(2)
                                    Text("sha256 · \(baseline.contentFingerprint.prefix(12).uppercased())")
                                        .font(.system(size: 7.6, design: .monospaced))
                                        .foregroundStyle(AppPalette.muted)
                                }
                            }
                            HStack(spacing: 6) {
                                RenameReviewTag(
                                    label: baseline.sourceDate.map { "SRCDAT \($0)" } ?? "MTIME BASELINE",
                                    color: baseline.sourceDate == nil ? AppPalette.warning : AppPalette.ibmBlue,
                                    compact: true
                                )
                                Spacer()
                                Text("\(occurrenceCount(for: baseline.relativePath, plan: plan)) TOKENS")
                                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AppPalette.success)
                            }
                        }
                        .padding(12)
                        .background(AppPalette.panel)
                        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("IMMUTABLE REVIEW RECEIPT")
                    .renameEyebrow(color: AppPalette.ibmBlue)
                Text(review.reviewFingerprint)
                    .font(.system(size: 7.2, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text("Reviewed by \(review.reviewedBy) · \(review.reviewedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.system(size: 7.6))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(12)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private func exactChanges(plan: SourceWorkspaceRenamePlan) -> some View {
        VStack(spacing: 0) {
            RenameReviewSectionHeader(
                eyebrow: "02 · EXACT CHANGESET",
                title: "Token-aware replacements",
                detail: "Comments and string literals remain untouched."
            )
            HStack(spacing: 0) {
                RenameIdentityPlate(label: "CURRENT", value: plan.currentName, accent: AppPalette.danger)
                VStack(spacing: 3) {
                    Rectangle().fill(AppPalette.borderStrong).frame(width: 36, height: 1)
                    Text("APPLY")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                    Rectangle().fill(AppPalette.ibmBlue).frame(width: 36, height: 1)
                }
                .frame(width: 58)
                RenameIdentityPlate(label: "PROPOSED", value: plan.proposedName, accent: AppPalette.success)
            }
            .padding(14)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(Array(plan.occurrences.prefix(48).enumerated()), id: \.element.id) { offset, occurrence in
                        let lines = diffLines(for: occurrence, plan: plan)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                Text(String(format: "%02d", offset + 1))
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AppPalette.ibmBlue)
                                    .frame(width: 21, height: 21)
                                    .background(AppPalette.selection)
                                    .overlay { Rectangle().stroke(AppPalette.registrationBlue.opacity(0.5), lineWidth: 1) }
                                Text(occurrence.relativePath)
                                    .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppPalette.text)
                                    .lineLimit(1)
                                Spacer()
                                Text("L\(occurrence.line):\(occurrence.column)")
                                    .font(.system(size: 7.4, design: .monospaced))
                                    .foregroundStyle(AppPalette.muted)
                            }
                            RenameDiffLine(prefix: "−", text: lines.original, color: AppPalette.danger)
                            RenameDiffLine(prefix: "+", text: lines.replacement, color: AppPalette.success)
                        }
                        .padding(10)
                        .background(AppPalette.panel)
                        .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 1) }
                    }
                    if plan.occurrences.count > 48 {
                        Text("\(plan.occurrences.count - 48) additional exact occurrences remain bound to this receipt.")
                            .font(.system(size: 8.3, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                            .padding(12)
                    }
                }
                .padding(14)
            }
        }
        .background(AppPalette.window)
    }

    private func applicationGate(
        plan: SourceWorkspaceRenamePlan,
        review: ReviewedSourceWorkspaceRename
    ) -> some View {
        VStack(spacing: 0) {
            RenameReviewSectionHeader(
                eyebrow: "03 · APPLICATION GATE",
                title: "Replace safely, recover visibly",
                detail: "The review authorizes only this exact local batch."
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    RenameGateRow(number: "1", title: "Re-check all baselines", detail: "Content, mtime, permissions, and path type must still match.")
                    RenameGateRow(number: "2", title: "Prepare every replacement", detail: "No file changes until the complete bounded batch validates.")
                    RenameGateRow(number: "3", title: "Replace one file atomically", detail: "Each file uses a same-volume atomic replacement and byte verification.")
                    RenameGateRow(number: "4", title: "Stop on first mismatch", detail: "Earlier replacements are restored in reverse order before returning.")
                    RenameGateRow(number: "5", title: "Rebuild the local index", detail: "Success is shown only after the changed folder is indexed again.")

                    HStack(alignment: .top, spacing: 9) {
                        Rectangle().fill(AppPalette.warning).frame(width: 4)
                        Text("A multi-file batch is rollback-protected, not crash-atomic. Sudden power loss or external edits can require local inspection; iTelAS never retries automatically.")
                            .font(.system(size: 8.4))
                            .foregroundStyle(AppPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .background(AppPalette.warning.opacity(0.08))

                    if !model.sourceWorkspaceUsesSelectedFolder {
                        RenameReviewNotice(
                            title: "READ-ONLY REPLAY",
                            text: "This receipt demonstrates the gate only. Choose a local folder, rebuild its preview, and review that exact index before Apply becomes available.",
                            color: AppPalette.warning
                        )
                    }
                    if let recovery = model.sourceWorkspaceRenameRecovery {
                        RenameReviewNotice(
                            title: recovery.label,
                            text: recovery.isComplete
                                ? "Every earlier replacement was restored; the refreshed index is authoritative."
                                : "Inspect before retrying: \(recovery.unresolvedPaths.joined(separator: ", ")).",
                            color: recovery.isComplete ? AppPalette.success : AppPalette.danger
                        )
                    }

                    Toggle(isOn: Binding(
                        get: { model.sourceWorkspaceRenameAttested },
                        set: { model.sourceWorkspaceRenameAttested = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("I reviewed every affected path and exact identifier change.")
                                .font(.system(size: 9.2, weight: .semibold))
                                .foregroundStyle(AppPalette.text)
                            Text("Receipt \(review.shortFingerprint) · \(plan.baselines.count) files · \(plan.occurrences.count) tokens")
                                .font(.system(size: 7.5, design: .monospaced))
                                .foregroundStyle(AppPalette.muted)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(model.sourceWorkspaceRenameApplyPhase.isApplying)
                    .padding(12)
                    .background(model.sourceWorkspaceRenameAttested ? AppPalette.success.opacity(0.08) : AppPalette.raised)
                    .overlay { Rectangle().stroke(model.sourceWorkspaceRenameAttested ? AppPalette.success : AppPalette.border, lineWidth: 1) }
                }
                .padding(14)
            }
        }
        .background(AppPalette.panel)
    }

    private var unavailableReview: some View {
        VStack(spacing: 14) {
            RenameBatchGlyph()
                .frame(width: 54, height: 54)
            Text(model.sourceWorkspaceRenameRecovery?.label ?? "REVIEW NO LONGER CURRENT")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(model.sourceWorkspaceRenameRecovery?.isComplete == false ? AppPalette.danger : AppPalette.text)
            Text(model.sourceWorkspaceIndexDiagnostic)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            if let recovery = model.sourceWorkspaceRenameRecovery, !recovery.unresolvedPaths.isEmpty {
                Text(recovery.unresolvedPaths.joined(separator: " · "))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.danger)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.window)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WORKBENCH NOTE")
                    .renameEyebrow(color: AppPalette.ibmBlue)
                Text("\(proverb.text) — \(proverb.source)")
                    .font(.system(size: 8.7))
                    .italic()
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("CANCEL") { model.cancelSourceWorkspaceRenameReview() }
                .buttonStyle(RenameReviewOutlineButtonStyle())
                .disabled(model.sourceWorkspaceRenameApplyPhase.isApplying)
            Button(applyButtonLabel) { model.applyReviewedSourceWorkspaceRename() }
                .buttonStyle(RenameReviewApplyButtonStyle(enabled: model.sourceWorkspaceRenameCanApply))
                .disabled(!model.sourceWorkspaceRenameCanApply)
        }
        .padding(.horizontal, 18)
        .frame(height: 70)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var applyButtonLabel: String {
        if model.sourceWorkspaceRenameApplyPhase.isApplying { return "VERIFYING AND APPLYING…" }
        if !model.sourceWorkspaceUsesSelectedFolder { return "CHOOSE FOLDER TO APPLY" }
        return "APPLY EXACT REVIEWED RENAME"
    }

    private func occurrenceCount(for path: String, plan: SourceWorkspaceRenamePlan) -> Int {
        plan.occurrences.filter { $0.relativePath.caseInsensitiveCompare(path) == .orderedSame }.count
    }

    private func diffLines(
        for occurrence: SourceWorkspaceRenameOccurrence,
        plan: SourceWorkspaceRenamePlan
    ) -> (original: String, replacement: String) {
        guard let document = model.sourceWorkspaceIndex.document(at: occurrence.relativePath) else {
            return (occurrence.excerpt, occurrence.excerpt)
        }
        let source = document.text as NSString
        let tokenRange = NSRange(location: occurrence.utf16Location, length: occurrence.utf16Length)
        guard NSMaxRange(tokenRange) <= source.length else { return (occurrence.excerpt, occurrence.excerpt) }
        let lineRange = source.lineRange(for: tokenRange)
        let original = NSMutableString(string: source.substring(with: lineRange))
        let localRange = NSRange(location: tokenRange.location - lineRange.location, length: tokenRange.length)
        original.replaceCharacters(in: localRange, with: plan.proposedName)
        let originalLine = source.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementLine = String(original).trimmingCharacters(in: .whitespacesAndNewlines)
        return (originalLine, replacementLine)
    }
}

private struct RenameReviewSectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).renameEyebrow(color: AppPalette.ibmBlue)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppPalette.text)
            Text(detail)
                .font(.system(size: 8.3))
                .foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct RenameIdentityPlate: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).renameEyebrow(color: accent)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.panel)
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 1) }
    }
}

private struct RenameDiffLine: View {
    let prefix: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(prefix)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 10)
            Text(text)
                .font(.system(size: 8.2, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(color.opacity(0.045))
    }
}

private struct RenameGateRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Rectangle().fill(AppPalette.instrument)
                Text(number)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.terminalGreen)
            }
            .frame(width: 25, height: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9.3, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text(detail)
                    .font(.system(size: 7.8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RenameReviewNotice: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Rectangle().fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).renameEyebrow(color: color)
                Text(text)
                    .font(.system(size: 8.3))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(color.opacity(0.07))
    }
}

private struct RenameReviewTag: View {
    let label: String
    let color: Color
    var compact = false

    var body: some View {
        Text(label)
            .font(.system(size: compact ? 6.7 : 7.5, weight: .bold, design: .monospaced))
            .tracking(0.45)
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 5 : 8)
            .frame(height: compact ? 18 : 24)
            .background(color.opacity(0.09))
            .overlay { Rectangle().stroke(color.opacity(0.55), lineWidth: 1) }
    }
}

private struct RenameBatchGlyph: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.3, lineCap: .square, lineJoin: .miter)
            var left = Path()
            left.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.18))
            left.addLine(to: CGPoint(x: size.width * 0.39, y: size.height * 0.18))
            left.addLine(to: CGPoint(x: size.width * 0.48, y: size.height * 0.28))
            left.addLine(to: CGPoint(x: size.width * 0.48, y: size.height * 0.82))
            left.addLine(to: CGPoint(x: size.width * 0.08, y: size.height * 0.82))
            left.closeSubpath()
            context.stroke(left, with: .color(AppPalette.registrationBlue), style: stroke)

            var right = Path()
            right.move(to: CGPoint(x: size.width * 0.52, y: size.height * 0.18))
            right.addLine(to: CGPoint(x: size.width * 0.83, y: size.height * 0.18))
            right.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.28))
            right.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.82))
            right.addLine(to: CGPoint(x: size.width * 0.52, y: size.height * 0.82))
            right.closeSubpath()
            context.stroke(right, with: .color(AppPalette.terminalGreen), style: stroke)

            var corridor = Path()
            corridor.move(to: CGPoint(x: size.width * 0.24, y: size.height * 0.50))
            corridor.addLine(to: CGPoint(x: size.width * 0.68, y: size.height * 0.50))
            corridor.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.43))
            corridor.move(to: CGPoint(x: size.width * 0.68, y: size.height * 0.50))
            corridor.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.57))
            context.stroke(corridor, with: .color(Color.white), style: StrokeStyle(lineWidth: 1.4, lineCap: .square))

            for y in [0.34, 0.66] {
                var tick = Path()
                tick.move(to: CGPoint(x: size.width * 0.15, y: size.height * y))
                tick.addLine(to: CGPoint(x: size.width * 0.36, y: size.height * y))
                tick.move(to: CGPoint(x: size.width * 0.59, y: size.height * y))
                tick.addLine(to: CGPoint(x: size.width * 0.80, y: size.height * y))
                context.stroke(tick, with: .color(Color.white.opacity(0.55)), style: StrokeStyle(lineWidth: 0.8))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct RenameFileGlyph: View {
    var body: some View {
        Canvas { context, size in
            var page = Path()
            page.move(to: CGPoint(x: 1, y: 1))
            page.addLine(to: CGPoint(x: size.width * 0.68, y: 1))
            page.addLine(to: CGPoint(x: size.width - 1, y: size.height * 0.27))
            page.addLine(to: CGPoint(x: size.width - 1, y: size.height - 1))
            page.addLine(to: CGPoint(x: 1, y: size.height - 1))
            page.closeSubpath()
            context.stroke(page, with: .color(AppPalette.registrationBlue), style: StrokeStyle(lineWidth: 1.1))
            for y in [0.43, 0.61, 0.79] {
                var line = Path()
                line.move(to: CGPoint(x: size.width * 0.22, y: size.height * y))
                line.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * y))
                context.stroke(line, with: .color(AppPalette.borderStrong), style: StrokeStyle(lineWidth: 0.8))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct RenameReviewApplyButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8.8, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(enabled ? Color.white : AppPalette.muted)
            .padding(.horizontal, 17)
            .frame(height: 36)
            .background(enabled ? AppPalette.instrument : AppPalette.border)
            .overlay(alignment: .leading) {
                Rectangle().fill(enabled ? AppPalette.terminalGreen : AppPalette.borderStrong).frame(width: 3)
            }
            .overlay { Rectangle().stroke(enabled ? AppPalette.instrument : AppPalette.borderStrong, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct RenameReviewOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8.8, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.secondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(configuration.isPressed ? AppPalette.panel : Color.clear)
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
    }
}

private extension View {
    func renameEyebrow(color: Color) -> some View {
        font(.system(size: 7.3, weight: .bold, design: .monospaced))
            .tracking(0.75)
            .foregroundStyle(color)
    }
}
