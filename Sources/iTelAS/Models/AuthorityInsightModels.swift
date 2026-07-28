import Foundation
import iTelASCore

enum AuthorityInsightPhase: Equatable {
    case localReplay
    case collecting
    case ready
    case failed

    var label: String {
        switch self {
        case .localReplay: "LOCAL REPLAY"
        case .collecting: "COLLECTING"
        case .ready: "LIVE EVIDENCE"
        case .failed: "EVIDENCE GAP"
        }
    }

    var isCollecting: Bool { self == .collecting }
}

enum AuthorityInsightSamples {
    static func makeSnapshot() -> AuthorityInsightSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_785_166_212)
        let subject = try! AuthoritySubject("RPGDEV1")
        let target = try! IBMObjectIdentity(library: "ARLIB", name: "PAYROLL", type: .file)
        let planner = AuthoritySQLPlanner(subject: subject, target: target)
        let use = AuthoritySurface(objectOperational: true, dataRead: true, dataExecute: true)
        let change = AuthoritySurface(
            objectOperational: true,
            dataRead: true,
            dataAdd: true,
            dataUpdate: true,
            dataDelete: true,
            dataExecute: true
        )
        let groups = [
            AuthorityGroupMembership(groupProfile: "APPDEV", userProfile: subject.description, userText: "Application developers"),
            AuthorityGroupMembership(groupProfile: "PAYROLLR", userProfile: subject.description, userText: "Payroll readers"),
            AuthorityGroupMembership(groupProfile: "OPSVIEW", userProfile: subject.description, userText: "Operations observers")
        ]
        let objectGrants = [
            grant(target, principal: subject.description, authority: "*USE", surface: use),
            grant(target, principal: "APPDEV", authority: "*CHANGE", surface: change),
            grant(target, principal: "OPSVIEW", authority: "*USE", surface: use),
            grant(target, principal: "*PUBLIC", authority: "*EXCLUDE", surface: .none),
            grant(target, principal: "APPAUDIT", authority: "*USE", surface: use)
        ]
        let authorizationListGrants = [
            AuthorityAuthorizationListGrant(
                authorizationList: "PAYROLLAUT",
                authorizationName: "PAYROLLR",
                objectAuthority: "*USE",
                owner: "SECADMIN",
                surface: use
            ),
            AuthorityAuthorizationListGrant(
                authorizationList: "PAYROLLAUT",
                authorizationName: "*PUBLIC",
                objectAuthority: "*EXCLUDE",
                owner: "SECADMIN",
                surface: .none
            )
        ]
        let observations = [
            AuthorityRuntimeObservation(
                subject: subject,
                target: target,
                checkedAt: capturedAt.addingTimeInterval(-940),
                checkSucceeded: true,
                requiredAuthority: "*USE",
                detailedRequiredAuthority: "*OBJOPR *READ",
                currentAuthority: "*CHANGE",
                detailedCurrentAuthority: "*OBJOPR *READ *ADD *UPD *DLT *EXECUTE",
                authoritySource: "GROUP PRIVATE",
                groupName: "APPDEV",
                adoptedAuthorityUsed: false,
                currentAdoptedAuthority: nil,
                adoptedAuthoritySource: nil
            ),
            AuthorityRuntimeObservation(
                subject: subject,
                target: target,
                checkedAt: capturedAt.addingTimeInterval(-1_840),
                checkSucceeded: true,
                requiredAuthority: "*USE",
                detailedRequiredAuthority: "*OBJOPR *READ",
                currentAuthority: "*USE",
                detailedCurrentAuthority: "*OBJOPR *READ *EXECUTE",
                authoritySource: "USER PRIVATE",
                groupName: nil,
                adoptedAuthorityUsed: false,
                currentAdoptedAuthority: nil,
                adoptedAuthoritySource: nil
            ),
            AuthorityRuntimeObservation(
                subject: subject,
                target: target,
                checkedAt: capturedAt.addingTimeInterval(-3_420),
                checkSucceeded: true,
                requiredAuthority: "*USE",
                detailedRequiredAuthority: "*OBJOPR *READ",
                currentAuthority: "*USE",
                detailedCurrentAuthority: "*OBJOPR *READ *EXECUTE",
                authoritySource: "AUTHORIZATION LIST PRIVATE",
                groupName: "PAYROLLR",
                adoptedAuthorityUsed: false,
                currentAdoptedAuthority: nil,
                adoptedAuthoritySource: nil
            )
        ]
        let requests: [AuthorityEvidenceSource: SQLExecutionRequest] = [
            .userInfo: planner.userInfo,
            .groupProfileEntries: planner.groupProfileEntries,
            .objectPrivileges: planner.objectPrivileges,
            .authorizationListUserInfo: planner.authorizationListUserInfo(try! IBMSystemObjectName("PAYROLLAUT")),
            .authorityCollection: planner.authorityCollection
        ]
        let counts: [AuthorityEvidenceSource: Int] = [
            .userInfo: 1,
            .groupProfileEntries: 3,
            .objectPrivileges: 5,
            .authorizationListUserInfo: 2,
            .authorityCollection: 3
        ]
        var receipts = AuthorityEvidenceSource.liveSQLSources.map { source in
            AuthorityEvidenceReceipt(
                source: source,
                rowCount: counts[source] ?? 0,
                boundWasReached: false,
                elapsedMilliseconds: source == .authorityCollection ? 46 : 18,
                queryFingerprint: AIContentFingerprint.sha256(requests[source]?.sql ?? source.rawValue),
                outcome: .collected
            )
        }
        receipts.append(AuthorityEvidenceReceipt(
            source: .effectiveAuthorityResolution,
            rowCount: 0,
            boundWasReached: false,
            elapsedMilliseconds: nil,
            queryFingerprint: AIContentFingerprint.sha256("NO SINGLE EFFECTIVE AUTHORITY PROOF"),
            outcome: .unavailable("No single read-only service proves every function-usage, adopted-authority, cached-check, and unexercised runtime path.")
        ))
        return AuthorityInsightSnapshot(
            targetName: "DEV ORION",
            subject: subject,
            target: target,
            capturedAt: capturedAt,
            profile: AuthorityProfileSnapshot(
                subject: subject,
                status: "*ENABLED",
                userClass: "*PGMR",
                specialAuthorities: ["*JOBCTL"],
                primaryGroup: "APPDEV",
                supplementalGroupCount: 2,
                authorityCollectionActive: true,
                authorityCollectionRepositoryExists: true,
                lastUsedAt: capturedAt.addingTimeInterval(-86_400 * 4)
            ),
            groups: groups,
            objectGrants: objectGrants,
            authorizationListGrants: authorizationListGrants,
            observations: observations,
            receipts: receipts,
            isBundledReplay: true
        )
    }

    private static func grant(
        _ target: IBMObjectIdentity,
        principal: String,
        authority: String,
        surface: AuthoritySurface
    ) -> AuthorityObjectGrant {
        AuthorityObjectGrant(
            target: target,
            authorizationName: principal,
            objectAuthority: authority,
            owner: "APPOWNER",
            authorizationList: "PAYROLLAUT",
            primaryGroup: "APPDEV",
            isObjectOwner: false,
            surface: surface
        )
    }
}
