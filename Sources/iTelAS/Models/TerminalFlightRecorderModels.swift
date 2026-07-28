import Foundation
import iTelASCore

struct TerminalMacroRunState: Equatable {
    let macroID: UUID
    let macroFingerprint: String
    var nextStepIndex: Int
    var completedStepIDs: [UUID]

    init(macro: ReviewedTerminalMacro) {
        macroID = macro.id
        macroFingerprint = macro.contentFingerprint
        nextStepIndex = 0
        completedStepIDs = []
    }
}

enum TerminalMacroEditorActionKind: String, CaseIterable, Identifiable {
    case matchFrame
    case stageReadOnlyCommand
    case fieldExit
    case sendAID
    case bookmark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .matchFrame: "MATCH SCREEN"
        case .stageReadOnlyCommand: "STAGE READ-ONLY COMMAND"
        case .fieldExit: "FIELD EXIT"
        case .sendAID: "SEND HOST KEY"
        case .bookmark: "BOOKMARK EVIDENCE"
        }
    }
}

struct TerminalMacroEditorStepDraft: Identifiable, Equatable {
    var id: UUID
    var name: String
    var kind: TerminalMacroEditorActionKind
    var command: String
    var frameFingerprint: String
    var fieldExit: TerminalMacroFieldExit
    var aidCode: UInt8

    init(
        id: UUID = UUID(),
        name: String = "Capture result evidence",
        kind: TerminalMacroEditorActionKind = .bookmark,
        command: String = "",
        frameFingerprint: String = "",
        fieldExit: TerminalMacroFieldExit = .neutral,
        aidCode: UInt8 = TN5250AID.enter.rawValue
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.command = command
        self.frameFingerprint = frameFingerprint
        self.fieldExit = fieldExit
        self.aidCode = aidCode
    }

    init(step: ReviewedTerminalMacroStep) {
        id = step.id
        name = step.name
        command = ""
        frameFingerprint = ""
        fieldExit = .neutral
        aidCode = TN5250AID.enter.rawValue
        switch step.action {
        case .matchFrame(let fingerprint):
            kind = .matchFrame
            frameFingerprint = fingerprint
        case .stageReadOnlyCommand(let command):
            kind = .stageReadOnlyCommand
            self.command = command
        case .fieldExit(let fieldExit):
            kind = .fieldExit
            self.fieldExit = fieldExit
        case .sendAID(let code):
            kind = .sendAID
            aidCode = code
        case .bookmark:
            kind = .bookmark
        }
    }

    func resolvedStep() -> ReviewedTerminalMacroStep {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action: TerminalMacroAction = switch kind {
        case .matchFrame:
            .matchFrame(fingerprint: frameFingerprint)
        case .stageReadOnlyCommand:
            .stageReadOnlyCommand(command.trimmingCharacters(in: .whitespacesAndNewlines))
        case .fieldExit:
            .fieldExit(fieldExit)
        case .sendAID:
            .sendAID(aidCode)
        case .bookmark:
            .bookmark
        }
        return ReviewedTerminalMacroStep(
            id: id,
            name: normalizedName.isEmpty ? action.title : normalizedName,
            action: action
        )
    }
}

struct TerminalMacroEditorDraft: Identifiable, Equatable {
    var id: UUID
    var name: String
    var targetProfileID: UUID?
    var steps: [TerminalMacroEditorStepDraft]

    init(
        id: UUID = UUID(),
        name: String = "New reviewed macro",
        targetProfileID: UUID? = nil,
        steps: [TerminalMacroEditorStepDraft] = [TerminalMacroEditorStepDraft()]
    ) {
        self.id = id
        self.name = name
        self.targetProfileID = targetProfileID
        self.steps = steps
    }

    init(macro: ReviewedTerminalMacro) {
        id = macro.id
        name = macro.name
        targetProfileID = macro.targetProfileID
        steps = macro.steps.map(TerminalMacroEditorStepDraft.init(step:))
    }

    func resolvedMacro() -> ReviewedTerminalMacro {
        ReviewedTerminalMacro(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            targetProfileID: targetProfileID,
            steps: steps.map { $0.resolvedStep() }
        )
    }
}

enum TerminalFlightRecorderSamples {
    static let profileID = UUID(uuidString: "4B51B7B8-14CB-4F69-89E4-0951237F1850")!
    static let selectedFrameID = UUID(uuidString: "9520D624-2C71-4DA1-8767-E3BB2E9C3006")!
    static let selectedMacroID = UUID(uuidString: "6DA97553-9846-4318-80FE-1993F0390419")!

