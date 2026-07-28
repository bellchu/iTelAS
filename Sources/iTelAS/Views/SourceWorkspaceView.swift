import AppKit
import SwiftUI
import iTelASCore

struct SourceWorkspaceView: View {
    @Environment(AppModel.self) private var model
    @State private var navigatorScope = SourceNavigatorScope.members
    @State private var sourceSearch = ""
    @State private var isIFSComparisonPresented = false
    @State private var isSourceMemberComparisonPresented = false
    @State private var sourceDetailMode = SourceDetailMode.intelligence
    @State private var intelligenceSection = SourceIntelligenceSection.outline
    @State private var selectedSourceSymbolID: String?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sourceNavigator
                    .frame(width: 292)

                Rectangle()
                    .fill(AppPalette.border)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    sourceHeader
                    HStack(spacing: 0) {
                        sourceEditor

                        Rectangle()
                            .fill(AppPalette.border)
                            .frame(width: 1)

                        changeLens
                            .frame(width: 360)
                    }
                }
            }

            sourceStatusStrip
        }
        .background(AppPalette.window)
        .sheet(isPresented: $model.isIFSWriteReviewPresented) {
            IFSWriteReviewView()
                .environment(model)
        }
        .sheet(isPresented: $model.isSourceMemberWriteReviewPresented) {
            SourceMemberWriteReviewView()
                .environment(model)
        }
        .sheet(isPresented: $isIFSComparisonPresented) {
            IFSRemoteComparisonView(
                localDraft: model.sourceDocument.text,
                openedBaseline: model.ifsRemoteBaselineText ?? model.sourceDocument.originalText,
                currentRemote: model.ifsLatestRemoteText ?? model.ifsRemoteBaselineText ?? model.sourceDocument.originalText
            )
        }
        .sheet(isPresented: $isSourceMemberComparisonPresented) {
            SourceMemberRemoteComparisonView(
                localDraft: model.sourceDocument.text,
                openedBaseline: model.sourceMemberSnapshot?.text ?? model.sourceDocument.originalText,
                currentRemote: model.sourceMemberCurrentRemoteSnapshot?.text
                    ?? model.sourceMemberSnapshot?.text
                    ?? model.sourceDocument.originalText
            )
        }
        .onChange(of: model.sourceIntelligence.fingerprint) { _, _ in
            if let selectedSourceSymbolID,
               !model.sourceIntelligence.symbols.contains(where: { $0.id == selectedSourceSymbolID }) {
                self.selectedSourceSymbolID = nil
            }
        }
    }

    private var sourceNavigator: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(navigatorScope == .members ? "MEMBER CATALOG" : "IFS NAVIGATOR")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.text)
                Spacer()
                Text(navigatorScope == .members ? "⇧⌘M" : "⇧⌘O")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 0) {
                ForEach(SourceNavigatorScope.allCases) { scope in
                    Button {
                        navigatorScope = scope
                    } label: {
                        Text(scope.rawValue)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(navigatorScope == scope ? Color.white : AppPalette.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(navigatorScope == scope ? AppPalette.instrument : AppPalette.panel)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(navigatorScope == scope ? .isSelected : [])
                }
            }
            .frame(height: 34)
            .padding(7)
            .background(AppPalette.raised)

            HStack(spacing: 8) {
                SourceReticleGlyph()
                    .stroke(AppPalette.muted, lineWidth: 1.2)
                    .frame(width: 15, height: 15)
                TextField(navigatorScope == .ifs ? "Filter current directory" : "Find member or path", text: $sourceSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if navigatorScope == .ifs {
                ifsNavigator
            } else {
                memberNavigator
            }
        }
        .background(AppPalette.panel)
    }

    private var memberNavigator: some View {
        let query = sourceSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraries = model.sourceMemberLibraries.filter {
            query.isEmpty || $0.value.localizedCaseInsensitiveContains(query)
        }
        let files = model.sourceMemberFiles.filter {
            query.isEmpty || $0.sourceFile.value.localizedCaseInsensitiveContains(query)
        }
        let members = model.sourceMembers.filter {
            query.isEmpty
                || $0.identity.member.value.localizedCaseInsensitiveContains(query)
                || $0.sourceType.localizedCaseInsensitiveContains(query)
                || $0.text.localizedCaseInsensitiveContains(query)
        }
        let capabilityColor = model.sourceMemberCapabilityConnected ? AppPalette.success : AppPalette.warning
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(capabilityColor).frame(width: 4, height: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.sourceMemberPhase == .localReplay ? "LOCAL REPLAY" : "MEMBER PROVIDER")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                    Text(model.sourceMemberCapabilityConnected
                         ? model.db2Receipt?.accessMode.label.uppercased() ?? "CAPABILITY READY"
                         : "NO HOST QUERY CAPABILITY")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(capabilityColor)
                }
                Spacer()
                Button("REPLAY") { model.restoreSourceMemberReplay(openMember: false) }
                    .buttonStyle(SourceMiniButtonStyle())
                Button(model.sourceMemberCapabilityConnected ? "REFRESH" : "CONNECT") {
                    if model.sourceMemberCapabilityConnected {
                        model.refreshSourceMemberCatalog()
                    } else {
                        model.presentDb2ConnectionDossier()
                    }
                }
                .buttonStyle(SourceMiniButtonStyle(accented: model.sourceMemberCapabilityConnected))
                .disabled(model.sourceMemberPhase.isBusy)
            }
            .padding(.horizontal, 11)
            .frame(height: 49)
            .background(AppPalette.raised.opacity(0.72))
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if let indexedPath = model.openedSourceWorkspaceSnapshotPath,
               sourceSearch.isEmpty || indexedPath.localizedCaseInsensitiveContains(sourceSearch) {
                HStack(spacing: 9) {
                    SourceFileGlyph(color: AppPalette.success)
                        .frame(width: 15, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.sourceDocument.identity.displayName)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppPalette.text)
                        Text("INDEX SNAPSHOT · READ ONLY")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(0.45)
                            .foregroundStyle(AppPalette.success)
                        Text(indexedPath)
                            .font(.system(size: 6.7, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
                .background(AppPalette.success.opacity(0.08))
                .overlay(alignment: .leading) {
                    Rectangle().fill(AppPalette.success).frame(width: 3)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.75)).frame(height: 1) }
            }

            if sourceMatchesSearch {
                Button { model.returnToLocalSourceScratch() } label: {
                    HStack(spacing: 9) {
                        SourceFileGlyph(color: AppPalette.registrationBlue)
                            .frame(width: 15, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CUSTOMER.rpgle")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppPalette.text)
                            Text(sourceDocumentIsLocal ? model.sourceSaveState.label : "LOCAL SCRATCH · AVAILABLE")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .tracking(0.45)
                                .foregroundStyle(AppPalette.ibmBlue)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(sourceDocumentIsLocal ? AppPalette.ibmBlue.opacity(0.09) : AppPalette.panel)
                    .overlay(alignment: .leading) {
                        if sourceDocumentIsLocal { Rectangle().fill(AppPalette.registrationBlue).frame(width: 3) }
                    }
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.75)).frame(height: 1) }
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    MemberCatalogStageHeader(number: "01", title: "LIBRARY", count: model.sourceMemberLibraries.count)
                    ForEach(libraries, id: \.self) { library in
                        Button { model.selectSourceMemberLibrary(library) } label: {
                            MemberLibraryRow(
                                library: library,
                                selected: model.selectedSourceMemberLibrary == library
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.sourceMemberPhase.isBusy)
                    }

                    MemberCatalogStageHeader(number: "02", title: "SOURCE FILE", count: model.sourceMemberFiles.count)
                    ForEach(files) { file in
                        Button { model.selectSourceMemberFile(file) } label: {
                            MemberSourceFileRow(
                                file: file,
                                selected: model.selectedSourceMemberFile?.id == file.id
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.sourceMemberPhase.isBusy)
                    }

                    MemberCatalogStageHeader(number: "03", title: "MEMBER", count: model.sourceMembers.count)
                    ForEach(members) { member in
                        Button { model.openSourceMember(member) } label: {
                            MemberCatalogRow(
                                member: member,
                                selected: sourceDocumentIsMember
                                    && model.openedSourceMemberIdentity == member.identity
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.sourceMemberPhase.isBusy)
                    }

                    if libraries.isEmpty && files.isEmpty && members.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NO CATALOG MATCH")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            Text("Clear the filter or refresh a caller-visible catalog. No broader query is issued automatically.")
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .overlay {
                if model.sourceMemberPhase.isBusy {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.sourceMemberPhase.label)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .padding(14)
                    .background(AppPalette.panel.opacity(0.94))
                    .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.sourceMemberPhase.label)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(model.sourceMemberPhase == .failed ? AppPalette.danger : capabilityColor)
                    Spacer()
                    Text(model.sourceMemberCapabilityConnected ? "LIVE" : "LOCAL")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Text(model.sourceMemberDiagnostic)
                    .font(.system(size: 8.2))
                    .foregroundStyle(AppPalette.secondary)
                    .lineLimit(3)
            }
            .padding(10)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
    }

    private var ifsNavigator: some View {
        @Bindable var model = model
        let filteredEntries = model.ifsEntries.filter {
            sourceSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(sourceSearch)
        }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(model.secureChannelPhase == .connected ? AppPalette.success : AppPalette.danger)
                    .frame(width: 5, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SYSTEM SFTP")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                    Text(model.ifsPhase.label)
                        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Button("CHANNEL") { model.presentSecureChannelDossier() }
                    .buttonStyle(SourceMiniButtonStyle())
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(AppPalette.raised.opacity(0.72))
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 7) {
                Button { model.openIFSParentDirectory() } label: {
                    Text("↑")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .background(AppPalette.raised)
                .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
                .disabled(model.ifsDirectory?.parent == nil || model.ifsPhase.isBusy)

                TextField("/home/PROFILE", text: $model.ifsPathText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .onSubmit { model.browseIFSPath() }

                Button("BROWSE") { model.browseIFSPath() }
                    .buttonStyle(SourceMiniButtonStyle(accented: true))
                    .disabled(model.ifsPhase.isBusy)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack {
                Text("NAME")
                Spacer()
                Text("SIZE")
            }
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 13)
            .frame(height: 27)
            .background(AppPalette.raised)

            if model.secureChannelPhase != .connected {
                VStack(alignment: .leading, spacing: 9) {
                    Text("PINNED CHANNEL REQUIRED")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                    Text("IFS browsing begins only after host-key review and a successful SSH + SFTP test. No saved credential is read automatically.")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("OPEN SECURE CHANNEL") { model.presentSecureChannelDossier() }
                        .buttonStyle(SourceBlackButtonStyle())
                }
                .padding(13)
                Spacer()
            } else if model.ifsPhase.isBusy {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.ifsPhase.label)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                    Text("No command shell is involved.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            Button {
                                if entry.kind == .directory {
                                    model.openIFSDirectory(entry)
                                } else {
                                    model.openIFSFile(entry)
                                }
                            } label: {
                                IFSDirectoryEntryRow(
                                    entry: entry,
                                    selected: model.ifsSelectedMetadata?.path == entry.metadata.path
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(entry.kind == .other)
                        }
                    }
                }
                .background(AppPalette.panel)
            }

            if let diagnostic = model.ifsDiagnostic {
                Text(diagnostic)
                    .font(.system(size: 8.5))
                    .foregroundStyle(model.ifsPhase == .failed || model.ifsPhase == .revisionConflict ? AppPalette.danger : AppPalette.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppPalette.raised.opacity(0.7))
                    .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            }
        }
    }

    private var sourceDocumentIsLocal: Bool {
        guard model.openedSourceWorkspaceSnapshotPath == nil else { return false }
        if case .localScratch = model.sourceDocument.identity { return true }
        return false
    }

    private var sourceDocumentIsWorkspaceSnapshot: Bool {
        model.openedSourceWorkspaceSnapshotPath != nil
    }

    private var sourceDocumentIsMember: Bool {
        if case .member = model.sourceDocument.identity { true } else { false }
    }

    private var sourceDocumentIsIFS: Bool {
        if case .ifs = model.sourceDocument.identity { true } else { false }
    }

    private var sourceMatchesSearch: Bool {
        sourceSearch.isEmpty
            || model.sourceDocument.identity.displayName.localizedCaseInsensitiveContains(sourceSearch)
    }

    private var sourceHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(sourceHeaderScopeLabel)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.secondary)
                Text("›")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                Text(model.sourceDocument.identity.displayName)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                Spacer()
                Button("SOURCE ATLAS") {
                    model.presentSourceWorkspaceIndex()
                }
                .buttonStyle(SourceOutlineButtonStyle())
                .help("Open the bounded local cross-reference index and reviewed dependency completion gate")
                sourceDetailModeControl
                Rectangle()
                    .fill(sourceSaveColor)
                    .frame(width: 6, height: 6)
                Text(sourceSaveLabel)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(sourceSaveColor)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(AppPalette.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 20) {
                SourceMetadata(label: "FORMAT", value: model.sourceIntelligence.dialect.label.uppercased())
                SourceMetadata(
                    label: "TARGET",
                    value: sourceDocumentIsWorkspaceSnapshot
                        ? "LOCAL INDEX"
                        : model.sourceDocument.identity.hostLocation ?? "UNASSIGNED"
                )
                SourceMetadata(label: "HOST CCSID", value: model.sourceDocument.ccsid.map(String.init) ?? "UNSET")
                SourceMetadata(
                    label: sourceDocumentIsMember
                        ? "SOURCE DATE"
                        : sourceDocumentIsWorkspaceSnapshot ? "INDEX RECEIPT" : sourceDocumentIsLocal ? "SOURCE DATE" : "REMOTE REV",
                    value: sourceDocumentIsMember ? model.sourceMemberDatePolicy.label.uppercased() : remoteRevisionLabel
                )
                SourceMetadata(
                    label: sourceDocumentIsMember ? "RECORDS" : "LINE ENDINGS",
                    value: sourceDocumentIsMember
                        ? String(model.sourceMemberSnapshot?.records.count ?? model.sourceDocument.lineCount)
                        : model.sourceDocument.lineEnding.rawValue
                )
                Spacer(minLength: 4)
                Button(sourceDocumentIsWorkspaceSnapshot ? "READ ONLY" : sourceDocumentIsLocal ? "COMPARE" : sourceDocumentIsMember ? "REFRESH & COMPARE" : "CHECK REVISION") {
                    if sourceDocumentIsWorkspaceSnapshot {
                        model.showNotice("This exact index snapshot is read only. Reopen the Atlas to refresh its source.")
                    } else if sourceDocumentIsLocal {
                        model.showNotice("Open an IFS file or source member before comparing remote content.")
                    } else if sourceDocumentIsMember {
                        model.compareSourceMemberRevision()
                    } else {
                        model.compareIFSRemoteRevision()
                    }
                }
                .buttonStyle(SourceOutlineButtonStyle())
                .disabled(sourceDocumentIsWorkspaceSnapshot || (sourceDocumentIsMember
                    ? model.sourceMemberPhase.isBusy
                    : !sourceDocumentIsLocal && (model.secureChannelPhase != .connected || model.ifsPhase.isBusy)))
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(AppPalette.raised.opacity(0.82))
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
    }

    private var remoteRevisionLabel: String {
        if sourceDocumentIsLocal { return model.sourceDocument.sourceDatePolicy.label.uppercased() }
        if sourceDocumentIsWorkspaceSnapshot {
            return String((model.sourceDocument.remoteRevision ?? "UNVERIFIED").prefix(8)).uppercased()
        }
        if sourceDocumentIsMember {
            return model.sourceMemberSnapshot?.revision.shortFingerprint ?? "UNVERIFIED"
        }
        guard let token = model.sourceDocument.remoteRevision,
              let revision = try? IFSRemoteRevision(token: token) else { return "UNVERIFIED" }
        return revision.shortFingerprint
    }

    private var sourceHeaderScopeLabel: String {
        if sourceDocumentIsLocal { return "LOCAL WORKSPACE" }
        if sourceDocumentIsWorkspaceSnapshot { return "INDEX SNAPSHOT" }
        if sourceDocumentIsMember {
            return model.sourceMemberPhase == .localReplay
                ? "LOCAL MEMBER REPLAY"
                : model.db2Receipt?.targetName.uppercased() ?? "MEMBER SNAPSHOT"
        }
        return "REMOTE IFS"
    }

    private var sourceEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: sourceDocumentIsMember ? 98 : 68)
                Text("······10······20······30······40······50······60······70······80······90·····100")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color(red: 0.47, green: 0.65, blue: 0.54))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    model.requestSourceCompletion()
                } label: {
                    HStack(spacing: 7) {
                        SourceCompletionForkMark(compact: true)
                            .frame(width: 18, height: 18)
                        Text("CONTENT ASSIST")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.55)
                        Text("CTRL SPACE")
                            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.terminalGreen.opacity(0.82))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(model.sourceCompletionSession == nil
                        ? Color.white.opacity(0.06)
                        : AppPalette.registrationBlue.opacity(0.82))
                    .overlay { Rectangle().stroke(Color.white.opacity(0.18), lineWidth: 0.7) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: .control)
                .help("Open bounded local source completions. No host lookup or AI request occurs.")
                .padding(.trailing, 6)
            }
            .frame(height: 28)
            .background(Color(red: 0.047, green: 0.114, blue: 0.082))

            PrecisionTextEditor(
                text: Binding(
                    get: { model.sourceDocument.text },
                    set: { model.updateSourceText($0) }
                ),
                accessibilityLabel: sourceDocumentIsLocal
                    ? "Local source scratch editor"
                    : sourceDocumentIsWorkspaceSnapshot
                    ? "Read-only indexed source snapshot"
                    : sourceDocumentIsMember
                    ? "Record-aware source member editor"
                    : "Remote IFS local draft editor",
                isEditable: !sourceDocumentIsWorkspaceSnapshot
                    && model.ifsPhase != .writing
                    && model.sourceMemberPhase != .writing,
                recordMetadata: sourceDocumentIsMember ? model.sourceMemberEditorRecords : nil,
                navigationRequest: model.sourceNavigationRequest,
                highlightSpans: model.sourceIntelligenceIsCurrent ? model.sourceIntelligence.highlights : [],
                highlightRevision: model.sourceIntelligenceIsCurrent
                    ? "\(model.sourceDocument.format.rawValue):\(model.sourceIntelligence.fingerprint)"
                    : "pending:\(model.sourceDocument.format.rawValue)",
                completionSession: model.sourceCompletionSession,
                completionSelectionIndex: model.sourceCompletionSelectionIndex,
                onCursorChange: { model.updateSourceCursor(line: $0, column: $1) },
                onSelectionChange: { model.updateSourceSelection($0) },
                onCompletionRequest: { model.requestSourceCompletion(caretUTF16: $0) },
                onCompletionMove: { model.moveSourceCompletionSelection(delta: $0) },
                onCompletionDismiss: { model.dismissSourceCompletion() },
                onCompletionAssist: { model.openSourceCompletionAssist(itemID: $0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack(spacing: 9) {
                SourceSafetyDiamond()
                    .stroke(Color(red: 0.54, green: 0.43, blue: 0), lineWidth: 1.1)
                    .frame(width: 14, height: 14)
                Text(editorSafetyMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 0.44, green: 0.35, blue: 0))
                Spacer()
                Text(editorMeasureLabel)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color(red: 0.44, green: 0.35, blue: 0))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color(red: 1, green: 0.976, blue: 0.83))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.warning.opacity(0.6)).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorSafetyMessage: String {
        if sourceDocumentIsLocal {
            return "Host upload stays blocked until target identity, CCSID, remote revision, and source-date policy pass preflight."
        }
        if sourceDocumentIsWorkspaceSnapshot {
            return model.openedSourceWorkspaceSnapshotIsCurrent
                ? "Read-only indexed snapshot. Reopen the Atlas to refresh evidence; no edit, autosave, or source-file write is available."
                : "This read-only snapshot is stale against the current index. Reopen the Atlas before relying on its location evidence."
        }
        if sourceDocumentIsMember {
            if model.sourceMemberPhase == .localReplay {
                return "This record-aware replay is local. Connect a separate reviewed-write capability before any host change."
            }
            if model.sourceMemberWriteCapabilityConnected {
                return "A write still requires six eligibility gates, an exact revision re-check, and a separate immutable review."
            }
            return "This connection can read member records but cannot write them. Reconnect explicitly for reviewed member writes."
        }
        return "This session-only draft is not persisted. A write requires an exact remote-revision check and a separate immutable review."
    }

    private var editorMeasureLabel: String {
        if sourceDocumentIsMember, let snapshot = model.sourceMemberSnapshot {
            return "\(model.sourceDocument.lineCount) RECORDS · \(snapshot.metadata.sourceTextByteLength) BYTE WIDTH"
        }
        return ByteCountFormatter.string(
            fromByteCount: Int64(model.sourceDocument.utf8ByteCount),
            countStyle: .file
        )
    }

    private var sourceSaveColor: Color {
        if sourceDocumentIsWorkspaceSnapshot {
            return model.openedSourceWorkspaceSnapshotIsCurrent ? AppPalette.registrationBlue : AppPalette.warning
        }
        switch model.sourceSaveState {
        case .clean, .saved, .remoteClean: return AppPalette.success
        case .saving, .remoteDraft: return AppPalette.warning
        case .failed: return AppPalette.danger
        }
    }

    private var sourceSaveLabel: String {
        sourceDocumentIsWorkspaceSnapshot
            ? (model.openedSourceWorkspaceSnapshotIsCurrent ? "READ ONLY" : "STALE SNAPSHOT")
            : model.sourceSaveState.label
    }

    private var sourceDetailModeControl: some View {
        HStack(spacing: 0) {
            Button {
                sourceDetailMode = .intelligence
            } label: {
                Text("INTEL")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(sourceDetailMode == .intelligence ? Color.white : AppPalette.secondary)
                    .frame(width: 53, height: 24)
                    .background(sourceDetailMode == .intelligence ? AppPalette.instrument : AppPalette.panel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show local source intelligence")
            .accessibilityAddTraits(sourceDetailMode == .intelligence ? .isSelected : [])

            Button {
                sourceDetailMode = .safety
            } label: {
                Text(sourceDocumentIsMember
                    ? "INTEGRITY"
                    : sourceDocumentIsIFS ? "WRITE" : sourceDocumentIsWorkspaceSnapshot ? "EVIDENCE" : "CHANGES")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(sourceDetailMode == .safety ? Color.white : AppPalette.secondary)
                    .frame(width: sourceDocumentIsMember ? 69 : 61, height: 24)
                    .background(sourceDetailMode == .safety ? AppPalette.instrument : AppPalette.panel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show source safety and change controls")
            .accessibilityAddTraits(sourceDetailMode == .safety ? .isSelected : [])
        }
        .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
    }

    @ViewBuilder
    private var changeLens: some View {
        if sourceDetailMode == .intelligence {
            sourceIntelligenceDesk
        } else if sourceDocumentIsWorkspaceSnapshot {
            workspaceSnapshotLens
        } else if sourceDocumentIsLocal {
            localChangeLens
        } else if sourceDocumentIsMember {
            sourceMemberIntegrityDesk
        } else {
            ifsWriteFlightRecorder
        }
    }

    private var workspaceSnapshotLens: some View {
        VStack(alignment: .leading, spacing: 0) {
            lensSection(label: "INDEX CUSTODY") {
                Text(model.openedSourceWorkspaceSnapshotPath ?? "No indexed path")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Text("Content receipt \(String((model.sourceDocument.remoteRevision ?? "UNVERIFIED").prefix(12)).uppercased())")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(AppPalette.secondary)
            }
            lensSection(label: "BOUNDARY") {
                Text("This buffer is an immutable view of the selected local index snapshot. It is not autosaved, written back, uploaded, compiled, or sent to Assist.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Return to Local Scratch") { model.returnToLocalSourceScratch() }
                    .buttonStyle(SourceOutlineButtonStyle())
            }
            Spacer()
        }
        .background(AppPalette.panel)
    }

    private var selectedSourceSymbol: SourceSymbol? {
        if let selectedSourceSymbolID,
           let selected = model.sourceIntelligence.symbols.first(where: { $0.id == selectedSourceSymbolID }) {
            return selected
        }
        return model.sourceIntelligence.symbols.first
    }

    private var sourceIntelligenceDesk: some View {
        let snapshot = model.sourceIntelligence
        let analysisState = snapshot.wasLimited
            ? "LIMITED"
            : snapshot.highlightingWasLimited ? "COLOR CAP" : "CURRENT"
        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                SourceIntelligenceCircuitMark()
                    .frame(width: 23, height: 23)
                Text("SOURCE INTELLIGENCE")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.72)
                Spacer()
                Text("LOCAL")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(Color(red: 0.09, green: 0.20, blue: 0.33))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(AppPalette.ibmBlue.opacity(0.08))
                    .overlay { Rectangle().stroke(AppPalette.ibmBlue.opacity(0.34), lineWidth: 1) }
            }
            .padding(.horizontal, 13)
            .frame(height: 50)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            HStack(spacing: 4) {
                intelligenceTab(.outline, count: snapshot.symbols.count)
                intelligenceTab(.references, count: snapshot.references.count)
                intelligenceTab(.checks, count: snapshot.checks.count)
            }
            .padding(5)
            .frame(height: 36)
            .background(AppPalette.raised)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(snapshot.dialect.label.uppercased())
                        .foregroundStyle(Color(red: 0.09, green: 0.20, blue: 0.33))
                    Spacer()
                    Text(analysisState)
                        .foregroundStyle(snapshot.wasLimited || snapshot.highlightingWasLimited ? AppPalette.warning : AppPalette.success)
                }
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                Text("\(snapshot.analyzedLineCount) LINES · \(snapshot.highlights.count) COLOR SPANS · SHA-256 \(snapshot.shortFingerprint)…")
                    .font(.system(size: 7.1, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(AppPalette.raised.opacity(0.65))
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    sourceIntelligenceContent
                }
            }
            .background(AppPalette.panel)

            VStack(alignment: .leading, spacing: 4) {
                Text("NOT A COMPILER RESULT")
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(AppPalette.muted)
                Text(snapshot.limitations.first ?? snapshot.boundaryLabel)
                    .font(.system(size: 7.8))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.raised.opacity(0.55))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            VStack(spacing: 7) {
                Button(selectedSourceSymbol == nil ? "PREPARE ASSIST REVIEW" : "ASK ASSIST ABOUT SYMBOL") {
                    model.prepareSourceAssistReview(symbol: selectedSourceSymbol)
                }
                .buttonStyle(SourceOutlineButtonStyle())
                .help("Prepare an explicit context dossier; no source is sent until you review and approve it")

                Button("OPEN COMPILE EVIDENCE  →") {
                    model.selectedTool = .buildAndTest
                }
                .buttonStyle(SourceBlackButtonStyle())
            }
            .padding(12)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    @ViewBuilder
    private var sourceIntelligenceContent: some View {
        switch intelligenceSection {
        case .outline:
            intelligenceSectionHeader("STRUCTURE", count: model.sourceIntelligence.symbols.count)
            if model.sourceIntelligence.symbols.isEmpty {
                intelligenceEmptyState("No supported declarations were found in the current bounded snapshot.")
            } else {
                ForEach(model.sourceIntelligence.symbols) { symbol in
                    Button {
                        selectedSourceSymbolID = symbol.id
                        model.navigateToSource(symbol.range)
                    } label: {
                        SourceIntelligenceSymbolRow(
                            symbol: symbol,
                            isSelected: selectedSourceSymbol?.id == symbol.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(symbol.kind.label) \(symbol.name), line \(symbol.range.startLine)")
                }
            }
        case .references:
            intelligenceSectionHeader("REFERENCES", count: model.sourceIntelligence.references.count)
            if model.sourceIntelligence.references.isEmpty {
                intelligenceEmptyState("No supported calls, COPY or INCLUDE directives, or external DDS references were found.")
            } else {
                ForEach(model.sourceIntelligence.references) { reference in
                    Button {
                        model.navigateToSource(reference.range)
                    } label: {
                        SourceIntelligenceReferenceRow(reference: reference)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(reference.kind.label) \(reference.target.displayName), line \(reference.range.startLine)")
                }
            }
        case .checks:
            intelligenceSectionHeader("LOCAL CHECKS", count: model.sourceIntelligence.checks.count)
            if model.sourceIntelligence.checks.isEmpty {
                HStack(spacing: 9) {
                    Rectangle().fill(AppPalette.success).frame(width: 4, height: 20)
                    Text("No local structural advisories in this snapshot.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
            } else {
                ForEach(model.sourceIntelligence.checks) { check in
                    Button {
                        model.navigateToSource(check.range)
                    } label: {
                        SourceIntelligenceCheckRow(check: check)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(check.severity.label), line \(check.range.startLine): \(check.message)")
                }
            }
        }
    }

    private func intelligenceTab(_ section: SourceIntelligenceSection, count: Int) -> some View {
        Button {
            intelligenceSection = section
        } label: {
            Text("\(section.rawValue) · \(count)")
                .font(.system(size: 7.1, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(intelligenceSection == section ? Color.white : AppPalette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(intelligenceSection == section ? AppPalette.instrument : AppPalette.panel)
                .overlay {
                    if intelligenceSection != section {
                        Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(intelligenceSection == section ? .isSelected : [])
    }

    private func intelligenceSectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)")
        }
        .font(.system(size: 7.3, weight: .bold, design: .monospaced))
        .tracking(0.5)
        .foregroundStyle(AppPalette.muted)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(AppPalette.raised.opacity(0.62))
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private func intelligenceEmptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 8.5))
            .foregroundStyle(AppPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
    }

    private var sourceMemberIntegrityDesk: some View {
        let delta = model.sourceDocument.delta
        let eligibility = model.sourceMemberWriteEligibility
        let readyGateCount = eligibility?.checks.filter { $0.state == .ready }.count ?? 0
        let exactIdentity = model.openedSourceMemberIdentity?.description ?? "No exact member identity"
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                SourceMemberIntegrityGlyph()
                    .frame(width: 21, height: 21)
                Text("RECORD INTEGRITY")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.75)
                Spacer()
                Text(model.sourceMemberPhase == .localReplay
                     ? "LOCAL REPLAY"
                     : model.db2Receipt?.accessMode.label.uppercased() ?? "OFFLINE")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(model.sourceMemberWriteCapabilityConnected ? AppPalette.warning : AppPalette.success)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background((model.sourceMemberWriteCapabilityConnected ? AppPalette.warning : AppPalette.success).opacity(0.08))
                    .overlay {
                        Rectangle().stroke(
                            (model.sourceMemberWriteCapabilityConnected ? AppPalette.warning : AppPalette.success).opacity(0.45),
                            lineWidth: 1
                        )
                    }
            }
            .padding(.horizontal, 13)
            .frame(height: 50)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            lensSection(label: "EXACT MEMBER IDENTITY") {
                HStack {
                    Text(exactIdentity)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                        .textSelection(.enabled)
                    Spacer(minLength: 6)
                    Text(model.sourceMemberSnapshot == nil ? "UNVERIFIED" : "PINNED")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(model.sourceMemberSnapshot == nil ? AppPalette.warning : AppPalette.success)
                }
                Text("Library, source file, and member stay bound through compare, review, transaction, and verification.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            lensSection(label: "REVISION LEDGER") {
                HStack(spacing: 9) {
                    SourceMemberRevisionBlock(
                        label: "OPENED",
                        value: model.sourceMemberSnapshot?.revision.shortFingerprint ?? "—",
                        color: AppPalette.text
                    )
                    SourceMemberRevisionFlowGlyph(
                        color: model.sourceMemberRevisionState == .conflict ? AppPalette.danger : AppPalette.success
                    )
                    .frame(width: 36, height: 18)
                    SourceMemberRevisionBlock(
                        label: "CURRENT",
                        value: model.sourceMemberCurrentRemoteSnapshot?.revision.shortFingerprint ?? "NOT CHECKED",
                        color: model.sourceMemberRevisionState == .conflict ? AppPalette.danger : AppPalette.success
                    )
                    Spacer(minLength: 0)
                }
                Text(model.sourceMemberRevisionState.label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(model.sourceMemberRevisionState == .conflict ? AppPalette.danger : AppPalette.muted)
            }

            lensSection(label: "WRITE ELIGIBILITY · 6 GATES") {
                HStack {
                    Text("\(readyGateCount) / \(eligibility?.checks.count ?? 6) READY")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(readyGateCount == 6 ? AppPalette.success : AppPalette.warning)
                    Spacer()
                    Text(model.sourceMemberWriteCapabilityConnected ? "WRITE CAPABILITY" : "READ / LOCAL")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                if let eligibility {
                    ForEach(eligibility.checks) { gate in
                        SourceMemberWriteGateRow(gate: gate)
                    }
                } else {
                    Text("Open a typed source-member snapshot to evaluate layout, authority, CCSID, journal images, triggers, and sequence order.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            lensSection(label: "LOCAL DELTA") {
                HStack(spacing: 20) {
                    SourceDeltaMetric(value: "+\(delta.added)", label: "RECORDS", color: AppPalette.success)
                    SourceDeltaMetric(value: "~\(delta.modified)", label: "CHANGED", color: AppPalette.ibmBlue)
                    SourceDeltaMetric(value: "−\(delta.removed)", label: "DELETED", color: AppPalette.muted)
                }
                Menu {
                    Button("Preserve existing; clear inserted") {
                        model.setSourceMemberDatePolicy(.preserve)
                    }
                    Button("Clear changed records") {
                        model.setSourceMemberDatePolicy(.clearChanged)
                    }
                } label: {
                    HStack {
                        Text("SOURCE DATE POLICY")
                        Spacer()
                        Text(model.sourceMemberDatePolicy.label.uppercased())
                    }
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .padding(.horizontal, 8)
                    .frame(height: 27)
                    .background(AppPalette.raised)
                    .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
                }
                .menuStyle(.borderlessButton)
                .disabled(model.sourceMemberPhase == .writing)
            }

            if model.sourceMemberRevisionState == .conflict {
                VStack(alignment: .leading, spacing: 7) {
                    Text("REMOTE REVISION CHANGED")
                        .font(.system(size: 7.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.danger)
                    Text("Review the opened baseline, local draft, and current remote records before deciding what to keep.")
                        .font(.system(size: 8.3))
                        .foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("OPEN THREE-WAY COMPARISON") { isSourceMemberComparisonPresented = true }
                        .buttonStyle(SourceOutlineButtonStyle())
                }
                .padding(11)
                .background(AppPalette.danger.opacity(0.055))
                .overlay(alignment: .top) { Rectangle().fill(AppPalette.danger.opacity(0.45)).frame(height: 1) }
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Button("REVIEW DELTA WITH ASSIST") { model.prepareSourceAssistReview() }
                    .buttonStyle(SourceOutlineButtonStyle())

                if model.sourceMemberWriteCapabilityConnected {
                    Button(model.sourceMemberPhase == .preparingWrite ? "CHECKING CURRENT REVISION…" : "REVIEW TRANSACTIONAL WRITE") {
                        model.requestSourceMemberWriteReview()
                    }
                    .buttonStyle(SourceBlackButtonStyle(enabled: model.sourceDocument.isDirty && readyGateCount == 6))
                    .disabled(!model.sourceDocument.isDirty || readyGateCount != 6 || model.sourceMemberPhase.isBusy)
                } else {
                    Button("OPEN REVIEWED-WRITE DOSSIER") { model.presentDb2ConnectionDossier() }
                        .buttonStyle(SourceBlackButtonStyle())
                        .help("A separate Db2 capability is required; opening the dossier does not contact the host")
                }

                if model.sourceDocument.isDirty {
                    Button("DISCARD LOCAL MEMBER EDITS") { model.discardSourceMemberDraft() }
                        .buttonStyle(SourceOutlineButtonStyle())
                        .disabled(model.sourceMemberPhase.isBusy)
                }
            }
            .padding(12)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var localChangeLens: some View {
        let delta = model.sourceDocument.delta
        let preflight = model.sourceWritePreflight
        let memberContract = [
            ("Exact identity", "Library / source file / member"),
            ("Record semantics", "Sequence + date + source text"),
            ("Loss prevention", "CCSID and byte width before write"),
            ("Commit boundary", "Journal before + after images")
        ]
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                ChangeLensGlyph()
                    .stroke(AppPalette.registrationBlue, lineWidth: 1.3)
                    .frame(width: 18, height: 18)
                Text("CHANGE LENS")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                Spacer()
                Text(delta.totalChanges == 0 ? "CLEAN" : "\(delta.totalChanges) EDITS")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(delta.totalChanges == 0 ? AppPalette.success : AppPalette.ibmBlue)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            lensSection(label: "HOST IDENTITY") {
                Text(model.sourceDocument.identity.hostLocation ?? "No member or IFS path selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.text)
                Text("The complete host identity stays visible through edit, compare, write, and compile.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            lensSection(label: "SOURCE MEMBER CONTRACT") {
                ForEach(Array(memberContract.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 7) {
                        SourceMemberRecordGlyph(primary: AppPalette.success, secondary: AppPalette.ibmBlue)
                            .frame(width: 14, height: 14)
                        Text(item.0)
                            .font(.system(size: 9, weight: .semibold))
                        Spacer(minLength: 4)
                        Text(item.1)
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(1)
                    }
                }
            }

            lensSection(label: "WRITE PREFLIGHT") {
                ForEach(preflight.checks) { check in
                    SourcePreflightRow(check: check)
                }
            }

            lensSection(label: "DRAFT DELTA") {
                HStack(spacing: 0) {
                    Rectangle().fill(AppPalette.borderStrong).frame(maxWidth: .infinity)
                    Rectangle().fill(AppPalette.success).frame(width: max(8, CGFloat(delta.added) * 12))
                    Rectangle().fill(AppPalette.ibmBlue).frame(width: max(8, CGFloat(delta.modified) * 12))
                    Rectangle().fill(AppPalette.danger).frame(width: max(4, CGFloat(delta.removed) * 12))
                }
                .frame(height: 7)

                HStack(spacing: 24) {
                    SourceDeltaMetric(value: "+\(delta.added)", label: "ADDED", color: AppPalette.success)
                    SourceDeltaMetric(value: "~\(delta.modified)", label: "CHANGED", color: AppPalette.ibmBlue)
                    SourceDeltaMetric(value: "−\(delta.removed)", label: "REMOVED", color: AppPalette.muted)
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Button("PREPARE ASSIST REVIEW") {
                    model.prepareSourceAssistReview()
                }
                .buttonStyle(SourceOutlineButtonStyle())
                .help("Open the Assist dossier to choose, preview, and explicitly send source context")

                Button(preflight.isReady ? "REVIEW WRITE PLAN" : "UPLOAD BLOCKED · CONNECT PROVIDER") {
                    model.showNotice(preflight.isReady
                        ? "Review the typed write plan before committing host changes."
                        : "The write preflight is not ready; no host operation was attempted.")
                }
                .buttonStyle(SourceBlackButtonStyle(enabled: preflight.isReady))
            }
            .padding(13)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private var ifsWriteFlightRecorder: some View {
        let delta = model.sourceDocument.delta
        let preflight = model.sourceWritePreflight
        let readyGateCount = preflight.checks.filter { $0.state == .ready }.count
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IFSFlightRecorderGlyph()
                        .stroke(AppPalette.terminalGreen, lineWidth: 1.25)
                        .frame(width: 19, height: 19)
                    Text("WRITE FLIGHT RECORDER")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text("\(readyGateCount) / \(preflight.checks.count)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(readyGateCount == preflight.checks.count ? AppPalette.terminalGreen : AppPalette.warning)
                        .padding(.horizontal, 7)
                        .frame(height: 21)
                        .background(AppPalette.terminalRaised)
                        .overlay { Rectangle().stroke(Color.white.opacity(0.14), lineWidth: 1) }
                }
                Text("No remote write begins until the exact target, expected bytes, and staged sibling are reviewed together.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 0.72, green: 0.79, blue: 0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(AppPalette.instrument)

            lensSection(label: "IMMUTABLE TARGET") {
                Text(model.secureChannelProfile.targetLabel)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                Text(model.sourceDocument.identity.hostLocation ?? "No IFS target")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .textSelection(.enabled)
                if let metadata = model.ifsSelectedMetadata {
                    Text("\(metadata.permissions)  \(metadata.owner):\(metadata.group)  ·  \(ByteCountFormatter.string(fromByteCount: metadata.byteCount, countStyle: .file))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            lensSection(label: "WRITE GATES") {
                ForEach(preflight.checks) { check in
                    SourcePreflightRow(check: check)
                }
            }

            if model.ifsRevisionState == .conflict {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Rectangle().fill(AppPalette.danger).frame(width: 4, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("REMOTE REVISION CHANGED")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundStyle(AppPalette.danger)
                            Text("The write path is blocked. The current remote bytes are available for comparison.")
                                .font(.system(size: 8.5))
                                .foregroundStyle(AppPalette.secondary)
                        }
                    }
                    Button("OPEN LOCAL ↔ REMOTE COMPARISON") {
                        isIFSComparisonPresented = true
                    }
                    .buttonStyle(SourceOutlineButtonStyle())
                }
                .padding(12)
                .background(AppPalette.danger.opacity(0.055))
                .overlay(alignment: .top) { Rectangle().fill(AppPalette.danger.opacity(0.45)).frame(height: 1) }
            } else if let plan = model.ifsWritePlan {
                lensSection(label: "STAGED REPLACEMENT") {
                    FlightPlanRow(number: "1", text: "Upload \(plan.byteCount) reviewed bytes")
                    FlightPlanRow(number: "2", text: "Re-check \(plan.expectedRevision.shortFingerprint)")
                    FlightPlanRow(number: "3", text: "Request same-directory rename")
                    Text(plan.stagedSibling.value)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            } else if let receipt = model.ifsWriteReceipt {
                lensSection(label: "LAST VERIFIED RECEIPT") {
                    Text(receipt.committedRevision.shortFingerprint)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.success)
                    Text("Committed bytes were re-downloaded and matched the reviewed payload.")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    SourceDeltaMetric(value: "+\(delta.added)", label: "ADDED", color: AppPalette.success)
                    SourceDeltaMetric(value: "~\(delta.modified)", label: "CHANGED", color: AppPalette.ibmBlue)
                    SourceDeltaMetric(value: "−\(delta.removed)", label: "REMOVED", color: AppPalette.muted)
                }
                .frame(maxWidth: .infinity)

                Button(model.ifsPhase == .preparingWrite ? "CHECKING REMOTE REVISION…" : "REVIEW STAGED WRITE") {
                    model.requestIFSWriteReview()
                }
                .buttonStyle(SourceBlackButtonStyle(enabled: preflight.isReady && model.sourceDocument.isDirty))
                .disabled(!preflight.isReady || !model.sourceDocument.isDirty || model.ifsPhase.isBusy)

                HStack(spacing: 8) {
                    Button("CHECK REVISION") { model.compareIFSRemoteRevision() }
                        .buttonStyle(SourceOutlineButtonStyle())
                        .disabled(model.ifsPhase.isBusy)
                    Button("DISCARD DRAFT") { model.discardRemoteSourceDraft() }
                        .buttonStyle(SourceOutlineButtonStyle())
                        .disabled(!model.sourceDocument.isDirty || model.ifsPhase.isBusy)
                }
            }
            .padding(13)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .background(AppPalette.panel)
    }

    private func lensSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(AppPalette.muted)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var sourceStatusStrip: some View {
        return HStack(spacing: 18) {
            Text(sourceStatusPrimary)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.terminalGreen)
            Text(sourceStatusEncoding)
            Text(sourceStatusEvidence)
            Spacer()
            Text("\(model.proverb.text) — \(model.proverb.source)")
                .italic()
                .lineLimit(1)
            Text(sourceDocumentIsMember
                 ? "Record \(model.sourceCursorLine)  Col \(model.sourceCursorColumn)"
                 : "Ln \(model.sourceCursorLine)  Col \(model.sourceCursorColumn)")
                .foregroundStyle(Color.white)
        }
        .font(.system(size: 8.5, design: .monospaced))
        .foregroundStyle(Color(red: 0.67, green: 0.74, blue: 0.70))
        .padding(.horizontal, 13)
        .frame(height: 29)
        .background(AppPalette.terminal)
    }

    private var sourceStatusPrimary: String {
        if sourceDocumentIsWorkspaceSnapshot {
            return model.openedSourceWorkspaceSnapshotIsCurrent
                ? "INDEX SNAPSHOT · READ ONLY"
                : "INDEX SNAPSHOT · STALE"
        }
        if sourceDocumentIsMember {
            return model.sourceMemberPhase == .localReplay
                ? "MEMBER REPLAY · RECORD-AWARE"
                : "DB2 MEMBER · \(model.sourceMemberPhase.label)"
        }
        if sourceDocumentIsLocal {
            return navigatorScope == .members
                ? "MEMBER CATALOG · \(model.sourceMemberPhase.label)"
                : "LOCAL SCRATCH"
        }
        return model.secureChannelPhase == .connected ? "SYSTEM SFTP · PINNED" : "REMOTE DRAFT · OFFLINE"
    }

    private var sourceStatusEncoding: String {
        if sourceDocumentIsWorkspaceSnapshot { return "UTF-8 · MEMORY ONLY" }
        if sourceDocumentIsMember {
            return "CCSID \(model.sourceMemberSnapshot?.metadata.ccsid ?? 0) · WIDTH \(model.sourceMemberSnapshot?.metadata.sourceTextByteLength ?? 0)"
        }
        return sourceDocumentIsLocal
            ? "UTF-8 → CCSID: UNSET"
            : "UTF-8 ↔ CCSID 1208 · \(model.sourceDocument.lineEnding.rawValue)"
    }

    private var sourceStatusEvidence: String {
        if sourceDocumentIsWorkspaceSnapshot { return "CONTENT RECEIPT: \(remoteRevisionLabel)" }
        if sourceDocumentIsMember { return "SOURCE DATES: \(model.sourceMemberDatePolicy.label.uppercased())" }
        if sourceDocumentIsLocal {
            return navigatorScope == .members
                ? (model.sourceMemberCapabilityConnected ? "DB2 MEMBER CAPABILITY: READY" : "DB2 MEMBER CAPABILITY: OFFLINE")
                : "SOURCE DATES: PRESERVE"
        }
        return model.ifsRevisionState.label
    }
}

private enum SourceDetailMode {
    case intelligence
    case safety
}

private enum SourceIntelligenceSection: String, CaseIterable, Identifiable {
    case outline = "OUTLINE"
    case references = "REFERENCES"
    case checks = "CHECKS"

    var id: String { rawValue }
}

private struct SourceIntelligenceCircuitMark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(red: 0.47, green: 0.66, blue: 1)).frame(width: 2, height: 15).offset(x: 5, y: 4)
            Rectangle().fill(Color(red: 0.47, green: 0.66, blue: 1)).frame(width: 10, height: 2).offset(x: 7, y: 6)
            Rectangle().fill(AppPalette.terminalGreen).frame(width: 7, height: 2).offset(x: 7, y: 15)
            Rectangle().fill(Color.white).frame(width: 4, height: 6).offset(x: 16, y: 4)
            Rectangle().fill(Color.white).frame(width: 5, height: 6).offset(x: 13, y: 13)
        }
        .frame(width: 23, height: 23)
        .background(Color(red: 0.06, green: 0.16, blue: 0.27))
        .accessibilityHidden(true)
    }
}

private struct SourceIntelligenceSymbolRow: View {
    let symbol: SourceSymbol
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(symbol.kind.shortLabel)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? Color(red: 0.69, green: 0.80, blue: 1) : AppPalette.secondary)
                .frame(width: 27, height: 22)
                .background(isSelected ? Color(red: 0.09, green: 0.20, blue: 0.33) : AppPalette.raised)

            VStack(alignment: .leading, spacing: 2) {
                Text(symbol.name)
                    .font(.system(size: 9.1, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color(red: 0.09, green: 0.20, blue: 0.33) : AppPalette.text)
                    .lineLimit(1)
                Text(symbol.containerName.map { "\(symbol.detail) · \($0)" } ?? symbol.detail)
                    .font(.system(size: 6.8, design: .monospaced))
                    .foregroundStyle(isSelected ? AppPalette.ibmBlue : AppPalette.muted)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(symbol.range.startLine)")
                .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? AppPalette.ibmBlue : AppPalette.muted)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 42)
        .background(isSelected ? AppPalette.ibmBlue.opacity(0.08) : AppPalette.panel)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(AppPalette.ibmBlue).frame(width: 3) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.72)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

private struct SourceIntelligenceReferenceRow: View {
    let reference: SourceReference

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                Rectangle().fill(reference.resolution == .currentDocument ? AppPalette.success : AppPalette.warning)
                    .frame(width: 5, height: 5)
                Rectangle().fill(reference.resolution == .currentDocument ? AppPalette.success : AppPalette.warning)
                    .frame(width: 7, height: 1)
                Rectangle()
                    .stroke(reference.resolution == .currentDocument ? AppPalette.success : AppPalette.warning, lineWidth: 1)
                    .frame(width: 5, height: 7)
            }
            .frame(width: 18)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(reference.target.displayName)
                    .font(.system(size: 8.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
                Text("\(reference.kind.label) · \(reference.resolution.label)")
                    .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                    .foregroundStyle(reference.resolution == .currentDocument ? AppPalette.success : AppPalette.warning)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(reference.range.startLine)")
                .font(.system(size: 7.1, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 45)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.72)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

private struct SourceIntelligenceCheckRow: View {
    let check: SourceLocalCheck

    private var color: Color {
        switch check.severity {
        case .information: AppPalette.ibmBlue
        case .advisory: Color(red: 0.70, green: 0.53, blue: 0)
        case .warning: AppPalette.danger
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            SourceSafetyDiamond()
                .stroke(color, lineWidth: 1.05)
                .frame(width: 13, height: 13)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("LOCAL CHECK · \(check.severity.label)")
                    Spacer()
                    Text("LINE \(check.range.startLine)")
                }
                .font(.system(size: 6.9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                Text(check.message)
                    .font(.system(size: 8.1))
                    .foregroundStyle(AppPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.055))
        .overlay(alignment: .bottom) { Rectangle().fill(color.opacity(0.34)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

struct WorkbenchInstrumentRailView: View {
    @Environment(AppModel.self) private var model

    private let tools: [WorkbenchTool] = [
        .sourceWorkspace,
        .terminal,
        .sqlStudio,
        .objectGraph,
        .buildAndTest,
        .jobsAndQueues,
        .spoolAndOutput,
        .transferCenter,
        .systemHealth,
        .automation,
        .securityAdvisor,
        .casebook
    ]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(tools) { tool in
                Button {
                    model.selectedTool = tool
                } label: {
                    WorkbenchGlyph(
                        tool: tool,
                        color: model.selectedTool == tool ? Color(red: 0.47, green: 0.66, blue: 1) : Color(red: 0.57, green: 0.64, blue: 0.68),
                        size: 21
                    )
                    .frame(width: 42, height: 42)
                    .background(model.selectedTool == tool ? Color(red: 0.09, green: 0.17, blue: 0.27) : Color.clear)
                    .overlay(alignment: .leading) {
                        if model.selectedTool == tool {
                            Rectangle().fill(AppPalette.registrationBlue).frame(width: 3)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tool.title)
            }

            Spacer()

            Button {
                model.isAssistantVisible.toggle()
            } label: {
                UtilityGlyph(kind: .assistant, color: AppPalette.terminalGreen, size: 18)
                    .frame(width: 42, height: 42)
                    .background(Color(red: 0.06, green: 0.13, blue: 0.10))
                    .overlay {
                        Rectangle().stroke(Color(red: 0.19, green: 0.36, blue: 0.26), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(model.isAssistantVisible ? "Hide iTelAS Assist" : "Show iTelAS Assist")
        }
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity)
        .background(AppPalette.instrument)
    }
}

private enum SourceNavigatorScope: String, CaseIterable, Identifiable {
    case members = "MEMBERS"
    case ifs = "IFS"
    var id: Self { self }
}

private struct SourceMetadata: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
        }
    }
}

private struct MemberContractRow: View {
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            SourceMemberRecordGlyph(primary: AppPalette.success, secondary: AppPalette.registrationBlue)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
            Spacer(minLength: 4)
            Text(detail)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
        }
    }
}

private struct MemberCatalogStageHeader: View {
    let number: String
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(number)
                .foregroundStyle(AppPalette.ibmBlue)
            Text(title)
            Spacer()
            Text(String(count))
                .foregroundStyle(AppPalette.muted)
        }
        .font(.system(size: 7, weight: .bold, design: .monospaced))
        .tracking(0.65)
        .padding(.horizontal, 11)
        .frame(height: 27)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.65)).frame(height: 1) }
    }
}

private struct MemberLibraryRow: View {
    let library: IBMSystemObjectName
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Rectangle().fill(selected ? AppPalette.instrument : AppPalette.raised)
                Text("L")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? AppPalette.terminalGreen : AppPalette.secondary)
            }
            .frame(width: 20, height: 20)
            Text(library.value)
                .font(.system(size: 9, weight: selected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(AppPalette.text)
            Spacer()
            Text(selected ? "CURRENT" : "LIB")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? AppPalette.success : AppPalette.muted)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(selected ? AppPalette.success.opacity(0.065) : AppPalette.panel)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(AppPalette.success).frame(width: 3) }
        }
        .contentShape(Rectangle())
    }
}

private struct MemberSourceFileRow: View {
    let file: SourceMemberFileSummary
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            SourceFileGlyph(color: selected ? AppPalette.registrationBlue : AppPalette.muted)
                .frame(width: 14, height: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.sourceFile.value)
                    .font(.system(size: 8.7, weight: selected ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                Text("CCSID \(file.ccsid.map(String.init) ?? "—") · \(file.recordLength) BYTE RECORD")
                    .font(.system(size: 6.4, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
            Text(String(file.memberCount))
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(selected ? AppPalette.ibmBlue.opacity(0.065) : AppPalette.panel)
        .contentShape(Rectangle())
    }
}

private struct MemberCatalogRow: View {
    let member: SourceMemberSummary
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Rectangle().fill(selected ? AppPalette.instrument : AppPalette.raised)
                Text(String(member.sourceType.prefix(2)))
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? Color(red: 0.69, green: 0.8, blue: 1) : AppPalette.secondary)
            }
            .frame(width: 27, height: 23)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.identity.member.value)
                    .font(.system(size: 9, weight: selected ? .bold : .semibold, design: .monospaced))
                    .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.text)
                Text("\(member.sourceType) · \(member.recordCount) RECORDS")
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.muted)
            }
            Spacer()
            if member.lastSourceUpdate != nil {
                Text("DATED")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 42)
        .background(selected ? AppPalette.ibmBlue.opacity(0.09) : AppPalette.panel)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(AppPalette.registrationBlue).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .help(member.text.isEmpty ? member.identity.description : member.text)
    }
}

private struct SourceMemberWriteGateRow: View {
    let gate: SourceMemberWriteGate

    private var color: Color {
        gate.state == .ready ? AppPalette.success : AppPalette.danger
    }

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: 4, height: 14)
            Text(gate.kind.label)
                .font(.system(size: 8.5))
                .foregroundStyle(AppPalette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(gate.state == .ready ? "PASS" : "BLOCKED")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(color)
        }
        .help(gate.detail)
    }
}

private struct SourceMemberRevisionBlock: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 6.3, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

private struct SourceMemberRevisionFlowGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var line = Path()
            line.move(to: CGPoint(x: 1, y: size.height / 2))
            line.addLine(to: CGPoint(x: size.width - 7, y: size.height / 2))
            context.stroke(line, with: .color(color), lineWidth: 1)
            var arrow = Path()
            arrow.move(to: CGPoint(x: size.width - 9, y: size.height / 2 - 4))
            arrow.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
            arrow.addLine(to: CGPoint(x: size.width - 9, y: size.height / 2 + 4))
            context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 1, lineJoin: .miter))
        }
        .accessibilityHidden(true)
    }
}

