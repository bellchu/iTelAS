import Foundation
import XCTest
@testable import iTelASCore

final class AuthorityInsightTests: XCTestCase {
    private let subject = AuthoritySubject(profile: try! IBMSystemObjectName("RPGDEV1"))
    private let target = IBMObjectIdentity(
        library: try! IBMSystemObjectName("ARLIB"),
        name: try! IBMSystemObjectName("PAYROLL"),
        type: .file
    )

    func testSubjectAndPlannerUseExactBoundedReadOnlyQueries() throws {
        let normalized = try AuthoritySubject("rpgdev1")
        XCTAssertEqual(normalized.description, "RPGDEV1")
        XCTAssertThrowsError(try AuthoritySubject("RPGDEV1'"))

        let planner = AuthoritySQLPlanner(subject: subject, target: target)
        var requests = planner.initialRequests
        requests.append((.authorizationListUserInfo, planner.authorizationListUserInfo(try IBMSystemObjectName("PAYAUTL"))))
        XCTAssertEqual(requests.count, 5)
        for (_, request) in requests {
            XCTAssertTrue(request.readOnly)
            XCTAssertEqual(request.timeoutSeconds, 30)
            XCTAssertTrue((1...101).contains(request.maximumRows))
            XCTAssertTrue(SQLStatementAnalyzer().analyze(request.sql).isSingleReadOnlyStatement)
            XCTAssertNoThrow(try Db2OperationAuthorizer(accessMode: .readOnly).authorizeInteractiveSQL(request))
            for mutation in [" GRANT ", " REVOKE ", " CALL ", " UPDATE ", " DELETE ", " INSERT "] {
                XCTAssertFalse(" \(request.sql.uppercased()) ".contains(mutation))
            }
        }
        XCTAssertTrue(planner.userInfo.sql.contains("AUTHORIZATION_NAME = 'RPGDEV1'"))
        XCTAssertTrue(planner.objectPrivileges.sql.contains("SYSTEM_OBJECT_NAME = 'PAYROLL'"))
        XCTAssertTrue(planner.authorityCollection.sql.contains("SYSTEM_OBJECT_TYPE = '*FILE'"))
    }

    func testProfileDecoderUsesColumnNamesAndExcludesPasswordFields() throws {
        let values: [String: SQLValue] = [
            "AUTHORIZATION_NAME": .string("RPGDEV1"),
            "STATUS": .string("*ENABLED"),
            "USER_CLASS_NAME": .string("*PGMR"),
            "SPECIAL_AUTHORITIES": .string("*JOBCTL    *SAVSYS"),
            "GROUP_PROFILE_NAME": .string("APPDEV"),
            "SUPPLEMENTAL_GROUP_COUNT": .integer(2),
            "AUTHORITY_COLLECTION_ACTIVE": .string("YES"),
            "AUTHORITY_COLLECTION_REPOSITORY_EXISTS": .string("YES"),
            "LAST_USED_TIMESTAMP": .timestamp(Date(timeIntervalSince1970: 1_000))
        ]
        let profile = try XCTUnwrap(AuthoritySQLDecoder().decodeProfile(
            namedResult(order: values.keys.reversed(), values: values),
            subject: subject
        ))
        XCTAssertEqual(profile.userClass, "*PGMR")
        XCTAssertEqual(profile.primaryGroup, "APPDEV")
        XCTAssertEqual(profile.specialAuthorities, ["*JOBCTL", "*SAVSYS"])
        XCTAssertTrue(profile.authorityCollectionActive)
        XCTAssertFalse(AuthoritySQLPlanner(subject: subject, target: target).userInfo.sql.contains("PASSWORD"))
    }

