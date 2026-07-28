import Foundation
import iTelASCore

enum CompileEvidenceOrigin: Equatable {
    case bundledReplay
    case localImport(fileName: String)

    var label: String {
        switch self {
        case .bundledReplay: "LOCAL REPLAY"
        case .localImport: "LOCAL IMPORT"
        }
    }

    var detail: String {
        switch self {
        case .bundledReplay:
            "Bundled non-host evidence for inspecting the workflow."
        case .localImport(let fileName):
            "Parsed locally from \(fileName); no host was contacted."
        }
    }
}

enum CompileRunOutcome: String {
    case passed
    case failed
    case evidenceOnly

    var label: String {
        switch self {
        case .passed: "PASSED"
        case .failed: "FAILED"
        case .evidenceOnly: "EVIDENCE"
        }
    }
}

struct CompileRecipeRecord: Equatable {
    let name: String
    let language: String
    let sourceIdentity: String
    let targetIdentity: String
    let compiler: String
    let commandPreview: String
    let eventFileIdentity: String
    let environment: IBMEnvironment
}

struct CompileRunRecord: Identifiable, Equatable {
    let id: UUID
    let sequence: Int?
    let objectName: String
    let startedAtLabel: String
    let durationLabel: String
    let jobIdentity: String
    let outcome: CompileRunOutcome
    let origin: CompileEvidenceOrigin
    let recipe: CompileRecipeRecord
    let evidence: CompileEvidenceParseResult
    let sourceText: String?
    let sourceRevision: String?
    let objectWasChanged: Bool?
    let observedHostRelease: IBMReleaseLevel?

    var analysis: CompileEvidenceAnalysis { CompileEvidenceAnalysis(result: evidence) }
    var displaySequence: String { sequence.map { "#\($0)" } ?? "IMPORT" }
    var fingerprint: String {
        let fields = [
            "itelas-compile-run-v1", id.uuidString, sequence.map(String.init) ?? "",
            objectName, startedAtLabel, durationLabel, jobIdentity, outcome.rawValue,
            origin.label, recipe.name, recipe.language, recipe.sourceIdentity,
            recipe.targetIdentity, recipe.compiler, recipe.commandPreview,
            recipe.eventFileIdentity, recipe.environment.rawValue, evidence.fingerprint,
            sourceRevision ?? "", objectWasChanged.map(String.init) ?? "",
            observedHostRelease?.value ?? ""
        ]
        return AIContentFingerprint.sha256(
            fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        )
    }
    var shortFingerprint: String { String(fingerprint.prefix(8)).uppercased() }