    static func makeArchive() -> TerminalFlightRecorderArchive {
        let base = Date(timeIntervalSince1970: 1_785_178_181)
        let specifications: [(UUID, TimeInterval, String, String, String)] = [
            (
                UUID(uuidString: "B298B504-59BD-41B2-A20B-F276E9921001")!,
                0,
                "SESSION OPENED",
                "Local recorder armed after sign-on",
                "No automatic host action"
            ),
            (
                UUID(uuidString: "4C221A97-02D5-486C-A87B-9B5C1E631002")!,
                16,
                "SIGN ON COMPLETE",
                "Device QPADEV0041 allocated",
                "Password field was cleared"
            ),
            (
                UUID(uuidString: "8DDE2E42-B80D-44F6-B39C-EDE59E841003")!,
                37,
                "COMMAND ENTRY",
                "Read-only command entry",
                "Command field was cleared"
            ),
            (
                UUID(uuidString: "2FEB0C33-80C2-42A7-BB7E-AF8405401004")!,
                121,
                "WORK WITH ACTIVE JOBS",
                "QBATCH · 24 jobs",
                "Candidate inventory only"
            ),
            (
                UUID(uuidString: "0F6D43A1-9464-40CC-96BA-281568F61005")!,
                133,
                "JOB DETAIL · ORDERSRV",
                "744921/QUSER/ORDERSRV · MSGW",
                "One selection field cleared"
            ),
            (
                selectedFrameID,
                147,
                "DISPLAY JOB LOG",
                "CPF9898 · order 48371 held",
                "One selection field cleared"
            )
        ]
        let frames = specifications.map { id, offset, title, detail, note in
            TerminalEvidenceFrame(
                id: id,
                capturedAt: base.addingTimeInterval(offset),
                profileID: profileID,
                profileName: "DEV ORION",
                deviceName: "QPADEV0041",
                screen: makeScreen(title: title, detail: detail, note: note)
            )
        }

        var macro = ReviewedTerminalMacro(
            id: selectedMacroID,
            name: "Inspect QBATCH jobs",
            targetProfileID: profileID,
            steps: [
                ReviewedTerminalMacroStep(
                    name: "Match Command Entry",
                    action: .matchFrame(fingerprint: frames[2].screenFingerprint)
                ),
                ReviewedTerminalMacroStep(
                    name: "Stage WRKACTJOB",
                    action: .stageReadOnlyCommand("WRKACTJOB SBS(QBATCH)")
                ),
                ReviewedTerminalMacroStep(
                    name: "Send Enter",
                    action: .sendAID(TN5250AID.enter.rawValue)
                ),
                ReviewedTerminalMacroStep(
                    name: "Match active jobs",
                    action: .matchFrame(fingerprint: frames[3].screenFingerprint)
                ),
                ReviewedTerminalMacroStep(
                    name: "Capture result evidence",
                    action: .bookmark
                )
            ]
        )
        try? macro.attestReview(by: "LOCAL OPERATOR", at: base.addingTimeInterval(180))

        let receipts = macro.steps.prefix(2).enumerated().map { index, step in
            TerminalMacroStepReceipt(
                recordedAt: base.addingTimeInterval(190 + Double(index)),
                macroID: macro.id,
                macroFingerprint: macro.contentFingerprint,
                stepID: step.id,
                stepOrdinal: index + 1,
                actionLabel: step.action.kindLabel,
                expectedScreenFingerprint: index == 0 ? frames[2].screenFingerprint : nil,
                observedScreenFingerprint: frames[2].screenFingerprint,
                outcome: .passed,
                detail: index == 0 ? "Exact redacted screen matched." : "Read-only command staged without submission."
            )
        }

        return TerminalFlightRecorderArchive(
            policy: TerminalHistoryPolicy(retention: .thirtyDays),
            frames: frames,
            macros: [macro],
            receipts: receipts,
            updatedAt: base.addingTimeInterval(192)
        )
    }

    private static func makeScreen(title: String, detail: String, note: String) -> TerminalScreen {
        var screen = TerminalScreen(rows: 24, columns: 80)
        screen.inputInhibited = false
        screen.messageWaiting = title.contains("JOB") || title.contains("LOG")
        let heading = TerminalAttributes(foreground: .turquoise, highIntensity: true, protected: true)
        let body = TerminalAttributes(foreground: .green, protected: true)
        let data = TerminalAttributes(foreground: .white, protected: true)
        let warning = TerminalAttributes(foreground: .yellow, protected: true)
        let input = TerminalAttributes(foreground: .green, protected: false)
        screen.write(title, row: 1, column: max(1, (80 - title.count) / 2), attributes: heading)
        screen.write("Job: 744921/QUSER/ORDERSRV", row: 3, column: 3, attributes: data)
        screen.write("System: DEVORION", row: 3, column: 56, attributes: data)
        screen.write(detail, row: 7, column: 5, attributes: title.contains("LOG") ? warning : body)
        screen.write(note, row: 10, column: 5, attributes: data)
        screen.write("Selection:", row: 18, column: 5, attributes: body)
        screen.write("SHOULD NOT PERSIST", row: 18, column: 17, attributes: input)
        screen.fields.append(TerminalField(start: 18 * 80 + 17, length: 24, isProtected: false))
        screen.write("F3=Exit   F5=Refresh   F12=Cancel", row: 22, column: 3, attributes: body)
        return screen
    }
}
