import Foundation

public struct DataTransferLimits: Equatable, Sendable {
    public var maximumSourceBytes: Int
    public var maximumRows: Int
    public var maximumColumns: Int
    public var maximumCellBytes: Int
    public var maximumHeaderCharacters: Int
    public var queryTimeoutSeconds: Int

    public init(
        maximumSourceBytes: Int = 8 * 1_024 * 1_024,
        maximumRows: Int = 25_000,
        maximumColumns: Int = 256,
        maximumCellBytes: Int = 65_536,
        maximumHeaderCharacters: Int = 128,
        queryTimeoutSeconds: Int = 30
    ) {
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumRows = maximumRows
        self.maximumColumns = maximumColumns
        self.maximumCellBytes = maximumCellBytes
        self.maximumHeaderCharacters = maximumHeaderCharacters
        self.queryTimeoutSeconds = queryTimeoutSeconds
    }

    public static let standard = DataTransferLimits()
}

public enum DataTransferError: Error, Equatable, LocalizedError, Sendable {
    case sourceTooLarge(maximum: Int)
    case sourceIsNotUTF8
    case sourceContainsControl
    case invalidFileName
    case emptySource
    case malformedCSV(row: Int, column: Int)
    case unterminatedQuotedField(row: Int, column: Int)
    case cellTooLarge(row: Int, column: Int, maximum: Int)
    case tooManyRows(maximum: Int)
    case tooManyColumns(maximum: Int)
    case inconsistentColumnCount(row: Int, expected: Int, actual: Int)
    case invalidHeader(column: Int)
    case duplicateHeader(String)
    case duplicateColumn(surface: String, column: String)
    case missingColumn(surface: String, column: String)
    case malformedRow(surface: String, index: Int)
    case invalidValue(surface: String, index: Int, column: String)
    case schemaTooLarge(maximum: Int)
    case schemaTruncated
    case duplicateOrdinal(Int)
    case invalidTargetColumn

    public var errorDescription: String? {
        switch self {
        case .sourceTooLarge(let maximum):
            "The local delimited source exceeds the \(maximum)-byte profiling limit."
        case .sourceIsNotUTF8:
            "The local delimited source is not valid UTF-8. Convert it explicitly before profiling."
        case .sourceContainsControl:
            "The local delimited source contains a NUL or unsupported control byte."
        case .invalidFileName:
            "The local source file name is empty, oversized, or contains a control character."
        case .emptySource:
            "The local delimited source does not contain a header and at least one data row."
        case .malformedCSV(let row, let column):
            "The delimited source has invalid quote or record structure at row \(row), column \(column)."
        case .unterminatedQuotedField(let row, let column):
            "The delimited source ends inside a quoted field at row \(row), column \(column)."
        case .cellTooLarge(let row, let column, let maximum):
            "The value at row \(row), column \(column) exceeds the \(maximum)-byte cell limit."
        case .tooManyRows(let maximum):
            "The local source exceeds the \(maximum)-row profiling limit."
        case .tooManyColumns(let maximum):
            "The local source exceeds the \(maximum)-column profiling limit."
        case .inconsistentColumnCount(let row, let expected, let actual):
            "Row \(row) has \(actual) columns; the header defines \(expected)."
        case .invalidHeader(let column):
            "Header column \(column) is empty, oversized, or contains a control character."
        case .duplicateHeader(let header):
            "The local source contains an ambiguous duplicate “\(header)” header."
        case .duplicateColumn(let surface, let column):
            "The \(surface) result contains an ambiguous duplicate \(column) column."
        case .missingColumn(let surface, let column):
            "The \(surface) result does not contain the required \(column) column."
        case .malformedRow(let surface, let index):
            "The \(surface) result row \(index) does not match its column layout."
        case .invalidValue(let surface, let index, let column):
            "The \(surface) result row \(index) contains an invalid \(column) value."
        case .schemaTooLarge(let maximum):
            "The target schema exceeds the \(maximum)-column evidence limit."
        case .schemaTruncated:
            "The target schema result reached its transport bound and cannot prove a complete mapping."
        case .duplicateOrdinal(let ordinal):
            "The target schema contains duplicate ordinal position \(ordinal)."
        case .invalidTargetColumn:
            "The target schema contains an invalid column definition."
        }
    }
}

public struct DelimitedTextDialect: Equatable, Sendable {
    public let delimiter: UInt8
    public let hasHeader: Bool

    public init(delimiter: UInt8 = 0x2C, hasHeader: Bool = true) {
        self.delimiter = delimiter
        self.hasHeader = hasHeader
    }

    public static let commaSeparated = DelimitedTextDialect()

    public var label: String {
        switch delimiter {
        case 0x2C: "COMMA CSV"
        case 0x09: "TAB DELIMITED"
        case 0x3B: "SEMICOLON CSV"
        default: "DELIMITED TEXT"
        }
    }
}

public enum TransferSourceKind: Equatable, Sendable {
    case text
    case integer
    case decimal(precision: Int, scale: Int)
    case isoDate
    case booleanTokens

    public var label: String {
        switch self {
        case .text: "TEXT"
        case .integer: "INTEGER"
        case .decimal(let precision, let scale): "DECIMAL(\(precision),\(scale))"
        case .isoDate: "DATE ISO"
        case .booleanTokens: "BOOLEAN TOKENS"
        }
    }
}

public struct TransferSourceColumnProfile: Equatable, Sendable, Identifiable {
    public let header: String
    public let ordinalPosition: Int
    public let inferredKind: TransferSourceKind
    public let blankCount: Int
    public let distinctCount: Int
    public let maxCharacters: Int
    public let maxUTF8Bytes: Int
    public let hasLeadingZeroRisk: Bool
    public let sampleValues: [String]

    public var id: String { header.uppercased() }

