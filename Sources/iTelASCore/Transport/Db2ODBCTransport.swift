import Darwin
import Foundation

public enum Db2ODBCTransportError: Error, Equatable, LocalizedError, Sendable {
    case prerequisitesMissing
    case driverManagerMissing
    case symbolMissing(String)
    case alreadyConnected
    case notConnected
    case operationFailed(operation: String, sqlState: String, nativeCode: Int32, message: String)
    case resultValueTooLarge
    case malformedUTF8
    case unsupportedParameter
    case sourceResultTruncated
    case revisionChanged
    case committedRevisionMismatch

    public var errorDescription: String? {
        switch self {
        case .prerequisitesMissing:
            "The native arm64 unixODBC, IBM i Access ODBC, and TLS prerequisites are not ready."
        case .driverManagerMissing:
            "The unixODBC driver-manager library was not found at a supported local path."
        case .symbolMissing(let symbol):
            "The unixODBC runtime is missing the required \(symbol) entry point."
        case .alreadyConnected:
            "This Db2 transport is already connected."
        case .notConnected:
            "The Db2 transport is not connected."
        case .operationFailed(let operation, let state, let nativeCode, let message):
            "\(operation) failed (\(state), \(nativeCode)): \(message)"
        case .resultValueTooLarge:
            "A Db2 value exceeded the bounded 4 MiB result-cell limit."
        case .malformedUTF8:
            "The IBM i ODBC driver returned text that was not valid UTF-8."
        case .unsupportedParameter:
            "The Db2 request contains a parameter type this transport does not bind."
        case .sourceResultTruncated:
            "The source-member result hit a safety bound and was not accepted as complete."
        case .revisionChanged:
            "The source member changed after review; the transaction was rolled back."
        case .committedRevisionMismatch:
            "The transactional source-member result did not match the reviewed revision."
        }
    }
}

