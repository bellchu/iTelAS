import Foundation

public struct TN5250DataStreamParser: Sendable {
    private enum PendingCursorOrder: Sendable {
        case insert(Int)
        case move(Int)
    }

    private var codec: EBCDICCodec
    private var bufferPosition = 0
    private var attributes = TerminalAttributes()
    private var pendingCursorOrder: PendingCursorOrder?

    public init(ccsid: Int = 37) throws {
        codec = try EBCDICCodec(ccsid: ccsid)
    }

    public mutating func apply(_ record: TN5250Record, to screen: inout TerminalScreen) {
        switch record.opcode {
        case .messageLightOn:
            screen.messageWaiting = true
        case .messageLightOff:
            screen.messageWaiting = false
        case .cancelInvite:
            screen.inputInhibited = true
        case .invite:
            parseCommands([UInt8](record.payload), screen: &screen)
            screen.inputInhibited = false
            screen.ensureCursorInInputField()
        case .putGet:
            parseCommands([UInt8](record.payload), screen: &screen)
        case .outputOnly, .saveScreen, .restoreScreen, .readImmediate, .readScreen, .noOperation, .none:
            parseCommands([UInt8](record.payload), screen: &screen)
        }
    }

    private mutating func parseCommands(_ bytes: [UInt8], screen: inout TerminalScreen) {
        var offset = 0
        while offset < bytes.count {
            if bytes[offset] == 0x04, offset + 1 < bytes.count {
                let command = bytes[offset + 1]
                offset += 2
                switch command {
                case 0x40:
                    screen.clear(rows: 24, columns: 80)
                    bufferPosition = 0
                    attributes = TerminalAttributes()
                    pendingCursorOrder = nil
                case 0x20:
                    screen.clear(rows: 27, columns: 132)
                    bufferPosition = 0
                    attributes = TerminalAttributes()
                    pendingCursorOrder = nil
                case 0x11:
                    guard offset + 1 < bytes.count else {
                        offset = bytes.count
                        continue
                    }
                    let firstControl = bytes[offset]
                    let secondControl = bytes[offset + 1]
                    offset += 2
                    let keyboardWasUnlocked = !screen.inputInhibited
                    // IBM's WTD contract initializes the display address before
                    // processing orders. CC1 is immediate; CC2 is deferred until
                    // every order and data byte in this command has been applied.
                    bufferPosition = 0
                    pendingCursorOrder = nil
                    applyFirstWriteControl(firstControl, screen: &screen)
                    parseWriteOrders(bytes, offset: &offset, screen: &screen)
                    applySecondWriteControl(
                        secondControl,
                        keyboardWasUnlocked: keyboardWasUnlocked,
                        screen: &screen
                    )
                case 0x42, 0x52, 0x82:
                    // Read Input, Read MDT, and Read MDT Alternate each carry
                    // two control bytes. CC2's unlock bit is the workstation
                    // invitation boundary and must take effect before an AID
                    // can be entered. Other post-read control actions remain
                    // deferred so they cannot clear input before its reply.
                    guard offset + 1 < bytes.count else {
                        offset = bytes.count
                        continue
                    }
                    let secondControl = bytes[offset + 1]
                    screen.readMode = switch command {
                    case 0x42: .inputFields
                    case 0x82: .modifiedFieldsAlternate
                    default: .modifiedFields
                    }
                    offset += 2
                    applyKeyboardUnlock(
                        secondControl,
                        keyboardWasUnlocked: !screen.inputInhibited,
                        screen: &screen
                    )
                case 0xF3:
                    // Structured fields are capability negotiation and are handled by a later parser layer.
                    offset = bytes.count
                default:
                    continue
                }
            } else {
                offset += 1
            }
        }
    }