    public init(
        header: String,
        ordinalPosition: Int,
        inferredKind: TransferSourceKind,
        blankCount: Int,
        distinctCount: Int,
        maxCharacters: Int,
        maxUTF8Bytes: Int,
        hasLeadingZeroRisk: Bool,
        sampleValues: [String]
    ) {
        self.header = header
        self.ordinalPosition = ordinalPosition
        self.inferredKind = inferredKind
        self.blankCount = blankCount
        self.distinctCount = distinctCount
        self.maxCharacters = maxCharacters
        self.maxUTF8Bytes = maxUTF8Bytes
        self.hasLeadingZeroRisk = hasLeadingZeroRisk
        self.sampleValues = sampleValues
    }
}

public struct TransferSourceArtifact: Equatable, Sendable {
    public let fileName: String
    public let byteCount: Int
    public let sha256: String
    public let dialect: DelimitedTextDialect
    public let headers: [String]
    public let rows: [[String]]
    public let columns: [TransferSourceColumnProfile]
    public let isBundledReplay: Bool

    public var rowCount: Int { rows.count }

    public init(
        fileName: String,
        byteCount: Int,
        sha256: String,
        dialect: DelimitedTextDialect,
        headers: [String],
        rows: [[String]],
        columns: [TransferSourceColumnProfile],
        isBundledReplay: Bool = false
    ) {
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
        self.dialect = dialect
        self.headers = headers
        self.rows = rows
        self.columns = columns
        self.isBundledReplay = isBundledReplay
    }
}

public struct DelimitedTextProfiler: Sendable {
    public let limits: DataTransferLimits
    public let dialect: DelimitedTextDialect

    public init(
        limits: DataTransferLimits = .standard,
        dialect: DelimitedTextDialect = .commaSeparated
    ) {
        self.limits = limits
        self.dialect = dialect
    }

    public func parse(
        _ data: Data,
        fileName: String,
        isBundledReplay: Bool = false
    ) throws -> TransferSourceArtifact {
        guard data.count <= limits.maximumSourceBytes else {
            throw DataTransferError.sourceTooLarge(maximum: limits.maximumSourceBytes)
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw DataTransferError.sourceIsNotUTF8
        }
        let cleanFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...255).contains(cleanFileName.count), Self.isSafeText(cleanFileName) else {
            throw DataTransferError.invalidFileName
        }

        var bytes = Array(data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
        }
        guard !bytes.isEmpty else { throw DataTransferError.emptySource }
        guard bytes.allSatisfy({ byte in
            byte >= 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }) else {
            throw DataTransferError.sourceContainsControl
        }

        var records: [[String]] = []
        var record: [String] = []
        var field = Data()
        var inQuotes = false
        var quoteClosed = false
        var index = 0
        var endedWithRecordSeparator = false

        func decodedField(row: Int, column: Int) throws -> String {
            guard field.count <= limits.maximumCellBytes else {
                throw DataTransferError.cellTooLarge(
                    row: row,
                    column: column,
                    maximum: limits.maximumCellBytes
                )
            }
            guard let text = String(data: field, encoding: .utf8) else {
                throw DataTransferError.sourceIsNotUTF8
            }
            return text
        }

        while index < bytes.count {
            let byte = bytes[index]
            let rowNumber = records.count + 1
            let columnNumber = record.count + 1

            if inQuotes {
                if byte == 0x22 {
                    if index + 1 < bytes.count, bytes[index + 1] == 0x22 {
                        field.append(0x22)
                        index += 2
                    } else {
                        inQuotes = false
                        quoteClosed = true
                        index += 1
                    }
                } else {
                    field.append(byte)
                    guard field.count <= limits.maximumCellBytes else {
                        throw DataTransferError.cellTooLarge(
                            row: rowNumber,
                            column: columnNumber,
                            maximum: limits.maximumCellBytes
                        )
                    }
                    index += 1
                }
                endedWithRecordSeparator = false
                continue
            }

            if byte == 0x22 {
                guard field.isEmpty, !quoteClosed else {
                    throw DataTransferError.malformedCSV(row: rowNumber, column: columnNumber)
                }
                inQuotes = true
                index += 1
                endedWithRecordSeparator = false
            } else if byte == dialect.delimiter {
                record.append(try decodedField(row: rowNumber, column: columnNumber))
                field.removeAll(keepingCapacity: true)
                quoteClosed = false
                index += 1
                guard record.count < limits.maximumColumns else {
                    throw DataTransferError.tooManyColumns(maximum: limits.maximumColumns)
                }
                endedWithRecordSeparator = false
            } else if byte == 0x0A || byte == 0x0D {
                if byte == 0x0D {
                    guard index + 1 < bytes.count, bytes[index + 1] == 0x0A else {
                        throw DataTransferError.malformedCSV(row: rowNumber, column: columnNumber)
                    }
                    index += 2
                } else {
                    index += 1
                }
                record.append(try decodedField(row: rowNumber, column: columnNumber))
                field.removeAll(keepingCapacity: true)
                quoteClosed = false
                guard record.count <= limits.maximumColumns else {
                    throw DataTransferError.tooManyColumns(maximum: limits.maximumColumns)
                }
                records.append(record)
                record.removeAll(keepingCapacity: true)
                guard records.count <= limits.maximumRows + 1 else {
                    throw DataTransferError.tooManyRows(maximum: limits.maximumRows)
                }
                endedWithRecordSeparator = true
            } else {
                guard !quoteClosed else {
                    throw DataTransferError.malformedCSV(row: rowNumber, column: columnNumber)
                }
                field.append(byte)
                guard field.count <= limits.maximumCellBytes else {
                    throw DataTransferError.cellTooLarge(
                        row: rowNumber,
                        column: columnNumber,
                        maximum: limits.maximumCellBytes
                    )
                }
                index += 1
                endedWithRecordSeparator = false
            }
        }