private struct SourceMemberIntegrityGlyph: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AppPalette.instrument))
            let blue = Color(red: 0.69, green: 0.8, blue: 1)
            context.fill(
                Path(CGRect(x: size.width * 0.46, y: size.height * 0.18, width: size.width * 0.09, height: size.height * 0.64)),
                with: .color(blue)
            )
            context.fill(
                Path(CGRect(x: size.width * 0.18, y: size.height * 0.46, width: size.width * 0.64, height: size.height * 0.09)),
                with: .color(blue)
            )
            context.fill(
                Path(CGRect(x: size.width * 0.38, y: size.height * 0.38, width: size.width * 0.24, height: size.height * 0.24)),
                with: .color(.white)
            )
        }
        .accessibilityHidden(true)
    }
}

private struct SourcePreflightRow: View {
    let check: SourcePreflightCheck

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
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.text)
            Spacer(minLength: 4)
            Text(check.state.rawValue.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(color)
        }
        .help(check.detail)
    }
}

private struct SourceDeltaMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(AppPalette.muted)
        }
    }
}

private struct SourceBlackButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(enabled ? Color.white : AppPalette.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(enabled ? AppPalette.instrument.opacity(configuration.isPressed ? 0.8 : 1) : AppPalette.borderStrong.opacity(0.55))
            .contentShape(Rectangle())
    }
}

