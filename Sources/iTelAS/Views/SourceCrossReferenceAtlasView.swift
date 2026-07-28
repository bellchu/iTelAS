import Foundation
import SwiftUI
import UniformTypeIdentifiers
import iTelASCore

struct SourceCrossReferenceAtlasView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isFolderImporterPresented = false
    @State private var isRefreshReceiptPresented = false
    @State private var topologyFilter = ""
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            custodyBand
            HStack(spacing: 0) {
                topologyRail
                    .frame(width: 268)
                Rectangle().fill(AppPalette.border).frame(width: 1)
                evidenceStage
                Rectangle().fill(AppPalette.border).frame(width: 1)
                dependencyGate
                    .frame(width: 370)
            }
            footer
        }
        .background(AppPalette.window)
        .sheet(isPresented: $model.isSourceWorkspaceRenameReviewPresented) {
            SourceWorkspaceRenameReviewView()
                .environment(model)
                .frame(width: 1_180, height: 760)
        }
        .sheet(isPresented: $model.isSourceWorkspaceHostIncludeReviewPresented) {
            SourceWorkspaceHostIncludeReviewView()
                .environment(model)
                .frame(width: 1_180, height: 760)
        }
        .sheet(isPresented: $model.isSourceWorkspaceCompileEvidencePresented) {
            SourceWorkspaceCompilerEvidenceView()
                .environment(model)
                .frame(width: 1_180, height: 760)
        }
        .sheet(isPresented: $model.isSourceWorkspaceIncludeChainPresented) {
            SourceWorkspaceIncludeChainView()
                .environment(model)
                .frame(width: 1_180, height: 760)
        }
        .sheet(isPresented: $isRefreshReceiptPresented) {
            SourceWorkspaceIndexRefreshReceiptView()
                .environment(model)
                .frame(width: 1_080, height: 720)
        }
        .sheet(isPresented: $model.isSourceWorkspaceDriftReceiptPresented) {
            SourceWorkspaceDriftReceiptView()
                .environment(model)
                .frame(width: 1_080, height: 720)
        }
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.scanSourceWorkspace(at: url)
            case .failure(let error):
                model.sourceWorkspaceIndexDiagnostic = "Folder selection failed: \(error.localizedDescription)"
            }
        }
        .onAppear {
            proverb = .random(excluding: proverb.id)
            if model.selectedSourceWorkspacePath == nil {
                model.selectedSourceWorkspacePath = model.sourceWorkspaceIndex.documents.first?.relativePath
            }
            model.ensureSourceWorkspaceSearch()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandWordmark(compact: true)
            Rectangle().fill(AppPalette.border).frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("SOURCE CROSS-REFERENCE ATLAS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Workspace symbols · includes · impact evidence")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            Button { isRefreshReceiptPresented = true } label: {
                AtlasBadge(
                    label: model.sourceWorkspaceIndexRefreshStatusLabel,
                    color: model.sourceWorkspaceIndexPhase == .ready ? AppPalette.success : AppPalette.warning
                )
            }
            .buttonStyle(.plain)
            .disabled(model.currentSourceWorkspaceIndexBuildReport == nil)
            .help("Open the exact local index refresh receipt")
            Button { model.isSourceWorkspaceDriftReceiptPresented = true } label: {
                AtlasBadge(
                    label: model.sourceWorkspaceDriftStatusLabel,
                    color: driftStatusColor
                )
            }
            .buttonStyle(.plain)
            .help("Open the path-only workspace signal receipt")
            AtlasBadge(
                label: "\(model.sourceWorkspaceIndex.localFileCount) LOCAL · \(model.sourceWorkspaceIndex.hostIncludeFileCount) HOST · \(model.sourceWorkspaceIndex.symbolCount) SYMBOLS",
                color: AppPalette.registrationBlue
            )
            Button("Replay") { model.restoreSourceWorkspaceIndexReplay() }
                .buttonStyle(AtlasOutlineButtonStyle())
                .disabled(model.sourceWorkspaceRenameApplyPhase.isApplying || model.sourceWorkspaceHostIncludePhase.isReading)
            Button("Compile Evidence") { model.presentSourceWorkspaceCompileEvidence() }
                .buttonStyle(AtlasOutlineButtonStyle())
                .disabled(model.sourceWorkspaceRenameApplyPhase.isApplying || model.sourceWorkspaceHostIncludePhase.isReading)
            Button(model.currentSourceWorkspaceIndexBuildReport?.isIncremental == true ? "Refresh Changes" : "Refresh") {
                model.refreshSourceWorkspaceIndex()
            }
                .buttonStyle(AtlasOutlineButtonStyle())
                .disabled(model.sourceWorkspaceIndexPhase.isIndexing || model.sourceWorkspaceRenameApplyPhase.isApplying || model.sourceWorkspaceHostIncludePhase.isReading)
            Button("Choose Folder") { isFolderImporterPresented = true }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .disabled(model.sourceWorkspaceIndexPhase.isIndexing || model.sourceWorkspaceRenameApplyPhase.isApplying || model.sourceWorkspaceHostIncludePhase.isReading)
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.secondary)
                .disabled(model.sourceWorkspaceRenameApplyPhase.isApplying || model.sourceWorkspaceHostIncludePhase.isReading)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var custodyBand: some View {
        HStack(spacing: 18) {
            SourceAtlasTopologyMark()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("INDEXED ROOT")
                    .atlasEyebrow(color: AppPalette.terminalGreen)
                Text(model.sourceWorkspaceIndex.rootName.uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(indexedRootDetail)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(width: 315, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text("INDEX CONTRACT")
                    .atlasEyebrow(color: AppPalette.terminal(.blue))
                Text(model.currentSourceWorkspaceIndexBuildReport?.isIncremental == true
                    ? model.sourceWorkspaceHasPendingDrift
                        ? "Workspace signals revoked exactness"
                        : "Exact bytes decide analysis reuse"
                    : "Bounded local analysis + responsive search")
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(.white)
                Text(model.currentSourceWorkspaceIndexBuildReport?.isIncremental == true
                    ? model.sourceWorkspaceHasPendingDrift
                        ? "Paths and flags only · no source bytes read · completion, compiler, rename, and navigation locked"
                        : "Every supported file re-read · exact path, format, and bytes required · dependencies rebuilt"
                    : "Cancellable off-main query · stale generations discarded · source stays local · exact reviewed reads")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.sourceWorkspaceHasPendingDrift ? "PATH-ONLY SIGNALS" : model.sourceWorkspaceIndexPhase == .localReplay ? "DETERMINISTIC REPLAY" : "LOCAL MEMORY")
                        .foregroundStyle(AppPalette.warning)
                    Text("ARM64")
                        .foregroundStyle(AppPalette.terminalGreen)
                }
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                Text("INDEX \(model.sourceWorkspaceIndex.shortFingerprint) · SEARCH \(model.currentSourceWorkspaceSearchReport?.shortFingerprint ?? "NONE")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(model.currentSourceWorkspaceIndexBuildReport.map { _ in
                    model.sourceWorkspaceHasPendingDrift
                        ? "\(model.sourceWorkspaceDriftReceiptLabel) · 0 source reads · API key unread"
                        : "\(model.sourceWorkspaceIndexRefreshReceiptLabel) · source stays local · API key unread"
                } ?? model.sourceWorkspaceHostIncludeContent.map {
                    "Host overlay \($0.shortFingerprint) · API key unread · no host write"
                } ?? "Provider idle · API key unread · host lookup none")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 86)
        .background(AppPalette.instrument)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
    }

    private var topologyRail: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKSPACE MAP / \(model.sourceWorkspaceIndex.fileCount)")
                        .atlasEyebrow(color: AppPalette.ibmBlue)
                    Text("Source topology")
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer()
                Text(model.sourceWorkspaceIndexPhase == .ready ? "CURRENT" : "REPLAY")
                    .atlasEyebrow(color: model.sourceWorkspaceIndexPhase == .ready ? AppPalette.success : AppPalette.warning)
            }
            .padding(.horizontal, 13)
            .frame(height: 64)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                TextField("Filter path or language", text: $topologyFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9))
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredDocuments) { document in
                        Button {
                            model.selectSourceWorkspaceDocument(document.relativePath)
                        } label: {
                            SourceAtlasDocumentRow(
                                document: document,
                                selected: model.selectedSourceWorkspacePath == document.relativePath
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if filteredDocuments.isEmpty {
                        Text("No indexed path matches this filter.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(AppPalette.secondary)
                            .padding(18)
                    }
                }
            }
            .background(AppPalette.panel)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.currentSourceWorkspaceIndexBuildReport == nil ? "INDEX COVERAGE" : "REFRESH COVERAGE")
                        .atlasEyebrow(color: AppPalette.muted)
                    Spacer()
                    Text("\(model.sourceWorkspaceIndex.skippedFiles.count) SKIPPED")
                        .atlasEyebrow(color: AppPalette.warning)
                }
                ForEach(activeCoverageRows, id: \.0) { row in
                    SourceAtlasCoverageRow(label: row.0, count: row.1, total: activeCoverageTotal)
                }
            }
            .padding(12)
            .frame(height: 128)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
    }

    private var evidenceStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RESPONSIVE INDEX QUERY")
                        .atlasEyebrow(color: AppPalette.ibmBlue)
                    Text("Search stays responsive")
                        .font(.system(size: 17, weight: .bold))
                }
                .frame(width: 196, alignment: .leading)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppPalette.ibmBlue)
                    TextField("Symbol, reference, path, or text", text: Binding(
                        get: { model.sourceWorkspaceSearchQuery },
                        set: { model.updateSourceWorkspaceSearchQuery($0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .onSubmit { model.refreshSourceWorkspaceSearch() }
                    Spacer()
                    if model.sourceWorkspaceSearchPhase.isSearching {
                        ProgressView()
                            .controlSize(.mini)
                        Button("Cancel") { model.cancelSourceWorkspaceSearch() }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.danger)
                    } else {
                        Text(model.sourceWorkspaceSearchStatusLabel)
                            .foregroundStyle(searchStatusColor)
                    }
                    Text("⌘⇧F")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(AppPalette.raised)
                .overlay { Rectangle().stroke(AppPalette.ibmBlue.opacity(0.72), lineWidth: 1) }
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 0) {
                AtlasMetric(label: "RESULTS", value: String(model.sourceWorkspaceSearchResults.count), color: AppPalette.ibmBlue)
                AtlasMetric(
                    label: "FILES EXAMINED",
                    value: "\(model.currentSourceWorkspaceSearchReport?.examinedDocumentCount ?? 0)/\(model.sourceWorkspaceIndex.fileCount)",
                    color: AppPalette.success
                )
                AtlasMetric(
                    label: "CANDIDATES",
                    value: String(model.currentSourceWorkspaceSearchReport?.candidateCount ?? 0),
                    color: AppPalette.warning
                )
                AtlasMetric(
                    label: "SEARCH RECEIPT",
                    value: model.currentSourceWorkspaceSearchReport?.shortFingerprint ?? "PENDING",
                    color: model.currentSourceWorkspaceSearchReport?.isTruncated == true ? AppPalette.danger : AppPalette.registrationBlue
                )
            }
            .frame(height: 46)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            selectedDocumentHeader
            dependencyCorridor

            HStack {
                Text("SEARCH RESULT LEDGER")
                    .atlasEyebrow(color: AppPalette.muted)
                Spacer()
                Text("KIND · PATH · EXACT LINE")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 31)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.sourceWorkspaceSearchResults) { result in
                        Button {
                            if model.openSourceWorkspaceResult(result) {
                                dismiss()
                            }
                        } label: {
                            SourceAtlasResultRow(
                                result: result,
                                selected: model.selectedSourceWorkspacePath == result.relativePath
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if model.sourceWorkspaceSearchResults.isEmpty {
                        VStack(spacing: 8) {
                            if model.sourceWorkspaceSearchPhase.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(emptySearchMessage)
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(22)
                    }
                }
            }
            .background(AppPalette.panel)
        }
    }

    private var selectedDocumentHeader: some View {
        HStack(spacing: 11) {
            SourceAtlasBranchGlyph()
                .frame(width: 38, height: 38)
            if let document = model.selectedSourceWorkspaceDocument {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(document.format.rawValue) / EXACT CONTENT BASELINE")
                        .atlasEyebrow(color: AppPalette.ibmBlue)
                    Text(document.displayName)
                        .font(.system(size: 18, weight: .bold))
                    Text("\(document.relativePath) · \(document.lineCount) lines · \(document.shortFingerprint)")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                }
                Spacer()
                AtlasBadge(
                    label: "\(document.snapshot.symbols.count) SYMBOLS",
                    color: AppPalette.success
                )
                if !model.sourceWorkspaceCompileDiagnosticsForSelectedDocument.isEmpty {
                    AtlasBadge(
                        label: "\(model.sourceWorkspaceCompileDiagnosticsForSelectedDocument.count) COMPILER",
                        color: AppPalette.danger
                    )
                }
            } else {
                Text("Select an indexed document or search result.")
                    .foregroundStyle(AppPalette.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var dependencyCorridor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("INCLUDE CHAIN NAVIGATOR / TRANSITIVE EVIDENCE")
                    .atlasEyebrow(color: AppPalette.muted)
                Spacer()
                Text("LEXICAL · NOT A COMPILER EXPANSION")
                    .atlasEyebrow(color: AppPalette.warning)
            }
            HStack(spacing: 7) {
                SourceAtlasCorridorNode(
                    title: "DOCUMENTS",
                    value: String(model.currentSourceWorkspaceIncludeChain?.documents.count ?? 0),
                    color: AppPalette.ibmBlue
                )
                SourceAtlasConnector()
                SourceAtlasCorridorNode(
                    title: "DIRECTIVES",
                    value: String(model.currentSourceWorkspaceIncludeChain?.directives.count ?? 0),
                    color: AppPalette.success,
                    emphasized: true
                )
                SourceAtlasConnector()
                SourceAtlasCorridorNode(
                    title: "MAX DEPTH",
                    value: String(model.currentSourceWorkspaceIncludeChain?.maximumDepthObserved ?? 0),
                    color: AppPalette.warning
                )
                SourceAtlasConnector(dashed: true)
                SourceAtlasCorridorNode(
                    title: "BOUNDARIES",
                    value: String(model.currentSourceWorkspaceIncludeChain?.boundaries.count ?? 0),
                    color: AppPalette.danger
                )
            }
            HStack(spacing: 8) {
                ForEach(model.currentSourceWorkspaceIncludeChain?.directives.prefix(2).map { $0 } ?? []) { directive in
                    Text("L\(directive.targetDepth) · \(directive.kind.label) · \(directive.targetLabel) · \(directive.resolution.label)")
                        .font(.system(size: 6.7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(resolutionColor(directive.resolution))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(resolutionColor(directive.resolution).opacity(0.08))
                        .overlay { Rectangle().stroke(resolutionColor(directive.resolution).opacity(0.4), lineWidth: 1) }
                }
                Spacer()
                Button("Open Include Chain") { model.presentSourceWorkspaceIncludeChain() }
                    .buttonStyle(AtlasOutlineButtonStyle())
                    .disabled(!model.sourceWorkspaceEvidenceIsCurrent)
            }
            if let candidate = model.selectedSourceWorkspaceHostIncludeCandidate {
                HStack(spacing: 8) {
                    SourceAtlasHostRelayMark()
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("EXACT HOST INCLUDE INTAKE")
                            .atlasEyebrow(color: AppPalette.registrationBlue)
                        Text("\(candidate.kind.label) · \(candidate.targetLabel)")
                            .font(.system(size: 7.2, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if model.sourceWorkspaceHostIncludeNeedsLibrary {
                        TextField("LIBRARY", text: Binding(
                            get: { model.sourceWorkspaceHostIncludeLibrary },
                            set: { model.sourceWorkspaceHostIncludeLibrary = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(width: 88, height: 24)
                        .background(AppPalette.panel)
                        .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
                    }
                    Button("Review Exact Host Read") {
                        model.presentSourceWorkspaceHostIncludeReview(candidate.id)
                    }
                    .buttonStyle(AtlasOutlineButtonStyle())
                    .disabled(
                        model.sourceWorkspaceHostIncludeNeedsLibrary
                            && model.sourceWorkspaceHostIncludeLibrary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .frame(height: 28)
            } else if let content = model.sourceWorkspaceHostIncludeContent {
                HStack(spacing: 8) {
                    SourceAtlasHostRelayMark()
                        .frame(width: 22, height: 22)
                    Text("HOST OVERLAY \(content.shortFingerprint) · \(content.target.displayName)")
                        .atlasEyebrow(color: AppPalette.success)
                        .lineLimit(1)
                    Spacer()
                    Button("Drop Overlay") { model.removeSourceWorkspaceHostIncludes() }
                        .buttonStyle(AtlasOutlineButtonStyle())
                }
                .frame(height: 28)
            }
        }
        .padding(12)
        .frame(height: 166)
        .background(Color(red: 0.975, green: 0.982, blue: 0.988))
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var dependencyGate: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SourceAtlasReviewMark()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                            Text(model.sourceWorkspaceHasPendingDrift ? "EXACTNESS LOCK" : reviewGateNeedsRefresh ? "REVIEW INVALIDATION" : "COMPLETION TRUST GATE")
                                .atlasEyebrow(color: AppPalette.ibmBlue)
                            Text(model.sourceWorkspaceHasPendingDrift ? "Verification required" : reviewGateNeedsRefresh ? "Receipts stay honest" : "Reviewed scope")
                                .font(.system(size: 17, weight: .bold))
                            Text(model.sourceWorkspaceHasPendingDrift
                                ? "Pending path signals lock every index-bound action"
                                : reviewGateNeedsRefresh
                                    ? "Index-bound reviews never inherit changed source"
                                    : "Only reviewed dependency symbols enter completion")
                        .font(.system(size: 7.5))
                        .foregroundStyle(AppPalette.secondary)
                }
                Spacer()
                AtlasBadge(
                    label: model.sourceWorkspaceDependencyReviewIsCurrent ? "REVIEWED" : "DRAFT",
                    color: model.sourceWorkspaceDependencyReviewIsCurrent ? AppPalette.success : AppPalette.warning
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 68)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack {
                Text("\(model.sourceWorkspaceDependencySelection.count) FILES")
                    .atlasEyebrow(color: AppPalette.ibmBlue)
                Text("·")
                    .foregroundStyle(AppPalette.muted)
                Text("INDEX \(model.sourceWorkspaceIndex.shortFingerprint)")
                    .atlasEyebrow(color: AppPalette.text)
                Spacer()
                Text(model.sourceWorkspaceDependencyReviewIsCurrent ? "CURRENT" : "REVIEW NEEDED")
                    .atlasEyebrow(color: model.sourceWorkspaceDependencyReviewIsCurrent ? AppPalette.success : AppPalette.warning)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(spacing: 0) {
                ForEach(dependencyCandidates.prefix(5)) { document in
                    Button {
                        model.toggleSourceWorkspaceDependency(document.relativePath)
                    } label: {
                        SourceAtlasDependencyReviewRow(
                            document: document,
                            selected: model.sourceWorkspaceDependencySelection.contains(document.relativePath)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if dependencyCandidates.isEmpty {
                    Text("No exact indexed dependency is available for this document.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                        .padding(15)
                }
            }
            .frame(minHeight: 92)
            .background(AppPalette.panel)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("REVIEW RECEIPT")
                        .atlasEyebrow(color: AppPalette.muted)
                    Spacer()
                    Text(model.sourceWorkspaceDependencyReview?.shortFingerprint ?? "NOT RECORDED")
                        .atlasEyebrow(color: model.sourceWorkspaceDependencyReviewIsCurrent ? AppPalette.success : AppPalette.muted)
                }
                Text(reviewGateNeedsRefresh
                    ? model.sourceWorkspaceHasPendingDrift
                        ? "macOS reported workspace changes. The signal receipt proves no content; exact-byte verification must rebuild current evidence."
                        : "The current delta receipt changed indexed evidence. Rebuild this scope from the current source before completion uses it."
                    : "The exact index, selected paths, and content fingerprints are frozen. Any changed file makes this scope stale.")
                    .font(.system(size: 7.8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review Dependencies for Completion") {
                    model.attestSourceWorkspaceDependencies()
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .disabled(model.sourceWorkspaceDependencySelection.isEmpty || !model.sourceWorkspaceEvidenceIsCurrent)
            }
            .padding(12)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SOURCE-DATE-AWARE PREVIEW")
                                .atlasEyebrow(color: AppPalette.ibmBlue)
                            Text("Rename corridor")
                                .font(.system(size: 16.5, weight: .bold))
                        }
                        Spacer()
                        AtlasBadge(label: "PREVIEW ONLY", color: AppPalette.warning)
                    }
                    HStack(spacing: 8) {
                        AtlasRenameField(
                            label: "CURRENT",
                            text: Binding(
                                get: { model.sourceWorkspaceRenameCurrentName },
                                set: { model.sourceWorkspaceRenameCurrentName = $0; model.invalidateSourceWorkspaceRenamePreview() }
                            )
                        )
                        Text("→")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.ibmBlue)
                        AtlasRenameField(
                            label: "PROPOSED",
                            text: Binding(
                                get: { model.sourceWorkspaceRenameProposedName },
                                set: { model.sourceWorkspaceRenameProposedName = $0; model.invalidateSourceWorkspaceRenamePreview() }
                            ),
                            accented: true
                        )
                    }
                    if let plan = model.sourceWorkspaceRenamePlan {
                        AtlasRenameMetric(label: "AFFECTED FILES", value: String(plan.baselines.count), color: AppPalette.ibmBlue)
                        AtlasRenameMetric(label: "TOKEN MATCHES", value: String(plan.occurrences.count), color: AppPalette.success)
                        AtlasRenameMetric(
                            label: "SOURCE DATES",
                            value: plan.baselines.contains(where: { $0.sourceDate != nil }) ? "PRESERVE" : "MTIME BASELINE",
                            color: AppPalette.warning
                        )
                        Text("Preview \(plan.shortFingerprint) is \(plan.isCurrent(for: model.sourceWorkspaceIndex) ? "current" : "stale"). Review binds its exact baselines before local application.")
                            .font(.system(size: 7.3, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                    } else {
                        Text("Prepare a token-aware preview. Comments and string literals are excluded; no file is rewritten.")
                            .font(.system(size: 7.8))
                            .foregroundStyle(AppPalette.secondary)
                    }
                    Button("Prepare Exact Rename Preview") {
                        model.prepareSourceWorkspaceRenamePlan()
                    }
                    .buttonStyle(AtlasOutlineButtonStyle())
                    .disabled(!model.sourceWorkspaceEvidenceIsCurrent)
                    if let plan = model.sourceWorkspaceRenamePlan {
                        Button(model.sourceWorkspaceUsesSelectedFolder ? "Review Exact Rename Batch" : "Review Replay Gate") {
                            model.presentSourceWorkspaceRenameReview()
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(!plan.isCurrent(for: model.sourceWorkspaceIndex) || !model.sourceWorkspaceEvidenceIsCurrent)
                    }
                    if let receipt = model.sourceWorkspaceRenameApplyReceipt {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LAST VERIFIED APPLY · \(receipt.shortFingerprint)")
                                .atlasEyebrow(color: AppPalette.success)
                            Text("\(receipt.replacementCount) tokens · \(receipt.changedPaths.count) files · fresh index required")
                                .font(.system(size: 7.3, design: .monospaced))
                                .foregroundStyle(AppPalette.secondary)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppPalette.success.opacity(0.07))
                        .overlay { Rectangle().stroke(AppPalette.success.opacity(0.45), lineWidth: 1) }
                    }
                }
                .padding(12)
            }
            .background(AppPalette.panel)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("INDEX: \(model.sourceWorkspaceIndexRefreshStatusLabel) · \(model.sourceWorkspaceIndex.localFileCount) LOCAL")
                .foregroundStyle(AppPalette.terminalGreen)
            Text("SEARCH: \(model.sourceWorkspaceSearchStatusLabel)")
                .foregroundStyle(Color(red: 0.92, green: 0.64, blue: 0.32))
            Text("EVIDENCE: \(model.sourceWorkspaceCompileStatusLabel)")
                .foregroundStyle(AppPalette.registrationBlue)
            Text("WATCH: \(model.sourceWorkspaceDriftPhase.label)")
                .foregroundStyle(driftStatusColor)
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .italic()
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Text("ARM64 · LOCAL INDEX")
                .foregroundStyle(.white)
        }
        .font(.system(size: 6.8, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(AppPalette.instrument)
    }

    private var searchStatusColor: Color {
        if model.sourceWorkspaceSearchPhase == .failed { return AppPalette.danger }
        if model.currentSourceWorkspaceSearchReport?.isTruncated == true { return AppPalette.warning }
        return model.sourceWorkspaceSearchReportIsCurrent ? AppPalette.success : AppPalette.muted
    }

    private var driftStatusColor: Color {
        if model.sourceWorkspaceDriftPhase == .watching { return AppPalette.success }
        if model.sourceWorkspaceDriftPhase == .failed { return AppPalette.danger }
        return AppPalette.warning
    }

    private var emptySearchMessage: String {
        if model.sourceWorkspaceSearchPhase.isSearching {
            return "Searching the frozen local index off the main interface. Superseded queries are discarded."
        }
        if model.sourceWorkspaceSearchPhase == .failed {
            return model.sourceWorkspaceSearchDiagnostic
        }
        if model.sourceWorkspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Browse mode shows exact indexed paths without running a text query."
        }
        return "No bounded result matches this current search receipt."
    }

    private var filteredDocuments: [SourceWorkspaceDocumentIndex] {
        let query = topologyFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.sourceWorkspaceIndex.documents }
        return model.sourceWorkspaceIndex.documents.filter {
            $0.relativePath.localizedCaseInsensitiveContains(query)
                || $0.format.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private var coverageRows: [(String, Int)] {
        let grouped = Dictionary(grouping: model.sourceWorkspaceIndex.documents, by: \.format)
        return SourceFormat.allCases.compactMap { format in
            guard let count = grouped[format]?.count, count > 0 else { return nil }
            return (format.rawValue, count)
        }.prefix(4).map { $0 }
    }

    private var activeCoverageRows: [(String, Int)] {
        guard let report = model.currentSourceWorkspaceIndexBuildReport else { return coverageRows }
        return [
            ("REUSED", report.reusedAnalysisCount),
            ("ANALYZED", report.reanalyzedDocumentCount),
            ("ADDED", report.addedDocumentCount),
            ("REMOVED", report.removedDocumentCount)
        ]
    }

    private var activeCoverageTotal: Int {
        guard let report = model.currentSourceWorkspaceIndexBuildReport else {
            return model.sourceWorkspaceIndex.fileCount
        }
        return max(report.inputFileCount, report.removedDocumentCount)
    }

    private var indexedRootDetail: String {
        guard let report = model.currentSourceWorkspaceIndexBuildReport else {
            return "\(model.sourceWorkspaceIndex.localFileCount) local UTF-8 · \(model.sourceWorkspaceIndex.hostIncludeFileCount) reviewed host · \(byteLabel(model.sourceWorkspaceIndex.totalUTF8Bytes))"
        }
        return "\(report.inputFileCount) UTF-8 files · \(byteLabel(report.inputUTF8ByteCount)) · \(report.reusedAnalysisCount) reused · \(report.analyzedDocumentCount) analyzed"
    }

    private var reviewGateNeedsRefresh: Bool {
        guard let report = model.currentSourceWorkspaceIndexBuildReport,
              report.isIncremental,
              !report.entries.isEmpty else { return false }
        return !model.sourceWorkspaceDependencyReviewIsCurrent
    }

    private var dependencyCandidates: [SourceWorkspaceDocumentIndex] {
        let exactPaths = model.selectedSourceWorkspaceOutboundDependencies
            .filter { $0.resolution == .exact }
            .flatMap(\.targetPaths)
        let paths = Set(exactPaths + Array(model.sourceWorkspaceDependencySelection))
        let candidates = paths.compactMap(model.sourceWorkspaceIndex.document(at:))
            .sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
        if !candidates.isEmpty { return candidates }
        return model.sourceWorkspaceIndex.documents
            .filter { $0.relativePath != model.selectedSourceWorkspacePath }
            .prefix(5).map { $0 }
    }

    private func byteLabel(_ count: Int) -> String {
        if count >= 1_024 * 1_024 { return String(format: "%.1f MB", Double(count) / 1_048_576) }
        if count >= 1_024 { return String(format: "%.1f KB", Double(count) / 1_024) }
        return "\(count) B"
    }

    private func resolutionColor(_ resolution: SourceWorkspaceDependencyResolutionKind) -> Color {
        switch resolution {
        case .exact: AppPalette.success
        case .ambiguous: AppPalette.warning
        case .hostBacked: AppPalette.registrationBlue
        case .unresolved: AppPalette.danger
        }
    }

    private func resolutionColor(_ resolution: SourceWorkspaceIncludeResolution) -> Color {
        switch resolution {
        case .exact, .shared: AppPalette.success
        case .ambiguous, .cycle, .depthLimit, .documentLimit: AppPalette.warning
        case .hostContentNotLoaded: AppPalette.registrationBlue
        case .unresolved: AppPalette.danger
        }
    }
}

struct SourceWorkspaceIndexRefreshReceiptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        VStack(spacing: 0) {
            header
            custodyBand
            if let report = model.currentSourceWorkspaceIndexBuildReport {
                metrics(report)
                HStack(spacing: 0) {
                    deltaLedger(report)
                    Rectangle().fill(AppPalette.border).frame(width: 1)
                    receiptDossier(report)
                        .frame(width: 334)
                }
            } else {
                ContentUnavailableView(
                    "Refresh receipt unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Refresh or choose a local source root to produce a current receipt.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
        .background(AppPalette.window)
        .onAppear { proverb = .random(excluding: proverb.id) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandWordmark(compact: true)
            Rectangle().fill(AppPalette.border).frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("INCREMENTAL INDEX REFRESH")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Exact byte comparison · reused analysis · dependency rebuild")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            if let report = model.currentSourceWorkspaceIndexBuildReport {
                AtlasBadge(
                    label: report.isIncremental ? "DELTA CURRENT" : "FULL CURRENT",
                    color: report.isIncremental ? AppPalette.success : AppPalette.warning
                )
                AtlasBadge(
                    label: "\(report.inputFileCount) FILES · \(report.analyzedDocumentCount) ANALYZED",
                    color: AppPalette.registrationBlue
                )
            }
            Button("Refresh Changes") {
                model.refreshSourceWorkspaceIndex()
            }
            .buttonStyle(AtlasOutlineButtonStyle())
            .disabled(model.sourceWorkspaceIndexPhase.isIndexing)
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
            SourceAtlasTopologyMark()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("INDEXED ROOT / REFRESH RECEIPT")
                    .atlasEyebrow(color: AppPalette.terminalGreen)
                Text(model.sourceWorkspaceIndex.rootName.uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(model.sourceWorkspaceIndex.localFileCount) local files · \(byteLabel(model.sourceWorkspaceIndex.totalUTF8Bytes)) · source memory only")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(width: 300, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text("REFRESH CONTRACT")
                    .atlasEyebrow(color: AppPalette.terminal(.blue))
                Text("Exact bytes decide analysis reuse")
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(.white)
                Text("Bytes re-read · exact path/format/UTF-8 match · dependencies rebuilt")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let report = model.currentSourceWorkspaceIndexBuildReport {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(report.previousShortFingerprint ?? "FIRST SCAN") → \(model.sourceWorkspaceIndex.shortFingerprint)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("DELTA \(report.shortFingerprint) · \(model.sourceWorkspaceIndexDurationMilliseconds ?? 0) MS")
                        .atlasEyebrow(color: AppPalette.warning)
                    Text("No disk cache · provider idle · API key unread · no host write")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 88)
        .background(AppPalette.instrument)
    }

    private func metrics(_ report: SourceWorkspaceIndexBuildReport) -> some View {
        HStack(spacing: 0) {
            AtlasMetric(label: "REUSED ANALYSIS", value: String(report.reusedAnalysisCount), color: AppPalette.ibmBlue)
            AtlasMetric(label: "REANALYZED", value: String(report.reanalyzedDocumentCount), color: AppPalette.success)
            AtlasMetric(label: "ADDED / REMOVED", value: "\(report.addedDocumentCount) / \(report.removedDocumentCount)", color: AppPalette.warning)
            AtlasMetric(label: "DELTA RECEIPT", value: report.shortFingerprint, color: AppPalette.danger)
        }
        .frame(height: 54)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func deltaLedger(_ report: SourceWorkspaceIndexBuildReport) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.isIncremental ? "CHANGED FILE LEDGER" : "INITIAL ANALYSIS LEDGER")
                        .atlasEyebrow(color: AppPalette.ibmBlue)
                    Text(report.entries.isEmpty ? "No source delta" : "Refresh proved what changed")
                        .font(.system(size: 17, weight: .bold))
                }
                Spacer()
                Text("STATE · PATH · CONTENT EVIDENCE")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(report.entries) { entry in
                        SourceIndexDeltaEntryRow(entry: entry)
                    }
                    if report.entries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .foregroundStyle(AppPalette.success)
                            Text("Every indexed path, format, and source byte matched the previous receipt. Dependencies were still rebuilt.")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(28)
                    }
                }
            }
            .background(AppPalette.panel)
        }
    }

    private func receiptDossier(_ report: SourceWorkspaceIndexBuildReport) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SourceAtlasReviewMark()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REFRESH CUSTODY")
                        .atlasEyebrow(color: AppPalette.ibmBlue)
                    Text("Receipt chain")
                        .font(.system(size: 17, weight: .bold))
                    Text("No prior review silently crosses an index change")
                        .font(.system(size: 7.5))
                        .foregroundStyle(AppPalette.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 66)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 7) {
                    SourceIndexReceiptNode(
                        label: "BEFORE",
                        value: report.previousShortFingerprint ?? "FIRST SCAN",
                        color: AppPalette.muted
                    )
                    Text("→")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                    SourceIndexReceiptNode(
                        label: "CURRENT",
                        value: model.sourceWorkspaceIndex.shortFingerprint,
                        color: AppPalette.ibmBlue
                    )
                }
                SourceIndexReceiptFact(label: "SOURCE BYTES READ", value: byteLabel(report.inputUTF8ByteCount), color: AppPalette.ibmBlue)
                SourceIndexReceiptFact(label: "ANALYSIS REUSED", value: String(report.reusedAnalysisCount), color: AppPalette.success)
                SourceIndexReceiptFact(label: "METADATA-ONLY", value: String(report.metadataOnlyDocumentCount), color: AppPalette.warning)
                SourceIndexReceiptFact(label: "DISK CACHE", value: "NONE", color: AppPalette.warning)
                SourceIndexReceiptFact(label: "HOST / PROVIDER", value: "NO ACTION", color: AppPalette.success)
                Text("Source text and analysis remain in application memory. Closing iTelAS discards this index; a later session performs a full analysis.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("BOUNDARY")
                        .atlasEyebrow(color: AppPalette.warning)
                    Text("A delta receipt proves local reuse decisions, not compiler correctness, object binding, release compatibility, or host state.")
                        .font(.system(size: 8))
                        .foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(AppPalette.warning.opacity(0.07))
                .overlay { Rectangle().stroke(AppPalette.warning.opacity(0.45), lineWidth: 1) }
            }
            .padding(13)
            .background(AppPalette.raised)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("INDEX: \(model.sourceWorkspaceIndexRefreshStatusLabel)")
                .foregroundStyle(AppPalette.terminalGreen)
            Text(model.sourceWorkspaceIndexRefreshReceiptLabel)
                .foregroundStyle(Color(red: 0.92, green: 0.64, blue: 0.32))
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .italic()
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Text("ARM64 · MEMORY ONLY")
                .foregroundStyle(.white)
        }
        .font(.system(size: 6.8, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(AppPalette.instrument)
    }

    private func byteLabel(_ count: Int) -> String {
        if count >= 1_024 * 1_024 { return String(format: "%.1f MB", Double(count) / 1_048_576) }
        if count >= 1_024 { return String(format: "%.1f KB", Double(count) / 1_024) }
        return "\(count) B"
    }
}

struct SourceWorkspaceDriftReceiptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var proverb = WorkbenchProverb.random()

    var body: some View {
        VStack(spacing: 0) {
            header
            custodyBand
            metrics
            HStack(spacing: 0) {
                signalLedger
                Rectangle().fill(AppPalette.border).frame(width: 1)
                verificationPanel
                    .frame(width: 348)
            }
            footer
        }
        .background(AppPalette.window)
        .onAppear { proverb = .random(excluding: proverb.id) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandWordmark(compact: true)
            Rectangle().fill(AppPalette.border).frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("WORKSPACE DRIFT RADAR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("Recursive local signals · stale-evidence gates · exact-byte verification")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            AtlasBadge(label: model.sourceWorkspaceDriftStatusLabel, color: statusColor)
            AtlasBadge(
                label: "\(model.sourceWorkspaceDriftReceipt?.uniquePathCount ?? 0) PATHS · \(model.sourceWorkspaceDriftReceipt?.rawEventCount ?? 0) EVENTS",
                color: AppPalette.registrationBlue
            )
            Button("Verify now") { model.verifySourceWorkspaceDriftNow() }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .disabled(model.sourceWorkspaceDriftPhase == .localReplay || model.sourceWorkspaceIndexPhase.isIndexing)
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
            SourceWorkspaceDriftPulseMark()
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text("PATH-ONLY SIGNAL RECEIPT")
                    .atlasEyebrow(color: AppPalette.terminalGreen)
                Text(model.sourceWorkspaceIndex.rootName.uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Recursive macOS signals · supported source paths · session only")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(width: 300, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text("TRUST CONTRACT")
                    .atlasEyebrow(color: AppPalette.terminal(.blue))
                Text(model.sourceWorkspaceHasPendingDrift ? "Signals revoke exactness immediately" : "Exact evidence is current")
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(.white)
                Text("Advisory metadata only · exact-byte refresh is authoritative")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(model.sourceWorkspaceDriftReceiptLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("BASELINE \(String((model.sourceWorkspaceDriftReceipt?.baselineIndexFingerprint ?? model.sourceWorkspaceIndex.fingerprint).prefix(8)).uppercased())")
                    .atlasEyebrow(color: AppPalette.warning)
                Text("No disk cache · provider idle · API key unread · no host action")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 88)
        .background(AppPalette.instrument)
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            AtlasMetric(label: "SIGNALLED PATHS", value: String(model.sourceWorkspaceDriftReceipt?.uniquePathCount ?? 0), color: AppPalette.ibmBlue)
            AtlasMetric(label: "RAW EVENTS", value: String(model.sourceWorkspaceDriftReceipt?.rawEventCount ?? 0), color: AppPalette.warning)
            AtlasMetric(label: "SOURCE READS", value: "0", color: AppPalette.success)
            AtlasMetric(
                label: "VERIFICATION",
                value: model.sourceWorkspaceDriftReceipt?.requiresFullVerification == true ? "FULL" : "EXACT",
                color: AppPalette.danger
            )
        }
        .frame(height: 54)
        .background(AppPalette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var signalLedger: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("COALESCED SIGNAL LEDGER")
                        .atlasEyebrow(color: AppPalette.ibmBlue)
                    Text(model.sourceWorkspaceDriftReceipt?.entries.isEmpty == false ? "What macOS reported" : "No pending workspace signal")
                        .font(.system(size: 17, weight: .bold))
                }
                Spacer()
                Text("KIND · PATH · SIGNAL RECEIPT")
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let receipt = model.sourceWorkspaceDriftReceipt {
                        ForEach(receipt.entries) { entry in
                            SourceWorkspaceDriftEntryRow(entry: entry)
                        }
                    }
                    if model.sourceWorkspaceDriftReceipt?.entries.isEmpty != false {
                        VStack(spacing: 9) {
                            SourceWorkspaceDriftPulseMark()
                                .frame(width: 48, height: 48)
                            Text("Recursive monitoring has no unverified supported-source signal.")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.secondary)
                        }
                        .padding(30)
                    }
                }
            }
            .background(AppPalette.panel)

            signalCircuit
        }
    }

    private var signalCircuit: some View {
        HStack(spacing: 7) {
            DriftCircuitNode(label: "MACOS EVENTS", detail: "PATH + FLAGS", color: AppPalette.ibmBlue)
            Text("→").foregroundStyle(AppPalette.muted)
            DriftCircuitNode(label: "NORMALIZE", detail: "SAFE ROOT", color: AppPalette.registrationBlue)
            Text("→").foregroundStyle(AppPalette.muted)
            DriftCircuitNode(label: "COALESCE", detail: "650 MS", color: AppPalette.warning)
            Text("→").foregroundStyle(AppPalette.muted)
            DriftCircuitNode(label: "EXACTNESS", detail: "LOCK / VERIFY", color: AppPalette.success)
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 74)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var verificationPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SourceAtlasReviewMark()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXACTNESS GATES")
                        .atlasEyebrow(color: AppPalette.ibmBlue)
                    Text(model.sourceWorkspaceHasPendingDrift ? "Evidence locked" : "Evidence current")
                        .font(.system(size: 17, weight: .bold))
                    Text("No index-bound action inherits unverified source")
                        .font(.system(size: 7.5))
                        .foregroundStyle(AppPalette.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 66)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(spacing: 0) {
                DriftGateRow(label: "COMPLETION SCOPE", locked: gatesLocked)
                DriftGateRow(label: "COMPILER MAPPING", locked: gatesLocked)
                DriftGateRow(label: "RENAME APPLICATION", locked: gatesLocked)
                DriftGateRow(label: "OCCURRENCE NAVIGATION", locked: gatesLocked)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AUTOMATIC VERIFICATION")
                            .atlasEyebrow(color: AppPalette.ibmBlue)
                        Text("Coalesced refresh after 650 ms")
                            .font(.system(size: 8))
                            .foregroundStyle(AppPalette.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.sourceWorkspaceAutoRefreshEnabled },
                        set: { model.setSourceWorkspaceAutoRefreshEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(model.sourceWorkspaceDriftPhase == .localReplay)
                }
                HStack(spacing: 8) {
                    Button(model.sourceWorkspaceDriftPhase.isPaused ? "Resume watch" : "Pause watch") {
                        if model.sourceWorkspaceDriftPhase.isPaused {
                            model.resumeSourceWorkspaceDriftMonitoring()
                        } else {
                            model.pauseSourceWorkspaceDriftMonitoring()
                        }
                    }
                    .buttonStyle(AtlasOutlineButtonStyle())
                    .disabled(model.sourceWorkspaceDriftPhase == .localReplay || model.sourceWorkspaceIndexPhase.isIndexing)
                    Button("Verify now") { model.verifySourceWorkspaceDriftNow() }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(model.sourceWorkspaceDriftPhase == .localReplay || model.sourceWorkspaceIndexPhase.isIndexing)
                }
                Text(model.sourceWorkspaceDriftDiagnostic)
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    Text("BOUNDARY")
                        .atlasEyebrow(color: AppPalette.warning)
                    Text("A signal proves that macOS observed a path event. Only a complete bounded scan can prove current source bytes and rebuild evidence.")
                        .font(.system(size: 8))
                        .foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(AppPalette.warning.opacity(0.07))
                .overlay { Rectangle().stroke(AppPalette.warning.opacity(0.45), lineWidth: 1) }
            }
            .padding(13)
            .background(AppPalette.raised)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("WATCH: \(model.sourceWorkspaceDriftPhase.label)")
                .foregroundStyle(statusColor)
            Text(model.sourceWorkspaceDriftReceiptLabel)
                .foregroundStyle(Color(red: 0.92, green: 0.64, blue: 0.32))
            Text("EXACTNESS: \(model.sourceWorkspaceEvidenceIsCurrent ? "CURRENT" : "LOCKED")")
                .foregroundStyle(model.sourceWorkspaceEvidenceIsCurrent ? AppPalette.terminalGreen : AppPalette.warning)
            Spacer()
            Text("\(proverb.text) — \(proverb.source)")
                .italic()
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Text("ARM64 · SESSION ONLY")
                .foregroundStyle(.white)
        }
        .font(.system(size: 6.8, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(AppPalette.instrument)
    }

    private var gatesLocked: Bool {
        model.sourceWorkspaceDriftPhase != .localReplay && !model.sourceWorkspaceEvidenceIsCurrent
    }

    private var statusColor: Color {
        if model.sourceWorkspaceDriftPhase == .watching { return AppPalette.success }
        if model.sourceWorkspaceDriftPhase == .failed { return AppPalette.danger }
        return AppPalette.warning
    }
}

private struct SourceWorkspaceDriftEntryRow: View {
    let entry: SourceWorkspaceDriftEntry

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kinds.first?.label ?? "SIGNAL")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text("\(entry.rawEventCount) RAW")
                    .font(.system(size: 6.4, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .frame(width: 94, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayPath.uppercased())
                    .font(.system(size: 8.2, weight: .bold))
                    .lineLimit(1)
                Text(entry.kindLabel)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(entry.shortFingerprint)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 13)
        .frame(height: 58)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var color: Color {
        if entry.kinds.contains(.rescanRequired) || entry.kinds.contains(.rootChanged) { return AppPalette.danger }
        if entry.kinds.contains(.removed) || entry.kinds.contains(.renamed) { return AppPalette.warning }
        if entry.kinds.contains(.created) { return AppPalette.ibmBlue }
        return AppPalette.success
    }
}

private struct DriftCircuitNode: View {
    let label: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
            Text(detail)
                .font(.system(size: 6.2, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(AppPalette.panel)
        .overlay { Rectangle().stroke(color.opacity(0.6), lineWidth: 1) }
    }
}

private struct DriftGateRow: View {
    let label: String
    let locked: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Rectangle().fill((locked ? AppPalette.warning : AppPalette.success).opacity(0.1))
                Image(systemName: locked ? "lock.fill" : "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(locked ? AppPalette.warning : AppPalette.success)
            }
            .frame(width: 24, height: 24)
            Text(label)
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
            Spacer()
            Text(locked ? "LOCKED" : "CURRENT")
                .atlasEyebrow(color: locked ? AppPalette.warning : AppPalette.success)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct SourceWorkspaceDriftPulseMark: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Color(red: 0.035, green: 0.105, blue: 0.08)))
            context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(AppPalette.terminalGreen.opacity(0.35)), lineWidth: 1)

            var baseline = Path()
            baseline.move(to: CGPoint(x: 6, y: size.height * 0.55))
            baseline.addLine(to: CGPoint(x: size.width - 6, y: size.height * 0.55))
            context.stroke(baseline, with: .color(AppPalette.terminalGreen.opacity(0.45)), lineWidth: 1)

            var pulse = Path()
            pulse.move(to: CGPoint(x: 6, y: size.height * 0.55))
            pulse.addLine(to: CGPoint(x: size.width * 0.25, y: size.height * 0.55))
            pulse.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.30))
            pulse.addLine(to: CGPoint(x: size.width * 0.45, y: size.height * 0.73))
            pulse.addLine(to: CGPoint(x: size.width * 0.56, y: size.height * 0.40))
            pulse.addLine(to: CGPoint(x: size.width * 0.68, y: size.height * 0.55))
            pulse.addLine(to: CGPoint(x: size.width - 6, y: size.height * 0.55))
            context.stroke(pulse, with: .color(AppPalette.terminalGreen), lineWidth: 1.7)

            let nodes = [0.25, 0.45, 0.68]
            for (index, fraction) in nodes.enumerated() {
                let center = CGPoint(x: size.width * fraction, y: size.height * 0.55)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                    with: .color(index == 1 ? AppPalette.warning : AppPalette.ibmBlue)
                )
            }
        }
    }
}