/// Native IBM i database transport. unixODBC is loaded only from fixed Homebrew locations, so
/// the app remains a native arm64 binary and starts normally when the optional driver is absent.
public actor Db2ODBCTransport: DatabaseProvider, SourceMemberSQLTransport {
    public nonisolated let providerName = "IBM i Access ODBC"
    public nonisolated let targetName: String
    public nonisolated let environment: IBMEnvironment
    public nonisolated let accessMode: Db2AccessMode

    private let profile: Db2ConnectionProfile
    private let runtimeSnapshot: ProviderRuntimeSnapshot
    private let authorizer: Db2OperationAuthorizer
    private var session: Db2ODBCSession?
    private var currentReceipt: Db2ConnectionReceipt?

    public init(
        profile: Db2ConnectionProfile,
        accessMode: Db2AccessMode,
        runtimeSnapshot: ProviderRuntimeSnapshot = ProviderRuntimeProbe().inspectLocalMachine()
    ) {
        self.profile = profile
        self.accessMode = accessMode
        self.runtimeSnapshot = runtimeSnapshot
        authorizer = Db2OperationAuthorizer(accessMode: accessMode)
        targetName = profile.targetLabel
        environment = profile.environment
    }

    public var receipt: Db2ConnectionReceipt? { currentReceipt }
    public var isConnected: Bool { session != nil }

    @discardableResult
    public func connect(password: Db2Password) throws -> Db2ConnectionReceipt {
        guard session == nil else { throw Db2ODBCTransportError.alreadyConnected }
        guard runtimeSnapshot.secureDb2PrerequisitesReady else {
            throw Db2ODBCTransportError.prerequisitesMissing
        }
        let plan = try Db2ConnectionPlanner().plan(
            profile: profile,
            password: password,
            accessMode: accessMode
        )
        let opened = try Db2ODBCSession.open(plan: plan, password: password)
        let receipt = Db2ConnectionReceipt(
            profileID: profile.id,
            targetName: profile.targetLabel,
            environment: profile.environment,
            accessMode: accessMode,
            connectedAt: Date()
        )
        session = opened
        currentReceipt = receipt
        return receipt
    }

    public func disconnect() {
        session?.close()
        session = nil
        currentReceipt = nil
    }

    public func execute(_ request: SQLExecutionRequest) async throws -> SQLResult {
        try authorizer.authorizeInteractiveSQL(request)
        return try requireSession().execute(
            sql: request.sql,
            bindings: [],
            maximumRows: request.maximumRows,
            timeoutSeconds: request.timeoutSeconds
        )
    }

    public func query(_ request: SourceMemberSQLRequest) async throws -> SQLResult {
        try authorizer.authorizeSourceQuery(request)
        let session = try requireSession()
        do {
            let result = try session.execute(
                sql: request.sql,
                bindings: request.bindings,
                maximumRows: request.maximumRows,
                timeoutSeconds: request.timeoutSeconds
            )
            if accessMode.requiresExplicitTransaction { try session.commit() }
            return result
        } catch {
            if accessMode.requiresExplicitTransaction { try? session.rollback() }
            throw error
        }
    }

    public func readMember(
        identity: SourceMemberIdentity,
        metadata: SourceMemberSQLRequest,
        aliasPlan: SourceMemberAliasPlan
    ) async throws -> SourceMemberSnapshot {
        try authorizer.authorizeReadMember(
            identity: identity,
            metadata: metadata,
            aliasPlan: aliasPlan
        )
        let session = try requireSession()
        do {
            let snapshot = try Self.readSnapshot(
                session: session,
                identity: identity,
                metadata: metadata,
                aliasPlan: aliasPlan
            )
            if accessMode.requiresExplicitTransaction { try session.commit() }
            return snapshot
        } catch {
            if accessMode.requiresExplicitTransaction { try? session.rollback() }
            throw error
        }
    }

    public func transactionalReplace(
        _ plan: SourceMemberTransactionalReplacePlan
    ) async throws -> SourceMemberSnapshot {
        try authorizer.authorizeTransactionalReplace(plan)
        let session = try requireSession()
        let alias = plan.aliasPlan.alias.sqlIdentifier
        var aliasWasCreated = false

        do {
            _ = try session.execute(request: plan.aliasPlan.create)
            aliasWasCreated = true
            try session.commit()

            let metadataResult = try session.execute(request: SourceMemberSQLPlanner().metadata(for: plan.writePlan.identity))
            let beforeRows = try session.execute(request: plan.aliasPlan.readRecords)
            let before = try Self.decodeCompleteSnapshot(
                identity: plan.writePlan.identity,
                metadataResult: metadataResult,
                recordsResult: beforeRows
            )
            guard before.revision == plan.writePlan.expectedRevision else {
                throw Db2ODBCTransportError.revisionChanged
            }

            _ = try session.execute(
                sql: "DELETE FROM QTEMP.\(alias)",
                bindings: [],
                maximumRows: 0,
                timeoutSeconds: 30
            )
            for batch in plan.writePlan.records.chunked(maximumCount: plan.statementBatchSize) {
                try Task.checkCancellation()
                for record in batch {
                    _ = try session.execute(
                        sql: "INSERT INTO QTEMP.\(alias) (SRCSEQ, SRCDAT, SRCDTA) VALUES (?, ?, ?)",
                        bindings: [
                            .decimal(record.sequence.description),
                            .decimal(record.sourceDate.description),
                            .string(record.text)
                        ],
                        maximumRows: 0,
                        timeoutSeconds: 30
                    )
                }
            }

            let afterRows = try session.execute(request: plan.aliasPlan.readRecords)
            let adjustedMetadata = try Self.metadataResult(
                metadataResult,
                replacingRecordCountWith: plan.writePlan.records.count
            )
            let after = try Self.decodeCompleteSnapshot(
                identity: plan.writePlan.identity,
                metadataResult: adjustedMetadata,
                recordsResult: afterRows
            )
            guard after.revision == plan.writePlan.proposedRevision else {
                throw Db2ODBCTransportError.committedRevisionMismatch
            }
            try session.commit()

            do {
                _ = try session.execute(request: plan.aliasPlan.drop)
                aliasWasCreated = false
                try session.commit()
            } catch {
                // The reviewed data transaction is already committed. Clear QTEMP by closing
                // the session instead of misreporting the committed write as a failed write.
                try? session.rollback()
                session.close()
                self.session = nil
                currentReceipt = nil
                aliasWasCreated = false
            }
            return after
        } catch {
            try? session.rollback()
            if aliasWasCreated {
                _ = try? session.execute(request: plan.aliasPlan.drop)
                try? session.commit()
            }
            throw error
        }
    }

    private func requireSession() throws -> Db2ODBCSession {
        guard let session else { throw Db2ODBCTransportError.notConnected }
        return session
    }

    private static func readSnapshot(
        session: Db2ODBCSession,
        identity: SourceMemberIdentity,
        metadata: SourceMemberSQLRequest,
        aliasPlan: SourceMemberAliasPlan
    ) throws -> SourceMemberSnapshot {
        let metadataResult = try session.execute(request: metadata)
        _ = try session.execute(request: aliasPlan.create)
        var aliasWasCreated = true
        defer {
            if aliasWasCreated { _ = try? session.execute(request: aliasPlan.drop) }
        }
        let recordsResult = try session.execute(request: aliasPlan.readRecords)
        _ = try session.execute(request: aliasPlan.drop)
        aliasWasCreated = false
        return try decodeCompleteSnapshot(
            identity: identity,
            metadataResult: metadataResult,
            recordsResult: recordsResult
        )
    }

    private static func decodeCompleteSnapshot(
        identity: SourceMemberIdentity,
        metadataResult: SQLResult,
        recordsResult: SQLResult
    ) throws -> SourceMemberSnapshot {
        guard !metadataResult.wasTruncated, !recordsResult.wasTruncated else {
            throw Db2ODBCTransportError.sourceResultTruncated
        }
        return try SourceMemberSQLResultDecoder().decodeSnapshot(
            identity: identity,
            metadataResult: metadataResult,
            recordsResult: recordsResult
        )
    }

    private static func metadataResult(
        _ result: SQLResult,
        replacingRecordCountWith recordCount: Int
    ) throws -> SQLResult {
        let matchingColumns = result.columns.indices.filter {
            result.columns[$0].name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("NUMBER_ROWS") == .orderedSame
        }
        guard result.rows.count == 1,
              result.rows[0].count == result.columns.count,
              matchingColumns.count == 1,
              let recordCountColumn = matchingColumns.first else {
            throw SourceMemberWorkspaceError.providerResultMalformed
        }
        var rows = result.rows
        rows[0][recordCountColumn] = .integer(Int64(recordCount))
        return SQLResult(
            columns: result.columns,
            rows: rows,
            targetName: result.targetName,
            startedAt: result.startedAt,
            elapsedMilliseconds: result.elapsedMilliseconds,
            wasTruncated: result.wasTruncated
        )
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [ArraySlice<Element>] {
        guard maximumCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maximumCount).map { start in
            self[start..<Swift.min(start + maximumCount, count)]
        }
    }
}

private typealias ODBCHandle = UnsafeMutableRawPointer?
private typealias ODBCReturn = Int16
private typealias ODBCSmallInt = Int16
private typealias ODBCUShort = UInt16
private typealias ODBCInteger = Int32
private typealias ODBCUInteger = UInt32
private typealias ODBCLength = Int
private typealias ODBCULength = UInt

private enum ODBCConstant {
    static let success: ODBCReturn = 0
    static let successWithInfo: ODBCReturn = 1
    static let noData: ODBCReturn = 100