private struct SourceOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(AppPalette.text)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(configuration.isPressed ? AppPalette.raised : AppPalette.panel)
            .overlay { Rectangle().stroke(AppPalette.borderStrong, lineWidth: 1) }
            .contentShape(Rectangle())
    }
}

private struct SourceMiniButtonStyle: ButtonStyle {
    var accented = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(accented ? Color.white : AppPalette.text)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(accented ? AppPalette.ibmBlue.opacity(configuration.isPressed ? 0.75 : 1) : AppPalette.panel)
            .overlay { Rectangle().stroke(accented ? AppPalette.registrationBlue : AppPalette.borderStrong, lineWidth: 1) }
            .contentShape(Rectangle())
    }
}

private struct IFSDirectoryEntryRow: View {
    let entry: IFSDirectoryEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            IFSObjectGlyph(kind: entry.kind, selected: selected)
                .frame(width: 17, height: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 9.5, weight: selected ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(selected ? AppPalette.ibmBlue : AppPalette.text)
                    .lineLimit(1)
                Text("\(entry.metadata.permissions) · \(entry.metadata.owner)")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 5)
            Text(entry.kind == .directory ? "—" : ByteCountFormatter.string(fromByteCount: entry.metadata.byteCount, countStyle: .file))
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 43)
        .background(selected ? AppPalette.ibmBlue.opacity(0.09) : AppPalette.panel)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(AppPalette.registrationBlue).frame(width: 3) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.8)).frame(height: 1) }
        .contentShape(Rectangle())
        .help(entry.metadata.path.value)
    }
}

