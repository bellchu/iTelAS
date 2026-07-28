import Foundation

public enum TN5250InputEncoderError: Error, Equatable, LocalizedError, Sendable {
    case signedTransparentField(Int)
    case tooManyEntryFields(Int)
    case invalidReadResequenceStart(Int)
    case invalidReadResequenceTarget(field: Int, target: Int)
    case closedReadResequenceLoop(field: Int)
    case missingReadResequenceTerminator(field: Int)

    public var errorDescription: String? {
        switch self {
        case .signedTransparentField(let field):
            "Input field \(field) combines signed-numeric and transparent controls; IBM defines that combination as unpredictable, so iTelAS refused to send it."
        case .tooManyEntryFields(let count):
            "The host defined \(count) entry fields, but 5250 read resequencing supports at most 128. Input was not sent."
        case .invalidReadResequenceStart(let field):
            "The host requested read resequencing from undefined field \(field). Input was not sent."
        case .invalidReadResequenceTarget(let field, let target):
            "Read resequencing field \(field) points to undefined field \(target). Input was not sent."
        case .closedReadResequenceLoop(let field):
            "The host supplied a closed read resequencing loop at field \(field). Input was not sent."
        case .missingReadResequenceTerminator(let field):
            "The host's read resequencing chain reaches field \(field) without the required terminator. Input was not sent."
        }
    }
}

public enum TN5250InputEncoder {
    private struct NumberedEntryField {
        let ordinal: Int
        let field: TerminalField
    }

    public static func payload(
        aid: UInt8,
        screen: TerminalScreen,
        ccsid: Int = 37
    ) throws -> Data {
        let codec = try EBCDICCodec(ccsid: ccsid)
        var payload = Data([
            UInt8(clamping: screen.cursor.row + 1),
            UInt8(clamping: screen.cursor.column + 1),
            aid
        ])

        guard screen.aidCarriesFieldData(aid) else { return payload }
        let orderedFields = try orderedEntryFields(screen)

        switch screen.readMode {
        case .inputFields:
            // Read Input returns every input field only while the master MDT
            // is set. There are no SBA delimiters between fields.
            guard screen.fields.contains(where: { $0.isEntryField && $0.modified }) else {
                return payload
            }
            for numberedField in orderedFields where !numberedField.field.isProtected {
                let field = numberedField.field
                try validate(field, ordinal: numberedField.ordinal)
                payload.append(try readInputBytes(field: field, screen: screen, codec: codec))
            }

        case .modifiedFields, .modifiedFieldsAlternate:
            let preservesNulls = screen.readMode == .modifiedFieldsAlternate
            for numberedField in orderedFields
            where numberedField.field.modified && !numberedField.field.isProtected {
                let field = numberedField.field
                try validate(field, ordinal: numberedField.ordinal)
                guard screen.cells.indices.contains(field.start) else { continue }
                appendFieldAddress(field, screen: screen, to: &payload)

                if field.isTransparent {
                    let bytes = try transparentBytes(field: field, screen: screen, codec: codec)
                    payload.append(0x10)
                    payload.append(UInt8((bytes.count >> 8) & 0xFF))
                    payload.append(UInt8(bytes.count & 0xFF))
                    payload.append(bytes)
                } else {
                    payload.append(try readModifiedBytes(
                        field: field,
                        screen: screen,
                        codec: codec,
                        preservesNulls: preservesNulls
                    ))
                }
            }
        }
        return payload
    }

    private static func orderedEntryFields(_ screen: TerminalScreen) throws -> [NumberedEntryField] {
        let normalOrder = screen.fields
            .filter(\.isEntryField)
            .sorted { lhs, rhs in lhs.start < rhs.start }
            .enumerated()
            .map { NumberedEntryField(ordinal: $0.offset + 1, field: $0.element) }
        let requestedStart = Int(screen.readResequenceStartField)
        guard requestedStart != 0 else { return normalOrder }
        guard normalOrder.count <= 128 else {
            throw TN5250InputEncoderError.tooManyEntryFields(normalOrder.count)
        }
        guard normalOrder.indices.contains(requestedStart - 1) else {
            throw TN5250InputEncoderError.invalidReadResequenceStart(requestedStart)
        }

        var result: [NumberedEntryField] = []
        var visited = Set<Int>()
        var current = requestedStart
        while true {
            guard visited.insert(current).inserted else {
                throw TN5250InputEncoderError.closedReadResequenceLoop(field: current)
            }
            let numberedField = normalOrder[current - 1]
            result.append(numberedField)

            if let target = numberedField.field.readResequenceNextField {
                if target == 0xFF { return result }
                let targetNumber = Int(target)
                guard (1...normalOrder.count).contains(targetNumber), targetNumber <= 128 else {
                    throw TN5250InputEncoderError.invalidReadResequenceTarget(
                        field: current,
                        target: targetNumber
                    )
                }
                current = targetNumber
            } else {
                guard current < normalOrder.count else {
                    throw TN5250InputEncoderError.missingReadResequenceTerminator(field: current)
                }
                current += 1
            }
        }
    }

