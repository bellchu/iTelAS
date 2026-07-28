import Foundation

public enum TerminalColor: String, Codable, CaseIterable, Sendable {
    case green
    case white
    case red
    case turquoise
    case yellow
    case pink
    case blue
    case neutral
    case black
}

public struct TerminalAttributes: Codable, Equatable, Sendable {
    public var foreground: TerminalColor
    public var reverse: Bool
    public var underline: Bool
    public var blink: Bool
    public var highIntensity: Bool
    public var columnSeparator: Bool
    public var nonDisplay: Bool
    public var protected: Bool

    public init(
        foreground: TerminalColor = .green,
        reverse: Bool = false,
        underline: Bool = false,
        blink: Bool = false,
        highIntensity: Bool = false,
        columnSeparator: Bool = false,
        nonDisplay: Bool = false,
        protected: Bool = true
    ) {
        self.foreground = foreground
        self.reverse = reverse
        self.underline = underline
        self.blink = blink
        self.highIntensity = highIntensity
        self.columnSeparator = columnSeparator
        self.nonDisplay = nonDisplay
        self.protected = protected
    }

    private enum CodingKeys: String, CodingKey {
        case foreground
        case reverse
        case underline
        case blink
        case highIntensity
        case columnSeparator
        case nonDisplay
        case protected
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        foreground = try container.decode(TerminalColor.self, forKey: .foreground)
        reverse = try container.decode(Bool.self, forKey: .reverse)
        underline = try container.decode(Bool.self, forKey: .underline)
        blink = try container.decode(Bool.self, forKey: .blink)
        highIntensity = try container.decodeIfPresent(Bool.self, forKey: .highIntensity) ?? false
        columnSeparator = try container.decode(Bool.self, forKey: .columnSeparator)
        nonDisplay = try container.decode(Bool.self, forKey: .nonDisplay)
        protected = try container.decode(Bool.self, forKey: .protected)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(foreground, forKey: .foreground)
        try container.encode(reverse, forKey: .reverse)
        try container.encode(underline, forKey: .underline)
        try container.encode(blink, forKey: .blink)
        try container.encode(highIntensity, forKey: .highIntensity)
        try container.encode(columnSeparator, forKey: .columnSeparator)
        try container.encode(nonDisplay, forKey: .nonDisplay)
        try container.encode(protected, forKey: .protected)
    }
}

public struct TerminalCell: Equatable, Sendable {
    public var character: Character
    public var attributes: TerminalAttributes
    /// A 5250 null (X'00') and an EBCDIC blank (X'40') look identical, but
    /// field validation and inbound read formatting treat them differently.
    public var isNull: Bool
    var screenAttributes: TerminalAttributes
    /// Some workstation keys place a control value in the input buffer while
    /// showing a friendlier glyph on screen (for example, Dup/X'1C').
    var inputByteOverride: UInt8?

    public init(
        character: Character = " ",
        attributes: TerminalAttributes = .init(),
        isNull: Bool? = nil
    ) {
        let storesNull = isNull ?? (character == "\0")
        self.character = storesNull ? " " : character
        self.attributes = attributes
        self.isNull = storesNull
        self.screenAttributes = attributes
        self.inputByteOverride = nil
    }
}

private struct TerminalExtendedPrimaryAttributes: Equatable, Sendable {
    let columnSeparator: Bool
    let blink: Bool
    let underline: Bool
    let highIntensity: Bool
    let reverse: Bool

    init(byte: UInt8) {
        columnSeparator = byte & 0x10 != 0
        blink = byte & 0x08 != 0
        underline = byte & 0x04 != 0
        highIntensity = byte & 0x02 != 0
        reverse = byte & 0x01 != 0
    }
}

private enum TerminalExtendedPrimaryChange: Equatable, Sendable {
    case screenAttributes
    case extended(TerminalExtendedPrimaryAttributes)
}

private enum TerminalExtendedColorChange: Equatable, Sendable {
    case screenAttributes
    case color(TerminalColor)
}