private struct IFSObjectGlyph: View {
    let kind: IFSResourceKind
    let selected: Bool

    var body: some View {
        Canvas { context, size in
            let color = selected ? AppPalette.registrationBlue : AppPalette.secondary
            let stroke = StrokeStyle(lineWidth: 1.15, lineCap: .square, lineJoin: .miter)
            switch kind {
            case .directory:
                var path = Path()
                path.move(to: CGPoint(x: 1, y: 4))
                path.addLine(to: CGPoint(x: size.width * 0.43, y: 4))
                path.addLine(to: CGPoint(x: size.width * 0.52, y: 7))
                path.addLine(to: CGPoint(x: size.width - 1, y: 7))
                path.addLine(to: CGPoint(x: size.width - 1, y: size.height - 2))
                path.addLine(to: CGPoint(x: 1, y: size.height - 2))
                path.closeSubpath()
                context.stroke(path, with: .color(color), style: stroke)
                context.fill(Path(CGRect(x: 2, y: 1, width: size.width * 0.38, height: 3)), with: .color(color))
            case .file:
                context.stroke(Path(CGRect(x: 3, y: 1, width: size.width - 6, height: size.height - 2)), with: .color(color), style: stroke)
                context.fill(Path(CGRect(x: 6, y: 6, width: size.width - 10, height: 2)), with: .color(color))
                context.fill(Path(CGRect(x: 6, y: 10, width: size.width - 12, height: 2)), with: .color(color.opacity(0.65)))
            case .symbolicLink:
                context.stroke(Path(CGRect(x: 1, y: 5, width: 9, height: 7)), with: .color(color), style: stroke)
                context.stroke(Path(CGRect(x: 7, y: 5, width: 9, height: 7)), with: .color(color), style: stroke)
            case .other:
                context.stroke(Path(ellipseIn: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)), with: .color(color), style: stroke)
                context.fill(Path(CGRect(x: size.width * 0.44, y: 5, width: 2, height: size.height - 10)), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct IFSFlightRecorderGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 2))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 2))
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
        path.addRect(CGRect(x: rect.midX - 2.5, y: rect.midY - 2.5, width: 5, height: 5))
        return path
    }
}