    static let nullData: ODBCLength = -1
    static let noTotal: ODBCLength = -4
    static let nts: ODBCInteger = -3

    static let handleEnvironment: ODBCSmallInt = 1
    static let handleConnection: ODBCSmallInt = 2
    static let handleStatement: ODBCSmallInt = 3

    static let attrODBCVersion: ODBCInteger = 200
    static let odbcVersion3: Int = 3
    static let attrAccessMode: ODBCInteger = 101
    static let attrAutoCommit: ODBCInteger = 102
    static let attrLoginTimeout: ODBCInteger = 103
    static let attrTransactionIsolation: ODBCInteger = 108
    static let attrConnectionTimeout: ODBCInteger = 113
    static let attrQueryTimeout: ODBCInteger = 0
    static let attrMaximumRows: ODBCInteger = 1
    static let integerAttributeLength: ODBCInteger = -5

    static let autoCommitOff = 0
    static let autoCommitOn = 1
    static let transactionSerializable = 8
    static let driverNoPrompt: ODBCUShort = 0
    static let commit: ODBCSmallInt = 0
    static let rollback: ODBCSmallInt = 1

    static let parameterInput: ODBCSmallInt = 1
    static let cCharacter: ODBCSmallInt = 1
    static let cBinary: ODBCSmallInt = -2
    static let sqlCharacter: ODBCSmallInt = 1
    static let sqlNumeric: ODBCSmallInt = 2
    static let sqlDecimal: ODBCSmallInt = 3
    static let sqlInteger: ODBCSmallInt = 4
    static let sqlSmallInteger: ODBCSmallInt = 5
    static let sqlFloat: ODBCSmallInt = 6
    static let sqlReal: ODBCSmallInt = 7
    static let sqlDouble: ODBCSmallInt = 8
    static let sqlDateLegacy: ODBCSmallInt = 9
    static let sqlTimeLegacy: ODBCSmallInt = 10
    static let sqlTimestampLegacy: ODBCSmallInt = 11
    static let sqlVarchar: ODBCSmallInt = 12
    static let sqlLongVarchar: ODBCSmallInt = -1
    static let sqlBinary: ODBCSmallInt = -2
    static let sqlVarBinary: ODBCSmallInt = -3
    static let sqlLongVarBinary: ODBCSmallInt = -4
    static let sqlBigInteger: ODBCSmallInt = -5
    static let sqlTinyInteger: ODBCSmallInt = -6
    static let sqlBit: ODBCSmallInt = -7
    static let sqlWideCharacter: ODBCSmallInt = -8
    static let sqlWideVarchar: ODBCSmallInt = -9
    static let sqlWideLongVarchar: ODBCSmallInt = -10
    static let sqlTypeDate: ODBCSmallInt = 91
    static let sqlTypeTime: ODBCSmallInt = 92
    static let sqlTypeTimestamp: ODBCSmallInt = 93
}

private typealias SQLAllocHandleFunction = @convention(c) (
    ODBCSmallInt, ODBCHandle, UnsafeMutablePointer<ODBCHandle>?
) -> ODBCReturn
private typealias SQLSetEnvAttrFunction = @convention(c) (
    ODBCHandle, ODBCInteger, UnsafeMutableRawPointer?, ODBCInteger
) -> ODBCReturn
private typealias SQLSetConnectAttrFunction = @convention(c) (
    ODBCHandle, ODBCInteger, UnsafeMutableRawPointer?, ODBCInteger
) -> ODBCReturn
private typealias SQLDriverConnectFunction = @convention(c) (
    ODBCHandle, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, ODBCSmallInt,
    UnsafeMutablePointer<UInt8>?, ODBCSmallInt, UnsafeMutablePointer<ODBCSmallInt>?, ODBCUShort
) -> ODBCReturn
private typealias SQLDisconnectFunction = @convention(c) (ODBCHandle) -> ODBCReturn
private typealias SQLFreeHandleFunction = @convention(c) (ODBCSmallInt, ODBCHandle) -> ODBCReturn
private typealias SQLSetStmtAttrFunction = @convention(c) (
    ODBCHandle, ODBCInteger, UnsafeMutableRawPointer?, ODBCInteger
) -> ODBCReturn
private typealias SQLPrepareFunction = @convention(c) (
    ODBCHandle, UnsafeMutablePointer<UInt8>?, ODBCInteger
) -> ODBCReturn
private typealias SQLBindParameterFunction = @convention(c) (
    ODBCHandle, ODBCUShort, ODBCSmallInt, ODBCSmallInt, ODBCSmallInt,
    ODBCULength, ODBCSmallInt, UnsafeMutableRawPointer?, ODBCLength,
    UnsafeMutablePointer<ODBCLength>?
) -> ODBCReturn
private typealias SQLExecuteFunction = @convention(c) (ODBCHandle) -> ODBCReturn
private typealias SQLNumResultColsFunction = @convention(c) (
    ODBCHandle, UnsafeMutablePointer<ODBCSmallInt>?
) -> ODBCReturn
private typealias SQLDescribeColFunction = @convention(c) (
    ODBCHandle, ODBCUShort, UnsafeMutablePointer<UInt8>?, ODBCSmallInt,
    UnsafeMutablePointer<ODBCSmallInt>?, UnsafeMutablePointer<ODBCSmallInt>?,
    UnsafeMutablePointer<ODBCULength>?, UnsafeMutablePointer<ODBCSmallInt>?,
    UnsafeMutablePointer<ODBCSmallInt>?
) -> ODBCReturn
private typealias SQLFetchFunction = @convention(c) (ODBCHandle) -> ODBCReturn
private typealias SQLGetDataFunction = @convention(c) (
    ODBCHandle, ODBCUShort, ODBCSmallInt, UnsafeMutableRawPointer?, ODBCLength,
    UnsafeMutablePointer<ODBCLength>?
) -> ODBCReturn
private typealias SQLEndTranFunction = @convention(c) (
    ODBCSmallInt, ODBCHandle, ODBCSmallInt
) -> ODBCReturn
private typealias SQLGetDiagRecFunction = @convention(c) (
    ODBCSmallInt, ODBCHandle, ODBCSmallInt, UnsafeMutablePointer<UInt8>?,
    UnsafeMutablePointer<ODBCInteger>?, UnsafeMutablePointer<UInt8>?, ODBCSmallInt,
    UnsafeMutablePointer<ODBCSmallInt>?
) -> ODBCReturn

