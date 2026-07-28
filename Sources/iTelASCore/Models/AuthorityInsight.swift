import Foundation

public struct AuthorityInsightLimits: Equatable, Sendable {
    public var maximumGroupRows: Int
    public var maximumPrivilegeRows: Int
    public var maximumAuthorizationListRows: Int
    public var maximumRuntimeRows: Int
    public var queryTimeoutSeconds: Int

    public init(
        maximumGroupRows: Int = 16,
        maximumPrivilegeRows: Int = 100,
        maximumAuthorizationListRows: Int = 100,
        maximumRuntimeRows: Int = 100,
        queryTimeoutSeconds: Int = 30
    ) {
        self.maximumGroupRows = maximumGroupRows
        self.maximumPrivilegeRows = maximumPrivilegeRows
        self.maximumAuthorizationListRows = maximumAuthorizationListRows
        self.maximumRuntimeRows = maximumRuntimeRows
        self.queryTimeoutSeconds = queryTimeoutSeconds
    }

    public static let standard = AuthorityInsightLimits()
}

public enum AuthorityInsightError: Error, Equatable, LocalizedError, Sendable {
    case duplicateColumn(source: String, column: String)
    case missingColumn(source: String, column: String)
    case malformedRow(source: String, index: Int)
    case tooManyRows(source: String, maximum: Int)
    case truncatedResult(source: String)
    case identityMismatch(source: String)
    case invalidValue(source: String, index: Int, column: String)
    case invalidText(source: String, index: Int, column: String)

    public var errorDescription: String? {
        switch self {
        case .duplicateColumn(let source, let column):
            "The \(source) result contains an ambiguous duplicate \(column) column."
        case .missingColumn(let source, let column):
            "The \(source) result does not contain the required \(column) column."
        case .malformedRow(let source, let index):
            "The \(source) result row \(index) does not match its column layout."
        case .tooManyRows(let source, let maximum):
            "The \(source) result exceeds the \(maximum)-row evidence limit."
        case .truncatedResult(let source):
            "The \(source) result was truncated, so the authority evidence is incomplete."
        case .identityMismatch(let source):
            "The \(source) result did not describe the requested exact subject and object scope."
        case .invalidValue(let source, let index, let column):
            "The \(source) result row \(index) contains an invalid \(column) value."
        case .invalidText(let source, let index, let column):
            "The \(source) result row \(index) contains unsafe or oversized \(column) text."
        }
    }
}

public struct AuthoritySubject: Hashable, Codable, Sendable, CustomStringConvertible {
    public let profile: IBMSystemObjectName

    public init(_ profile: String) throws {
        self.profile = try IBMSystemObjectName(profile)
    }

    public init(profile: IBMSystemObjectName) {
        self.profile = profile
    }

    public var description: String { profile.value }
}

public enum AuthorityEvidenceSource: String, CaseIterable, Sendable {
    case userInfo = "USER_INFO"
    case groupProfileEntries = "GROUP_PROFILE_ENTRIES"
    case objectPrivileges = "OBJECT_PRIVILEGES"
    case authorizationListUserInfo = "AUTHORIZATION_LIST_USER_INFO"
    case authorityCollection = "AUTHORITY_COLLECTION"
    case effectiveAuthorityResolution = "EFFECTIVE_AUTHORITY_RESOLUTION"

    public static let liveSQLSources: [Self] = [
        .userInfo,
        .groupProfileEntries,
        .objectPrivileges,
        .authorizationListUserInfo,
        .authorityCollection
    ]
}

public enum AuthorityEvidenceOutcome: Equatable, Sendable {
    case collected
    case unavailable(String)

    public var isCollected: Bool {
        if case .collected = self { return true }
        return false
    }
}

public struct AuthorityEvidenceReceipt: Equatable, Sendable, Identifiable {
    public let source: AuthorityEvidenceSource
    public let rowCount: Int
    public let boundWasReached: Bool
    public let elapsedMilliseconds: Int?
    public let queryFingerprint: String
    public let outcome: AuthorityEvidenceOutcome

    public var id: AuthorityEvidenceSource { source }

    public init(
        source: AuthorityEvidenceSource,
        rowCount: Int,
        boundWasReached: Bool,
        elapsedMilliseconds: Int?,
        queryFingerprint: String,
        outcome: AuthorityEvidenceOutcome
    ) {
        self.source = source
        self.rowCount = rowCount
        self.boundWasReached = boundWasReached
        self.elapsedMilliseconds = elapsedMilliseconds
        self.queryFingerprint = queryFingerprint
        self.outcome = outcome
    }
}

public struct AuthorityProfileSnapshot: Equatable, Sendable {
    public let subject: AuthoritySubject
    public let status: String
    public let userClass: String
    public let specialAuthorities: [String]
    public let primaryGroup: String?
    public let supplementalGroupCount: Int
    public let authorityCollectionActive: Bool
    public let authorityCollectionRepositoryExists: Bool
    public let lastUsedAt: Date?

    public init(
        subject: AuthoritySubject,
        status: String,
        userClass: String,
        specialAuthorities: [String],
        primaryGroup: String?,
        supplementalGroupCount: Int,
        authorityCollectionActive: Bool,
        authorityCollectionRepositoryExists: Bool,
        lastUsedAt: Date?
    ) {
        self.subject = subject
        self.status = status
        self.userClass = userClass
        self.specialAuthorities = Array(Set(specialAuthorities.map { $0.uppercased() })).sorted()
        self.primaryGroup = primaryGroup?.uppercased()
        self.supplementalGroupCount = supplementalGroupCount
        self.authorityCollectionActive = authorityCollectionActive
        self.authorityCollectionRepositoryExists = authorityCollectionRepositoryExists
        self.lastUsedAt = lastUsedAt
    }
}

public struct AuthorityGroupMembership: Equatable, Hashable, Sendable, Identifiable {
    public let groupProfile: String
    public let userProfile: String
    public let userText: String?

    public var id: String { groupProfile }

    public init(groupProfile: String, userProfile: String, userText: String? = nil) {
        self.groupProfile = groupProfile.uppercased()
        self.userProfile = userProfile.uppercased()
        self.userText = userText
    }
}

public struct AuthoritySurface: Equatable, Sendable {
    public let authorizationListManagement: Bool
    public let objectOperational: Bool
    public let objectManagement: Bool
    public let objectExistence: Bool
    public let objectAlter: Bool
    public let objectReference: Bool
    public let dataRead: Bool
    public let dataAdd: Bool
    public let dataUpdate: Bool
    public let dataDelete: Bool
    public let dataExecute: Bool

