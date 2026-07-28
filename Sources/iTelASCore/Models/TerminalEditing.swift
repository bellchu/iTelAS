import Foundation

public struct TerminalPasteResult: Equatable, Sendable {
    public let insertedCharacters: Int
    public let skippedCharacters: Int
    public let fieldsTouched: Int

    public init(insertedCharacters: Int, skippedCharacters: Int, fieldsTouched: Int) {
        self.insertedCharacters = insertedCharacters
        self.skippedCharacters = skippedCharacters
        self.fieldsTouched = fieldsTouched
    }
}

public enum TerminalInputIssue: Equatable, Sendable {
    case notInEditableField
    case characterRejected
    case insertOverflow
    case mandatoryEntry(field: Int)
    case mandatoryFill(field: Int)
    case fieldExitRequired(field: Int)
    case duplicationNotAllowed(field: Int)
    case fieldMinusRequiresNumeric(field: Int)
    case invalidNumericSign(field: Int)

    public var message: String {
        switch self {
        case .notInEditableField:
            "Move to an editable field first."
        case .characterRejected:
            "The current 5250 field does not accept that character."
        case .insertOverflow:
            "Insert is blocked because the current field has no null position available."
        case .mandatoryEntry(let field):
            "Field \(field) requires an entry before Enter or Field Exit."
        case .mandatoryFill(let field):
            "Field \(field) must be completely filled before you leave it."
        case .fieldExitRequired(let field):
            "Field \(field) requires Field Exit, Field +, or Field - before Enter."
        case .duplicationNotAllowed(let field):
            "Dup is not enabled for field \(field)."
        case .fieldMinusRequiresNumeric(let field):
            "Field - is valid only for numeric field \(field)."
        case .invalidNumericSign(let field):
            "Field \(field) needs a low-order digit before Field - can apply a negative sign."
        }
    }
}

public enum TerminalCharacterInputResult: Equatable, Sendable {
    case rejected(TerminalInputIssue)
    case accepted
    case advanced
    case autoEnter
    case forwardEdgeTrigger

    public var wasAccepted: Bool {
        switch self {
        case .rejected: false
        case .accepted, .advanced, .autoEnter, .forwardEdgeTrigger: true
        }
    }
}

public enum TerminalFieldExitKind: Equatable, Sendable {
    case neutral
    case positive
    case negative
}

public enum TerminalFieldActionResult: Equatable, Sendable {
    case rejected(TerminalInputIssue)
    case advanced
    case autoEnter
    case forwardEdgeTrigger

    public var succeeded: Bool {
        switch self {
        case .rejected: false
        case .advanced, .autoEnter, .forwardEdgeTrigger: true
        }
    }
}

public enum TerminalAIDPreparationResult: Equatable, Sendable {
    case ready
    case rejected(TerminalInputIssue)
}

public extension TerminalScreen {
    var editableFieldCount: Int {
        fields.lazy.filter { !$0.isProtected }.count
    }

    var currentEditableFieldOrdinal: Int? {
        let position = cursor.row * columns + cursor.column
        let inputFields = sortedEditableFields
        guard let index = inputFields.firstIndex(where: { $0.contains(position) }) else { return nil }
        return index + 1
    }

    var isCurrentInputFieldNonDisplay: Bool {
        guard let index = editableFieldIndex(at: cursor.row * columns + cursor.column) else { return false }
        return fields[index].isNonDisplay
    }

    var isCurrentInputFieldForwardEdgeTrigger: Bool {
        guard let index = editableFieldIndex(at: cursorPosition) else { return false }
        return fields[index].isForwardEdgeTrigger
    }

    var currentEditableFieldLength: Int? {
        guard let index = editableFieldIndex(at: cursorPosition) else { return nil }
        return fields[index].length
    }

