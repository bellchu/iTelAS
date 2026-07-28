import Foundation

private func terminalRecorderDate(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
}

public struct TerminalFlightRecorderLimits: Equatable, Sendable {
    public var maximumFrames: Int
    public var maximumMacros: Int
    public var maximumStepsPerMacro: Int
    public var maximumReceipts: Int
    public var maximumArchiveUTF8Bytes: Int
    public var maximumCommandUTF8Bytes: Int

    public init(
        maximumFrames: Int = 250,
        maximumMacros: Int = 40,
        maximumStepsPerMacro: Int = 32,
        maximumReceipts: Int = 500,
        maximumArchiveUTF8Bytes: Int = 12 * 1_024 * 1_024,
        maximumCommandUTF8Bytes: Int = 1_024
    ) {
        self.maximumFrames = maximumFrames
        self.maximumMacros = maximumMacros
        self.maximumStepsPerMacro = maximumStepsPerMacro
        self.maximumReceipts = maximumReceipts
        self.maximumArchiveUTF8Bytes = maximumArchiveUTF8Bytes
        self.maximumCommandUTF8Bytes = maximumCommandUTF8Bytes
    }

    public static let standard = TerminalFlightRecorderLimits()
}

public enum TerminalFlightRecorderError: Error, LocalizedError, Equatable {
    case invalidDimensions
    case invalidCellCount
    case invalidCell
    case unredactedCell
    case fingerprintMismatch
    case invalidRetention
    case tooManyFrames(maximum: Int)
    case tooManyMacros(maximum: Int)
    case tooManySteps(maximum: Int)
    case tooManyReceipts(maximum: Int)
    case archiveTooLarge(maximum: Int)
    case invalidMacroName
    case invalidReviewer
    case invalidMacroStep
    case commandTooLarge(maximum: Int)
    case commandMayContainSecret
    case staleMacroReview
    case invalidReceipt

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: "The terminal evidence geometry is invalid."
        case .invalidCellCount: "The terminal evidence cell count does not match its geometry."
        case .invalidCell: "The terminal evidence contains an invalid display cell."
        case .unredactedCell: "Terminal evidence cannot retain an input or non-display cell."
        case .fingerprintMismatch: "The terminal evidence fingerprint does not match its content."
        case .invalidRetention: "The terminal history retention policy is invalid."
        case .tooManyFrames(let maximum): "The recorder can retain at most \(maximum) frames."
        case .tooManyMacros(let maximum): "The recorder can retain at most \(maximum) macros."
        case .tooManySteps(let maximum): "A macro can contain at most \(maximum) steps."
        case .tooManyReceipts(let maximum): "The recorder can retain at most \(maximum) execution receipts."
        case .archiveTooLarge(let maximum): "The recorder archive exceeds its \(maximum)-byte limit."
        case .invalidMacroName: "Give the macro a short printable name."
        case .invalidReviewer: "Give the local review attestation a short printable reviewer label."
        case .invalidMacroStep: "One macro step is incomplete or unsupported."
        case .commandTooLarge(let maximum): "A staged command can contain at most \(maximum) UTF-8 bytes."
        case .commandMayContainSecret: "Credentials and secret assignments cannot be stored in a terminal macro."
        case .staleMacroReview: "The macro changed after review and must be reviewed again."
        case .invalidReceipt: "The macro execution receipt is invalid or was modified."
        }
    }
}

public enum TerminalHistoryRetention: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    public var id: Int { rawValue }
    public var label: String { "\(rawValue) DAYS" }
}

public struct TerminalHistoryPolicy: Codable, Equatable, Sendable {
    public var retention: TerminalHistoryRetention
    public var maximumFrames: Int

    public init(
        retention: TerminalHistoryRetention = .thirtyDays,
        maximumFrames: Int = TerminalFlightRecorderLimits.standard.maximumFrames
    ) {
        self.retention = retention
        self.maximumFrames = maximumFrames
    }

    public func validate(limits: TerminalFlightRecorderLimits = .standard) throws {
        guard (1...limits.maximumFrames).contains(maximumFrames) else {
            throw TerminalFlightRecorderError.invalidRetention
        }
    }
}