    public init(
        authorizationListManagement: Bool = false,
        objectOperational: Bool = false,
        objectManagement: Bool = false,
        objectExistence: Bool = false,
        objectAlter: Bool = false,
        objectReference: Bool = false,
        dataRead: Bool = false,
        dataAdd: Bool = false,
        dataUpdate: Bool = false,
        dataDelete: Bool = false,
        dataExecute: Bool = false
    ) {
        self.authorizationListManagement = authorizationListManagement
        self.objectOperational = objectOperational
        self.objectManagement = objectManagement
        self.objectExistence = objectExistence
        self.objectAlter = objectAlter
        self.objectReference = objectReference
        self.dataRead = dataRead
        self.dataAdd = dataAdd
        self.dataUpdate = dataUpdate
        self.dataDelete = dataDelete
        self.dataExecute = dataExecute
    }

    public var hasAnyAuthority: Bool {
        authorizationListManagement || objectOperational || objectManagement || objectExistence
            || objectAlter || objectReference || dataRead || dataAdd || dataUpdate || dataDelete
            || dataExecute
    }

    public var carriesDataChange: Bool { dataAdd || dataUpdate || dataDelete }

    public static let none = AuthoritySurface()
    public static let all = AuthoritySurface(
        authorizationListManagement: true,
        objectOperational: true,
        objectManagement: true,
        objectExistence: true,
        objectAlter: true,
        objectReference: true,
        dataRead: true,
        dataAdd: true,
        dataUpdate: true,
        dataDelete: true,
        dataExecute: true
    )

    public static func inferred(from authority: String?) -> AuthoritySurface {
        switch authority?.uppercased() {
        case "*ALL":
            .all
        case "*CHANGE":
            AuthoritySurface(
                objectOperational: true,
                dataRead: true,
                dataAdd: true,
                dataUpdate: true,
                dataDelete: true,
                dataExecute: true
            )
        case "*USE":
            AuthoritySurface(objectOperational: true, dataRead: true, dataExecute: true)
        default:
            .none
        }
    }
}

public struct AuthorityObjectGrant: Equatable, Sendable, Identifiable {
    public let target: IBMObjectIdentity
    public let authorizationName: String
    public let objectAuthority: String
    public let owner: String
    public let authorizationList: String?
    public let primaryGroup: String?
    public let isObjectOwner: Bool
    public let surface: AuthoritySurface

    public var id: String {
        [target.description, authorizationName, objectAuthority, authorizationList ?? ""].joined(separator: "\u{1F}")
    }

    public init(
        target: IBMObjectIdentity,
        authorizationName: String,
        objectAuthority: String,
        owner: String,
        authorizationList: String?,
        primaryGroup: String?,
        isObjectOwner: Bool,
        surface: AuthoritySurface
    ) {
        self.target = target
        self.authorizationName = authorizationName.uppercased()
        self.objectAuthority = objectAuthority.uppercased()
        self.owner = owner.uppercased()
        self.authorizationList = authorizationList?.uppercased()
        self.primaryGroup = primaryGroup?.uppercased()
        self.isObjectOwner = isObjectOwner
        self.surface = surface
    }
}

public struct AuthorityAuthorizationListGrant: Equatable, Sendable, Identifiable {
    public let authorizationList: String
    public let authorizationName: String
    public let objectAuthority: String
    public let owner: String
    public let surface: AuthoritySurface

    public var id: String {
        [authorizationList, authorizationName, objectAuthority].joined(separator: "\u{1F}")
    }

    public init(
        authorizationList: String,
        authorizationName: String,
        objectAuthority: String,
        owner: String,
        surface: AuthoritySurface
    ) {
        self.authorizationList = authorizationList.uppercased()
        self.authorizationName = authorizationName.uppercased()
        self.objectAuthority = objectAuthority.uppercased()
        self.owner = owner.uppercased()
        self.surface = surface
    }
}

public struct AuthorityRuntimeObservation: Equatable, Sendable, Identifiable {
    public let subject: AuthoritySubject
    public let target: IBMObjectIdentity
    public let checkedAt: Date?
    public let checkSucceeded: Bool?
    public let requiredAuthority: String?
    public let detailedRequiredAuthority: String?
    public let currentAuthority: String?
    public let detailedCurrentAuthority: String?
    public let authoritySource: String?
    public let groupName: String?
    public let adoptedAuthorityUsed: Bool?
    public let currentAdoptedAuthority: String?
    public let adoptedAuthoritySource: String?

    public var id: String {
        [
            subject.description,
            target.description,
            checkedAt.map { String($0.timeIntervalSince1970) } ?? "",
            requiredAuthority ?? "",
            authoritySource ?? "",
            adoptedAuthoritySource ?? ""
        ].joined(separator: "\u{1F}")
    }

    public init(
        subject: AuthoritySubject,
        target: IBMObjectIdentity,
        checkedAt: Date?,
        checkSucceeded: Bool?,
        requiredAuthority: String?,
        detailedRequiredAuthority: String?,
        currentAuthority: String?,
        detailedCurrentAuthority: String?,
        authoritySource: String?,
        groupName: String?,
        adoptedAuthorityUsed: Bool?,
        currentAdoptedAuthority: String?,
        adoptedAuthoritySource: String?
    ) {
        self.subject = subject
        self.target = target
        self.checkedAt = checkedAt
        self.checkSucceeded = checkSucceeded
        self.requiredAuthority = requiredAuthority
        self.detailedRequiredAuthority = detailedRequiredAuthority
        self.currentAuthority = currentAuthority
        self.detailedCurrentAuthority = detailedCurrentAuthority
        self.authoritySource = authoritySource
        self.groupName = groupName
        self.adoptedAuthorityUsed = adoptedAuthorityUsed
        self.currentAdoptedAuthority = currentAdoptedAuthority
        self.adoptedAuthoritySource = adoptedAuthoritySource
    }
}

public enum AuthorityPathKind: String, CaseIterable, Sendable {
    case direct
    case primaryGroup
    case supplementalGroup
    case publicAuthority
    case owner
    case authorizationList
    case allObject
    case observed

    public var label: String {
        switch self {
        case .direct: "DIRECT"
        case .primaryGroup: "PRIMARY GROUP"
        case .supplementalGroup: "GROUP"
        case .publicAuthority: "PUBLIC"
        case .owner: "OWNER"
        case .authorizationList: "AUTL"
        case .allObject: "*ALLOBJ"
        case .observed: "OBSERVED"
        }
    }

    public var isObserved: Bool { self == .observed }
}

public struct AuthorityPath: Equatable, Sendable, Identifiable {
    public let kind: AuthorityPathKind
    public let principal: String
    public let via: String
    public let authority: String
    public let surface: AuthoritySurface
    public let evidenceSource: AuthorityEvidenceSource
    public let grantsAccess: Bool
    public let note: String

    public var id: String {
        [kind.rawValue, principal, via, authority, evidenceSource.rawValue].joined(separator: "\u{1F}")
    }