    var currentEditableFieldContract: String? {
        guard let index = editableFieldIndex(at: cursorPosition) else { return nil }
        let field = fields[index]
        var components = [field.inputType.label]
        if field.isMonocase { components.append("MONOCASE") }
        if field.requiresFieldExit { components.append("FIELD EXIT") }
        if field.requiresInput { components.append("MANDATORY") }
        if let adjustment = field.adjustment.label { components.append(adjustment) }
        if field.allowsDuplication { components.append("DUP") }
        if field.isTransparent { components.append("TRANSPARENT") }
        if field.isForwardEdgeTrigger {
            components.append("FWD EDGE")
            components.append("AID FET")
        } else if field.autoEnter {
            components.append("AUTO ENTER")
        }
        if field.isFieldExitPending { components.append("EXIT PENDING") }
        return components.joined(separator: " · ")
    }

    var currentFieldMovementIssue: TerminalInputIssue? {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else { return nil }
        return movementIssue(leaving: fieldIndex)
    }

    var isLikelyCommandEntryScreen: Bool {
        guard currentEditableFieldLength != nil, !isCurrentInputFieldNonDisplay else { return false }
        let display = visibleText(redactingSensitive: true).uppercased()
        return [
            "SELECTION OR COMMAND",
            "COMMAND ===>",
            "COMMAND  ===>",
            "ENTER COMMAND"
        ].contains(where: display.contains)
    }

    mutating func stageTextInCurrentInputField(_ text: String) -> TerminalPasteResult {
        guard !text.isEmpty,
              !text.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" }),
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let fieldIndex = editableFieldIndex(at: cursorPosition),
              !fields[fieldIndex].isNonDisplay,
              text.count <= fields[fieldIndex].length else {
            return TerminalPasteResult(insertedCharacters: 0, skippedCharacters: text.count, fieldsTouched: 0)
        }

        let field = fields[fieldIndex]
        let normalizedCharacters = text.compactMap(field.normalizedKeyboardCharacter)
        guard normalizedCharacters.count == text.count else {
            return TerminalPasteResult(insertedCharacters: 0, skippedCharacters: text.count, fieldsTouched: 0)
        }
        clear(range: field.start..<(field.start + field.length), fieldIndex: fieldIndex)
        move(to: field.start)
        return pasteText(String(normalizedCharacters))
    }

    @discardableResult
    mutating func moveToNextInputField() -> Bool {
        let inputFields = sortedEditableFields
        guard !inputFields.isEmpty else { return false }
        let next = inputFields.first(where: { $0.start > cursorPosition }) ?? inputFields[0]
        guard prepareForCursorMove(to: next.start) else { return false }
        move(to: next.start)
        return true
    }

    @discardableResult
    mutating func moveToPreviousInputField() -> Bool {
        let inputFields = sortedEditableFields
        guard !inputFields.isEmpty else { return false }
        let currentPosition = cursor.row * columns + cursor.column
        let previous = inputFields.last(where: { $0.start < currentPosition }) ?? inputFields[inputFields.count - 1]
        guard prepareForCursorMove(to: previous.start) else { return false }
        moveCursor(row: previous.start / columns, column: previous.start % columns)
        return true
    }

    @discardableResult
    mutating func moveCursorToInputField(row: Int, column: Int) -> Bool {
        guard let requested = index(row: row, column: column) else { return false }
        if let fieldIndex = editableFieldIndex(at: requested) {
            guard prepareForCursorMove(to: requested) else { return false }
            moveCursor(row: row, column: column)
            return !fields[fieldIndex].isProtected
        }

        let sameRow = sortedEditableFields.filter { field in
            let firstRow = field.start / columns
            let lastRow = (field.start + field.length - 1) / columns
            return (firstRow...lastRow).contains(row)
        }
        guard let nearest = sameRow.min(by: {
            distance(from: requested, to: $0) < distance(from: requested, to: $1)
        }) else { return false }
        let target = min(max(requested, nearest.start), nearest.start + nearest.length - 1)
        guard prepareForCursorMove(to: target) else { return false }
        moveCursor(row: target / columns, column: target % columns)
        return true
    }

