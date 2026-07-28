import SwiftUI
import iTelASCore

struct SourceWorkspaceIncludeChainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var proverb = WorkbenchProverb.random()

    private var chain: SourceWorkspaceIncludeChain? {
        model.currentSourceWorkspaceIncludeChain
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            custodyBand
            if let chain {
                HStack(spacing: 0) {
                    documentRail(chain)
                        .frame(width: 244)
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    directiveStage(chain)
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    trustGate(chain)
                        .frame(width: 330)
                }
            } else {
                lockedState
            }
            footer
        }
        .background(AppPalette.window)
        .onAppear {
            proverb = .random(excluding: proverb.id)
            model.refreshSourceWorkspaceIncludeChain()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IncludeLoomMark(compact: true)
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("iTelAS")
                    .font(.system(size: 17, weight: .bold))
                Text("INCLUDE LOOM")
                    .includeEyebrow(color: AppPalette.ibmBlue)
            }
            .frame(width: 126, alignment: .leading)
            Rectangle().fill(AppPalette.borderStrong).frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("INCLUDE CHAIN NAVIGATOR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Recursive /COPY and /INCLUDE provenance · exact gaps stay visible")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            IncludeChainBadge(
                label: chain?.completion.label ?? model.sourceWorkspaceIncludeChainStatusLabel,
                color: chain.map(statusColor) ?? AppPalette.warning
            )
            if let chain {
                IncludeChainBadge(
                    label: "\(chain.documents.count) DOCS · \(chain.maximumDepthObserved) LEVELS",
                    color: AppPalette.ibmBlue
                )
            }
            Button("Rebuild Map") { model.refreshSourceWorkspaceIncludeChain() }
                .buttonStyle(IncludeChainOutlineButtonStyle())
                .disabled(!model.sourceWorkspaceEvidenceIsCurrent)
            Button("Use Exact Closure") { model.useSourceWorkspaceIncludeClosure() }
                .buttonStyle(IncludeChainPrimaryButtonStyle())
                .disabled(chain == nil || !model.sourceWorkspaceEvidenceIsCurrent)
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var custodyBand: some View {
        HStack(spacing: 18) {
            IncludeLoomMark(compact: false)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("ROOT / CURRENT INDEX BYTES")
                    .includeEyebrow(color: AppPalette.terminalGreen)
                Text(chain?.rootPath.split(separator: "/").last.map(String.init)?.uppercased() ?? "NO CURRENT ROOT")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(chain.map { "\($0.rootPath) · INDEX \(String($0.indexFingerprint.prefix(8)).uppercased())" } ?? "Exact workspace verification is required")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }
            .frame(width: 310, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("INCLUDE EVIDENCE CONTRACT")
                    .includeEyebrow(color: AppPalette.terminal(.blue))
                Text("Trace what is present; expose what is not")
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(.white)
                Text("Current indexed bytes only · conditional directives not evaluated · host content never guessed")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(chain == nil ? "MAP LOCKED" : "MAP CURRENT")
                        .foregroundStyle(chain == nil ? AppPalette.warning : AppPalette.terminalGreen)
                    Text("SESSION ONLY")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                Text(chain.map { "MAP \($0.shortFingerprint) · \($0.boundaries.count) BOUNDARIES" } ?? "MAP NONE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("No source persistence · no provider · no API key · no host action")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 86)
        .background(AppPalette.instrument)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
    }

    private func documentRail(_ chain: SourceWorkspaceIncludeChain) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("MAPPED DOCUMENTS")
                        .includeEyebrow(color: AppPalette.ibmBlue)
                    Spacer()
                    Text(String(chain.documents.count))
                        .includeEyebrow(color: AppPalette.success)
                }
                Text("Choose a new root")
                    .font(.system(size: 17, weight: .bold))
                Text("Each map binds one root to one exact index.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(.horizontal, 13)
            .frame(height: 76)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chain.documents) { document in
                        Button {
                            model.selectSourceWorkspaceDocument(document.relativePath)
                        } label: {
                            IncludeChainDocumentRow(
                                document: document,
                                selected: document.relativePath.caseInsensitiveCompare(chain.rootPath) == .orderedSame
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(AppPalette.panel)

            VStack(alignment: .leading, spacing: 6) {
                Text("SEMANTIC BOUNDARY")
                    .includeEyebrow(color: AppPalette.warning)
                Text("Lexical, not preprocessed")
                    .font(.system(size: 14.5, weight: .bold))
                Text("Conditional compilation, compiler options, and SQL precompiler expansion remain outside this receipt.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(height: 112, alignment: .top)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
    }

    private func directiveStage(_ chain: SourceWorkspaceIncludeChain) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                IncludeChainMetric(label: "DOCUMENTS", value: String(chain.documents.count), color: AppPalette.ibmBlue)
                IncludeChainMetric(label: "DIRECTIVES", value: String(chain.directives.count), color: AppPalette.success)
                IncludeChainMetric(label: "MAX DEPTH", value: String(chain.maximumDepthObserved), color: AppPalette.warning)
                IncludeChainMetric(label: "MAP RECEIPT", value: chain.shortFingerprint, color: statusColor(chain))
            }
            .frame(height: 54)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 10) {
                IncludeRouteGlyph()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LEXICAL INCLUDE LOOM / TRANSITIVE PROVENANCE")
                        .includeEyebrow(color: AppPalette.ibmBlue)
                    Text(chain.rootPath)
                        .font(.system(size: 16.5, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                    Text("Exact indexed targets traverse; ambiguity, cycles, limits, and missing host content stop visibly.")
                        .font(.system(size: 7.8))
                        .foregroundStyle(AppPalette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("NOT A COMPILER EXPANSION")
                    .includeEyebrow(color: AppPalette.warning)
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack {
                Text("DIRECTIVE PROVENANCE LEDGER")
                    .includeEyebrow(color: AppPalette.muted)
                Spacer()
                Text("LEVEL · SOURCE LINE · TARGET · RESOLUTION")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chain.directives) { directive in
                        Button {
                            if model.openSourceWorkspaceIncludeDirective(directive) { dismiss() }
                        } label: {
                            IncludeDirectiveRow(directive: directive)
                        }
                        .buttonStyle(.plain)
                    }
                    if chain.directives.isEmpty {
                        VStack(spacing: 8) {
                            IncludeRouteGlyph()
                                .frame(width: 44, height: 44)
                            Text("This indexed document has no lexical /COPY or /INCLUDE directive.")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.secondary)
                        }
                        .padding(28)
                    }
                }
            }
            .background(AppPalette.panel)
        }
    }

    private func trustGate(_ chain: SourceWorkspaceIncludeChain) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IncludeBoundaryMark()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FAIL-CLOSED EVIDENCE")
                        .includeEyebrow(color: AppPalette.ibmBlue)
                    Text("Trust boundaries")
                        .font(.system(size: 17, weight: .bold))
                    Text("No guessed branch enters completion.")
                        .font(.system(size: 7.8))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                IncludeChainBadge(
                    label: "\(chain.boundaries.count) GAPS",
                    color: chain.boundaries.isEmpty ? AppPalette.success : AppPalette.danger
                )
            }
            .padding(.horizontal, 13)
            .frame(height: 72)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chain.boundaries) { boundary in
                        Button {
                            model.selectSourceWorkspaceIncludeBoundary(boundary.id)
                        } label: {
                            IncludeBoundaryRow(
                                boundary: boundary,
                                selected: boundary.id == model.selectedSourceWorkspaceIncludeBoundary?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if chain.boundaries.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("EXACT CLOSURE")
                                .includeEyebrow(color: AppPalette.success)
                            Text("Every observed include resolved to one indexed document.")
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppPalette.secondary)
                        }
                        .padding(14)
                    }
                }
            }
            .frame(maxHeight: 210)
            .background(AppPalette.panel)

            boundaryInspector

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("EXACT CLOSURE RECEIPT")
                        .includeEyebrow(color: AppPalette.muted)
                    Spacer()
                    Text(chain.shortFingerprint)
                        .includeEyebrow(color: AppPalette.success)
                }
                Text("Stage \(chain.documents.count) exact document(s). Visible boundaries stay excluded, and completion review remains separate.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Use Exact Closure") { model.useSourceWorkspaceIncludeClosure() }
                    .buttonStyle(IncludeChainPrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
    }

    @ViewBuilder
    private var boundaryInspector: some View {
        if let boundary = model.selectedSourceWorkspaceIncludeBoundary {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SELECTED BOUNDARY")
                        .includeEyebrow(color: boundaryColor(boundary.kind))
                    Spacer()
                    Text("LINE \(boundary.range.startLine)")
                        .includeEyebrow(color: AppPalette.muted)
                }
                Text(boundary.kind.label)
                    .font(.system(size: 14.5, weight: .bold))
                Text(boundary.targetLabel)
                    .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(boundary.detail)
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
                Button("Open Exact Source Line") {
                    if model.openSourceWorkspaceIncludeBoundary(boundary) { dismiss() }
                }
                .buttonStyle(IncludeChainOutlineButtonStyle())
            }
            .padding(13)
            .frame(height: 142, alignment: .top)
            .background(boundaryColor(boundary.kind).opacity(0.055))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("BOUNDARY INSPECTOR")
                    .includeEyebrow(color: AppPalette.success)
                Text("No unresolved include boundary is present in this receipt.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            .padding(13)
            .frame(height: 142, alignment: .top)
            .background(AppPalette.panel)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
    }

    private var lockedState: some View {
        VStack(spacing: 14) {
            IncludeBoundaryMark()
                .frame(width: 62, height: 62)
            Text("Exact workspace verification is required")
                .font(.system(size: 22, weight: .bold))
            Text("Pending path signals or a stale root revoked this index-bound include map. Verify exact bytes, then rebuild the map.")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("Rebuild Current Map") { model.refreshSourceWorkspaceIncludeChain() }
                .buttonStyle(IncludeChainPrimaryButtonStyle())
                .disabled(!model.sourceWorkspaceEvidenceIsCurrent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.window)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(chain.map { "MAP: \($0.shortFingerprint) · \($0.documents.count) DOCS · \($0.directives.count) DIRECTIVES" } ?? "MAP: LOCKED")
                .foregroundStyle(chain == nil ? AppPalette.warning : AppPalette.terminalGreen)
            Text("SOURCE PERSISTENCE: NONE")
                .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.36))
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .font(.system(size: 8, design: .default).italic())
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
            Text("ARM64 · SESSION ONLY")
                .foregroundStyle(.white)
        }
        .font(.system(size: 7.3, weight: .bold, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(AppPalette.instrument)
    }

    private func statusColor(_ chain: SourceWorkspaceIncludeChain) -> Color {
        switch chain.completion {
        case .exact: AppPalette.success
        case .boundariesVisible: AppPalette.warning
        case .traversalLimitReached: AppPalette.danger
        }
    }

    private func boundaryColor(_ kind: SourceWorkspaceIncludeBoundaryKind) -> Color {
        switch kind {
        case .hostContentNotLoaded: AppPalette.registrationBlue
        case .unresolved: AppPalette.danger
        case .ambiguous, .cycle, .depthLimit, .documentLimit, .directiveLimit: AppPalette.warning
        }
    }
}