    public init(
        kind: AuthorityPathKind,
        principal: String,
        via: String,
        authority: String,
        surface: AuthoritySurface,
        evidenceSource: AuthorityEvidenceSource,
        grantsAccess: Bool,
        note: String
    ) {
        self.kind = kind
        self.principal = principal
        self.via = via
        self.authority = authority
        self.surface = surface
        self.evidenceSource = evidenceSource
        self.grantsAccess = grantsAccess
        self.note = note
    }
}

public struct AuthorityAssessment: Equatable, Sendable {
    public let staticPathCount: Int
    public let reachableStaticPathCount: Int
    public let observedCount: Int
    public let dataChangePathCount: Int
    public let gapCount: Int
    public let hasAllObjectSignal: Bool
    public let hasAdoptedAuthorityObservation: Bool
    public let verdict: String
    public let method: String

    public init(paths: [AuthorityPath], receipts: [AuthorityEvidenceReceipt], observations: [AuthorityRuntimeObservation]) {
        let staticPaths = paths.filter { !$0.kind.isObserved }
        staticPathCount = staticPaths.count
        reachableStaticPathCount = staticPaths.filter(\.grantsAccess).count
        observedCount = observations.count
        dataChangePathCount = staticPaths.filter { $0.grantsAccess && $0.surface.carriesDataChange }.count
        gapCount = receipts.filter { !$0.outcome.isCollected }.count
        hasAllObjectSignal = staticPaths.contains { $0.kind == .allObject }
        hasAdoptedAuthorityObservation = observations.contains {
            $0.adoptedAuthorityUsed == true || $0.adoptedAuthoritySource != nil
        }
        verdict = "REVIEW REQUIRED"
        method = "Static DIRECT, GROUP, PUBLIC, OWNER, *ALLOBJ, and AUTL paths are explanatory evidence, not a complete effective-authority calculation. OBSERVED authority-collection rows describe only exercised checks and retain their source, adopted-authority, success, and required-authority fields. Caller authority can hide rows; function usage, unexercised code paths, cached checks, and other runtime context remain gaps. Missing rows never prove absence. No grant, revoke, profile, authorization-list, or collection state is changed."
    }
}

public struct AuthoritySimulationResult: Equatable, Sendable {
    public let removedPathIDs: Set<String>
    public let remainingPaths: [AuthorityPath]
    public let accessRemains: Bool
    public let hostWritesPerformed: Bool

    public init(removedPathIDs: Set<String>, remainingPaths: [AuthorityPath]) {
        self.removedPathIDs = removedPathIDs
        self.remainingPaths = remainingPaths
        accessRemains = remainingPaths.contains { $0.grantsAccess }
        hostWritesPerformed = false
    }
}

public struct AuthorityInsightSnapshot: Equatable, Sendable {
    public let targetName: String
    public let subject: AuthoritySubject
    public let target: IBMObjectIdentity
    public let capturedAt: Date
    public let profile: AuthorityProfileSnapshot?
    public let groups: [AuthorityGroupMembership]
    public let objectGrants: [AuthorityObjectGrant]
    public let authorizationListGrants: [AuthorityAuthorizationListGrant]
    public let observations: [AuthorityRuntimeObservation]
    public let receipts: [AuthorityEvidenceReceipt]
    public let isBundledReplay: Bool

    public init(
        targetName: String,
        subject: AuthoritySubject,
        target: IBMObjectIdentity,
        capturedAt: Date,
        profile: AuthorityProfileSnapshot?,
        groups: [AuthorityGroupMembership],
        objectGrants: [AuthorityObjectGrant],
        authorizationListGrants: [AuthorityAuthorizationListGrant],
        observations: [AuthorityRuntimeObservation],
        receipts: [AuthorityEvidenceReceipt],
        isBundledReplay: Bool = false
    ) {
        self.targetName = targetName
        self.subject = subject
        self.target = target
        self.capturedAt = capturedAt
        self.profile = profile
        var uniqueGroups: [String: AuthorityGroupMembership] = [:]
        for membership in groups { uniqueGroups[membership.id] = membership }
        self.groups = Array(uniqueGroups.values).sorted { $0.groupProfile < $1.groupProfile }
        var uniqueObjectGrants: [String: AuthorityObjectGrant] = [:]
        for grant in objectGrants { uniqueObjectGrants[grant.id] = grant }
        self.objectGrants = Array(uniqueObjectGrants.values).sorted {
            $0.authorizationName < $1.authorizationName
        }
        var uniqueAuthorizationListGrants: [String: AuthorityAuthorizationListGrant] = [:]
        for grant in authorizationListGrants { uniqueAuthorizationListGrants[grant.id] = grant }
        self.authorizationListGrants = Array(uniqueAuthorizationListGrants.values).sorted {
            $0.authorizationName < $1.authorizationName
        }
        var uniqueObservations: [String: AuthorityRuntimeObservation] = [:]
        for observation in observations { uniqueObservations[observation.id] = observation }
        self.observations = Array(uniqueObservations.values).sorted {
            ($0.checkedAt ?? .distantPast) > ($1.checkedAt ?? .distantPast)
        }
        self.receipts = receipts.sorted {
            let order = AuthorityEvidenceSource.allCases
            return (order.firstIndex(of: $0.source) ?? order.endIndex)
                < (order.firstIndex(of: $1.source) ?? order.endIndex)
        }
        self.isBundledReplay = isBundledReplay
    }

    public var authorizationList: String? {
        objectGrants.compactMap(\.authorizationList).first
    }

    public var paths: [AuthorityPath] { AuthorityPathAnalyzer().paths(in: self) }
    public var staticPaths: [AuthorityPath] { paths.filter { !$0.kind.isObserved } }
    public var observedPaths: [AuthorityPath] { paths.filter { $0.kind.isObserved } }
    public var gaps: [AuthorityEvidenceReceipt] { receipts.filter { !$0.outcome.isCollected } }
    public var assessment: AuthorityAssessment {
        AuthorityAssessment(paths: paths, receipts: receipts, observations: observations)
    }

    public func simulate(removing pathIDs: Set<String>) -> AuthoritySimulationResult {
        AuthoritySimulationResult(
            removedPathIDs: pathIDs,
            remainingPaths: staticPaths.filter { !pathIDs.contains($0.id) }
        )
    }
}

public struct AuthorityPathAnalyzer: Sendable {
    public init() {}

