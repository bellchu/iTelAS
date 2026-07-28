import Foundation

public enum SQLTypedExportFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case csvBundle
    case typedJSON

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .csvBundle: "CSV + manifest"
        case .typedJSON: "Typed JSON"
        }
    }

    public var detail: String {
        switch self {
        case .csvBundle: "A spreadsheet-safe CSV plus exact schema and receipt sidecars."
        case .typedJSON: "One portable document with tagged values, schema, and provenance."
        }
    }

    public var isPackage: Bool { self == .csvBundle }
}

public struct SQLTypedExportLimits: Equatable, Sendable {
    public var maximumColumns: Int
    public var maximumRows: Int
    public var maximumCellUTF8Bytes: Int
    public var maximumQueryUTF8Bytes: Int
    public var maximumArtifactBytes: Int

    public init(
        maximumColumns: Int = 256,
        maximumRows: Int = 10_000,
        maximumCellUTF8Bytes: Int = 1_048_576,
        maximumQueryUTF8Bytes: Int = 1_048_576,
        maximumArtifactBytes: Int = 32 * 1_048_576
    ) {
        self.maximumColumns = maximumColumns
        self.maximumRows = maximumRows
        self.maximumCellUTF8Bytes = maximumCellUTF8Bytes
        self.maximumQueryUTF8Bytes = maximumQueryUTF8Bytes
        self.maximumArtifactBytes = maximumArtifactBytes
    }

    public static let standard = SQLTypedExportLimits()
}

public enum SQLTypedExportError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case emptyQuery
    case queryTooLarge(maximum: Int)
    case invalidTarget
    case invalidProvider
    case noColumns
    case tooManyColumns(maximum: Int)
    case tooManyRows(maximum: Int)
    case invalidColumn(index: Int)
    case duplicateColumn(String)
    case invalidRowWidth(row: Int, expected: Int, actual: Int)
    case unexpectedNull(row: Int, column: Int)
    case invalidDecimal(row: Int, column: Int)
    case invalidText(row: Int, column: Int)
    case cellTooLarge(row: Int, column: Int, maximum: Int)
    case artifactTooLarge(maximum: Int)
    case invalidDestination
    case destinationExists
    case symbolicDestination
    case invalidArtifactFile(String)
    case writeVerificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits: "The export limits are invalid."
        case .emptyQuery: "The retained result has no exact query provenance."
        case .queryTooLarge(let maximum): "The retained query exceeds the \(maximum)-byte export limit."
        case .invalidTarget: "The retained result target is invalid."
        case .invalidProvider: "The retained provider identity is invalid."
        case .noColumns: "The retained result has no columns to export."
        case .tooManyColumns(let maximum): "The result exceeds the \(maximum)-column export limit."
        case .tooManyRows(let maximum): "The result exceeds the \(maximum)-row export limit."
        case .invalidColumn(let index): "Column \(index + 1) has invalid metadata."
        case .duplicateColumn(let name): "The result contains duplicate column name \(name)."
        case .invalidRowWidth(let row, let expected, let actual):
            "Row \(row + 1) contains \(actual) values; \(expected) were required."
        case .unexpectedNull(let row, let column):
            "Row \(row + 1), column \(column + 1) is NULL although the retained schema marks it required."
        case .invalidDecimal(let row, let column):
            "Row \(row + 1), column \(column + 1) contains an invalid decimal representation."
        case .invalidText(let row, let column):
            "Row \(row + 1), column \(column + 1) contains unsupported text controls."
        case .cellTooLarge(let row, let column, let maximum):
            "Row \(row + 1), column \(column + 1) exceeds the \(maximum)-byte cell limit."
        case .artifactTooLarge(let maximum): "The generated artifact exceeds the \(maximum)-byte limit."
        case .invalidDestination: "Choose a valid local export destination."
        case .destinationExists: "The selected export destination already exists."
        case .symbolicDestination: "Symbolic-link export destinations are not accepted."
        case .invalidArtifactFile(let name): "The export contains an invalid artifact file named \(name)."
        case .writeVerificationFailed(let name): "The saved artifact \(name) did not match its SHA-256 receipt."
        }
    }
}

public enum SQLTypedExportValueKind: String, Codable, CaseIterable, Sendable {
    case null
    case string
    case integer
    case decimal
    case date
    case timestamp
    case boolean
    case binary

    public var label: String { rawValue.uppercased() }
}

