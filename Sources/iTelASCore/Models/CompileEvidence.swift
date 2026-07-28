import Foundation

public struct CompileEvidenceLimits: Equatable, Sendable {
    public var maximumUTF8Bytes: Int
    public var maximumRecords: Int
    public var maximumRecordUTF8Bytes: Int
    public var maximumPathCharacters: Int
    public var maximumMessageCharacters: Int

    public init(
        maximumUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumRecords: Int = 50_000,
        maximumRecordUTF8Bytes: Int = 4_096,
        maximumPathCharacters: Int = 4_096,
        maximumMessageCharacters: Int = 2_048
    ) {
        self.maximumUTF8Bytes = maximumUTF8Bytes
        self.maximumRecords = maximumRecords
        self.maximumRecordUTF8Bytes = maximumRecordUTF8Bytes
        self.maximumPathCharacters = maximumPathCharacters
        self.maximumMessageCharacters = maximumMessageCharacters
    }

    public static let standard = CompileEvidenceLimits()
}

public enum CompileEvidenceError: Error, LocalizedError, Equatable {
    case inputTooLarge(maximum: Int)
    case invalidUTF8
    case containsNullByte
    case tooManyRecords(maximum: Int)
    case recordTooLarge(index: Int, maximum: Int)
    case malformedRecord(index: Int, kind: String)
    case invalidNumber(index: Int, field: String)
    case invalidFileContinuation(index: Int)
    case pathTooLarge(maximum: Int)
    case messageTooLarge(index: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge(let maximum):
            "The event-file evidence exceeds the \(maximum)-byte import limit."
        case .invalidUTF8:
            "The local event-file export is not valid UTF-8. Convert it explicitly before import."
        case .containsNullByte:
            "Binary or NUL-containing event-file evidence cannot be imported."
        case .tooManyRecords(let maximum):
            "The event-file evidence exceeds the \(maximum)-record import limit."
        case .recordTooLarge(let index, let maximum):
            "EVFEVENT record \(index) exceeds the \(maximum)-byte limit."
        case .malformedRecord(let index, let kind):
            "EVFEVENT record \(index) has a malformed \(kind) layout."
        case .invalidNumber(let index, let field):
            "EVFEVENT record \(index) has an invalid \(field) value."
        case .invalidFileContinuation(let index):
            "EVFEVENT record \(index) continues a file identity that was not started."
        case .pathTooLarge(let maximum):
            "An EVFEVENT source identity exceeds the \(maximum)-character limit."
        case .messageTooLarge(let index, let maximum):
            "EVFEVENT message \(index) exceeds the \(maximum)-character limit."
        }
    }
}

public enum CompileDiagnosticBand: String, Codable, CaseIterable, Sendable {
    case information
    case warning
    case error
    case severe
    case terminal

    public init(severity: Int) {
        self = switch severity {
        case ..<10: .information
        case 10..<20: .warning
        case 20..<30: .error
        case 30..<40: .severe
        default: .terminal
        }
    }

    public var label: String {
        switch self {
        case .information: "Information"
        case .warning: "Warning"
        case .error: "Error"
        case .severe: "Severe"
        case .terminal: "Terminal"
        }
    }
}

public struct CompileEvidenceSourceFile: Identifiable, Equatable, Sendable {
    public let processorSequence: Int
    public let fileIdentifier: String
    public let path: String

    public var id: String { "\(processorSequence):\(fileIdentifier):\(path)" }

    public init(processorSequence: Int, fileIdentifier: String, path: String) {
        self.processorSequence = processorSequence
        self.fileIdentifier = fileIdentifier
        self.path = path
    }
}

public struct CompileDiagnostic: Identifiable, Equatable, Sendable {
    public let recordIndex: Int
    public let processorSequence: Int
    public let fileIdentifier: String
    public let filePath: String?
    public let startLine: Int
    public let endLine: Int
    public let startColumn: Int
    public let endColumn: Int
    public let messageID: String
    public let severityLetter: String
    public let severity: Int
    public let message: String

    public var id: String {
        "\(recordIndex):\(processorSequence):\(fileIdentifier):\(messageID):\(startLine):\(startColumn)"
    }

    public var band: CompileDiagnosticBand { CompileDiagnosticBand(severity: severity) }
    public var isSourceLinked: Bool { filePath != nil && startLine > 0 }