private struct SourceIndexDeltaEntryRow: View {
    let entry: SourceWorkspaceIndexDeltaEntry

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.label)
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(entry.kind == .metadataOnly ? "REUSED" : entry.kind == .removed ? "RETIRED" : "ANALYZED")
                    .font(.system(size: 6.4, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.relativePath.uppercased())
                    .font(.system(size: 8.2, weight: .bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(entry.shortFingerprint)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 13)
        .frame(height: 58)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var color: Color {
        switch entry.kind {
        case .added: AppPalette.ibmBlue
        case .reanalyzed: AppPalette.success
        case .metadataOnly: AppPalette.warning
        case .removed: AppPalette.danger
        }
    }

    private var detail: String {
        let before = entry.previousContentFingerprint.map { String($0.prefix(8)).uppercased() } ?? "NONE"
        let after = entry.currentContentFingerprint.map { String($0.prefix(8)).uppercased() } ?? "NONE"
        switch entry.kind {
        case .added:
            return "New supported source · \(entry.currentUTF8ByteCount ?? 0) bytes · \(after)"
        case .reanalyzed:
            return "\(entry.previousUTF8ByteCount ?? 0) → \(entry.currentUTF8ByteCount ?? 0) bytes · \(before) → \(after)"
        case .metadataOnly:
            return "Exact source bytes matched · analysis reused · \(after)"
        case .removed:
            return "Absent from current root · prior \(entry.previousUTF8ByteCount ?? 0) bytes · \(before)"
        }
    }
}

private struct SourceIndexReceiptNode: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.panel)
        .overlay { Rectangle().stroke(color.opacity(0.65), lineWidth: 1) }
    }
}