public struct SQLTypedExportColumnContract: Codable, Equatable, Identifiable, Sendable {
    public let ordinal: Int
    public let name: String
    public let databaseType: String
    public let isNullable: Bool
    public let ccsid: Int?
    public let observedKinds: [SQLTypedExportValueKind]

    public var id: Int { ordinal }

    public init(
        ordinal: Int,
        name: String,
        databaseType: String,
        isNullable: Bool,
        ccsid: Int?,
        observedKinds: [SQLTypedExportValueKind]
    ) {
        self.ordinal = ordinal
        self.name = name
        self.databaseType = databaseType
        self.isNullable = isNullable
        self.ccsid = ccsid
        self.observedKinds = observedKinds
    }
}

public enum SQLTypedExportTransformationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case formulaDefense
    case textEscape
    case nullToken
    case numericText
    case temporalISO8601
    case binaryBase64

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .formulaDefense: "Formula defense"
        case .textEscape: "Text escape"
        case .nullToken: "NULL token"
        case .numericText: "Exact numeric text"
        case .temporalISO8601: "ISO 8601 temporal"
        case .binaryBase64: "Base64 binary"
        }
    }

    public var detail: String {
        switch self {
        case .formulaDefense: "Formula-like text receives a reversible leading apostrophe in CSV only."
        case .textEscape: "Leading escape markers and apostrophes are reversibly escaped in CSV text."
        case .nullToken: "NULL is encoded as \\N and remains distinct from empty text."
        case .numericText: "Integers and decimals use apostrophe-prefixed exact text to prevent spreadsheet rounding."
        case .temporalISO8601: "Dates and timestamps use locale-independent UTC wire text."
        case .binaryBase64: "Binary bytes use Base64 while byte counts remain in schema evidence."
        }
    }
}

public struct SQLTypedExportTransformation: Codable, Equatable, Identifiable, Sendable {
    public let kind: SQLTypedExportTransformationKind
    public let count: Int

    public var id: SQLTypedExportTransformationKind { kind }
    public var label: String { kind.label }
    public var detail: String { kind.detail }

