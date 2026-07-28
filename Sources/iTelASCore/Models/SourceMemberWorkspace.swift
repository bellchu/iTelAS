import CryptoKit
import Foundation

public enum SourceMemberWorkspaceError: Error, Equatable, LocalizedError, Sendable {
    case invalidObjectName
    case objectNameTooLong
    case invalidSourceType
    case invalidSequence
    case invalidSourceDate
    case invalidRecordText
    case invalidRecordLength
    case invalidRecordCount
    case recordCountMismatch
    case sourceFormatUnsupported
    case recordSequenceNotStrictlyIncreasing
    case sourceMemberTooLarge
    case sourceLineTooWide(record: Int, maximumBytes: Int)
    case ccsidRoundTripFailed(record: Int)
    case writeAuthorityInsufficient
    case journalingInsufficient
    case triggersUnsupported
    case noChanges
    case sequenceSpaceExhausted
    case invalidRevision
    case providerResultMalformed
    case providerResultTruncated
    case revisionChanged
    case committedRevisionMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidObjectName:
            "Use a classic IBM i system name: A-Z, 0-9, _, $, #, or @, with a non-numeric first character."
        case .objectNameTooLong:
            "Classic IBM i system names are limited to 10 characters."
        case .invalidSourceType:
            "The source type is not a supported 10-character system value."
        case .invalidSequence:
            "Source sequence values must fit DECIMAL(6,2)."
        case .invalidSourceDate:
            "Source date values must contain exactly six decimal digits."
        case .invalidRecordText:
            "A source record cannot contain a line break or NUL character."
        case .invalidRecordLength:
            "The source record length or source-text length is inconsistent."
        case .invalidRecordCount:
            "The source member exceeds the bounded record limit."
        case .recordCountMismatch:
            "Catalog and record counts do not match; read the member again."
        case .sourceFormatUnsupported:
            "Only the standard SRCSEQ, SRCDAT, SRCDTA source-record layout is editable."
        case .recordSequenceNotStrictlyIncreasing:
            "Sequence values are not strictly increasing, so iTelAS will not invent a renumbering policy."
        case .sourceMemberTooLarge:
            "The source member is too large for a bounded record-aware edit."
        case .sourceLineTooWide(let record, let maximumBytes):
            "Record \(record) exceeds the \(maximumBytes)-byte SRCDTA field."
        case .ccsidRoundTripFailed(let record):
            "Record \(record) cannot round-trip through the member CCSID."
        case .writeAuthorityInsufficient:
            "The provider did not prove the read, write, update, and delete authorities needed for a transactional replacement."
        case .journalingInsufficient:
            "Member writes require active journaling with before and after images."
        case .triggersUnsupported:
            "Source files with triggers require a separately reviewed workflow."
        case .noChanges:
            "The proposed record set is identical to the opened member revision."
        case .sequenceSpaceExhausted:
            "There is no sequence-number space for the inserted records without renumbering existing records."
        case .invalidRevision:
            "The source-member revision token is malformed."
        case .providerResultMalformed:
            "The Db2 provider returned an unexpected source-member result shape."
        case .providerResultTruncated:
            "The source-member catalog reached its safety bound. Narrow the library search before treating the catalog as complete."
        case .revisionChanged:
            "The source member changed after it was opened; compare the current records before writing."
        case .committedRevisionMismatch:
            "The committed source-member records do not match the reviewed plan."
        }
    }
}

public struct IBMSystemObjectName: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ rawValue: String) throws {
        guard rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            throw SourceMemberWorkspaceError.invalidObjectName
        }
        let normalized = rawValue.uppercased()
        guard normalized.count <= 10 else {
            throw SourceMemberWorkspaceError.objectNameTooLong
        }
        let scalars = Array(normalized.unicodeScalars)
        guard let first = scalars.first,
              Self.isInitialScalar(first),
              scalars.dropFirst().allSatisfy(Self.isSubsequentScalar) else {
            throw SourceMemberWorkspaceError.invalidObjectName
        }
        value = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
    public var sqlIdentifier: String { value }

    private static func isInitialScalar(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(scalar.value) || [35, 36, 64, 95].contains(scalar.value)
    }

    private static func isSubsequentScalar(_ scalar: UnicodeScalar) -> Bool {
        isInitialScalar(scalar) || (48...57).contains(scalar.value)
    }
}

public struct SourceMemberIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let library: IBMSystemObjectName
    public let sourceFile: IBMSystemObjectName
    public let member: IBMSystemObjectName

    public init(library: String, sourceFile: String, member: String) throws {
        self.library = try IBMSystemObjectName(library)
        self.sourceFile = try IBMSystemObjectName(sourceFile)
        self.member = try IBMSystemObjectName(member)
    }

    public init(
        library: IBMSystemObjectName,
        sourceFile: IBMSystemObjectName,
        member: IBMSystemObjectName
    ) {
        self.library = library
        self.sourceFile = sourceFile
        self.member = member
    }

    public var description: String { "\(library)/\(sourceFile)(\(member))" }
    public var breadcrumb: String { "\(library) / \(sourceFile) / \(member)" }
    public var qsysPath: String {
        "/QSYS.LIB/\(library.value).LIB/\(sourceFile.value).FILE/\(member.value).MBR"
    }
}

public struct SourceMemberSequence: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let hundredths: Int

    public init(hundredths: Int) throws {
        guard (0...999_999).contains(hundredths) else {
            throw SourceMemberWorkspaceError.invalidSequence
        }
        self.hundredths = hundredths
    }

    public init(_ displayValue: String) throws {
        let pieces = displayValue.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              pieces[0].count <= 4,
              pieces[1].count == 2,
              pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let whole = Int(pieces[0]),
              let fraction = Int(pieces[1]) else {
            throw SourceMemberWorkspaceError.invalidSequence
        }
        try self.init(hundredths: whole * 100 + fraction)
    }

    public var description: String {
        String(format: "%04d.%02d", hundredths / 100, hundredths % 100)
    }

    public static func < (lhs: SourceMemberSequence, rhs: SourceMemberSequence) -> Bool {
        lhs.hundredths < rhs.hundredths
    }
}