public struct TerminalEvidenceCell: Codable, Equatable, Sendable {
    public let character: String
    public let attributes: TerminalAttributes

    public init(character: Character, attributes: TerminalAttributes) {
        self.character = String(character)
        self.attributes = attributes
    }

    fileprivate func validate() throws {
        guard character.count == 1,
              let scalar = character.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else {
            throw TerminalFlightRecorderError.invalidCell
        }
        guard attributes.protected, !attributes.nonDisplay else {
            throw TerminalFlightRecorderError.unredactedCell
        }
    }
}

public struct TerminalEvidenceFrame: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let profileID: UUID
    public let profileName: String
    public let deviceName: String?
    public let rows: Int
    public let columns: Int
    public let cells: [TerminalEvidenceCell]
    public let inputInhibited: Bool
    public let messageWaiting: Bool
    public let readMode: TerminalReadMode
    public let clearedInputFieldCount: Int
    public let clearedSensitiveRowCount: Int
    public let screenFingerprint: String

    public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        profileID: UUID,
        profileName: String,
        deviceName: String? = nil,
        screen: TerminalScreen
    ) {
        let inputPositions = Set(
            screen.fields
                .filter { !$0.isProtected }
                .flatMap { field in
                    let lower = max(0, field.start)
                    let upper = min(screen.cells.count, field.start + max(0, field.length))
                    return lower < upper ? Array(lower..<upper) : []
                }
        )
        let sensitiveRows = Set((0..<screen.rows).filter { row in
            Self.rowMayContainSecret(screen.rowText(row))
        })
        let sanitizedCells = screen.cells.enumerated().map { index, cell in
            var attributes = cell.attributes
            let row = index / screen.columns
            let mustClear = inputPositions.contains(index)
                || attributes.nonDisplay
                || sensitiveRows.contains(row)
            attributes.nonDisplay = false
            attributes.protected = true
            return TerminalEvidenceCell(
                character: mustClear ? " " : cell.character,
                attributes: attributes
            )
        }

        self.id = id
        self.capturedAt = terminalRecorderDate(capturedAt)
        self.profileID = profileID
        self.profileName = Self.boundedLabel(profileName, fallback: "Terminal session")
        self.deviceName = deviceName.map { Self.boundedLabel($0, fallback: "") }.flatMap { $0.isEmpty ? nil : $0 }
        rows = screen.rows
        columns = screen.columns
        cells = sanitizedCells
        inputInhibited = screen.inputInhibited
        messageWaiting = screen.messageWaiting
        readMode = screen.readMode
        clearedInputFieldCount = screen.fields.filter { !$0.isProtected }.count
        clearedSensitiveRowCount = sensitiveRows.count
        screenFingerprint = Self.fingerprint(
            rows: screen.rows,
            columns: screen.columns,
            cells: sanitizedCells,
            inputInhibited: screen.inputInhibited,
            messageWaiting: screen.messageWaiting,
            readMode: screen.readMode
        )
    }

    public var title: String {
        visibleLines
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "5250 screen"
    }

    public var shortFingerprint: String {
        "\(screenFingerprint.prefix(8))…\(screenFingerprint.suffix(4))".uppercased()
    }

    public var visibleLines: [String] {
        guard rows > 0, columns > 0, cells.count == rows * columns else { return [] }
        return (0..<rows).map { row in
            cells[(row * columns)..<((row + 1) * columns)].map(\.character).joined()
        }
    }

    public var visibleText: String { visibleLines.joined(separator: "\n") }

    public var previewScreen: TerminalScreen {
        var result = TerminalScreen(rows: rows, columns: columns)
        result.cells = cells.map { evidenceCell in
            TerminalCell(
                character: evidenceCell.character.first ?? " ",
                attributes: evidenceCell.attributes,
                isNull: false
            )
        }
        result.fields = []
        result.cursor = TerminalCursor(isVisible: false)
        result.inputInhibited = true
        result.messageWaiting = messageWaiting
        result.readMode = readMode
        return result
    }

    public func validate() throws {
        guard (1...64).contains(rows), (1...256).contains(columns) else {
            throw TerminalFlightRecorderError.invalidDimensions
        }
        guard cells.count == rows * columns else {
            throw TerminalFlightRecorderError.invalidCellCount
        }
        try cells.forEach { try $0.validate() }
        let expected = Self.fingerprint(
            rows: rows,
            columns: columns,
            cells: cells,
            inputInhibited: inputInhibited,
            messageWaiting: messageWaiting,
            readMode: readMode
        )
        guard screenFingerprint == expected else {
            throw TerminalFlightRecorderError.fingerprintMismatch
        }
        guard !profileName.isEmpty, profileName.utf8.count <= 128,
              deviceName?.utf8.count ?? 0 <= 128,
              clearedInputFieldCount >= 0,
              clearedSensitiveRowCount >= 0 else {
            throw TerminalFlightRecorderError.invalidCell
        }
    }

    private static func fingerprint(
        rows: Int,
        columns: Int,
        cells: [TerminalEvidenceCell],
        inputInhibited: Bool,
        messageWaiting: Bool,
        readMode: TerminalReadMode
    ) -> String {
        let attributes = cells.map { cell in
            let value = cell.attributes
            return [
                cell.character,
                value.foreground.rawValue,
                value.reverse ? "1" : "0",
                value.underline ? "1" : "0",
                value.blink ? "1" : "0",
                value.highIntensity ? "1" : "0",
                value.columnSeparator ? "1" : "0"
            ].joined(separator: ":")
        }.joined(separator: "|")
        return AIContentFingerprint.sha256(
            "v1\n\(rows)x\(columns)\n\(readMode.rawValue)\n\(inputInhibited ? 1 : 0)\n\(messageWaiting ? 1 : 0)\n\(attributes)"
        )
    }

    private static func boundedLabel(_ value: String, fallback: String) -> String {
        let singleLine = value
            .split(whereSeparator: { $0.isNewline || $0.isASCII && $0.asciiValue.map { $0 < 0x20 } == true })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((singleLine.isEmpty ? fallback : singleLine).prefix(128))
    }

    private static func rowMayContainSecret(_ row: String) -> Bool {
        let upper = row.uppercased()
        return ["PASSWORD", "PASSWD", "PASSPHRASE", "API KEY", "TOKEN", "SECRET"]
            .contains(where: upper.contains)
    }
}