public struct TerminalCursor: Codable, Equatable, Sendable {
    public var row: Int
    public var column: Int
    public var isVisible: Bool
    public var isBlinking: Bool

    public init(
        row: Int = 0,
        column: Int = 0,
        isVisible: Bool = true,
        isBlinking: Bool = false
    ) {
        self.row = row
        self.column = column
        self.isVisible = isVisible
        self.isBlinking = isBlinking
    }

    private enum CodingKeys: String, CodingKey {
        case row
        case column
        case isVisible
        case isBlinking
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        row = try container.decode(Int.self, forKey: .row)
        column = try container.decode(Int.self, forKey: .column)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        isBlinking = try container.decodeIfPresent(Bool.self, forKey: .isBlinking) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(row, forKey: .row)
        try container.encode(column, forKey: .column)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(isBlinking, forKey: .isBlinking)
    }
}

public enum TerminalFieldInputType: String, Codable, CaseIterable, Sendable {
    case alphabeticShift
    case alphabeticOnly
    case numericShift
    case numericOnly
    case katakanaShift
    case digitsOnly
    case ioOnly
    case signedNumeric

    init(rawFFWValue: UInt8) {
        switch rawFFWValue & 0x07 {
        case 0: self = .alphabeticShift
        case 1: self = .alphabeticOnly
        case 2: self = .numericShift
        case 3: self = .numericOnly
        case 4: self = .katakanaShift
        case 5: self = .digitsOnly
        case 6: self = .ioOnly
        default: self = .signedNumeric
        }
    }

    public var label: String {
        switch self {
        case .alphabeticShift: "ALPHA SHIFT"
        case .alphabeticOnly: "ALPHA ONLY"
        case .numericShift: "NUMERIC SHIFT"
        case .numericOnly: "NUMERIC ONLY"
        case .katakanaShift: "KATAKANA SHIFT"
        case .digitsOnly: "DIGITS ONLY"
        case .ioOnly: "I/O ONLY"
        case .signedNumeric: "SIGNED NUMERIC"
        }
    }

    public var isNumericConstrained: Bool {
        switch self {
        case .numericOnly, .digitsOnly, .signedNumeric: true
        default: false
        }
    }

    fileprivate func accepts(_ character: Character) -> Bool {
        let scalar = character.unicodeScalars.count == 1 ? character.unicodeScalars.first : nil
        let isASCIIDigit = scalar.map { (0x30...0x39).contains($0.value) } ?? false
        return switch self {
        case .alphabeticShift, .numericShift, .katakanaShift:
            true
        case .alphabeticOnly:
            character.isLetter || ",.- ".contains(character)
        case .numericOnly:
            isASCIIDigit || ",.-+ ".contains(character)
        case .digitsOnly, .signedNumeric:
            isASCIIDigit
        case .ioOnly:
            false
        }
    }
}

public enum TerminalFieldAdjustment: String, Codable, Sendable {
    case none
    case centerZeroFill
    case centerBlankFill
    case mandatoryFill

    init(rawFFWValue: UInt8) {
        switch rawFFWValue & 0x07 {
        case 5: self = .centerZeroFill
        case 6: self = .centerBlankFill
        case 7: self = .mandatoryFill
        default: self = .none
        }
    }

    public var label: String? {
        switch self {
        case .none: nil
        case .centerZeroFill: "RIGHT ZERO-FILL"
        case .centerBlankFill: "RIGHT BLANK-FILL"
        case .mandatoryFill: "MANDATORY FILL"
        }
    }

    var rightFillCharacter: Character? {
        switch self {
        case .centerZeroFill: "0"
        case .centerBlankFill: " "
        case .none, .mandatoryFill: nil
        }
    }
}