    public func paths(in snapshot: AuthorityInsightSnapshot) -> [AuthorityPath] {
        let subject = snapshot.subject.profile.value
        let primaryGroup = snapshot.profile?.primaryGroup
        var groups = Set(snapshot.groups.map(\.groupProfile))
        if let primaryGroup { groups.insert(primaryGroup) }
        var paths: [AuthorityPath] = []

        for grant in snapshot.objectGrants {
            let principal = grant.authorizationName
            let kind: AuthorityPathKind?
            if principal == subject {
                kind = grant.isObjectOwner || grant.owner == subject ? .owner : .direct
            } else if principal == primaryGroup {
                kind = .primaryGroup
            } else if groups.contains(principal) {
                kind = .supplementalGroup
            } else if principal == "*PUBLIC" {
                kind = .publicAuthority
            } else {
                kind = nil
            }
            guard let kind else { continue }
            paths.append(AuthorityPath(
                kind: kind,
                principal: principal,
                via: "exact object row",
                authority: grant.objectAuthority,
                surface: grant.surface,
                evidenceSource: .objectPrivileges,
                grantsAccess: Self.grantsAccess(authority: grant.objectAuthority, surface: grant.surface),
                note: "Static OBJECT_PRIVILEGES evidence; caller visibility can be partial."
            ))
        }

        if snapshot.profile?.specialAuthorities.contains("*ALLOBJ") == true {
            paths.append(AuthorityPath(
                kind: .allObject,
                principal: subject,
                via: "profile special authority",
                authority: "*ALLOBJ",
                surface: .all,
                evidenceSource: .userInfo,
                grantsAccess: true,
                note: "High-impact profile signal; runtime exceptions and function usage still require review."
            ))
        }

        if let authorizationList = snapshot.authorizationList {
            for grant in snapshot.authorizationListGrants where grant.authorizationList == authorizationList {
                let principal = grant.authorizationName
                guard principal == subject || groups.contains(principal) || principal == "*PUBLIC" else { continue }
                paths.append(AuthorityPath(
                    kind: .authorizationList,
                    principal: principal,
                    via: authorizationList,
                    authority: grant.objectAuthority,
                    surface: grant.surface,
                    evidenceSource: .authorizationListUserInfo,
                    grantsAccess: Self.grantsAccess(authority: grant.objectAuthority, surface: grant.surface),
                    note: "Static authorization-list entry; the view can return only caller-visible rows."
                ))
            }
        }

        for observation in snapshot.observations {
            paths.append(AuthorityPath(
                kind: .observed,
                principal: subject,
                via: observation.authoritySource ?? observation.adoptedAuthoritySource ?? "source unavailable",
                authority: observation.currentAuthority ?? observation.currentAdoptedAuthority ?? "USER DEFINED",
                surface: AuthoritySurface.inferred(
                    from: observation.currentAuthority ?? observation.currentAdoptedAuthority
                ),
                evidenceSource: .authorityCollection,
                grantsAccess: observation.checkSucceeded == true,
                note: "Observed authority check only; collection coverage is not inferred."
            ))
        }

        var unique: [String: AuthorityPath] = [:]
        for path in paths { unique[path.id] = path }
        let order = AuthorityPathKind.allCases
        return Array(unique.values).sorted {
            let left = order.firstIndex(of: $0.kind) ?? order.endIndex
            let right = order.firstIndex(of: $1.kind) ?? order.endIndex
            return left == right ? $0.id < $1.id : left < right
        }
    }

    private static func grantsAccess(authority: String, surface: AuthoritySurface) -> Bool {
        authority != "*EXCLUDE" && (surface.hasAnyAuthority || ["*ALL", "*CHANGE", "*USE", "*AUTL"].contains(authority))
    }
}

public struct AuthoritySQLPlanner: Sendable {
    public let subject: AuthoritySubject
    public let target: IBMObjectIdentity
    public let limits: AuthorityInsightLimits

    public init(
        subject: AuthoritySubject,
        target: IBMObjectIdentity,
        limits: AuthorityInsightLimits = .standard
    ) {
        self.subject = subject
        self.target = target
        self.limits = limits
    }

    public var userInfo: SQLExecutionRequest {
        request("""
        SELECT AUTHORIZATION_NAME,
               STATUS,
               USER_CLASS_NAME,
               SPECIAL_AUTHORITIES,
               GROUP_PROFILE_NAME,
               SUPPLEMENTAL_GROUP_COUNT,
               AUTHORITY_COLLECTION_ACTIVE,
               AUTHORITY_COLLECTION_REPOSITORY_EXISTS,
               LAST_USED_TIMESTAMP
          FROM QSYS2.USER_INFO
         WHERE AUTHORIZATION_NAME = '\(subject.profile.value)'
         FETCH FIRST 2 ROWS ONLY
        """, maximumRows: 2)
    }

    public var groupProfileEntries: SQLExecutionRequest {
        request("""
        SELECT GROUP_PROFILE_NAME,
               USER_PROFILE_NAME,
               USER_TEXT
          FROM QSYS2.GROUP_PROFILE_ENTRIES
         WHERE USER_PROFILE_NAME = '\(subject.profile.value)'
         ORDER BY GROUP_PROFILE_NAME
         FETCH FIRST \(limits.maximumGroupRows + 1) ROWS ONLY
        """, maximumRows: limits.maximumGroupRows + 1)
    }

    public var objectPrivileges: SQLExecutionRequest {
        request("""
        SELECT SYSTEM_OBJECT_SCHEMA,
               SYSTEM_OBJECT_NAME,
               OBJECT_TYPE,
               AUTHORIZATION_NAME,
               OBJECT_AUTHORITY,
               OWNER,
               AUTHORIZATION_LIST,
               PRIMARY_GROUP,
               AUTHORIZATION_LIST_MANAGEMENT,
               OBJECT_OWNER,
               OBJECT_OPERATIONAL,
               OBJECT_MANAGEMENT,
               OBJECT_EXISTENCE,
               OBJECT_ALTER,
               OBJECT_REFERENCE,
               DATA_READ,
               DATA_ADD,
               DATA_UPDATE,
               DATA_DELETE,
               DATA_EXECUTE
          FROM QSYS2.OBJECT_PRIVILEGES
         WHERE SYSTEM_OBJECT_SCHEMA = '\(target.library.value)'
           AND SYSTEM_OBJECT_NAME = '\(target.name.value)'
           AND OBJECT_TYPE = '\(target.type.rawValue)'
         ORDER BY AUTHORIZATION_NAME
         FETCH FIRST \(limits.maximumPrivilegeRows + 1) ROWS ONLY
        """, maximumRows: limits.maximumPrivilegeRows + 1)
    }

    public func authorizationListUserInfo(_ authorizationList: IBMSystemObjectName) -> SQLExecutionRequest {
        request("""
        SELECT AUTHORIZATION_LIST,
               AUTHORIZATION_NAME,
               OBJECT_AUTHORITY,
               AUTHORIZATION_LIST_MANAGEMENT,
               OWNER,
               OBJECT_OPERATIONAL,
               OBJECT_MANAGEMENT,
               OBJECT_EXISTENCE,
               OBJECT_ALTER,
               OBJECT_REFERENCE,
               DATA_READ,
               DATA_ADD,
               DATA_UPDATE,
               DATA_DELETE,
               DATA_EXECUTE
          FROM QSYS2.AUTHORIZATION_LIST_USER_INFO
         WHERE AUTHORIZATION_LIST = '\(authorizationList.value)'
         ORDER BY AUTHORIZATION_NAME
         FETCH FIRST \(limits.maximumAuthorizationListRows + 1) ROWS ONLY
        """, maximumRows: limits.maximumAuthorizationListRows + 1)
    }