public enum TerminalMacroFieldExit: String, Codable, CaseIterable, Identifiable, Sendable {
    case neutral
    case positive
    case negative

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .neutral: "FIELD EXIT"
        case .positive: "FIELD +"
        case .negative: "FIELD -"
        }
    }
}

public enum TerminalMacroAction: Codable, Equatable, Sendable {
    case matchFrame(fingerprint: String)
    case stageReadOnlyCommand(String)
    case fieldExit(TerminalMacroFieldExit)
    case sendAID(UInt8)
    case bookmark

    public var kindLabel: String {
        switch self {
        case .matchFrame: "MATCH"
        case .stageReadOnlyCommand: "STAGE"
        case .fieldExit: "FIELD"
        case .sendAID: "SEND"
        case .bookmark: "BOOKMARK"
        }
    }

    public var title: String {
        switch self {
        case .matchFrame: "Match exact redacted screen"
        case .stageReadOnlyCommand(let command): command
        case .fieldExit(let kind): kind.label.capitalized
        case .sendAID(let code): Self.aidLabel(code)
        case .bookmark: "Capture result evidence"
        }
    }

    public var hasHostEffect: Bool {
        switch self {
        case .fieldExit, .sendAID: true
        case .matchFrame, .stageReadOnlyCommand, .bookmark: false
        }
    }

    public static func aidLabel(_ code: UInt8) -> String {
        if code == TN5250AID.forwardEdgeTrigger.rawValue { return "Forward Edge Trigger" }
        if code == TN5250AID.enter.rawValue { return "Enter" }
        if code == TN5250AID.help.rawValue { return "Help" }
        if code == TN5250AID.clear.rawValue { return "Clear" }
        if code == TN5250AID.rollUp.rawValue { return "Roll Up" }
        if code == TN5250AID.rollDown.rawValue { return "Roll Down" }
        if let number = TN5250AID.functionNumber(for: code) { return "F\(number)" }
        return String(format: "AID 0x%02X", code)
    }

