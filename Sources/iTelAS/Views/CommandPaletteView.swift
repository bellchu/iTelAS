import AppKit
import SwiftUI
import iTelASCore

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var scope: PaletteScope = .all
    @State private var selection: PaletteActionID?

    private var allItems: [PaletteItem] {
        var items = WorkbenchTool.allCases.map { tool in
            PaletteItem(
                id: .tool(tool),
                scope: .navigate,
                title: "Open \(tool.title)",
                detail: tool.subtitle,
                badge: "NAVIGATE",
                available: true
            )
        }

        items.append(PaletteItem(
            id: .newSession,
            scope: .sessions,
            title: "New secure IBM i session",
            detail: "Open the TLS-first Connection Studio",
            badge: "SESSION",
            available: true
        ))
        items.append(contentsOf: model.profiles.map { profile in
            PaletteItem(
                id: .connect(profile.id),
                scope: .sessions,
                title: "Connect \(profile.name)",
                detail: "\(profile.security == .tls ? "TLS" : "Telnet") · \(profile.terminalModel.telnetName) · CCSID \(profile.ccsid)",
                badge: profile.environment.label,
                available: true
            )
        })

        items.append(PaletteItem(
            id: .screenHistory,
            scope: .navigate,
            title: "Open Session Flight Recorder",
            detail: "Review \(model.terminalFlightRecorder.frames.count) durable redacted frame(s) and reviewed macros",
            badge: "ACTION",
            available: true
        ))
        items.append(PaletteItem(
            id: .copyScreen,
            scope: .navigate,
            title: "Copy visible 5250 screen",
            detail: "Sensitive non-display fields remain hidden",
            badge: "ACTION",
            available: true
        ))

        for diagnostic in HostDiagnosticCommand.library {
            let staging = model.hostCommandStagingStatus(for: diagnostic.command)
            items.append(PaletteItem(
                id: .diagnostic(diagnostic.id),
                scope: .diagnostics,
                title: "Stage \(diagnostic.command)",
                detail: staging.isReady ? diagnostic.detail : staging.message,
                badge: staging.isReady ? "READ ONLY" : "BLOCKED",
                available: staging.isReady
            ))
        }

        items.append(contentsOf: IBMIServicesCatalog.queries.map { service in
            PaletteItem(
                id: .sqlService(service.id),
                scope: .queries,
                title: "Open \(service.title) query",
                detail: "\(service.serviceName) · \(service.summary)",
                badge: "IBM i SERVICE",
                available: true
            )
        })

        items.append(PaletteItem(
            id: .assistVisibleScreen,
            scope: .assist,
            title: "Ask Assist about the visible screen",
            detail: "Draft a question and inspect the context receipt before sending",
            badge: "ASSIST",
            available: true
        ))
        items.append(PaletteItem(
            id: .proposalPatchStack,
            scope: .assist,
            title: "Open Proposal Patch Stack",
            detail: "Review \(model.aiProposalPatchStack.count) queued local proposal\(model.aiProposalPatchStack.count == 1 ? "" : "s") as one baseline-bound atomic change",
            badge: model.aiProposalPatchStack.isEmpty ? "EMPTY" : "\(model.aiProposalPatchStack.count) QUEUED",
            available: true
        ))
        items.append(PaletteItem(
            id: .aiSettings,
            scope: .assist,
            title: "Open AI Assist settings",
            detail: model.apiKeyExists ? "Provider key is stored in macOS Keychain" : "Add a provider and API key to opt in",
            badge: "SETTINGS",
            available: true
        ))
        return items
    }

    private var visibleItems: [PaletteItem] {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
        return allItems.filter { item in
            let matchesScope = scope == .all || item.scope == scope
            let haystack = "\(item.title) \(item.detail) \(item.badge)".lowercased()
            return matchesScope && tokens.allSatisfy(haystack.contains)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }

                VStack(spacing: 0) {
                    searchHeader
                    HStack(spacing: 0) {
                        scopeRail
                        Rectangle().fill(AppPalette.border).frame(width: 1)
                        resultPane
                    }
                    footer
                }
                .frame(
                    width: min(780, geometry.size.width - 80),
                    height: min(560, geometry.size.height - 70)
                )
                .background(AppPalette.panel)
                .clipShape(ChamferedRectangle(cut: 7))
                .overlay { ChamferedRectangle(cut: 7).stroke(AppPalette.borderStrong, lineWidth: 1) }
                .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            }
        }
        .onAppear {
            model.rotateProverb()
            selection = visibleItems.first?.id
        }
        .onChange(of: query) {
            selection = visibleItems.first?.id
        }
        .onChange(of: scope) {
            selection = visibleItems.first?.id
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Universal IBM i Command Palette")
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            UtilityGlyph(kind: .commandPalette, color: AppPalette.terminalGreen, size: 21)
                .frame(width: 36, height: 36)
                .background(AppPalette.instrument, in: ChamferedRectangle(cut: 4))

            VStack(alignment: .leading, spacing: 2) {
                CommandPaletteSearchField(
                    text: $query,
                    onMoveUp: { moveSelection(-1) },
                    onMoveDown: { moveSelection(1) },
                    onSubmit: activateSelected,
                    onEscape: close
                )
                .frame(height: 22)

                Text("UNIVERSAL IBM i COMMAND PALETTE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(AppPalette.ibmBlue)
            }

            Text("⌘ K")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(AppPalette.raised, in: ChamferedRectangle(cut: 3))
                .overlay { ChamferedRectangle(cut: 3).stroke(AppPalette.borderStrong, lineWidth: 0.8) }
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var scopeRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SCOPE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(AppPalette.muted)
                .padding(.horizontal, 9)
                .padding(.bottom, 4)

            ForEach(Array(PaletteScope.allCases.enumerated()), id: \.element) { index, candidate in
                Button {
                    scope = candidate
                } label: {
                    HStack(spacing: 9) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(scope == candidate ? AppPalette.ibmBlue : AppPalette.muted)
                        Text(candidate.label)
                            .font(.system(size: 10, weight: scope == candidate ? .semibold : .regular))
                            .foregroundStyle(scope == candidate ? AppPalette.text : AppPalette.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                    .background(scope == candidate ? AppPalette.ibmBlue.opacity(0.08) : Color.clear)
                    .clipShape(ChamferedRectangle(cut: 3))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            Text(model.proverb.text)
                .font(.system(size: 8.5, weight: .medium))
                .italic()
                .foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(model.proverb.source)")
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(10)
        .frame(width: 168)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(AppPalette.raised)
    }

    private var resultPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(query.isEmpty ? "BEST MATCHES" : "SEARCH RESULTS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.text)
                Spacer()
                Text("\(visibleItems.count) ACTION\(visibleItems.count == 1 ? "" : "S")")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(AppPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

            if visibleItems.isEmpty {
                VStack(spacing: 9) {
                    UtilityGlyph(kind: .commandPalette, color: AppPalette.muted, size: 25)
                    Text("No matching action")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.text)
                    Text("Try a tool name, system, CL command, or workflow.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleItems) { item in
                                resultRow(item)
                                    .id(item.id)
                            }
                        }
                    }
                    .onChange(of: selection) {
                        if let selection {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(selection, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.panel)
    }

    private func resultRow(_ item: PaletteItem) -> some View {
        Button {
            selection = item.id
            activate(item)
        } label: {
            HStack(spacing: 11) {
                itemGlyph(item)
                    .frame(width: 30, height: 30)
                    .background(
                        selection == item.id ? AppPalette.instrument : AppPalette.raised,
                        in: ChamferedRectangle(cut: 4)
                    )
                    .overlay {
                        ChamferedRectangle(cut: 4)
                            .stroke(selection == item.id ? AppPalette.instrument : AppPalette.border, lineWidth: 0.8)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 10.5, weight: selection == item.id ? .semibold : .medium))
                        .foregroundStyle(item.available ? AppPalette.text : AppPalette.muted)
                    Text(item.detail)
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(item.badge)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeColor(item))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(badgeColor(item).opacity(0.08), in: ChamferedRectangle(cut: 2))
                    .overlay { ChamferedRectangle(cut: 2).stroke(badgeColor(item).opacity(0.45), lineWidth: 0.6) }

                if selection == item.id {
                    Text("↩")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.secondary)
                        .frame(width: 25, height: 24)
                        .background(AppPalette.panel, in: ChamferedRectangle(cut: 2))
                        .overlay { ChamferedRectangle(cut: 2).stroke(AppPalette.borderStrong, lineWidth: 0.7) }
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 59)
            .contentShape(Rectangle())
            .background(selection == item.id ? AppPalette.ibmBlue.opacity(0.075) : Color.clear)
            .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selection = item.id }
        }
        .accessibilityLabel("\(item.title). \(item.detail)")
        .accessibilityHint(item.available ? "Press Return to choose" : "Currently unavailable")
    }

    @ViewBuilder
    private func itemGlyph(_ item: PaletteItem) -> some View {
        let color = selection == item.id ? AppPalette.terminalGreen : badgeColor(item)
        switch item.id {
        case .tool(let tool):
            WorkbenchGlyph(tool: tool, color: color, size: 16)
        case .connect:
            UtilityGlyph(kind: .connectionTest, color: color, size: 16)
        case .newSession:
            UtilityGlyph(kind: .add, color: color, size: 15)
        case .screenHistory:
            UtilityGlyph(kind: .history, color: color, size: 16)
        case .copyScreen:
            UtilityGlyph(kind: .copy, color: color, size: 15)
        case .diagnostic:
            UtilityGlyph(kind: .stage, color: color, size: 16)
        case .sqlService:
            WorkbenchGlyph(tool: .sqlStudio, color: color, size: 16)
        case .assistVisibleScreen:
            UtilityGlyph(kind: .assistant, color: color, size: 16)
        case .proposalPatchStack:
            UtilityGlyph(kind: .patchStack, color: color, size: 16)
        case .aiSettings:
            UtilityGlyph(kind: .settings, color: color, size: 16)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
            Text(footerTarget)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)

            Spacer()

            Text("HOST ACTIONS STAGE ONLY")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(AppPalette.warning)

            Text("↑↓ navigate   ↩ choose   esc close")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(AppPalette.raised)
        .overlay(alignment: .top) { Rectangle().fill(AppPalette.border).frame(height: 1) }
    }

    private var connectionColor: Color {
        if case .connected = model.connectionState { return AppPalette.success }
        return AppPalette.muted
    }

    private var footerTarget: String {
        guard case .connected = model.connectionState else { return "OFFLINE · NO HOST FIELD" }
        let profile = model.selectedProfile?.name.uppercased() ?? "CONNECTED"
        if let field = model.screen.currentEditableFieldOrdinal {
            return "\(profile) · FIELD \(field)/\(model.screen.editableFieldCount)"
        }
        return "\(profile) · NO HOST FIELD"
    }

    private func badgeColor(_ item: PaletteItem) -> Color {
        switch item.scope {
        case .all, .navigate: AppPalette.ibmBlue
        case .sessions: AppPalette.success
        case .diagnostics: item.available ? AppPalette.warning : AppPalette.muted
        case .queries: AppPalette.terminalGreen
        case .assist: AppPalette.registrationBlue
        }
    }

    private func moveSelection(_ delta: Int) {
        let ids = visibleItems.map(\.id)
        guard !ids.isEmpty else {
            selection = nil
            return
        }
        guard let selection, let current = ids.firstIndex(of: selection) else {
            self.selection = delta < 0 ? ids.last : ids.first
            return
        }
        self.selection = ids[(current + delta + ids.count) % ids.count]
    }

    private func activateSelected() {
        guard let selection,
              let item = visibleItems.first(where: { $0.id == selection }) else { return }
        activate(item)
    }

    private func activate(_ item: PaletteItem) {
        switch item.id {
        case .tool(let tool):
            close()
            model.selectedTool = tool
        case .connect(let profileID):
            guard let profile = model.profiles.first(where: { $0.id == profileID }) else { return }
            close()
            model.connect(profile)
            model.selectedTool = .terminal
        case .newSession:
            close()
            model.presentNewSession()
        case .screenHistory:
            close()
            model.presentTerminalFlightRecorder()
        case .copyScreen:
            close()
            model.copyVisibleScreen()
        case .diagnostic(let commandID):
            guard let command = HostDiagnosticCommand.library.first(where: { $0.id == commandID }) else { return }
            let staging = model.hostCommandStagingStatus(for: command.command)
            guard staging.isReady else {
                model.showNotice(staging.message)
                return
            }
            close()
            model.stageReadOnlyHostCommand(command.command)
        case .sqlService(let serviceID):
            guard let service = IBMIServicesCatalog.queries.first(where: { $0.id == serviceID }) else { return }
            model.selectSQLService(service)
            model.selectedTool = .sqlStudio
            close()
        case .assistVisibleScreen:
            close()
            model.isAssistantVisible = true
            model.assistantInput = "Explain the visible IBM i screen, identify the current workflow, and suggest the safest next checks."
            model.previewCurrentAIContext()
        case .proposalPatchStack:
            close()
            model.openAIProposalPatchStack()
        case .aiSettings:
            close()
            model.isAISettingsPresented = true
        }
    }

    private func close() {
        model.isCommandPalettePresented = false
    }
}

private enum PaletteScope: String, CaseIterable, Hashable {
    case all
    case navigate
    case sessions
    case diagnostics
    case queries
    case assist

    var label: String {
        switch self {
        case .all: "All"
        case .navigate: "Navigate"
        case .sessions: "Sessions"
        case .diagnostics: "Diagnostics"
        case .queries: "Queries"
        case .assist: "Assist"
        }
    }
}

private enum PaletteActionID: Hashable {
    case tool(WorkbenchTool)
    case connect(UUID)
    case newSession
    case screenHistory
    case copyScreen
    case diagnostic(String)
    case sqlService(String)
    case assistVisibleScreen
    case proposalPatchStack
    case aiSettings
}

private struct PaletteItem: Identifiable {
    let id: PaletteActionID
    let scope: PaletteScope
    let title: String
    let detail: String
    let badge: String
    let available: Bool
}

private struct CommandPaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PaletteTextField {
        let field = PaletteTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14, weight: .regular)
        field.textColor = NSColor.labelColor
        field.placeholderString = "Search tools, systems, diagnostics, queries, and actions…"
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.onMoveUp = onMoveUp
        field.onMoveDown = onMoveDown
        field.onSubmit = onSubmit
        field.onEscape = onEscape
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: PaletteTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.onMoveUp = onMoveUp
        field.onMoveDown = onMoveDown
        field.onSubmit = onSubmit
        field.onEscape = onEscape
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandPaletteSearchField

        init(parent: CommandPaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

private final class PaletteTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            onMoveUp?()
        case 125:
            onMoveDown?()
        case 36, 76:
            onSubmit?()
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}