    public var authorityCollection: SQLExecutionRequest {
        request("""
        SELECT AUTHORIZATION_NAME,
               CHECK_TIMESTAMP,
               SYSTEM_OBJECT_SCHEMA,
               SYSTEM_OBJECT_NAME,
               SYSTEM_OBJECT_TYPE,
               AUTHORIZATION_LIST,
               AUTHORITY_CHECK_SUCCESSFUL,
               REQUIRED_AUTHORITY,
               DETAILED_REQUIRED_AUTHORITY,
               CURRENT_AUTHORITY,
               DETAILED_CURRENT_AUTHORITY,
               AUTHORITY_SOURCE,
               GROUP_NAME,
               ADOPT_AUTHORITY_USED,
               CURRENT_ADOPTED_AUTHORITY,
               ADOPTED_AUTHORITY_SOURCE
          FROM QSYS2.AUTHORITY_COLLECTION
         WHERE AUTHORIZATION_NAME = '\(subject.profile.value)'
           AND SYSTEM_OBJECT_SCHEMA = '\(target.library.value)'
           AND SYSTEM_OBJECT_NAME = '\(target.name.value)'
           AND SYSTEM_OBJECT_TYPE = '\(target.type.rawValue)'
         ORDER BY CHECK_TIMESTAMP DESC
         FETCH FIRST \(limits.maximumRuntimeRows + 1) ROWS ONLY
        """, maximumRows: limits.maximumRuntimeRows + 1)
    }

    public var initialRequests: [(AuthorityEvidenceSource, SQLExecutionRequest)] {
        [
            (.userInfo, userInfo),
            (.groupProfileEntries, groupProfileEntries),
            (.objectPrivileges, objectPrivileges),
            (.authorityCollection, authorityCollection)
        ]
    }

    private func request(_ sql: String, maximumRows: Int) -> SQLExecutionRequest {
        SQLExecutionRequest(
            sql: sql,
            maximumRows: maximumRows,
            timeoutSeconds: limits.queryTimeoutSeconds,
            readOnly: true
        )
    }
}

public struct AuthoritySQLDecoder: Sendable {
    public let limits: AuthorityInsightLimits

    public init(limits: AuthorityInsightLimits = .standard) {
        self.limits = limits
    }

    public func decodeProfile(_ result: SQLResult, subject: AuthoritySubject) throws -> AuthorityProfileSnapshot? {
        let source = AuthorityEvidenceSource.userInfo.rawValue
        let required = [
            "AUTHORIZATION_NAME", "STATUS", "USER_CLASS_NAME", "SPECIAL_AUTHORITIES",
            "GROUP_PROFILE_NAME", "SUPPLEMENTAL_GROUP_COUNT", "AUTHORITY_COLLECTION_ACTIVE",
            "AUTHORITY_COLLECTION_REPOSITORY_EXISTS", "LAST_USED_TIMESTAMP"
        ]
        try validate(result, source: source, required: required, maximumRows: 1)
        guard let first = result.rows.indices.first else { return nil }
        let row = try AuthoritySQLRow(result: result, source: source, rowIndex: first + 1)
        guard try row.requiredText("AUTHORIZATION_NAME", maximumBytes: 10).uppercased() == subject.profile.value else {
            throw AuthorityInsightError.identityMismatch(source: source)
        }
        let supplementalCount = try row.requiredInt("SUPPLEMENTAL_GROUP_COUNT")
        guard (0...15).contains(supplementalCount) else {
            throw AuthorityInsightError.invalidValue(source: source, index: 1, column: "SUPPLEMENTAL_GROUP_COUNT")
        }
        let primary = try row.optionalText("GROUP_PROFILE_NAME", maximumBytes: 10)?.uppercased()
        return AuthorityProfileSnapshot(
            subject: subject,
            status: try row.requiredText("STATUS", maximumBytes: 10).uppercased(),
            userClass: try row.requiredText("USER_CLASS_NAME", maximumBytes: 10).uppercased(),
            specialAuthorities: try row.optionalText("SPECIAL_AUTHORITIES", maximumBytes: 88)?
                .split(whereSeparator: \.isWhitespace).map { String($0).uppercased() } ?? [],
            primaryGroup: primary == "*NONE" ? nil : primary,
            supplementalGroupCount: supplementalCount,
            authorityCollectionActive: try row.requiredYesNo("AUTHORITY_COLLECTION_ACTIVE"),
            authorityCollectionRepositoryExists: try row.requiredYesNo("AUTHORITY_COLLECTION_REPOSITORY_EXISTS"),
            lastUsedAt: try row.optionalDate("LAST_USED_TIMESTAMP")
        )
    }

    public func decodeGroups(_ result: SQLResult, subject: AuthoritySubject) throws -> [AuthorityGroupMembership] {
        let source = AuthorityEvidenceSource.groupProfileEntries.rawValue
        try validate(
            result,
            source: source,
            required: ["GROUP_PROFILE_NAME", "USER_PROFILE_NAME", "USER_TEXT"],
            maximumRows: limits.maximumGroupRows
        )
        return try result.rows.indices.map { index in
            let row = try AuthoritySQLRow(result: result, source: source, rowIndex: index + 1)
            let user = try row.requiredText("USER_PROFILE_NAME", maximumBytes: 128).uppercased()
            guard user == subject.profile.value else { throw AuthorityInsightError.identityMismatch(source: source) }
            let group = try row.requiredText("GROUP_PROFILE_NAME", maximumBytes: 128).uppercased()
            _ = try IBMSystemObjectName(group)
            return AuthorityGroupMembership(
                groupProfile: group,
                userProfile: user,
                userText: try row.optionalText("USER_TEXT", maximumBytes: 50)
            )
        }
    }

    public func decodeObjectGrants(_ result: SQLResult, target: IBMObjectIdentity) throws -> [AuthorityObjectGrant] {
        let source = AuthorityEvidenceSource.objectPrivileges.rawValue
        let common = [
            "SYSTEM_OBJECT_SCHEMA", "SYSTEM_OBJECT_NAME", "OBJECT_TYPE", "AUTHORIZATION_NAME",
            "OBJECT_AUTHORITY", "OWNER", "AUTHORIZATION_LIST", "PRIMARY_GROUP", "OBJECT_OWNER"
        ]
        try validate(
            result,
            source: source,
            required: common + Self.surfaceColumns,
            maximumRows: limits.maximumPrivilegeRows
        )
        return try result.rows.indices.map { index in
            let row = try AuthoritySQLRow(result: result, source: source, rowIndex: index + 1)
            try verifyTarget(row, target: target, source: source)
            let principal = try validatedPrincipal(row.requiredText("AUTHORIZATION_NAME", maximumBytes: 10), row: index + 1, source: source)
            let authority = try validatedAuthority(row.requiredText("OBJECT_AUTHORITY", maximumBytes: 12), row: index + 1, source: source, allowsAUTL: true)
            return AuthorityObjectGrant(
                target: target,
                authorizationName: principal,
                objectAuthority: authority,
                owner: try validatedProfile(row.requiredText("OWNER", maximumBytes: 10), row: index + 1, column: "OWNER", source: source),
                authorizationList: try optionalProfile(row, column: "AUTHORIZATION_LIST", rowIndex: index + 1, source: source),
                primaryGroup: try optionalProfile(row, column: "PRIMARY_GROUP", rowIndex: index + 1, source: source),
                isObjectOwner: try row.requiredYesNo("OBJECT_OWNER"),
                surface: try decodeSurface(row)
            )
        }
    }