    func testProfileDecoderFailsClosedOnDuplicateMissingMismatchAndTruncation() throws {
        let values = profileValues
        let columns = Array(values.keys)
        let duplicate = columns + ["authorization_name"]
        let duplicateRow = columns.map { values[$0]! } + [.string("RPGDEV1")]
        XCTAssertThrowsError(try AuthoritySQLDecoder().decodeProfile(
            result(columns: duplicate, rows: [duplicateRow]),
            subject: subject
        )) { error in
            XCTAssertEqual(error as? AuthorityInsightError, .duplicateColumn(source: "USER_INFO", column: "AUTHORIZATION_NAME"))
        }

        let missing = columns.filter { $0 != "STATUS" }
        XCTAssertThrowsError(try AuthoritySQLDecoder().decodeProfile(
            namedResult(order: missing, values: values),
            subject: subject
        )) { error in
            XCTAssertEqual(error as? AuthorityInsightError, .missingColumn(source: "USER_INFO", column: "STATUS"))
        }

        var mismatch = values
        mismatch["AUTHORIZATION_NAME"] = .string("OTHER")
        XCTAssertThrowsError(try AuthoritySQLDecoder().decodeProfile(
            namedResult(order: columns, values: mismatch),
            subject: subject
        )) { error in
            XCTAssertEqual(error as? AuthorityInsightError, .identityMismatch(source: "USER_INFO"))
        }

        XCTAssertThrowsError(try AuthoritySQLDecoder().decodeProfile(
            namedResult(order: columns, values: values, truncated: true),
            subject: subject
        )) { error in
            XCTAssertEqual(error as? AuthorityInsightError, .truncatedResult(source: "USER_INFO"))
        }
    }

    func testGroupDecoderRejectsCrossSubjectAndControlText() throws {
        let values: [String: SQLValue] = [
            "GROUP_PROFILE_NAME": .string("APPDEV"),
            "USER_PROFILE_NAME": .string("RPGDEV1"),
            "USER_TEXT": .string("Application developer")
        ]
        let membership = try XCTUnwrap(AuthoritySQLDecoder().decodeGroups(
            namedResult(order: values.keys.reversed(), values: values),
            subject: subject
        ).first)
        XCTAssertEqual(membership.groupProfile, "APPDEV")

        var mismatch = values
        mismatch["USER_PROFILE_NAME"] = .string("OTHER")
        XCTAssertThrowsError(try AuthoritySQLDecoder().decodeGroups(
            namedResult(order: values.keys, values: mismatch),
            subject: subject
        ))
        var unsafe = values
        unsafe["USER_TEXT"] = .string("customer\nsecret")
        XCTAssertThrowsError(try AuthoritySQLDecoder().decodeGroups(
            namedResult(order: values.keys, values: unsafe),
            subject: subject
        ))
    }

    func testObjectAndAuthorizationListDecodersPreserveAuthorityBits() throws {
        let objectGrant = try XCTUnwrap(AuthoritySQLDecoder().decodeObjectGrants(
            namedResult(order: objectGrantValues.keys.reversed(), values: objectGrantValues),
            target: target
        ).first)
        XCTAssertEqual(objectGrant.authorizationName, "APPDEV")
        XCTAssertEqual(objectGrant.objectAuthority, "*CHANGE")
        XCTAssertEqual(objectGrant.authorizationList, "PAYAUTL")
        XCTAssertTrue(objectGrant.surface.dataUpdate)
        XCTAssertFalse(objectGrant.surface.objectManagement)

        let authorizationList = try IBMSystemObjectName("PAYAUTL")
        let autlGrant = try XCTUnwrap(AuthoritySQLDecoder().decodeAuthorizationListGrants(
            namedResult(order: authorizationListValues.keys.reversed(), values: authorizationListValues),
            authorizationList: authorizationList
        ).first)
        XCTAssertEqual(autlGrant.authorizationName, "PAYROLLR")
        XCTAssertEqual(autlGrant.objectAuthority, "*USE")
        XCTAssertTrue(autlGrant.surface.dataRead)
        XCTAssertFalse(autlGrant.surface.dataUpdate)
    }

    func testPrivilegeDecoderRejectsBoundsIdentityAndInvalidIndicators() throws {
        let columns = Array(objectGrantValues.keys)
        let row = columns.map { objectGrantValues[$0]! }
        let decoder = AuthoritySQLDecoder(limits: .init(maximumPrivilegeRows: 1))
        XCTAssertThrowsError(try decoder.decodeObjectGrants(
            result(columns: columns, rows: [row, row]),
            target: target
        )) { error in
            XCTAssertEqual(error as? AuthorityInsightError, .tooManyRows(source: "OBJECT_PRIVILEGES", maximum: 1))
        }

        var mismatch = objectGrantValues
        mismatch["SYSTEM_OBJECT_NAME"] = .string("OTHER")
        XCTAssertThrowsError(try AuthoritySQLDecoder().decodeObjectGrants(
            namedResult(order: columns, values: mismatch),
            target: target
        ))
        var invalid = objectGrantValues
        invalid["DATA_UPDATE"] = .string("MAYBE")
        XCTAssertThrowsError(try AuthoritySQLDecoder().decodeObjectGrants(
            namedResult(order: columns, values: invalid),
            target: target
        ))
    }