    public init(kind: SQLTypedExportTransformationKind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

public struct SQLTypedExportPreviewCell: Equatable, Sendable {
    public let kind: SQLTypedExportValueKind
    public let sourceDisplay: String
    public let exportDisplay: String
    public let representationChanged: Bool

    public init(
        kind: SQLTypedExportValueKind,
        sourceDisplay: String,
        exportDisplay: String,
        representationChanged: Bool
    ) {
        self.kind = kind
        self.sourceDisplay = sourceDisplay
        self.exportDisplay = exportDisplay
        self.representationChanged = representationChanged
    }
}

public struct SQLTypedExportFile: Equatable, Identifiable, Sendable {
    public let name: String
    public let mediaType: String
    public let data: Data
    public let sha256: String

    public var id: String { name }
    public var byteCount: Int { data.count }
    public var shortFingerprint: String {
        "\(sha256.prefix(8))…\(sha256.suffix(4))".uppercased()
    }

    public init(name: String, mediaType: String, data: Data) {
        self.name = name
        self.mediaType = mediaType
        self.data = data
        sha256 = AIContentFingerprint.sha256(data)
    }
}

public struct SQLTypedExportPlan: Equatable, Sendable {
    public let format: SQLTypedExportFormat
    public let targetName: String
    public let providerName: String
    public let environment: IBMEnvironment
    public let startedAt: Date
    public let elapsedMilliseconds: Int
    public let wasTruncated: Bool
    public let rowCount: Int
    public let columnCount: Int
    public let nullCount: Int
    public let formulaRiskCount: Int
    public let binaryCellCount: Int
    public let columns: [SQLTypedExportColumnContract]
    public let previewRows: [[SQLTypedExportPreviewCell]]
    public let transformations: [SQLTypedExportTransformation]
    public let files: [SQLTypedExportFile]
    public let queryFingerprint: String
    public let resultFingerprint: String
    public let schemaFingerprint: String
    public let fingerprint: String

    public var shortFingerprint: String {
        "\(fingerprint.prefix(8))…\(fingerprint.suffix(4))".uppercased()
    }

    public var attentionTransformationCount: Int {
        transformations
            .filter { $0.kind == .formulaDefense || $0.kind == .binaryBase64 }
            .reduce(0) { $0 + $1.count }
    }

    public var totalByteCount: Int { files.reduce(0) { $0 + $1.byteCount } }

    public var suggestedBaseName: String {
        let filtered = targetName.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let collapsed = String(filtered).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "db2-result" : "\(collapsed)-db2-result"
    }

    public func assistContextText() -> String {
        var lines = [
            "ITELAS DB2 TYPED EXPORT SCHEMA v1",
            "environment=\(environment.label)",
            "target=withheld",
            "provider=withheld",
            "format=\(format.rawValue)",
            "rows=\(rowCount)",
            "columns=\(columnCount)",
            "truncated=\(wasTruncated ? "yes" : "no")",
            "null-cells=\(nullCount)",
            "formula-like-text=\(formulaRiskCount)",
            "binary-cells=\(binaryCellCount)",
            "query-sha256=\(queryFingerprint)",
            "result-sha256=\(resultFingerprint)",
            "schema-sha256=\(schemaFingerprint)",
            "export-plan-sha256=\(fingerprint)",
            "",
            "SCHEMA"
        ]
        lines.append(contentsOf: columns.map { column in
            let ccsid = column.ccsid.map(String.init) ?? "unavailable"
            let kinds = column.observedKinds.map(\.rawValue).joined(separator: ",")
            return "\(column.ordinal). \(column.name) | \(column.databaseType) | nullable=\(column.isNullable ? "yes" : "no") | ccsid=\(ccsid) | observed=\(kinds)"
        })
        lines.append("")
        lines.append("REPRESENTATION CONTRACT")
        lines.append(contentsOf: transformations.map {
            "\($0.kind.rawValue)=\($0.count) | \($0.detail)"
        })
        lines.append("")
        lines.append("FILES")
        lines.append(contentsOf: files.map {
            "\($0.name) | bytes=\($0.byteCount) | sha256=\($0.sha256)"
        })
        lines.append("")
        lines.append("BOUNDARIES")
        lines.append("No query text or result cell value is included in this Assist context.")
        lines.append("The export does not prove business meaning, downstream spreadsheet behavior, authority, completeness beyond the retained row cap, or current host state.")
        lines.append("Pinning this text is local and does not send a provider request.")
        return lines.joined(separator: "\n")
    }
}

public struct SQLTypedExportBuilder: Sendable {
    private struct Statistics {
        var nulls = 0
        var formulas = 0
        var textEscapes = 0
        var numerics = 0
        var temporals = 0
        var binaries = 0
    }

    private struct CellWire: Codable {
        let kind: String
        let value: String?
        let byteCount: Int?
    }

    private struct SchemaWire: Codable {
        let version: Int
        let format: String
        let encoding: String
        let recordDelimiter: String
        let nullToken: String
        let textEscapePrefix: String
        let spreadsheetTextPrefix: String
        let decimalMode: String
        let temporalMode: String
        let binaryMode: String
        let querySHA256: String
        let resultSHA256: String
        let columns: [SQLTypedExportColumnContract]
    }

    private struct FileReceiptWire: Codable {
        let name: String
        let mediaType: String
        let byteCount: Int
        let sha256: String
    }

    private struct ReceiptWire: Codable {
        let version: Int
        let format: String
        let targetName: String
        let providerName: String
        let environment: String
        let startedAt: String
        let elapsedMilliseconds: Int
        let rowCount: Int
        let columnCount: Int
        let wasTruncated: Bool
        let querySHA256: String
        let resultSHA256: String
        let schemaSHA256: String
        let planSHA256: String
        let transformations: [String: Int]
        let payloadFiles: [FileReceiptWire]
    }

    private struct TypedDocumentWire: Codable {
        let version: Int
        let format: String
        let targetName: String
        let providerName: String
        let environment: String
        let startedAt: String
        let elapsedMilliseconds: Int
        let wasTruncated: Bool
        let querySHA256: String
        let resultSHA256: String
        let schemaSHA256: String
        let columns: [SQLTypedExportColumnContract]
        let rows: [[CellWire]]
    }

    public let limits: SQLTypedExportLimits

    public init(limits: SQLTypedExportLimits = .standard) {
        self.limits = limits
    }

    public func build(
        result: SQLResult,
        query: String,
        providerName: String,
        environment: IBMEnvironment,
        format: SQLTypedExportFormat
    ) throws -> SQLTypedExportPlan {
        try validateLimits()
        let normalizedTarget = result.targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProvider = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validMetadata(normalizedTarget, maximum: 256) else {
            throw SQLTypedExportError.invalidTarget
        }
        guard Self.validMetadata(normalizedProvider, maximum: 256) else {
            throw SQLTypedExportError.invalidProvider
        }
        guard !query.isEmpty else { throw SQLTypedExportError.emptyQuery }
        guard query.lengthOfBytes(using: .utf8) <= limits.maximumQueryUTF8Bytes else {
            throw SQLTypedExportError.queryTooLarge(maximum: limits.maximumQueryUTF8Bytes)
        }
        guard !result.columns.isEmpty else { throw SQLTypedExportError.noColumns }
        guard result.columns.count <= limits.maximumColumns else {
            throw SQLTypedExportError.tooManyColumns(maximum: limits.maximumColumns)
        }
        guard result.rows.count <= limits.maximumRows else {
            throw SQLTypedExportError.tooManyRows(maximum: limits.maximumRows)
        }

        let validatedColumns = try validateColumns(result.columns)
        var observedKinds = Array(repeating: Set<SQLTypedExportValueKind>(), count: result.columns.count)
        var statistics = Statistics()
        for (rowIndex, row) in result.rows.enumerated() {
            guard row.count == result.columns.count else {
                throw SQLTypedExportError.invalidRowWidth(
                    row: rowIndex,
                    expected: result.columns.count,
                    actual: row.count
                )
            }
            for (columnIndex, value) in row.enumerated() {
                try validate(
                    value,
                    row: rowIndex,
                    column: columnIndex,
                    nullable: result.columns[columnIndex].isNullable
                )
                observedKinds[columnIndex].insert(Self.kind(of: value))
                Self.accumulate(value, format: format, statistics: &statistics)
            }
        }
        let columns = validatedColumns.enumerated().map { index, column in
            SQLTypedExportColumnContract(
                ordinal: index + 1,
                name: column.name,
                databaseType: column.databaseType,
                isNullable: column.isNullable,
                ccsid: column.ccsid,
                observedKinds: observedKinds[index].sorted { $0.rawValue < $1.rawValue }
            )
        }
        let queryFingerprint = AIContentFingerprint.sha256(query)
        let resultFingerprint = Self.resultFingerprint(result)
        let schemaFingerprint = Self.schemaFingerprint(columns)
        let transformations = Self.transformations(statistics)
        let previewRows = result.rows.prefix(5).map { row in
            row.map { value in
                let source = Self.sourceDisplay(value)
                let exported = format == .csvBundle
                    ? Self.csvWire(value).text
                    : Self.typedCell(value).value ?? "null"
                return SQLTypedExportPreviewCell(
                    kind: Self.kind(of: value),
                    sourceDisplay: source,
                    exportDisplay: exported,
                    representationChanged: source != exported
                )
            }
        }

        let payloadFiles: [SQLTypedExportFile]
        switch format {
        case .csvBundle:
            let csv = Self.csvData(columns: columns, rows: result.rows)
            let schema = try Self.encoded(SchemaWire(
                version: 1,
                format: "csv+manifest",
                encoding: "UTF-8",
                recordDelimiter: "CRLF",
                nullToken: "\\N",
                textEscapePrefix: "\\",
                spreadsheetTextPrefix: "'",
                decimalMode: "apostrophe-prefixed exact text",
                temporalMode: "apostrophe-prefixed ISO 8601 UTC",
                binaryMode: "apostrophe-prefixed Base64",
                querySHA256: queryFingerprint,
                resultSHA256: resultFingerprint,
                columns: columns
            ))
            payloadFiles = [
                SQLTypedExportFile(name: "data.csv", mediaType: "text/csv", data: csv),
                SQLTypedExportFile(name: "schema.json", mediaType: "application/json", data: schema)
            ]
        case .typedJSON:
            let document = try Self.encoded(TypedDocumentWire(
                version: 1,
                format: "typed-json",
                targetName: normalizedTarget,
                providerName: normalizedProvider,
                environment: environment.label,
                startedAt: Self.timestamp(result.startedAt),
                elapsedMilliseconds: result.elapsedMilliseconds,
                wasTruncated: result.wasTruncated,
                querySHA256: queryFingerprint,
                resultSHA256: resultFingerprint,
                schemaSHA256: schemaFingerprint,
                columns: columns,
                rows: result.rows.map { $0.map(Self.typedCell) }
            ))
            payloadFiles = [
                SQLTypedExportFile(name: "result.typed.json", mediaType: "application/json", data: document)
            ]
        }

        let planFingerprint = AIContentFingerprint.sha256(Self.framed(
            [
                "sql-typed-export-v1",
                format.rawValue,
                queryFingerprint,
                resultFingerprint,
                schemaFingerprint
            ] + payloadFiles.flatMap { [$0.name, $0.mediaType, String($0.byteCount), $0.sha256] }
              + transformations.flatMap { [$0.kind.rawValue, String($0.count)] }
        ))
        var files = payloadFiles
        if format == .csvBundle {
            let receipt = try Self.encoded(ReceiptWire(
                version: 1,
                format: format.rawValue,
                targetName: normalizedTarget,
                providerName: normalizedProvider,
                environment: environment.label,
                startedAt: Self.timestamp(result.startedAt),
                elapsedMilliseconds: result.elapsedMilliseconds,
                rowCount: result.rows.count,
                columnCount: result.columns.count,
                wasTruncated: result.wasTruncated,
                querySHA256: queryFingerprint,
                resultSHA256: resultFingerprint,
                schemaSHA256: schemaFingerprint,
                planSHA256: planFingerprint,
                transformations: Dictionary(uniqueKeysWithValues: transformations.map {
                    ($0.kind.rawValue, $0.count)
                }),
                payloadFiles: payloadFiles.map {
                    FileReceiptWire(
                        name: $0.name,
                        mediaType: $0.mediaType,
                        byteCount: $0.byteCount,
                        sha256: $0.sha256
                    )
                }
            ))
            files.append(SQLTypedExportFile(
                name: "receipt.json",
                mediaType: "application/json",
                data: receipt
            ))
        }
        guard files.reduce(0, { $0 + $1.byteCount }) <= limits.maximumArtifactBytes else {
            throw SQLTypedExportError.artifactTooLarge(maximum: limits.maximumArtifactBytes)
        }

        return SQLTypedExportPlan(
            format: format,
            targetName: normalizedTarget,
            providerName: normalizedProvider,
            environment: environment,
            startedAt: result.startedAt,
            elapsedMilliseconds: result.elapsedMilliseconds,
            wasTruncated: result.wasTruncated,
            rowCount: result.rows.count,
            columnCount: result.columns.count,
            nullCount: statistics.nulls,
            formulaRiskCount: statistics.formulas,
            binaryCellCount: statistics.binaries,
            columns: columns,
            previewRows: previewRows,
            transformations: transformations,
            files: files,
            queryFingerprint: queryFingerprint,
            resultFingerprint: resultFingerprint,
            schemaFingerprint: schemaFingerprint,
            fingerprint: planFingerprint
        )
    }

    private func validateLimits() throws {
        guard limits.maximumColumns > 0,
              limits.maximumRows >= 0,
              limits.maximumCellUTF8Bytes > 0,
              limits.maximumQueryUTF8Bytes > 0,
              limits.maximumArtifactBytes > 0 else {
            throw SQLTypedExportError.invalidLimits
        }
    }

    private func validateColumns(_ columns: [SQLColumn]) throws -> [SQLColumn] {
        var names = Set<String>()
        for (index, column) in columns.enumerated() {
            let name = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = column.databaseType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.validMetadata(name, maximum: 256),
                  Self.validMetadata(type, maximum: 128),
                  column.ccsid.map({ (0...65_535).contains($0) }) ?? true else {
                throw SQLTypedExportError.invalidColumn(index: index)
            }
            let key = name.uppercased()
            guard names.insert(key).inserted else {
                throw SQLTypedExportError.duplicateColumn(name)
            }
        }
        return columns
    }

    private func validate(
        _ value: SQLValue,
        row: Int,
        column: Int,
        nullable: Bool
    ) throws {
        if case .null = value {
            guard nullable else { throw SQLTypedExportError.unexpectedNull(row: row, column: column) }
            return
        }
        let byteCount: Int
        switch value {
        case .string(let text):
            guard !text.contains("\0") else {
                throw SQLTypedExportError.invalidText(row: row, column: column)
            }
            byteCount = text.lengthOfBytes(using: .utf8)
        case .decimal(let decimal):
            guard Self.isDecimal(decimal) else {
                throw SQLTypedExportError.invalidDecimal(row: row, column: column)
            }
            byteCount = decimal.lengthOfBytes(using: .utf8)
        case .binary(let data): byteCount = data.count
        case .integer: byteCount = 24
        case .date, .timestamp: byteCount = 40
        case .boolean: byteCount = 5
        case .null: byteCount = 0
        }
        guard byteCount <= limits.maximumCellUTF8Bytes else {
            throw SQLTypedExportError.cellTooLarge(
                row: row,
                column: column,
                maximum: limits.maximumCellUTF8Bytes
            )
        }
    }

    private static func accumulate(
        _ value: SQLValue,
        format: SQLTypedExportFormat,
        statistics: inout Statistics
    ) {
        switch value {
        case .null: statistics.nulls += 1
        case .string(let text) where format == .csvBundle:
            if formulaLike(text) { statistics.formulas += 1 }
            if text.first == "\\" || text.first == "'" { statistics.textEscapes += 1 }
        case .integer where format == .csvBundle,
             .decimal where format == .csvBundle:
            statistics.numerics += 1
        case .date, .timestamp:
            statistics.temporals += 1
        case .binary:
            statistics.binaries += 1
        default: break
        }
    }

    private static func transformations(_ statistics: Statistics) -> [SQLTypedExportTransformation] {
        let values: [(SQLTypedExportTransformationKind, Int)] = [
            (.formulaDefense, statistics.formulas),
            (.textEscape, statistics.textEscapes),
            (.nullToken, statistics.nulls),
            (.numericText, statistics.numerics),
            (.temporalISO8601, statistics.temporals),
            (.binaryBase64, statistics.binaries)
        ]
        return values.compactMap { kind, count in
            count > 0 ? SQLTypedExportTransformation(kind: kind, count: count) : nil
        }
    }

    private static func kind(of value: SQLValue) -> SQLTypedExportValueKind {
        switch value {
        case .null: .null
        case .string: .string
        case .integer: .integer
        case .decimal: .decimal
        case .date: .date
        case .timestamp: .timestamp
        case .boolean: .boolean
        case .binary: .binary
        }
    }

    private static func typedCell(_ value: SQLValue) -> CellWire {
        switch value {
        case .null: CellWire(kind: "null", value: nil, byteCount: nil)
        case .string(let text): CellWire(kind: "string", value: text, byteCount: nil)
        case .integer(let number): CellWire(kind: "integer", value: String(number), byteCount: nil)
        case .decimal(let number): CellWire(kind: "decimal", value: number, byteCount: nil)
        case .date(let date): CellWire(kind: "date", value: dateOnly(date), byteCount: nil)
        case .timestamp(let date): CellWire(kind: "timestamp", value: timestamp(date), byteCount: nil)
        case .boolean(let value): CellWire(kind: "boolean", value: value ? "true" : "false", byteCount: nil)
        case .binary(let data): CellWire(kind: "binary", value: data.base64EncodedString(), byteCount: data.count)
        }
    }

    private static func sourceDisplay(_ value: SQLValue) -> String {
        switch value {
        case .null: "NULL"
        case .string(let text): text
        case .integer(let number): String(number)
        case .decimal(let number): number
        case .date(let date): dateOnly(date)
        case .timestamp(let date): timestamp(date)
        case .boolean(let value): value ? "TRUE" : "FALSE"
        case .binary(let data): "<\(data.count) BYTES>"
        }
    }

    private static func csvData(
        columns: [SQLTypedExportColumnContract],
        rows: [[SQLValue]]
    ) -> Data {
        var records = [columns.map { csvField(csvHeader($0.name)) }.joined(separator: ",")]
        records.append(contentsOf: rows.map { row in
            row.map { csvField(csvWire($0).text) }.joined(separator: ",")
        })
        return Data((records.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func csvHeader(_ value: String) -> String {
        if value.first == "\\" || value.first == "'" { return "\\" + value }
        return formulaLike(value) ? "'" + value : value
    }

    private static func csvWire(_ value: SQLValue) -> (text: String, changed: Bool) {
        switch value {
        case .null: return ("\\N", true)
        case .string(let text):
            if text.first == "\\" || text.first == "'" { return ("\\" + text, true) }
            if formulaLike(text) { return ("'" + text, true) }
            return (text, false)
        case .integer(let number): return ("'\(number)", true)
        case .decimal(let number): return ("'\(number)", true)
        case .date(let date): return ("'\(dateOnly(date))", true)
        case .timestamp(let date): return ("'\(timestamp(date))", true)
        case .boolean(let value): return (value ? "TRUE" : "FALSE", false)
        case .binary(let data): return ("'\(data.base64EncodedString())", true)
        }
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\r") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func formulaLike(_ value: String) -> Bool {
        guard let first = value.drop(while: { $0 == " " || $0 == "\t" }).first else { return false }
        return first == "=" || first == "+" || first == "-" || first == "@"
    }

    private static func isDecimal(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 256 else { return false }
        return value.range(
            of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func validMetadata(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty
            && value.utf8.count <= maximum
            && !value.contains("\0")
            && !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    }

    private static func resultFingerprint(_ result: SQLResult) -> String {
        var fields = [
            "sql-result-v1",
            result.targetName,
            timestamp(result.startedAt),
            String(result.elapsedMilliseconds),
            result.wasTruncated ? "truncated" : "complete"
        ]
        fields.append(contentsOf: result.columns.flatMap {
            [$0.name, $0.databaseType, $0.isNullable ? "nullable" : "required", $0.ccsid.map(String.init) ?? "ccsid-unavailable"]
        })
        fields.append(contentsOf: result.rows.flatMap { row in
            row.map { value in
                let wire = typedCell(value)
                return framed([
                    wire.kind,
                    wire.value ?? "<null>",
                    wire.byteCount.map(String.init) ?? ""
                ])
            }
        })
        return AIContentFingerprint.sha256(framed(fields))
    }

    private static func schemaFingerprint(_ columns: [SQLTypedExportColumnContract]) -> String {
        AIContentFingerprint.sha256(framed(
            ["sql-schema-v1"] + columns.flatMap {
                [
                    String($0.ordinal),
                    $0.name,
                    $0.databaseType,
                    $0.isNullable ? "nullable" : "required",
                    $0.ccsid.map(String.init) ?? "ccsid-unavailable",
                    $0.observedKinds.map(\.rawValue).joined(separator: ",")
                ]
            }
        ))
    }

    private static func framed(_ fields: [String]) -> String {
        fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public struct SQLTypedExportWriter {
    public init() {}

    @discardableResult
    public func write(
        _ plan: SQLTypedExportPlan,
        to destination: URL,
        replacingExisting: Bool = false,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard destination.isFileURL,
              !destination.lastPathComponent.isEmpty,
              destination.lastPathComponent != ".",
              destination.lastPathComponent != ".." else {
            throw SQLTypedExportError.invalidDestination
        }
        let parent = destination.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue else {
            throw SQLTypedExportError.invalidDestination
        }
        let exists = fileManager.fileExists(atPath: destination.path)
        if exists {
            let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw SQLTypedExportError.symbolicDestination }
            guard replacingExisting else { throw SQLTypedExportError.destinationExists }
        }
        for file in plan.files {
            guard Self.validFileName(file.name) else {
                throw SQLTypedExportError.invalidArtifactFile(file.name)
            }
        }

        let staging = parent.appendingPathComponent(
            ".itelas-export-\(UUID().uuidString).tmp",
            isDirectory: plan.format.isPackage
        )
        defer { try? fileManager.removeItem(at: staging) }
        if plan.format.isPackage {
            try fileManager.createDirectory(
                at: staging,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            for file in plan.files {
                let url = staging.appendingPathComponent(file.name, isDirectory: false)
                try file.data.write(to: url, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                try Self.verify(file, at: url)
            }
        } else {
            guard plan.files.count == 1, let file = plan.files.first else {
                throw SQLTypedExportError.invalidArtifactFile("typed export")
            }
            try file.data.write(to: staging, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            try Self.verify(file, at: staging)
        }

        if exists {
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: staging,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        if plan.format.isPackage {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)
            for file in plan.files {
                try Self.verify(file, at: destination.appendingPathComponent(file.name))
            }
        } else if let file = plan.files.first {
            try Self.verify(file, at: destination)
        }
        return destination
    }

    private static func validFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
            && URL(fileURLWithPath: name).lastPathComponent == name
    }

    private static func verify(_ file: SQLTypedExportFile, at url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == file.byteCount,
              AIContentFingerprint.sha256(data) == file.sha256 else {
            throw SQLTypedExportError.writeVerificationFailed(file.name)
        }
    }
}