    private mutating func parseWriteOrders(_ bytes: [UInt8], offset: inout Int, screen: inout TerminalScreen) {
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            switch byte {
            case 0x01: // Start of Header: reset and define the format table header.
                guard offset < bytes.count else { return }
                let length = Int(bytes[offset])
                offset += 1
                guard (1...7).contains(length), offset + length <= bytes.count else { return }
                let header = Array(bytes[offset..<(offset + length)])
                offset += length
                screen.fields.removeAll(keepingCapacity: true)
                screen.readResequenceStartField = length >= 3 ? header[2] : 0
                if length == 7 {
                    // SOH bytes 5...7 are exclusion switches on the wire:
                    // bit 23 maps to F24 and bit 0 maps to F1.
                    let excluded = UInt32(header[4]) << 16
                        | UInt32(header[5]) << 8
                        | UInt32(header[6])
                    screen.functionKeyDataInclusionMask = (~excluded) & 0x00FF_FFFF
                } else {
                    screen.functionKeyDataInclusionMask = 0x00FF_FFFF
                }
                screen.refreshPresentation()
                screen.inputInhibited = true
            case 0x02: // Repeat to Address.
                guard offset + 2 < bytes.count else { return }
                guard let target = displayAddress(
                    row: bytes[offset],
                    column: bytes[offset + 1],
                    screen: screen
                ), bufferPosition >= 0, target >= bufferPosition else { return }
                let repeatedByte = bytes[offset + 2]
                offset += 3
                repeatByte(repeatedByte, through: target, screen: &screen)
            case 0x03: // Erase to Address.
                guard offset + 2 < bytes.count,
                      let target = displayAddress(
                          row: bytes[offset],
                          column: bytes[offset + 1],
                          screen: screen
                      ),
                      bufferPosition >= 0,
                      target >= bufferPosition else { return }
                let length = Int(bytes[offset + 2])
                let typeCount = length - 1
                let typesStart = offset + 3
                guard (2...5).contains(length),
                      typesStart + typeCount <= bytes.count else { return }
                let attributeTypes = Array(bytes[typesStart..<(typesStart + typeCount)])
                guard screen.erasePresentation(
                    in: bufferPosition...target,
                    attributeTypes: attributeTypes
                ) else { return }
                offset = typesStart + typeCount
                bufferPosition = target + 1
            case 0x04:
                offset -= 1
                return
            case 0x11: // Set Buffer Address, one-based row and column.
                guard offset + 1 < bytes.count else { return }
                guard let target = bufferAddress(
                    row: bytes[offset],
                    column: bytes[offset + 1],
                    screen: screen
                ) else { return }
                offset += 2
                bufferPosition = target
            case 0x13: // Insert Cursor takes effect only when CC2 unlocks the keyboard.
                guard offset + 1 < bytes.count else { return }
                guard let target = displayAddress(
                    row: bytes[offset],
                    column: bytes[offset + 1],
                    screen: screen
                ) else { return }
                offset += 2
                screen.setHomeCursor(position: target)
                pendingCursorOrder = .insert(target)
            case 0x14: // Move Cursor is applied after all WTD orders.
                guard offset + 1 < bytes.count else { return }
                guard let target = displayAddress(
                    row: bytes[offset],
                    column: bytes[offset + 1],
                    screen: screen
                ) else { return }
                offset += 2
                pendingCursorOrder = .move(target)
            case 0x10: // Transparent Data.
                guard offset + 1 < bytes.count else { return }
                let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
                offset += 2
                let end = offset + length
                guard end <= bytes.count,
                      bufferPosition >= 0,
                      bufferPosition + length <= screen.cells.count else { return }
                for transparentByte in bytes[offset..<end] {
                    writeTransparent(transparentByte, screen: &screen)
                }
                offset = end
            case 0x12: // Write Extended Attribute; this order does not advance the display address.
                guard offset + 1 < bytes.count else { return }
                let attributeType = bytes[offset]
                let value = bytes[offset + 1]
                guard screen.cells.indices.contains(bufferPosition) else { return }
                let accepted: Bool
                switch attributeType {
                case 0x01:
                    accepted = screen.writeExtendedPrimary(value, at: bufferPosition)
                case 0x03:
                    accepted = screen.writeExtendedColor(value, at: bufferPosition)
                default:
                    accepted = false
                }
                guard accepted else { return }
                offset += 2
            case 0x15: // Write to Display Structured Field.
                guard offset + 1 < bytes.count else { return }
                let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
                offset = min(bytes.count, offset + max(2, length))
            case 0x1D: // Start of Field.
                parseStartOfField(bytes, offset: &offset, screen: &screen)
            case 0x20...0x3F:
                attributes = Self.attributes(for: byte)
                writeAttribute(byte, screen: &screen)
            default:
                write(byte, screen: &screen)
            }
        }
    }

    private mutating func parseStartOfField(
        _ bytes: [UInt8],
        offset: inout Int,
        screen: inout TerminalScreen
    ) {
        guard offset < bytes.count else { return }
        let ffw1 = bytes[offset]
        offset += 1
        let hasFieldFormatWord = ffw1 & 0xC0 == 0x40
        var ffw2: UInt8 = 0
        var attributeByte = ffw1
        var isTransparent = false
        var isForwardEdgeTrigger = false
        var readResequenceNextField: UInt8?

        if hasFieldFormatWord {
            guard offset < bytes.count else { return }
            ffw2 = bytes[offset]
            offset += 1
            guard offset < bytes.count else { return }
            var candidate = bytes[offset]
            offset += 1

            // FCWs are two-byte pairs between the FFW and screen attribute.
            // X'80nn' defines the next field in a read resequencing chain and
            // X'84xx' makes the field transparent, and X'8501' requests the
            // distinct Forward Edge Trigger automatic AID.
            while !Self.isAttribute(candidate) {
                guard offset < bytes.count else { return }
                let fcwFirst = candidate
                let fcwSecond = bytes[offset]
                offset += 1
                if fcwFirst == 0x80, readResequenceNextField == nil {
                    readResequenceNextField = fcwSecond
                } else if fcwFirst == 0x84 {
                    isTransparent = true
                } else if fcwFirst == 0x85, fcwSecond == 0x01 {
                    isForwardEdgeTrigger = true
                }
                guard offset < bytes.count else { return }
                candidate = bytes[offset]
                offset += 1
            }
            attributeByte = candidate
        } else {
            guard Self.isAttribute(attributeByte) else { return }
        }

        guard offset + 1 < bytes.count else { return }
        let declaredLength = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        offset += 2

        attributes = Self.attributes(for: attributeByte)
        let isProtected = !hasFieldFormatWord || ffw1 & 0x20 != 0
        attributes.protected = isProtected

        let suppressStartingAttribute = bufferPosition == -1
        guard bufferPosition >= 0 || suppressStartingAttribute else { return }
        let fieldStart = suppressStartingAttribute ? 0 : bufferPosition + 1
        guard screen.cells.indices.contains(fieldStart) else { return }
        if suppressStartingAttribute, hasFieldFormatWord, attributes.nonDisplay {
            // RFC 1205 permits SBA(1,0)+SF for a row-1/column-1 field, but
            // explicitly forbids a non-display input field in that form.
            return
        }

        let existingIndex = screen.fields.firstIndex(where: { $0.start == fieldStart })
        let fieldLength = existingIndex.map { screen.fields[$0].length }
            ?? min(declaredLength, screen.cells.count - fieldStart)
        let inputType = TerminalFieldInputType(rawFFWValue: ffw1 & 0x07)
        if fieldLength == 0 || (inputType == .signedNumeric && fieldLength < 2) { return }

        if suppressStartingAttribute {
            bufferPosition = 0
        } else {
            writeAttribute(attributeByte, screen: &screen)
        }

        let existingField = existingIndex.map { screen.fields[$0] }
        let field = TerminalField(
            id: existingIndex.map { screen.fields[$0].id } ?? UUID(),
            start: fieldStart,
            length: fieldLength,
            isProtected: isProtected,
            isNonDisplay: attributes.nonDisplay,
            inputType: hasFieldFormatWord ? inputType : .alphabeticShift,
            allowsDuplication: hasFieldFormatWord && ffw1 & 0x10 != 0,
            autoEnter: hasFieldFormatWord && ffw2 & 0x80 != 0,
            requiresFieldExit: hasFieldFormatWord && ffw2 & 0x40 != 0,
            isMonocase: hasFieldFormatWord && ffw2 & 0x20 != 0,
            requiresInput: hasFieldFormatWord && ffw2 & 0x08 != 0,
            adjustment: hasFieldFormatWord
                ? TerminalFieldAdjustment(rawFFWValue: ffw2 & 0x07)
                : .none,
            isEntryField: hasFieldFormatWord,
            // IBM ignores FCWs supplied while redefining an existing field.
            readResequenceNextField: existingField?.readResequenceNextField
                ?? (hasFieldFormatWord ? readResequenceNextField : nil),
            isTransparent: existingField?.isTransparent
                ?? (hasFieldFormatWord && isTransparent),
            isForwardEdgeTrigger: existingField?.isForwardEdgeTrigger
                ?? (hasFieldFormatWord && isForwardEdgeTrigger),
            modified: hasFieldFormatWord && ffw1 & 0x08 != 0
        )
        if let existingIndex {
            screen.fields[existingIndex] = field
        } else {
            screen.fields.append(field)
        }
        if hasFieldFormatWord {
            screen.inputInhibited = true
        }

        screen.setScreenAttributes(attributes, in: fieldStart..<(fieldStart + fieldLength))
        if existingIndex == nil {
            let endingAttributePosition = fieldStart + fieldLength
            if screen.cells.indices.contains(endingAttributePosition) {
                var endingAttributes = Self.attributes(for: 0x20)
                endingAttributes.nonDisplay = true
                screen.write(" ", at: endingAttributePosition, attributes: endingAttributes)
            }
        }
    }

    private mutating func write(_ byte: UInt8, screen: inout TerminalScreen) {
        guard screen.cells.indices.contains(bufferPosition) else { return }
        screen.write(codec.decode(byte: byte), at: bufferPosition, attributes: attributes)
        bufferPosition += 1
    }

    private mutating func writeTransparent(_ byte: UInt8, screen: inout TerminalScreen) {
        guard screen.cells.indices.contains(bufferPosition) else { return }
        screen.writeTransparent(
            byte,
            decodedCharacter: codec.decode(byte: byte),
            at: bufferPosition,
            attributes: attributes
        )
        bufferPosition += 1
    }

    private mutating func writeAttribute(_ byte: UInt8, screen: inout TerminalScreen) {
        guard screen.cells.indices.contains(bufferPosition) else { return }
        var hiddenAttribute = Self.attributes(for: byte)
        hiddenAttribute.nonDisplay = true
        screen.write(" ", at: bufferPosition, attributes: hiddenAttribute)
        bufferPosition += 1
    }

    private func displayAddress(row: UInt8, column: UInt8, screen: TerminalScreen) -> Int? {
        guard (1...screen.rows).contains(Int(row)),
              (1...screen.columns).contains(Int(column)) else { return nil }
        return (Int(row) - 1) * screen.columns + Int(column) - 1
    }

    private func bufferAddress(row: UInt8, column: UInt8, screen: TerminalScreen) -> Int? {
        if row == 1, column == 0 { return -1 }
        return displayAddress(row: row, column: column, screen: screen)
    }

    private mutating func repeatByte(_ byte: UInt8, through target: Int, screen: inout TerminalScreen) {
        guard screen.cells.indices.contains(bufferPosition),
              screen.cells.indices.contains(target),
              bufferPosition <= target else { return }
        while bufferPosition <= target {
            write(byte, screen: &screen)
        }
    }

    private static func isAttribute(_ byte: UInt8) -> Bool {
        (0x20...0x3F).contains(byte)
    }

    public static func attributes(for byte: UInt8) -> TerminalAttributes {
        let reverse = [
            0x21, 0x23, 0x25,
            0x29, 0x2B, 0x2D,
            0x31, 0x33, 0x35,
            0x39, 0x3B, 0x3D
        ].contains(byte)
        let underline = [
            0x24, 0x25, 0x26,
            0x2C, 0x2D, 0x2E,
            0x34, 0x35, 0x36,
            0x3C, 0x3D, 0x3E
        ].contains(byte)
        let blink = [0x2A, 0x2B, 0x2E].contains(byte)
        let columnSeparator = (0x30...0x33).contains(byte)
        let color: TerminalColor
        switch byte {
        case 0x22, 0x23, 0x26: color = .white
        case 0x28...0x2E: color = .red
        case 0x30, 0x31, 0x34, 0x35: color = .turquoise
        case 0x32, 0x33, 0x36: color = .yellow
        case 0x38, 0x39, 0x3C, 0x3D: color = .pink
        case 0x3A, 0x3B, 0x3E: color = .blue
        default: color = .green
        }
        return TerminalAttributes(
            foreground: color,
            reverse: reverse,
            underline: underline,
            blink: blink,
            columnSeparator: columnSeparator,
            nonDisplay: [0x27, 0x2F, 0x37, 0x3F].contains(byte),
            protected: true
        )
    }

    private mutating func applyFirstWriteControl(_ byte: UInt8, screen: inout TerminalScreen) {
        // 5250 numbers bits from the high-order side. CC1's operation is in
        // bits 0...2; bits 3...7 are reserved and must all be zero.
        guard byte & 0x1F == 0 else { return }
        let operation = Int((byte & 0xE0) >> 5)
        guard operation != 0 else { return }

        screen.inputInhibited = true
        switch operation {
        case 1:
            break
        case 2:
            resetModifiedDataTags(includingProtectedFields: false, screen: &screen)
        case 3:
            resetModifiedDataTags(includingProtectedFields: true, screen: &screen)
        case 4:
            clearUnprotectedFields(onlyModified: true, screen: &screen)
        case 5:
            resetModifiedDataTags(includingProtectedFields: false, screen: &screen)
            clearUnprotectedFields(onlyModified: false, screen: &screen)
        case 6:
            clearUnprotectedFields(onlyModified: true, screen: &screen)
            resetModifiedDataTags(includingProtectedFields: false, screen: &screen)
        case 7:
            resetModifiedDataTags(includingProtectedFields: true, screen: &screen)
            clearUnprotectedFields(onlyModified: false, screen: &screen)
        default:
            break
        }
    }

    private mutating func applySecondWriteControl(
        _ byte: UInt8,
        keyboardWasUnlocked: Bool,
        screen: inout TerminalScreen
    ) {
        // When both reset/set or message-off/message-on are present, the
        // documented set/on behavior wins.
        if byte & 0x10 != 0 {
            screen.cursor.isBlinking = true
        } else if byte & 0x20 != 0 {
            screen.cursor.isBlinking = false
        }

        if byte & 0x04 != 0 {
            screen.audibleAlarmSequence &+= 1
        }

        if byte & 0x01 != 0 {
            screen.messageWaiting = true
        } else if byte & 0x02 != 0 {
            screen.messageWaiting = false
        }

        if case .move(let position) = pendingCursorOrder {
            screen.moveCursor(
                row: position / screen.columns,
                column: position % screen.columns
            )
        }

        applyKeyboardUnlock(
            byte,
            keyboardWasUnlocked: keyboardWasUnlocked,
            screen: &screen
        )
    }

    private mutating func applyKeyboardUnlock(
        _ byte: UInt8,
        keyboardWasUnlocked: Bool,
        screen: inout TerminalScreen
    ) {
        guard byte & 0x08 != 0 else { return }
        screen.inputInhibited = false
        if case .move = pendingCursorOrder { return }

        let suppressCursorMove = byte & 0x40 != 0
        guard !keyboardWasUnlocked, !suppressCursorMove else { return }
        if case .insert(let position) = pendingCursorOrder {
            screen.moveCursor(
                row: position / screen.columns,
                column: position % screen.columns
            )
        } else {
            screen.moveCursor(row: 0, column: 0)
            screen.ensureCursorInInputField()
        }
    }

    private func resetModifiedDataTags(
        includingProtectedFields: Bool,
        screen: inout TerminalScreen
    ) {
        for index in screen.fields.indices
        where includingProtectedFields || !screen.fields[index].isProtected {
            screen.fields[index].modified = false
            screen.fields[index].isFieldExitPending = false
        }
    }

    private func clearUnprotectedFields(onlyModified: Bool, screen: inout TerminalScreen) {
        for fieldIndex in screen.fields.indices {
            let field = screen.fields[fieldIndex]
            guard !field.isProtected, !onlyModified || field.modified else { continue }
            let lowerBound = max(0, field.start)
            let upperBound = min(screen.cells.count, field.start + field.length)
            guard lowerBound < upperBound else { continue }
            for position in lowerBound..<upperBound {
                screen.cells[position].character = " "
                screen.cells[position].isNull = true
                screen.cells[position].inputByteOverride = nil
            }
            screen.fields[fieldIndex].isFieldExitPending = false
            screen.fields[fieldIndex].isNegative = false
        }
    }
}