        guard !inQuotes else {
            throw DataTransferError.unterminatedQuotedField(
                row: records.count + 1,
                column: record.count + 1
            )
        }
        if !endedWithRecordSeparator || !record.isEmpty || !field.isEmpty {
            record.append(try decodedField(row: records.count + 1, column: record.count + 1))
            records.append(record)
        }

        guard dialect.hasHeader,
              records.count >= 2,
              let rawHeaders = records.first,
              !rawHeaders.isEmpty else {
            throw DataTransferError.emptySource
        }
        guard rawHeaders.count <= limits.maximumColumns else {
            throw DataTransferError.tooManyColumns(maximum: limits.maximumColumns)
        }

        var seenHeaders = Set<String>()
        let headers = try rawHeaders.enumerated().map { offset, value in
            let header = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...limits.maximumHeaderCharacters).contains(header.count),
                  Self.isSafeText(header) else {
                throw DataTransferError.invalidHeader(column: offset + 1)
            }
            let key = header.uppercased()
            guard seenHeaders.insert(key).inserted else {
                throw DataTransferError.duplicateHeader(header)
            }
            return header
        }

        let rows = Array(records.dropFirst())
        guard rows.count <= limits.maximumRows else {
            throw DataTransferError.tooManyRows(maximum: limits.maximumRows)
        }
        for (offset, row) in rows.enumerated() where row.count != headers.count {
            throw DataTransferError.inconsistentColumnCount(
                row: offset + 2,
                expected: headers.count,
                actual: row.count
            )
        }

        let columns = headers.indices.map { columnIndex in
            Self.profileColumn(
                header: headers[columnIndex],
                ordinal: columnIndex + 1,
                values: rows.map { $0[columnIndex] }
            )
        }

        return TransferSourceArtifact(
            fileName: cleanFileName,
            byteCount: data.count,
            sha256: AIContentFingerprint.sha256(data),
            dialect: dialect,
            headers: headers,
            rows: rows,
            columns: columns,
            isBundledReplay: isBundledReplay
        )
    }

    private static func profileColumn(
        header: String,
        ordinal: Int,
        values: [String]
    ) -> TransferSourceColumnProfile {
        let nonblank = values.filter { !$0.isEmpty }
        let samples = Array(nonblank.reduce(into: [String]()) { result, value in
            if result.count < 3, !result.contains(value) { result.append(value) }
        })
        let distinctCount = Set(values).count
        let leadingZeroRisk = nonblank.contains(where: hasSignificantLeadingZero)
        let kind = inferredKind(values: nonblank, leadingZeroRisk: leadingZeroRisk)
        return TransferSourceColumnProfile(
            header: header,
            ordinalPosition: ordinal,
            inferredKind: kind,
            blankCount: values.count - nonblank.count,
            distinctCount: distinctCount,
            maxCharacters: values.map { $0.unicodeScalars.count }.max() ?? 0,
            maxUTF8Bytes: values.map { $0.utf8.count }.max() ?? 0,
            hasLeadingZeroRisk: leadingZeroRisk,
            sampleValues: samples
        )
    }

    private static func inferredKind(values: [String], leadingZeroRisk: Bool) -> TransferSourceKind {
        guard !values.isEmpty else { return .text }
        let upper = Set(values.map { $0.uppercased() })
        if upper.isSubset(of: ["TRUE", "FALSE", "Y", "N"]) {
            return .booleanTokens
        }
        if values.allSatisfy(isISODate) { return .isoDate }
        if !leadingZeroRisk, values.allSatisfy({ integerShape($0) != nil }) {
            return .integer
        }
        let shapes = values.compactMap(decimalShape)
        if !leadingZeroRisk, shapes.count == values.count,
           values.contains(where: { $0.contains(".") }) {
            return .decimal(
                precision: shapes.map(\.precision).max() ?? 1,
                scale: shapes.map(\.scale).max() ?? 0
            )
        }
        return .text
    }

    fileprivate static func decimalShape(_ value: String) -> (precision: Int, scale: Int)? {
        var body = value
        if body.first == "+" || body.first == "-" { body.removeFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              !parts[0].isEmpty,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              !(parts.count == 2 && parts[1].isEmpty) else { return nil }
        let integerDigits = parts[0].drop(while: { $0 == "0" }).count
        let scale = parts.count == 2 ? parts[1].count : 0
        return (max(1, integerDigits) + scale, scale)
    }

    fileprivate static func integerShape(_ value: String) -> Int64? {
        guard !value.isEmpty,
              !value.contains("."),
              value.dropFirst(value.first == "+" || value.first == "-" ? 1 : 0).allSatisfy(\.isNumber) else {
            return nil
        }
        return Int64(value)
    }

    fileprivate static func isISODate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...9_999).contains(year),
              (1...12).contains(month),
              (1...31).contains(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        let confirmed = calendar.dateComponents([.year, .month, .day], from: date)
        return confirmed.year == year && confirmed.month == month && confirmed.day == day
    }

    private static func hasSignificantLeadingZero(_ value: String) -> Bool {
        var body = value
        if body.first == "+" || body.first == "-" { body.removeFirst() }
        return body.count > 1 && body.first == "0" && body.allSatisfy(\.isNumber)
    }

    private static func isSafeText(_ value: String) -> Bool {
        !value.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 0x20 && $0.value != 0x09) })
    }
}

public struct IBMTableIdentity: Hashable, Sendable, Identifiable, CustomStringConvertible {
    public let library: IBMSystemObjectName
    public let table: IBMSystemObjectName

    public var id: String { "\(library.value)/\(table.value)" }
    public var description: String { id }

    public init(library: IBMSystemObjectName, table: IBMSystemObjectName) {
        self.library = library
        self.table = table
    }
}