    public func decodeAuthorizationListGrants(
        _ result: SQLResult,
        authorizationList: IBMSystemObjectName
    ) throws -> [AuthorityAuthorizationListGrant] {
        let source = AuthorityEvidenceSource.authorizationListUserInfo.rawValue
        let common = ["AUTHORIZATION_LIST", "AUTHORIZATION_NAME", "OBJECT_AUTHORITY", "OWNER"]
        try validate(
            result,
            source: source,
            required: common + Self.surfaceColumns.filter { $0 != "OBJECT_OWNER" },
            maximumRows: limits.maximumAuthorizationListRows
        )
        return try result.rows.indices.map { index in
            let row = try AuthoritySQLRow(result: result, source: source, rowIndex: index + 1)
            let returnedList = try row.requiredText("AUTHORIZATION_LIST", maximumBytes: 10).uppercased()
            guard returnedList == authorizationList.value else {
                throw AuthorityInsightError.identityMismatch(source: source)
            }
            return AuthorityAuthorizationListGrant(
                authorizationList: returnedList,
                authorizationName: try validatedPrincipal(row.requiredText("AUTHORIZATION_NAME", maximumBytes: 10), row: index + 1, source: source),
                objectAuthority: try validatedAuthority(row.requiredText("OBJECT_AUTHORITY", maximumBytes: 12), row: index + 1, source: source, allowsAUTL: false),
                owner: try validatedProfile(row.requiredText("OWNER", maximumBytes: 10), row: index + 1, column: "OWNER", source: source),
                surface: try decodeSurface(row)
            )
        }
    }

    public func decodeRuntimeObservations(
        _ result: SQLResult,
        subject: AuthoritySubject,
        target: IBMObjectIdentity
    ) throws -> [AuthorityRuntimeObservation] {
        let source = AuthorityEvidenceSource.authorityCollection.rawValue
        let required = [
            "AUTHORIZATION_NAME", "CHECK_TIMESTAMP", "SYSTEM_OBJECT_SCHEMA", "SYSTEM_OBJECT_NAME",
            "SYSTEM_OBJECT_TYPE", "AUTHORIZATION_LIST", "AUTHORITY_CHECK_SUCCESSFUL", "REQUIRED_AUTHORITY",
            "DETAILED_REQUIRED_AUTHORITY", "CURRENT_AUTHORITY", "DETAILED_CURRENT_AUTHORITY",
            "AUTHORITY_SOURCE", "GROUP_NAME", "ADOPT_AUTHORITY_USED", "CURRENT_ADOPTED_AUTHORITY",
            "ADOPTED_AUTHORITY_SOURCE"
        ]
        try validate(result, source: source, required: required, maximumRows: limits.maximumRuntimeRows)
        return try result.rows.indices.map { index in
            let row = try AuthoritySQLRow(result: result, source: source, rowIndex: index + 1)
            guard try row.requiredText("AUTHORIZATION_NAME", maximumBytes: 10).uppercased() == subject.profile.value else {
                throw AuthorityInsightError.identityMismatch(source: source)
            }
            try verifyTarget(row, target: target, source: source)
            return AuthorityRuntimeObservation(
                subject: subject,
                target: target,
                checkedAt: try row.optionalDate("CHECK_TIMESTAMP"),
                checkSucceeded: try row.optionalZeroOne("AUTHORITY_CHECK_SUCCESSFUL"),
                requiredAuthority: try row.optionalText("REQUIRED_AUTHORITY", maximumBytes: 12),
                detailedRequiredAuthority: try row.optionalText("DETAILED_REQUIRED_AUTHORITY", maximumBytes: 90),
                currentAuthority: try row.optionalText("CURRENT_AUTHORITY", maximumBytes: 12),
                detailedCurrentAuthority: try row.optionalText("DETAILED_CURRENT_AUTHORITY", maximumBytes: 99),
                authoritySource: try row.optionalText("AUTHORITY_SOURCE", maximumBytes: 50),
                groupName: try optionalProfile(row, column: "GROUP_NAME", rowIndex: index + 1, source: source),
                adoptedAuthorityUsed: try row.optionalZeroOne("ADOPT_AUTHORITY_USED"),
                currentAdoptedAuthority: try row.optionalText("CURRENT_ADOPTED_AUTHORITY", maximumBytes: 12),
                adoptedAuthoritySource: try row.optionalText("ADOPTED_AUTHORITY_SOURCE", maximumBytes: 50)
            )
        }
    }

    private static let surfaceColumns = [
        "AUTHORIZATION_LIST_MANAGEMENT", "OBJECT_OPERATIONAL", "OBJECT_MANAGEMENT", "OBJECT_EXISTENCE",
        "OBJECT_ALTER", "OBJECT_REFERENCE", "DATA_READ", "DATA_ADD", "DATA_UPDATE", "DATA_DELETE",
        "DATA_EXECUTE"
    ]

    private func decodeSurface(_ row: AuthoritySQLRow) throws -> AuthoritySurface {
        AuthoritySurface(
            authorizationListManagement: try row.requiredYesNo("AUTHORIZATION_LIST_MANAGEMENT"),
            objectOperational: try row.requiredYesNo("OBJECT_OPERATIONAL"),
            objectManagement: try row.requiredYesNo("OBJECT_MANAGEMENT"),
            objectExistence: try row.requiredYesNo("OBJECT_EXISTENCE"),
            objectAlter: try row.requiredYesNo("OBJECT_ALTER"),
            objectReference: try row.requiredYesNo("OBJECT_REFERENCE"),
            dataRead: try row.requiredYesNo("DATA_READ"),
            dataAdd: try row.requiredYesNo("DATA_ADD"),
            dataUpdate: try row.requiredYesNo("DATA_UPDATE"),
            dataDelete: try row.requiredYesNo("DATA_DELETE"),
            dataExecute: try row.requiredYesNo("DATA_EXECUTE")
        )
    }