private struct SourceIndexReceiptFact: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 6.6, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Spacer()
            Text(value)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct SourceAtlasDocumentRow: View {
    let document: SourceWorkspaceDocumentIndex
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(color)
                .frame(width: 4, height: 27)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayName.uppercased())
                    .font(.system(size: 8.2, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text("\(document.origin.label) · \(document.format.rawValue) · \(document.snapshot.symbols.count) SYMBOLS · \(document.shortFingerprint)")
                    .font(.system(size: 6.4, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Text(document.relativePath)
                    .font(.system(size: 6.7, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 11)
        .frame(height: 52)
        .background(selected ? AppPalette.selection : AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var color: Color {
        if document.origin.isHostBacked { return AppPalette.registrationBlue }
        return switch document.format {
        case .rpgle: AppPalette.ibmBlue
        case .clle: AppPalette.success
        case .cobol: Color(red: 0.42, green: 0.27, blue: 0.62)
        case .dds: AppPalette.warning
        case .sql: Color(red: 0.10, green: 0.47, blue: 0.52)
        case .text: AppPalette.muted
        }
    }
}

private struct SourceAtlasHostRelayMark: View {
    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            var route = Path()
            route.move(to: CGPoint(x: 3, y: 5))
            route.addLine(to: CGPoint(x: 9, y: 5))
            route.addLine(to: CGPoint(x: 9, y: midY))
            route.addLine(to: CGPoint(x: size.width - 5, y: midY))
            route.move(to: CGPoint(x: 3, y: size.height - 5))
            route.addLine(to: CGPoint(x: 9, y: size.height - 5))
            route.addLine(to: CGPoint(x: 9, y: midY))
            context.stroke(route, with: .color(AppPalette.terminalGreen), lineWidth: 1.4)
            context.fill(Path(ellipseIn: CGRect(x: 1, y: 2, width: 6, height: 6)), with: .color(AppPalette.ibmBlue))
            context.fill(Path(ellipseIn: CGRect(x: size.width - 7, y: midY - 3, width: 6, height: 6)), with: .color(AppPalette.terminalGreen))
        }
        .background(AppPalette.instrument)
        .overlay { Rectangle().stroke(AppPalette.registrationBlue.opacity(0.65), lineWidth: 1) }
    }
}

private struct SourceAtlasResultRow: View {
    let result: SourceWorkspaceSearchResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(color).frame(width: 4, height: 32)
            Text(result.kind.label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(result.relativePath.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .lineLimit(1)
                    Text("L\(result.line):\(result.column)")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Text(result.excerpt.isEmpty ? result.detail : result.excerpt)
                    .font(.system(size: 7.7, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("OPEN")
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
        }
        .padding(.horizontal, 12)
        .frame(height: 53)
        .background(selected ? AppPalette.selection.opacity(0.62) : AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var color: Color {
        switch result.kind {
        case .file: AppPalette.ibmBlue
        case .symbol: AppPalette.success
        case .reference: AppPalette.warning
        case .text: AppPalette.secondary
        }
    }
}

private struct SourceAtlasDependencyReviewRow: View {
    let document: SourceWorkspaceDocumentIndex
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Rectangle()
                    .fill(selected ? AppPalette.success : Color.clear)
                    .overlay { Rectangle().stroke(selected ? AppPalette.success : AppPalette.borderStrong, lineWidth: 1) }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.relativePath.uppercased())
                    .font(.system(size: 7.8, weight: .bold))
                    .lineLimit(1)
                Text("\(document.snapshot.symbols.count) SYMBOLS · \(document.shortFingerprint)")
                    .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct SourceAtlasCoverageRow: View {
    let label: String
    let count: Int
    let total: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 6.6, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .frame(width: 43, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppPalette.border)
                    Rectangle()
                        .fill(AppPalette.ibmBlue)
                        .frame(width: geometry.size.width * CGFloat(count) / CGFloat(max(1, total)))
                }
            }
            .frame(height: 4)
            Text(String(count))
                .font(.system(size: 6.6, weight: .bold, design: .monospaced))
                .frame(width: 18, alignment: .trailing)
        }
        .frame(height: 15)
    }
}

private struct AtlasMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(color).frame(width: 3, height: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) { Rectangle().fill(AppPalette.border).frame(width: 1) }
    }
}

private struct SourceAtlasCorridorNode: View {
    let title: String
    let value: String
    let color: Color
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
        .background(emphasized ? color.opacity(0.08) : AppPalette.panel)
        .overlay { Rectangle().stroke(color.opacity(emphasized ? 0.9 : 0.5), lineWidth: 1) }
    }
}