public struct TransferTargetColumn: Equatable, Sendable, Identifiable {
    public let name: String
    public let systemName: IBMSystemObjectName?
    public let ordinalPosition: Int
    public let dataType: String
    public let length: Int
    public let numericScale: Int?
    public let isNullable: Bool
    public let isUpdatable: Bool
    public let hasDefault: Bool
    public let ccsid: Int?
    public let isIdentity: Bool
    public let identityGeneration: String?
    public let isHidden: Bool
    public let hasFieldProcedure: Bool
    public let dateFormat: String?
    public let dateSeparator: String?

    public var id: String { "\(ordinalPosition):\(name.uppercased())" }

    public var typeDisplay: String {
        switch dataType {
        case "DECIMAL", "NUMERIC":
            "\(dataType)(\(length),\(numericScale ?? 0))"
        case "CHAR", "VARCHAR", "CLOB", "GRAPHIC", "VARG", "VARGRAPHIC", "DBCLOB":
            "\(dataType)(\(length))" + (ccsid.map { " CCSID \($0)" } ?? "")
        default:
            dataType
        }
    }

    public init(
        name: String,
        systemName: IBMSystemObjectName? = nil,
        ordinalPosition: Int,
        dataType: String,
        length: Int,
        numericScale: Int? = nil,
        isNullable: Bool,
        isUpdatable: Bool = true,
        hasDefault: Bool = false,
        ccsid: Int? = nil,
        isIdentity: Bool = false,
        identityGeneration: String? = nil,
        isHidden: Bool = false,
        hasFieldProcedure: Bool = false,
        dateFormat: String? = nil,
        dateSeparator: String? = nil
    ) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanType = dataType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (1...128).contains(cleanName.count),
              cleanName.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
              (1...20).contains(cleanType.count),
              cleanType.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              (1...DataTransferLimits.standard.maximumColumns).contains(ordinalPosition),
              length > 0,
              numericScale.map({ $0 >= 0 && $0 <= length }) ?? true else {
            throw DataTransferError.invalidTargetColumn
        }
        self.name = cleanName
        self.systemName = systemName
        self.ordinalPosition = ordinalPosition
        self.dataType = cleanType
        self.length = length
        self.numericScale = numericScale
        self.isNullable = isNullable
        self.isUpdatable = isUpdatable
        self.hasDefault = hasDefault
        self.ccsid = ccsid
        self.isIdentity = isIdentity
        self.identityGeneration = identityGeneration
        self.isHidden = isHidden
        self.hasFieldProcedure = hasFieldProcedure
        self.dateFormat = dateFormat
        self.dateSeparator = dateSeparator
    }
}

public struct TransferTargetSnapshot: Equatable, Sendable {
    public let targetName: String
    public let table: IBMTableIdentity
    public let capturedAt: Date
    public let columns: [TransferTargetColumn]
    public let queryFingerprint: String
    public let schemaFingerprint: String
    public let isBundledReplay: Bool

    public init(
        targetName: String,
        table: IBMTableIdentity,
        capturedAt: Date,
        columns: [TransferTargetColumn],
        queryFingerprint: String,
        schemaFingerprint: String? = nil,
        isBundledReplay: Bool = false
    ) {
        self.targetName = targetName
        self.table = table
        self.capturedAt = capturedAt
        let orderedColumns = columns.sorted { $0.ordinalPosition < $1.ordinalPosition }
        self.columns = orderedColumns
        self.queryFingerprint = queryFingerprint
        self.schemaFingerprint = schemaFingerprint ?? Self.fingerprint(table: table, columns: orderedColumns)
        self.isBundledReplay = isBundledReplay
    }

    private static func fingerprint(
        table: IBMTableIdentity,
        columns: [TransferTargetColumn]
    ) -> String {
        func field(_ value: String?) -> String {
            let text = value ?? "<NULL>"
            return "\(text.utf8.count):\(text)"
        }

        var records = [field(table.library.value), field(table.table.value)]
        records.append(contentsOf: columns.map { column in
            [
                String(column.ordinalPosition), column.name, column.systemName?.value,
                column.dataType, String(column.length), column.numericScale.map(String.init),
                String(column.isNullable), String(column.isUpdatable), String(column.hasDefault),
                column.ccsid.map(String.init), String(column.isIdentity), column.identityGeneration,
                String(column.isHidden), String(column.hasFieldProcedure), column.dateFormat,
                column.dateSeparator
            ].map(field).joined(separator: "|")
        })
        return AIContentFingerprint.sha256(records.joined(separator: "\n"))
    }
}

public enum TransferIssueSeverity: String, CaseIterable, Sendable {
    case blocker = "BLOCKER"
    case warning = "WARNING"
    case information = "INFORMATION"

    fileprivate var rank: Int {
        switch self {
        case .blocker: 3
        case .warning: 2
        case .information: 1
        }
    }
}

public enum TransferIssueCode: String, Hashable, Sendable {
    case missingTargetColumn
    case requiredTargetMissingSource
    case targetNotUpdatable
    case generatedTarget
    case hiddenTarget
    case fieldProcedure
    case unsupportedType
    case unsupportedCCSID
    case unrepresentableText
    case truncation
    case invalidInteger
    case integerOverflow
    case invalidDecimal
    case decimalOverflow
    case ambiguousDate
    case invalidBoolean
    case leadingZeroLoss
    case blankRequiresRule
    case domainEvidenceMissing
    case blankValuesPreserved
}

public struct TransferIssue: Equatable, Sendable, Identifiable {
    public let severity: TransferIssueSeverity
    public let code: TransferIssueCode
    public let sourceHeader: String?
    public let targetColumn: String?
    public let rowNumber: Int?
    public let sampleValue: String?
    public let message: String

