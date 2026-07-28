import Foundation

public struct SourceWorkspaceIncludeChainLimits: Equatable, Sendable {
    public let maximumDocuments: Int
    public let maximumDirectives: Int
    public let maximumDepth: Int

    public init(
        maximumDocuments: Int = 64,
        maximumDirectives: Int = 512,
        maximumDepth: Int = 24
    ) {
        self.maximumDocuments = min(max(1, maximumDocuments), 256)
        self.maximumDirectives = min(max(1, maximumDirectives), 4_096)
        self.maximumDepth = min(max(1, maximumDepth), 64)
    }
}

public enum SourceWorkspaceIncludeChainError: Error, Equatable, LocalizedError, Sendable {
    case rootNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .rootNotFound(let path):
            "The include-map root is not present in the current source index: \(path)."
        }
    }
}

public enum SourceWorkspaceIncludeResolution: String, CaseIterable, Sendable {
    case exact
    case shared
    case ambiguous
    case hostContentNotLoaded
    case unresolved
    case cycle
    case depthLimit
    case documentLimit

    public var label: String {
        switch self {
        case .exact: "EXACT"
        case .shared: "SHARED EXACT"
        case .ambiguous: "AMBIGUOUS"
        case .hostContentNotLoaded: "HOST CONTENT NOT LOADED"
        case .unresolved: "UNRESOLVED"
        case .cycle: "CYCLE"
        case .depthLimit: "DEPTH LIMIT"
        case .documentLimit: "DOCUMENT LIMIT"
        }
    }

    public var isBoundary: Bool {
        switch self {
        case .exact, .shared: false
        default: true
        }
    }
}

public enum SourceWorkspaceIncludeBoundaryKind: String, CaseIterable, Sendable {
    case ambiguous
    case hostContentNotLoaded
    case unresolved
    case cycle
    case depthLimit
    case documentLimit
    case directiveLimit

    public var label: String {
        switch self {
        case .ambiguous: "AMBIGUOUS TARGET"
        case .hostContentNotLoaded: "HOST CONTENT NOT LOADED"
        case .unresolved: "UNRESOLVED TARGET"
        case .cycle: "CYCLE DETECTED"
        case .depthLimit: "DEPTH LIMIT REACHED"
        case .documentLimit: "DOCUMENT LIMIT REACHED"
        case .directiveLimit: "DIRECTIVE LIMIT REACHED"
        }
    }

    public var isTraversalLimit: Bool {
        switch self {
        case .depthLimit, .documentLimit, .directiveLimit: true
        default: false
        }
    }
}

public struct SourceWorkspaceIncludeDocument: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let contentFingerprint: String
    public let depth: Int
    public let originLabel: String

    public var id: String { relativePath.uppercased() }
    public var shortFingerprint: String { String(contentFingerprint.prefix(8)).uppercased() }

    fileprivate init(document: SourceWorkspaceDocumentIndex, depth: Int) {
        relativePath = document.relativePath
        contentFingerprint = document.contentFingerprint
        self.depth = max(0, depth)
        originLabel = document.origin.label
    }
}

public struct SourceWorkspaceIncludeDirective: Equatable, Sendable, Identifiable {
    public let id: String
    public let edgeID: String
    public let sourcePath: String
    public let sourceContentFingerprint: String
    public let sourceDepth: Int
    public let kind: SourceReferenceKind
    public let targetLabel: String
    public let targetPath: String?
    public let candidatePaths: [String]
    public let resolution: SourceWorkspaceIncludeResolution
    public let range: SourceTextRange
    public let routePaths: [String]

    public var targetDepth: Int { sourceDepth + 1 }
    public var canNavigateToTarget: Bool {
        targetPath != nil && (resolution == .exact || resolution == .shared)
    }