private final class Db2ODBCAPI: @unchecked Sendable {
    static let supportedLibraryPaths = ProviderRuntimeProbe.unixODBCLibraryCandidates

    let libraryHandle: UnsafeMutableRawPointer
    let allocHandle: SQLAllocHandleFunction
    let setEnvironmentAttribute: SQLSetEnvAttrFunction
    let setConnectionAttribute: SQLSetConnectAttrFunction
    let driverConnect: SQLDriverConnectFunction
    let disconnect: SQLDisconnectFunction
    let freeHandle: SQLFreeHandleFunction
    let setStatementAttribute: SQLSetStmtAttrFunction
    let prepare: SQLPrepareFunction
    let bindParameter: SQLBindParameterFunction
    let execute: SQLExecuteFunction
    let numberOfResultColumns: SQLNumResultColsFunction
    let describeColumn: SQLDescribeColFunction
    let fetch: SQLFetchFunction
    let getData: SQLGetDataFunction
    let endTransaction: SQLEndTranFunction
    let getDiagnosticRecord: SQLGetDiagRecFunction

    init(fileManager: FileManager = .default) throws {
        guard let path = Self.supportedLibraryPaths.first(where: fileManager.fileExists(atPath:)) else {
            throw Db2ODBCTransportError.driverManagerMissing
        }
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw Db2ODBCTransportError.driverManagerMissing
        }
        libraryHandle = handle
        do {
            allocHandle = try Self.load("SQLAllocHandle", from: handle)
            setEnvironmentAttribute = try Self.load("SQLSetEnvAttr", from: handle)
            setConnectionAttribute = try Self.load("SQLSetConnectAttr", from: handle)
            driverConnect = try Self.load("SQLDriverConnect", from: handle)
            disconnect = try Self.load("SQLDisconnect", from: handle)
            freeHandle = try Self.load("SQLFreeHandle", from: handle)
            setStatementAttribute = try Self.load("SQLSetStmtAttr", from: handle)
            prepare = try Self.load("SQLPrepare", from: handle)
            bindParameter = try Self.load("SQLBindParameter", from: handle)
            execute = try Self.load("SQLExecute", from: handle)
            numberOfResultColumns = try Self.load("SQLNumResultCols", from: handle)
            describeColumn = try Self.load("SQLDescribeCol", from: handle)
            fetch = try Self.load("SQLFetch", from: handle)
            getData = try Self.load("SQLGetData", from: handle)
            endTransaction = try Self.load("SQLEndTran", from: handle)
            getDiagnosticRecord = try Self.load("SQLGetDiagRec", from: handle)
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit { dlclose(libraryHandle) }

    private static func load<Function>(
        _ name: String,
        from handle: UnsafeMutableRawPointer
    ) throws -> Function {
        guard let symbol = dlsym(handle, name) else {
            throw Db2ODBCTransportError.symbolMissing(name)
        }
        return unsafeBitCast(symbol, to: Function.self)
    }
}

private struct Db2ODBCColumn {
    let name: String
    let sqlType: ODBCSmallInt
    let databaseType: String
    let isNullable: Bool

    var isBinary: Bool {
        sqlType == ODBCConstant.sqlBinary
            || sqlType == ODBCConstant.sqlVarBinary
            || sqlType == ODBCConstant.sqlLongVarBinary
    }
}

private final class Db2ODBCBoundParameter {
    let cType: ODBCSmallInt
    let sqlType: ODBCSmallInt
    let columnSize: ODBCULength
    let decimalDigits: ODBCSmallInt
    let buffer: UnsafeMutableRawPointer
    let bufferLength: ODBCLength
    let indicator: UnsafeMutablePointer<ODBCLength>

