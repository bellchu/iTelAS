import AppKit
import SwiftUI
import iTelASCore

struct SessionWorkspaceView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingPaste: TerminalPasteRequest?
    @State private var isKeyboardMapPresented = false
    @State private var isFunctionKeyLayoutPresented = false
    @State private var terminalSelection: TerminalSelection?

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader

            if !model.terminalSessions.isEmpty {
                sessionSwitcher
            }

            VStack(spacing: 11) {
                Panel {
                    VStack(spacing: 0) {
                        terminalToolbar
                        TerminalCanvasView(
                            screen: model.screen,
                            selection: terminalSelection,
                            onCellSelected: { row, column in
                                terminalSelection = nil
                                guard !model.screen.inputInhibited else {
                                    model.showNotice("Keyboard is inhibited while IBM i is processing.")
                                    return
                                }
                                if !model.screen.moveCursorToInputField(row: row, column: column) {
                                    model.showNotice(
                                        model.screen.currentFieldMovementIssue?.message
                                            ?? "That screen position is protected."
                                    )
                                }
                            },
                            onSelectionChanged: { terminalSelection = $0 },
                            onKeyDown: { handleKeyEvent($0) }
                        )
                        operatorInformationArea
                    }
                }

                functionKeyBar
            }
            .padding(15)
        }
        .background(AppPalette.window)
        .sheet(item: $pendingPaste) { request in
            TerminalPasteReviewView(
                request: request,
                ccsid: model.selectedProfile?.ccsid ?? 37,
                onCancel: { pendingPaste = nil },
                onPaste: {
                    _ = model.pasteTerminalText(request.text)
                    pendingPaste = nil
                }
            )
            .frame(width: 570, height: request.hidesContent ? 390 : 470)
        }
        .sheet(isPresented: $isKeyboardMapPresented) {
            TerminalKeyboardMapView(
                profileName: model.selectedProfile?.name,
                onConfigure: {
                    isKeyboardMapPresented = false
                    DispatchQueue.main.async {
                        isFunctionKeyLayoutPresented = true
                    }
                }
            )
                .frame(width: 760, height: 640)
        }
        .sheet(isPresented: $isFunctionKeyLayoutPresented) {
            if let profile = model.selectedProfile {
                TerminalFunctionKeyLayoutView(profile: profile)
            } else {
                ContentUnavailableView(
                    "No session profile",
                    systemImage: "keyboard",
                    description: Text("Choose or create an IBM i session profile before customizing its function keys.")
                )
                .frame(width: 520, height: 320)
            }
        }
        .onChange(of: model.screen) {
            terminalSelection = nil
        }
        .onChange(of: model.selectedTerminalSessionID) {
            terminalSelection = nil
        }
    }

    private var sessionSwitcher: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.terminalSessions) { session in
                        TerminalSessionTab(
                            session: session,
                            profile: model.profile(for: session),
                            selected: model.selectedTerminalSessionID == session.id,
                            select: { model.selectTerminalSession(session.id) },
                            close: { model.closeTerminalSession(session.id) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)

            Button {
                if let profile = model.selectedProfile {
                    model.openAdditionalSession(profile)
                } else {
                    model.presentNewSession()
                }
            } label: {
                UtilityGlyph(kind: .add, color: AppPalette.registrationBlue, size: 13)
            }
            .buttonStyle(PrecisionIconButtonStyle(size: 29))
            .help(model.selectedProfile.map { "Open another \($0.name) session" } ?? "Open a new session")

            sessionSummary
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var sessionSummary: some View {
        let connected = model.terminalSessions.filter {
            if case .connected = $0.connectionState { return true }
            return false
        }.count
        let recovering = model.terminalSessions.filter {
            switch $0.connectionState {
            case .connecting, .negotiating, .waiting:
                true
            case .connected, .disconnected, .failed:
                false
            }
        }.count
        let retained = model.terminalSessions.count - connected - recovering

        return HStack(spacing: 7) {
            UtilityGlyph(kind: .sessionPulse, color: AppPalette.registrationBlue, size: 14)
            Text("\(connected) LIVE · \(recovering) WAIT · \(retained) RETAINED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppPalette.secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(AppPalette.raised, in: ChamferedRectangle(cut: 3))
        .overlay {
            ChamferedRectangle(cut: 3).stroke(AppPalette.border, lineWidth: 0.8)
        }
        .accessibilityLabel("\(connected) live, \(recovering) reconnecting, \(retained) retained terminal sessions")
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.selectedProfile?.name.uppercased() ?? "NATIVE TERMINAL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AppPalette.ibmBlue)
                    if let profile = model.selectedProfile {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AppPalette.muted)
                        Text(profile.terminalModel.displayName)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
                Text(model.selectedProfile == nil ? "5250 session workspace" : "Interactive session")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.text)
            }

            Spacer()

            if let notice = model.transientNotice ?? model.protocolNotice {
                Label(notice, systemImage: "checkmark.circle")
                    .lineLimit(1)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppPalette.success)
            }

            switch model.connectionState {
            case .connected:
                Button("Disconnect") { model.disconnect() }
                    .buttonStyle(SecondaryButtonStyle())
            case .connecting, .negotiating, .waiting:
                Button {} label: {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text(connectionProgressLabel)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(true)
            case .disconnected, .failed:
                if let profile = model.selectedProfile {
                    Button {
                        model.connect(profile)
                    } label: {
                        HStack(spacing: 7) {
                            UtilityGlyph(kind: .connectionTest, color: .white, size: 13)
                            Text("Connect")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("New Session") { model.presentNewSession() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 62)
        .background(AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.border).frame(height: 1)
        }
    }

    private var terminalToolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionDot)
                .frame(width: 7, height: 7)
            Text(activeDeviceLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
            Text("·")
                .foregroundStyle(.white.opacity(0.35))
            Text(model.selectedProfile.map { "\($0.security.rawValue.uppercased()) · CCSID \($0.ccsid)" } ?? "NO HOST")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            terminalToolButton(.paste, help: "Review clipboard text before inserting (⌘V)") {
                requestPaste()
            }
            terminalToolButton(.keyboard, help: "5250 keyboard map and profile key layout") {
                isKeyboardMapPresented = true
            }
            terminalToolButton(
                .copy,
                help: terminalSelection == nil ? "Copy visible screen (⌘C)" : "Copy rectangular selection (⌘C)"
            ) {
                copySelectionOrScreen()
            }
            terminalToolButton(.capture, help: "Capture screen") {
                model.captureScreen()
            }
            terminalToolButton(.pdfDocument, help: "Export a redacted screen PDF") {
                model.exportScreenPDF()
            }
            terminalToolButton(.printSnapshot, help: "Print a redacted screen snapshot") {
                model.printScreenSnapshot()
            }
            terminalToolButton(.history, help: "Session Flight Recorder") {
                model.presentTerminalFlightRecorder()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(AppPalette.terminalRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func terminalToolButton(_ kind: UtilityGlyphKind, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            UtilityGlyph(kind: kind, color: .white.opacity(0.68), size: 13)
        }
        .buttonStyle(PrecisionIconButtonStyle(size: 26))
        .help(help)
    }

    private var operatorInformationArea: some View {
        HStack(spacing: 14) {
            Text(model.screen.inputInhibited ? "X SYSTEM" : "READY")
                .foregroundStyle(model.screen.inputInhibited ? AppPalette.warning : AppPalette.terminalGreen)
            Text(model.isTerminalInsertMode ? "INS" : "OVR")
                .foregroundStyle(model.isTerminalInsertMode ? AppPalette.terminalGreen : .white.opacity(0.52))
            if let ordinal = model.screen.currentEditableFieldOrdinal {
                Text("FIELD \(ordinal)/\(model.screen.editableFieldCount)")
            }
            if let contract = model.screen.currentEditableFieldContract {
                Text(contract)
                    .lineLimit(1)
                    .foregroundStyle(AppPalette.terminal(.turquoise))
            }
            if let selection = terminalSelection {
                Text("SELECT \(selection.selectedRowCount)×\(selection.selectedColumnCount)")
                    .foregroundStyle(AppPalette.terminal(.turquoise))
            }
            Spacer()
            Text(String(format: "R%02d C%03d", model.screen.cursor.row + 1, model.screen.cursor.column + 1))
            Text("\(model.screen.rows)×\(model.screen.columns)")
            Text("CCSID \(model.selectedProfile?.ccsid ?? 37)")
            Text(model.screen.readMode.label)
                .foregroundStyle(model.screen.readMode == .modifiedFieldsAlternate
                    ? AppPalette.terminal(.turquoise)
                    : .white.opacity(0.52))
            if let startup = model.startupResponse {
                Text(startup.responseCode)
                    .foregroundStyle(startup.disposition == .failure ? AppPalette.danger : AppPalette.terminalGreen)
            }
            if model.screen.messageWaiting {
                Label("MSG", systemImage: "envelope.badge")
                    .foregroundStyle(AppPalette.warning)
            }
        }
        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.52))
        .padding(.horizontal, 11)
        .frame(height: 27)
        .background(AppPalette.terminalRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var functionKeyBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if pinnedFunctionKeys.isEmpty {
                        Text("No function keys pinned · use the keyboard map to configure this profile")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    } else {
                        ForEach(pinnedFunctionKeys) { binding in
                            functionButton(binding)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button { model.sendAID(TN5250AID.rollDown.rawValue) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Page Up · Roll Down")
            Button { model.sendAID(TN5250AID.rollUp.rawValue) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Page Down · Roll Up")
        }
        .frame(height: 38)
    }

    private var pinnedFunctionKeys: [TerminalFunctionKeyBinding] {
        model.activeTerminalFunctionKeyBindings.filter(\.isPinned)
    }

    private func functionButton(_ binding: TerminalFunctionKeyBinding) -> some View {
        Button {
            model.sendFunctionKey(slot: binding.slot)
        } label: {
            HStack(spacing: 5) {
                Text(binding.physicalKeyLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                Text(binding.displayLabel)
                if !binding.isIdentityRoute {
                    Text("→\(binding.hostActionLabel)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .help("\(binding.physicalKeyLabel) sends host \(binding.hostActionLabel) · \(binding.displayLabel)")
    }

    private var connectionDot: Color {
        switch model.connectionState {
        case .connected: AppPalette.terminalGreen
        case .connecting, .negotiating, .waiting: AppPalette.warning
        case .failed: AppPalette.danger
        case .disconnected: AppPalette.muted
        }
    }

    private var activeDeviceLabel: String {
        model.startupResponse?.deviceName.nonEmpty
            ?? model.selectedProfile?.deviceName.nonEmpty
            ?? (model.selectedProfile == nil ? "LOCAL PREVIEW" : "AUTO DEVICE")
    }

    private var connectionProgressLabel: String {
        switch model.connectionState {
        case .connecting: "Opening transport…"
        case .negotiating: "Negotiating 5250…"
        case .waiting(let detail): detail.nonEmpty ?? "Waiting for IBM i…"
        case .connected, .disconnected, .failed: "Connect"
        }
    }

    private func requestPaste() {
        guard case .connected = model.connectionState else {
            model.showNotice("Connect an IBM i session before pasting into host fields.")
            return
        }
        guard let text = model.terminalClipboardText(), !text.isEmpty else {
            model.showNotice("The clipboard does not contain text.")
            return
        }
        guard !model.screen.inputInhibited else {
            model.showNotice("Keyboard is inhibited; clipboard text was not read into the terminal.")
            return
        }
        _ = model.screen.ensureCursorInInputField()
        pendingPaste = TerminalPasteRequest(
            text: text,
            hidesContent: model.screen.isCurrentInputFieldNonDisplay
        )
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.characters ?? ""
        let lowerCharacters = (event.charactersIgnoringModifiers ?? characters).lowercased()

        if modifiers.contains(.command) {
            if lowerCharacters == "v" {
                requestPaste()
                return true
            }
            if lowerCharacters == "c" {
                copySelectionOrScreen()
                return true
            }
            return false
        }

        guard let scalar = (event.charactersIgnoringModifiers ?? characters).unicodeScalars.first?.value else { return false }

        if (MacTerminalKey.f1...MacTerminalKey.f24).contains(scalar) {
            var number = Int(scalar - MacTerminalKey.f1) + 1
            if number <= 12, modifiers.contains(.shift) { number += 12 }
            model.sendFunctionKey(slot: number)
            return true
        }

        if modifiers.contains(.control) {
            switch lowerCharacters {
            case "e":
                return model.screen.eraseAllInputFields()
            case "h":
                model.sendAID(TN5250AID.help.rawValue)
                return true
            case "r":
                model.showNotice(model.screen.inputInhibited
                    ? "IBM i still owns the keyboard; wait for the next host screen."
                    : "No local 5250 keyboard error is active.")
                return true
            default:
                return false
            }
        }

        if modifiers.contains(.option), lowerCharacters == "i" {
            model.toggleTerminalInsertMode()
            return true
        }

        switch event.keyCode {
        case 36, 76: // Return and keypad Enter.
            if modifiers.contains(.shift) || event.keyCode == 76 {
                _ = model.performTerminalFieldExit()
                return true
            }
            model.sendAID(TN5250AID.enter.rawValue)
            return true
        case 48: // Tab.
            return consumeMovement(modifiers.contains(.shift)
                ? model.screen.moveToPreviousInputField()
                : model.screen.moveToNextInputField())
        case 51: // Backspace / Delete.
            return model.screen.deleteBackward()
        case 53: // Escape = 5250 Clear.
            model.sendAID(TN5250AID.clear.rawValue)
            return true
        case 126: // Up.
            return consumeMovement(model.screen.moveCursorVertically(-1))
        case 125: // Down.
            return consumeMovement(model.screen.moveCursorVertically(1))
        case 123: // Left.
            return consumeMovement(model.screen.moveCursorLeft())
        case 124: // Right.
            return consumeMovement(model.screen.moveCursorRight())
        case 115: // Home.
            return consumeMovement(model.screen.moveToStartOfInputField())
        case 119: // End = Erase EOF; Option-End = Erase Input.
            if modifiers.contains(.option) {
                return model.screen.eraseAllInputFields()
            }
            return model.screen.eraseToEndOfInputField()
        case 114: // Insert / Help position on extended keyboards.
            if modifiers.contains(.shift) {
                _ = model.duplicateTerminalField()
                return true
            }
            model.toggleTerminalInsertMode()
            return true
        case 69: // Keypad Plus = Field +.
            _ = model.performTerminalFieldExit(.positive)
            return true
        case 78: // Keypad Minus = Field -.
            _ = model.performTerminalFieldExit(.negative)
            return true
        case 117: // Forward Delete.
            return model.screen.deleteCharacter()
        case 116: // Page Up = Roll Down.
            model.sendAID(TN5250AID.rollDown.rawValue)
            return true
        case 121: // Page Down = Roll Up.
            model.sendAID(TN5250AID.rollUp.rawValue)
            return true
        default:
            break
        }

        if scalar == MacTerminalKey.help {
            model.sendAID(TN5250AID.help.rawValue)
            return true
        }
        if scalar == MacTerminalKey.printScreen {
            model.sendAID(TN5250AID.print.rawValue)
            return true
        }

        guard !modifiers.contains(.option),
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        var insertedAny = false
        for character in characters {
            insertedAny = model.insertTerminalCharacter(character) || insertedAny
        }
        return insertedAny
    }

    private func consumeMovement(_ succeeded: Bool) -> Bool {
        if succeeded { return true }
        guard let issue = model.screen.currentFieldMovementIssue else { return false }
        model.showNotice(issue.message)
        return true
    }

    private func copySelectionOrScreen() {
        if let terminalSelection {
            model.copyTerminalSelection(terminalSelection)
        } else {
            model.copyVisibleScreen()
        }
    }
}

private struct TerminalSessionTab: View {
    let session: TerminalSessionState
    let profile: SessionProfile?
    let selected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: select) {
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(selected ? AppPalette.registrationBlue : Color.clear)
                        .frame(width: 2, height: 21)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile?.name.uppercased() ?? "REMOVED PROFILE")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AppPalette.text)
                            .lineLimit(1)
                        Text(session.connectionLabel)
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: close) {
                UtilityGlyph(kind: .closeSession, color: AppPalette.muted, size: 12)
                    .frame(width: 19, height: 19)
            }
            .buttonStyle(.plain)
            .help("Close this terminal session")
            .accessibilityLabel("Close \(profile?.name ?? "terminal") session")
        }
        .padding(.horizontal, 8)
        .frame(width: 218, height: 36)
        .background(selected ? AppPalette.ibmBlue.opacity(0.09) : AppPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(selected ? AppPalette.registrationBlue : AppPalette.border.opacity(0.45))
                .frame(height: selected ? 2 : 1)
        }
        .clipShape(ChamferedRectangle(cut: 3))
        .accessibilityElement(children: .contain)
    }

    private var statusColor: Color {
        switch session.connectionState {
        case .connected: AppPalette.success
        case .connecting, .negotiating, .waiting: AppPalette.warning
        case .failed: AppPalette.danger
        case .disconnected: AppPalette.muted
        }
    }
}

struct TerminalCanvasView: View {
    let screen: TerminalScreen
    var selection: TerminalSelection?
    var onCellSelected: ((Int, Int) -> Void)?
    var onSelectionChanged: ((TerminalSelection?) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    init(
        screen: TerminalScreen,
        selection: TerminalSelection? = nil,
        onCellSelected: ((Int, Int) -> Void)? = nil,
        onSelectionChanged: ((TerminalSelection?) -> Void)? = nil,
        onKeyDown: ((NSEvent) -> Bool)? = nil
    ) {
        self.screen = screen
        self.selection = selection
        self.onCellSelected = onCellSelected
        self.onSelectionChanged = onSelectionChanged
        self.onKeyDown = onKeyDown
    }

    var body: some View {
        GeometryReader { _ in
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let blinkVisible = Int(
                    timeline.date.timeIntervalSinceReferenceDate * 2
                ).isMultiple(of: 2)
                Canvas(opaque: true, colorMode: .linear) { context, size in
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(AppPalette.terminal)
                    )
                    let cellWidth = size.width / CGFloat(screen.columns)
                    let cellHeight = size.height / CGFloat(screen.rows)
                    let fontSize = min(cellHeight * 0.7, cellWidth * 1.48)

                    if let selection {
                        let firstRow = max(0, selection.minimumRow)
                        let lastRow = min(screen.rows - 1, selection.maximumRow)
                        let firstColumn = max(0, selection.minimumColumn)
                        let lastColumn = min(screen.columns - 1, selection.maximumColumn)
                        if firstRow <= lastRow, firstColumn <= lastColumn {
                            let selectionRect = CGRect(
                                x: CGFloat(firstColumn) * cellWidth,
                                y: CGFloat(firstRow) * cellHeight,
                                width: CGFloat(lastColumn - firstColumn + 1) * cellWidth,
                                height: CGFloat(lastRow - firstRow + 1) * cellHeight
                            )
                            context.fill(
                                Path(selectionRect),
                                with: .color(AppPalette.ibmBlue.opacity(0.24))
                            )
                            context.stroke(
                                Path(selectionRect.insetBy(dx: 0.5, dy: 0.5)),
                                with: .color(AppPalette.terminal(.turquoise)),
                                lineWidth: 1
                            )
                        }
                    }

                    for row in 0..<screen.rows {
                        var column = 0
                        while column < screen.columns {
                            let start = row * screen.columns + column
                            let attributes = screen.cells[start].attributes
                            var endColumn = column + 1
                            while endColumn < screen.columns,
                                  screen.cells[row * screen.columns + endColumn].attributes == attributes {
                                endColumn += 1
                            }
                            let rect = CGRect(
                                x: CGFloat(column) * cellWidth,
                                y: CGFloat(row) * cellHeight,
                                width: CGFloat(endColumn - column) * cellWidth,
                                height: cellHeight
                            )
                            if attributes.reverse {
                                context.fill(
                                    Path(rect),
                                    with: .color(
                                        AppPalette.terminal(attributes.foreground).opacity(0.9)
                                    )
                                )
                            }
                            for glyphColumn in column..<endColumn {
                                let cell = screen.cells[row * screen.columns + glyphColumn]
                                let character = cell.attributes.nonDisplay
                                    || (attributes.blink && !blinkVisible)
                                    ? " "
                                    : String(cell.character)
                                guard character != " " || attributes.underline else { continue }
                                let cellRect = CGRect(
                                    x: CGFloat(glyphColumn) * cellWidth,
                                    y: CGFloat(row) * cellHeight,
                                    width: cellWidth,
                                    height: cellHeight
                                )
                                var glyph = Text(character)
                                    .font(.system(
                                        size: fontSize,
                                        weight: attributes.highIntensity ? .medium : .regular,
                                        design: .monospaced
                                    ))
                                    .foregroundStyle(
                                        attributes.reverse
                                            ? AppPalette.terminal
                                            : AppPalette.terminal(attributes.foreground)
                                    )
                                if attributes.underline { glyph = glyph.underline() }
                                context.draw(
                                    glyph,
                                    at: CGPoint(x: cellRect.midX, y: cellRect.minY),
                                    anchor: .top
                                )
                            }
                            if attributes.columnSeparator {
                                var separators = Path()
                                for boundary in column...endColumn {
                                    let x = CGFloat(boundary) * cellWidth
                                    separators.move(
                                        to: CGPoint(x: x, y: rect.minY + cellHeight * 0.2)
                                    )
                                    separators.addLine(
                                        to: CGPoint(x: x, y: rect.maxY - cellHeight * 0.2)
                                    )
                                }
                                context.stroke(
                                    separators,
                                    with: .color(
                                        AppPalette.terminal(attributes.foreground).opacity(0.36)
                                    ),
                                    lineWidth: 0.65
                                )
                            }
                            column = endColumn
                        }
                    }

                    if screen.cursor.isVisible,
                       (!screen.cursor.isBlinking || blinkVisible),
                       (0..<screen.rows).contains(screen.cursor.row),
                       (0..<screen.columns).contains(screen.cursor.column) {
                        let cursor = CGRect(
                            x: CGFloat(screen.cursor.column) * cellWidth,
                            y: CGFloat(screen.cursor.row) * cellHeight,
                            width: max(1, cellWidth),
                            height: cellHeight
                        ).insetBy(dx: 0.5, dy: 0.5)
                        context.stroke(
                            Path(cursor),
                            with: .color(AppPalette.terminalGreen),
                            lineWidth: 1.2
                        )
                    }
                }
            }
            .padding(18)
            .background(AppPalette.terminal)
            .overlay {
                TerminalInputCaptureView(
                    rows: screen.rows,
                    columns: screen.columns,
                    inset: 18,
                    accessibilityText: screen.visibleText(),
                    onCellSelected: onCellSelected,
                    onSelectionChanged: onSelectionChanged,
                    onKeyDown: onKeyDown
                )
            }
        }
        .accessibilityLabel("5250 terminal screen")
        .accessibilityValue(screen.visibleText())
    }
}

private enum MacTerminalKey {
    static let f1: UInt32 = 0xF704
    static let f24: UInt32 = 0xF71B
    static let printScreen: UInt32 = 0xF72E
    static let help: UInt32 = 0xF746
}

private struct TerminalInputCaptureView: NSViewRepresentable {
    let rows: Int
    let columns: Int
    let inset: CGFloat
    let accessibilityText: String
    let onCellSelected: ((Int, Int) -> Void)?
    let onSelectionChanged: ((TerminalSelection?) -> Void)?
    let onKeyDown: ((NSEvent) -> Bool)?

    func makeNSView(context: Context) -> TerminalInputNSView {
        let view = TerminalInputNSView()
        view.rows = rows
        view.columns = columns
        view.contentInset = inset
        view.updateAccessibility(text: accessibilityText)
        view.onCellSelected = onCellSelected
        view.onSelectionChanged = onSelectionChanged
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ view: TerminalInputNSView, context: Context) {
        view.rows = rows
        view.columns = columns
        view.contentInset = inset
        view.updateAccessibility(text: accessibilityText)
        view.onCellSelected = onCellSelected
        view.onSelectionChanged = onSelectionChanged
        view.onKeyDown = onKeyDown
    }
}

private final class TerminalInputNSView: NSView {
    var rows = 24
    var columns = 80
    var contentInset: CGFloat = 18
    var onCellSelected: ((Int, Int) -> Void)?
    var onSelectionChanged: ((TerminalSelection?) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    private var selectionAnchor: TerminalSelectionPoint?
    private var lastSelectionExtent: TerminalSelectionPoint?
    private var didDragSelection = false

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    func updateAccessibility(text: String) {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("5250 terminal screen")
        setAccessibilityValue(text)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let point = terminalPoint(for: event) else { return }
        selectionAnchor = point
        lastSelectionExtent = point
        didDragSelection = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let selectionAnchor, let extent = terminalPoint(for: event) else { return }
        lastSelectionExtent = extent
        if extent != selectionAnchor { didDragSelection = true }
        guard didDragSelection else { return }
        onSelectionChanged?(TerminalSelection(anchor: selectionAnchor, extent: extent))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            selectionAnchor = nil
            lastSelectionExtent = nil
            didDragSelection = false
        }
        guard let selectionAnchor else { return }
        let extent = terminalPoint(for: event) ?? lastSelectionExtent ?? selectionAnchor
        if didDragSelection {
            onSelectionChanged?(TerminalSelection(anchor: selectionAnchor, extent: extent))
        } else {
            onSelectionChanged?(nil)
            onCellSelected?(extent.row, extent.column)
        }
    }

    private func terminalPoint(for event: NSEvent) -> TerminalSelectionPoint? {
        let point = convert(event.locationInWindow, from: nil)
        let width = bounds.width - contentInset * 2
        let height = bounds.height - contentInset * 2
        let x = point.x - contentInset
        let y = bounds.height - point.y - contentInset
        guard width > 0, height > 0, x >= 0, y >= 0, x < width, y < height else { return nil }
        let column = min(columns - 1, Int(x / (width / CGFloat(columns))))
        let row = min(rows - 1, Int(y / (height / CGFloat(rows))))
        return TerminalSelectionPoint(row: row, column: column)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

}

private struct TerminalPasteRequest: Identifiable {
    let id = UUID()
    let text: String
    let hidesContent: Bool

    var lineCount: Int {
        max(1, text.split(whereSeparator: \.isNewline).count)
    }
}

private struct TerminalPasteReviewView: View {
    let request: TerminalPasteRequest
    let ccsid: Int
    let onCancel: () -> Void
    let onPaste: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                UtilityGlyph(kind: .paste, color: AppPalette.ibmBlue, size: 24)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.ibmBlue.opacity(0.08), in: ChamferedRectangle(cut: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text("REVIEW 5250 PASTE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Insert clipboard text into host fields")
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Text("CCSID \(ccsid)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }

            HStack(spacing: 10) {
                pasteMetric("CHARACTERS", "\(request.text.count)")
                pasteMetric("LINES", "\(request.lineCount)")
                pasteMetric("TARGET", request.hidesContent ? "NON-DISPLAY" : "VISIBLE")
            }

            if request.hidesContent {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(AppPalette.warning)
                    Text("Clipboard content is hidden because the active 5250 field is non-display.")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.warning.opacity(0.08), in: ChamferedRectangle(cut: 5))
                .overlay { ChamferedRectangle(cut: 5).stroke(AppPalette.warning.opacity(0.3), lineWidth: 1) }
            } else {
                ScrollView {
                    Text(request.text.prefix(2_000))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppPalette.text)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .privacySensitive()
                        .padding(14)
                }
                .background(AppPalette.raised, in: ChamferedRectangle(cut: 5))
                .overlay { ChamferedRectangle(cut: 5).stroke(AppPalette.borderStrong, lineWidth: 1) }
            }

            Text("Tabs and line breaks advance to the next editable field. Protected fields are never modified; overflowing, numeric-invalid, control, or unrepresentable characters are skipped and reported.")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.secondary)
                .lineSpacing(3)

            Spacer(minLength: 0)
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(action: onPaste) {
                    HStack(spacing: 7) {
                        UtilityGlyph(kind: .paste, color: .white, size: 13)
                        Text("Insert into 5250 fields")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .background(AppPalette.window)
    }

    private func pasteMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.text)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(AppPalette.panel, in: ChamferedRectangle(cut: 4))
        .overlay { ChamferedRectangle(cut: 4).stroke(AppPalette.border, lineWidth: 1) }
    }
}

private struct TerminalKeyboardMapView: View {
    let profileName: String?
    let onConfigure: () -> Void

    private let groups: [(String, [(String, String)])] = [
        ("HOST KEYS", [
            ("Return", "Enter"), ("F1–F12", "F1–F12"), ("⇧F1–F12", "F13–F24"),
            ("Page Up", "Roll Down"), ("Page Down", "Roll Up"), ("Esc", "Clear")
        ]),
        ("FIELD EDITING", [
            ("Tab / ⇧Tab", "Next / previous field"), ("⇧Return / keypad Enter", "Field Exit"),
            ("Home", "Start of field"), ("End", "Erase EOF"), ("⌥End / ⌃E", "Erase all input"),
            ("keypad + / -", "Field Plus / Field Minus"), ("⇧Insert", "Dup"),
            ("⌥I / Insert", "Insert / overwrite"), ("Delete", "Backspace"), ("Forward Delete", "Delete character")
        ]),
        ("NAVIGATION & CLIPBOARD", [
            ("Arrow keys", "Editable-field cursor"), ("Mouse click", "Position in editable field"),
            ("Mouse drag", "Rectangular text selection"), ("⌘C", "Copy selection or visible screen"),
            ("⌘V", "Review, then paste"), ("⌃R", "Reset status check"),
            ("⌃H / Help key", "5250 Help"), ("Print Screen", "Host Print")
        ])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                UtilityGlyph(kind: .keyboard, color: AppPalette.ibmBlue, size: 25)
                    .frame(width: 43, height: 43)
                    .background(AppPalette.ibmBlue.opacity(0.08), in: ChamferedRectangle(cut: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text("MAC 5250 KEYBOARD")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(AppPalette.ibmBlue)
                    Text("Operator mapping")
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Text("IBM i · DISPLAY SESSION")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.0)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.7)
                                .foregroundStyle(AppPalette.text)
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                .background(AppPalette.raised)
                            ForEach(Array(group.1.enumerated()), id: \.offset) { index, binding in
                                HStack(spacing: 14) {
                                    Text(binding.0)
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AppPalette.ibmBlue)
                                        .frame(width: 190, alignment: .leading)
                                    Text(binding.1)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(AppPalette.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 34)
                                if index < group.1.count - 1 {
                                    Rectangle().fill(AppPalette.border).frame(height: 1).padding(.leading, 14)
                                }
                            }
                        }
                        .background(AppPalette.panel, in: ChamferedRectangle(cut: 5))
                        .clipShape(ChamferedRectangle(cut: 5))
                        .overlay { ChamferedRectangle(cut: 5).stroke(AppPalette.borderStrong, lineWidth: 1) }
                    }
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(AppPalette.ibmBlue)
                Text("The mapping follows common 5250 workstation behavior. Profile-scoped routing controls the local physical key and dock; host-specific DSPKBDMAP settings may still change function-key meaning.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppPalette.secondary)
                Spacer(minLength: 8)
                Button("Customize profile") {
                    onConfigure()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(profileName == nil)
                .help(profileName.map { "Customize the 5250 function-key layout for \($0)" }
                    ?? "Choose a session profile before customizing function keys")
            }
            .padding(12)
            .background(AppPalette.ibmBlue.opacity(0.06), in: ChamferedRectangle(cut: 4))
        }
        .padding(24)
        .background(AppPalette.window)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