    public var id: String {
        "\(severity.rawValue):\(code.rawValue):\(sourceHeader ?? "-"):\(targetColumn ?? "-"):\(rowNumber ?? 0)"
    }

    public init(
        severity: TransferIssueSeverity,
        code: TransferIssueCode,
        sourceHeader: String? = nil,
        targetColumn: String? = nil,
        rowNumber: Int? = nil,
        sampleValue: String? = nil,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.sourceHeader = sourceHeader
        self.targetColumn = targetColumn
        self.rowNumber = rowNumber
        self.sampleValue = sampleValue
        self.message = message
    }
}

public enum TransferMappingVerdict: String, Sendable {
    case ready = "READY"
    case warning = "WARN"
    case blocked = "BLOCK"
}

public struct TransferColumnMapping: Equatable, Sendable, Identifiable {
    public let source: TransferSourceColumnProfile
    public let target: TransferTargetColumn?
    public let verdict: TransferMappingVerdict
    public let issues: [TransferIssue]

    public var id: String { source.id }

    public init(
        source: TransferSourceColumnProfile,
        target: TransferTargetColumn?,
        verdict: TransferMappingVerdict,
        issues: [TransferIssue]
    ) {
        self.source = source
        self.target = target
        self.verdict = verdict
        self.issues = issues
    }
}

public enum TransferEvidenceSource: String, CaseIterable, Sendable {
    case localSourceProfile = "LOCAL_SOURCE_PROFILE"
    case targetSchema = "SYSCOLUMNS2"
    case writeExecution = "WRITE_EXECUTION"
}

public enum TransferEvidenceOutcome: Equatable, Sendable {
    case collected
    case unavailable(String)

    public var isCollected: Bool {
        if case .collected = self { return true }
        return false
    }
}

public struct TransferEvidenceReceipt: Equatable, Sendable, Identifiable {
    public let source: TransferEvidenceSource
    public let itemCount: Int
    public let elapsedMilliseconds: Int?
    public let fingerprint: String?
    public let outcome: TransferEvidenceOutcome

    public var id: TransferEvidenceSource { source }

    public init(
        source: TransferEvidenceSource,
        itemCount: Int,
        elapsedMilliseconds: Int? = nil,
        fingerprint: String? = nil,
        outcome: TransferEvidenceOutcome
    ) {
        self.source = source
        self.itemCount = itemCount
        self.elapsedMilliseconds = elapsedMilliseconds
        self.fingerprint = fingerprint
        self.outcome = outcome
    }
}

public struct TransferValidationReport: Equatable, Sendable {
    public let source: TransferSourceArtifact
    public let target: TransferTargetSnapshot
    public let mappings: [TransferColumnMapping]
    public let issues: [TransferIssue]
    public let receipts: [TransferEvidenceReceipt]
    public let createdAt: Date

    public var blockerCount: Int { issues.filter { $0.severity == .blocker }.count }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    public var isMappingValid: Bool { blockerCount == 0 }
    public var hostWriteAvailable: Bool { false }

    public init(
        source: TransferSourceArtifact,
        target: TransferTargetSnapshot,
        mappings: [TransferColumnMapping],
        issues: [TransferIssue],
        receipts: [TransferEvidenceReceipt],
        createdAt: Date = Date()
    ) {
        self.source = source
        self.target = target
        self.mappings = mappings
        self.issues = issues
        self.receipts = receipts
        self.createdAt = createdAt
    }
}

public struct TransferSchemaAnalyzer: Sendable {
    public init() {}

    public func validate(
        source: TransferSourceArtifact,
        target: TransferTargetSnapshot,
        sourceElapsedMilliseconds: Int? = nil,
        targetElapsedMilliseconds: Int? = nil
    ) -> TransferValidationReport {
        let targetByName = Dictionary(grouping: target.columns) { $0.name.uppercased() }
        let targetBySystemName = Dictionary(grouping: target.columns) { $0.systemName?.value ?? "" }
        var mappedTargetIDs = Set<String>()
        var allIssues: [TransferIssue] = []
        var mappings: [TransferColumnMapping] = []

        for sourceColumn in source.columns {
            let key = sourceColumn.header.uppercased()
            let candidates = (targetByName[key] ?? []) + (targetBySystemName[key] ?? [])
            let uniqueCandidates = Array(Dictionary(grouping: candidates, by: \.id).values.compactMap(\.first))
            guard uniqueCandidates.count == 1, let targetColumn = uniqueCandidates.first else {
                let issue = TransferIssue(
                    severity: .blocker,
                    code: .missingTargetColumn,
                    sourceHeader: sourceColumn.header,
                    message: "No unique target column matches source header \(sourceColumn.header)."
                )
                allIssues.append(issue)
                mappings.append(TransferColumnMapping(
                    source: sourceColumn,
                    target: nil,
                    verdict: .blocked,
                    issues: [issue]
                ))
                continue
            }

            mappedTargetIDs.insert(targetColumn.id)
            let values = source.rows.map { $0[sourceColumn.ordinalPosition - 1] }
            let issues = validateColumn(sourceColumn, values: values, target: targetColumn)
            allIssues.append(contentsOf: issues)
            let highest = issues.map(\.severity.rank).max() ?? 0
            let verdict: TransferMappingVerdict = highest >= TransferIssueSeverity.blocker.rank
                ? .blocked
                : highest >= TransferIssueSeverity.warning.rank ? .warning : .ready
            mappings.append(TransferColumnMapping(
                source: sourceColumn,
                target: targetColumn,
                verdict: verdict,
                issues: issues
            ))
        }

        for targetColumn in target.columns where !mappedTargetIDs.contains(targetColumn.id) {
            guard !targetColumn.isNullable,
                  !targetColumn.hasDefault,
                  !targetColumn.isIdentity,
                  !targetColumn.isHidden else { continue }
            allIssues.append(TransferIssue(
                severity: .blocker,
                code: .requiredTargetMissingSource,
                targetColumn: targetColumn.name,
                message: "Required target column \(targetColumn.name) has no source mapping, default, or generated value."
            ))
        }

        let blankCount = source.columns.reduce(0) { $0 + $1.blankCount }
        if blankCount > 0 {
            allIssues.append(TransferIssue(
                severity: .information,
                code: .blankValuesPreserved,
                message: "\(blankCount) blank source cell(s) remain text. Blank-to-NULL conversion is never inferred."
            ))
        }

        let receipts = [
            TransferEvidenceReceipt(
                source: .localSourceProfile,
                itemCount: source.rowCount,
                elapsedMilliseconds: sourceElapsedMilliseconds,
                fingerprint: source.sha256,
                outcome: .collected
            ),
            TransferEvidenceReceipt(
                source: .targetSchema,
                itemCount: target.columns.count,
                elapsedMilliseconds: targetElapsedMilliseconds,
                fingerprint: target.schemaFingerprint,
                outcome: .collected
            ),
            TransferEvidenceReceipt(
                source: .writeExecution,
                itemCount: 0,
                outcome: .unavailable("This milestone has no insert, update, merge, create-table, upload, or IFS write capability.")
            )
        ]

        return TransferValidationReport(
            source: source,
            target: target,
            mappings: mappings,
            issues: allIssues.sorted {
                if $0.severity.rank != $1.severity.rank { return $0.severity.rank > $1.severity.rank }
                return $0.id < $1.id
            },
            receipts: receipts
        )
    }

