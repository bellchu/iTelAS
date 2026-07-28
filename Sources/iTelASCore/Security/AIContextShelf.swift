import Foundation

/// A local, operator-curated set of context items. The shelf is inert until a
/// caller explicitly builds a request bundle from it.
public struct AIContextShelf: Equatable, Sendable {
    public let fragments: [AIContextFragment]
    public let limits: AIContextLimits

    public static let empty = AIContextShelf(
        validatedFragments: [],
        limits: .standard
    )

    public init(
        fragments: [AIContextFragment] = [],
        limits: AIContextLimits = .standard
    ) throws {
        if !fragments.isEmpty {
            _ = try AIContextBundle(fragments: fragments, limits: limits)
        }
        self.fragments = fragments
        self.limits = limits
    }

    private init(
        validatedFragments: [AIContextFragment],
        limits: AIContextLimits
    ) {
        fragments = validatedFragments
        self.limits = limits
    }

    public var isEmpty: Bool { fragments.isEmpty }
    public var count: Int { fragments.count }
    public var totalUTF8Bytes: Int {
        fragments.reduce(into: 0) { $0 += $1.utf8ByteCount }
    }

    /// Pins one evidence kind. Pinning the same kind again replaces its stale
    /// value in place instead of silently attaching two ambiguous versions.
    public func pinning(_ fragment: AIContextFragment) throws -> AIContextShelf {
        var updated = fragments
        if let index = updated.firstIndex(where: { $0.kind == fragment.kind }) {
            updated[index] = fragment
        } else {
            updated.append(fragment)
        }
        return try AIContextShelf(fragments: updated, limits: limits)
    }

    public func removing(_ kind: AIContextKind) -> AIContextShelf {
        AIContextShelf(
            validatedFragments: fragments.filter { $0.kind != kind },
            limits: limits
        )
    }

    public func removingAll() -> AIContextShelf {
        AIContextShelf(validatedFragments: [], limits: limits)
    }

    /// Produces the exact immutable request bundle. An empty shelf produces no
    /// bundle, which preserves the default of sharing nothing.
    public func requestBundle() throws -> AIContextBundle? {
        guard !fragments.isEmpty else { return nil }
        return try AIContextBundle(fragments: fragments, limits: limits)
    }
}