    public init(
        recordIndex: Int,
        processorSequence: Int,
        fileIdentifier: String,
        filePath: String?,
        startLine: Int,
        endLine: Int,
        startColumn: Int,
        endColumn: Int,
        messageID: String,
        severityLetter: String,
        severity: Int,
        message: String
    ) {
        self.recordIndex = recordIndex
        self.processorSequence = processorSequence
        self.fileIdentifier = fileIdentifier
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.startColumn = startColumn
        self.endColumn = endColumn
        self.messageID = messageID
        self.severityLetter = severityLetter
        self.severity = severity
        self.message = message
    }
}

public struct CompileEvidenceParseResult: Equatable, Sendable {
    public let timestamp: String?
    public let sourceFiles: [CompileEvidenceSourceFile]
    public let diagnostics: [CompileDiagnostic]
    public let recordCount: Int
    public let expansionRecordCount: Int
    public let unknownRecordCount: Int
    public let unresolvedFileReferenceCount: Int
    public let fingerprint: String

    public init(
        timestamp: String?,
        sourceFiles: [CompileEvidenceSourceFile],
        diagnostics: [CompileDiagnostic],
        recordCount: Int,
        expansionRecordCount: Int,
        unknownRecordCount: Int,
        unresolvedFileReferenceCount: Int,
        fingerprint: String
    ) {
        self.timestamp = timestamp
        self.sourceFiles = sourceFiles
        self.diagnostics = diagnostics
        self.recordCount = recordCount
        self.expansionRecordCount = expansionRecordCount
        self.unknownRecordCount = unknownRecordCount
        self.unresolvedFileReferenceCount = unresolvedFileReferenceCount
        self.fingerprint = fingerprint
    }

    public var maximumSeverity: Int { diagnostics.map(\.severity).max() ?? 0 }
    public var hasExpansionMappings: Bool { expansionRecordCount > 0 }
}

public enum CompileEvidenceConfidence: String, Sendable {
    case high
    case medium
    case low

    public var label: String { rawValue.uppercased() }
}

public struct CompileEvidenceAnalysis: Equatable, Sendable {
    public let primaryDiagnostic: CompileDiagnostic?
    public let relatedDiagnostics: [CompileDiagnostic]
    public let informationalDiagnostics: [CompileDiagnostic]
    public let unlocatedDiagnostics: [CompileDiagnostic]
    public let confidence: CompileEvidenceConfidence
    public let selectionBasis: String

    public init(result: CompileEvidenceParseResult) {
        let sourceLinkedBlocking = result.diagnostics.filter { $0.isSourceLinked && $0.severity >= 20 }
        let highestSourceSeverity = sourceLinkedBlocking.map(\.severity).max()
        let highestCandidates = highestSourceSeverity.map { severity in
            sourceLinkedBlocking.filter { $0.severity == severity }
        } ?? []

        let primary = highestCandidates.first
        primaryDiagnostic = primary
        relatedDiagnostics = result.diagnostics.filter { diagnostic in
            diagnostic.severity >= 20 && diagnostic.id != primary?.id
        }
        informationalDiagnostics = result.diagnostics.filter { $0.severity < 20 }
        unlocatedDiagnostics = result.diagnostics.filter { !$0.isSourceLinked }

        confidence = switch highestCandidates.count {
        case 1: .high
        case 2...: .medium
        default: .low
        }
        selectionBasis = primaryDiagnostic == nil
            ? "No source-linked diagnostic at severity 20 or above was present."
            : "Primary means the first source-linked diagnostic at the highest recorded blocking severity; it is a triage lead, not proof of causality."
    }
}

public struct EVFEVENTParser: Sendable {
    private struct PendingFileIdentity {
        let recordIndex: Int
        let processorSequence: Int
        let fileIdentifier: String
        let expectedCharacters: Int
        var payload: String
    }

    public let limits: CompileEvidenceLimits

    public init(limits: CompileEvidenceLimits = .standard) {
        self.limits = limits
    }

    public func parse(data: Data) throws -> CompileEvidenceParseResult {
        guard data.count <= limits.maximumUTF8Bytes else {
            throw CompileEvidenceError.inputTooLarge(maximum: limits.maximumUTF8Bytes)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CompileEvidenceError.invalidUTF8
        }
        return try parse(text: text)
    }