    private func validateColumn(
        _ source: TransferSourceColumnProfile,
        values: [String],
        target: TransferTargetColumn
    ) -> [TransferIssue] {
        var issues: [TransferIssue] = []

        if !target.isUpdatable {
            issues.append(issue(.blocker, .targetNotUpdatable, source, target, nil, nil,
                "Target column \(target.name) is not updatable."))
        }
        if target.isIdentity, target.identityGeneration?.uppercased() == "ALWAYS" {
            issues.append(issue(.blocker, .generatedTarget, source, target, nil, nil,
                "Target column \(target.name) is generated always and cannot accept a source value."))
        }
        if target.isHidden {
            issues.append(issue(.blocker, .hiddenTarget, source, target, nil, nil,
                "Target column \(target.name) is hidden and is not eligible for automatic mapping."))
        }
        if target.hasFieldProcedure {
            issues.append(issue(.blocker, .fieldProcedure, source, target, nil, nil,
                "Target column \(target.name) has a field procedure; local profiling cannot prove encoded semantics."))
        }
        guard issues.isEmpty else { return issues }

        let numericTypes = Set(["SMALLINT", "INTEGER", "BIGINT", "DECIMAL", "NUMERIC"])
        let scalarTypes = numericTypes.union(["DATE", "BOOLEAN"])
        if source.hasLeadingZeroRisk, numericTypes.contains(target.dataType) {
            issues.append(issue(.blocker, .leadingZeroLoss, source, target, nil, nil,
                "Leading-zero source values cannot map to numeric target \(target.name) without losing their exact representation."))
        }
        if source.blankCount > 0, scalarTypes.contains(target.dataType) {
            issues.append(issue(.blocker, .blankRequiresRule, source, target, nil, nil,
                "Blank source values need an explicit conversion or NULL rule before mapping to \(target.dataType)."))
        }

        switch target.dataType {
        case "CHAR", "VARCHAR", "CLOB":
            issues.append(contentsOf: validateText(source, values: values, target: target))
            if target.length == 1, source.inferredKind == .booleanTokens {
                issues.append(issue(.warning, .domainEvidenceMissing, source, target, nil, nil,
                    "Observed one-character tokens need domain or constraint evidence before transfer."))
            }
        case "SMALLINT", "INTEGER", "BIGINT":
            issues.append(contentsOf: validateIntegers(source, values: values, target: target))
        case "DECIMAL", "NUMERIC":
            issues.append(contentsOf: validateDecimals(source, values: values, target: target))
        case "DATE":
            issues.append(contentsOf: validateDates(source, values: values, target: target))
        case "BOOLEAN":
            issues.append(contentsOf: validateBooleans(source, values: values, target: target))
        default:
            issues.append(issue(.blocker, .unsupportedType, source, target, nil, nil,
                "Target type \(target.dataType) is outside the current lossless dry-run contract."))
        }
        return issues
    }

    private func validateText(
        _ source: TransferSourceColumnProfile,
        values: [String],
        target: TransferTargetColumn
    ) -> [TransferIssue] {
        guard let ccsid = target.ccsid, ccsid != 65535 else {
            return [issue(.blocker, .unsupportedCCSID, source, target, nil, nil,
                "Target text CCSID is absent or binary; character conversion cannot be proven.")]
        }

        if ccsid == 1208 {
            if let match = values.enumerated().first(where: { $0.element.unicodeScalars.count > target.length }) {
                return [issue(.blocker, .truncation, source, target, match.offset + 2, match.element,
                    "The source value has \(match.element.unicodeScalars.count) Unicode scalar values; target \(target.name) allows \(target.length) characters.")]
            }
            return []
        }

        guard let codec = try? EBCDICCodec(ccsid: ccsid) else {
            return [issue(.blocker, .unsupportedCCSID, source, target, nil, nil,
                "The local codec catalog cannot prove lossless conversion to target CCSID \(ccsid).")]
        }
        for (offset, value) in values.enumerated() {
            guard let encoded = try? codec.encode(value) else {
                return [issue(.blocker, .unrepresentableText, source, target, offset + 2, value,
                    "A source value is not representable in target CCSID \(ccsid); substitution is not allowed.")]
            }
            if encoded.count > target.length {
                return [issue(.blocker, .truncation, source, target, offset + 2, value,
                    "The encoded source value needs \(encoded.count) bytes; target \(target.name) allows \(target.length).")]
            }
        }
        return []
    }