private struct FlightPlanRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.ibmBlue)
                .frame(width: 18, height: 18)
                .background(AppPalette.ibmBlue.opacity(0.09))
                .overlay { Rectangle().stroke(AppPalette.registrationBlue.opacity(0.55), lineWidth: 1) }
            Text(text)
                .font(.system(size: 8.5))
                .foregroundStyle(AppPalette.secondary)
        }
    }
}

private struct IFSWriteReviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IFSFlightRecorderGlyph()
                    .stroke(AppPalette.terminalGreen, lineWidth: 1.4)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REVIEW STAGED IFS WRITE")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.white)
                    Text("This confirmation is bound to one host, path, revision, and payload.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.71, green: 0.78, blue: 0.74))
                }
                Spacer()
                Text(model.ifsPhase.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.ifsPhase == .writing ? AppPalette.warning : AppPalette.terminalGreen)
            }
            .padding(.horizontal, 20)
            .frame(height: 68)
            .background(AppPalette.instrument)

            if let plan = model.ifsWritePlan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ReviewSection(title: "EXACT DESTINATION") {
                            ReviewField(label: "HOST", value: model.secureChannelProfile.targetLabel)
                            ReviewField(label: "PATH", value: plan.target.value)
                            ReviewField(label: "MODE", value: model.ifsSelectedMetadata?.permissions ?? "unknown")
                        }

                        ReviewSection(title: "REVISION CONTRACT") {
                            ReviewField(label: "EXPECTED REMOTE", value: plan.expectedRevision.token)
                            ReviewField(label: "REVIEWED PAYLOAD", value: "sha256:\(plan.payloadSHA256):\(plan.byteCount)")
                            ReviewField(label: "ENCODING", value: "UTF-8 · CCSID \(plan.ccsid) · \(plan.lineEnding.rawValue)")
                        }

                        ReviewSection(title: "STAGED REPLACEMENT") {
                            FlightPlanRow(number: "1", text: "Upload to the generated sibling path")
                            ReviewField(label: "SIBLING", value: plan.stagedSibling.value)
                            FlightPlanRow(number: "2", text: "Download and hash the staged bytes")
                            FlightPlanRow(number: "3", text: "Re-check the target immediately before rename")
                            FlightPlanRow(number: "4", text: "Request rename, then hash the committed target")
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Rectangle().fill(AppPalette.danger).frame(width: 4, height: 42)
                            Text("Any host, path, revision, object-type, encoding, staged-payload, rename, or committed-payload mismatch stops the workflow. An unverified rename outcome requires remote inspection before any retry; iTelAS never replays it automatically.")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(AppPalette.danger.opacity(0.055))
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(model.ifsDiagnostic ?? "The reviewed plan is no longer available.")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                Button("CANCEL") { model.cancelIFSWriteReview() }
                    .buttonStyle(SourceOutlineButtonStyle())
                    .disabled(model.ifsPhase == .writing)
                Button(model.ifsPhase == .writing ? "VERIFYING REMOTE WRITE…" : "WRITE EXACT REVIEWED BYTES") {
                    model.commitReviewedIFSWrite()
                }
                .buttonStyle(SourceBlackButtonStyle(enabled: model.ifsWritePlan != nil && model.ifsPhase == .reviewReady))
                .disabled(model.ifsWritePlan == nil || model.ifsPhase != .reviewReady)
            }
            .padding(16)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .frame(minWidth: 680, minHeight: 700)
        .background(AppPalette.window)
        .interactiveDismissDisabled(model.ifsPhase == .writing)
        .onDisappear {
            if model.ifsPhase == .reviewReady { model.cancelIFSWriteReview() }
        }
    }
}

