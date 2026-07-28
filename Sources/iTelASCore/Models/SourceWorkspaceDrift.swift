import Foundation

public struct SourceWorkspaceDriftLimits: Equatable, Sendable {
    public let maximumUniquePaths: Int
    public let maximumRawEvents: Int
    public let maximumRelativePathUTF8Bytes: Int

    public init(
        maximumUniquePaths: Int = 256,
        maximumRawEvents: Int = 2_048,
        maximumRelativePathUTF8Bytes: Int = 1_024
    ) {
        self.maximumUniquePaths = max(1, maximumUniquePaths)
        self.maximumRawEvents = max(1, maximumRawEvents)
        self.maximumRelativePathUTF8Bytes = max(1, maximumRelativePathUTF8Bytes)
    }
}

public enum SourceWorkspaceDriftKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case created
    case removed
    case modified
    case renamed
    case metadata
    case directory
    case rootChanged
    case rescanRequired

    public var label: String {
        switch self {
        case .created: "CREATED"
        case .removed: "REMOVED"
        case .modified: "MODIFIED"
        case .renamed: "RENAMED"
        case .metadata: "METADATA"
        case .directory: "DIRECTORY"
        case .rootChanged: "ROOT CHANGED"
        case .rescanRequired: "RESCAN REQUIRED"
        }
    }
}

public enum SourceWorkspaceDriftError: Error, Equatable, LocalizedError, Sendable {
    case invalidRelativePath
    case relativePathTooLong(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            "A workspace signal contained an unsafe relative path."
        case .relativePathTooLong(let limit):
            "A workspace signal path exceeded the \(limit)-byte limit."
        }
    }
}

public struct SourceWorkspaceDriftObservation: Equatable, Sendable {
    public let relativePath: String?
    public let kinds: Set<SourceWorkspaceDriftKind>
    public let rawEventCount: Int
    public let eventID: UInt64

    public init(
        relativePath: String?,
        kinds: Set<SourceWorkspaceDriftKind>,
        rawEventCount: Int = 1,
        eventID: UInt64,
        limits: SourceWorkspaceDriftLimits = SourceWorkspaceDriftLimits()
    ) throws {
        if let relativePath {
            self.relativePath = try Self.validate(relativePath, limits: limits)
        } else {
            self.relativePath = nil
        }
        self.kinds = kinds.isEmpty ? [.modified] : kinds
        self.rawEventCount = max(1, rawEventCount)
        self.eventID = eventID
    }

    private static func validate(
        _ path: String,
        limits: SourceWorkspaceDriftLimits
    ) throws -> String {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw SourceWorkspaceDriftError.invalidRelativePath
        }
        guard path.lengthOfBytes(using: .utf8) <= limits.maximumRelativePathUTF8Bytes else {
            throw SourceWorkspaceDriftError.relativePathTooLong(limits.maximumRelativePathUTF8Bytes)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw SourceWorkspaceDriftError.invalidRelativePath
        }
        return path
    }
}

public struct SourceWorkspaceDriftEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let relativePath: String?
    public let kinds: [SourceWorkspaceDriftKind]
    public let rawEventCount: Int
    public let maximumEventID: UInt64

    public var displayPath: String { relativePath ?? "WORKSPACE ROOT" }
    public var kindLabel: String { kinds.map(\.label).joined(separator: " + ") }
    public var shortFingerprint: String { String(id.prefix(8)).uppercased() }

    fileprivate init(
        relativePath: String?,
        kinds: Set<SourceWorkspaceDriftKind>,
        rawEventCount: Int,
        maximumEventID: UInt64
    ) {
        let sortedKinds = kinds.sorted { $0.rawValue < $1.rawValue }
        let identifier = AIContentFingerprint.sha256(driftFields([
            "itelas-source-drift-entry-v1",
            relativePath ?? "",
            sortedKinds.map(\.rawValue).joined(separator: ","),
            String(rawEventCount)
        ]))
        id = identifier
        self.relativePath = relativePath
        self.kinds = sortedKinds
        self.rawEventCount = rawEventCount
        self.maximumEventID = maximumEventID
    }
}