public struct SourceMemberDateCode: Hashable, Codable, Sendable, CustomStringConvertible {
    public let digits: Int

    public init(digits: Int) throws {
        guard (0...999_999).contains(digits) else {
            throw SourceMemberWorkspaceError.invalidSourceDate
        }
        self.digits = digits
    }

    public init(_ displayValue: String) throws {
        guard displayValue.count == 6,
              displayValue.allSatisfy(\.isNumber),
              let digits = Int(displayValue) else {
            throw SourceMemberWorkspaceError.invalidSourceDate
        }
        try self.init(digits: digits)
    }

    public static let zero = try! SourceMemberDateCode(digits: 0)
    public var description: String { String(format: "%06d", digits) }
}

public struct SourceMemberRecord: Hashable, Codable, Sendable {
    public let sequence: SourceMemberSequence
    public let sourceDate: SourceMemberDateCode
    public let text: String

    public init(
        sequence: SourceMemberSequence,
        sourceDate: SourceMemberDateCode,
        text: String
    ) throws {
        guard !text.contains("\n"), !text.contains("\r"), !text.contains("\0") else {
            throw SourceMemberWorkspaceError.invalidRecordText
        }
        self.sequence = sequence
        self.sourceDate = sourceDate
        self.text = text
    }
}

public enum SourceMemberFieldLayout: String, Codable, Sendable {
    case standardThreeField
    case customSourceFields
    case unknown
}

public enum SourceMemberJournalEvidence: String, Codable, Sendable {
    case unverified
    case notJournaled
    case afterImages
    case beforeAndAfter
}

public struct SourceMemberAccess: Hashable, Codable, Sendable {
    public let canRead: Bool
    public let canWrite: Bool
    public let canUpdate: Bool
    public let canDelete: Bool

    public init(canRead: Bool, canWrite: Bool, canUpdate: Bool, canDelete: Bool) {
        self.canRead = canRead
        self.canWrite = canWrite
        self.canUpdate = canUpdate
        self.canDelete = canDelete
    }

    public var permitsTransactionalReplacement: Bool {
        canRead && canWrite && canUpdate && canDelete
    }
}

public struct SourceMemberMetadata: Hashable, Codable, Sendable {
    public static let maximumEditableRecords = 20_000

    public let identity: SourceMemberIdentity
    public let sourceType: String
    public let memberText: String
    public let recordLength: Int
    public let sourceTextByteLength: Int
    public let ccsid: Int
    public let recordCount: Int
    public let fieldLayout: SourceMemberFieldLayout
    public let access: SourceMemberAccess
    public let journalEvidence: SourceMemberJournalEvidence
    public let triggerCount: Int
    public let fileLevelIdentifier: String?
    public let lastSourceUpdate: Date?

    public init(
        identity: SourceMemberIdentity,
        sourceType: String,
        memberText: String = "",
        recordLength: Int,
        sourceTextByteLength: Int,
        ccsid: Int,
        recordCount: Int,
        fieldLayout: SourceMemberFieldLayout,
        access: SourceMemberAccess,
        journalEvidence: SourceMemberJournalEvidence,
        triggerCount: Int = 0,
        fileLevelIdentifier: String? = nil,
        lastSourceUpdate: Date? = nil
    ) throws {
        let normalizedSourceType = sourceType.uppercased()
        guard !normalizedSourceType.isEmpty,
              normalizedSourceType.count <= 10,
              normalizedSourceType.unicodeScalars.allSatisfy({
                  (65...90).contains($0.value) || (48...57).contains($0.value) || [35, 36, 64, 95].contains($0.value)
              }) else {
            throw SourceMemberWorkspaceError.invalidSourceType
        }
        guard (13...32_766).contains(recordLength),
              sourceTextByteLength == recordLength - 12,
              sourceTextByteLength > 0,
              ccsid > 0 else {
            throw SourceMemberWorkspaceError.invalidRecordLength
        }
        guard (0...Self.maximumEditableRecords).contains(recordCount), triggerCount >= 0 else {
            throw SourceMemberWorkspaceError.invalidRecordCount
        }
        self.identity = identity
        self.sourceType = normalizedSourceType
        self.memberText = memberText
        self.recordLength = recordLength
        self.sourceTextByteLength = sourceTextByteLength
        self.ccsid = ccsid
        self.recordCount = recordCount
        self.fieldLayout = fieldLayout
        self.access = access
        self.journalEvidence = journalEvidence
        self.triggerCount = triggerCount
        self.fileLevelIdentifier = fileLevelIdentifier
        self.lastSourceUpdate = lastSourceUpdate
    }

    public var codecIsAvailable: Bool {
        EBCDICCCSIDCatalog.definition(for: ccsid)?.isAvailable == true
    }
}

public struct SourceMemberRevision: Hashable, Codable, Sendable {
    public let sha256: String
    public let recordCount: Int

    public init(
        identity: SourceMemberIdentity,
        recordLength: Int,
        ccsid: Int,
        records: [SourceMemberRecord]
    ) {
        var canonical = Data("itelas-source-member-revision-v1".utf8)
        Self.append(identity.library.value, to: &canonical)
        Self.append(identity.sourceFile.value, to: &canonical)
        Self.append(identity.member.value, to: &canonical)
        Self.append(recordLength, to: &canonical)
        Self.append(ccsid, to: &canonical)
        Self.append(records.count, to: &canonical)
        for record in records {
            Self.append(record.sequence.hundredths, to: &canonical)
            Self.append(record.sourceDate.digits, to: &canonical)
            Self.append(record.text, to: &canonical)
        }
        sha256 = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        recordCount = records.count
    }

    public init(token: String) throws {
        let pieces = token.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 4,
              pieces[0] == "smrv1",
              pieces[1] == "sha256",
              pieces[2].count == 64,
              pieces[2].allSatisfy(\.isHexDigit),
              let count = Int(pieces[3]),
              (0...SourceMemberMetadata.maximumEditableRecords).contains(count) else {
            throw SourceMemberWorkspaceError.invalidRevision
        }
        sha256 = String(pieces[2]).lowercased()
        recordCount = count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(token: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }

    public var token: String { "smrv1:sha256:\(sha256):\(recordCount)" }
    public var shortFingerprint: String { "\(sha256.prefix(8))…\(sha256.suffix(4))".uppercased() }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        append(bytes.count, to: &data)
        data.append(bytes)
    }