    fileprivate func validate(limits: TerminalFlightRecorderLimits) throws {
        switch self {
        case .matchFrame(let fingerprint):
            guard Self.isSHA256(fingerprint) else { throw TerminalFlightRecorderError.invalidMacroStep }
        case .stageReadOnlyCommand(let command):
            let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  normalized == command,
                  !command.contains("\0"),
                  !command.contains(where: \.isNewline) else {
                throw TerminalFlightRecorderError.invalidMacroStep
            }
            guard command.utf8.count <= limits.maximumCommandUTF8Bytes else {
                throw TerminalFlightRecorderError.commandTooLarge(maximum: limits.maximumCommandUTF8Bytes)
            }
            let upper = command.uppercased()
            guard !["PASSWORD=", "PASSWD=", "TOKEN=", "SECRET=", "APIKEY=", "API_KEY="]
                .contains(where: upper.contains) else {
                throw TerminalFlightRecorderError.commandMayContainSecret
            }
        case .fieldExit:
            break
        case .sendAID(let code):
            guard code == TN5250AID.enter.rawValue
                    || code == TN5250AID.help.rawValue
                    || code == TN5250AID.clear.rawValue
                    || code == TN5250AID.rollUp.rawValue
                    || code == TN5250AID.rollDown.rawValue
                    || TN5250AID.functionNumber(for: code) != nil else {
                throw TerminalFlightRecorderError.invalidMacroStep
            }
        case .bookmark:
            break
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }
}

public struct ReviewedTerminalMacroStep: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var action: TerminalMacroAction

    public init(id: UUID = UUID(), name: String, action: TerminalMacroAction) {
        self.id = id
        self.name = name
        self.action = action
    }

    fileprivate func validate(limits: TerminalFlightRecorderLimits) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized == name,
              name.utf8.count <= 128,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw TerminalFlightRecorderError.invalidMacroStep
        }
        try action.validate(limits: limits)
    }
}

public struct ReviewedTerminalMacro: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var targetProfileID: UUID?
    public var steps: [ReviewedTerminalMacroStep]
    public var reviewedAt: Date?
    public var reviewedBy: String?
    public var reviewFingerprint: String?

    public init(
        id: UUID = UUID(),
        name: String,
        targetProfileID: UUID? = nil,
        steps: [ReviewedTerminalMacroStep],
        reviewedAt: Date? = nil,
        reviewedBy: String? = nil,
        reviewFingerprint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.targetProfileID = targetProfileID
        self.steps = steps
        self.reviewedAt = reviewedAt.map(terminalRecorderDate)
        self.reviewedBy = reviewedBy
        self.reviewFingerprint = reviewFingerprint
    }

    public var contentFingerprint: String {
        struct Payload: Encodable {
            let version: Int
            let id: UUID
            let name: String
            let targetProfileID: UUID?
            let steps: [ReviewedTerminalMacroStep]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = Payload(version: 1, id: id, name: name, targetProfileID: targetProfileID, steps: steps)
        return AIContentFingerprint.sha256((try? encoder.encode(payload)) ?? Data())
    }

    public var shortFingerprint: String {
        "\(contentFingerprint.prefix(8))…\(contentFingerprint.suffix(4))".uppercased()
    }

    public var isReviewCurrent: Bool {
        reviewedAt != nil && reviewedBy?.isEmpty == false && reviewFingerprint == contentFingerprint
    }

    public mutating func attestReview(by reviewer: String, at reviewedAt: Date = Date()) throws {
        try validateContent()
        let normalized = reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.utf8.count <= 128,
              normalized.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw TerminalFlightRecorderError.invalidReviewer
        }
        self.reviewedAt = terminalRecorderDate(reviewedAt)
        reviewedBy = normalized
        reviewFingerprint = contentFingerprint
    }

    public mutating func invalidateReview() {
        reviewedAt = nil
        reviewedBy = nil
        reviewFingerprint = nil
    }

    public func validate(limits: TerminalFlightRecorderLimits = .standard) throws {
        try validateContent(limits: limits)
        let hasAnyReviewField = reviewedAt != nil || reviewedBy != nil || reviewFingerprint != nil
        guard !hasAnyReviewField || isReviewCurrent else {
            throw TerminalFlightRecorderError.staleMacroReview
        }
    }

    private func validateContent(limits: TerminalFlightRecorderLimits = .standard) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized == name,
              name.utf8.count <= 128,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw TerminalFlightRecorderError.invalidMacroName
        }
        guard !steps.isEmpty, steps.count <= limits.maximumStepsPerMacro else {
            throw steps.isEmpty
                ? TerminalFlightRecorderError.invalidMacroStep
                : TerminalFlightRecorderError.tooManySteps(maximum: limits.maximumStepsPerMacro)
        }
        guard Set(steps.map(\.id)).count == steps.count else {
            throw TerminalFlightRecorderError.invalidMacroStep
        }
        try steps.forEach { try $0.validate(limits: limits) }
    }
}

