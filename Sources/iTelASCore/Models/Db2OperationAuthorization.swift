import Foundation

public enum Db2OperationAuthorizationError: Error, Equatable, LocalizedError, Sendable {
    case capabilityMismatch
    case unsafeSQLRequest
    case unrecognizedSourceRequest
    case unrecognizedSourceMemberPlan

    public var errorDescription: String? {
        switch self {
        case .capabilityMismatch:
            "The connected Db2 capability does not authorize this operation."
        case .unsafeSQLRequest:
            "The Db2 request did not pass the single-statement, read-only, row, and timeout bounds."
        case .unrecognizedSourceRequest:
            "The source-member query is outside the generated read contract."
        case .unrecognizedSourceMemberPlan:
            "The source-member operation no longer matches its generated, reviewed plan."
        }
    }
}

/// Application-level enforcement layered on top of the IBM driver connection type. The IBM
/// driver needs read/write mode to create a QTEMP member alias, so that narrow exception is
/// authorized here rather than exposing a general-purpose write session.
public struct Db2OperationAuthorizer: Sendable {
    public static let maximumInteractiveRows = 10_000
    public static let maximumTimeoutSeconds = 120

    private let analyzer = SQLStatementAnalyzer()
    public let accessMode: Db2AccessMode

    public init(accessMode: Db2AccessMode) {
        self.accessMode = accessMode
    }

    public func authorizeInteractiveSQL(_ request: SQLExecutionRequest) throws {
        guard accessMode == .readOnly,
              request.readOnly,
              (1...Self.maximumInteractiveRows).contains(request.maximumRows),
              (1...Self.maximumTimeoutSeconds).contains(request.timeoutSeconds),
              analyzer.analyze(request.sql).isSingleReadOnlyStatement else {
            throw Db2OperationAuthorizationError.unsafeSQLRequest
        }
    }

    public func authorizeSourceQuery(_ request: SourceMemberSQLRequest) throws {
        let allowedPurposes: Set<SourceMemberSQLPurpose> = [
            .listLibraries, .listSourceFiles, .listMembers, .readMetadata
        ]
        guard accessMode == .sourceMemberRead || accessMode == .reviewedSourceMemberWrite else {
            throw Db2OperationAuthorizationError.capabilityMismatch
        }
        guard allowedPurposes.contains(request.purpose),
              request.readOnly,
              request.maximumRows >= 1,
              request.maximumRows <= SourceMemberMetadata.maximumEditableRecords,
              (1...Self.maximumTimeoutSeconds).contains(request.timeoutSeconds),
              analyzer.analyze(request.sql).isSingleReadOnlyStatement else {
            throw Db2OperationAuthorizationError.unrecognizedSourceRequest
        }
    }

    public func authorizeReadMember(
        identity: SourceMemberIdentity,
        metadata: SourceMemberSQLRequest,
        aliasPlan: SourceMemberAliasPlan
    ) throws {
        guard accessMode == .sourceMemberRead || accessMode == .reviewedSourceMemberWrite else {
            throw Db2OperationAuthorizationError.capabilityMismatch
        }
        let planner = SourceMemberSQLPlanner()
        guard metadata == planner.metadata(for: identity),
              aliasPlan == (try planner.aliasPlan(for: identity)),
              aliasPlan.create.purpose == .createTemporaryAlias,
              aliasPlan.readRecords.purpose == .readRecords,
              aliasPlan.drop.purpose == .dropTemporaryAlias else {
            throw Db2OperationAuthorizationError.unrecognizedSourceMemberPlan
        }
    }

    public func authorizeTransactionalReplace(_ plan: SourceMemberTransactionalReplacePlan) throws {
        guard accessMode == .reviewedSourceMemberWrite else {
            throw Db2OperationAuthorizationError.capabilityMismatch
        }
        let expected = try SourceMemberSQLPlanner().transactionalReplacePlan(for: plan.writePlan)
        guard plan == expected,
              plan.isolation == .serializable,
              plan.requiresBeforeAndAfterImages,
              plan.writePlan.requiresJournaledTransaction,
              plan.statementBatchSize == 250 else {
            throw Db2OperationAuthorizationError.unrecognizedSourceMemberPlan
        }
    }
}