public struct SourceWorkspaceDriftReceipt: Equatable, Sendable, Identifiable {
    public let id: String
    public let baselineIndexFingerprint: String
    public let entries: [SourceWorkspaceDriftEntry]
    public let rawEventCount: Int
    public let maximumEventID: UInt64
    public let isTruncated: Bool
    public let requiresFullVerification: Bool
    public let fingerprint: String

    public var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }
    public var uniquePathCount: Int { entries.count }
    public var hasPendingSignals: Bool { rawEventCount > 0 || isTruncated }

    public init(
        baselineIndexFingerprint: String,
        observations: [SourceWorkspaceDriftObservation],
        limits: SourceWorkspaceDriftLimits = SourceWorkspaceDriftLimits()
    ) {
        struct Accumulator {
            var displayPath: String?
            var kinds: Set<SourceWorkspaceDriftKind>
            var rawEventCount: Int
            var maximumEventID: UInt64
        }

        let boundedObservations = Array(observations.prefix(limits.maximumRawEvents))
        var accumulators: [String: Accumulator] = [:]
        var overflowedUniquePathLimit = false
        for observation in boundedObservations {
            let key = Self.canonicalKey(observation.relativePath)
            if var accumulator = accumulators[key] {
                if let candidate = observation.relativePath,
                   accumulator.displayPath.map({ candidate < $0 }) ?? true {
                    accumulator.displayPath = candidate
                }
                accumulator.kinds.formUnion(observation.kinds)
                accumulator.rawEventCount += observation.rawEventCount
                accumulator.maximumEventID = max(accumulator.maximumEventID, observation.eventID)
                accumulators[key] = accumulator
            } else if accumulators.count < limits.maximumUniquePaths {
                accumulators[key] = Accumulator(
                    displayPath: observation.relativePath,
                    kinds: observation.kinds,
                    rawEventCount: observation.rawEventCount,
                    maximumEventID: observation.eventID
                )
            } else {
                overflowedUniquePathLimit = true
            }
        }

        let entries = accumulators.values.map {
            SourceWorkspaceDriftEntry(
                relativePath: $0.displayPath,
                kinds: $0.kinds,
                rawEventCount: $0.rawEventCount,
                maximumEventID: $0.maximumEventID
            )
        }.sorted { lhs, rhs in
            Self.canonicalKey(lhs.relativePath) < Self.canonicalKey(rhs.relativePath)
        }
        let rawEventCount = observations.reduce(0) { partial, observation in
            let (sum, overflow) = partial.addingReportingOverflow(observation.rawEventCount)
            return overflow ? Int.max : sum
        }
        let maximumEventID = observations.map(\.eventID).max() ?? 0
        let isTruncated = observations.count > limits.maximumRawEvents
            || rawEventCount > limits.maximumRawEvents
            || overflowedUniquePathLimit
        let requiresFullVerification = isTruncated || entries.contains { entry in
            entry.kinds.contains(.rootChanged) || entry.kinds.contains(.rescanRequired)
        }
        let fingerprint = AIContentFingerprint.sha256(driftFields(
            [
                "itelas-source-drift-receipt-v1",
                baselineIndexFingerprint,
                String(rawEventCount),
                isTruncated ? "truncated" : "complete",
                requiresFullVerification ? "full" : "incremental"
            ] + entries.map(\.id)
        ))
        id = fingerprint
        self.baselineIndexFingerprint = baselineIndexFingerprint
        self.entries = entries
        self.rawEventCount = rawEventCount
        self.maximumEventID = maximumEventID
        self.isTruncated = isTruncated
        self.requiresFullVerification = requiresFullVerification
        self.fingerprint = fingerprint
    }

    public func isBound(to indexFingerprint: String) -> Bool {
        baselineIndexFingerprint == indexFingerprint
    }

    public static func observations(
        _ observations: [SourceWorkspaceDriftObservation],
        afterClearingThrough eventID: UInt64
    ) -> [SourceWorkspaceDriftObservation] {
        observations.filter { $0.eventID > eventID }
    }

    private static func canonicalKey(_ path: String?) -> String {
        path?.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased(with: Locale(identifier: "en_US_POSIX")) ?? ""
    }
}

private func driftFields(_ values: [String]) -> String {
    values.map { "\($0.utf8.count):\($0)" }.joined()
}