    init(value: SQLValue) throws {
        let payload: Data
        switch value {
        case .null:
            cType = ODBCConstant.cCharacter
            sqlType = ODBCConstant.sqlVarchar
            columnSize = 1
            decimalDigits = 0
            payload = Data()
        case .string(let value):
            cType = ODBCConstant.cCharacter
            sqlType = ODBCConstant.sqlVarchar
            columnSize = ODBCULength(max(1, value.count))
            decimalDigits = 0
            payload = Data(value.utf8)
        case .integer(let value):
            cType = ODBCConstant.cCharacter
            sqlType = ODBCConstant.sqlBigInteger
            let text = String(value)
            columnSize = ODBCULength(text.filter(\.isNumber).count)
            decimalDigits = 0
            payload = Data(text.utf8)
        case .decimal(let value):
            let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
            let digitCount = value.filter(\.isNumber).count
            guard !value.isEmpty,
                  pieces.count <= 2,
                  digitCount > 0,
                  digitCount <= 63,
                  value.enumerated().allSatisfy({ offset, character in
                      character.isNumber || character == "." || (offset == 0 && character == "-")
                  }) else {
                throw Db2ODBCTransportError.unsupportedParameter
            }
            cType = ODBCConstant.cCharacter
            sqlType = ODBCConstant.sqlDecimal
            columnSize = ODBCULength(digitCount)
            decimalDigits = ODBCSmallInt(pieces.count == 2 ? pieces[1].count : 0)
            payload = Data(value.utf8)
        case .date(let value):
            cType = ODBCConstant.cCharacter
            sqlType = ODBCConstant.sqlTypeDate
            columnSize = 10
            decimalDigits = 0
            payload = Data(Self.dateFormatter.string(from: value).utf8)
        case .timestamp(let value):
            cType = ODBCConstant.cCharacter
            sqlType = ODBCConstant.sqlTypeTimestamp
            columnSize = 26
            decimalDigits = 6
            payload = Data(Self.timestampFormatter.string(from: value).utf8)
        case .boolean(let value):
            cType = ODBCConstant.cCharacter
            sqlType = ODBCConstant.sqlBit
            columnSize = 1
            decimalDigits = 0
            payload = Data((value ? "1" : "0").utf8)
        case .binary(let value):
            cType = ODBCConstant.cBinary
            sqlType = ODBCConstant.sqlVarBinary
            columnSize = ODBCULength(max(1, value.count))
            decimalDigits = 0
            payload = value
        }

        guard payload.count <= 4 * 1_024 * 1_024 else {
            throw Db2ODBCTransportError.resultValueTooLarge
        }
        let allocationSize = max(1, payload.count + (cType == ODBCConstant.cCharacter ? 1 : 0))
        let allocatedBuffer = UnsafeMutableRawPointer.allocate(byteCount: allocationSize, alignment: 1)
        allocatedBuffer.initializeMemory(as: UInt8.self, repeating: 0, count: allocationSize)
        payload.withUnsafeBytes { source in
            if let baseAddress = source.baseAddress, !payload.isEmpty {
                allocatedBuffer.copyMemory(from: baseAddress, byteCount: payload.count)
            }
        }
        buffer = allocatedBuffer
        bufferLength = ODBCLength(allocationSize)
        indicator = .allocate(capacity: 1)
        indicator.initialize(to: value.isNull ? ODBCConstant.nullData : ODBCLength(payload.count))
    }

    deinit {
        indicator.deinitialize(count: 1)
        indicator.deallocate()
        buffer.deallocate()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        return formatter
    }()
}

private extension SQLValue {
    var isNull: Bool {
        if case .null = self { true } else { false }
    }
}

private final class Db2ODBCSession: @unchecked Sendable {
    private static let maximumCellBytes = 4 * 1_024 * 1_024
    private static let transferBufferSize = 4_096

    private let api: Db2ODBCAPI
    private let environmentHandle: ODBCHandle
    private let connectionHandle: ODBCHandle
    private let targetName: String
    private var isOpen = true

    private init(
        api: Db2ODBCAPI,
        environmentHandle: ODBCHandle,
        connectionHandle: ODBCHandle,
        targetName: String
    ) {
        self.api = api
        self.environmentHandle = environmentHandle
        self.connectionHandle = connectionHandle
        self.targetName = targetName
    }

    static func open(plan: Db2ConnectionPlan, password: Db2Password) throws -> Db2ODBCSession {
        let api = try Db2ODBCAPI()
        var environment: ODBCHandle = nil
        var connection: ODBCHandle = nil

        var result = api.allocHandle(ODBCConstant.handleEnvironment, nil, &environment)
        guard Self.succeeded(result) else {
            throw Db2ODBCTransportError.operationFailed(
                operation: "Allocate ODBC environment",
                sqlState: "HY000",
                nativeCode: 0,
                message: "The driver manager could not allocate an environment handle."
            )
        }
        do {
            result = api.setEnvironmentAttribute(
                environment,
                ODBCConstant.attrODBCVersion,
                Self.integerPointer(ODBCConstant.odbcVersion3),
                0
            )
            try Self.requireSuccess(
                result,
                operation: "Set ODBC version",
                api: api,
                handleType: ODBCConstant.handleEnvironment,
                handle: environment
            )

            result = api.allocHandle(ODBCConstant.handleConnection, environment, &connection)
            try Self.requireSuccess(
                result,
                operation: "Allocate Db2 connection",
                api: api,
                handleType: ODBCConstant.handleEnvironment,
                handle: environment
            )

            do {
                try Self.setConnectionAttribute(
                    api: api,
                    connection: connection,
                    attribute: ODBCConstant.attrAccessMode,
                    value: plan.policy.accessAttribute.rawValue,
                    operation: "Set Db2 access mode"
                )
                try Self.setConnectionAttribute(
                    api: api,
                    connection: connection,
                    attribute: ODBCConstant.attrLoginTimeout,
                    value: plan.policy.loginTimeoutSeconds,
                    operation: "Set sign-on timeout"
                )
                try Self.setConnectionAttribute(
                    api: api,
                    connection: connection,
                    attribute: ODBCConstant.attrConnectionTimeout,
                    value: plan.policy.connectionTimeoutSeconds,
                    operation: "Set connection timeout"
                )
                try Self.setConnectionAttribute(
                    api: api,
                    connection: connection,
                    attribute: ODBCConstant.attrAutoCommit,
                    value: plan.policy.autoCommit ? ODBCConstant.autoCommitOn : ODBCConstant.autoCommitOff,
                    operation: "Set commitment mode"
                )
                if plan.policy.serializableIsolation {
                    try Self.setConnectionAttribute(
                        api: api,
                        connection: connection,
                        attribute: ODBCConstant.attrTransactionIsolation,
                        value: ODBCConstant.transactionSerializable,
                        operation: "Set serializable isolation"
                    )
                }

                result = plan.connectionString.withUnsafeCString { pointer, _ in
                    api.driverConnect(
                        connection,
                        nil,
                        UnsafeMutablePointer(mutating: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)),
                        ODBCSmallInt(ODBCConstant.nts),
                        nil,
                        0,
                        nil,
                        ODBCConstant.driverNoPrompt
                    )
                }
                try Self.requireSuccess(
                    result,
                    operation: "Connect to Db2 for i",
                    api: api,
                    handleType: ODBCConstant.handleConnection,
                    handle: connection,
                    password: password
                )
                return Db2ODBCSession(
                    api: api,
                    environmentHandle: environment,
                    connectionHandle: connection,
                    targetName: plan.targetName
                )
            } catch {
                _ = api.freeHandle(ODBCConstant.handleConnection, connection)
                throw error
            }
        } catch {
            _ = api.freeHandle(ODBCConstant.handleEnvironment, environment)
            throw error
        }
    }