    @discardableResult
    mutating func moveCursorLeft() -> Bool {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else {
            return moveToPreviousInputField()
        }
        let field = fields[fieldIndex]
        if cursorPosition > field.start {
            move(to: cursorPosition - 1)
            return true
        }
        guard moveToPreviousInputField(),
              let previousIndex = editableFieldIndex(at: cursorPosition) else { return false }
        let previous = fields[previousIndex]
        move(to: previous.start + previous.length - 1)
        return true
    }

    @discardableResult
    mutating func moveCursorRight() -> Bool {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else {
            return moveToNextInputField()
        }
        let field = fields[fieldIndex]
        if cursorPosition < field.start + field.length - 1 {
            move(to: cursorPosition + 1)
            return true
        }
        return moveToNextInputField()
    }

    @discardableResult
    mutating func moveCursorVertically(_ rowDelta: Int) -> Bool {
        guard rowDelta != 0 else { return false }
        let direction = rowDelta.signum()
        let targetRows = stride(
            from: cursor.row + direction,
            through: direction > 0 ? rows - 1 : 0,
            by: direction
        )
        for targetRow in targetRows {
            let candidates = sortedEditableFields.filter { field in
                let firstRow = field.start / columns
                let lastRow = (field.start + field.length - 1) / columns
                return (firstRow...lastRow).contains(targetRow)
            }
            if let field = candidates.min(by: {
                horizontalDistance(fromColumn: cursor.column, to: $0, onRow: targetRow)
                    < horizontalDistance(fromColumn: cursor.column, to: $1, onRow: targetRow)
            }) {
                let rowStart = targetRow * columns
                let rowEnd = rowStart + columns - 1
                let lower = max(field.start, rowStart)
                let upper = min(field.start + field.length - 1, rowEnd)
                let destination = min(max(rowStart + cursor.column, lower), upper)
                guard prepareForCursorMove(to: destination) else { return false }
                move(to: destination)
                return true
            }
        }
        return false
    }

    @discardableResult
    mutating func moveToStartOfInputField() -> Bool {
        if let homeCursorPosition, cells.indices.contains(homeCursorPosition) {
            guard prepareForCursorMove(to: homeCursorPosition) else { return false }
            move(to: homeCursorPosition)
            return true
        }
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else {
            return ensureCursorInInputField()
        }
        move(to: fields[fieldIndex].start)
        return true
    }

    @discardableResult
    mutating func eraseToEndOfInputField() -> Bool {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else { return false }
        let field = fields[fieldIndex]
        clear(range: cursorPosition..<(field.start + field.length), fieldIndex: fieldIndex)
        return true
    }

    @discardableResult
    mutating func eraseCurrentInputField() -> Bool {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else { return false }
        let field = fields[fieldIndex]
        clear(range: field.start..<(field.start + field.length), fieldIndex: fieldIndex)
        move(to: field.start)
        return true
    }

    @discardableResult
    mutating func eraseAllInputFields() -> Bool {
        let editableIndices = fields.indices.filter { !fields[$0].isProtected }
        guard !editableIndices.isEmpty else { return false }
        for fieldIndex in editableIndices {
            let field = fields[fieldIndex]
            clear(range: field.start..<(field.start + field.length), fieldIndex: fieldIndex)
        }
        let first = editableIndices.map { fields[$0] }.min(by: { $0.start < $1.start })!
        move(to: first.start)
        return true
    }

    @discardableResult
    mutating func fieldExit() -> Bool {
        performFieldExit(.neutral).succeeded
    }

