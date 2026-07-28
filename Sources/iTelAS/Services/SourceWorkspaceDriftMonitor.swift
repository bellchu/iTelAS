import CoreServices
import Darwin
import Foundation
import iTelASCore

enum SourceWorkspaceDriftMonitorError: Error, LocalizedError {
    case streamUnavailable
    case streamStartFailed

    var errorDescription: String? {
        switch self {
        case .streamUnavailable:
            "macOS could not create a recursive workspace event stream."
        case .streamStartFailed:
            "macOS could not start recursive workspace monitoring."
        }
    }
}

final class SourceWorkspaceDriftMonitor: @unchecked Sendable {
    typealias BatchHandler = @Sendable ([SourceWorkspaceDriftObservation]) -> Void

    enum Mode: Equatable {
        case fsevents
        case metadataFallback

        var label: String {
            switch self {
            case .fsevents: "FSEVENTS"
            case .metadataFallback: "METADATA FALLBACK"
            }
        }
    }

    private let rootURL: URL
    private let rootPath: String
    private let rootPathPrefix: String
    private let coalescingInterval: TimeInterval
    private let limits: SourceWorkspaceDriftLimits
    private let onBatch: BatchHandler
    private let eventQueue = DispatchQueue(label: "io.situ.itelas.source-workspace-drift")
    private var stream: FSEventStreamRef?
    private var fallbackTimer: DispatchSourceTimer?
    private var fallbackSnapshot: MetadataSnapshot?
    private var fallbackEventID: UInt64 = 0
    private var pending: [SourceWorkspaceDriftObservation] = []
    private var overflowEventCount = 0
    private var overflowMaximumEventID: UInt64 = 0
    private var deliveryWorkItem: DispatchWorkItem?
    private var startupMetadataCheck: DispatchWorkItem?
    private(set) var mode: Mode = .fsevents

    init(
        rootURL: URL,
        coalescingInterval: TimeInterval = 0.65,
        limits: SourceWorkspaceDriftLimits = SourceWorkspaceDriftLimits(),
        initialFallbackEventID: UInt64 = 0,
        onBatch: @escaping BatchHandler
    ) {
        let standardizedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.rootURL = standardizedRoot
        rootPath = standardizedRoot.path
        rootPathPrefix = standardizedRoot.path.hasSuffix("/")
            ? standardizedRoot.path
            : standardizedRoot.path + "/"
        self.coalescingInterval = max(0.1, coalescingInterval)
        self.limits = limits
        fallbackEventID = initialFallbackEventID
        self.onBatch = onBatch
    }