public struct TerminalField: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: Int
    public var length: Int
    public var isProtected: Bool
    public var isNonDisplay: Bool
    public var inputType: TerminalFieldInputType
    public var allowsDuplication: Bool
    public var autoEnter: Bool
    public var requiresFieldExit: Bool
    public var isMonocase: Bool
    public var requiresInput: Bool
    public var adjustment: TerminalFieldAdjustment
    /// True for fields backed by a field-format word. IBM numbers these
    /// format-table entries for read resequencing, including bypass fields;
    /// output-only fields are not part of that sequence.
    public var isEntryField: Bool
    /// X'80nn' field-control word. `nil` means the next field in normal
    /// sequence and X'FF' terminates an active resequencing chain.
    public var readResequenceNextField: UInt8?
    /// X'84xx' field-control word. Transparent input is returned without
    /// null conversion, trimming, or character formatting.
    public var isTransparent: Bool
    /// X'8501' field-control word. It performs Auto Enter behavior but
    /// returns the distinct Forward Edge Trigger AID X'50'.
    public var isForwardEdgeTrigger: Bool
    public var modified: Bool
    /// Runtime workstation state. It is set after an edit that must be
    /// completed with a nondata or field-exit key and reset by the host.
    public var isFieldExitPending: Bool
    /// Field Minus for numeric-only fields is represented by D-zoning the
    /// low-order digit when input is encoded; the display still shows a digit.
    public var isNegative: Bool

    public var isNumericOnly: Bool { inputType.isNumericConstrained }

    public init(
        id: UUID = UUID(),
        start: Int,
        length: Int,
        isProtected: Bool,
        isNonDisplay: Bool = false,
        isNumericOnly: Bool = false,
        inputType: TerminalFieldInputType? = nil,
        allowsDuplication: Bool = false,
        autoEnter: Bool = false,
        requiresFieldExit: Bool = false,
        isMonocase: Bool = false,
        requiresInput: Bool = false,
        adjustment: TerminalFieldAdjustment = .none,
        isEntryField: Bool = true,
        readResequenceNextField: UInt8? = nil,
        isTransparent: Bool = false,
        isForwardEdgeTrigger: Bool = false,
        modified: Bool = false,
        isFieldExitPending: Bool = false,
        isNegative: Bool = false
    ) {
        self.id = id
        self.start = start
        self.length = length
        self.isProtected = isProtected
        self.isNonDisplay = isNonDisplay
        self.inputType = inputType ?? (isNumericOnly ? .digitsOnly : .alphabeticShift)
        self.allowsDuplication = allowsDuplication
        self.autoEnter = autoEnter
        self.requiresFieldExit = requiresFieldExit
        self.isMonocase = isMonocase
        self.requiresInput = requiresInput
        self.adjustment = adjustment
        self.isEntryField = isEntryField
        self.readResequenceNextField = readResequenceNextField
        self.isTransparent = isTransparent
        self.isForwardEdgeTrigger = isForwardEdgeTrigger
        self.modified = modified
        self.isFieldExitPending = isFieldExitPending
        self.isNegative = isNegative
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case start
        case length
        case isProtected
        case isNonDisplay
        case isNumericOnly
        case inputType
        case allowsDuplication
        case autoEnter
        case requiresFieldExit
        case isMonocase
        case requiresInput
        case adjustment
        case isEntryField
        case readResequenceNextField
        case isTransparent
        case isForwardEdgeTrigger
        case modified
        case isFieldExitPending
        case isNegative
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        start = try container.decode(Int.self, forKey: .start)
        length = try container.decode(Int.self, forKey: .length)
        isProtected = try container.decode(Bool.self, forKey: .isProtected)
        isNonDisplay = try container.decodeIfPresent(Bool.self, forKey: .isNonDisplay) ?? false
        let legacyNumericOnly = try container.decodeIfPresent(Bool.self, forKey: .isNumericOnly) ?? false
        inputType = try container.decodeIfPresent(TerminalFieldInputType.self, forKey: .inputType)
            ?? (legacyNumericOnly ? .digitsOnly : .alphabeticShift)
        allowsDuplication = try container.decodeIfPresent(Bool.self, forKey: .allowsDuplication) ?? false
        autoEnter = try container.decodeIfPresent(Bool.self, forKey: .autoEnter) ?? false
        requiresFieldExit = try container.decodeIfPresent(Bool.self, forKey: .requiresFieldExit) ?? false
        isMonocase = try container.decodeIfPresent(Bool.self, forKey: .isMonocase) ?? false
        requiresInput = try container.decodeIfPresent(Bool.self, forKey: .requiresInput) ?? false
        adjustment = try container.decodeIfPresent(TerminalFieldAdjustment.self, forKey: .adjustment) ?? .none
        isEntryField = try container.decodeIfPresent(Bool.self, forKey: .isEntryField) ?? true
        readResequenceNextField = try container.decodeIfPresent(UInt8.self, forKey: .readResequenceNextField)
        isTransparent = try container.decodeIfPresent(Bool.self, forKey: .isTransparent) ?? false
        isForwardEdgeTrigger = try container.decodeIfPresent(Bool.self, forKey: .isForwardEdgeTrigger) ?? false
        modified = try container.decodeIfPresent(Bool.self, forKey: .modified) ?? false
        isFieldExitPending = try container.decodeIfPresent(Bool.self, forKey: .isFieldExitPending) ?? false
        isNegative = try container.decodeIfPresent(Bool.self, forKey: .isNegative) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(start, forKey: .start)
        try container.encode(length, forKey: .length)
        try container.encode(isProtected, forKey: .isProtected)
        try container.encode(isNonDisplay, forKey: .isNonDisplay)
        try container.encode(isNumericOnly, forKey: .isNumericOnly)
        try container.encode(inputType, forKey: .inputType)
        try container.encode(allowsDuplication, forKey: .allowsDuplication)
        try container.encode(autoEnter, forKey: .autoEnter)
        try container.encode(requiresFieldExit, forKey: .requiresFieldExit)
        try container.encode(isMonocase, forKey: .isMonocase)
        try container.encode(requiresInput, forKey: .requiresInput)
        try container.encode(adjustment, forKey: .adjustment)
        try container.encode(isEntryField, forKey: .isEntryField)
        try container.encodeIfPresent(readResequenceNextField, forKey: .readResequenceNextField)
        try container.encode(isTransparent, forKey: .isTransparent)
        try container.encode(isForwardEdgeTrigger, forKey: .isForwardEdgeTrigger)
        try container.encode(modified, forKey: .modified)
        try container.encode(isFieldExitPending, forKey: .isFieldExitPending)
        try container.encode(isNegative, forKey: .isNegative)
    }

    public func contains(_ position: Int) -> Bool {
        position >= start && position < start + length
    }

    public var inputDataRange: Range<Int> {
        let end = start + max(0, length - (inputType == .signedNumeric ? 1 : 0))
        return start..<end
    }

    public var requiresExplicitFieldExit: Bool {
        requiresFieldExit || adjustment.rightFillCharacter != nil || inputType == .signedNumeric
    }

    public func normalizedKeyboardCharacter(_ character: Character) -> Character? {
        guard !isProtected, inputType.accepts(character) else { return nil }
        guard isMonocase, character.isLetter else { return character }
        let uppercase = String(character).uppercased()
        guard uppercase.count == 1 else { return nil }
        return uppercase.first
    }
}