    private func validate(
        _ result: SQLResult,
        source: String,
        required: [String],
        maximumRows: Int
    ) throws {
        var seen = Set<String>()
        for column in result.columns {
            let name = column.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard seen.insert(name).inserted else {
                throw AuthorityInsightError.duplicateColumn(source: source, column: name)
            }
        }
        for column in required where !seen.contains(column) {
            throw AuthorityInsightError.missingColumn(source: source, column: column)
        }
        guard !result.wasTruncated else { throw AuthorityInsightError.truncatedResult(source: source) }
        guard result.rows.count <= maximumRows else {
            throw AuthorityInsightError.tooManyRows(source: source, maximum: maximumRows)
        }
        for (index, row) in result.rows.enumerated() where row.count != result.columns.count {
            throw AuthorityInsightError.malformedRow(source: source, index: index + 1)
        }
    }

    private func verifyTarget(_ row: AuthoritySQLRow, target: IBMObjectIdentity, source: String) throws {
        let typeColumn = row.hasColumn("OBJECT_TYPE") ? "OBJECT_TYPE" : "SYSTEM_OBJECT_TYPE"
        guard try row.requiredText("SYSTEM_OBJECT_SCHEMA", maximumBytes: 10).uppercased() == target.library.value,
              try row.requiredText("SYSTEM_OBJECT_NAME", maximumBytes: 10).uppercased() == target.name.value,
              try row.requiredText(typeColumn, maximumBytes: 8).uppercased() == target.type.rawValue else {
            throw AuthorityInsightError.identityMismatch(source: source)
        }
    }

    private func validatedPrincipal(_ value: String, row: Int, source: String) throws -> String {
        let normalized = value.uppercased()
        if normalized == "*PUBLIC" { return normalized }
        return try validatedProfile(normalized, row: row, column: "AUTHORIZATION_NAME", source: source)
    }

    private func validatedProfile(
        _ value: String,
        row: Int,
        column: String,
        source: String
    ) throws -> String {
        do { return try IBMSystemObjectName(value.uppercased()).value }
        catch { throw AuthorityInsightError.invalidValue(source: source, index: row, column: column) }
    }

    private func optionalProfile(
        _ row: AuthoritySQLRow,
        column: String,
        rowIndex: Int,
        source: String
    ) throws -> String? {
        guard let value = try row.optionalText(column, maximumBytes: 10)?.uppercased(), value != "*NONE" else {
            return nil
        }
        return try validatedProfile(value, row: rowIndex, column: column, source: source)
    }

    private func validatedAuthority(
        _ value: String,
        row: Int,
        source: String,
        allowsAUTL: Bool
    ) throws -> String {
        let normalized = value.uppercased()
        var allowed: Set<String> = ["*ALL", "*CHANGE", "*EXCLUDE", "*USE", "USER DEFINED"]
        if allowsAUTL { allowed.insert("*AUTL") }
        guard allowed.contains(normalized) else {
            throw AuthorityInsightError.invalidValue(source: source, index: row, column: "OBJECT_AUTHORITY")
        }
        return normalized
    }
}

public struct AuthorityArtifactBuilder: Sendable {
    public init() {}

    public func build(snapshot: AuthorityInsightSnapshot) -> String {
        let assessment = snapshot.assessment
        var lines = [
            "iTelAS AUTHORITY PATH ATLAS ARTIFACT",
            "Verdict: \(assessment.verdict)",
            "Target system: \(snapshot.targetName)",
            "Subject profile: \(snapshot.subject.description)",
            "Object: \(snapshot.target.description)",
            "Captured: \(snapshot.capturedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)))",
            "Bundled replay: \(snapshot.isBundledReplay ? "YES" : "NO")",
            "Host writes: NONE",
            "",
            "PROFILE"
        ]
        if let profile = snapshot.profile {
            lines += [
                "Status: \(profile.status)",
                "User class: \(profile.userClass)",
                "Special authorities: \(profile.specialAuthorities.isEmpty ? "NONE REPORTED" : profile.specialAuthorities.joined(separator: ", "))",
                "Primary group: \(profile.primaryGroup ?? "NONE REPORTED")",
                "Authority collection active: \(profile.authorityCollectionActive ? "YES" : "NO")",
                "Authority collection repository: \(profile.authorityCollectionRepositoryExists ? "YES" : "NO")"
            ]
        } else {
            lines.append("UNAVAILABLE")
        }
        lines += ["", "GROUP MEMBERSHIP"]
        lines += snapshot.groups.isEmpty
            ? ["NONE RETURNED"]
            : snapshot.groups.map { "\($0.groupProfile) <- \($0.userProfile)" }
        lines += ["", "EXPLAINED PATHS"]
        lines += snapshot.paths.isEmpty ? ["NONE RETURNED"] : snapshot.paths.map { path in
            "\(path.kind.label): \(path.principal) -> \(path.via) -> \(snapshot.target.description) · \(path.authority) · \(path.grantsAccess ? "REPORTED ACCESS" : "BLOCKED OR UNPROVEN") · \(surfaceText(path.surface))"
        }
        lines += ["", "RUNTIME OBSERVATIONS"]
        lines += snapshot.observations.isEmpty ? ["NONE RETURNED"] : snapshot.observations.map { observation in
            [
                observation.checkedAt.map { $0.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)) } ?? "TIME UNAVAILABLE",
                observation.checkSucceeded.map { $0 ? "SUCCEEDED" : "FAILED" } ?? "RESULT UNAVAILABLE",
                "required=\(observation.requiredAuthority ?? observation.detailedRequiredAuthority ?? "UNAVAILABLE")",
                "current=\(observation.currentAuthority ?? observation.detailedCurrentAuthority ?? "UNAVAILABLE")",
                "source=\(observation.authoritySource ?? "UNAVAILABLE")",
                "adopted=\(observation.adoptedAuthorityUsed.map { $0 ? "YES" : "NO" } ?? "UNAVAILABLE")",
                "adopted-source=\(observation.adoptedAuthoritySource ?? "UNAVAILABLE")"
            ].joined(separator: " · ")
        }
        lines += ["", "EVIDENCE RECEIPTS"]
        for receipt in snapshot.receipts {
            let outcome: String
            switch receipt.outcome {
            case .collected:
                outcome = "COLLECTED"
            case .unavailable(let reason):
                outcome = "UNAVAILABLE · \(reason)"
            }
            lines.append(
                "\(receipt.source.rawValue): \(outcome) · rows=\(receipt.rowCount) · bound=\(receipt.boundWasReached ? "REACHED" : "NOT REACHED") · query-sha256=\(receipt.queryFingerprint)"
            )
        }
        lines += [
            "",
            "METHOD AND LIMITATIONS",
            assessment.method,
            "Authority collection is runtime evidence only; the application must exercise every relevant path before least-privilege conclusions are considered.",
            "A local what-if removes selected evidence paths from this artifact only. It never grants, revokes, changes profiles, changes authorization lists, or starts, ends, or deletes authority collection.",
            "No host writes were performed."
        ]
        return lines.joined(separator: "\n")
    }

    private func surfaceText(_ surface: AuthoritySurface) -> String {
        var labels: [String] = []
        if surface.objectOperational { labels.append("OBJOPR") }
        if surface.objectManagement { labels.append("OBJMGT") }
        if surface.objectExistence { labels.append("OBJEXIST") }
        if surface.objectAlter { labels.append("OBJALTER") }
        if surface.objectReference { labels.append("OBJREF") }
        if surface.dataRead { labels.append("READ") }
        if surface.dataAdd { labels.append("ADD") }
        if surface.dataUpdate { labels.append("UPDATE") }
        if surface.dataDelete { labels.append("DELETE") }
        if surface.dataExecute { labels.append("EXECUTE") }
        if surface.authorizationListManagement { labels.append("AUTLMGT") }
        return labels.isEmpty ? "NO DETAILED AUTHORITY REPORTED" : labels.joined(separator: ",")
    }
}