private struct SourceAtlasConnector: View {
    var dashed = false

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                path,
                with: .color(AppPalette.borderStrong),
                style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : [])
            )
        }
        .frame(width: 18, height: 45)
    }
}

private struct AtlasRenameField: View {
    let label: String
    @Binding var text: String
    var accented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 6.2, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            TextField(label, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(accented ? AppPalette.selection : AppPalette.raised)
                .overlay { Rectangle().stroke(accented ? AppPalette.ibmBlue : AppPalette.borderStrong, lineWidth: 1) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AtlasRenameMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Spacer()
            Text(value)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(height: 20)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct AtlasBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 4, height: 15)
            Text(label)
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(color.opacity(0.07))
        .overlay { Rectangle().stroke(color.opacity(0.65), lineWidth: 1) }
    }
}

private struct AtlasPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.2, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(minHeight: 31)
            .background(configuration.isPressed ? AppPalette.registrationBlue.opacity(0.78) : AppPalette.instrument)
            .overlay(alignment: .leading) { Rectangle().fill(AppPalette.terminalGreen).frame(width: 4) }
    }
}

private struct AtlasOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.1, weight: .bold, design: .monospaced))
            .foregroundStyle(AppPalette.text)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(configuration.isPressed ? AppPalette.selection : AppPalette.panel)
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
    }
}