private struct SourceMemberWriteReviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SourceMemberIntegrityGlyph()
                    .frame(width: 25, height: 25)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REVIEW SOURCE-MEMBER TRANSACTION")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.white)
                    Text("One exact identity, one expected revision, one proposed record set.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.71, green: 0.78, blue: 0.74))
                }
                Spacer()
                Text(model.sourceMemberPhase.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.sourceMemberPhase == .writing ? AppPalette.warning : AppPalette.terminalGreen)
            }
            .padding(.horizontal, 20)
            .frame(height: 68)
            .background(AppPalette.instrument)

            if let plan = model.sourceMemberWritePlan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ReviewSection(title: "EXACT DESTINATION") {
                            ReviewField(label: "HOST", value: model.db2Receipt?.targetName ?? "Connection unavailable")
                            ReviewField(label: "LIBRARY", value: plan.identity.library.value)
                            ReviewField(label: "SOURCE FILE", value: plan.identity.sourceFile.value)
                            ReviewField(label: "MEMBER", value: plan.identity.member.value)
                        }

                        ReviewSection(title: "REVISION CONTRACT") {
                            ReviewField(label: "EXPECTED", value: plan.expectedRevision.token)
                            ReviewField(label: "PROPOSED", value: plan.proposedRevision.token)
                            ReviewField(label: "RECORDS", value: "\(plan.expectedRevision.recordCount) → \(plan.records.count)")
                        }

                        ReviewSection(title: "RECORD CONTRACT") {
                            ReviewField(label: "CCSID", value: String(plan.ccsid))
                            ReviewField(label: "SOURCE WIDTH", value: "\(plan.sourceTextByteLength) bytes")
                            ReviewField(label: "SOURCE DATE", value: plan.sourceDatePolicy.label)
                            ReviewField(label: "ISOLATION", value: "SERIALIZABLE · EXPLICIT COMMIT")
                        }

                        if let eligibility = model.sourceMemberWriteEligibility {
                            ReviewSection(title: "SIX ELIGIBILITY GATES") {
                                ForEach(eligibility.checks) { gate in
                                    SourceMemberWriteGateRow(gate: gate)
                                }
                            }
                        }

                        ReviewSection(title: "TRANSACTION SEQUENCE") {
                            FlightPlanRow(number: "1", text: "Create the deterministic QTEMP alias")
                            FlightPlanRow(number: "2", text: "Re-read and match the expected canonical revision")
                            FlightPlanRow(number: "3", text: "Replace SRCSEQ, SRCDAT, and SRCDTA records in bounded batches")
                            FlightPlanRow(number: "4", text: "Re-read and match the proposed canonical revision before commit")
                            FlightPlanRow(number: "5", text: "Commit once, then remove the QTEMP alias")
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Rectangle().fill(AppPalette.danger).frame(width: 4, height: 50)
                            Text("Any identity, revision, layout, authority, CCSID, byte-width, journal-image, trigger, sequence, or post-write revision mismatch rolls back or fails closed. This review cannot authorize general SQL or a different member.")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(AppPalette.danger.opacity(0.055))
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(model.sourceMemberDiagnostic)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                Button("CANCEL") { model.cancelSourceMemberWriteReview() }
                    .buttonStyle(SourceOutlineButtonStyle())
                    .disabled(model.sourceMemberPhase == .writing)
                Button(model.sourceMemberPhase == .writing ? "VERIFYING TRANSACTION…" : "COMMIT EXACT REVIEWED RECORDS") {
                    model.commitReviewedSourceMemberWrite()
                }
                .buttonStyle(SourceBlackButtonStyle(
                    enabled: model.sourceMemberWritePlan != nil && model.sourceMemberPhase == .reviewReady
                ))
                .disabled(model.sourceMemberWritePlan == nil || model.sourceMemberPhase != .reviewReady)
            }
            .padding(16)
            .background(AppPalette.raised)
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .frame(minWidth: 720, minHeight: 760)
        .background(AppPalette.window)
        .interactiveDismissDisabled(model.sourceMemberPhase == .writing)
        .onDisappear {
            if model.sourceMemberPhase == .reviewReady {
                model.cancelSourceMemberWriteReview()
            }
        }
    }
}

private struct ReviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.75)
                .foregroundStyle(AppPalette.ibmBlue)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }
}

private struct ReviewField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AppPalette.muted)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(AppPalette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SourceMemberRemoteComparisonView: View {
    let localDraft: String
    let openedBaseline: String
    let currentRemote: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SourceMemberIntegrityGlyph()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOURCE-MEMBER REVISION COMPARISON")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.white)
                    Text("The local draft and current member records are read-only in this comparison.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.71, green: 0.78, blue: 0.74))
                }
                Spacer()
                Text("OPENED BASELINE · \(openedBaseline.split(separator: "\n", omittingEmptySubsequences: false).count) RECORDS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.terminalGreen)
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            .background(AppPalette.instrument)

            HStack(spacing: 0) {
                ComparisonColumn(title: "LOCAL WORKING DRAFT", marker: AppPalette.warning, text: localDraft)
                Rectangle().fill(AppPalette.borderStrong).frame(width: 1)
                ComparisonColumn(title: "CURRENT MEMBER RECORDS", marker: AppPalette.ibmBlue, text: currentRemote)
            }

            HStack(spacing: 8) {
                Rectangle().fill(AppPalette.danger).frame(width: 4, height: 27)
                Text("A conflict never rebases or overwrites the local draft automatically. Reconcile explicitly, reopen the member, and establish a new reviewed revision.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(AppPalette.danger.opacity(0.055))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.danger.opacity(0.35)).frame(height: 1) }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(AppPalette.window)
    }
}

private struct IFSRemoteComparisonView: View {
    let localDraft: String
    let openedBaseline: String
    let currentRemote: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ChangeLensGlyph()
                    .stroke(AppPalette.terminalGreen, lineWidth: 1.4)
                    .frame(width: 23, height: 23)
                VStack(alignment: .leading, spacing: 2) {
                    Text("IFS REVISION COMPARISON")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.white)
                    Text("Local draft and current remote bytes are read-only in this comparison.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.71, green: 0.78, blue: 0.74))
                }
                Spacer()
                Text("OPENED BASELINE · \(openedBaseline.split(separator: "\n", omittingEmptySubsequences: false).count) LINES")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.terminalGreen)
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            .background(AppPalette.instrument)

            HStack(spacing: 0) {
                ComparisonColumn(title: "LOCAL WORKING DRAFT", marker: AppPalette.warning, text: localDraft)
                Rectangle().fill(AppPalette.borderStrong).frame(width: 1)
                ComparisonColumn(title: "CURRENT REMOTE", marker: AppPalette.ibmBlue, text: currentRemote)
            }

            HStack(spacing: 8) {
                Rectangle().fill(AppPalette.danger).frame(width: 4, height: 24)
                Text("A conflict never updates the draft baseline automatically. Reconcile explicitly, then reopen the remote file to establish a new write revision.")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(AppPalette.danger.opacity(0.055))
            .overlay(alignment: .top) { Rectangle().fill(AppPalette.danger.opacity(0.35)).frame(height: 1) }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(AppPalette.window)
    }
}

private struct ComparisonColumn: View {
    let title: String
    let marker: Color
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(marker).frame(width: 4, height: 14)
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                Spacer()
                Text("\(text.split(separator: "\n", omittingEmptySubsequences: false).count) LINES")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AppPalette.text)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(AppPalette.panel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SourceReticleGlyph: Shape {
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

private struct SourceFileGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var sheet = Path()
            sheet.move(to: CGPoint(x: 1, y: 1))
            sheet.addLine(to: CGPoint(x: size.width * 0.62, y: 1))
            sheet.addLine(to: CGPoint(x: size.width - 1, y: size.height * 0.3))
            sheet.addLine(to: CGPoint(x: size.width - 1, y: size.height - 1))
            sheet.addLine(to: CGPoint(x: 1, y: size.height - 1))
            sheet.closeSubpath()
            context.stroke(sheet, with: .color(color), lineWidth: 1.2)

            var fold = Path()
            fold.move(to: CGPoint(x: size.width * 0.62, y: 1))
            fold.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.3))
            fold.addLine(to: CGPoint(x: size.width - 1, y: size.height * 0.3))
            context.stroke(fold, with: .color(color), lineWidth: 1.1)
        }
    }
}

private struct SourceMemberRecordGlyph: View {
    let primary: Color
    let secondary: Color

    var body: some View {
        Canvas { context, size in
            let spine = Path(CGRect(
                x: 1,
                y: 1,
                width: max(2, size.width * 0.16),
                height: size.height - 2
            ))
            context.fill(spine, with: .color(primary))

            let railX = size.width * 0.31
            let available = size.width - railX - 1
            let heights = [size.height * 0.18, size.height * 0.46, size.height * 0.74]
            let widths = [available, available * 0.72, available * 0.9]
            for index in heights.indices {
                let rail = Path(CGRect(
                    x: railX,
                    y: heights[index],
                    width: widths[index],
                    height: max(1.5, size.height * 0.11)
                ))
                context.fill(rail, with: .color(index == 1 ? primary.opacity(0.8) : secondary))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ChangeLensGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let half = rect.width * 0.48
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: half, height: half))
        path.addRect(CGRect(x: rect.maxX - half, y: rect.maxY - half, width: half, height: half))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY * 0.98))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct SourceSafetyDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.midX, y: rect.height * 0.27))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.59))
        path.move(to: CGPoint(x: rect.midX, y: rect.height * 0.73))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.75))
        return path
    }
}