    private func validateIntegers(
        _ source: TransferSourceColumnProfile,
        values: [String],
        target: TransferTargetColumn
    ) -> [TransferIssue] {
        let bounds: ClosedRange<Int64> = switch target.dataType {
        case "SMALLINT": Int64(Int16.min)...Int64(Int16.max)
        case "INTEGER": Int64(Int32.min)...Int64(Int32.max)
        default: Int64.min...Int64.max
        }
        for (offset, value) in values.enumerated() where !value.isEmpty {
            guard let integer = DelimitedTextProfiler.integerShape(value) else {
                return [issue(.blocker, .invalidInteger, source, target, offset + 2, value,
                    "The source value is not an exact base-10 integer.")]
            }
            guard bounds.contains(integer) else {
                return [issue(.blocker, .integerOverflow, source, target, offset + 2, value,
                    "The source integer is outside the \(target.dataType) range.")]
            }
        }
        return []
    }

    private func validateDecimals(
        _ source: TransferSourceColumnProfile,
        values: [String],
        target: TransferTargetColumn
    ) -> [TransferIssue] {
        let targetScale = target.numericScale ?? 0
        let targetIntegerDigits = target.length - targetScale
        for (offset, value) in values.enumerated() where !value.isEmpty {
            guard let shape = DelimitedTextProfiler.decimalShape(value) else {
                return [issue(.blocker, .invalidDecimal, source, target, offset + 2, value,
                    "The source value is not an exact ungrouped base-10 decimal.")]
            }
            let integerDigits = shape.precision - shape.scale
            guard shape.scale <= targetScale, integerDigits <= targetIntegerDigits else {
                return [issue(.blocker, .decimalOverflow, source, target, offset + 2, value,
                    "The source decimal needs \(integerDigits) integer and \(shape.scale) fraction digits; target is \(target.typeDisplay).")]
            }
        }
        return []
    }

    private func validateDates(
        _ source: TransferSourceColumnProfile,
        values: [String],
        target: TransferTargetColumn
    ) -> [TransferIssue] {
        for (offset, value) in values.enumerated() where !value.isEmpty {
            guard DelimitedTextProfiler.isISODate(value) else {
                return [issue(.blocker, .ambiguousDate, source, target, offset + 2, value,
                    "Date input must use unambiguous ISO 8601 YYYY-MM-DD; no locale inference is allowed.")]
            }
        }
        return []
    }

    private func validateBooleans(
        _ source: TransferSourceColumnProfile,
        values: [String],
        target: TransferTargetColumn
    ) -> [TransferIssue] {
        let allowed = Set(["TRUE", "FALSE", "1", "0"])
        if let match = values.enumerated().first(where: {
            !$0.element.isEmpty && !allowed.contains($0.element.uppercased())
        }) {
            return [issue(.blocker, .invalidBoolean, source, target, match.offset + 2, match.element,
                "Boolean input must be TRUE, FALSE, 1, or 0 under the current explicit contract.")]
        }
        return []
    }

    private func issue(
        _ severity: TransferIssueSeverity,
        _ code: TransferIssueCode,
        _ source: TransferSourceColumnProfile,
        _ target: TransferTargetColumn,
        _ row: Int?,
        _ sample: String?,
        _ message: String
    ) -> TransferIssue {
        TransferIssue(
            severity: severity,
            code: code,
            sourceHeader: source.header,
            targetColumn: target.name,
            rowNumber: row,
            sampleValue: sample,
            message: message
        )
    }
}

public struct TransferSchemaSQLPlanner: Sendable {
    public let limits: DataTransferLimits

    public init(limits: DataTransferLimits = .standard) {
        self.limits = limits
    }

    public func targetSchema(_ table: IBMTableIdentity) -> SQLExecutionRequest {
        let overflowProbeLimit = limits.maximumColumns == Int.max
            ? Int.max
            : limits.maximumColumns + 1
        return SQLExecutionRequest(
            sql: """
            SELECT COLUMN_NAME,
                   SYSTEM_COLUMN_NAME,
                   ORDINAL_POSITION,
                   DATA_TYPE,
                   LENGTH,
                   NUMERIC_SCALE,
                   IS_NULLABLE,
                   IS_UPDATABLE,
                   HAS_DEFAULT,
                   CCSID,
                   IS_IDENTITY,
                   IDENTITY_GENERATION,
                   HIDDEN,
                   HAS_FLDPROC,
                   DATE_FORMAT,
                   DATE_SEPARATOR
              FROM QSYS2.SYSCOLUMNS2
             WHERE SYSTEM_TABLE_SCHEMA = '\(table.library.value)'
               AND SYSTEM_TABLE_NAME = '\(table.table.value)'
             ORDER BY ORDINAL_POSITION
             FETCH FIRST \(overflowProbeLimit) ROWS ONLY
            """,
            maximumRows: limits.maximumColumns,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }
}

public struct TransferSchemaSQLDecoder: Sendable {
    public let limits: DataTransferLimits

    public init(limits: DataTransferLimits = .standard) {
        self.limits = limits
    }