private struct SourceAtlasTopologyMark: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Color(red: 0.035, green: 0.105, blue: 0.08)))
            context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(AppPalette.terminalGreen.opacity(0.35)), lineWidth: 1)
            let points = [
                CGPoint(x: 9, y: 12), CGPoint(x: 9, y: size.height / 2), CGPoint(x: 9, y: size.height - 12)
            ]
            let hub = CGPoint(x: size.width * 0.56, y: size.height / 2)
            let output = CGPoint(x: size.width - 9, y: size.height / 2)
            for point in points {
                var route = Path()
                route.move(to: point)
                route.addLine(to: CGPoint(x: size.width * 0.34, y: point.y))
                route.addLine(to: hub)
                context.stroke(route, with: .color(AppPalette.terminalGreen), lineWidth: 1.4)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(point.y == points[1].y ? AppPalette.warning : AppPalette.ibmBlue))
            }
            var out = Path()
            out.move(to: hub)
            out.addLine(to: output)
            context.stroke(out, with: .color(AppPalette.terminalGreen), lineWidth: 1.8)
            context.fill(Path(ellipseIn: CGRect(x: output.x - 4, y: output.y - 4, width: 8, height: 8)), with: .color(.white))
        }
    }
}

private struct SourceAtlasBranchGlyph: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AppPalette.instrument))
            var path = Path()
            path.move(to: CGPoint(x: 7, y: size.height / 2))
            path.addLine(to: CGPoint(x: 17, y: size.height / 2))
            path.addLine(to: CGPoint(x: 17, y: 9))
            path.move(to: CGPoint(x: 17, y: size.height / 2))
            path.addLine(to: CGPoint(x: 17, y: size.height - 9))
            path.move(to: CGPoint(x: 17, y: 9))
            path.addLine(to: CGPoint(x: 30, y: 9))
            path.move(to: CGPoint(x: 17, y: size.height - 9))
            path.addLine(to: CGPoint(x: 30, y: size.height - 9))
            context.stroke(path, with: .color(AppPalette.terminalGreen), lineWidth: 1.5)
            context.fill(Path(ellipseIn: CGRect(x: 27, y: 6, width: 6, height: 6)), with: .color(AppPalette.ibmBlue))
            context.fill(Path(ellipseIn: CGRect(x: 27, y: size.height - 12, width: 6, height: 6)), with: .color(AppPalette.warning))
        }
    }
}

private struct SourceAtlasReviewMark: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AppPalette.instrument))
            var path = Path()
            path.move(to: CGPoint(x: 6, y: 10))
            path.addLine(to: CGPoint(x: 16, y: 10))
            path.addLine(to: CGPoint(x: 16, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 8, y: size.height / 2))
            path.move(to: CGPoint(x: 6, y: size.height - 10))
            path.addLine(to: CGPoint(x: 16, y: size.height - 10))
            path.addLine(to: CGPoint(x: 16, y: size.height / 2))
            context.stroke(path, with: .color(AppPalette.terminalGreen), lineWidth: 1.5)
            context.fill(Path(ellipseIn: CGRect(x: size.width - 12, y: size.height / 2 - 4, width: 8, height: 8)), with: .color(AppPalette.ibmBlue))
        }
    }
}

private extension View {
    func atlasEyebrow(color: Color) -> some View {
        font(.system(size: 6.8, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(color)
    }
}