    mutating func performFieldExit(_ kind: TerminalFieldExitKind) -> TerminalFieldActionResult {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else {
            return .rejected(.notInEditableField)
        }
        let ordinal = editableFieldOrdinal(for: fieldIndex)
        let field = fields[fieldIndex]
        let originalScreen = self
        guard !field.requiresInput || field.modified else {
            return .rejected(.mandatoryEntry(field: ordinal))
        }
        if kind == .negative,
           field.inputType != .numericOnly,
           field.inputType != .signedNumeric {
            return .rejected(.fieldMinusRequiresNumeric(field: ordinal))
        }

        let dataRange = field.inputDataRange
        guard !dataRange.isEmpty else { return .rejected(.notInEditableField) }
        let lastDataPosition = dataRange.upperBound - 1
        let exitsFromFirstPosition = cursorPosition == dataRange.lowerBound
        let preservesFilledLastPosition = cursorPosition == lastDataPosition && !cells[lastDataPosition].isNull

        if field.adjustment == .mandatoryFill, field.modified,
           !exitsFromFirstPosition,
           (!fieldIsComplete(fieldIndex) || !preservesFilledLastPosition) {
            return .rejected(.mandatoryFill(field: ordinal))
        }

        if field.adjustment == .mandatoryFill, exitsFromFirstPosition {
            clear(range: dataRange, fieldIndex: fieldIndex)
        } else if let fill = field.adjustment.rightFillCharacter {
            rightAdjust(fieldIndex: fieldIndex, fill: fill)
        } else if field.inputType == .signedNumeric {
            rightAdjust(fieldIndex: fieldIndex, fill: " ")
        } else if field.adjustment != .mandatoryFill {
            let eraseStart = preservesFilledLastPosition
                ? dataRange.upperBound
                : min(max(cursorPosition, dataRange.lowerBound), dataRange.upperBound)
            if eraseStart < dataRange.upperBound {
                clear(range: eraseStart..<dataRange.upperBound, fieldIndex: fieldIndex)
            } else {
                fields[fieldIndex].modified = true
            }
        }

        if kind == .negative {
            guard let lowOrderPosition = dataRange.last(where: { !cells[$0].isNull }),
                  isASCIIDigit(cells[lowOrderPosition].character) else {
                self = originalScreen
                return .rejected(.invalidNumericSign(field: ordinal))
            }
            fields[fieldIndex].isNegative = true
        } else {
            fields[fieldIndex].isNegative = false
        }

        if field.inputType == .signedNumeric {
            let signPosition = field.start + field.length - 1
            cells[signPosition].character = kind == .negative ? "-" : " "
            cells[signPosition].isNull = kind != .negative
            cells[signPosition].inputByteOverride = nil
        }
        fields[fieldIndex].modified = true
        fields[fieldIndex].isFieldExitPending = false

        if field.isForwardEdgeTrigger { return .forwardEdgeTrigger }
        if field.autoEnter { return .autoEnter }
        _ = moveToNextInputFieldUnchecked()
        return .advanced
    }

    mutating func duplicateCurrentField() -> TerminalFieldActionResult {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else {
            return .rejected(.notInEditableField)
        }
        let ordinal = editableFieldOrdinal(for: fieldIndex)
        let field = fields[fieldIndex]
        guard field.allowsDuplication else {
            return .rejected(.duplicationNotAllowed(field: ordinal))
        }
        let dataRange = field.inputDataRange
        guard dataRange.contains(cursorPosition) else {
            return .rejected(.characterRejected)
        }
        if field.adjustment == .mandatoryFill,
           (dataRange.lowerBound..<cursorPosition).contains(where: { cells[$0].isNull }) {
            return .rejected(.mandatoryFill(field: ordinal))
        }
        for position in cursorPosition..<dataRange.upperBound {
            cells[position].character = "*"
            cells[position].isNull = false
            cells[position].inputByteOverride = 0x1C
        }
        fields[fieldIndex].modified = true
        fields[fieldIndex].isFieldExitPending = false
        fields[fieldIndex].isNegative = false
        if field.isForwardEdgeTrigger { return .forwardEdgeTrigger }
        if field.autoEnter { return .autoEnter }
        _ = moveToNextInputFieldUnchecked()
        return .advanced
    }