    private static func append(_ value: Int, to data: inout Data) {
        var encoded = UInt64(value).bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }
}

public struct SourceMemberSnapshot: Equatable, Sendable {
    public let metadata: SourceMemberMetadata
    public let records: [SourceMemberRecord]
    public let revision: SourceMemberRevision

    public init(metadata: SourceMemberMetadata, records: [SourceMemberRecord]) throws {
        guard metadata.recordCount == records.count else {
            throw SourceMemberWorkspaceError.recordCountMismatch
        }
        self.metadata = metadata
        self.records = records
        revision = SourceMemberRevision(
            identity: metadata.identity,
            recordLength: metadata.recordLength,
            ccsid: metadata.ccsid,
            records: records
        )
    }

    public var text: String { records.map(\.text).joined(separator: "\n") }
    public var sequencesAreStrictlyIncreasing: Bool {
        zip(records, records.dropFirst()).allSatisfy { pair in
            pair.0.sequence < pair.1.sequence
        }
    }

    public var sourceDocument: SourceDocument {
        SourceDocument(
            identity: .member(
                library: metadata.identity.library.value,
                sourceFile: metadata.identity.sourceFile.value,
                member: metadata.identity.member.value,
                sourceType: metadata.sourceType
            ),
            format: Self.format(for: metadata.sourceType),
            ccsid: metadata.ccsid,
            sourceDatePolicy: .preserve,
            originalText: text,
            remoteRevision: revision.token
        )
    }

    private static func format(for sourceType: String) -> SourceFormat {
        switch sourceType {
        case "RPGLE", "SQLRPGLE", "RPG": .rpgle
        case "CL", "CLLE": .clle
        case "CBL", "CBLLE", "SQLCBL", "SQLCBLLE": .cobol
        case "PF", "LF", "DSPF", "PRTF", "DDS": .dds
        case "SQL": .sql
        default: .text
        }
    }
}

public enum SourceMemberDatePolicy: Hashable, Codable, Sendable {
    case preserve
    case stampChanged(SourceMemberDateCode)
    case clearChanged

    public var label: String {
        switch self {
        case .preserve: "Preserve existing; clear inserted"
        case .stampChanged(let date): "Stamp changed records \(date)"
        case .clearChanged: "Clear changed records"
        }
    }

    fileprivate func date(for original: SourceMemberDateCode?) -> SourceMemberDateCode {
        switch self {
        case .preserve: original ?? .zero
        case .stampChanged(let date): date
        case .clearChanged: .zero
        }
    }
}

public enum SourceMemberWriteGateKind: String, CaseIterable, Sendable {
    case standardFieldLayout
    case changeAuthority
    case ccsidRoundTrip
    case journalBeforeAndAfter
    case noTriggers
    case orderedSequence

    public var label: String {
        switch self {
        case .standardFieldLayout: "SRCSEQ / SRCDAT / SRCDTA"
        case .changeAuthority: "Record change authority"
        case .ccsidRoundTrip: "CCSID codec"
        case .journalBeforeAndAfter: "Journal before + after images"
        case .noTriggers: "No unreviewed triggers"
        case .orderedSequence: "Strict source sequence"
        }
    }
}

public enum SourceMemberGateState: String, Sendable {
    case ready
    case blocked
}

public struct SourceMemberWriteGate: Equatable, Sendable, Identifiable {
    public let kind: SourceMemberWriteGateKind
    public let state: SourceMemberGateState
    public let detail: String
    public var id: SourceMemberWriteGateKind { kind }
}

public struct SourceMemberWriteEligibility: Equatable, Sendable {
    public let checks: [SourceMemberWriteGate]

    public init(snapshot: SourceMemberSnapshot) {
        let metadata = snapshot.metadata
        checks = [
            SourceMemberWriteGate(
                kind: .standardFieldLayout,
                state: metadata.fieldLayout == .standardThreeField ? .ready : .blocked,
                detail: metadata.fieldLayout == .standardThreeField
                    ? "The member exposes the standard three source fields."
                    : "Custom source fields require a separate record mapping."
            ),
            SourceMemberWriteGate(
                kind: .changeAuthority,
                state: metadata.access.permitsTransactionalReplacement ? .ready : .blocked,
                detail: metadata.access.permitsTransactionalReplacement
                    ? "Read, write, update, and delete operations are available."
                    : "Transactional replacement authority is incomplete."
            ),
            SourceMemberWriteGate(
                kind: .ccsidRoundTrip,
                state: metadata.codecIsAvailable ? .ready : .blocked,
                detail: metadata.codecIsAvailable
                    ? "Native codec support is available for CCSID \(metadata.ccsid)."
                    : "CCSID \(metadata.ccsid) is outside the verified single-byte codec boundary."
            ),
            SourceMemberWriteGate(
                kind: .journalBeforeAndAfter,
                state: metadata.journalEvidence == .beforeAndAfter ? .ready : .blocked,
                detail: metadata.journalEvidence == .beforeAndAfter
                    ? "The file is journaled with before and after images."
                    : "No transactional member write is allowed without before and after journal evidence."
            ),
            SourceMemberWriteGate(
                kind: .noTriggers,
                state: metadata.triggerCount == 0 ? .ready : .blocked,
                detail: metadata.triggerCount == 0
                    ? "No trigger side effects were reported."
                    : "The source file reports \(metadata.triggerCount) trigger(s)."
            ),
            SourceMemberWriteGate(
                kind: .orderedSequence,
                state: snapshot.sequencesAreStrictlyIncreasing ? .ready : .blocked,
                detail: snapshot.sequencesAreStrictlyIncreasing
                    ? "Existing sequence values are strictly increasing."
                    : "Existing sequence values would require an explicit renumbering decision."
            )
        ]
    }