public enum TerminalMacroReceiptOutcome: String, Codable, Sendable {
    case passed
    case blocked
}

public struct TerminalMacroStepReceipt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let macroID: UUID
    public let macroFingerprint: String
    public let stepID: UUID
    public let stepOrdinal: Int
    public let actionLabel: String
    public let expectedScreenFingerprint: String?
    public let observedScreenFingerprint: String?
    public let outcome: TerminalMacroReceiptOutcome
    public let detail: String
    public let receiptFingerprint: String

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        macroID: UUID,
        macroFingerprint: String,
        stepID: UUID,
        stepOrdinal: Int,
        actionLabel: String,
        expectedScreenFingerprint: String?,
        observedScreenFingerprint: String?,
        outcome: TerminalMacroReceiptOutcome,
        detail: String
    ) {
        self.id = id
        let normalizedRecordedAt = terminalRecorderDate(recordedAt)
        self.recordedAt = normalizedRecordedAt
        self.macroID = macroID
        self.macroFingerprint = macroFingerprint
        self.stepID = stepID
        self.stepOrdinal = stepOrdinal
        self.actionLabel = Self.bounded(actionLabel, maximum: 128)
        self.expectedScreenFingerprint = expectedScreenFingerprint
        self.observedScreenFingerprint = observedScreenFingerprint
        self.outcome = outcome
        self.detail = Self.bounded(detail, maximum: 300)
        receiptFingerprint = Self.fingerprint(
            id: id,
            recordedAt: normalizedRecordedAt,
            macroID: macroID,
            macroFingerprint: macroFingerprint,
            stepID: stepID,
            stepOrdinal: stepOrdinal,
            actionLabel: Self.bounded(actionLabel, maximum: 128),
            expectedScreenFingerprint: expectedScreenFingerprint,
            observedScreenFingerprint: observedScreenFingerprint,
            outcome: outcome,
            detail: Self.bounded(detail, maximum: 300)
        )
    }

    public func validate() throws {
        guard stepOrdinal > 0,
              macroFingerprint.count == 64,
              !actionLabel.isEmpty,
              !detail.isEmpty,
              receiptFingerprint == Self.fingerprint(
                id: id,
                recordedAt: recordedAt,
                macroID: macroID,
                macroFingerprint: macroFingerprint,
                stepID: stepID,
                stepOrdinal: stepOrdinal,
                actionLabel: actionLabel,
                expectedScreenFingerprint: expectedScreenFingerprint,
                observedScreenFingerprint: observedScreenFingerprint,
                outcome: outcome,
                detail: detail
              ) else {
            throw TerminalFlightRecorderError.invalidReceipt
        }
    }

    private static func fingerprint(
        id: UUID,
        recordedAt: Date,
        macroID: UUID,
        macroFingerprint: String,
        stepID: UUID,
        stepOrdinal: Int,
        actionLabel: String,
        expectedScreenFingerprint: String?,
        observedScreenFingerprint: String?,
        outcome: TerminalMacroReceiptOutcome,
        detail: String
    ) -> String {
        AIContentFingerprint.sha256([
            "v1", id.uuidString, String(Int64(recordedAt.timeIntervalSince1970 * 1_000)),
            macroID.uuidString, macroFingerprint, stepID.uuidString, String(stepOrdinal),
            actionLabel, expectedScreenFingerprint ?? "-", observedScreenFingerprint ?? "-",
            outcome.rawValue, detail
        ].joined(separator: "\n"))
    }

    private static func bounded(_ value: String, maximum: Int) -> String {
        let singleLine = value.split(whereSeparator: \.isNewline).joined(separator: " ")
        return String(singleLine.prefix(maximum)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TerminalFlightRecorderArchive: Codable, Equatable, Sendable {
    public var version: Int
    public var policy: TerminalHistoryPolicy
    public var frames: [TerminalEvidenceFrame]
    public var macros: [ReviewedTerminalMacro]
    public var receipts: [TerminalMacroStepReceipt]
    public var updatedAt: Date

    public init(
        version: Int = 1,
        policy: TerminalHistoryPolicy = TerminalHistoryPolicy(),
        frames: [TerminalEvidenceFrame] = [],
        macros: [ReviewedTerminalMacro] = [],
        receipts: [TerminalMacroStepReceipt] = [],
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.policy = policy
        self.frames = frames
        self.macros = macros
        self.receipts = receipts
        self.updatedAt = terminalRecorderDate(updatedAt)
    }

    @discardableResult
    public mutating func append(
        _ frame: TerminalEvidenceFrame,
        at now: Date = Date(),
        limits: TerminalFlightRecorderLimits = .standard
    ) throws -> Bool {
        try frame.validate()
        try policy.validate(limits: limits)
        prune(at: now)
        guard frames.last?.profileID != frame.profileID
                || frames.last?.screenFingerprint != frame.screenFingerprint else {
            return false
        }
        frames.append(frame)
        let maximum = min(policy.maximumFrames, limits.maximumFrames)
        if frames.count > maximum { frames.removeFirst(frames.count - maximum) }
        updatedAt = terminalRecorderDate(now)
        return true
    }

    public mutating func upsert(
        _ macro: ReviewedTerminalMacro,
        at now: Date = Date(),
        limits: TerminalFlightRecorderLimits = .standard
    ) throws {
        try macro.validate(limits: limits)
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index] = macro
        } else {
            guard macros.count < limits.maximumMacros else {
                throw TerminalFlightRecorderError.tooManyMacros(maximum: limits.maximumMacros)
            }
            macros.append(macro)
        }
        updatedAt = terminalRecorderDate(now)
    }

    public mutating func append(
        _ receipt: TerminalMacroStepReceipt,
        at now: Date = Date(),
        limits: TerminalFlightRecorderLimits = .standard
    ) throws {
        try receipt.validate()
        receipts.append(receipt)
        if receipts.count > limits.maximumReceipts {
            receipts.removeFirst(receipts.count - limits.maximumReceipts)
        }
        updatedAt = terminalRecorderDate(now)
    }

    public mutating func prune(at now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(policy.retention.rawValue) * 86_400)
        frames.removeAll { $0.capturedAt < cutoff }
        let maximum = max(1, min(policy.maximumFrames, TerminalFlightRecorderLimits.standard.maximumFrames))
        if frames.count > maximum { frames.removeFirst(frames.count - maximum) }
    }

    public func validate(limits: TerminalFlightRecorderLimits = .standard) throws {
        guard version == 1 else { throw TerminalFlightRecorderError.invalidRetention }
        try policy.validate(limits: limits)
        guard frames.count <= limits.maximumFrames else {
            throw TerminalFlightRecorderError.tooManyFrames(maximum: limits.maximumFrames)
        }
        guard macros.count <= limits.maximumMacros else {
            throw TerminalFlightRecorderError.tooManyMacros(maximum: limits.maximumMacros)
        }
        guard receipts.count <= limits.maximumReceipts else {
            throw TerminalFlightRecorderError.tooManyReceipts(maximum: limits.maximumReceipts)
        }
        guard Set(frames.map(\.id)).count == frames.count,
              Set(macros.map(\.id)).count == macros.count,
              Set(receipts.map(\.id)).count == receipts.count else {
            throw TerminalFlightRecorderError.fingerprintMismatch
        }
        try frames.forEach { try $0.validate() }
        try macros.forEach { try $0.validate(limits: limits) }
        try receipts.forEach { try $0.validate() }
    }
}