    @discardableResult
    mutating func deleteCharacter() -> Bool {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else { return false }
        let field = fields[fieldIndex]
        let end = field.inputDataRange.upperBound
        guard field.inputDataRange.contains(cursorPosition) else { return false }
        if cursorPosition < end - 1 {
            for position in cursorPosition..<(end - 1) {
                cells[position].character = cells[position + 1].character
                cells[position].isNull = cells[position + 1].isNull
                cells[position].inputByteOverride = cells[position + 1].inputByteOverride
            }
        }
        cells[end - 1].character = " "
        cells[end - 1].isNull = true
        cells[end - 1].inputByteOverride = nil
        fields[fieldIndex].modified = true
        fields[fieldIndex].isFieldExitPending = fields[fieldIndex].adjustment.rightFillCharacter != nil
            || fields[fieldIndex].inputType == .signedNumeric
        return true
    }

    @discardableResult
    mutating func replaceCharacter(_ character: Character, insertMode: Bool) -> Bool {
        guard insertMode else { return replaceCharacter(character) }
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else { return false }
        let field = fields[fieldIndex]
        let dataRange = field.inputDataRange
        guard dataRange.contains(cursorPosition) else { return false }
        guard let normalized = field.normalizedKeyboardCharacter(character) else { return false }
        let end = dataRange.upperBound
        guard cells[end - 1].isNull else { return false }
        if cursorPosition < end - 1 {
            for position in stride(from: end - 1, through: cursorPosition + 1, by: -1) {
                cells[position].character = cells[position - 1].character
                cells[position].isNull = cells[position - 1].isNull
                cells[position].inputByteOverride = cells[position - 1].inputByteOverride
            }
        }
        cells[cursorPosition].character = normalized
        cells[cursorPosition].isNull = false
        cells[cursorPosition].inputByteOverride = nil
        fields[fieldIndex].modified = true
        if field.adjustment.rightFillCharacter != nil || field.inputType == .signedNumeric {
            fields[fieldIndex].isFieldExitPending = true
        } else if field.requiresFieldExit && cursorPosition == end - 1 {
            fields[fieldIndex].isFieldExitPending = true
        }
        move(to: min(cursorPosition + 1, end - 1))
        return true
    }

    mutating func typeCharacter(
        _ character: Character,
        insertMode: Bool = false
    ) -> TerminalCharacterInputResult {
        guard let fieldIndex = editableFieldIndex(at: cursorPosition) else {
            return .rejected(.notInEditableField)
        }
        let field = fields[fieldIndex]
        guard field.inputDataRange.contains(cursorPosition),
              field.normalizedKeyboardCharacter(character) != nil else {
            return .rejected(.characterRejected)
        }
        let positionBeforeInsert = cursorPosition
        guard replaceCharacter(character, insertMode: insertMode) else {
            return .rejected(insertMode ? .insertOverflow : .characterRejected)
        }

        let lastDataPosition = field.inputDataRange.upperBound - 1
        if field.adjustment.rightFillCharacter != nil || field.inputType == .signedNumeric {
            fields[fieldIndex].isFieldExitPending = true
        } else if field.requiresFieldExit && positionBeforeInsert == lastDataPosition {
            fields[fieldIndex].isFieldExitPending = true
        }
        guard positionBeforeInsert == lastDataPosition else { return .accepted }

        if field.isForwardEdgeTrigger || field.autoEnter {
            if field.inputType == .signedNumeric {
                let signPosition = field.start + field.length - 1
                cells[signPosition].character = " "
                cells[signPosition].isNull = true
                cells[signPosition].inputByteOverride = nil
                fields[fieldIndex].isNegative = false
            }
            fields[fieldIndex].isFieldExitPending = false
            return field.isForwardEdgeTrigger ? .forwardEdgeTrigger : .autoEnter
        }
        if field.requiresExplicitFieldExit { return .accepted }

        _ = moveToNextInputFieldUnchecked()
        return .advanced
    }