    func start() throws {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            createFlags
        ) else {
            try startMetadataFallback()
            return
        }
        FSEventStreamSetDispatchQueue(created, eventQueue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            try startMetadataFallback()
            return
        }
        stream = created
        mode = .fsevents
        scheduleStartupMetadataCheck()
    }

    func stop(flushPending: Bool = true) {
        startupMetadataCheck?.cancel()
        startupMetadataCheck = nil
        if let stream {
            if flushPending { FSEventStreamFlushSync(stream) }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        eventQueue.sync {
            deliveryWorkItem?.cancel()
            deliveryWorkItem = nil
            fallbackTimer?.setEventHandler {}
            fallbackTimer?.cancel()
            fallbackTimer = nil
            fallbackSnapshot = nil
            if flushPending {
                deliverPending()
            } else {
                pending.removeAll(keepingCapacity: false)
                overflowEventCount = 0
                overflowMaximumEventID = 0
            }
        }
    }

    deinit {
        deliveryWorkItem?.cancel()
        startupMetadataCheck?.cancel()
        fallbackTimer?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func startMetadataFallback() throws {
        guard let snapshot = makeMetadataSnapshot() else {
            throw SourceWorkspaceDriftMonitorError.streamStartFailed
        }
        mode = .metadataFallback
        fallbackSnapshot = snapshot
        let timer = DispatchSource.makeTimerSource(queue: eventQueue)
        timer.schedule(
            deadline: .now() + coalescingInterval,
            repeating: coalescingInterval,
            leeway: .milliseconds(80)
        )
        timer.setEventHandler { [weak self] in self?.pollMetadataFallback() }
        fallbackTimer = timer
        timer.resume()
    }

    private func scheduleStartupMetadataCheck() {
        guard fallbackSnapshot == nil, let snapshot = makeMetadataSnapshot() else { return }
        fallbackSnapshot = snapshot
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.stream != nil,
                  self.mode == .fsevents else { return }
            self.startupMetadataCheck = nil
            self.pollMetadataFallback()
            self.fallbackSnapshot = nil
        }
        startupMetadataCheck = workItem
        eventQueue.asyncAfter(
            deadline: .now() + max(0.35, coalescingInterval * 1.5),
            execute: workItem
        )
    }

    private func pollMetadataFallback() {
        guard let previous = fallbackSnapshot else { return }
        guard let current = makeMetadataSnapshot() else {
            emitFallbackRootSignal(kinds: [.rootChanged, .rescanRequired])
            return
        }
        fallbackSnapshot = current
        var observations: [SourceWorkspaceDriftObservation] = []
        let allPaths = Set(previous.entries.keys).union(current.entries.keys).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        for path in allPaths {
            let old = previous.entries[path]
            let new = current.entries[path]
            let kinds: Set<SourceWorkspaceDriftKind>
            switch (old, new) {
            case (nil, let new?):
                kinds = new.isDirectory ? [.created, .directory] : [.created]
            case (let old?, nil):
                kinds = old.isDirectory ? [.removed, .directory] : [.removed]
            case (let old?, let new?) where old != new:
                kinds = new.isDirectory ? [.modified, .directory] : [.modified, .metadata]
            default:
                continue
            }
            fallbackEventID &+= 1
            if let observation = try? SourceWorkspaceDriftObservation(
                relativePath: path,
                kinds: kinds,
                eventID: fallbackEventID,
                limits: limits
            ) {
                observations.append(observation)
            }
        }
        if previous.isTruncated || current.isTruncated {
            fallbackEventID &+= 1
            if let observation = try? SourceWorkspaceDriftObservation(
                relativePath: nil,
                kinds: [.rescanRequired],
                eventID: fallbackEventID,
                limits: limits
            ) {
                observations.insert(observation, at: 0)
            }
        }
        if !observations.isEmpty { onBatch(observations) }
    }

    private func emitFallbackRootSignal(kinds: Set<SourceWorkspaceDriftKind>) {
        fallbackEventID &+= 1
        guard let observation = try? SourceWorkspaceDriftObservation(
            relativePath: nil,
            kinds: kinds,
            eventID: fallbackEventID,
            limits: limits
        ) else { return }
        onBatch([observation])
    }

    private func makeMetadataSnapshot() -> MetadataSnapshot? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]
        guard let rootValues = try? rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return nil }

        let maximumEntries = max(10_000, SourceWorkspaceIndexLimits().maximumFiles * 2)
        var entries: [String: MetadataSignature] = [:]
        var isTruncated = false
        while let candidate = enumerator.nextObject() as? URL {
            guard entries.count < maximumEntries else {
                isTruncated = true
                break
            }
            guard let values = try? candidate.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let isDirectory = values.isDirectory == true
            guard isDirectory || (values.isRegularFile == true && SourceWorkspaceIndexService.format(for: candidate) != nil) else {
                continue
            }
            let path = candidate.standardizedFileURL.path
            guard path.hasPrefix(rootPathPrefix) else { continue }
            let relativePath = String(path.dropFirst(rootPathPrefix.count))
            guard !relativePath.isEmpty else { continue }
            entries[relativePath] = MetadataSignature(
                isDirectory: isDirectory,
                byteCount: values.fileSize ?? 0,
                modifiedNanoseconds: Int64((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000_000_000),
                resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) } ?? ""
            )
        }
        return MetadataSnapshot(entries: entries, isTruncated: isTruncated)
    }

    private func receive(
        count: Int,
        eventPaths: UnsafeMutableRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>,
        eventIDs: UnsafePointer<FSEventStreamEventId>
    ) {
        let paths = unsafeBitCast(eventPaths, to: CFArray.self) as NSArray
        for offset in 0..<count {
            guard let absolutePath = paths[offset] as? String else { continue }
            append(path: absolutePath, flags: flags[offset], eventID: UInt64(eventIDs[offset]))
        }
        scheduleDelivery()
    }

    private func append(path absolutePath: String, flags: FSEventStreamEventFlags, eventID: UInt64) {
        guard let observation = Self.observation(
            absolutePath: absolutePath,
            rootPath: rootPath,
            rootPathPrefix: rootPathPrefix,
            flags: flags,
            eventID: eventID,
            limits: limits
        ) else { return }

        if pending.count < limits.maximumRawEvents {
            pending.append(observation)
        } else {
            overflowEventCount += observation.rawEventCount
            overflowMaximumEventID = max(overflowMaximumEventID, observation.eventID)
        }
    }

    private func scheduleDelivery() {
        deliveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.deliverPending() }
        deliveryWorkItem = workItem
        eventQueue.asyncAfter(deadline: .now() + coalescingInterval, execute: workItem)
    }

    private func deliverPending() {
        deliveryWorkItem?.cancel()
        deliveryWorkItem = nil
        guard !pending.isEmpty || overflowEventCount > 0 else { return }
        var batch = pending
        if overflowEventCount > 0,
           let overflow = try? SourceWorkspaceDriftObservation(
                relativePath: nil,
                kinds: [.rescanRequired],
                rawEventCount: overflowEventCount,
                eventID: overflowMaximumEventID,
                limits: limits
           ) {
            batch.insert(overflow, at: 0)
        }
        pending.removeAll(keepingCapacity: true)
        overflowEventCount = 0
        overflowMaximumEventID = 0
        onBatch(batch)
    }

    static func observation(
        absolutePath: String,
        rootPath: String,
        rootPathPrefix: String,
        flags: FSEventStreamEventFlags,
        eventID: UInt64,
        limits: SourceWorkspaceDriftLimits = SourceWorkspaceDriftLimits()
    ) -> SourceWorkspaceDriftObservation? {
        let isRoot = absolutePath == rootPath
        guard isRoot || absolutePath.hasPrefix(rootPathPrefix) else { return nil }
        let relativePath = isRoot ? nil : String(absolutePath.dropFirst(rootPathPrefix.count))

        let requiresRescan = flags & (
            FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
        ) != 0
        let rootChanged = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
        let isDirectory = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0

        if let relativePath, !requiresRescan, !rootChanged {
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(where: { $0.hasPrefix(".") }) else { return nil }
            if !isDirectory,
               SourceWorkspaceIndexService.format(for: URL(fileURLWithPath: relativePath)) == nil {
                return nil
            }
        }

        var kinds = Set<SourceWorkspaceDriftKind>()
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 { kinds.insert(.created) }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 { kinds.insert(.removed) }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 { kinds.insert(.modified) }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 { kinds.insert(.renamed) }
        if flags & (
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod)
        ) != 0 { kinds.insert(.metadata) }
        if isDirectory { kinds.insert(.directory) }
        if rootChanged { kinds.insert(.rootChanged) }
        if requiresRescan { kinds.insert(.rescanRequired) }

        guard !kinds.isEmpty,
              let observation = try? SourceWorkspaceDriftObservation(
                relativePath: relativePath,
                kinds: kinds,
                eventID: eventID,
                limits: limits
              ) else { return nil }
        return observation
    }

    private static let callback: FSEventStreamCallback = {
        _, context, count, eventPaths, flags, eventIDs in
        guard let context else { return }
        let monitor = Unmanaged<SourceWorkspaceDriftMonitor>
            .fromOpaque(context)
            .takeUnretainedValue()
        monitor.receive(
            count: count,
            eventPaths: eventPaths,
            flags: flags,
            eventIDs: eventIDs
        )
    }
}

private struct MetadataSnapshot {
    let entries: [String: MetadataSignature]
    let isTruncated: Bool
}

private struct MetadataSignature: Equatable {
    let isDirectory: Bool
    let byteCount: Int
    let modifiedNanoseconds: Int64
    let resourceIdentifier: String
}