public enum TerminalReadMode: String, Codable, Equatable, Sendable {
    case inputFields
    case modifiedFields
    case modifiedFieldsAlternate

    public var label: String {
        switch self {
        case .inputFields: "READ INPUT"
        case .modifiedFields: "READ MDT"
        case .modifiedFieldsAlternate: "READ MDT ALT"
        }
    }
}

public struct TerminalScreen: Equatable, Sendable {
    public private(set) var rows: Int
    public private(set) var columns: Int
    public var cells: [TerminalCell]
    public var fields: [TerminalField]
    public var cursor: TerminalCursor
    public var homeCursorPosition: Int?
    public var inputInhibited: Bool
    public var messageWaiting: Bool
    /// The most recent host input command controls how the next AID response
    /// formats field data. Read MDT is the power-on/default workstation mode.
    public var readMode: TerminalReadMode
    /// SOH byte 3. Zero selects normal screen order; otherwise it is the
    /// one-based format-table entry that begins the host-defined read chain.
    public var readResequenceStartField: UInt8
    /// One bit per F1...F24. A set bit permits field data to accompany that
    /// function-key AID. The wire-level SOH switches use the inverse meaning.
    public var functionKeyDataInclusionMask: UInt32
    /// Monotonic event marker used by the native presentation layer. It carries
    /// no host data and lets repeated 5250 alarm requests remain observable.
    public var audibleAlarmSequence: UInt64
    private var extendedPrimaryChanges: [TerminalExtendedPrimaryChange?]
    private var extendedColorChanges: [TerminalExtendedColorChange?]