    private static func validate(_ field: TerminalField, ordinal: Int) throws {
        if field.isTransparent, field.inputType == .signedNumeric {
            throw TN5250InputEncoderError.signedTransparentField(ordinal)
        }
    }

    private static func appendFieldAddress(
        _ field: TerminalField,
        screen: TerminalScreen,
        to payload: inout Data
    ) {
        let row = field.start / screen.columns
        let column = field.start % screen.columns
        payload.append(contentsOf: [
            0x11,
            UInt8(clamping: row + 1),
            UInt8(clamping: column + 1)
        ])
    }

    private static func readModifiedBytes(
        field: TerminalField,
        screen: TerminalScreen,
        codec: EBCDICCodec,
        preservesNulls: Bool
    ) throws -> Data {
        let range = boundedDataRange(field.inputDataRange, screen: screen)
        guard let lastDataPosition = range.last(where: { !screen.cells[$0].isNull }) else {
            return Data()
        }
        var data = try encodedBytes(
            in: range.lowerBound..<(lastDataPosition + 1),
            screen: screen,
            codec: codec,
            nullByte: preservesNulls ? 0x00 : 0x40
        )
        applyNumericSign(field: field, screen: screen, data: &data)
        return data
    }

    private static func readInputBytes(
        field: TerminalField,
        screen: TerminalScreen,
        codec: EBCDICCodec
    ) throws -> Data {
        if field.isTransparent {
            return try transparentBytes(field: field, screen: screen, codec: codec)
        }
        var data = try encodedBytes(
            in: boundedDataRange(field.inputDataRange, screen: screen),
            screen: screen,
            codec: codec,
            nullByte: 0x40
        )
        applyNumericSign(field: field, screen: screen, data: &data)
        return data
    }

    private static func transparentBytes(
        field: TerminalField,
        screen: TerminalScreen,
        codec: EBCDICCodec
    ) throws -> Data {
        let declaredRange = field.start..<(field.start + max(0, field.length))
        let range = boundedDataRange(declaredRange, screen: screen)
        var data = Data()
        data.reserveCapacity(range.count)
        for position in range {
            let cell = screen.cells[position]
            if let byte = cell.inputByteOverride {
                data.append(byte)
            } else if cell.isNull {
                data.append(0x00)
            } else {
                data.append(try codec.encode(String(cell.character)))
            }
        }
        return data
    }

    private static func encodedBytes(
        in range: Range<Int>,
        screen: TerminalScreen,
        codec: EBCDICCodec,
        nullByte: UInt8
    ) throws -> Data {
        var data = Data()
        data.reserveCapacity(range.count)
        for position in range {
            let cell = screen.cells[position]
            if cell.isNull {
                data.append(nullByte)
            } else if let byte = cell.inputByteOverride {
                data.append(byte)
            } else {
                data.append(try codec.encode(String(cell.character)))
            }
        }
        return data
    }

    private static func boundedDataRange(
        _ range: Range<Int>,
        screen: TerminalScreen
    ) -> Range<Int> {
        let lowerBound = min(max(0, range.lowerBound), screen.cells.count)
        let upperBound = min(max(lowerBound, range.upperBound), screen.cells.count)
        return lowerBound..<upperBound
    }

    private static func applyNumericSign(
        field: TerminalField,
        screen: TerminalScreen,
        data: inout Data
    ) {
        guard !data.isEmpty else { return }
        let signPosition = field.start + field.length - 1
        let hasNegativeDisplaySign = screen.cells.indices.contains(signPosition)
            && screen.cells[signPosition].character == "-"
        let shouldDZone = (field.inputType == .signedNumeric && (field.isNegative || hasNegativeDisplaySign))
            || (field.inputType == .numericOnly && field.isNegative)
        guard shouldDZone else { return }
        let lowOrderIndex = data.index(before: data.endIndex)
        if (0xF0...0xF9).contains(data[lowOrderIndex]) {
            data[lowOrderIndex] = 0xD0 | (data[lowOrderIndex] & 0x0F)
        }
    }
}