    func testRuntimeDecoderKeepsSourceAndAdoptedAuthoritySeparate() throws {
        let observation = try XCTUnwrap(AuthoritySQLDecoder().decodeRuntimeObservations(
            namedResult(order: runtimeValues.keys.reversed(), values: runtimeValues),
            subject: subject,
            target: target
        ).first)
        XCTAssertTrue(observation.checkSucceeded == true)
        XCTAssertEqual(observation.requiredAuthority, "*USE")
        XCTAssertEqual(observation.authoritySource, "GROUP PRIVATE")
        XCTAssertEqual(observation.groupName, "APPDEV")
        XCTAssertTrue(observation.adoptedAuthorityUsed == true)
        XCTAssertEqual(observation.adoptedAuthoritySource, "ADOPTED PRIVATE")
    }

    func testAnalyzerKeepsStaticObservedAndBlockedPathsDistinct() throws {
        let snapshot = sampleSnapshot()
        XCTAssertEqual(snapshot.staticPaths.filter(\.grantsAccess).count, 3)
        XCTAssertEqual(snapshot.staticPaths.filter { !$0.grantsAccess }.count, 1)
        XCTAssertEqual(snapshot.observedPaths.count, 1)
        XCTAssertEqual(snapshot.assessment.dataChangePathCount, 1)
        XCTAssertEqual(snapshot.assessment.gapCount, 1)
        XCTAssertEqual(snapshot.assessment.verdict, "REVIEW REQUIRED")
        XCTAssertTrue(snapshot.assessment.method.contains("Missing rows never prove absence"))
        XCTAssertTrue(snapshot.assessment.hasAdoptedAuthorityObservation)
    }

    func testAuthorizationListRecognizesPrimaryGroupWhenMembershipRowsAreUnavailable() throws {
        let base = sampleSnapshot()
        let snapshot = AuthorityInsightSnapshot(
            targetName: base.targetName,
            subject: base.subject,
            target: base.target,
            capturedAt: base.capturedAt,
            profile: base.profile,
            groups: [],
            objectGrants: base.objectGrants,
            authorizationListGrants: [
                AuthorityAuthorizationListGrant(
                    authorizationList: "PAYAUTL",
                    authorizationName: "APPDEV",
                    objectAuthority: "*USE",
                    owner: "SECOFR",
                    surface: AuthoritySurface(objectOperational: true, dataRead: true)
                )
            ],
            observations: [],
            receipts: base.receipts
        )

        XCTAssertTrue(snapshot.staticPaths.contains {
            $0.kind == .authorizationList && $0.principal == "APPDEV" && $0.grantsAccess
        })
    }

    func testLocalSimulationNeverWritesAndDoesNotTreatObservedRowsAsStaticProof() throws {
        let snapshot = sampleSnapshot()
        let groupPath = try XCTUnwrap(snapshot.staticPaths.first { $0.principal == "APPDEV" })
        let first = snapshot.simulate(removing: [groupPath.id])
        XCTAssertTrue(first.accessRemains)
        XCTAssertFalse(first.hostWritesPerformed)
        XCTAssertFalse(first.remainingPaths.contains { $0.kind == .observed })

        let allUsable = Set(snapshot.staticPaths.filter(\.grantsAccess).map(\.id))
        let second = snapshot.simulate(removing: allUsable)
        XCTAssertFalse(second.accessRemains)
        XCTAssertFalse(second.hostWritesPerformed)
    }

    func testArtifactIsExactAndAssistContextAliasesIdentities() throws {
        let snapshot = sampleSnapshot(targetName: "private-host")
        let artifact = AuthorityArtifactBuilder().build(snapshot: snapshot)
        XCTAssertTrue(artifact.contains("RPGDEV1"))
        XCTAssertTrue(artifact.contains("ARLIB/PAYROLL *FILE"))
        XCTAssertTrue(artifact.contains("PAYAUTL"))
        XCTAssertTrue(artifact.contains("EFFECTIVE_AUTHORITY_RESOLUTION: UNAVAILABLE"))
        XCTAssertTrue(artifact.contains("No host writes were performed"))

        let context = AuthorityAssistContextBuilder().build(snapshot: snapshot)
        for privateValue in ["private-host", "RPGDEV1", "ARLIB", "PAYROLL", "PAYAUTL", "APPDEV", "PAYROLLR", "APPOWNER"] {
            XCTAssertFalse(context.contains(privateValue))
        }
        XCTAssertTrue(context.contains("SUBJECT-001"))
        XCTAssertTrue(context.contains("OBJECT-001 *FILE"))
        XCTAssertTrue(context.contains("DETAILS WITHHELD"))
        XCTAssertTrue(context.contains("Collection coverage: UNKNOWN"))
    }