    public init(rows: Int = 24, columns: Int = 80) {
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.cells = Array(repeating: TerminalCell(isNull: true), count: self.rows * self.columns)
        self.fields = []
        self.cursor = TerminalCursor()
        self.homeCursorPosition = nil
        self.inputInhibited = true
        self.messageWaiting = false
        self.readMode = .modifiedFields
        self.readResequenceStartField = 0
        self.functionKeyDataInclusionMask = 0x00FF_FFFF
        self.audibleAlarmSequence = 0
        self.extendedPrimaryChanges = Array(repeating: nil, count: self.rows * self.columns)
        self.extendedColorChanges = Array(repeating: nil, count: self.rows * self.columns)
    }

    public func index(row: Int, column: Int) -> Int? {
        guard (0..<rows).contains(row), (0..<columns).contains(column) else { return nil }
        return row * columns + column
    }

    public func rowText(_ row: Int, revealNonDisplay: Bool = false) -> String {
        guard (0..<rows).contains(row) else { return "" }
        let start = row * columns
        return String(cells[start..<(start + columns)].map { cell in
            cell.attributes.nonDisplay && !revealNonDisplay ? " " : cell.character
        })
    }

    public func visibleText(redactingSensitive: Bool = true) -> String {
        (0..<rows).map { row in
            let text = rowText(row)
            guard redactingSensitive else { return text }
            let upper = text.uppercased()
            let sensitiveLabels = ["PASSWORD", "PASSWD", "API KEY", "TOKEN", "SECRET"]
            if sensitiveLabels.contains(where: upper.contains) {
                let prefix = text.prefix(while: { $0 != ":" && $0 != ">" })
                return "\(prefix): [REDACTED]"
            }
            return text
        }.joined(separator: "\n")
    }

    public func functionKeyCarriesFieldData(_ number: Int) -> Bool {
        guard (1...24).contains(number) else { return false }
        return functionKeyDataInclusionMask & (UInt32(1) << UInt32(number - 1)) != 0
    }

    public func aidCarriesFieldData(_ aid: UInt8) -> Bool {
        guard TN5250AID.carriesModifiedFields(aid) else { return false }
        guard let functionNumber = TN5250AID.functionNumber(for: aid) else { return true }
        return functionKeyCarriesFieldData(functionNumber)
    }

    public mutating func clear(rows newRows: Int? = nil, columns newColumns: Int? = nil) {
        rows = max(1, newRows ?? rows)
        columns = max(1, newColumns ?? columns)
        cells = Array(repeating: TerminalCell(isNull: true), count: rows * columns)
        fields.removeAll(keepingCapacity: true)
        cursor = TerminalCursor()
        homeCursorPosition = nil
        inputInhibited = true
        readMode = .modifiedFields
        readResequenceStartField = 0
        functionKeyDataInclusionMask = 0x00FF_FFFF
        extendedPrimaryChanges = Array(repeating: nil, count: rows * columns)
        extendedColorChanges = Array(repeating: nil, count: rows * columns)
    }