private struct IncludeChainDocumentRow: View {
    let document: SourceWorkspaceIncludeDocument
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(selected ? AppPalette.ibmBlue : AppPalette.borderStrong)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.relativePath.split(separator: "/").last.map(String.init)?.uppercased() ?? document.relativePath.uppercased())
                    .font(.system(size: 8.2, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.text)
                    .lineLimit(1)
                Text("L\(document.depth) · \(document.originLabel) · \(document.shortFingerprint)")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(selected ? "ROOT" : "REMAP")
                .includeEyebrow(color: selected ? AppPalette.ibmBlue : AppPalette.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(selected ? AppPalette.selection : AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

private struct IncludeDirectiveRow: View {
    let directive: SourceWorkspaceIncludeDirective

    private var color: Color {
        switch directive.resolution {
        case .exact, .shared: AppPalette.success
        case .hostContentNotLoaded: AppPalette.registrationBlue
        case .unresolved: AppPalette.danger
        case .ambiguous, .cycle, .depthLimit, .documentLimit: AppPalette.warning
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(color).frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("L\(directive.targetDepth)")
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text("LINE \(directive.range.startLine)")
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(directive.kind.label) · \(directive.targetLabel)")
                    .font(.system(size: 8.2, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text(directive.sourcePath)
                    .font(.system(size: 7.3))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(directive.resolution.label)
                .includeEyebrow(color: color)
                .multilineTextAlignment(.trailing)
            Text("OPEN")
                .includeEyebrow(color: AppPalette.text)
                .padding(.horizontal, 7)
                .frame(height: 23)
                .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

private struct IncludeBoundaryRow: View {
    let boundary: SourceWorkspaceIncludeBoundary
    let selected: Bool

    private var color: Color {
        switch boundary.kind {
        case .hostContentNotLoaded: AppPalette.registrationBlue
        case .unresolved: AppPalette.danger
        case .ambiguous, .cycle, .depthLimit, .documentLimit, .directiveLimit: AppPalette.warning
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Rectangle().fill(color).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(boundary.kind.label)
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(boundary.targetLabel)
                    .font(.system(size: 7.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text("\(boundary.sourcePath):\(boundary.range.startLine)")
                    .font(.system(size: 7))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("›")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .frame(height: 68)
        .background(selected ? color.opacity(0.09) : AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

private struct IncludeChainMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).includeEyebrow(color: AppPalette.muted)
            HStack(spacing: 6) {
                Rectangle().fill(color).frame(width: 3, height: 14)
                Text(value)
                    .font(.system(size: value.count > 4 ? 11 : 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(AppPalette.border).frame(width: 1) }
    }
}

private struct IncludeChainBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 4, height: 15)
            Text(label)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(color.opacity(0.07))
        .overlay { Rectangle().stroke(color.opacity(0.65), lineWidth: 1) }
    }
}

private struct IncludeLoomMark: View {
    let compact: Bool

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 50
            let scaleY = size.height / 50
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scaleX, y: y * scaleY)
            }
            var route = Path()
            route.move(to: point(5, 9))
            route.addLine(to: point(18, 9))
            route.addLine(to: point(18, 22))
            route.addLine(to: point(33, 22))
            route.addLine(to: point(33, 10))
            route.addLine(to: point(44, 10))
            route.move(to: point(18, 22))
            route.addLine(to: point(18, 38))
            route.addLine(to: point(34, 38))
            route.addLine(to: point(44, 45))
            context.stroke(route, with: .color(AppPalette.terminalGreen), lineWidth: compact ? 1.5 : 1.8)
            context.fill(Path(ellipseIn: CGRect(x: 3 * scaleX, y: 6 * scaleY, width: 7 * scaleX, height: 7 * scaleY)), with: .color(AppPalette.ibmBlue))
            context.fill(Path(ellipseIn: CGRect(x: 41 * scaleX, y: 7 * scaleY, width: 7 * scaleX, height: 7 * scaleY)), with: .color(.white))
            context.fill(Path(CGRect(x: 31 * scaleX, y: 35 * scaleY, width: 7 * scaleX, height: 7 * scaleY)), with: .color(AppPalette.warning))
            context.fill(Path(ellipseIn: CGRect(x: 41 * scaleX, y: 41 * scaleY, width: 7 * scaleX, height: 7 * scaleY)), with: .color(AppPalette.terminalGreen))
        }
        .padding(compact ? 6 : 7)
        .background(AppPalette.terminal)
        .overlay { Rectangle().stroke(compact ? AppPalette.ibmBlue : Color.white.opacity(0.16), lineWidth: 1) }
        .accessibilityLabel("Include loom mark showing an exact route and a visible boundary")
    }
}

private struct IncludeRouteGlyph: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 4, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width * 0.38, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width * 0.38, y: 7))
            path.addLine(to: CGPoint(x: size.width * 0.72, y: 7))
            path.move(to: CGPoint(x: size.width * 0.38, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width * 0.38, y: size.height - 7))
            path.addLine(to: CGPoint(x: size.width - 5, y: size.height - 7))
            context.stroke(path, with: .color(AppPalette.terminalGreen), lineWidth: 1.5)
            context.fill(Path(ellipseIn: CGRect(x: 2, y: size.height / 2 - 3, width: 6, height: 6)), with: .color(AppPalette.ibmBlue))
            context.fill(Path(ellipseIn: CGRect(x: size.width - 9, y: size.height - 10, width: 6, height: 6)), with: .color(AppPalette.warning))
        }
        .padding(5)
        .background(AppPalette.terminal)
        .accessibilityHidden(true)
    }
}

private struct IncludeBoundaryMark: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 7, y: 5))
            path.addLine(to: CGPoint(x: 7, y: size.height - 5))
            path.move(to: CGPoint(x: 7, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width * 0.55, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width * 0.55, y: 8))
            context.stroke(path, with: .color(AppPalette.terminalGreen), lineWidth: 1.5)
            context.fill(Path(CGRect(x: size.width - 12, y: size.height / 2 - 5, width: 10, height: 10)), with: .color(AppPalette.danger))
        }
        .padding(5)
        .background(AppPalette.terminal)
        .accessibilityLabel("Trust boundary mark")
    }
}

private struct IncludeChainPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.2, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(AppPalette.instrument.opacity(configuration.isPressed ? 0.78 : 1))
            .overlay(alignment: .leading) {
                Rectangle().fill(AppPalette.terminalGreen).frame(width: 4, height: 18).padding(.leading, 2)
            }
    }
}

private struct IncludeChainOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.2, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.text)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(AppPalette.panel.opacity(configuration.isPressed ? 0.72 : 1))
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
    }
}

private extension View {
    func includeEyebrow(color: Color) -> some View {
        font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(color)
    }
}