    func assistContextText(maximumDiagnostics: Int = 60) -> String {
        let analysis = analysis
        var lines = [
            "ITELAS COMPILE EVIDENCE v1",
            "ORIGIN: \(origin.label)",
            "OUTCOME: \(outcome.label)",
            "OBJECT: \(objectName)",
            "SOURCE: \(recipe.sourceIdentity)",
            "TARGET: \(recipe.targetIdentity)",
            "ENVIRONMENT: \(recipe.environment.label)",
            "COMPILER: \(recipe.compiler)",
            "COMMAND: \(recipe.commandPreview)",
            "EVENT FILE: \(recipe.eventFileIdentity)",
            "JOB: \(jobIdentity)",
            "EVIDENCE SHA-256: \(evidence.fingerprint)",
            "SOURCE REVISION: \(sourceRevision ?? "not attached")",
            "PRIMARY SELECTION BASIS: \(analysis.selectionBasis)",
            "DIAGNOSTICS:"
        ]
        for diagnostic in evidence.diagnostics.prefix(maximumDiagnostics) {
            let location = diagnostic.filePath.map {
                "\($0):\(diagnostic.startLine):\(diagnostic.startColumn)"
            } ?? "unlocated file-id \(diagnostic.fileIdentifier)"
            lines.append(
                "[record \(diagnostic.recordIndex) | \(diagnostic.messageID) | severity \(diagnostic.severity) | \(location)] \(diagnostic.message)"
            )
        }
        if evidence.diagnostics.count > maximumDiagnostics {
            lines.append("[\(evidence.diagnostics.count - maximumDiagnostics) additional diagnostics omitted by local cap]")
        }
        if evidence.hasExpansionMappings {
            lines.append("LIMIT: EXPANSION records are present; this milestone does not remap generated precompiler lines.")
        }
        if evidence.unresolvedFileReferenceCount > 0 {
            lines.append("LIMIT: \(evidence.unresolvedFileReferenceCount) diagnostic file reference(s) were unresolved.")
        }
        if let sourceText, let primary = analysis.primaryDiagnostic, primary.startLine > 0 {
            lines.append("SOURCE EXCERPT:")
            let sourceLines = sourceText.split(separator: "\n", omittingEmptySubsequences: false)
            let lower = max(1, primary.startLine - 4)
            let upper = min(sourceLines.count, primary.endLine + 4)
            if lower <= upper {
                for lineNumber in lower...upper {
                    lines.append(String(format: "%05d | %@", lineNumber, String(sourceLines[lineNumber - 1])))
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension CompileRunRecord {
    func lineageEvidence(
        limits: CompileLineageLimits = .standard
    ) throws -> CompileLineageRunEvidence {
        let releaseEvidence = try CompileTargetReleaseEvidence(
            commandText: recipe.commandPreview,
            observedHostRelease: observedHostRelease?.value
        )
        let releaseToken: String? = switch releaseEvidence.commandToken {
        case .current: "*CURRENT"
        case .previous: "*PRV"
        case .specific(let release): release.value
        case .notRecorded: nil
        }
        let diagnosticIdentities = try evidence.diagnostics.map { diagnostic in
            try CompileLineageDiagnosticIdentity(
                messageID: diagnostic.messageID,
                severity: diagnostic.severity,
                sourceIdentity: diagnostic.filePath ?? "FILEID \(diagnostic.fileIdentifier)",
                startLine: diagnostic.startLine,
                startColumn: diagnostic.startColumn,
                limits: limits
            )
        }
        let lineageOutcome: CompileLineageOutcome = switch outcome {
        case .passed: .passed
        case .failed: .failed
        case .evidenceOnly: .evidenceOnly
        }
        let objectResult: CompileLineageObjectResult = switch objectWasChanged {
        case true: .changed
        case false: .unchanged
        case nil: .unrecorded
        }
        let compilerIdentity = recipe.compiler
            .split(separator: "·", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? recipe.compiler

        return try CompileLineageRunEvidence(
            fingerprint: fingerprint,
            sequence: sequence,
            objectIdentity: recipe.targetIdentity,
            sourceIdentity: recipe.sourceIdentity,
            sourceRevision: sourceRevision,
            toolchainIdentity: compilerIdentity,
            commandFingerprint: AIContentFingerprint.sha256(recipe.commandPreview),
            eventEvidenceFingerprint: evidence.fingerprint,
            eventFileIdentity: recipe.eventFileIdentity,
            targetReleaseToken: releaseToken,
            observedHostRelease: observedHostRelease?.value,
            jobIdentity: jobIdentity,
            outcome: lineageOutcome,
            objectResult: objectResult,
            maximumSeverity: evidence.maximumSeverity,
            diagnostics: diagnosticIdentities,
            limits: limits
        )
    }
}

enum CompileEvidenceSamples {
    static func makeRuns() -> [CompileRunRecord] {
        [
            failedOrderEntry(),
            passedOrderEntry(),
            failedOrderService()
        ]
    }

    private static func failedOrderEntry() -> CompileRunRecord {
        let sourceIdentity = "ARLIB/QRPGLESRC(ORDERENTRY)"
        let evidence = parse(
            sourceIdentity: sourceIdentity,
            messages: [
                "ERROR      0 001 1 000042 000042 019 000042 028 RNF7030 S 30 046 Name or indicator CUSTOMERNO is not defined.",
                "ERROR      0 001 1 000043 000043 001 000043 005 RNF7503 E 20 045 Expression contains an operand that is not valid.",
                "ERROR      0 001 1 000044 000044 014 000044 025 SQL0312 E 20 083 Variable CUSTOMERNO is not defined or not usable by the SQL precompiler.",
                "ERROR      0 001 1 000049 000049 014 000049 019 RNF7031 I 00 047 The name or indicator UNUSED is not referenced.",
                "ERROR      0 001 0 000000 000000 000 000000 000 RNS9308 T 50 057 Compilation stopped. Severity 30 errors found in program."
            ]
        )
        let source = SourceWorkspaceIndexSamples.orderEntrySource
        return CompileRunRecord(
            id: UUID(uuidString: "18F16EF7-A858-4A31-A1E4-000000000184")!,
            sequence: 184,
            objectName: "ORDERENTRY",
            startedAtLabel: "09:42:18",
            durationLabel: "00:00:19",
            jobIdentity: "847216/DEVUSER/ITELASBLD",
            outcome: .failed,
            origin: .bundledReplay,
            recipe: recipe(object: "ORDERENTRY", sourceIdentity: sourceIdentity),
            evidence: evidence,
            sourceText: source,
            sourceRevision: AIContentFingerprint.sha256(source),
            objectWasChanged: false,
            observedHostRelease: try! IBMReleaseLevel("V7R6M0")
        )
    }

    private static func passedOrderEntry() -> CompileRunRecord {
        let sourceIdentity = "ARLIB/QRPGLESRC(ORDERENTRY)"
        let source = SourceWorkspaceIndexSamples.orderEntrySource.replacingOccurrences(of: "customerNo", with: "customerID")
        return CompileRunRecord(
            id: UUID(uuidString: "18F16EF7-A858-4A31-A1E4-000000000183")!,
            sequence: 183,
            objectName: "ORDERENTRY",
            startedAtLabel: "09:17:03",
            durationLabel: "00:00:14",
            jobIdentity: "847102/DEVUSER/ITELASBLD",
            outcome: .passed,
            origin: .bundledReplay,
            recipe: recipe(object: "ORDERENTRY", sourceIdentity: sourceIdentity),
            evidence: parse(sourceIdentity: sourceIdentity, messages: []),
            sourceText: source,
            sourceRevision: AIContentFingerprint.sha256(source),
            objectWasChanged: true,
            observedHostRelease: try! IBMReleaseLevel("V7R6M0")
        )
    }

    private static func failedOrderService() -> CompileRunRecord {
        let sourceIdentity = "DEVLIB/QRPGLESRC(ORDSVC)"
        let evidence = parse(
            sourceIdentity: sourceIdentity,
            messages: [
                "ERROR      0 001 1 000018 000018 001 000018 010 RNF0202 E 20 055 The control specification keyword is not recognized.",
                "ERROR      0 001 0 000000 000000 000 000000 000 RNS9308 T 50 057 Compilation stopped. Severity 20 errors found in program."
            ]
        )
        return CompileRunRecord(
            id: UUID(uuidString: "18F16EF7-A858-4A31-A1E4-000000000182")!,
            sequence: 182,
            objectName: "ORDSVC",
            startedAtLabel: "Yesterday",
            durationLabel: "00:00:31",
            jobIdentity: "846991/DEVUSER/ITELASBLD",
            outcome: .failed,
            origin: .bundledReplay,
            recipe: recipe(object: "ORDSVC", sourceIdentity: sourceIdentity),
            evidence: evidence,
            sourceText: nil,
            sourceRevision: nil,
            objectWasChanged: false,
            observedHostRelease: try! IBMReleaseLevel("V7R6M0")
        )
    }

    private static func recipe(object: String, sourceIdentity: String) -> CompileRecipeRecord {
        CompileRecipeRecord(
            name: "ILE RPG · Program",
            language: "RPGLE",
            sourceIdentity: sourceIdentity,
            targetIdentity: "ARLIB/\(object) · *PGM",
            compiler: "CRTBNDRPG · TGTRLS(*CURRENT)",
            commandPreview: "CRTBNDRPG PGM(ARLIB/\(object)) SRCFILE(ARLIB/QRPGLESRC) SRCMBR(\(object)) OPTION(*EVENTF) TGTRLS(*CURRENT)",
            eventFileIdentity: "ARLIB/EVFEVENT(\(object))",
            environment: .development
        )
    }

    private static func parse(sourceIdentity: String, messages: [String]) -> CompileEvidenceParseResult {
        let length = String(format: "%03d", sourceIdentity.count)
        let text = ([
            "TIMESTAMP  0 20260727094218",
            "PROCESSOR  0 000 1",
            "FILEID     0 001 000000 \(length) \(sourceIdentity) 20260727094155 0"
        ] + messages + ["FILEEND    0 001 000098"]).joined(separator: "\n")
        guard let parsed = try? EVFEVENTParser().parse(text: text) else {
            preconditionFailure("The bundled compile evidence fixture must remain valid.")
        }
        return parsed
    }

}

struct CompileRecipeDraft: Equatable {
    var id: UUID
    var createdAt: Date
    var name: String
    var toolchain: CompileRecipeToolchain
    var sourceLibrary: String
    var sourceFile: String
    var sourceMember: String
    var targetLibrary: String
    var targetObject: String
    var environment: IBMEnvironment
    var targetRelease: String
    var debugView: CompileRecipeDebugView
    var sqlCommitment: CompileRecipeSQLCommitment
    var rpgPreprocessor: CompileRecipeRPGPreprocessor
    var replaceExisting: Bool

    init(recipe: CompileRecipe) {
        id = recipe.id
        createdAt = recipe.createdAt
        name = recipe.name
        toolchain = recipe.toolchain
        sourceLibrary = recipe.sourceLibrary.value
        sourceFile = recipe.sourceFile.value
        sourceMember = recipe.sourceMember.value
        targetLibrary = recipe.targetLibrary.value
        targetObject = recipe.targetObject.value
        environment = recipe.environment
        targetRelease = recipe.targetRelease.commandValue
        debugView = recipe.debugView
        sqlCommitment = recipe.sqlCommitment
        rpgPreprocessor = recipe.rpgPreprocessor
        replaceExisting = recipe.replaceExisting
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String = "New RPG recipe",
        toolchain: CompileRecipeToolchain = .ileRPG,
        sourceLibrary: String = "DEVLIB",
        sourceFile: String = "QRPGLESRC",
        sourceMember: String = "PROGRAM",
        targetLibrary: String = "DEVLIB",
        targetObject: String = "PROGRAM",
        environment: IBMEnvironment = .development,
        targetRelease: String = "*CURRENT",
        debugView: CompileRecipeDebugView = .source,
        sqlCommitment: CompileRecipeSQLCommitment = .none,
        rpgPreprocessor: CompileRecipeRPGPreprocessor = .none,
        replaceExisting: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.toolchain = toolchain
        self.sourceLibrary = sourceLibrary
        self.sourceFile = sourceFile
        self.sourceMember = sourceMember
        self.targetLibrary = targetLibrary
        self.targetObject = targetObject
        self.environment = environment
        self.targetRelease = targetRelease
        self.debugView = debugView
        self.sqlCommitment = sqlCommitment
        self.rpgPreprocessor = rpgPreprocessor
        self.replaceExisting = replaceExisting
    }

    func makeRecipe(updatedAt: Date = Date()) throws -> CompileRecipe {
        try CompileRecipe(
            id: id,
            name: name,
            toolchain: toolchain,
            sourceLibrary: sourceLibrary,
            sourceFile: sourceFile,
            sourceMember: sourceMember,
            targetLibrary: targetLibrary,
            targetObject: targetObject,
            environment: environment,
            targetRelease: targetRelease,
            debugView: debugView,
            sqlCommitment: sqlCommitment,
            rpgPreprocessor: rpgPreprocessor,
            replaceExisting: replaceExisting,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

enum CompileRecipeDriftState: String, Equatable {
    case exact
    case changed
    case relative
    case unavailable

    var label: String { rawValue.uppercased() }
}

struct CompileRecipeDriftItem: Identifiable, Equatable {
    let id: String
    let label: String
    let currentValue: String
    let retainedValue: String
    let state: CompileRecipeDriftState
}

enum CompileRecipeSamples {
    private static let sampleDate = Date(timeIntervalSince1970: 1_774_800_000)

    static let library: CompileRecipeLibrary = {
        try! CompileRecipeLibrary(recipes: [
            CompileRecipe(
                id: UUID(uuidString: "A94A938A-46B8-4D4A-9000-000000000001")!,
                name: "Order Entry",
                toolchain: .sqlILERPG,
                sourceLibrary: "ARLIB",
                sourceFile: "QRPGLESRC",
                sourceMember: "ORDERENTRY",
                targetLibrary: "ARLIB",
                targetObject: "ORDERENTRY",
                environment: .development,
                targetRelease: "*CURRENT",
                debugView: .source,
                sqlCommitment: .none,
                rpgPreprocessor: .levelTwo,
                createdAt: sampleDate,
                updatedAt: sampleDate
            ),
            CompileRecipe(
                id: UUID(uuidString: "A94A938A-46B8-4D4A-9000-000000000002")!,
                name: "Order Service",
                toolchain: .ileRPG,
                sourceLibrary: "DEVLIB",
                sourceFile: "QRPGLESRC",
                sourceMember: "ORDSVC",
                targetLibrary: "ARLIB",
                targetObject: "ORDSVC",
                environment: .development,
                targetRelease: "*CURRENT",
                createdAt: sampleDate,
                updatedAt: sampleDate
            ),
            CompileRecipe(
                id: UUID(uuidString: "A94A938A-46B8-4D4A-9000-000000000003")!,
                name: "Billing Extract",
                toolchain: .sqlILERPG,
                sourceLibrary: "FINLIB",
                sourceFile: "QRPGLESRC",
                sourceMember: "BILLEXT",
                targetLibrary: "FINLIB",
                targetObject: "BILLEXT",
                environment: .qualityAssurance,
                targetRelease: "V7R5M0",
                debugView: .none,
                sqlCommitment: .cursorStability,
                rpgPreprocessor: .levelOne,
                replaceExisting: false,
                createdAt: sampleDate,
                updatedAt: sampleDate
            )
        ])
    }()
}