    public var isEligible: Bool { checks.allSatisfy { $0.state == .ready } }
}

public struct SourceMemberWritePlan: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let identity: SourceMemberIdentity
    public let expectedRevision: SourceMemberRevision
    public let proposedRevision: SourceMemberRevision
    public let records: [SourceMemberRecord]
    public let ccsid: Int
    public let recordLength: Int
    public let sourceTextByteLength: Int
    public let sourceDatePolicy: SourceMemberDatePolicy
    public let createdAt: Date
    public let requiresJournaledTransaction: Bool

    public init(
        snapshot: SourceMemberSnapshot,
        editedText: String,
        sourceDatePolicy: SourceMemberDatePolicy,
        createdAt: Date = Date()
    ) throws {
        let metadata = snapshot.metadata
        guard metadata.fieldLayout == .standardThreeField else {
            throw SourceMemberWorkspaceError.sourceFormatUnsupported
        }
        guard metadata.access.permitsTransactionalReplacement else {
            throw SourceMemberWorkspaceError.writeAuthorityInsufficient
        }
        guard metadata.journalEvidence == .beforeAndAfter else {
            throw SourceMemberWorkspaceError.journalingInsufficient
        }
        guard metadata.triggerCount == 0 else {
            throw SourceMemberWorkspaceError.triggersUnsupported
        }
        guard snapshot.sequencesAreStrictlyIncreasing else {
            throw SourceMemberWorkspaceError.recordSequenceNotStrictlyIncreasing
        }
        guard let codec = try? EBCDICCodec(ccsid: metadata.ccsid) else {
            throw EBCDICCodecError.unsupportedCCSID(metadata.ccsid)
        }

        let lines = editedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count <= SourceMemberMetadata.maximumEditableRecords else {
            throw SourceMemberWorkspaceError.sourceMemberTooLarge
        }
        let plannedRecords = try Self.planRecords(
            original: snapshot.records,
            editedLines: lines,
            datePolicy: sourceDatePolicy
        )
        for (offset, record) in plannedRecords.enumerated() {
            let encoded: Data
            do {
                encoded = try codec.encode(record.text)
                guard try codec.decode(encoded) == record.text else {
                    throw SourceMemberWorkspaceError.ccsidRoundTripFailed(record: offset + 1)
                }
            } catch let error as SourceMemberWorkspaceError {
                throw error
            } catch {
                throw SourceMemberWorkspaceError.ccsidRoundTripFailed(record: offset + 1)
            }
            guard encoded.count <= metadata.sourceTextByteLength else {
                throw SourceMemberWorkspaceError.sourceLineTooWide(
                    record: offset + 1,
                    maximumBytes: metadata.sourceTextByteLength
                )
            }
        }

        let proposed = SourceMemberRevision(
            identity: metadata.identity,
            recordLength: metadata.recordLength,
            ccsid: metadata.ccsid,
            records: plannedRecords
        )
        guard proposed != snapshot.revision else {
            throw SourceMemberWorkspaceError.noChanges
        }

        id = UUID()
        identity = metadata.identity
        expectedRevision = snapshot.revision
        proposedRevision = proposed
        records = plannedRecords
        ccsid = metadata.ccsid
        recordLength = metadata.recordLength
        sourceTextByteLength = metadata.sourceTextByteLength
        self.sourceDatePolicy = sourceDatePolicy
        self.createdAt = createdAt
        requiresJournaledTransaction = true
    }

    private static func planRecords(
        original: [SourceMemberRecord],
        editedLines: [String],
        datePolicy: SourceMemberDatePolicy
    ) throws -> [SourceMemberRecord] {
        let originalLines = original.map(\.text)
        let difference = editedLines.difference(from: originalLines)
        let removed = Set(difference.compactMap { change -> Int? in
            if case .remove(let offset, _, _) = change { offset } else { nil }
        })
        let inserted = Set(difference.compactMap { change -> Int? in
            if case .insert(let offset, _, _) = change { offset } else { nil }
        })

        var matches: [(old: Int, new: Int)] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < original.count || newIndex < editedLines.count {
            if oldIndex < original.count, removed.contains(oldIndex) {
                oldIndex += 1
            } else if newIndex < editedLines.count, inserted.contains(newIndex) {
                newIndex += 1
            } else if oldIndex < original.count, newIndex < editedLines.count {
                matches.append((oldIndex, newIndex))
                oldIndex += 1
                newIndex += 1
            } else {
                break
            }
        }

        var output: [SourceMemberRecord] = []
        var previousOld = -1
        var previousNew = -1
        let boundaries = matches + [(old: original.count, new: editedLines.count)]
        for boundary in boundaries {
            let oldRange = (previousOld + 1)..<boundary.old
            let newRange = (previousNew + 1)..<boundary.new
            let oldSegment = Array(original[oldRange])
            let newSegment = Array(editedLines[newRange])
            let pairedCount = min(oldSegment.count, newSegment.count)

            if pairedCount > 0 {
                for index in 0..<pairedCount {
                    output.append(try SourceMemberRecord(
                        sequence: oldSegment[index].sequence,
                        sourceDate: datePolicy.date(for: oldSegment[index].sourceDate),
                        text: newSegment[index]
                    ))
                }
            }

            if newSegment.count > pairedCount {
                let extraLines = Array(newSegment.dropFirst(pairedCount))
                let lower = output.last?.sequence
                let upper = boundary.old < original.count ? original[boundary.old].sequence : nil
                let sequences = try allocateSequences(count: extraLines.count, lower: lower, upper: upper)
                for (line, sequence) in zip(extraLines, sequences) {
                    output.append(try SourceMemberRecord(
                        sequence: sequence,
                        sourceDate: datePolicy.date(for: nil),
                        text: line
                    ))
                }
            }

            if boundary.old < original.count {
                output.append(original[boundary.old])
            }
            previousOld = boundary.old
            previousNew = boundary.new
        }
        return output
    }

    private static func allocateSequences(
        count: Int,
        lower: SourceMemberSequence?,
        upper: SourceMemberSequence?
    ) throws -> [SourceMemberSequence] {
        guard count > 0 else { return [] }
        let maximum = 999_999
        let values: [Int]
        switch (lower?.hundredths, upper?.hundredths) {
        case let (.some(low), .some(high)):
            let gap = high - low - 1
            guard gap >= count else { throw SourceMemberWorkspaceError.sequenceSpaceExhausted }
            values = (1...count).map { low + ((high - low) * $0) / (count + 1) }
        case let (.some(low), .none):
            let increment = low + count * 100 <= maximum ? 100 : 1
            guard low + count * increment <= maximum else {
                throw SourceMemberWorkspaceError.sequenceSpaceExhausted
            }
            values = (1...count).map { low + $0 * increment }
        case let (.none, .some(high)):
            let increment = count * 100 < high ? 100 : 1
            let first = high - count * increment
            guard first >= 0 else { throw SourceMemberWorkspaceError.sequenceSpaceExhausted }
            values = (0..<count).map { first + $0 * increment }
        case (.none, .none):
            guard count * 100 <= maximum else {
                throw SourceMemberWorkspaceError.sequenceSpaceExhausted
            }
            values = (1...count).map { $0 * 100 }
        }
        guard zip(values, values.dropFirst()).allSatisfy({ pair in pair.0 < pair.1 }) else {
            throw SourceMemberWorkspaceError.sequenceSpaceExhausted
        }
        return try values.map(SourceMemberSequence.init(hundredths:))
    }
}