    public func parse(text: String) throws -> CompileEvidenceParseResult {
        let byteCount = text.lengthOfBytes(using: .utf8)
        guard byteCount <= limits.maximumUTF8Bytes else {
            throw CompileEvidenceError.inputTooLarge(maximum: limits.maximumUTF8Bytes)
        }
        guard !text.contains("\0") else { throw CompileEvidenceError.containsNullByte }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.contains("\r") else {
            throw CompileEvidenceError.malformedRecord(index: 1, kind: "line ending")
        }
        var records = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if records.last?.isEmpty == true { records.removeLast() }
        guard records.count <= limits.maximumRecords else {
            throw CompileEvidenceError.tooManyRecords(maximum: limits.maximumRecords)
        }

        var timestamp: String?
        var processorSequence = 0
        var currentFiles: [String: String] = [:]
        var sourceFiles: [CompileEvidenceSourceFile] = []
        var diagnostics: [CompileDiagnostic] = []
        var pendingFile: PendingFileIdentity?
        var expansionRecordCount = 0
        var unknownRecordCount = 0
        var unresolvedFileReferenceCount = 0

        func integer(_ value: Substring, index: Int, field: String) throws -> Int {
            guard let number = Int(value) else {
                throw CompileEvidenceError.invalidNumber(index: index, field: field)
            }
            return number
        }

        func finalizedPath(from pending: PendingFileIdentity) throws -> String? {
            guard pending.payload.count >= pending.expectedCharacters else { return nil }
            guard pending.expectedCharacters <= limits.maximumPathCharacters else {
                throw CompileEvidenceError.pathTooLarge(maximum: limits.maximumPathCharacters)
            }
            let end = pending.payload.index(pending.payload.startIndex, offsetBy: pending.expectedCharacters)
            let path = String(pending.payload[..<end])
            guard !path.isEmpty,
                  !path.contains("\0"),
                  path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                throw CompileEvidenceError.malformedRecord(index: pending.recordIndex, kind: "FILEID")
            }
            return path
        }