    private func sampleSnapshot(targetName: String = "DEV01") -> AuthorityInsightSnapshot {
        let use = AuthoritySurface(objectOperational: true, dataRead: true, dataExecute: true)
        let change = AuthoritySurface(
            objectOperational: true,
            dataRead: true,
            dataAdd: true,
            dataUpdate: true,
            dataDelete: true,
            dataExecute: true
        )
        let profile = AuthorityProfileSnapshot(
            subject: subject,
            status: "*ENABLED",
            userClass: "*PGMR",
            specialAuthorities: ["*JOBCTL"],
            primaryGroup: "APPDEV",
            supplementalGroupCount: 1,
            authorityCollectionActive: true,
            authorityCollectionRepositoryExists: true,
            lastUsedAt: Date(timeIntervalSince1970: 900)
        )
        let grants = [
            AuthorityObjectGrant(
                target: target,
                authorizationName: "RPGDEV1",
                objectAuthority: "*USE",
                owner: "APPOWNER",
                authorizationList: "PAYAUTL",
                primaryGroup: "APPDEV",
                isObjectOwner: false,
                surface: use
            ),
            AuthorityObjectGrant(
                target: target,
                authorizationName: "APPDEV",
                objectAuthority: "*CHANGE",
                owner: "APPOWNER",
                authorizationList: "PAYAUTL",
                primaryGroup: "APPDEV",
                isObjectOwner: false,
                surface: change
            ),
            AuthorityObjectGrant(
                target: target,
                authorizationName: "*PUBLIC",
                objectAuthority: "*EXCLUDE",
                owner: "APPOWNER",
                authorizationList: "PAYAUTL",
                primaryGroup: "APPDEV",
                isObjectOwner: false,
                surface: .none
            )
        ]
        let autl = AuthorityAuthorizationListGrant(
            authorizationList: "PAYAUTL",
            authorizationName: "PAYROLLR",
            objectAuthority: "*USE",
            owner: "SECOFR",
            surface: use
        )
        let observation = AuthorityRuntimeObservation(
            subject: subject,
            target: target,
            checkedAt: Date(timeIntervalSince1970: 1_000),
            checkSucceeded: true,
            requiredAuthority: "*USE",
            detailedRequiredAuthority: "*OBJOPR *READ",
            currentAuthority: "*CHANGE",
            detailedCurrentAuthority: "*OBJOPR *READ *ADD *UPD *DLT *EXECUTE",
            authoritySource: "GROUP PRIVATE",
            groupName: "APPDEV",
            adoptedAuthorityUsed: true,
            currentAdoptedAuthority: "*USE",
            adoptedAuthoritySource: "ADOPTED PRIVATE"
        )
        let receipts = AuthorityEvidenceSource.liveSQLSources.map { source in
            AuthorityEvidenceReceipt(
                source: source,
                rowCount: 1,
                boundWasReached: false,
                elapsedMilliseconds: 12,
                queryFingerprint: "sha-\(source.rawValue)",
                outcome: .collected
            )
        } + [AuthorityEvidenceReceipt(
            source: .effectiveAuthorityResolution,
            rowCount: 0,
            boundWasReached: false,
            elapsedMilliseconds: nil,
            queryFingerprint: "private-fingerprint",
            outcome: .unavailable("private diagnostic")
        )]
        return AuthorityInsightSnapshot(
            targetName: targetName,
            subject: subject,
            target: target,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            profile: profile,
            groups: [AuthorityGroupMembership(groupProfile: "APPDEV", userProfile: "RPGDEV1"), AuthorityGroupMembership(groupProfile: "PAYROLLR", userProfile: "RPGDEV1")],
            objectGrants: grants,
            authorizationListGrants: [autl],
            observations: [observation],
            receipts: receipts,
            isBundledReplay: true
        )
    }

    private var profileValues: [String: SQLValue] {
        [
            "AUTHORIZATION_NAME": .string("RPGDEV1"),
            "STATUS": .string("*ENABLED"),
            "USER_CLASS_NAME": .string("*PGMR"),
            "SPECIAL_AUTHORITIES": .null,
            "GROUP_PROFILE_NAME": .string("APPDEV"),
            "SUPPLEMENTAL_GROUP_COUNT": .integer(1),
            "AUTHORITY_COLLECTION_ACTIVE": .string("YES"),
            "AUTHORITY_COLLECTION_REPOSITORY_EXISTS": .string("YES"),
            "LAST_USED_TIMESTAMP": .timestamp(Date(timeIntervalSince1970: 1_000))
        ]
    }