public enum SourceMemberSQLPurpose: String, Sendable {
    case listLibraries
    case listSourceFiles
    case listMembers
    case readMetadata
    case createTemporaryAlias
    case readRecords
    case dropTemporaryAlias
}

public struct SourceMemberSQLRequest: Equatable, Sendable {
    public let purpose: SourceMemberSQLPurpose
    public let sql: String
    public let bindings: [SQLValue]
    public let maximumRows: Int
    public let timeoutSeconds: Int
    public let readOnly: Bool

    public init(
        purpose: SourceMemberSQLPurpose,
        sql: String,
        bindings: [SQLValue] = [],
        maximumRows: Int,
        timeoutSeconds: Int = 20,
        readOnly: Bool
    ) {
        self.purpose = purpose
        self.sql = sql
        self.bindings = bindings
        self.maximumRows = maximumRows
        self.timeoutSeconds = timeoutSeconds
        self.readOnly = readOnly
    }
}

public struct SourceMemberAliasPlan: Equatable, Sendable {
    public let identity: SourceMemberIdentity
    public let alias: IBMSystemObjectName
    public let create: SourceMemberSQLRequest
    public let readRecords: SourceMemberSQLRequest
    public let drop: SourceMemberSQLRequest
}

public struct SourceMemberSQLPlanner: Sendable {
    public init() {}

    public func libraries(search: String? = nil) -> SourceMemberSQLRequest {
        var sql = """
        SELECT DISTINCT SYSTEM_TABLE_SCHEMA
          FROM QSYS2.SYSFILES
         WHERE NATIVE_TYPE = 'PHYSICAL'
           AND FILE_TYPE = 'SOURCE'
        """
        var bindings: [SQLValue] = []
        if let search, !search.isEmpty {
            sql += " AND SYSTEM_TABLE_SCHEMA LIKE ? ESCAPE '\\'"
            bindings = [.string(Self.likePrefix(search))]
        }
        sql += " ORDER BY SYSTEM_TABLE_SCHEMA FETCH FIRST 500 ROWS ONLY"
        return SourceMemberSQLRequest(
            purpose: .listLibraries,
            sql: sql,
            bindings: bindings,
            maximumRows: 500,
            readOnly: true
        )
    }

    public func sourceFiles(in library: IBMSystemObjectName) -> SourceMemberSQLRequest {
        SourceMemberSQLRequest(
            purpose: .listSourceFiles,
            sql: """
            SELECT SYSTEM_TABLE_NAME, RECORD_LENGTH, COMMON_CCSID, NUMBER_MEMBERS,
                   ALLOW_READ, ALLOW_WRITE, ALLOW_UPDATE, ALLOW_DELETE
              FROM QSYS2.SYSFILES
             WHERE SYSTEM_TABLE_SCHEMA = ?
               AND NATIVE_TYPE = 'PHYSICAL'
               AND FILE_TYPE = 'SOURCE'
             ORDER BY SYSTEM_TABLE_NAME
             FETCH FIRST 1000 ROWS ONLY
            """,
            bindings: [.string(library.value)],
            maximumRows: 1_000,
            readOnly: true
        )
    }

    public func members(
        in library: IBMSystemObjectName,
        sourceFile: IBMSystemObjectName
    ) -> SourceMemberSQLRequest {
        SourceMemberSQLRequest(
            purpose: .listMembers,
            sql: """
            SELECT SYSTEM_TABLE_MEMBER, SOURCE_TYPE, TEXT_DESCRIPTION,
                   LAST_SOURCE_UPDATE_TIMESTAMP, NUMBER_ROWS
              FROM QSYS2.SYSMEMBERSTAT
             WHERE SYSTEM_TABLE_SCHEMA = ?
               AND SYSTEM_TABLE_NAME = ?
               AND SOURCE_TYPE IS NOT NULL
             ORDER BY SYSTEM_TABLE_MEMBER
             FETCH FIRST 20000 ROWS ONLY
            """,
            bindings: [.string(library.value), .string(sourceFile.value)],
            maximumRows: SourceMemberMetadata.maximumEditableRecords,
            readOnly: true
        )
    }