    fileprivate init(
        edge: SourceWorkspaceDependencyEdge,
        sourceContentFingerprint: String,
        sourceDepth: Int,
        targetPath: String?,
        resolution: SourceWorkspaceIncludeResolution,
        routePaths: [String]
    ) {
        edgeID = edge.id
        sourcePath = edge.sourcePath
        self.sourceContentFingerprint = sourceContentFingerprint
        self.sourceDepth = max(0, sourceDepth)
        kind = edge.kind
        targetLabel = edge.targetLabel
        self.targetPath = targetPath
        candidatePaths = edge.targetPaths
        self.resolution = resolution
        range = edge.range
        self.routePaths = routePaths
        id = AIContentFingerprint.sha256(includeFingerprintFields([
            "itelas-include-directive-v1", edge.id, edge.sourcePath,
            sourceContentFingerprint, String(sourceDepth), edge.kind.rawValue,
            edge.targetLabel, targetPath ?? "", edge.targetPaths.joined(separator: "\n"),
            resolution.rawValue, String(edge.range.startLine), String(edge.range.startColumn),
            routePaths.joined(separator: "\n")
        ]))
    }
}

public struct SourceWorkspaceIncludeBoundary: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: SourceWorkspaceIncludeBoundaryKind
    public let sourcePath: String
    public let sourceDepth: Int
    public let targetLabel: String
    public let candidatePaths: [String]
    public let range: SourceTextRange
    public let routePaths: [String]
    public let directiveID: String?

    public var detail: String {
        switch kind {
        case .ambiguous:
            "\(candidatePaths.count) indexed candidates"
        case .hostContentNotLoaded:
            "Exact host bytes are not in this index"
        case .unresolved:
            "No indexed target was found"
        case .cycle:
            "The route returns to an upstream document"
        case .depthLimit:
            "Traversal stopped at level \(sourceDepth + 1)"
        case .documentLimit:
            "The exact closure reached its document cap"
        case .directiveLimit:
            "The include map reached its directive cap"
        }
    }

    fileprivate init(directive: SourceWorkspaceIncludeDirective, kind: SourceWorkspaceIncludeBoundaryKind) {
        self.kind = kind
        sourcePath = directive.sourcePath
        sourceDepth = directive.sourceDepth
        targetLabel = directive.targetLabel
        candidatePaths = directive.candidatePaths
        range = directive.range
        routePaths = directive.routePaths
        directiveID = directive.id
        id = AIContentFingerprint.sha256(includeFingerprintFields([
            "itelas-include-boundary-v1", kind.rawValue, directive.id,
            directive.sourcePath, String(directive.sourceDepth), directive.targetLabel,
            directive.candidatePaths.joined(separator: "\n"),
            String(directive.range.startLine), String(directive.range.startColumn),
            directive.routePaths.joined(separator: "\n")
        ]))
    }

    fileprivate init(
        kind: SourceWorkspaceIncludeBoundaryKind,
        sourcePath: String,
        sourceDepth: Int,
        targetLabel: String,
        range: SourceTextRange,
        routePaths: [String]
    ) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.sourceDepth = max(0, sourceDepth)
        self.targetLabel = targetLabel
        candidatePaths = []
        self.range = range
        self.routePaths = routePaths
        directiveID = nil
        id = AIContentFingerprint.sha256(includeFingerprintFields([
            "itelas-include-boundary-v1", kind.rawValue, sourcePath,
            String(sourceDepth), targetLabel, String(range.startLine),
            String(range.startColumn), routePaths.joined(separator: "\n")
        ]))
    }
}

public enum SourceWorkspaceIncludeCompletion: String, Sendable {
    case exact
    case boundariesVisible
    case traversalLimitReached

    public var label: String {
        switch self {
        case .exact: "EXACT CLOSURE"
        case .boundariesVisible: "BOUNDARIES VISIBLE"
        case .traversalLimitReached: "LIMIT REACHED"
        }
    }
}