@MainActor
struct PrecisionTextEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let isEditable: Bool
    let recordMetadata: [SourceMemberRecord]?
    let navigationRequest: SourceNavigationRequest?
    let highlightSpans: [SourceHighlightSpan]
    let highlightRevision: String
    let completionSession: SourceCompletionSession?
    let completionSelectionIndex: Int
    let onCursorChange: (Int, Int) -> Void
    let onSelectionChange: (NSRange) -> Void
    let onCompletionRequest: (Int) -> Void
    let onCompletionMove: (Int) -> Void
    let onCompletionDismiss: () -> Void
    let onCompletionAssist: (String) -> Void

    init(
        text: Binding<String>,
        accessibilityLabel: String,
        isEditable: Bool = true,
        recordMetadata: [SourceMemberRecord]? = nil,
        navigationRequest: SourceNavigationRequest? = nil,
        highlightSpans: [SourceHighlightSpan] = [],
        highlightRevision: String = "none",
        completionSession: SourceCompletionSession? = nil,
        completionSelectionIndex: Int = 0,
        onCursorChange: @escaping (Int, Int) -> Void,
        onSelectionChange: @escaping (NSRange) -> Void = { _ in },
        onCompletionRequest: @escaping (Int) -> Void = { _ in },
        onCompletionMove: @escaping (Int) -> Void = { _ in },
        onCompletionDismiss: @escaping () -> Void = {},
        onCompletionAssist: @escaping (String) -> Void = { _ in }
    ) {
        _text = text
        self.accessibilityLabel = accessibilityLabel
        self.isEditable = isEditable
        self.recordMetadata = recordMetadata
        self.navigationRequest = navigationRequest
        self.highlightSpans = highlightSpans
        self.highlightRevision = highlightRevision
        self.completionSession = completionSession
        self.completionSelectionIndex = completionSelectionIndex
        self.onCursorChange = onCursorChange
        self.onSelectionChange = onSelectionChange
        self.onCompletionRequest = onCompletionRequest
        self.onCompletionMove = onCompletionMove
        self.onCompletionDismiss = onCompletionDismiss
        self.onCompletionAssist = onCompletionAssist
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PrecisionEditorScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.992, alpha: 1)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false

        let textView = PrecisionEditorTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 300))
        scrollView.documentView = textView
        textView.delegate = context.coordinator
        textView.recordMetadata = recordMetadata
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.12, alpha: 1)
        textView.drawsBackground = true
        textView.backgroundColor = scrollView.backgroundColor
        textView.insertionPointColor = NSColor(calibratedRed: 0.06, green: 0.38, blue: 0.996, alpha: 1)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(calibratedRed: 0.86, green: 0.91, blue: 1, alpha: 1),
            .foregroundColor: NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.16, alpha: 1)
        ]
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: 100_000, height: 10_000_000)
        textView.textContainer?.containerSize = NSSize(width: 100_000, height: 10_000_000)
        textView.textContainer?.widthTracksTextView = false
        textView.setAccessibilityLabel(accessibilityLabel)
        applyEditorAttributes(to: textView, highlights: highlightSpans)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.needsDisplay = true

        let gutter = PrecisionEditorLineNumberGutterView(
            textView: textView,
            recordMetadata: recordMetadata
        )
        scrollView.lineNumberGutter = gutter
        scrollView.addSubview(gutter, positioned: .above, relativeTo: scrollView.contentView)
        scrollView.needsLayout = true

        context.coordinator.textView = textView
        context.coordinator.lineNumberGutter = gutter
        context.coordinator.scrollView = scrollView
        context.coordinator.appliedHighlightRevision = highlightRevision
        context.coordinator.installCompletionOverlay(in: scrollView)
        context.coordinator.reportCursor()
        return scrollView
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSScrollView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: max(0, proposal.width ?? 320),
            height: max(0, proposal.height ?? 300)
        )
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.setAccessibilityLabel(accessibilityLabel)
        (textView as? PrecisionEditorTextView)?.recordMetadata = recordMetadata
        context.coordinator.lineNumberGutter?.recordMetadata = recordMetadata
        scrollView.needsLayout = true
        textView.isEditable = isEditable
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            applyEditorAttributes(to: textView, highlights: [])
            textView.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.needsDisplay = true
            scrollView.needsDisplay = true
            context.coordinator.lineNumberGutter?.needsDisplay = true
            context.coordinator.reportCursor()
        }
        if context.coordinator.appliedHighlightRevision != highlightRevision {
            applyEditorAttributes(to: textView, highlights: highlightSpans)
            context.coordinator.appliedHighlightRevision = highlightRevision
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.needsDisplay = true
        }
        if let navigationRequest,
           context.coordinator.appliedNavigationID != navigationRequest.id,
           let selection = selectionRange(for: navigationRequest.range, in: textView.string) {
            context.coordinator.appliedNavigationID = navigationRequest.id
            textView.setSelectedRange(selection)
            textView.scrollRangeToVisible(selection)
            context.coordinator.reportCursor()
        }
        context.coordinator.updateCompletionOverlay()
    }

    private func selectionRange(for range: SourceTextRange, in text: String) -> NSRange? {
        range.utf16Range(in: text)
    }

    private func applyEditorAttributes(
        to textView: NSTextView,
        highlights: [SourceHighlightSpan]
    ) {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.12, alpha: 1)
        ]
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        let selection = textView.selectedRanges
        storage.beginEditing()
        if fullRange.length > 0 { storage.setAttributes(baseAttributes, range: fullRange) }
        for highlight in highlights.sorted(by: { $0.kind.priority < $1.kind.priority }) {
            guard let range = highlight.range.utf16Range(in: textView.string),
                  range.location >= 0,
                  NSMaxRange(range) <= fullRange.length else { continue }
            storage.addAttributes(highlightAttributes(for: highlight.kind), range: range)
        }
        storage.endEditing()
        textView.typingAttributes = baseAttributes
        let validSelection = selection.filter { NSMaxRange($0.rangeValue) <= fullRange.length }
        if !validSelection.isEmpty { textView.selectedRanges = validSelection }
    }

    private func highlightAttributes(for kind: SourceHighlightKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .directive:
            return [
                .foregroundColor: NSColor(calibratedRed: 0.47, green: 0.36, blue: 0.00, alpha: 1),
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .medium)
            ]
        case .keyword:
            return [
                .foregroundColor: NSColor(calibratedRed: 0.06, green: 0.38, blue: 0.996, alpha: 1),
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .medium)
            ]
        case .declaration:
            return [
                .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.24, blue: 0.62, alpha: 1),
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
            ]
        case .typeName:
            return [.foregroundColor: NSColor(calibratedRed: 0.00, green: 0.43, blue: 0.42, alpha: 1)]
        case .builtIn:
            return [.foregroundColor: NSColor(calibratedRed: 0.41, green: 0.16, blue: 0.77, alpha: 1)]
        case .stringLiteral:
            return [.foregroundColor: NSColor(calibratedRed: 0.24, green: 0.40, blue: 0.31, alpha: 1)]
        case .number:
            return [.foregroundColor: NSColor(calibratedRed: 0.57, green: 0.35, blue: 0.00, alpha: 1)]
        case .comment:
            return [
                .foregroundColor: NSColor(calibratedRed: 0.39, green: 0.46, blue: 0.42, alpha: 1),
                .obliqueness: 0.12
            ]
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PrecisionTextEditor
        weak var textView: NSTextView?
        fileprivate weak var lineNumberGutter: PrecisionEditorLineNumberGutterView?
        weak var scrollView: NSScrollView?
        fileprivate weak var completionHost: NSHostingView<SourceCompletionOverlayView>?
        var appliedNavigationID: UUID?
        var appliedHighlightRevision: String?

        init(parent: PrecisionTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            parent.onCompletionDismiss()
            textView.needsDisplay = true
            lineNumberGutter?.needsDisplay = true
            reportCursor()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let session = parent.completionSession,
               let textView,
               textView.selectedRange() != NSRange(location: session.caretUTF16, length: 0) {
                parent.onCompletionDismiss()
            }
            reportCursor()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let command = NSStringFromSelector(commandSelector)
            if command == "complete:" {
                parent.onCompletionRequest(textView.selectedRange().location)
                return true
            }
            guard parent.completionSession?.isPresentable == true else { return false }
            switch command {
            case "moveUp:":
                parent.onCompletionMove(-1)
                return true
            case "moveDown:":
                parent.onCompletionMove(1)
                return true
            case "insertNewline:", "insertNewlineIgnoringFieldEditor:", "insertTab:":
                activateSelectedCompletion()
                return true
            case "cancelOperation:":
                parent.onCompletionDismiss()
                return true
            default:
                return false
            }
        }

        func installCompletionOverlay(in scrollView: NSScrollView) {
            let coordinator = self
            let host = NSHostingView(rootView: SourceCompletionOverlayView(
                session: parent.completionSession,
                selectedIndex: parent.completionSelectionIndex,
                onActivate: { coordinator.activateCompletion(itemID: $0) },
                onDismiss: { coordinator.parent.onCompletionDismiss() }
            ))
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = []
            host.wantsLayer = true
            host.layer?.zPosition = 100
            host.isHidden = true
            scrollView.addSubview(host, positioned: .above, relativeTo: scrollView.contentView)
            completionHost = host
            updateCompletionOverlay()
        }

        func updateCompletionOverlay() {
            guard let host = completionHost,
                  let scrollView,
                  let textView,
                  let session = parent.completionSession,
                  session.isPresentable else {
                completionHost?.isHidden = true
                return
            }
            let selectedIndex = min(max(0, parent.completionSelectionIndex), session.items.count - 1)
            let coordinator = self
            host.rootView = SourceCompletionOverlayView(
                session: session,
                selectedIndex: selectedIndex,
                onActivate: { coordinator.activateCompletion(itemID: $0) },
                onDismiss: { coordinator.parent.onCompletionDismiss() }
            )

            let availableWidth = max(180, scrollView.bounds.width - 24)
            let width = min(510, availableWidth)
            let visibleRows = min(5, session.items.count)
            let height = min(scrollView.bounds.height - 24, CGFloat(155 + visibleRows * 44))
            let anchor = completionAnchor(
                caretUTF16: session.caretUTF16,
                textView: textView,
                scrollView: scrollView
            )
            let x = min(max(12, anchor.minX), max(12, scrollView.bounds.width - width - 12))
            let below = anchor.minY - height - 7
            let above = min(scrollView.bounds.height - height - 12, anchor.maxY + 7)
            let y = below >= 12 ? below : max(12, above)
            host.frame = NSRect(x: x, y: y, width: width, height: max(180, height))
            host.isHidden = false
        }

        private func completionAnchor(
            caretUTF16: Int,
            textView: NSTextView,
            scrollView: NSScrollView
        ) -> NSRect {
            guard let window = scrollView.window else {
                return NSRect(x: 20, y: scrollView.bounds.midY, width: 1, height: 16)
            }
            let safeCaret = min(max(0, caretUTF16), textView.string.utf16.count)
            let screenRect = textView.firstRect(
                forCharacterRange: NSRange(location: safeCaret, length: 0),
                actualRange: nil
            )
            return scrollView.convert(window.convertFromScreen(screenRect), from: nil)
        }

        private func activateSelectedCompletion() {
            guard let session = parent.completionSession, !session.items.isEmpty else { return }
            let index = min(max(0, parent.completionSelectionIndex), session.items.count - 1)
            activateCompletion(itemID: session.items[index].id)
        }

        func activateCompletion(itemID: String) {
            guard let textView,
                  let session = parent.completionSession,
                  let item = session.items.first(where: { $0.id == itemID }) else {
                parent.onCompletionDismiss()
                return
            }
            if item.action == .openAssistReview {
                parent.onCompletionAssist(itemID)
                return
            }
            do {
                let edit = try session.validatedEdit(for: itemID, in: textView.string)
                textView.window?.makeFirstResponder(textView)
                textView.insertText(edit.replacement, replacementRange: edit.range.nsRange)
                textView.setSelectedRange(NSRange(
                    location: edit.range.location + edit.replacement.utf16.count,
                    length: 0
                ))
                parent.onCompletionDismiss()
                reportCursor()
            } catch {
                parent.onCompletionDismiss()
                NSSound.beep()
            }
        }

        func reportCursor() {
            guard let textView else { return }
            let selection = textView.selectedRange()
            let location = min(selection.location, textView.string.utf16.count)
            let prefix = (textView.string as NSString).substring(to: location)
            let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
            parent.onCursorChange(lines.count, (lines.last?.utf16.count ?? 0) + 1)
            parent.onSelectionChange(selection)
        }
    }
}