    public mutating func write(
        _ text: String,
        row: Int,
        column: Int,
        attributes: TerminalAttributes = .init()
    ) {
        guard var position = index(row: row, column: column) else { return }
        for character in text where position < cells.count {
            let storesNull = character == "\0"
            cells[position].character = storesNull ? " " : character
            cells[position].isNull = storesNull
            cells[position].inputByteOverride = nil
            cells[position].screenAttributes = attributes
            refreshEffectiveAttributes(at: position)
            position += 1
        }
    }

    public mutating func write(_ character: Character, at position: Int, attributes: TerminalAttributes) {
        guard cells.indices.contains(position) else { return }
        let storesNull = character == "\0"
        cells[position].character = storesNull ? " " : character
        cells[position].isNull = storesNull
        cells[position].inputByteOverride = nil
        cells[position].screenAttributes = attributes
        refreshEffectiveAttributes(at: position)
    }

    mutating func writeTransparent(
        _ byte: UInt8,
        decodedCharacter: Character,
        at position: Int,
        attributes: TerminalAttributes
    ) {
        guard cells.indices.contains(position) else { return }
        cells[position].character = byte == 0 ? " " : decodedCharacter
        cells[position].isNull = byte == 0
        cells[position].inputByteOverride = byte
        cells[position].screenAttributes = attributes
        refreshEffectiveAttributes(at: position)
    }

    mutating func setScreenAttributes(_ attributes: TerminalAttributes, in range: Range<Int>) {
        let lowerBound = max(0, range.lowerBound)
        let upperBound = min(cells.count, range.upperBound)
        guard lowerBound < upperBound else { return }
        for position in lowerBound..<upperBound {
            cells[position].screenAttributes = attributes
            refreshEffectiveAttributes(at: position)
        }
    }

    @discardableResult
    mutating func writeExtendedPrimary(_ byte: UInt8, at position: Int) -> Bool {
        guard cells.indices.contains(position), byte == 0 || (0x80...0x9F).contains(byte) else {
            return false
        }
        switch byte {
        case 0:
            extendedPrimaryChanges[position] = nil
        case 0x80:
            extendedPrimaryChanges[position] = .screenAttributes
        default:
            extendedPrimaryChanges[position] = .extended(.init(byte: byte))
        }
        refreshEffectiveAttributes(startingAt: position)
        return true
    }

    @discardableResult
    mutating func writeExtendedColor(_ byte: UInt8, at position: Int) -> Bool {
        guard cells.indices.contains(position), byte == 0 || (0x80...0x8F).contains(byte) else {
            return false
        }
        switch byte {
        case 0:
            extendedColorChanges[position] = nil
        case 0x80:
            extendedColorChanges[position] = .screenAttributes
        case 0x81:
            extendedColorChanges[position] = .color(.black)
        case 0x82, 0x83:
            extendedColorChanges[position] = .color(.blue)
        case 0x84, 0x85:
            extendedColorChanges[position] = .color(.green)
        case 0x86, 0x87:
            extendedColorChanges[position] = .color(.turquoise)
        case 0x88, 0x89:
            extendedColorChanges[position] = .color(.red)
        case 0x8A, 0x8B:
            extendedColorChanges[position] = .color(.pink)
        case 0x8C, 0x8D:
            extendedColorChanges[position] = .color(.yellow)
        default:
            extendedColorChanges[position] = .color(.white)
        }
        refreshEffectiveAttributes(startingAt: position)
        return true
    }