    mutating func prepareForAID(_ aid: UInt8) -> TerminalAIDPreparationResult {
        guard aidCarriesFieldData(aid) else {
            clearCurrentFieldExitPending()
            return .ready
        }

        let isEnterLikeAID = aid == TN5250AID.enter.rawValue
            || aid == TN5250AID.forwardEdgeTrigger.rawValue

        if isEnterLikeAID,
           let missing = sortedEditableFieldIndices.first(where: {
               fields[$0].requiresInput && !fields[$0].modified
           }) {
            return .rejected(.mandatoryEntry(field: editableFieldOrdinal(for: missing)))
        }

        if let incomplete = sortedEditableFieldIndices.first(where: {
            fields[$0].adjustment == .mandatoryFill
                && fields[$0].modified
                && !fieldIsComplete($0)
        }) {
            return .rejected(.mandatoryFill(field: editableFieldOrdinal(for: incomplete)))
        }

        if isEnterLikeAID,
           let current = editableFieldIndex(at: cursorPosition),
           fields[current].isFieldExitPending,
           fields[current].adjustment.rightFillCharacter != nil || fields[current].inputType == .signedNumeric {
            return .rejected(.fieldExitRequired(field: editableFieldOrdinal(for: current)))
        }

        clearCurrentFieldExitPending()
        return .ready
    }

    mutating func pasteText(_ text: String, insertMode: Bool = false) -> TerminalPasteResult {
        guard ensureCursorInInputField() || editableFieldIndex(at: cursorPosition) != nil else {
            return TerminalPasteResult(insertedCharacters: 0, skippedCharacters: text.count, fieldsTouched: 0)
        }

        var inserted = 0
        var skipped = 0
        var touched = Set<UUID>()
        var advanceBeforeNextCharacter = false
        var heldAtForwardEdgeTrigger = false
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for character in normalized {
            if heldAtForwardEdgeTrigger {
                skipped += 1
                continue
            }
            if character == "\t" || character == "\n" {
                if !moveToNextInputField() { skipped += 1 }
                advanceBeforeNextCharacter = false
                continue
            }
            if advanceBeforeNextCharacter {
                _ = moveToNextInputField()
                advanceBeforeNextCharacter = false
            }
            guard !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  let fieldIndex = editableFieldIndex(at: cursorPosition) else {
                skipped += 1
                continue
            }
            let field = fields[fieldIndex]
            let positionBeforeInsert = cursorPosition
            if replaceCharacter(character, insertMode: insertMode) {
                inserted += 1
                touched.insert(field.id)
                if field.isForwardEdgeTrigger,
                   positionBeforeInsert == field.inputDataRange.upperBound - 1 {
                    // Bulk paste never generates an automatic AID. Hold the
                    // cursor at the FET edge so Field Exit remains an explicit,
                    // usable submission action; skip all remaining paste text.
                    heldAtForwardEdgeTrigger = true
                    advanceBeforeNextCharacter = false
                } else {
                    advanceBeforeNextCharacter = positionBeforeInsert == field.start + field.length - 1
                }
            } else {
                skipped += 1
            }
        }
        return TerminalPasteResult(
            insertedCharacters: inserted,
            skippedCharacters: skipped,
            fieldsTouched: touched.count
        )
    }
}

private extension TerminalScreen {
    var cursorPosition: Int { cursor.row * columns + cursor.column }

    var sortedEditableFields: [TerminalField] {
        fields.filter { !$0.isProtected }.sorted { $0.start < $1.start }
    }

    var sortedEditableFieldIndices: [Int] {
        fields.indices.filter { !fields[$0].isProtected }.sorted { fields[$0].start < fields[$1].start }
    }

    func editableFieldIndex(at position: Int) -> Int? {
        fields.firstIndex { !$0.isProtected && $0.contains(position) }
    }

    mutating func move(to position: Int) {
        moveCursor(row: position / columns, column: position % columns)
    }

    mutating func clear(range: Range<Int>, fieldIndex: Int) {
        for position in range where cells.indices.contains(position) {
            cells[position].character = " "
            cells[position].isNull = true
            cells[position].inputByteOverride = nil
        }
        fields[fieldIndex].modified = true
        fields[fieldIndex].isFieldExitPending = false
        fields[fieldIndex].isNegative = false
    }