public struct SourceWorkspaceIncludeChain: Equatable, Sendable, Identifiable {
    public let id: String
    public let indexFingerprint: String
    public let rootPath: String
    public let rootContentFingerprint: String
    public let documents: [SourceWorkspaceIncludeDocument]
    public let directives: [SourceWorkspaceIncludeDirective]
    public let boundaries: [SourceWorkspaceIncludeBoundary]
    public let limits: SourceWorkspaceIncludeChainLimits
    public let completion: SourceWorkspaceIncludeCompletion
    public let fingerprint: String

    public var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }
    public var maximumDepthObserved: Int {
        max(documents.map(\.depth).max() ?? 0, directives.map(\.targetDepth).max() ?? 0)
    }
    public var exactDocumentPaths: [String] { documents.map(\.relativePath) }
    public var isExact: Bool { completion == .exact }

    fileprivate init(
        index: SourceWorkspaceIndex,
        root: SourceWorkspaceDocumentIndex,
        documents: [SourceWorkspaceIncludeDocument],
        directives: [SourceWorkspaceIncludeDirective],
        boundaries: [SourceWorkspaceIncludeBoundary],
        limits: SourceWorkspaceIncludeChainLimits
    ) {
        let completion: SourceWorkspaceIncludeCompletion
        if boundaries.contains(where: { $0.kind.isTraversalLimit }) {
            completion = .traversalLimitReached
        } else if boundaries.isEmpty {
            completion = .exact
        } else {
            completion = .boundariesVisible
        }
        let fingerprint = AIContentFingerprint.sha256(includeFingerprintFields(
            [
                "itelas-source-include-chain-v1", index.fingerprint, root.relativePath,
                root.contentFingerprint, String(limits.maximumDocuments),
                String(limits.maximumDirectives), String(limits.maximumDepth), completion.rawValue
            ] + documents.flatMap {
                [$0.relativePath, $0.contentFingerprint, String($0.depth), $0.originLabel]
            } + directives.map(\.id) + boundaries.map(\.id)
        ))
        id = fingerprint
        indexFingerprint = index.fingerprint
        rootPath = root.relativePath
        rootContentFingerprint = root.contentFingerprint
        self.documents = documents
        self.directives = directives
        self.boundaries = boundaries
        self.limits = limits
        self.completion = completion
        self.fingerprint = fingerprint
    }

    public func isCurrent(for index: SourceWorkspaceIndex, rootPath: String? = nil) -> Bool {
        guard index.fingerprint == indexFingerprint,
              rootPath.map({ $0.caseInsensitiveCompare(self.rootPath) == .orderedSame }) ?? true,
              index.document(at: self.rootPath)?.contentFingerprint == rootContentFingerprint else {
            return false
        }
        return documents.allSatisfy { document in
            index.document(at: document.relativePath)?.contentFingerprint == document.contentFingerprint
        }
    }
}