        for (offset, record) in records.enumerated() {
            let recordIndex = offset + 1
            guard record.lengthOfBytes(using: .utf8) <= limits.maximumRecordUTF8Bytes else {
                throw CompileEvidenceError.recordTooLarge(index: recordIndex, maximum: limits.maximumRecordUTF8Bytes)
            }
            guard !record.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let kind = record.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""

            switch kind {
            case "TIMESTAMP":
                let fields = record.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 3 else {
                    throw CompileEvidenceError.malformedRecord(index: recordIndex, kind: kind)
                }
                timestamp = String(fields[2])

            case "PROCESSOR":
                if let pendingFile, try finalizedPath(from: pendingFile) == nil {
                    throw CompileEvidenceError.malformedRecord(index: recordIndex, kind: "FILEIDCONT")
                }
                pendingFile = nil
                processorSequence += 1
                currentFiles.removeAll(keepingCapacity: true)

            case "FILEID":
                if let pendingFile, try finalizedPath(from: pendingFile) == nil {
                    throw CompileEvidenceError.malformedRecord(index: recordIndex, kind: "FILEIDCONT")
                }
                guard let (fields, payload) = splitPrefixAndPayload(record, fieldCount: 5) else {
                    throw CompileEvidenceError.malformedRecord(index: recordIndex, kind: kind)
                }
                let fileIdentifier = String(fields[2])
                let expectedCharacters = try integer(fields[4], index: recordIndex, field: "file-name length")
                guard expectedCharacters > 0 else {
                    throw CompileEvidenceError.malformedRecord(index: recordIndex, kind: kind)
                }
                pendingFile = PendingFileIdentity(
                    recordIndex: recordIndex,
                    processorSequence: max(1, processorSequence),
                    fileIdentifier: fileIdentifier,
                    expectedCharacters: expectedCharacters,
                    payload: String(payload)
                )
                if let completed = pendingFile, let path = try finalizedPath(from: completed) {
                    currentFiles[fileIdentifier] = path
                    sourceFiles.append(.init(
                        processorSequence: completed.processorSequence,
                        fileIdentifier: fileIdentifier,
                        path: path
                    ))
                    try self.assertPathLimit(path)
                    pendingFile = nil
                }

            case "FILEIDCONT":
                guard let (fields, payload) = splitPrefixAndPayload(record, fieldCount: 5),
                      var pending = pendingFile,
                      String(fields[2]) == pending.fileIdentifier else {
                    throw CompileEvidenceError.invalidFileContinuation(index: recordIndex)
                }
                pending.payload += String(payload)
                pendingFile = pending
                if let path = try finalizedPath(from: pending) {
                    currentFiles[pending.fileIdentifier] = path
                    sourceFiles.append(.init(
                        processorSequence: pending.processorSequence,
                        fileIdentifier: pending.fileIdentifier,
                        path: path
                    ))
                    try self.assertPathLimit(path)
                    pendingFile = nil
                }

            case "ERROR":
                let fields = record.split(
                    maxSplits: 13,
                    omittingEmptySubsequences: true,
                    whereSeparator: \.isWhitespace
                )
                guard fields.count == 14 else {
                    throw CompileEvidenceError.malformedRecord(index: recordIndex, kind: kind)
                }
                let fileIdentifier = String(fields[2])
                let message = String(fields[13])
                guard message.count <= limits.maximumMessageCharacters else {
                    throw CompileEvidenceError.messageTooLarge(index: recordIndex, maximum: limits.maximumMessageCharacters)
                }
                let filePath = currentFiles[fileIdentifier]
                if filePath == nil { unresolvedFileReferenceCount += 1 }
                diagnostics.append(CompileDiagnostic(
                    recordIndex: recordIndex,
                    processorSequence: max(1, processorSequence),
                    fileIdentifier: fileIdentifier,
                    filePath: filePath,
                    startLine: try integer(fields[4], index: recordIndex, field: "start line"),
                    endLine: try integer(fields[5], index: recordIndex, field: "end line"),
                    startColumn: try integer(fields[6], index: recordIndex, field: "start column"),
                    endColumn: try integer(fields[8], index: recordIndex, field: "end column"),
                    messageID: String(fields[9]),
                    severityLetter: String(fields[10]),
                    severity: try integer(fields[11], index: recordIndex, field: "severity"),
                    message: message
                ))

            case "EXPANSION":
                expansionRecordCount += 1

            case "FILEEND":
                break

            default:
                unknownRecordCount += 1
            }
        }

        if let pendingFile, try finalizedPath(from: pendingFile) == nil {
            throw CompileEvidenceError.malformedRecord(index: max(1, records.count), kind: "FILEIDCONT")
        }

        return CompileEvidenceParseResult(
            timestamp: timestamp,
            sourceFiles: sourceFiles,
            diagnostics: diagnostics,
            recordCount: records.count,
            expansionRecordCount: expansionRecordCount,
            unknownRecordCount: unknownRecordCount,
            unresolvedFileReferenceCount: unresolvedFileReferenceCount,
            fingerprint: AIContentFingerprint.sha256(normalized)
        )
    }

    private func assertPathLimit(_ path: String) throws {
        guard path.count <= limits.maximumPathCharacters else {
            throw CompileEvidenceError.pathTooLarge(maximum: limits.maximumPathCharacters)
        }
    }

    /// Splits a record header while preserving the payload byte-for-byte after
    /// the single required field delimiter. Additional whitespace belongs to
    /// the payload, which matters when FILEIDCONT breaks immediately before a
    /// space in an IFS path.
    private func splitPrefixAndPayload(
        _ record: String,
        fieldCount: Int
    ) -> ([Substring], Substring)? {
        var fields: [Substring] = []
        var cursor = record.startIndex

        for _ in 0..<fieldCount {
            while cursor < record.endIndex, record[cursor].isWhitespace {
                cursor = record.index(after: cursor)
            }
            let fieldStart = cursor
            while cursor < record.endIndex, !record[cursor].isWhitespace {
                cursor = record.index(after: cursor)
            }
            guard fieldStart < cursor else { return nil }
            fields.append(record[fieldStart..<cursor])
        }

        guard cursor < record.endIndex, record[cursor].isWhitespace else { return nil }
        cursor = record.index(after: cursor)
        return (fields, record[cursor...])
    }
}