    public func metadata(for identity: SourceMemberIdentity) -> SourceMemberSQLRequest {
        SourceMemberSQLRequest(
            purpose: .readMetadata,
            sql: """
            SELECT F.RECORD_LENGTH, F.COMMON_CCSID, F.NUMBER_FIELDS,
                   F.ALLOW_READ, F.ALLOW_WRITE, F.ALLOW_UPDATE, F.ALLOW_DELETE,
                   F.TRIGGER_COUNT, F.FILE_LEVEL_ID,
                   M.SOURCE_TYPE, M.TEXT_DESCRIPTION, M.LAST_SOURCE_UPDATE_TIMESTAMP,
                   M.NUMBER_ROWS, J.JOURNAL_IMAGES
              FROM QSYS2.SYSFILES AS F
              JOIN QSYS2.SYSMEMBERSTAT AS M
                ON M.SYSTEM_TABLE_SCHEMA = F.SYSTEM_TABLE_SCHEMA
               AND M.SYSTEM_TABLE_NAME = F.SYSTEM_TABLE_NAME
              LEFT JOIN QSYS2.JOURNALED_OBJECTS AS J
                ON J.OBJECT_TYPE = '*FILE'
               AND J.FILE_TYPE = 'PHYSICAL'
               AND J.OBJECT_LIBRARY = F.SYSTEM_TABLE_SCHEMA
               AND J.OBJECT_NAME = F.SYSTEM_TABLE_NAME
             WHERE F.SYSTEM_TABLE_SCHEMA = ?
               AND F.SYSTEM_TABLE_NAME = ?
               AND M.SYSTEM_TABLE_MEMBER = ?
               AND F.NATIVE_TYPE = 'PHYSICAL'
               AND F.FILE_TYPE = 'SOURCE'
             FETCH FIRST 1 ROW ONLY
            """,
            bindings: [
                .string(identity.library.value),
                .string(identity.sourceFile.value),
                .string(identity.member.value)
            ],
            maximumRows: 1,
            readOnly: true
        )
    }

    public func aliasPlan(for identity: SourceMemberIdentity) throws -> SourceMemberAliasPlan {
        let alias = try temporaryAlias(for: identity)
        let qualifiedAlias = "QTEMP.\(alias.sqlIdentifier)"
        let createSQL = "CREATE ALIAS \(qualifiedAlias) FOR \(identity.library.sqlIdentifier).\(identity.sourceFile.sqlIdentifier) (\(identity.member.sqlIdentifier))"
        let readSQL = "SELECT RRN(R) AS RRN, SRCSEQ, SRCDAT, SRCDTA FROM \(qualifiedAlias) AS R ORDER BY RRN(R) FETCH FIRST 20001 ROWS ONLY"
        return SourceMemberAliasPlan(
            identity: identity,
            alias: alias,
            create: SourceMemberSQLRequest(
                purpose: .createTemporaryAlias,
                sql: createSQL,
                maximumRows: 0,
                readOnly: false
            ),
            readRecords: SourceMemberSQLRequest(
                purpose: .readRecords,
                sql: readSQL,
                maximumRows: SourceMemberMetadata.maximumEditableRecords + 1,
                readOnly: true
            ),
            drop: SourceMemberSQLRequest(
                purpose: .dropTemporaryAlias,
                sql: "DROP ALIAS \(qualifiedAlias)",
                maximumRows: 0,
                readOnly: false
            )
        )
    }

    public func transactionalReplacePlan(
        for writePlan: SourceMemberWritePlan
    ) throws -> SourceMemberTransactionalReplacePlan {
        SourceMemberTransactionalReplacePlan(
            aliasPlan: try aliasPlan(for: writePlan.identity),
            writePlan: writePlan
        )
    }

    private func temporaryAlias(for identity: SourceMemberIdentity) throws -> IBMSystemObjectName {
        let seed = Data("\(identity.library.value)/\(identity.sourceFile.value)/\(identity.member.value)".utf8)
        let suffix = SHA256.hash(data: seed).prefix(7).map { String(format: "%02X", $0) }.joined().prefix(7)
        return try IBMSystemObjectName("ITL\(suffix)")
    }