    deinit { close() }

    func close() {
        guard isOpen else { return }
        _ = api.endTransaction(ODBCConstant.handleConnection, connectionHandle, ODBCConstant.rollback)
        _ = api.disconnect(connectionHandle)
        _ = api.freeHandle(ODBCConstant.handleConnection, connectionHandle)
        _ = api.freeHandle(ODBCConstant.handleEnvironment, environmentHandle)
        isOpen = false
    }

    func commit() throws {
        try endTransaction(completion: ODBCConstant.commit, operation: "Commit Db2 transaction")
    }

    func rollback() throws {
        try endTransaction(completion: ODBCConstant.rollback, operation: "Roll back Db2 transaction")
    }

    func execute(request: SourceMemberSQLRequest) throws -> SQLResult {
        try execute(
            sql: request.sql,
            bindings: request.bindings,
            maximumRows: request.maximumRows,
            timeoutSeconds: request.timeoutSeconds
        )
    }

    func execute(
        sql: String,
        bindings: [SQLValue],
        maximumRows: Int,
        timeoutSeconds: Int
    ) throws -> SQLResult {
        guard isOpen else { throw Db2ODBCTransportError.notConnected }
        guard !sql.isEmpty,
              sql.utf8.count <= 1_048_576,
              (0...SourceMemberMetadata.maximumEditableRecords + 1).contains(maximumRows),
              (1...Db2OperationAuthorizer.maximumTimeoutSeconds).contains(timeoutSeconds) else {
            throw Db2OperationAuthorizationError.unsafeSQLRequest
        }

        var statement: ODBCHandle = nil
        let allocation = api.allocHandle(ODBCConstant.handleStatement, connectionHandle, &statement)
        try Self.requireSuccess(
            allocation,
            operation: "Allocate Db2 statement",
            api: api,
            handleType: ODBCConstant.handleConnection,
            handle: connectionHandle
        )
        defer { _ = api.freeHandle(ODBCConstant.handleStatement, statement) }

        try setStatementAttribute(
            statement: statement,
            attribute: ODBCConstant.attrQueryTimeout,
            value: timeoutSeconds,
            operation: "Set query timeout"
        )
        if maximumRows > 0 {
            try setStatementAttribute(
                statement: statement,
                attribute: ODBCConstant.attrMaximumRows,
                value: maximumRows + 1,
                operation: "Set result row bound"
            )
        }

        var sqlBytes = Array(sql.utf8)
        sqlBytes.append(0)
        let prepareResult = sqlBytes.withUnsafeMutableBufferPointer { buffer in
            api.prepare(statement, buffer.baseAddress, ODBCConstant.nts)
        }
        try Self.requireSuccess(
            prepareResult,
            operation: "Prepare Db2 statement",
            api: api,
            handleType: ODBCConstant.handleStatement,
            handle: statement
        )

        let parameters = try bindings.map(Db2ODBCBoundParameter.init(value:))
        for (offset, parameter) in parameters.enumerated() {
            let result = api.bindParameter(
                statement,
                ODBCUShort(offset + 1),
                ODBCConstant.parameterInput,
                parameter.cType,
                parameter.sqlType,
                parameter.columnSize,
                parameter.decimalDigits,
                parameter.buffer,
                parameter.bufferLength,
                parameter.indicator
            )
            try Self.requireSuccess(
                result,
                operation: "Bind Db2 parameter",
                api: api,
                handleType: ODBCConstant.handleStatement,
                handle: statement
            )
        }

        let startedAt = Date()
        let executionResult = withExtendedLifetime(parameters) {
            api.execute(statement)
        }
        try Self.requireSuccess(
            executionResult,
            operation: "Execute Db2 statement",
            api: api,
            handleType: ODBCConstant.handleStatement,
            handle: statement
        )
        var columnCount: ODBCSmallInt = 0
        try Self.requireSuccess(
            api.numberOfResultColumns(statement, &columnCount),
            operation: "Describe Db2 result",
            api: api,
            handleType: ODBCConstant.handleStatement,
            handle: statement
        )
        let descriptors = try describeColumns(statement: statement, count: Int(columnCount))
        let fetched = try fetchRows(
            statement: statement,
            columns: descriptors,
            maximumRows: maximumRows
        )
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        return SQLResult(
            columns: descriptors.map {
                SQLColumn(name: $0.name, databaseType: $0.databaseType, isNullable: $0.isNullable)
            },
            rows: fetched.rows,
            targetName: targetName,
            startedAt: startedAt,
            elapsedMilliseconds: elapsed,
            wasTruncated: fetched.wasTruncated
        )
    }