private struct SourceCompletionOverlayView: View {
    let session: SourceCompletionSession?
    let selectedIndex: Int
    let onActivate: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        if let session, session.isPresentable {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppPalette.registrationBlue)
                    .frame(height: 3)

                HStack(spacing: 10) {
                    SourceCompletionForkMark()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CONTENT ASSIST")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(AppPalette.text)
                        Text("\(session.format.rawValue.uppercased()) · LOCAL ANALYZER · RECEIPT \(session.shortReceipt)")
                            .font(.system(size: 7.2, weight: .medium, design: .monospaced))
                            .tracking(0.25)
                            .foregroundStyle(AppPalette.muted)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("CTRL SPACE")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                        Text(completionCountLabel(session))
                            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.ibmBlue)
                    }
                    Button(action: onDismiss) {
                        Text("×")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppPalette.secondary)
                            .frame(width: 24, height: 24)
                            .background(AppPalette.raised)
                            .overlay { Rectangle().stroke(AppPalette.border, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close content assist")
                }
                .padding(.horizontal, 11)
                .frame(height: 56)
                .background(AppPalette.panel)

                HStack(spacing: 8) {
                    Text(session.qualifier == nil ? "PREFIX" : "QUALIFIER")
                        .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppPalette.muted)
                    Text(completionContextLabel(session))
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                    Spacer()
                    if session.wasLimited {
                        Text("BOUNDED")
                            .font(.system(size: 6.6, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.56, green: 0.40, blue: 0))
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(AppPalette.raised)
                .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    onActivate(item.id)
                                } label: {
                                    SourceCompletionRow(
                                        item: item,
                                        selected: index == selectedIndex
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .accessibilityLabel(completionAccessibilityLabel(item, selected: index == selectedIndex))
                            }
                        }
                    }
                    .onAppear {
                        scrollToSelection(session: session, proxy: proxy)
                    }
                    .onChange(of: selectedIndex) { _, _ in
                        scrollToSelection(session: session, proxy: proxy)
                    }
                }
                .frame(height: CGFloat(min(5, session.items.count) * 44))
                .background(AppPalette.panel)

                completionReceipt(session)
                    .frame(height: 37)
                    .background(Color(red: 0.965, green: 0.977, blue: 0.992))
                    .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }

                HStack {
                    Text("UP/DOWN MOVE · RETURN ACCEPT · ESC CLOSE")
                    Spacer()
                    Text(session.boundaryLabel.uppercased())
                }
                .font(.system(size: 6.7, weight: .bold, design: .monospaced))
                .tracking(0.32)
                .foregroundStyle(AppPalette.muted)
                .padding(.horizontal, 11)
                .frame(height: 29)
                .background(AppPalette.raised)
                .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
            }
            .background(AppPalette.panel)
            .overlay {
                Rectangle().stroke(AppPalette.instrument.opacity(0.72), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Local source content assist")
        } else {
            EmptyView()
        }
    }

    private func completionCountLabel(_ session: SourceCompletionSession) -> String {
        let local = session.items.filter { $0.action == .insertText }.count
        let review = session.items.filter { $0.action == .openAssistReview }.count
        return review == 0 ? "\(local) LOCAL" : "\(local) LOCAL · \(review) REVIEW"
    }

    private func completionContextLabel(_ session: SourceCompletionSession) -> String {
        if let qualifier = session.qualifier {
            return qualifier + "." + session.prefix
        }
        return session.prefix.isEmpty ? "ALL LOCAL SYMBOLS" : session.prefix
    }

    @ViewBuilder
    private func completionReceipt(_ session: SourceCompletionSession) -> some View {
        let safeIndex = min(max(0, selectedIndex), session.items.count - 1)
        let item = session.items[safeIndex]
        HStack(spacing: 8) {
            Rectangle()
                .fill(item.action == .insertText ? AppPalette.success : AppPalette.registrationBlue)
                .frame(width: 3, height: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.action == .insertText ? "RETURN INSERTS LOCAL TEXT · UNDOABLE" : "RETURN OPENS CONTEXT DOSSIER · SENDS NOTHING YET")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .tracking(0.35)
                    .foregroundStyle(AppPalette.secondary)
                Text(item.detail)
                    .font(.system(size: 7.4))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
    }

    private func completionAccessibilityLabel(_ item: SourceCompletionItem, selected: Bool) -> String {
        let action = item.action == .insertText ? "Insert" : "Open reviewed Assist context"
        return "\(selected ? "Selected, " : "")\(item.kind.label) \(item.label). \(item.detail). \(action)."
    }

    private func scrollToSelection(
        session: SourceCompletionSession,
        proxy: ScrollViewProxy
    ) {
        guard session.items.indices.contains(selectedIndex) else { return }
        proxy.scrollTo(session.items[selectedIndex].id, anchor: .center)
    }
}

private struct SourceCompletionRow: View {
    let item: SourceCompletionItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Text(item.kind.shortLabel)
                .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(selected ? Color.white : kindColor)
                .frame(width: 35, height: 20)
                .background(selected ? Color.white.opacity(0.13) : kindColor.opacity(0.09))
                .overlay {
                    Rectangle().stroke(selected ? Color.white.opacity(0.36) : kindColor.opacity(0.42), lineWidth: 0.8)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? Color.white : AppPalette.text)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 7.2))
                    .foregroundStyle(selected ? Color.white.opacity(0.78) : AppPalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let line = item.sourceLine {
                Text("L\(line)")
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : AppPalette.muted)
            }
            Text(originLabel)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? Color.white.opacity(0.82) : kindColor)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(selected ? selectionColor : AppPalette.panel)
        .overlay(alignment: .leading) {
            Rectangle().fill(selected ? AppPalette.terminalGreen : kindColor).frame(width: 3)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border.opacity(0.75)).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private var selectionColor: Color {
        item.action == .openAssistReview ? AppPalette.instrument : AppPalette.registrationBlue
    }

    private var originLabel: String {
        switch item.origin {
        case .currentDocument: "DOC"
        case .workspaceIndex: "INDEX"
        case .languageCatalog: "CAT"
        case .assistReview: "REVIEW"
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .field: AppPalette.registrationBlue
        case .variable, .parameter: Color(red: 0.10, green: 0.48, blue: 0.40)
        case .dataStructure, .recordFormat: Color(red: 0.48, green: 0.24, blue: 0.62)
        case .procedure, .prototype: Color(red: 0.12, green: 0.35, blue: 0.68)
        case .file: Color(red: 0.50, green: 0.36, blue: 0.04)
        case .keyword: Color(red: 0.36, green: 0.27, blue: 0.66)
        case .builtIn: Color(red: 0.55, green: 0.25, blue: 0.68)
        case .assistReview: AppPalette.ibmBlue
        }
    }
}

private struct SourceCompletionForkMark: View {
    var compact = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                ChamferedRectangle(cut: compact ? 3 : 5)
                    .fill(compact ? Color.white.opacity(0.08) : AppPalette.instrument)
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.24, y: size.height * 0.72))
                    path.addLine(to: CGPoint(x: size.width * 0.45, y: size.height * 0.52))
                    path.addLine(to: CGPoint(x: size.width * 0.45, y: size.height * 0.28))
                    path.move(to: CGPoint(x: size.width * 0.45, y: size.height * 0.52))
                    path.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.52))
                    path.move(to: CGPoint(x: size.width * 0.45, y: size.height * 0.52))
                    path.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.76))
                }
                .stroke(compact ? Color.white.opacity(0.78) : AppPalette.terminalGreen, style: StrokeStyle(lineWidth: compact ? 1 : 1.4, lineCap: .square, lineJoin: .miter))
                Rectangle()
                    .fill(AppPalette.registrationBlue)
                    .frame(width: compact ? 3 : 4, height: compact ? 3 : 4)
                    .position(x: size.width * 0.45, y: size.height * 0.52)
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == 1 ? AppPalette.registrationBlue : Color.white)
                        .frame(width: compact ? 2.5 : 3.5, height: compact ? 2.5 : 3.5)
                        .position(portPosition(index, size: size))
                }
                if !compact {
                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.10, y: size.height * 0.18))
                        path.addLine(to: CGPoint(x: size.width * 0.26, y: size.height * 0.18))
                        path.move(to: CGPoint(x: size.width * 0.74, y: size.height * 0.86))
                        path.addLine(to: CGPoint(x: size.width * 0.90, y: size.height * 0.86))
                    }
                    .stroke(AppPalette.registrationBlue.opacity(0.72), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func portPosition(_ index: Int, size: CGSize) -> CGPoint {
        switch index {
        case 0: CGPoint(x: size.width * 0.24, y: size.height * 0.72)
        case 1: CGPoint(x: size.width * 0.45, y: size.height * 0.28)
        default: CGPoint(x: size.width * 0.72, y: size.height * 0.52)
        }
    }
}

@MainActor
private final class PrecisionEditorScrollView: NSScrollView {
    weak var lineNumberGutter: PrecisionEditorLineNumberGutterView?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        guard let lineNumberGutter else { return }
        lineNumberGutter.frame = NSRect(
            x: contentView.frame.minX,
            y: contentView.frame.minY,
            width: lineNumberGutter.preferredWidth,
            height: contentView.frame.height
        )
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        lineNumberGutter?.needsDisplay = true
    }
}

@MainActor
private final class PrecisionEditorTextView: NSTextView {
    var recordMetadata: [SourceMemberRecord]? {
        didSet {
            textContainerInset = NSSize(width: gutterWidth + 10, height: 9)
            needsDisplay = true
        }
    }

    private var gutterWidth: CGFloat { recordMetadata == nil ? 68 : 98 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textContainerInset = NSSize(width: gutterWidth + 10, height: 9)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        textContainerInset = NSSize(width: gutterWidth + 10, height: 9)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        textContainerInset = NSSize(width: gutterWidth + 10, height: 9)
    }
}

@MainActor
private final class PrecisionEditorLineNumberGutterView: NSView {
    private weak var textView: NSTextView?
    var recordMetadata: [SourceMemberRecord]? {
        didSet { needsDisplay = true }
    }

    var preferredWidth: CGFloat { recordMetadata == nil ? 68 : 98 }

    init(textView: NSTextView, recordMetadata: [SourceMemberRecord]?) {
        self.textView = textView
        self.recordMetadata = recordMetadata
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSColor(calibratedRed: 0.945, green: 0.957, blue: 0.969, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.90, alpha: 1).setStroke()
        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        edge.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        edge.lineWidth = 1
        edge.stroke()

        let viewport = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: viewport, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let source = textView.string as NSString
        let prefix = source.substring(to: min(characterRange.location, source.length))
        var lineNumber = prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.54, blue: 0.58, alpha: 1)
        ]
        var index = characterRange.location
        while index < source.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: index, length: 0)
            )
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let pointInText = NSPoint(
                x: 0,
                y: fragment.minY + textView.textContainerInset.height
            )
            let point = textView.convert(pointInText, to: self)
            if let recordMetadata {
                let recordIndex = lineNumber - 1
                if recordMetadata.indices.contains(recordIndex) {
                    let record = recordMetadata[recordIndex]
                    let sequence = record.sequence.description as NSString
                    let date = record.sourceDate.description as NSString
                    sequence.draw(at: NSPoint(x: 7, y: point.y), withAttributes: attributes)
                    date.draw(
                        at: NSPoint(x: 55, y: point.y + 1),
                        withAttributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular),
                            .foregroundColor: NSColor(calibratedRed: 0.58, green: 0.62, blue: 0.65, alpha: 1)
                        ]
                    )
                } else {
                    ("NEW" as NSString).draw(
                        at: NSPoint(x: 8, y: point.y),
                        withAttributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold),
                            .foregroundColor: NSColor(calibratedRed: 0.14, green: 0.55, blue: 0.28, alpha: 1)
                        ]
                    )
                }
            } else {
                let label = String(format: "%03d", lineNumber) as NSString
                label.draw(at: NSPoint(x: 8, y: point.y), withAttributes: attributes)
            }
            lineNumber += 1
            if fragment.minY > viewport.maxY + 30 { break }
            index = max(lineEnd, index + 1)
        }
    }
}