    @discardableResult
    mutating func erasePresentation(
        in range: ClosedRange<Int>,
        attributeTypes: [UInt8]
    ) -> Bool {
        guard cells.indices.contains(range.lowerBound),
              cells.indices.contains(range.upperBound),
              range.lowerBound <= range.upperBound,
              !attributeTypes.isEmpty,
              attributeTypes.allSatisfy({ [0x00, 0x01, 0x03, 0xFF].contains($0) }) else {
            return false
        }
        let clearAll = attributeTypes.contains(0xFF)
        if clearAll || attributeTypes.contains(0x00) {
            for position in range {
                cells[position].character = " "
                cells[position].isNull = true
                cells[position].inputByteOverride = nil
                cells[position].screenAttributes = TerminalAttributes()
            }
        }
        if clearAll || attributeTypes.contains(0x01) {
            for position in range { extendedPrimaryChanges[position] = nil }
        }
        if clearAll || attributeTypes.contains(0x03) {
            for position in range { extendedColorChanges[position] = nil }
        }
        refreshEffectiveAttributes(startingAt: range.lowerBound)
        return true
    }

    mutating func refreshPresentation() {
        refreshEffectiveAttributes(startingAt: 0)
    }

    public mutating func moveCursor(row: Int, column: Int) {
        cursor.row = min(max(row, 0), rows - 1)
        cursor.column = min(max(column, 0), columns - 1)
    }

    public mutating func setHomeCursor(position: Int) {
        guard cells.indices.contains(position) else { return }
        homeCursorPosition = position
    }

    @discardableResult
    public mutating func moveCursorHome() -> Bool {
        guard let homeCursorPosition, cells.indices.contains(homeCursorPosition) else { return false }
        moveCursor(
            row: homeCursorPosition / columns,
            column: homeCursorPosition % columns
        )
        return true
    }

    public mutating func replaceCharacter(_ character: Character) -> Bool {
        guard let position = index(row: cursor.row, column: cursor.column),
              let fieldIndex = fields.firstIndex(where: { $0.contains(position) && !$0.isProtected }) else {
            return false
        }
        let fieldEnd = fields[fieldIndex].inputDataRange.upperBound - 1
        guard position <= fieldEnd else { return false }
        guard let normalized = fields[fieldIndex].normalizedKeyboardCharacter(character) else { return false }
        cells[position].character = normalized
        cells[position].isNull = false
        cells[position].inputByteOverride = nil
        fields[fieldIndex].modified = true
        if fields[fieldIndex].adjustment.rightFillCharacter != nil
            || fields[fieldIndex].inputType == .signedNumeric
            || (fields[fieldIndex].requiresFieldExit && position == fieldEnd) {
            fields[fieldIndex].isFieldExitPending = true
        }
        let next = min(position + 1, fieldEnd)
        cursor.row = next / columns
        cursor.column = next % columns
        return true
    }

    /// Restores the workstation-style behavior expected by IBM i screens that
    /// unlock the keyboard without sending an explicit Insert Cursor order.
    /// A real 5250 device enters the first editable field instead of accepting
    /// keystrokes in a protected presentation cell.
    @discardableResult
    public mutating func ensureCursorInInputField() -> Bool {
        let currentPosition = cursor.row * columns + cursor.column
        if fields.contains(where: { !$0.isProtected && $0.contains(currentPosition) }) {
            return false
        }
        guard let firstInputField = fields
            .filter({ !$0.isProtected })
            .min(by: { $0.start < $1.start }) else {
            return false
        }
        moveCursor(
            row: firstInputField.start / columns,
            column: firstInputField.start % columns
        )
        return true
    }

    @discardableResult
    public mutating func deleteBackward() -> Bool {
        let currentPosition = cursor.row * columns + cursor.column
        guard let fieldIndex = fields.firstIndex(where: { $0.contains(currentPosition) && !$0.isProtected }) else {
            return false
        }
        let dataRange = fields[fieldIndex].inputDataRange
        guard !dataRange.isEmpty else { return false }
        let target = min(max(dataRange.lowerBound, currentPosition - 1), dataRange.upperBound - 1)
        cells[target].character = " "
        cells[target].isNull = true
        cells[target].inputByteOverride = nil
        fields[fieldIndex].modified = true
        if fields[fieldIndex].adjustment.rightFillCharacter != nil
            || fields[fieldIndex].inputType == .signedNumeric {
            fields[fieldIndex].isFieldExitPending = true
        }
        cursor.row = target / columns
        cursor.column = target % columns
        return true
    }