    private func describeColumns(statement: ODBCHandle, count: Int) throws -> [Db2ODBCColumn] {
        guard count > 0 else { return [] }
        return try (1...count).map { index in
            var name = [UInt8](repeating: 0, count: 1_024)
            var nameLength: ODBCSmallInt = 0
            var sqlType: ODBCSmallInt = 0
            var columnSize: ODBCULength = 0
            var decimalDigits: ODBCSmallInt = 0
            var nullable: ODBCSmallInt = 0
            let result = name.withUnsafeMutableBufferPointer { buffer in
                api.describeColumn(
                    statement,
                    ODBCUShort(index),
                    buffer.baseAddress,
                    ODBCSmallInt(buffer.count),
                    &nameLength,
                    &sqlType,
                    &columnSize,
                    &decimalDigits,
                    &nullable
                )
            }
            try Self.requireSuccess(
                result,
                operation: "Describe Db2 column",
                api: api,
                handleType: ODBCConstant.handleStatement,
                handle: statement
            )
            let validLength = min(max(0, Int(nameLength)), name.count - 1)
            guard let decodedName = String(bytes: name.prefix(validLength), encoding: .utf8) else {
                throw Db2ODBCTransportError.malformedUTF8
            }
            return Db2ODBCColumn(
                name: decodedName.isEmpty ? "COLUMN_\(index)" : decodedName,
                sqlType: sqlType,
                databaseType: Self.databaseTypeName(sqlType),
                isNullable: nullable != 0
            )
        }
    }

    private func fetchRows(
        statement: ODBCHandle,
        columns: [Db2ODBCColumn],
        maximumRows: Int
    ) throws -> (rows: [[SQLValue]], wasTruncated: Bool) {
        guard !columns.isEmpty else { return ([], false) }
        guard maximumRows > 0 else {
            throw Db2OperationAuthorizationError.unsafeSQLRequest
        }
        var rows: [[SQLValue]] = []
        while true {
            let result = api.fetch(statement)
            if result == ODBCConstant.noData { return (rows, false) }
            try Self.requireSuccess(
                result,
                operation: "Fetch Db2 row",
                api: api,
                handleType: ODBCConstant.handleStatement,
                handle: statement
            )
            if rows.count >= maximumRows { return (rows, true) }
            var row: [SQLValue] = []
            row.reserveCapacity(columns.count)
            for (offset, column) in columns.enumerated() {
                row.append(try readValue(
                    statement: statement,
                    columnNumber: ODBCUShort(offset + 1),
                    descriptor: column
                ))
            }
            rows.append(row)
        }
    }