    private static func likePrefix(_ value: String) -> String {
        var escaped = ""
        for character in value.uppercased().prefix(10) {
            if character == "\\" || character == "%" || character == "_" { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped + "%"
    }
}

public struct SourceMemberTransactionalReplacePlan: Equatable, Sendable {
    public enum Isolation: String, Sendable {
        case serializable
    }

    public let aliasPlan: SourceMemberAliasPlan
    public let writePlan: SourceMemberWritePlan
    public let isolation: Isolation
    public let requiresBeforeAndAfterImages: Bool
    public let statementBatchSize: Int

    public init(aliasPlan: SourceMemberAliasPlan, writePlan: SourceMemberWritePlan) {
        self.aliasPlan = aliasPlan
        self.writePlan = writePlan
        isolation = .serializable
        requiresBeforeAndAfterImages = true
        statementBatchSize = 250
    }
}

public struct SourceMemberFileSummary: Equatable, Sendable, Identifiable {
    public let library: IBMSystemObjectName
    public let sourceFile: IBMSystemObjectName
    public let recordLength: Int
    public let ccsid: Int?
    public let memberCount: Int
    public let access: SourceMemberAccess

    public init(
        library: IBMSystemObjectName,
        sourceFile: IBMSystemObjectName,
        recordLength: Int,
        ccsid: Int?,
        memberCount: Int,
        access: SourceMemberAccess
    ) {
        self.library = library
        self.sourceFile = sourceFile
        self.recordLength = recordLength
        self.ccsid = ccsid
        self.memberCount = memberCount
        self.access = access
    }

    public var id: String { "\(library.value)/\(sourceFile.value)" }
}

public struct SourceMemberSummary: Equatable, Sendable, Identifiable {
    public let identity: SourceMemberIdentity
    public let sourceType: String
    public let text: String
    public let lastSourceUpdate: Date?
    public let recordCount: Int

    public init(
        identity: SourceMemberIdentity,
        sourceType: String,
        text: String,
        lastSourceUpdate: Date?,
        recordCount: Int
    ) {
        self.identity = identity
        self.sourceType = sourceType
        self.text = text
        self.lastSourceUpdate = lastSourceUpdate
        self.recordCount = recordCount
    }

    public var id: SourceMemberIdentity { identity }
}

public protocol SourceMemberSQLTransport: Sendable {
    var providerName: String { get }
    var targetName: String { get }
    func query(_ request: SourceMemberSQLRequest) async throws -> SQLResult
    func readMember(
        identity: SourceMemberIdentity,
        metadata: SourceMemberSQLRequest,
        aliasPlan: SourceMemberAliasPlan
    ) async throws -> SourceMemberSnapshot
    func transactionalReplace(_ plan: SourceMemberTransactionalReplacePlan) async throws -> SourceMemberSnapshot
}

public protocol IBMSourceMemberProvider: Sendable {
    var providerName: String { get }
    var targetName: String { get }
    func listLibraries(search: String?) async throws -> [IBMSystemObjectName]
    func listSourceFiles(in library: IBMSystemObjectName) async throws -> [SourceMemberFileSummary]
    func listMembers(in library: IBMSystemObjectName, sourceFile: IBMSystemObjectName) async throws -> [SourceMemberSummary]
    func read(_ identity: SourceMemberIdentity) async throws -> SourceMemberSnapshot
    func compare(_ identity: SourceMemberIdentity, expectedRevision: SourceMemberRevision) async throws -> SourceMemberSnapshot
    func write(_ plan: SourceMemberWritePlan) async throws -> SourceMemberSnapshot
}

public actor Db2SourceMemberProvider: IBMSourceMemberProvider {
    public nonisolated var providerName: String { transport.providerName }
    public nonisolated var targetName: String { transport.targetName }

    private nonisolated let transport: any SourceMemberSQLTransport
    private let planner: SourceMemberSQLPlanner

    public init(
        transport: any SourceMemberSQLTransport,
        planner: SourceMemberSQLPlanner = SourceMemberSQLPlanner()
    ) {
        self.transport = transport
        self.planner = planner
    }

    public func listLibraries(search: String? = nil) async throws -> [IBMSystemObjectName] {
        let result = try await transport.query(planner.libraries(search: search))
        guard !result.wasTruncated else { throw SourceMemberWorkspaceError.providerResultTruncated }
        let table = try SourceMemberResultTable(result)
        return try table.rows.map { row in
            guard let value = try table.value("SYSTEM_TABLE_SCHEMA", in: row).sourceMemberString else {
                throw SourceMemberWorkspaceError.providerResultMalformed
            }
            return try IBMSystemObjectName(value.trimmingCharacters(in: .whitespaces))
        }
    }

    public func listSourceFiles(in library: IBMSystemObjectName) async throws -> [SourceMemberFileSummary] {
        let result = try await transport.query(planner.sourceFiles(in: library))
        guard !result.wasTruncated else { throw SourceMemberWorkspaceError.providerResultTruncated }
        let table = try SourceMemberResultTable(result)
        return try table.rows.map { row in
            guard let name = try table.value("SYSTEM_TABLE_NAME", in: row).sourceMemberString,
                  let recordLength = try table.value("RECORD_LENGTH", in: row).sourceMemberInt,
                  let memberCount = try table.value("NUMBER_MEMBERS", in: row).sourceMemberInt else {
                throw SourceMemberWorkspaceError.providerResultMalformed
            }
            return SourceMemberFileSummary(
                library: library,
                sourceFile: try IBMSystemObjectName(name.trimmingCharacters(in: .whitespaces)),
                recordLength: recordLength,
                ccsid: try table.value("COMMON_CCSID", in: row).sourceMemberOptionalInt,
                memberCount: memberCount,
                access: SourceMemberAccess(
                    canRead: try table.value("ALLOW_READ", in: row).sourceMemberYes,
                    canWrite: try table.value("ALLOW_WRITE", in: row).sourceMemberYes,
                    canUpdate: try table.value("ALLOW_UPDATE", in: row).sourceMemberYes,
                    canDelete: try table.value("ALLOW_DELETE", in: row).sourceMemberYes
                )
            )
        }
    }

    public func listMembers(
        in library: IBMSystemObjectName,
        sourceFile: IBMSystemObjectName
    ) async throws -> [SourceMemberSummary] {
        let result = try await transport.query(planner.members(in: library, sourceFile: sourceFile))
        guard !result.wasTruncated else { throw SourceMemberWorkspaceError.providerResultTruncated }
        let table = try SourceMemberResultTable(result)
        return try table.rows.map { row in
            guard let member = try table.value("SYSTEM_TABLE_MEMBER", in: row).sourceMemberString,
                  let sourceType = try table.value("SOURCE_TYPE", in: row).sourceMemberString,
                  let recordCount = try table.value("NUMBER_ROWS", in: row).sourceMemberInt else {
                throw SourceMemberWorkspaceError.providerResultMalformed
            }
            return SourceMemberSummary(
                identity: SourceMemberIdentity(
                    library: library,
                    sourceFile: sourceFile,
                    member: try IBMSystemObjectName(member.trimmingCharacters(in: .whitespaces))
                ),
                sourceType: sourceType.trimmingCharacters(in: .whitespaces),
                text: try table.value("TEXT_DESCRIPTION", in: row).sourceMemberString?.trimmingCharacters(in: .whitespaces) ?? "",
                lastSourceUpdate: try table.value("LAST_SOURCE_UPDATE_TIMESTAMP", in: row).sourceMemberDate,
                recordCount: recordCount
            )
        }
    }

    public func read(_ identity: SourceMemberIdentity) async throws -> SourceMemberSnapshot {
        try await transport.readMember(
            identity: identity,
            metadata: planner.metadata(for: identity),
            aliasPlan: planner.aliasPlan(for: identity)
        )
    }

    public func compare(
        _ identity: SourceMemberIdentity,
        expectedRevision: SourceMemberRevision
    ) async throws -> SourceMemberSnapshot {
        let current = try await read(identity)
        guard current.revision == expectedRevision else {
            throw SourceMemberWorkspaceError.revisionChanged
        }
        return current
    }

    public func write(_ plan: SourceMemberWritePlan) async throws -> SourceMemberSnapshot {
        let committed = try await transport.transactionalReplace(
            planner.transactionalReplacePlan(for: plan)
        )
        guard committed.metadata.identity == plan.identity,
              committed.revision == plan.proposedRevision else {
            throw SourceMemberWorkspaceError.committedRevisionMismatch
        }
        return committed
    }
}

public struct SourceMemberSQLResultDecoder: Sendable {
    public init() {}

    public func decodeSnapshot(
        identity: SourceMemberIdentity,
        metadataResult: SQLResult,
        recordsResult: SQLResult
    ) throws -> SourceMemberSnapshot {
        let metadataTable = try SourceMemberResultTable(metadataResult)
        guard metadataTable.rows.count == 1,
              let metadataRow = metadataTable.rows.first,
              let recordLength = try metadataTable.value("RECORD_LENGTH", in: metadataRow).sourceMemberInt,
              let ccsid = try metadataTable.value("COMMON_CCSID", in: metadataRow).sourceMemberInt,
              let numberFields = try metadataTable.value("NUMBER_FIELDS", in: metadataRow).sourceMemberInt,
              let triggerCount = try metadataTable.value("TRIGGER_COUNT", in: metadataRow).sourceMemberInt,
              let sourceType = try metadataTable.value("SOURCE_TYPE", in: metadataRow).sourceMemberString,
              let recordCount = try metadataTable.value("NUMBER_ROWS", in: metadataRow).sourceMemberInt else {
            throw SourceMemberWorkspaceError.providerResultMalformed
        }

        let metadata = try SourceMemberMetadata(
            identity: identity,
            sourceType: sourceType.trimmingCharacters(in: .whitespacesAndNewlines),
            memberText: try metadataTable.value("TEXT_DESCRIPTION", in: metadataRow).sourceMemberString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            recordLength: recordLength,
            sourceTextByteLength: recordLength - 12,
            ccsid: ccsid,
            recordCount: recordCount,
            fieldLayout: numberFields == 3 ? .standardThreeField : .customSourceFields,
            access: SourceMemberAccess(
                canRead: try metadataTable.value("ALLOW_READ", in: metadataRow).sourceMemberYes,
                canWrite: try metadataTable.value("ALLOW_WRITE", in: metadataRow).sourceMemberYes,
                canUpdate: try metadataTable.value("ALLOW_UPDATE", in: metadataRow).sourceMemberYes,
                canDelete: try metadataTable.value("ALLOW_DELETE", in: metadataRow).sourceMemberYes
            ),
            journalEvidence: Self.journalEvidence(try metadataTable.value("JOURNAL_IMAGES", in: metadataRow)),
            triggerCount: triggerCount,
            fileLevelIdentifier: try metadataTable.value("FILE_LEVEL_ID", in: metadataRow).sourceMemberString?.trimmingCharacters(in: .whitespacesAndNewlines),
            lastSourceUpdate: try metadataTable.value("LAST_SOURCE_UPDATE_TIMESTAMP", in: metadataRow).sourceMemberDate
        )

        let recordsTable = try SourceMemberResultTable(recordsResult)
        guard recordsTable.rows.count <= SourceMemberMetadata.maximumEditableRecords else {
            throw SourceMemberWorkspaceError.sourceMemberTooLarge
        }
        let records = try recordsTable.rows.enumerated().map { offset, row in
            guard try recordsTable.value("RRN", in: row).sourceMemberInt == offset + 1,
                  let sequenceText = try recordsTable.value("SRCSEQ", in: row).sourceMemberString,
                  let dateText = Self.sourceDateText(try recordsTable.value("SRCDAT", in: row)),
                  let sourceText = try recordsTable.value("SRCDTA", in: row).sourceMemberString else {
                throw SourceMemberWorkspaceError.providerResultMalformed
            }
            return try SourceMemberRecord(
                sequence: SourceMemberSequence(sequenceText.trimmingCharacters(in: .whitespacesAndNewlines)),
                sourceDate: SourceMemberDateCode(dateText),
                text: Self.trimmingTrailingSpaces(sourceText)
            )
        }
        return try SourceMemberSnapshot(metadata: metadata, records: records)
    }

    private static func sourceDateText(_ value: SQLValue) -> String? {
        guard let number = value.sourceMemberInt, (0...999_999).contains(number) else { return nil }
        return String(format: "%06d", number)
    }

    private static func journalEvidence(_ value: SQLValue) -> SourceMemberJournalEvidence {
        guard let raw = value.sourceMemberString?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return .notJournaled
        }
        return switch raw {
        case "*BOTH": .beforeAndAfter
        case "*AFTER": .afterImages
        default: .unverified
        }
    }

    private static func trimmingTrailingSpaces(_ value: String) -> String {
        var end = value.endIndex
        while end > value.startIndex {
            let previous = value.index(before: end)
            guard value[previous] == " " else { break }
            end = previous
        }
        return String(value[..<end])
    }
}

private struct SourceMemberResultTable {
    let rows: [[SQLValue]]
    private let columns: [String: Int]