    private func extendedPrimary(at position: Int) -> TerminalExtendedPrimaryAttributes? {
        guard extendedPrimaryChanges.indices.contains(position) else { return nil }
        for candidate in stride(from: position, through: 0, by: -1) {
            guard let change = extendedPrimaryChanges[candidate] else { continue }
            switch change {
            case .screenAttributes: return nil
            case .extended(let attributes): return attributes
            }
        }
        return nil
    }

    private func extendedColor(at position: Int) -> TerminalColor? {
        guard extendedColorChanges.indices.contains(position) else { return nil }
        for candidate in stride(from: position, through: 0, by: -1) {
            guard let change = extendedColorChanges[candidate] else { continue }
            switch change {
            case .screenAttributes: return nil
            case .color(let color): return color
            }
        }
        return nil
    }

    private func composedAttributes(
        at position: Int,
        extendedPrimary primary: TerminalExtendedPrimaryAttributes?,
        extendedColor color: TerminalColor?
    ) -> TerminalAttributes {
        var result = cells[position].screenAttributes
        if let primary {
            result.columnSeparator = primary.columnSeparator
            result.blink = primary.blink
            result.underline = primary.underline
            result.highIntensity = primary.highIntensity
            result.reverse = primary.reverse
        }
        if let color {
            result.foreground = color
        }
        if let field = fields.first(where: { $0.contains(position) }) {
            result.protected = field.isProtected
            result.nonDisplay = field.isNonDisplay
        }
        return result
    }

    private mutating func refreshEffectiveAttributes(at position: Int) {
        guard cells.indices.contains(position) else { return }
        cells[position].attributes = composedAttributes(
            at: position,
            extendedPrimary: extendedPrimary(at: position),
            extendedColor: extendedColor(at: position)
        )
    }

    private mutating func refreshEffectiveAttributes(startingAt position: Int) {
        guard !cells.isEmpty else { return }
        let start = max(0, position)
        var primary = start > 0 ? extendedPrimary(at: start - 1) : nil
        var color = start > 0 ? extendedColor(at: start - 1) : nil
        for candidate in start..<cells.count {
            if let change = extendedPrimaryChanges[candidate] {
                switch change {
                case .screenAttributes: primary = nil
                case .extended(let attributes): primary = attributes
                }
            }
            if let change = extendedColorChanges[candidate] {
                switch change {
                case .screenAttributes: color = nil
                case .color(let changedColor): color = changedColor
                }
            }
            cells[candidate].attributes = composedAttributes(
                at: candidate,
                extendedPrimary: primary,
                extendedColor: color
            )
        }
    }

    public static func welcome(rows: Int = 24, columns: Int = 80) -> TerminalScreen {
        var screen = TerminalScreen(rows: rows, columns: columns)
        screen.inputInhibited = false
        let title = TerminalAttributes(foreground: .turquoise, protected: true)
        let body = TerminalAttributes(foreground: .green, protected: true)
        let muted = TerminalAttributes(foreground: .white, protected: true)
        let center = max(1, (columns - 28) / 2)
        screen.write("iTelAS TN5250 WORKSPACE", row: 3, column: center, attributes: title)
        screen.write("Native Apple Silicon session core", row: 5, column: max(1, center - 3), attributes: muted)
        screen.write("No IBM i host is connected.", row: 9, column: max(1, center - 2), attributes: body)
        screen.write("Choose a saved system or create a secure TLS session.", row: 11, column: max(1, center - 14), attributes: body)
        screen.write("Command-K opens the universal IBM i command palette.", row: 14, column: max(1, center - 13), attributes: muted)
        screen.cursor = TerminalCursor(row: 17, column: max(1, center - 2), isVisible: false)
        return screen
    }
}