    private func readValue(
        statement: ODBCHandle,
        columnNumber: ODBCUShort,
        descriptor: Db2ODBCColumn
    ) throws -> SQLValue {
        let fetched = try readBytes(
            statement: statement,
            columnNumber: columnNumber,
            binary: descriptor.isBinary
        )
        guard let bytes = fetched else { return .null }
        if descriptor.isBinary { return .binary(bytes) }
        guard let raw = String(data: bytes, encoding: .utf8) else {
            throw Db2ODBCTransportError.malformedUTF8
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch descriptor.sqlType {
        case ODBCConstant.sqlTinyInteger,
             ODBCConstant.sqlSmallInteger,
             ODBCConstant.sqlInteger,
             ODBCConstant.sqlBigInteger:
            return Int64(value).map(SQLValue.integer) ?? .decimal(value)
        case ODBCConstant.sqlNumeric, ODBCConstant.sqlDecimal,
             ODBCConstant.sqlFloat, ODBCConstant.sqlReal, ODBCConstant.sqlDouble:
            return .decimal(value)
        case ODBCConstant.sqlBit:
            return .boolean(value == "1" || value.caseInsensitiveCompare("true") == .orderedSame)
        case ODBCConstant.sqlTypeDate, ODBCConstant.sqlDateLegacy:
            return Self.parseDate(value).map(SQLValue.date) ?? .string(raw)
        case ODBCConstant.sqlTypeTimestamp, ODBCConstant.sqlTimestampLegacy:
            return Self.parseTimestamp(value).map(SQLValue.timestamp) ?? .string(raw)
        default:
            return .string(raw)
        }
    }

    private func readBytes(
        statement: ODBCHandle,
        columnNumber: ODBCUShort,
        binary: Bool
    ) throws -> Data? {
        let capacity = Self.transferBufferSize + (binary ? 0 : 1)
        var output = Data()
        var calls = 0
        while true {
            calls += 1
            guard calls <= (Self.maximumCellBytes / Self.transferBufferSize) + 2 else {
                throw Db2ODBCTransportError.resultValueTooLarge
            }
            var buffer = [UInt8](repeating: 0, count: capacity)
            var indicator: ODBCLength = 0
            let result = buffer.withUnsafeMutableBytes { rawBuffer in
                api.getData(
                    statement,
                    columnNumber,
                    binary ? ODBCConstant.cBinary : ODBCConstant.cCharacter,
                    rawBuffer.baseAddress,
                    ODBCLength(capacity),
                    &indicator
                )
            }
            if indicator == ODBCConstant.nullData { return nil }
            guard result == ODBCConstant.success || result == ODBCConstant.successWithInfo else {
                try Self.requireSuccess(
                    result,
                    operation: "Read Db2 value",
                    api: api,
                    handleType: ODBCConstant.handleStatement,
                    handle: statement
                )
                return output
            }

            let byteCount: Int
            if binary {
                if result == ODBCConstant.successWithInfo || indicator == ODBCConstant.noTotal {
                    byteCount = Self.transferBufferSize
                } else {
                    byteCount = min(Self.transferBufferSize, max(0, indicator))
                }
            } else {
                byteCount = buffer[..<Self.transferBufferSize].firstIndex(of: 0) ?? Self.transferBufferSize
            }
            output.append(contentsOf: buffer.prefix(byteCount))
            guard output.count <= Self.maximumCellBytes else {
                throw Db2ODBCTransportError.resultValueTooLarge
            }
            if result == ODBCConstant.success { return output }
            let diagnostic = Self.firstDiagnostic(
                api: api,
                handleType: ODBCConstant.handleStatement,
                handle: statement,
                password: nil
            )
            guard diagnostic.sqlState == "01004" else {
                throw Db2ODBCTransportError.operationFailed(
                    operation: "Read Db2 value",
                    sqlState: diagnostic.sqlState,
                    nativeCode: diagnostic.nativeCode,
                    message: diagnostic.message
                )
            }
        }
    }

    private func setStatementAttribute(
        statement: ODBCHandle,
        attribute: ODBCInteger,
        value: Int,
        operation: String
    ) throws {
        try Self.requireSuccess(
            api.setStatementAttribute(
                statement,
                attribute,
                Self.integerPointer(value),
                ODBCConstant.integerAttributeLength
            ),
            operation: operation,
            api: api,
            handleType: ODBCConstant.handleStatement,
            handle: statement
        )
    }

    private func endTransaction(completion: ODBCSmallInt, operation: String) throws {
        try Self.requireSuccess(
            api.endTransaction(ODBCConstant.handleConnection, connectionHandle, completion),
            operation: operation,
            api: api,
            handleType: ODBCConstant.handleConnection,
            handle: connectionHandle
        )
    }

    private static func setConnectionAttribute(
        api: Db2ODBCAPI,
        connection: ODBCHandle,
        attribute: ODBCInteger,
        value: Int,
        operation: String
    ) throws {
        try requireSuccess(
            api.setConnectionAttribute(
                connection,
                attribute,
                integerPointer(value),
                ODBCConstant.integerAttributeLength
            ),
            operation: operation,
            api: api,
            handleType: ODBCConstant.handleConnection,
            handle: connection
        )
    }

    private static func requireSuccess(
        _ result: ODBCReturn,
        operation: String,
        api: Db2ODBCAPI,
        handleType: ODBCSmallInt,
        handle: ODBCHandle,
        password: Db2Password? = nil
    ) throws {
        guard !succeeded(result) else { return }
        let diagnostic = firstDiagnostic(
            api: api,
            handleType: handleType,
            handle: handle,
            password: password
        )
        throw Db2ODBCTransportError.operationFailed(
            operation: operation,
            sqlState: diagnostic.sqlState,
            nativeCode: diagnostic.nativeCode,
            message: diagnostic.message
        )
    }

    private static func firstDiagnostic(
        api: Db2ODBCAPI,
        handleType: ODBCSmallInt,
        handle: ODBCHandle,
        password: Db2Password?
    ) -> (sqlState: String, nativeCode: Int32, message: String) {
        guard handle != nil else {
            return ("HY000", 0, "The driver manager did not provide diagnostic details.")
        }
        var state = [UInt8](repeating: 0, count: 6)
        var message = [UInt8](repeating: 0, count: 1_024)
        var nativeCode: ODBCInteger = 0
        var messageLength: ODBCSmallInt = 0
        let result = state.withUnsafeMutableBufferPointer { stateBuffer in
            message.withUnsafeMutableBufferPointer { messageBuffer in
                api.getDiagnosticRecord(
                    handleType,
                    handle,
                    1,
                    stateBuffer.baseAddress,
                    &nativeCode,
                    messageBuffer.baseAddress,
                    ODBCSmallInt(messageBuffer.count),
                    &messageLength
                )
            }
        }
        guard succeeded(result) else {
            return ("HY000", 0, "The driver manager did not provide diagnostic details.")
        }
        let stateText = String(bytes: state.prefix(5), encoding: .ascii) ?? "HY000"
        let validLength = min(max(0, Int(messageLength)), message.count - 1)
        let rawMessage = String(bytes: message.prefix(validLength), encoding: .utf8)
            ?? "The driver returned an unreadable diagnostic."
        let safeMessage = Db2DiagnosticSanitizer().sanitize(rawMessage, password: password)
        return (stateText, nativeCode, safeMessage)
    }

    private static func succeeded(_ result: ODBCReturn) -> Bool {
        result == ODBCConstant.success || result == ODBCConstant.successWithInfo
    }

    private static func integerPointer(_ value: Int) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: value)
    }

    private static func databaseTypeName(_ type: ODBCSmallInt) -> String {
        switch type {
        case ODBCConstant.sqlCharacter: "CHAR"
        case ODBCConstant.sqlVarchar: "VARCHAR"
        case ODBCConstant.sqlLongVarchar: "LONG VARCHAR"
        case ODBCConstant.sqlWideCharacter: "WCHAR"
        case ODBCConstant.sqlWideVarchar: "WVARCHAR"
        case ODBCConstant.sqlWideLongVarchar: "WLONGVARCHAR"
        case ODBCConstant.sqlNumeric: "NUMERIC"
        case ODBCConstant.sqlDecimal: "DECIMAL"
        case ODBCConstant.sqlTinyInteger: "TINYINT"
        case ODBCConstant.sqlSmallInteger: "SMALLINT"
        case ODBCConstant.sqlInteger: "INTEGER"
        case ODBCConstant.sqlBigInteger: "BIGINT"
        case ODBCConstant.sqlFloat: "FLOAT"
        case ODBCConstant.sqlReal: "REAL"
        case ODBCConstant.sqlDouble: "DOUBLE"
        case ODBCConstant.sqlBit: "BOOLEAN"
        case ODBCConstant.sqlBinary: "BINARY"
        case ODBCConstant.sqlVarBinary: "VARBINARY"
        case ODBCConstant.sqlLongVarBinary: "LONG VARBINARY"
        case ODBCConstant.sqlTypeDate, ODBCConstant.sqlDateLegacy: "DATE"
        case ODBCConstant.sqlTypeTime, ODBCConstant.sqlTimeLegacy: "TIME"
        case ODBCConstant.sqlTypeTimestamp, ODBCConstant.sqlTimestampLegacy: "TIMESTAMP"
        default: "ODBC \(type)"
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        dateFormatter.date(from: value)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        for formatter in timestampFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss.SSSSSS",
        "yyyy-MM-dd HH:mm:ss.SSS",
        "yyyy-MM-dd HH:mm:ss"
    ].map { format in
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