    init(_ result: SQLResult) throws {
        guard !result.columns.isEmpty else {
            throw SourceMemberWorkspaceError.providerResultMalformed
        }
        var positions: [String: Int] = [:]
        for (index, column) in result.columns.enumerated() {
            let name = column.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !name.isEmpty, positions[name] == nil else {
                throw SourceMemberWorkspaceError.providerResultMalformed
            }
            positions[name] = index
        }
        guard result.rows.allSatisfy({ $0.count == result.columns.count }) else {
            throw SourceMemberWorkspaceError.providerResultMalformed
        }
        columns = positions
        rows = result.rows
    }

    func value(_ column: String, in row: [SQLValue]) throws -> SQLValue {
        guard let index = columns[column.uppercased()], row.indices.contains(index) else {
            throw SourceMemberWorkspaceError.providerResultMalformed
        }
        return row[index]
    }
}

private extension SQLValue {
    var sourceMemberString: String? {
        switch self {
        case .string(let value), .decimal(let value): value
        case .integer(let value): String(value)
        default: nil
        }
    }

    var sourceMemberInt: Int? {
        switch self {
        case .integer(let value): Int(exactly: value)
        case .decimal(let value), .string(let value): Int(value.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    var sourceMemberOptionalInt: Int? {
        if case .null = self { return nil }
        return sourceMemberInt
    }

    var sourceMemberYes: Bool {
        sourceMemberString?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "YES"
    }

    var sourceMemberDate: Date? {
        switch self {
        case .date(let value), .timestamp(let value): value
        default: nil
        }
    }
}