public struct AuthorityAssistContextBuilder: Sendable {
    public init() {}

    public func build(snapshot: AuthorityInsightSnapshot) -> String {
        let groupAliases = Dictionary(uniqueKeysWithValues: snapshot.groups.enumerated().map {
            ($0.element.groupProfile, String(format: "GROUP-%03d", $0.offset + 1))
        })
        func alias(_ principal: String) -> String {
            if principal == snapshot.subject.description { return "SUBJECT-001" }
            if principal == "*PUBLIC" { return "*PUBLIC" }
            return groupAliases[principal] ?? "PRINCIPAL-WITHHELD"
        }
        var lines = [
            "iTelAS AUTHORITY REVIEW CONTEXT",
            "Verdict: REVIEW REQUIRED",
            "Subject: SUBJECT-001",
            "Object: OBJECT-001 \(snapshot.target.type.rawValue)",
            "Identity handling: target system, profile, library, object, owner, authorization-list, group, timestamps, diagnostics, descriptions, and fingerprints are withheld or aliased.",
            "",
            "PATHS"
        ]
        lines += snapshot.paths.map { path in
            let via = path.kind == .authorizationList ? "AUTL-WITHHELD" : path.via
            return "\(path.kind.label): \(alias(path.principal)) -> \(via) -> OBJECT-001 · \(path.authority) · \(path.grantsAccess ? "REPORTED ACCESS" : "BLOCKED OR UNPROVEN")"
        }
        lines += ["", "EVIDENCE COVERAGE"]
        lines += snapshot.receipts.map { receipt in
            "\(receipt.source.rawValue): \(receipt.outcome.isCollected ? "COLLECTED" : "UNAVAILABLE — DETAILS WITHHELD")"
        }
        lines += [
            "",
            "RUNTIME SUMMARY",
            "Observed checks: \(snapshot.observations.count)",
            "Adopted-authority signal present: \(snapshot.assessment.hasAdoptedAuthorityObservation ? "YES" : "NO")",
            "Collection coverage: UNKNOWN",
            "",
            "REQUIRED INTERPRETATION",
            snapshot.assessment.method,
            "Recommend read-only verification only. Do not claim effective authority, least privilege, or safe remediation from this context."
        ]
        return lines.joined(separator: "\n")
    }
}

private struct AuthoritySQLRow {
    let source: String
    let rowIndex: Int
    private let values: [String: SQLValue]

    init(result: SQLResult, source: String, rowIndex: Int) throws {
        guard result.rows.indices.contains(rowIndex - 1),
              result.rows[rowIndex - 1].count == result.columns.count else {
            throw AuthorityInsightError.malformedRow(source: source, index: rowIndex)
        }
        self.source = source
        self.rowIndex = rowIndex
        var values: [String: SQLValue] = [:]
        for (column, value) in zip(result.columns, result.rows[rowIndex - 1]) {
            let name = column.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard values[name] == nil else {
                throw AuthorityInsightError.duplicateColumn(source: source, column: name)
            }
            values[name] = value
        }
        self.values = values
    }

    func hasColumn(_ column: String) -> Bool { values[column] != nil }

    func requiredText(_ column: String, maximumBytes: Int) throws -> String {
        guard let value = try optionalText(column, maximumBytes: maximumBytes), !value.isEmpty else {
            throw AuthorityInsightError.invalidValue(source: source, index: rowIndex, column: column)
        }
        return value
    }

    func optionalText(_ column: String, maximumBytes: Int) throws -> String? {
        guard let raw = values[column] else {
            throw AuthorityInsightError.missingColumn(source: source, column: column)
        }
        let value: String?
        switch raw {
        case .null:
            value = nil
        case .string(let text), .decimal(let text):
            value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .integer(let number):
            value = String(number)
        case .boolean(let flag):
            value = flag ? "YES" : "NO"
        default:
            throw AuthorityInsightError.invalidValue(source: source, index: rowIndex, column: column)
        }
        guard let value else { return nil }
        guard value.utf8.count <= maximumBytes,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw AuthorityInsightError.invalidText(source: source, index: rowIndex, column: column)
        }
        return value
    }

    func requiredInt(_ column: String) throws -> Int {
        guard let raw = values[column] else {
            throw AuthorityInsightError.missingColumn(source: source, column: column)
        }
        let value: Int?
        switch raw {
        case .integer(let number): value = Int(exactly: number)
        case .decimal(let text), .string(let text): value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: value = nil
        }
        guard let value else {
            throw AuthorityInsightError.invalidValue(source: source, index: rowIndex, column: column)
        }
        return value
    }

    func requiredYesNo(_ column: String) throws -> Bool {
        guard let value = try optionalYesNo(column) else {
            throw AuthorityInsightError.invalidValue(source: source, index: rowIndex, column: column)
        }
        return value
    }

    func optionalYesNo(_ column: String) throws -> Bool? {
        guard let raw = try optionalText(column, maximumBytes: 3)?.uppercased() else { return nil }
        switch raw {
        case "YES": return true
        case "NO": return false
        default: throw AuthorityInsightError.invalidValue(source: source, index: rowIndex, column: column)
        }
    }

    func optionalZeroOne(_ column: String) throws -> Bool? {
        guard let raw = try optionalText(column, maximumBytes: 3)?.uppercased() else { return nil }
        switch raw {
        case "1", "YES", "Y": return true
        case "0", "NO", "N": return false
        default: throw AuthorityInsightError.invalidValue(source: source, index: rowIndex, column: column)
        }
    }

    func optionalDate(_ column: String) throws -> Date? {
        guard let raw = values[column] else {
            throw AuthorityInsightError.missingColumn(source: source, column: column)
        }
        switch raw {
        case .null: return nil
        case .date(let date), .timestamp(let date): return date
        default: throw AuthorityInsightError.invalidValue(source: source, index: rowIndex, column: column)
        }
    }
}