    private var objectGrantValues: [String: SQLValue] {
        var values: [String: SQLValue] = [
            "SYSTEM_OBJECT_SCHEMA": .string("ARLIB"),
            "SYSTEM_OBJECT_NAME": .string("PAYROLL"),
            "OBJECT_TYPE": .string("*FILE"),
            "AUTHORIZATION_NAME": .string("APPDEV"),
            "OBJECT_AUTHORITY": .string("*CHANGE"),
            "OWNER": .string("APPOWNER"),
            "AUTHORIZATION_LIST": .string("PAYAUTL"),
            "PRIMARY_GROUP": .string("APPDEV"),
            "OBJECT_OWNER": .string("NO")
        ]
        for column in surfaceColumns { values[column] = .string("NO") }
        for column in ["OBJECT_OPERATIONAL", "DATA_READ", "DATA_ADD", "DATA_UPDATE", "DATA_DELETE", "DATA_EXECUTE"] {
            values[column] = .string("YES")
        }
        return values
    }

    private var authorizationListValues: [String: SQLValue] {
        var values: [String: SQLValue] = [
            "AUTHORIZATION_LIST": .string("PAYAUTL"),
            "AUTHORIZATION_NAME": .string("PAYROLLR"),
            "OBJECT_AUTHORITY": .string("*USE"),
            "OWNER": .string("SECOFR")
        ]
        for column in surfaceColumns { values[column] = .string("NO") }
        for column in ["OBJECT_OPERATIONAL", "DATA_READ", "DATA_EXECUTE"] {
            values[column] = .string("YES")
        }
        return values
    }

    private var runtimeValues: [String: SQLValue] {
        [
            "AUTHORIZATION_NAME": .string("RPGDEV1"),
            "CHECK_TIMESTAMP": .timestamp(Date(timeIntervalSince1970: 1_000)),
            "SYSTEM_OBJECT_SCHEMA": .string("ARLIB"),
            "SYSTEM_OBJECT_NAME": .string("PAYROLL"),
            "SYSTEM_OBJECT_TYPE": .string("*FILE"),
            "AUTHORIZATION_LIST": .string("PAYAUTL"),
            "AUTHORITY_CHECK_SUCCESSFUL": .string("1"),
            "REQUIRED_AUTHORITY": .string("*USE"),
            "DETAILED_REQUIRED_AUTHORITY": .string("*OBJOPR *READ"),
            "CURRENT_AUTHORITY": .string("*CHANGE"),
            "DETAILED_CURRENT_AUTHORITY": .string("*OBJOPR *READ *ADD *UPD *DLT *EXECUTE"),
            "AUTHORITY_SOURCE": .string("GROUP PRIVATE"),
            "GROUP_NAME": .string("APPDEV"),
            "ADOPT_AUTHORITY_USED": .string("1"),
            "CURRENT_ADOPTED_AUTHORITY": .string("*USE"),
            "ADOPTED_AUTHORITY_SOURCE": .string("ADOPTED PRIVATE")
        ]
    }

    private var surfaceColumns: [String] {
        [
            "AUTHORIZATION_LIST_MANAGEMENT", "OBJECT_OPERATIONAL", "OBJECT_MANAGEMENT", "OBJECT_EXISTENCE",
            "OBJECT_ALTER", "OBJECT_REFERENCE", "DATA_READ", "DATA_ADD", "DATA_UPDATE", "DATA_DELETE",
            "DATA_EXECUTE"
        ]
    }

    private func namedResult<S: Sequence>(
        order: S,
        values: [String: SQLValue],
        truncated: Bool = false
    ) -> SQLResult where S.Element == String {
        let columns = Array(order)
        return result(
            columns: columns,
            rows: [columns.map { values[$0] ?? .null }],
            truncated: truncated
        )
    }

    private func result(
        columns: [String],
        rows: [[SQLValue]],
        truncated: Bool = false
    ) -> SQLResult {
        SQLResult(
            columns: columns.map { SQLColumn(name: $0, databaseType: "VARCHAR", isNullable: true) },
            rows: rows,
            targetName: "TEST",
            startedAt: Date(timeIntervalSince1970: 1_000),
            elapsedMilliseconds: 12,
            wasTruncated: truncated
        )
    }
}