    func editableFieldOrdinal(for fieldIndex: Int) -> Int {
        (sortedEditableFieldIndices.firstIndex(of: fieldIndex) ?? 0) + 1
    }

    func fieldIsComplete(_ fieldIndex: Int) -> Bool {
        fields[fieldIndex].inputDataRange.allSatisfy { cells.indices.contains($0) && !cells[$0].isNull }
    }

    func movementIssue(leaving fieldIndex: Int) -> TerminalInputIssue? {
        let field = fields[fieldIndex]
        guard field.adjustment == .mandatoryFill, field.modified, !fieldIsComplete(fieldIndex) else {
            return nil
        }
        return .mandatoryFill(field: editableFieldOrdinal(for: fieldIndex))
    }

    mutating func prepareForCursorMove(to destination: Int) -> Bool {
        guard let current = editableFieldIndex(at: cursorPosition),
              !fields[current].contains(destination) else { return true }
        guard movementIssue(leaving: current) == nil else { return false }
        fields[current].isFieldExitPending = false
        return true
    }

    mutating func clearCurrentFieldExitPending() {
        guard let current = editableFieldIndex(at: cursorPosition) else { return }
        fields[current].isFieldExitPending = false
    }

    @discardableResult
    mutating func moveToNextInputFieldUnchecked() -> Bool {
        let inputFields = sortedEditableFields
        guard !inputFields.isEmpty else { return false }
        let next = inputFields.first(where: { $0.start > cursorPosition }) ?? inputFields[0]
        move(to: next.start)
        return true
    }

    mutating func rightAdjust(fieldIndex: Int, fill: Character) {
        let field = fields[fieldIndex]
        let dataRange = field.inputDataRange
        guard !dataRange.isEmpty else { return }
        let lastDataPosition = dataRange.upperBound - 1
        let boundary: Int
        if cursorPosition >= dataRange.upperBound {
            boundary = dataRange.upperBound
        } else if cursorPosition == lastDataPosition, !cells[lastDataPosition].isNull {
            boundary = dataRange.upperBound
        } else {
            boundary = max(dataRange.lowerBound, cursorPosition)
        }

        let firstDataPosition = (dataRange.lowerBound..<boundary).first(where: { !cells[$0].isNull })
        let content = firstDataPosition.map { start in
            (start..<boundary).map { position in
                TerminalCellInputContent(
                    character: cells[position].character,
                    isNull: cells[position].isNull,
                    byteOverride: cells[position].inputByteOverride
                )
            }
        } ?? []

        for position in dataRange {
            cells[position].character = " "
            cells[position].isNull = true
            cells[position].inputByteOverride = nil
        }
        guard !content.isEmpty else {
            fields[fieldIndex].modified = true
            return
        }

        let destinationStart = dataRange.upperBound - content.count
        if destinationStart > dataRange.lowerBound {
            for position in dataRange.lowerBound..<destinationStart {
                cells[position].character = fill
                cells[position].isNull = false
            }
        }
        for (offset, value) in content.enumerated() {
            let position = destinationStart + offset
            cells[position].character = value.character
            cells[position].isNull = value.isNull
            cells[position].inputByteOverride = value.byteOverride
        }
        fields[fieldIndex].modified = true
    }

    func isASCIIDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        return (0x30...0x39).contains(scalar.value)
    }

    func distance(from position: Int, to field: TerminalField) -> Int {
        if field.contains(position) { return 0 }
        if position < field.start { return field.start - position }
        return position - (field.start + field.length - 1)
    }

    func horizontalDistance(fromColumn column: Int, to field: TerminalField, onRow row: Int) -> Int {
        let rowStart = row * columns
        let lower = max(field.start, rowStart) - rowStart
        let upper = min(field.start + field.length - 1, rowStart + columns - 1) - rowStart
        if (lower...upper).contains(column) { return 0 }
        return min(abs(column - lower), abs(column - upper))
    }
}

private struct TerminalCellInputContent {
    let character: Character
    let isNull: Bool
    let byteOverride: UInt8?
}