    public func decode(
        _ result: SQLResult,
        table: IBMTableIdentity,
        request: SQLExecutionRequest
    ) throws -> TransferTargetSnapshot {
        guard result.rows.count <= limits.maximumColumns else {
            throw DataTransferError.schemaTooLarge(maximum: limits.maximumColumns)
        }
        guard !result.wasTruncated else { throw DataTransferError.schemaTruncated }
        let grid = try Grid(result: result, surface: "SYSCOLUMNS2")
        var ordinals = Set<Int>()
        var columns: [TransferTargetColumn] = []

        for (index, row) in grid.rows.enumerated() {
            let name = try row.requiredString("COLUMN_NAME", index: index)
            let systemNameText = try row.requiredString("SYSTEM_COLUMN_NAME", index: index)
            let systemName = try? IBMSystemObjectName(systemNameText)
            let ordinal = try row.requiredInt("ORDINAL_POSITION", index: index)
            guard ordinals.insert(ordinal).inserted else {
                throw DataTransferError.duplicateOrdinal(ordinal)
            }
            let dataType = try row.requiredString("DATA_TYPE", index: index)
            let length = try row.requiredInt("LENGTH", index: index)
            let scale = try row.optionalInt("NUMERIC_SCALE", index: index)
            let nullable = try row.yesNo("IS_NULLABLE", index: index)
            let updatable = try row.yesNo("IS_UPDATABLE", index: index)
            let defaultCode = try row.requiredString("HAS_DEFAULT", index: index)
            let ccsid = try row.optionalInt("CCSID", index: index)
            let identity = try row.yesNo("IS_IDENTITY", index: index, yes: "YES", no: "NO")
            let generation = try row.optionalString("IDENTITY_GENERATION", index: index)
            let hidden = try row.requiredString("HIDDEN", index: index) == "P"
            let fieldProcedure = try row.yesNo("HAS_FLDPROC", index: index)
            let dateFormat = try row.optionalString("DATE_FORMAT", index: index)
            let dateSeparator = try row.optionalString("DATE_SEPARATOR", index: index)
            columns.append(try TransferTargetColumn(
                name: name,
                systemName: systemName,
                ordinalPosition: ordinal,
                dataType: dataType,
                length: length,
                numericScale: scale,
                isNullable: nullable,
                isUpdatable: updatable,
                hasDefault: defaultCode != "N",
                ccsid: ccsid,
                isIdentity: identity,
                identityGeneration: generation,
                isHidden: hidden,
                hasFieldProcedure: fieldProcedure,
                dateFormat: dateFormat,
                dateSeparator: dateSeparator
            ))
        }

        guard !columns.isEmpty else {
            throw DataTransferError.invalidValue(surface: "SYSCOLUMNS2", index: 0, column: "COLUMN_NAME")
        }
        return TransferTargetSnapshot(
            targetName: result.targetName,
            table: table,
            capturedAt: result.startedAt,
            columns: columns,
            queryFingerprint: AIContentFingerprint.sha256(request.sql)
        )
    }

    private struct Grid {
        let rows: [Row]

        init(result: SQLResult, surface: String) throws {
            var indices: [String: Int] = [:]
            for (index, column) in result.columns.enumerated() {
                let key = column.name.uppercased()
                guard indices[key] == nil else {
                    throw DataTransferError.duplicateColumn(surface: surface, column: key)
                }
                indices[key] = index
            }
            let required = [
                "COLUMN_NAME", "SYSTEM_COLUMN_NAME", "ORDINAL_POSITION", "DATA_TYPE", "LENGTH",
                "NUMERIC_SCALE", "IS_NULLABLE", "IS_UPDATABLE", "HAS_DEFAULT", "CCSID",
                "IS_IDENTITY", "IDENTITY_GENERATION", "HIDDEN", "HAS_FLDPROC", "DATE_FORMAT",
                "DATE_SEPARATOR"
            ]
            for column in required where indices[column] == nil {
                throw DataTransferError.missingColumn(surface: surface, column: column)
            }
            rows = try result.rows.enumerated().map { index, values in
                guard values.count == result.columns.count else {
                    throw DataTransferError.malformedRow(surface: surface, index: index)
                }
                return Row(values: values, indices: indices, surface: surface)
            }
        }
    }

    private struct Row {
        let values: [SQLValue]
        let indices: [String: Int]
        let surface: String

        func value(_ column: String) throws -> SQLValue {
            guard let index = indices[column], values.indices.contains(index) else {
                throw DataTransferError.missingColumn(surface: surface, column: column)
            }
            return values[index]
        }

        func requiredString(_ column: String, index: Int) throws -> String {
            guard case .string(let raw) = try value(column) else {
                throw DataTransferError.invalidValue(surface: surface, index: index, column: column)
            }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  text.count <= 256,
                  text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
                throw DataTransferError.invalidValue(surface: surface, index: index, column: column)
            }
            return text
        }

        func optionalString(_ column: String, index: Int) throws -> String? {
            let raw = try value(column)
            if case .null = raw { return nil }
            guard case .string(let value) = raw else {
                throw DataTransferError.invalidValue(surface: surface, index: index, column: column)
            }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 256,
                  text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
                throw DataTransferError.invalidValue(surface: surface, index: index, column: column)
            }
            return text.isEmpty ? nil : text
        }

        func requiredInt(_ column: String, index: Int) throws -> Int {
            guard let value = try optionalInt(column, index: index) else {
                throw DataTransferError.invalidValue(surface: surface, index: index, column: column)
            }
            return value
        }

        func optionalInt(_ column: String, index: Int) throws -> Int? {
            switch try value(column) {
            case .null:
                return nil
            case .integer(let value):
                guard let exact = Int(exactly: value) else { break }
                return exact
            case .decimal(let value), .string(let value):
                if let exact = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return exact }
            default:
                break
            }
            throw DataTransferError.invalidValue(surface: surface, index: index, column: column)
        }

        func yesNo(
            _ column: String,
            index: Int,
            yes: String = "Y",
            no: String = "N"
        ) throws -> Bool {
            let value = try requiredString(column, index: index).uppercased()
            if value == yes { return true }
            if value == no { return false }
            throw DataTransferError.invalidValue(surface: surface, index: index, column: column)
        }
    }
}