public extension SourceWorkspaceIndex {
    func includeChain(
        for relativePath: String,
        limits: SourceWorkspaceIncludeChainLimits = SourceWorkspaceIncludeChainLimits()
    ) throws -> SourceWorkspaceIncludeChain {
        guard let root = document(at: relativePath) else {
            throw SourceWorkspaceIncludeChainError.rootNotFound(relativePath)
        }

        var documentsByID: [String: SourceWorkspaceIncludeDocument] = [
            root.id: SourceWorkspaceIncludeDocument(document: root, depth: 0)
        ]
        var directives: [SourceWorkspaceIncludeDirective] = []
        var boundaries: [SourceWorkspaceIncludeBoundary] = []
        var expanded: Set<String> = []
        var activeIDs: [String] = []
        var activePaths: [String] = []
        var directiveLimitReached = false

        func boundaryKind(for resolution: SourceWorkspaceIncludeResolution) -> SourceWorkspaceIncludeBoundaryKind? {
            switch resolution {
            case .ambiguous: .ambiguous
            case .hostContentNotLoaded: .hostContentNotLoaded
            case .unresolved: .unresolved
            case .cycle: .cycle
            case .depthLimit: .depthLimit
            case .documentLimit: .documentLimit
            case .exact, .shared: nil
            }
        }

        func visit(_ document: SourceWorkspaceDocumentIndex, depth: Int) throws {
            try Task.checkCancellation()
            guard !directiveLimitReached else { return }
            activeIDs.append(document.id)
            activePaths.append(document.relativePath)
            defer {
                _ = activeIDs.popLast()
                _ = activePaths.popLast()
                expanded.insert(document.id)
            }

            let includeEdges = document.dependencies
                .filter { $0.kind == .copy || $0.kind == .include }
                .sorted { lhs, rhs in
                    if lhs.range.startLine != rhs.range.startLine {
                        return lhs.range.startLine < rhs.range.startLine
                    }
                    if lhs.range.startColumn != rhs.range.startColumn {
                        return lhs.range.startColumn < rhs.range.startColumn
                    }
                    return lhs.id < rhs.id
                }

            for edge in includeEdges {
                try Task.checkCancellation()
                guard directives.count < limits.maximumDirectives else {
                    if !directiveLimitReached {
                        boundaries.append(SourceWorkspaceIncludeBoundary(
                            kind: .directiveLimit,
                            sourcePath: document.relativePath,
                            sourceDepth: depth,
                            targetLabel: edge.targetLabel,
                            range: edge.range,
                            routePaths: activePaths + [edge.targetLabel]
                        ))
                    }
                    directiveLimitReached = true
                    break
                }

                let targetPath = edge.targetPaths.count == 1 ? edge.targetPaths[0] : nil
                let resolution: SourceWorkspaceIncludeResolution
                var shouldVisitTarget = false
                var targetDocument: SourceWorkspaceDocumentIndex?

                switch edge.resolution {
                case .ambiguous:
                    resolution = .ambiguous
                case .hostBacked:
                    resolution = .hostContentNotLoaded
                case .unresolved:
                    resolution = .unresolved
                case .exact:
                    guard let targetPath, let target = self.document(at: targetPath) else {
                        resolution = .unresolved
                        break
                    }
                    targetDocument = target
                    if activeIDs.contains(target.id) {
                        resolution = .cycle
                    } else if depth + 1 > limits.maximumDepth {
                        resolution = .depthLimit
                    } else if expanded.contains(target.id) {
                        resolution = .shared
                    } else if documentsByID[target.id] == nil,
                              documentsByID.count >= limits.maximumDocuments {
                        resolution = .documentLimit
                    } else {
                        resolution = .exact
                        if documentsByID[target.id] == nil {
                            documentsByID[target.id] = SourceWorkspaceIncludeDocument(
                                document: target,
                                depth: depth + 1
                            )
                        }
                        shouldVisitTarget = true
                    }
                }

                let routeTarget = targetPath ?? edge.targetLabel
                let directive = SourceWorkspaceIncludeDirective(
                    edge: edge,
                    sourceContentFingerprint: document.contentFingerprint,
                    sourceDepth: depth,
                    targetPath: targetPath,
                    resolution: resolution,
                    routePaths: activePaths + [routeTarget]
                )
                directives.append(directive)
                if let kind = boundaryKind(for: resolution) {
                    boundaries.append(SourceWorkspaceIncludeBoundary(directive: directive, kind: kind))
                }
                if shouldVisitTarget, let targetDocument {
                    try visit(targetDocument, depth: depth + 1)
                }
            }
        }

        try visit(root, depth: 0)
        let documents = documentsByID.values.sorted { lhs, rhs in
            if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
            let lhsKey = lhs.relativePath.uppercased()
            let rhsKey = rhs.relativePath.uppercased()
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            return lhs.relativePath < rhs.relativePath
        }
        return SourceWorkspaceIncludeChain(
            index: self,
            root: root,
            documents: documents,
            directives: directives,
            boundaries: boundaries,
            limits: limits
        )
    }
}

private func includeFingerprintFields(_ values: [String]) -> String {
    values.map { "\($0.utf8.count):\($0)" }.joined(separator: "")
}
