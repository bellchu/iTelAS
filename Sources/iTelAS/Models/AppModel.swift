import Foundation
import Observation
import iTelASCore

enum LocalDraftSaveState {
    case clean
    case saving
    case saved
    case failed
    case remoteClean
    case remoteDraft

    var label: String {
        switch self {
        case .clean: "LOCAL · CLEAN"
        case .saving: "LOCAL · SAVING"
        case .saved: "LOCAL · AUTOSAVED"
        case .failed: "LOCAL · SAVE FAILED"
        case .remoteClean: "REMOTE · REVISION OPEN"
        case .remoteDraft: "REMOTE · SESSION DRAFT"
        }
    }
}

enum IFSRevisionState: Equatable {
    case unverified
    case match
    case conflict

    var label: String {
        switch self {
        case .unverified: "REVISION UNVERIFIED"
        case .match: "EXACT REVISION MATCH"
        case .conflict: "REMOTE REVISION CHANGED"
        }
    }
}

enum IFSWorkspacePhase: Equatable {
    case offline
    case idle
    case browsing
    case directoryReady
    case opening
    case fileReady
    case comparing
    case revisionMatch
    case revisionConflict
    case preparingWrite
    case reviewReady
    case writing
    case written
    case failed

    var label: String {
        switch self {
        case .offline: "CHANNEL OFFLINE"
        case .idle: "READY TO BROWSE"
        case .browsing: "READING DIRECTORY"
        case .directoryReady: "DIRECTORY READY"
        case .opening: "OPENING REMOTE FILE"
        case .fileReady: "REMOTE FILE OPEN"
        case .comparing: "CHECKING REVISION"
        case .revisionMatch: "REVISION MATCH"
        case .revisionConflict: "WRITE BLOCKED · CONFLICT"
        case .preparingWrite: "BUILDING WRITE PLAN"
        case .reviewReady: "REVIEW REQUIRED"
        case .writing: "VERIFYING AND WRITING"
        case .written: "WRITE VERIFIED"
        case .failed: "IFS OPERATION BLOCKED"
        }
    }

    var isBusy: Bool {
        switch self {
        case .browsing, .opening, .comparing, .preparingWrite, .writing: true
        default: false
        }
    }
}

enum SecureChannelPhase: Equatable {
    case idle
    case scanning
    case review
    case pinned
    case authenticating
    case connected
    case failed

    var label: String {
        switch self {
        case .idle: "PREFLIGHT"
        case .scanning: "DISCOVERING KEY"
        case .review: "REVIEW REQUIRED"
        case .pinned: "HOST PINNED"
        case .authenticating: "TESTING CHANNEL"
        case .connected: "SSH + SFTP READY"
        case .failed: "BLOCKED"
        }
    }

    var isBusy: Bool { self == .scanning || self == .authenticating }
}

enum Db2ConnectionPhase: Equatable {
    case idle
    case connecting
    case connected
    case failed

    var label: String {
        switch self {
        case .idle: "PREFLIGHT"
        case .connecting: "CONNECTING"
        case .connected: "CAPABILITY READY"
        case .failed: "BLOCKED"
        }
    }

    var isBusy: Bool { self == .connecting }
    var isConnected: Bool { self == .connected }
}

enum SQLExecutionPhase: Equatable {
    case idle
    case running
    case succeeded
    case failed

    var label: String {
        switch self {
        case .idle: "NO EXECUTION"
        case .running: "QUERY RUNNING"
        case .succeeded: "RESULT COMPLETE"
        case .failed: "QUERY FAILED"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var selectedTool: WorkbenchTool = .terminal
    var profiles: [SessionProfile]
    var selectedProfileID: UUID?
    var terminalSessions: [TerminalSessionState] = []
    var selectedTerminalSessionID: UUID?
    var terminalAlarmSignal: UInt64 = 0
    private var terminalPreviewScreen = TerminalScreen.welcome()
    private var terminalPreviewHistory: [TerminalSnapshot] = [
        TerminalSnapshot(source: "Local preview", screen: .welcome())
    ]

    var screen: TerminalScreen {
        get {
            guard let index = selectedTerminalSessionIndex else { return terminalPreviewScreen }
            return terminalSessions[index].screen
        }
        set {
            guard let index = selectedTerminalSessionIndex else {
                terminalPreviewScreen = newValue
                return
            }
            terminalSessions[index].screen = newValue
            terminalSessions[index].lastActivityAt = Date()
        }
    }

    var connectionState: TN5250ConnectionState {
        selectedTerminalSession?.connectionState ?? .disconnected
    }

    var protocolNotice: String? {
        selectedTerminalSession?.protocolNotice
    }

    var startupResponse: TN5250StartupResponse? {
        selectedTerminalSession?.startupResponse
    }

    var isTerminalInsertMode: Bool {
        get {
            guard let index = selectedTerminalSessionIndex else { return false }
            return terminalSessions[index].isInsertMode
        }
        set {
            guard let index = selectedTerminalSessionIndex else { return }
            terminalSessions[index].isInsertMode = newValue
            terminalSessions[index].lastActivityAt = Date()
        }
    }

    var screenHistory: [TerminalSnapshot] {
        guard let index = selectedTerminalSessionIndex else { return terminalPreviewHistory }
        return terminalSessions[index].screenHistory
    }

    var terminalFlightRecorder = TerminalFlightRecorderSamples.makeArchive()
    var selectedTerminalEvidenceFrameID: UUID? = TerminalFlightRecorderSamples.selectedFrameID
    var selectedTerminalMacroID: UUID? = TerminalFlightRecorderSamples.selectedMacroID
    var terminalRecorderArmedSessionIDs: Set<UUID> = []
    var terminalMacroRunState: TerminalMacroRunState?
    var terminalFlightRecorderUsesReplay = true
    var terminalFlightRecorderDiagnostic = "Showing deterministic redacted recorder evidence. No host, API key, or provider was contacted."
    var terminalMacroEditorDraft: TerminalMacroEditorDraft?

    var selectedTerminalEvidenceFrame: TerminalEvidenceFrame? {
        guard let selectedTerminalEvidenceFrameID else { return terminalFlightRecorder.frames.last }
        return terminalFlightRecorder.frames.first(where: { $0.id == selectedTerminalEvidenceFrameID })
            ?? terminalFlightRecorder.frames.last
    }

    var selectedTerminalMacro: ReviewedTerminalMacro? {
        guard let selectedTerminalMacroID else { return terminalFlightRecorder.macros.first }
        return terminalFlightRecorder.macros.first(where: { $0.id == selectedTerminalMacroID })
            ?? terminalFlightRecorder.macros.first
    }

    var isSelectedTerminalRecorderArmed: Bool {
        selectedTerminalSessionID.map(terminalRecorderArmedSessionIDs.contains) == true
    }

    var connectionDiagnostic: String?
    var connectionDiagnosticSucceeded = false
    var isTestingConnection = false

    var isAssistantVisible = false
    var assistantMessages: [AssistantMessage] = []
    var assistantInput = ""
    var isAssistantResponding = false
    var assistantStreamingText = ""
    var assistantResponsePhase: AIAssistantResponsePhase = .idle
    var assistantError: String?
    var includeScreenContext = false
    var aiConfiguration: AIConfiguration
    var latestAIContextReceipt: AIContextReceipt?
    var assistantRequestReceipts = AssistantRequestReceiptStore()
    var selectedAssistantRequestReceipt: AIContextReceipt?
    var isAIContextPreviewPresented = false
    var aiReviewDraft: AIReviewDraft?
    var isAIReviewDossierPresented = false
    var latestAIEditProposal: AIEditProposal?
    var latestAIProposalExplanation: String?
    var aiProposalDiagnostic: String?
    var aiProposalWasApplied = false
    var aiProposalPatchStack = AIProposalPatchStack()
    var selectedAIProposalPatchIDs: Set<UUID> = []
    var aiProposalPatchPreview: AIProposalPatchPreview?
    var aiProposalPatchLastApplication: AIProposalPatchPreview?
    var aiProposalPatchDiagnostic: String?
    var aiProposalPatchWasApplied = false
    var isAIProposalPatchStackPresented = false
    var preparedAssistantContextBundle: AIContextBundle?
    var preparedAssistantContextLabel: String?
    var continuityCasebook = ContinuityCasebookSamples.makeCasebook()
    var selectedContinuityCaseID: UUID? = ContinuityCasebookSamples.selectedCaseID
    var continuityCasebookUsesReplay = true
    var continuityCasebookDiagnostic = "Showing a deterministic local handoff replay. No provider, API key, or host was contacted."
    var pendingContinuityReferenceReview: ContinuityReferenceReviewDraft?
    var isContinuityReferenceImporterPresented = false
    var isContinuityReferenceReviewPresented = false
    var latestContinuitySnapshot: ContinuityHandoffSnapshot?
    var isContinuitySnapshotPresented = false

    var assistantStreamingByteCount: Int {
        assistantStreamingText.utf8.count
    }

    var latestAIProposalIsQueued: Bool {
        guard let proposal = latestAIEditProposal else { return false }
        return aiProposalPatchStack.patches.contains { $0.proposal == proposal }
    }

    var selectedContinuityCase: ContinuityCase? {
        guard let selectedContinuityCaseID else { return continuityCasebook.cases.first }
        return continuityCasebook.cases.first(where: { $0.id == selectedContinuityCaseID })
            ?? continuityCasebook.cases.first
    }

    var selectedContinuitySnapshots: [ContinuityHandoffSnapshot] {
        guard let selectedContinuityCase else { return [] }
        return continuityCasebook.snapshots.filter { $0.caseRecord.id == selectedContinuityCase.id }
    }

    var isConnectionStudioPresented = false
    var isCommandPalettePresented = false
    var editingProfile: SessionProfile?
    var profilePendingDeletion: SessionProfile?
    var isAISettingsPresented = false
    var isScreenHistoryPresented = false
    var isSourceWorkspaceIndexPresented = false
    var isSourceWorkspaceIncludeChainPresented = false
    var isProviderBayPresented = false
    var isSecureChannelDossierPresented = false
    var isDb2ConnectionDossierPresented = false
    var providerRuntimeSnapshot = ProviderRuntimeProbe().inspectLocalMachine()
    var secureChannelProfile = SecureChannelProfile(name: "Source workbench", host: "")
    var secureChannelHostKeys: [SSHHostKey] = []
    var selectedSecureChannelHostKeyID: String?
    var secureChannelHasPinnedKey = false
    var secureChannelPhase: SecureChannelPhase = .idle
    var secureChannelDiagnostic: String?
    var db2Profile = Db2ConnectionProfile(name: "Db2 development", host: "", username: "")
    var db2RequestedAccessMode: Db2AccessMode = .readOnly
    var db2Phase: Db2ConnectionPhase = .idle
    var db2Diagnostic: String?
    var db2Receipt: Db2ConnectionReceipt?
    var proverb = WorkbenchProverb.random()
    var transientNotice: String?
    var sourceDocument: SourceDocument
    var sourceCursorLine = 1
    var sourceCursorColumn = 1
    var sourceCursorUTF16 = 0
    var sourceSelection: AITextSelection?
    var sourceIntelligence: SourceIntelligenceSnapshot
    var sourceIntelligenceIsCurrent = true
    var sourceNavigationRequest: SourceNavigationRequest?
    var sourceCompletionSession: SourceCompletionSession?
    var sourceCompletionSelectionIndex = 0
    var sourceWorkspaceIndex = SourceWorkspaceIndexSamples.index
    var sourceWorkspaceIndexPhase: SourceWorkspaceIndexPhase = .localReplay
    var sourceWorkspaceIndexDiagnostic = "Showing deterministic local source topology. Choose a folder to build a private index."
    var sourceWorkspaceIndexBuildReport: SourceWorkspaceIndexBuildReport? = SourceWorkspaceIndexSamples.refreshBuildReport
    var sourceWorkspaceIndexDurationMilliseconds: Int? = 18
    var sourceWorkspaceDriftPhase: SourceWorkspaceDriftPhase = .localReplay
    var sourceWorkspaceDriftReceipt: SourceWorkspaceDriftReceipt? = SourceWorkspaceDriftSamples.receipt
    var sourceWorkspaceDriftDiagnostic = "Showing deterministic path-only change signals. No folder bytes were monitored or read."
    var sourceWorkspaceAutoRefreshEnabled = true
    var isSourceWorkspaceDriftReceiptPresented = false
    var sourceWorkspaceSearchQuery = "CalculateTax"
    var sourceWorkspaceSearchReport: SourceWorkspaceSearchReport? = try? SourceWorkspaceIndexSamples.index.searchReport("CalculateTax")
    var sourceWorkspaceSearchPhase: SourceWorkspaceSearchPhase = .ready
    var sourceWorkspaceSearchDurationMilliseconds: Int? = 0
    var sourceWorkspaceSearchDiagnostic = "Showing a deterministic receipt-bound local search replay."
    var selectedSourceWorkspacePath: String? = "qrpglesrc/taxservice.rpgle"
    var sourceWorkspaceIncludeChain: SourceWorkspaceIncludeChain? = try? SourceWorkspaceIndexSamples.index.includeChain(
        for: "qrpglesrc/taxservice.rpgle"
    )
    var selectedSourceWorkspaceIncludeBoundaryID: String?
    var openedSourceWorkspaceSnapshotPath: String?
    var sourceWorkspaceDependencySelection = Set(SourceWorkspaceIndexSamples.reviewedScope.selectedPaths)
    var sourceWorkspaceDependencyReview: ReviewedSourceDependencyScope? = SourceWorkspaceIndexSamples.reviewedScope
    var sourceWorkspaceRenameCurrentName = "CalculateTax"
    var sourceWorkspaceRenameProposedName = "CalculateOrderTax"
    var sourceWorkspaceRenamePlan: SourceWorkspaceRenamePlan? = try? SourceWorkspaceIndexSamples.index.makeRenamePlan(
        currentName: "CalculateTax",
        proposedName: "CalculateOrderTax"
    )
    var sourceWorkspaceRenameReview: ReviewedSourceWorkspaceRename?
    var sourceWorkspaceRenameAttested = false
    var sourceWorkspaceRenameApplyPhase: SourceWorkspaceRenameApplyPhase = .idle
    var sourceWorkspaceRenameApplyReceipt: SourceWorkspaceRenameApplyReceipt?
    var sourceWorkspaceRenameRecovery: SourceWorkspaceRenameRecoveryReport?
    var isSourceWorkspaceRenameReviewPresented = false
    var sourceWorkspaceHostIncludeLibrary = ""
    var sourceWorkspaceHostIncludeReview: ReviewedSourceWorkspaceHostInclude?
    var sourceWorkspaceHostIncludeAttested = false
    var sourceWorkspaceHostIncludePhase: SourceWorkspaceHostIncludePhase = .idle
    var sourceWorkspaceHostIncludeContent: SourceWorkspaceHostIncludeContent?
    var isSourceWorkspaceHostIncludeReviewPresented = false
    var sourceWorkspaceCompileRunID: UUID?
    var sourceWorkspaceCompileObservedRelease = ""
    var sourceWorkspaceCompileMappings: [String: String] = [:]
    var sourceWorkspaceCompileReview: ReviewedSourceWorkspaceCompileEvidence?
    var sourceWorkspaceCompileAttachment: ReviewedSourceWorkspaceCompileEvidence?
    var sourceWorkspaceCompileAttested = false
    var selectedSourceWorkspaceCompileDiagnosticID: String?
    var sourceWorkspaceCompileDiagnostic = "Choose a retained compile run to map its EVFEVENT identities into this exact index."
    var isSourceWorkspaceCompileEvidencePresented = false
    var sourceSaveState: LocalDraftSaveState = .clean
    var ifsPathText = "/home"
    var ifsDirectory: IFSPath?
    var ifsEntries: [IFSDirectoryEntry] = []
    var ifsSelectedMetadata: IFSResourceMetadata?
    var ifsRemoteBaselineText: String?
    var ifsLatestRemoteText: String?
    var ifsRevisionState: IFSRevisionState = .unverified
    var ifsPhase: IFSWorkspacePhase = .offline
    var ifsDiagnostic: String?
    var ifsWritePlan: IFSWritePlan?
    var ifsWriteReceipt: IFSWriteReceipt?
    var isIFSWriteReviewPresented = false
    var sourceMemberLibraries = SourceMemberWorkspaceSamples.libraries
    var sourceMemberFiles = SourceMemberWorkspaceSamples.sourceFiles
    var sourceMembers = SourceMemberWorkspaceSamples.members
    var selectedSourceMemberLibrary: IBMSystemObjectName? = SourceMemberWorkspaceSamples.developmentLibrary
    var selectedSourceMemberFile: SourceMemberFileSummary? = SourceMemberWorkspaceSamples.sourceFiles.first
    var selectedSourceMemberID: SourceMemberIdentity? = SourceMemberWorkspaceSamples.snapshot.metadata.identity
    var sourceMemberSnapshot: SourceMemberSnapshot?
    var sourceMemberCurrentRemoteSnapshot: SourceMemberSnapshot?
    var sourceMemberRevisionState: SourceMemberRevisionState = .unverified
    var sourceMemberPhase: SourceMemberWorkspacePhase = .localReplay
    var sourceMemberDiagnostic = "Showing a deterministic local source-member catalog. No library, file, member, source record, or authority was read from a host."
    var sourceMemberDatePolicy: SourceMemberDatePolicy = .preserve
    var sourceMemberWritePlan: SourceMemberWritePlan?
    var sourceMemberCommittedSnapshot: SourceMemberSnapshot?
    var isSourceMemberWriteReviewPresented = false
    var sqlText: String
    var sqlBaselineText: String
    var sqlSelectedServiceID: String?
    var sqlPolicy = SQLQueryPolicy.safeDefault
    var sqlCursorLine = 1
    var sqlCursorColumn = 1
    var sqlSelection: AITextSelection?
    var sqlSaveState: LocalDraftSaveState = .clean
    var sqlExecutionPhase: SQLExecutionPhase = .idle
    var sqlResult: SQLResult?
    var sqlExecutionDiagnostic: String?
    var sqlResultQueryText: String?
    var sqlResultProviderName: String?
    var sqlResultEnvironment: IBMEnvironment?
    var sqlTypedExportFormat: SQLTypedExportFormat = .csvBundle
    var sqlTypedExportPlan: SQLTypedExportPlan?
    var sqlTypedExportDiagnostic = "Run one bounded read-only query before preparing a local typed export."
    var isSQLTypedExportPresented = false
    var sqlExplainReview: SQLExplainReview?
    var sqlExplainDiagnostic = "Open Explain to build a local static review of one read-only SQL statement."
    var isSQLExplainPresented = false
    var compileRuns = CompileEvidenceSamples.makeRuns()
    var selectedCompileRunID: UUID?
    var selectedCompileDiagnosticID: String?
    var compileImportDiagnostic: String?
    var compileRecipeLibrary = CompileRecipeSamples.library
    var selectedCompileRecipeID: UUID?
    var compileRecipeDraft = CompileRecipeDraft(recipe: CompileRecipeSamples.library.recipes[0])
    var compileRecipeUsesBundledDefaults = true
    var compileRecipeDiagnostic = "Showing bundled local recipe examples. Save writes only a permission-restricted local recipe library."
    var isCompileRecipeStudioPresented = false
    var compileLineageCurrentRunID: UUID?
    var compileLineageBaselineRunID: UUID?
    var compileLineageDiagnostic = "Showing deterministic local comparison evidence. No compiler or host was contacted."
    var isCompileLineagePresented = false
    var jobIncidentSnapshot = JobIncidentSamples.makeSnapshot()
    var selectedIncidentJobID: IBMQualifiedJobName? = JobIncidentSamples.selectedJobID
    var jobIncidentPhase: JobIncidentPhase = .localReplay
    var jobIncidentDiagnostic = "Showing a deterministic local replay. Refresh is explicit and requires a non-production read-only Db2 connection."
    var spoolOutputSnapshot = SpooledOutputSamples.makeSnapshot()
    var selectedSpoolFileID: SpooledFileIdentity? = SpooledOutputSamples.selectedIdentity
    var spoolInventoryPhase: SpoolInventoryPhase = .localReplay
    var spoolInventoryDiagnostic = "Showing a deterministic local output inventory. Refresh is explicit and reads no spooled-file content."
    var spoolTextPreview: SpooledTextPreview? = SpooledOutputSamples.makePreview()
    var spoolPreviewPhase: SpoolPreviewPhase = .localReplay
    var spoolPreviewDiagnostic = "Showing deterministic text records. No host content read occurred."
    var spoolComparisonBaseline: SpooledTextPreview? = SpooledOutputSamples.makeBaseline()
    var transferValidationReport = DataTransferSamples.makeReport()
    var selectedTransferPlanID = "customer-update"
    var transferValidationPhase: TransferValidationPhase = .localReplay
    var transferSchemaPhase: TransferSchemaPhase = .localReplay
    var transferDiagnostic = "Showing a deterministic local CSV-to-table dry run. No host schema query or data write occurred."
    var transferTargetLibraryText = "ARLIB"
    var transferTargetTableText = "CUSTOMER"
    var transferSchemaIsCurrent = true
    var systemHealthSnapshot = SystemHealthSamples.makeSnapshot()
    var systemHealthPhase: SystemHealthPhase = .localReplay
    var systemHealthDiagnostic = "Showing deterministic local health evidence. No host query, certificate access, or system change occurred."
    var objectImpactSnapshot = ObjectImpactSamples.makeSnapshot()
    var objectImpactPhase: ObjectImpactPhase = .localReplay
    var objectImpactDiagnostic = "Showing deterministic direct dependency evidence. No host query or system change occurred."
    var objectImpactLibraryText = "ARLIB"
    var objectImpactNameText = "ORDERSRV"
    var objectImpactType: IBMObjectType = .serviceProgram
    var authorityInsightSnapshot = AuthorityInsightSamples.makeSnapshot()
    var authorityInsightPhase: AuthorityInsightPhase = .localReplay
    var authorityInsightDiagnostic = "Showing deterministic authority evidence. No host query, grant, revoke, profile change, authorization-list change, or collection change occurred."
    var authoritySubjectText = "RPGDEV1"
    var authorityLibraryText = "ARLIB"
    var authorityObjectText = "PAYROLL"
    var authorityObjectType: IBMObjectType = .file
    var authoritySimulationRemovedPathIDs: Set<String> = []
    var runbookLibrary = RunbookSamples.makeLibrary()
    var selectedRunbookID = RunbookSamples.selectedID
    var selectedRunbookStepNumber = RunbookSamples.selectedStepNumber
    var runbookResolution: ResolvedRunbook? = RunbookSamples.makeResolution()
    var runbookParameterValues = RunbookSamples.defaultValues(for: RunbookSamples.makeBlueprint())
    var runbookTargetName = "DEV ORION"
    var runbookEnvironment: IBMEnvironment = .development
    var runbookOperatorReason = ""
    var runbookApprovals = RunbookSamples.makeResolution().approvals
    var runbookPhase: RunbookPhase = .localReplay
    var runbookDiagnostic = "Showing a deterministic local blueprint resolution. No command, query, approval, schedule, or host action occurred."
    @ObservationIgnored private var sessionTransports: [UUID: TerminalSessionTransportRuntime] = [:]
    @ObservationIgnored private var testClient: TN5250Client?
    @ObservationIgnored private var activeTestGeneration: UUID?
    @ObservationIgnored private var sourceSaveTask: Task<Void, Never>?
    @ObservationIgnored private var sourceIntelligenceTask: Task<Void, Never>?
    @ObservationIgnored private var sourceWorkspaceIndexTask: Task<Void, Never>?
    @ObservationIgnored private var activeSourceWorkspaceIndexGeneration: UUID?
    @ObservationIgnored private var sourceWorkspaceSearchTask: Task<Void, Never>?
    @ObservationIgnored private var activeSourceWorkspaceSearchGeneration: UUID?
    @ObservationIgnored private var sourceWorkspaceRootURL: URL?
    @ObservationIgnored private var sourceWorkspaceDriftRootURL: URL?
    @ObservationIgnored private var sourceWorkspaceDriftMonitor: SourceWorkspaceDriftMonitor?
    @ObservationIgnored private var sourceWorkspaceDriftObservations: [SourceWorkspaceDriftObservation] = []
    @ObservationIgnored private var sourceWorkspaceDriftAutoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var activeSourceWorkspaceDriftAutoRefreshGeneration: UUID?
    @ObservationIgnored private var activeSourceWorkspaceDriftGeneration: UUID?
    @ObservationIgnored private var sourceWorkspaceDriftSecurityScopeURL: URL?
    @ObservationIgnored private var sourceWorkspaceRenameTask: Task<Void, Never>?
    @ObservationIgnored private var sourceWorkspaceHostIncludeTask: Task<Void, Never>?
    @ObservationIgnored private var activeSourceWorkspaceHostIncludeGeneration: UUID?
    @ObservationIgnored private var ifsOperationTask: Task<Void, Never>?
    @ObservationIgnored private var sourceMemberTask: Task<Void, Never>?
    @ObservationIgnored private var activeSourceMemberGeneration: UUID?
    @ObservationIgnored private var sqlSaveTask: Task<Void, Never>?
    @ObservationIgnored private var sqlExecutionTask: Task<Void, Never>?
    @ObservationIgnored private var jobIncidentTask: Task<Void, Never>?
    @ObservationIgnored private var activeJobIncidentGeneration: UUID?
    @ObservationIgnored private var spoolInventoryTask: Task<Void, Never>?
    @ObservationIgnored private var activeSpoolInventoryGeneration: UUID?
    @ObservationIgnored private var spoolPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var activeSpoolPreviewGeneration: UUID?
    @ObservationIgnored private var transferSchemaTask: Task<Void, Never>?
    @ObservationIgnored private var activeTransferSchemaGeneration: UUID?
    @ObservationIgnored private var systemHealthTask: Task<Void, Never>?
    @ObservationIgnored private var activeSystemHealthGeneration: UUID?
    @ObservationIgnored private var objectImpactTask: Task<Void, Never>?
    @ObservationIgnored private var activeObjectImpactGeneration: UUID?
    @ObservationIgnored private var authorityInsightTask: Task<Void, Never>?
    @ObservationIgnored private var activeAuthorityInsightGeneration: UUID?
    @ObservationIgnored private var assistantTask: Task<Void, Never>?
    @ObservationIgnored private var activeAssistantGeneration: UUID?
    @ObservationIgnored private var activeAssistantRequestKind: AssistantRequestKind?
    @ObservationIgnored private var db2Transport: Db2ODBCTransport?
    @ObservationIgnored private let aiService = AIService()
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored private let redactor = AIContextRedactor()
    @ObservationIgnored private let proposalParser = AIProposalParser()
    @ObservationIgnored private let sourceIntelligenceAnalyzer = SourceIntelligenceAnalyzer()
    @ObservationIgnored private let sourceCompletionEngine = SourceCompletionEngine()
    @ObservationIgnored private let commandClassifier = IBMCommandSafetyClassifier()
    @ObservationIgnored private let terminalExport = TerminalExportService()
    @ObservationIgnored private let continuityCasebookStore: ContinuityCasebookStore
    @ObservationIgnored private let terminalFlightRecorderStore: TerminalFlightRecorderStore
    @ObservationIgnored private let compileRecipeStore: CompileRecipeStore
    @ObservationIgnored private let secureChannelService = SecureChannelService()
    @ObservationIgnored private let ifsWorkspaceService = IFSWorkspaceService()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let sourceScratchStore: LocalTextDocumentStore
    @ObservationIgnored private let sqlScratchStore: LocalTextDocumentStore
    @ObservationIgnored private var activeAssistantProvenance: AssistantResponseProvenance?
    @ObservationIgnored private var activeAssistantRequestReceipt: AIContextReceipt?

    private enum DefaultsKey {
        static let profiles = "session-profiles-v1"
        static let aiConfiguration = "ai-configuration-v1"
        static let db2Profile = "db2-connection-profile-v1"
    }

    private enum AssistantRequestKind: Equatable {
        case chat
        case review
    }

    private struct SourceMemberConnectionContext {
        let provider: Db2SourceMemberProvider
        let receipt: Db2ConnectionReceipt
        let transport: Db2ODBCTransport
    }

    init(
        continuityCasebookStore: ContinuityCasebookStore = ContinuityCasebookStore(),
        terminalFlightRecorderStore: TerminalFlightRecorderStore = TerminalFlightRecorderStore(),
        compileRecipeStore: CompileRecipeStore = CompileRecipeStore()
    ) {
        self.continuityCasebookStore = continuityCasebookStore
        self.terminalFlightRecorderStore = terminalFlightRecorderStore
        self.compileRecipeStore = compileRecipeStore
        let sourceScratchStore = LocalTextDocumentStore(fileName: "CUSTOMER.rpgle")
        self.sourceScratchStore = sourceScratchStore
        let storedSourceText = (try? sourceScratchStore.read()) ?? nil
        let sourceText = storedSourceText ?? Self.defaultSourceScratch
        let initialSourceDocument = SourceDocument(
            identity: .localScratch(name: "CUSTOMER.rpgle"),
            format: .rpgle,
            sourceDatePolicy: .preserve,
            originalText: sourceText
        )
        sourceDocument = initialSourceDocument
        sourceIntelligence = SourceIntelligenceAnalyzer().analyze(initialSourceDocument)
        sourceSaveState = storedSourceText == nil ? .clean : .saved

        let sqlScratchStore = LocalTextDocumentStore(fileName: "active-query.sql")
        self.sqlScratchStore = sqlScratchStore
        let defaultSQLQuery = IBMIServicesCatalog.queries[0]
        let storedSQLText = (try? sqlScratchStore.read()) ?? nil
        sqlText = storedSQLText ?? defaultSQLQuery.sql
        sqlBaselineText = storedSQLText ?? defaultSQLQuery.sql
        sqlSelectedServiceID = storedSQLText == nil ? defaultSQLQuery.id : nil
        sqlSaveState = storedSQLText == nil ? .clean : .saved
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.profiles),
           let decoded = try? JSONDecoder().decode([SessionProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = []
        }
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.aiConfiguration),
           let decoded = try? JSONDecoder().decode(AIConfiguration.self, from: data) {
            aiConfiguration = decoded
        } else {
            aiConfiguration = AIConfiguration()
        }
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.db2Profile),
           let decoded = try? JSONDecoder().decode(Db2ConnectionProfile.self, from: data) {
            db2Profile = decoded
        }
        if let storedCasebook = try? continuityCasebookStore.read(),
           !storedCasebook.cases.isEmpty {
            continuityCasebook = storedCasebook
            selectedContinuityCaseID = storedCasebook.cases.first?.id
            continuityCasebookUsesReplay = false
            continuityCasebookDiagnostic = "Loaded the permission-restricted local Continuity Casebook."
        }
        do {
            if let storedRecorder = try terminalFlightRecorderStore.read() {
                var prunedRecorder = storedRecorder
                prunedRecorder.prune()
                terminalFlightRecorder = prunedRecorder
                selectedTerminalEvidenceFrameID = prunedRecorder.frames.last?.id
                selectedTerminalMacroID = prunedRecorder.macros.first?.id
                terminalFlightRecorderUsesReplay = false
                terminalFlightRecorderDiagnostic = "Loaded the permission-restricted local terminal evidence archive. Recording remains off until armed for a session."
            }
        } catch {
            terminalFlightRecorderDiagnostic = "Local recorder archive was refused: \(error.localizedDescription)"
        }
        do {
            if let storedRecipes = try compileRecipeStore.read(), !storedRecipes.recipes.isEmpty {
                compileRecipeLibrary = storedRecipes
                compileRecipeUsesBundledDefaults = false
                compileRecipeDiagnostic = "Loaded the permission-restricted local compile recipe library."
            }
        } catch {
            compileRecipeDiagnostic = "Local compile recipe library was refused: \(error.localizedDescription)"
        }
        selectedCompileRecipeID = compileRecipeLibrary.recipes.first?.id
        if let recipe = compileRecipeLibrary.recipes.first {
            compileRecipeDraft = CompileRecipeDraft(recipe: recipe)
        }
        selectedCompileRunID = compileRuns.first?.id
        selectedCompileDiagnosticID = compileRuns.first?.analysis.primaryDiagnostic?.id
        compileLineageCurrentRunID = selectedCompileRunID
        if let current = compileRuns.first {
            compileLineageBaselineRunID = compileRuns.dropFirst().first(where: {
                $0.recipe.targetIdentity == current.recipe.targetIdentity
            })?.id
        }
        sourceWorkspaceCompileRunID = selectedCompileRunID
        sourceWorkspaceCompileObservedRelease = compileRuns.first?.observedHostRelease?.value ?? ""
        rebuildSourceWorkspaceCompileReview(resetMappings: true)
    }

    private var selectedTerminalSessionIndex: Int? {
        guard let selectedTerminalSessionID else { return nil }
        return terminalSessions.firstIndex(where: { $0.id == selectedTerminalSessionID })
    }

    var selectedTerminalSession: TerminalSessionState? {
        guard let index = selectedTerminalSessionIndex else { return nil }
        return terminalSessions[index]
    }

    var selectedProfile: SessionProfile? {
        let profileID = selectedTerminalSession?.profileID ?? selectedProfileID
        return profiles.first(where: { $0.id == profileID })
    }

    func profile(for session: TerminalSessionState) -> SessionProfile? {
        profiles.first(where: { $0.id == session.profileID })
    }

    var activeTerminalFunctionKeyBindings: [TerminalFunctionKeyBinding] {
        let bindings = selectedProfile?.functionKeyBindings ?? TerminalFunctionKeyBinding.standard
        guard TerminalFunctionKeyBinding.validationErrors(for: bindings).isEmpty else {
            return TerminalFunctionKeyBinding.standard
        }
        return bindings.sorted { $0.slot < $1.slot }
    }

    func terminalFunctionKeyBinding(for slot: Int) -> TerminalFunctionKeyBinding? {
        activeTerminalFunctionKeyBindings.first { $0.slot == slot }
    }

    func sessions(for profile: SessionProfile) -> [TerminalSessionState] {
        terminalSessions.filter { $0.profileID == profile.id }
    }

    var apiKeyExists: Bool {
        ((try? keychain.readAPIKey()) ?? nil)?.isEmpty == false
    }

    var selectedCompileRun: CompileRunRecord? {
        compileRuns.first(where: { $0.id == selectedCompileRunID })
    }

    var selectedCompileDiagnostic: CompileDiagnostic? {
        guard let selectedCompileDiagnosticID else { return nil }
        return selectedCompileRun?.evidence.diagnostics.first(where: { $0.id == selectedCompileDiagnosticID })
    }

    var compileLineageCurrentRun: CompileRunRecord? {
        guard let compileLineageCurrentRunID else { return nil }
        return compileRuns.first(where: { $0.id == compileLineageCurrentRunID })
    }

    var compileLineageBaselineRun: CompileRunRecord? {
        guard let compileLineageBaselineRunID else { return nil }
        return compileRuns.first(where: { $0.id == compileLineageBaselineRunID })
    }

    var compileLineageScopedRuns: [CompileRunRecord] {
        guard let current = compileLineageCurrentRun else { return [] }
        return compileRuns.filter {
            $0.recipe.targetIdentity == current.recipe.targetIdentity
        }
    }

    var compileLineageBaselineCandidates: [CompileRunRecord] {
        guard let current = compileLineageCurrentRun else { return [] }
        return compileLineageScopedRuns.filter { $0.id != current.id }
    }

    var compileLineageComparison: CompileLineageComparison? {
        try? makeCompileLineageComparison()
    }

    var compileLineageValidationMessage: String? {
        do {
            _ = try makeCompileLineageComparison()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func makeCompileLineageComparison() throws -> CompileLineageComparison {
        guard let current = compileLineageCurrentRun else {
            throw CompileLineageError.missingSelectedRun
        }
        guard compileLineageScopedRuns.count >= 2 else {
            throw CompileLineageError.insufficientRuns(minimum: 2)
        }
        guard let baseline = compileLineageBaselineRun,
              baseline.id != current.id,
              baseline.recipe.targetIdentity == current.recipe.targetIdentity else {
            throw CompileLineageError.missingSelectedRun
        }
        let evidence = try compileLineageScopedRuns.map { try $0.lineageEvidence() }
        return try CompileLineageComparison(
            runs: evidence,
            baselineFingerprint: baseline.fingerprint,
            currentFingerprint: current.fingerprint
        )
    }

    var selectedCompileRecipe: CompileRecipe? {
        guard let selectedCompileRecipeID else { return nil }
        return compileRecipeLibrary.recipes.first(where: { $0.id == selectedCompileRecipeID })
    }

    var compileRecipePreview: CompileRecipe? {
        try? compileRecipeDraft.makeRecipe()
    }

    var compileRecipeValidationMessage: String? {
        do {
            _ = try compileRecipeDraft.makeRecipe()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var compileRecipeDraftIsSaved: Bool {
        guard !compileRecipeUsesBundledDefaults else { return false }
        guard let selectedCompileRecipe, let preview = compileRecipePreview else { return false }
        return selectedCompileRecipe.fingerprint == preview.fingerprint
    }

    var compileRecipeStatusLabel: String {
        if compileRecipePreview == nil { return "INVALID" }
        if compileRecipeUsesBundledDefaults, selectedCompileRecipeID != nil { return "EXAMPLE" }
        return compileRecipeDraftIsSaved ? "SAVED" : "UNSAVED"
    }

    var compileRecipeDriftItems: [CompileRecipeDriftItem] {
        guard let recipe = compileRecipePreview, let run = selectedCompileRun else {
            return [CompileRecipeDriftItem(
                id: "run",
                label: "Retained run",
                currentValue: "Current recipe",
                retainedValue: "No retained run selected",
                state: .unavailable
            )]
        }

        func normalized(_ value: String) -> String {
            value.uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        func item(
            _ id: String,
            _ label: String,
            _ current: String,
            _ retained: String,
            state: CompileRecipeDriftState? = nil
        ) -> CompileRecipeDriftItem {
            CompileRecipeDriftItem(
                id: id,
                label: label,
                currentValue: current,
                retainedValue: retained,
                state: state ?? (normalized(current) == normalized(retained) ? .exact : .changed)
            )
        }

        let retainedCommand = run.recipe.commandPreview
        let toolchainState: CompileRecipeDriftState = normalized(retainedCommand).contains(recipe.toolchain.commandName)
            ? .exact
            : .changed
        let eventState: CompileRecipeDriftState = normalized(retainedCommand).contains("OPTION(*EVENTF)")
            ? .exact
            : .unavailable
        let releaseEvidence = try? CompileTargetReleaseEvidence(commandText: retainedCommand)
        let retainedRelease = releaseEvidence?.commandToken.label ?? "Not recorded"
        let releaseState: CompileRecipeDriftState = switch recipe.targetRelease {
        case .current, .previous: .relative
        case .specific:
            normalized(retainedRelease).contains("TGTRLS(\(recipe.targetRelease.commandValue))") ? .exact : .changed
        }

        return [
            item("source", "Source", recipe.sourceIdentity, run.recipe.sourceIdentity),
            item("target", "Target", recipe.targetIdentity, run.recipe.targetIdentity),
            item("toolchain", "Toolchain", recipe.toolchain.commandName, run.recipe.compiler, state: toolchainState),
            item("event", "Event evidence", "OPTION(*EVENTF)", eventState == .exact ? "Recorded" : "Not recorded", state: eventState),
            item("release", "Target release", "TGTRLS(\(recipe.targetRelease.commandValue))", retainedRelease, state: releaseState),
            item(
                "command",
                "Whole command",
                recipe.commandFingerprint.uppercased(),
                AIContentFingerprint.sha256(retainedCommand).uppercased(),
                state: normalized(recipe.commandPreview) == normalized(retainedCommand) ? .exact : .changed
            )
        ]
    }

    var selectedIncidentJob: JobInventoryRecord? {
        guard let selectedIncidentJobID else { return nil }
        return jobIncidentSnapshot.job(named: selectedIncidentJobID)
    }

    var jobIncidentAnalysis: JobIncidentAnalysis? {
        selectedIncidentJob.map {
            JobIncidentAnalysis(snapshot: jobIncidentSnapshot, selectedJob: $0)
        }
    }

    var selectedSpooledFile: SpooledFileRecord? {
        guard let selectedSpoolFileID else { return nil }
        return spoolOutputSnapshot.file(selectedSpoolFileID)
    }

    var selectedSpoolOutputQueue: OutputQueueRecord? {
        selectedSpooledFile.flatMap(spoolOutputSnapshot.queue(for:))
    }

    var spoolTextComparison: SpooledTextComparison? {
        guard let baseline = spoolComparisonBaseline,
              let current = spoolTextPreview,
              current.identity == selectedSpoolFileID else { return nil }
        return try? SpooledTextComparison(baseline: baseline, current: current)
    }

    var selectedRunbookItem: RunbookCatalogItem? {
        runbookLibrary.first(where: { $0.id == selectedRunbookID })
    }

    var selectedRunbookBlueprint: RunbookBlueprint? {
        selectedRunbookItem?.blueprint
    }

    var selectedResolvedRunbookStep: ResolvedRunbookStep? {
        runbookResolution?.steps.first(where: { $0.number == selectedRunbookStepNumber })
    }

    func rotateProverb() {
        proverb = .random(excluding: proverb.id)
    }

    func presentProviderBay() {
        refreshProviderRuntimeProbe()
        isProviderBayPresented = true
    }

    func refreshProviderRuntimeProbe() {
        providerRuntimeSnapshot = ProviderRuntimeProbe().inspectLocalMachine()
    }

    func presentDb2ConnectionDossier() {
        refreshProviderRuntimeProbe()
        if db2Profile.normalizedHost.isEmpty, let selectedProfile {
            db2Profile.host = selectedProfile.host
            db2Profile.name = "\(selectedProfile.name) Db2"
            db2Profile.environment = selectedProfile.environment
        }
        isDb2ConnectionDossierPresented = true
    }

    func transitionFromProviderBayToDb2ConnectionDossier() {
        isProviderBayPresented = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            self?.presentDb2ConnectionDossier()
        }
    }

    func updateDb2Profile(_ profile: Db2ConnectionProfile) {
        let targetChanged = profile.normalizedHost != db2Profile.normalizedHost
            || profile.normalizedUsername != db2Profile.normalizedUsername
            || profile.environment != db2Profile.environment
        let connectionChanged = targetChanged
            || profile.loginTimeoutSeconds != db2Profile.loginTimeoutSeconds
            || profile.connectionTimeoutSeconds != db2Profile.connectionTimeoutSeconds
        let previousProfileID = db2Profile.id
        db2Profile = profile
        persistDb2Profile()
        guard connectionChanged else { return }

        sqlExecutionTask?.cancel()
        sqlExecutionTask = nil
        invalidateJobIncidentCollection(
            reason: "Connection identity changed. The prior incident snapshot was retained but is not current for the new target."
        )
        invalidateSpoolOutputCollection(
            reason: "Connection identity changed. Prior output evidence remains available for local review but is not current for the new target."
        )
        invalidateTransferSchema(
            reason: "Connection identity changed. Prior transfer profiling remains local, but its target schema is not current for the new identity."
        )
        invalidateSystemHealthCollection(
            reason: "Connection identity changed. Prior health evidence was retained for local review and is not current for the new target."
        )
        invalidateObjectImpactCollection(
            reason: "Connection identity changed. Prior dependency evidence remains local and is not current for the new target."
        )
        invalidateAuthorityInsightCollection(
            reason: "Connection identity changed. Prior authority evidence remains local and is not current for the new target."
        )
        invalidateSourceMemberConnection(
            reason: "Connection identity changed. Any open member snapshot remains local and must be refreshed before review or write."
        )
        if let transport = db2Transport {
            Task { await transport.disconnect() }
        }
        db2Transport = nil
        db2Receipt = nil
        db2Phase = .idle
        db2Diagnostic = "Connection identity changed. Review the target before connecting again."
        sqlResult = nil
        sqlResultQueryText = nil
        sqlResultProviderName = nil
        sqlResultEnvironment = nil
        sqlTypedExportPlan = nil
        isSQLTypedExportPresented = false
        sqlExecutionPhase = .idle
        sqlExecutionDiagnostic = nil
        if targetChanged {
            try? keychain.deleteDb2Password(profileID: previousProfileID)
        }
    }

    var db2PasswordExists: Bool {
        ((try? keychain.readDb2Password(profileID: db2Profile.id)) ?? nil)?.isEmpty == false
    }

    func selectDb2AccessMode(_ accessMode: Db2AccessMode) {
        guard !db2Phase.isBusy, !db2Phase.isConnected else {
            showNotice("Disconnect Db2 before changing the capability envelope.")
            return
        }
        db2RequestedAccessMode = accessMode
        db2Diagnostic = switch accessMode {
        case .readOnly:
            "Read-only SQL and IBM i Services are available after sign-on."
        case .sourceMemberRead:
            "Source-member reads use a generated QTEMP alias lifecycle; general SQL execution is disabled."
        case .reviewedSourceMemberWrite:
            "Only an exact reviewed source-member transaction can write; general SQL execution remains disabled."
        }
    }

    func connectDb2(password enteredPassword: String, rememberPassword: Bool) {
        guard !db2Phase.isBusy else { return }
        refreshProviderRuntimeProbe()
        guard providerRuntimeSnapshot.secureDb2PrerequisitesReady else {
            db2Phase = .failed
            db2Diagnostic = "Install and verify native unixODBC, the IBM i Access ODBC driver, and OpenSSL before connecting. No host was contacted."
            return
        }
        guard db2Profile.validationErrors.isEmpty else {
            db2Phase = .failed
            db2Diagnostic = db2Profile.validationErrors.joined(separator: " ")
            return
        }
        let requestedAccessMode = db2RequestedAccessMode
        guard requestedAccessMode == .readOnly || db2Profile.environment != .production else {
            db2Phase = .failed
            db2Diagnostic = "Source-member alias and write capabilities are blocked for PROD by this development policy. Choose Read only or a non-production target."
            return
        }

        let passwordText: String
        if !enteredPassword.isEmpty {
            passwordText = enteredPassword
        } else if let stored = try? keychain.readDb2Password(profileID: db2Profile.id),
                  !stored.isEmpty {
            passwordText = stored
        } else {
            db2Phase = .failed
            db2Diagnostic = "Enter the IBM i password or store one explicitly in macOS Keychain."
            return
        }

        let password: Db2Password
        do {
            password = try Db2Password(passwordText)
        } catch {
            db2Phase = .failed
            db2Diagnostic = error.localizedDescription
            return
        }

        let profile = db2Profile
        let runtime = providerRuntimeSnapshot
        let transport = Db2ODBCTransport(
            profile: profile,
            accessMode: requestedAccessMode,
            runtimeSnapshot: runtime
        )
        let passwordToPersist = rememberPassword ? passwordText : nil
        db2Phase = .connecting
        db2Diagnostic = "Opening an encrypted native ODBC session for \(requestedAccessMode.label.lowercased())."

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let receipt = try await transport.connect(password: password)
                guard db2Profile == profile, db2RequestedAccessMode == requestedAccessMode else {
                    await transport.disconnect()
                    return
                }
                if let passwordToPersist {
                    try keychain.writeDb2Password(passwordToPersist, profileID: profile.id)
                } else {
                    try? keychain.deleteDb2Password(profileID: profile.id)
                }
                db2Transport = transport
                db2Receipt = receipt
                db2Phase = .connected
                db2Diagnostic = "TLS and the \(receipt.accessMode.label.lowercased()) capability are active for \(receipt.targetName)."
                if receipt.accessMode == .sourceMemberRead || receipt.accessMode == .reviewedSourceMemberWrite {
                    sourceMemberPhase = .offline
                    sourceMemberDiagnostic = "Member capability connected. Refresh the catalog explicitly; no source-member query has run."
                }
                showNotice("Db2 \(receipt.accessMode.label.lowercased()) provider connected. No query was executed.")
            } catch {
                await transport.disconnect()
                guard db2Profile == profile, db2RequestedAccessMode == requestedAccessMode else { return }
                db2Transport = nil
                db2Receipt = nil
                db2Phase = .failed
                db2Diagnostic = error.localizedDescription
            }
        }
    }

    func disconnectDb2() {
        if case .sourceMember = sourceWorkspaceHostIncludeReview?.target {
            invalidateSourceWorkspaceHostIncludeRead(
                reason: "Db2 disconnected before the exact source-member include read completed."
            )
        }
        sqlExecutionTask?.cancel()
        sqlExecutionTask = nil
        invalidateJobIncidentCollection(
            reason: "Db2 disconnected. The prior incident snapshot remains available for local review only."
        )
        invalidateSpoolOutputCollection(
            reason: "Db2 disconnected. Prior output inventory and text remain available for local review only."
        )
        invalidateTransferSchema(
            reason: "Db2 disconnected. Prior transfer profiling remains local; refresh the target schema after reconnecting."
        )
        invalidateSystemHealthCollection(
            reason: "Db2 disconnected. Prior health evidence remains available for local review only."
        )
        invalidateObjectImpactCollection(
            reason: "Db2 disconnected. Prior dependency evidence remains available for local review only."
        )
        invalidateAuthorityInsightCollection(
            reason: "Db2 disconnected. Prior authority evidence remains available for local review only."
        )
        invalidateSourceMemberConnection(
            reason: "Db2 disconnected. Any open member snapshot and draft remain local; compare and write are blocked."
        )
        if let transport = db2Transport {
            Task { await transport.disconnect() }
        }
        db2Transport = nil
        db2Receipt = nil
        db2Phase = .idle
        db2Diagnostic = "Db2 session closed. Local drafts and prior result rows remain available."
        showNotice("Db2 provider disconnected.")
    }

    func removeStoredDb2Password() {
        do {
            try keychain.deleteDb2Password(profileID: db2Profile.id)
            showNotice("Removed the Db2 password from macOS Keychain.")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func presentSecureChannelDossier() {
        refreshProviderRuntimeProbe()
        if secureChannelProfile.host.isEmpty, let selectedProfile {
            secureChannelProfile = SecureChannelProfile(
                name: "\(selectedProfile.name) source access",
                host: selectedProfile.host,
                username: "",
                environment: selectedProfile.environment
            )
        }
        isSecureChannelDossierPresented = true
    }

    func transitionFromProviderBayToSecureChannelDossier() {
        isProviderBayPresented = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            self?.presentSecureChannelDossier()
        }
    }

    func updateSecureChannelProfile(_ profile: SecureChannelProfile) {
        let targetChanged = profile.normalizedHost != secureChannelProfile.normalizedHost
            || profile.port != secureChannelProfile.port
            || profile.normalizedUsername != secureChannelProfile.normalizedUsername
            || profile.authenticationMethod != secureChannelProfile.authenticationMethod
            || profile.privateKeyPath != secureChannelProfile.privateKeyPath
        secureChannelProfile = profile
        if targetChanged {
            if case .ifs = sourceWorkspaceHostIncludeReview?.target {
                invalidateSourceWorkspaceHostIncludeRead(
                    reason: "The secure-channel target changed before the exact IFS include read completed."
                )
            }
            secureChannelHostKeys = []
            selectedSecureChannelHostKeyID = nil
            secureChannelHasPinnedKey = false
            secureChannelPhase = .idle
            secureChannelDiagnostic = nil
            let isOpenIFS: Bool
            if case .ifs = sourceDocument.identity { isOpenIFS = true } else { isOpenIFS = false }
            resetIFSWorkspace(restoreLocalDocument: isOpenIFS)
        }
    }

    var selectedSecureChannelHostKey: SSHHostKey? {
        guard let selectedSecureChannelHostKeyID else { return nil }
        return secureChannelHostKeys.first(where: { $0.id == selectedSecureChannelHostKeyID })
    }

    func discoverSecureChannelHostKeys() {
        guard !secureChannelPhase.isBusy else { return }
        guard providerRuntimeSnapshot.sshReady else {
            secureChannelPhase = .failed
            secureChannelDiagnostic = "System OpenSSH is unavailable on this Mac."
            return
        }
        guard secureChannelProfile.validationErrors.isEmpty else {
            secureChannelPhase = .failed
            secureChannelDiagnostic = secureChannelProfile.validationErrors.joined(separator: " ")
            return
        }

        let profile = secureChannelProfile
        secureChannelPhase = .scanning
        secureChannelDiagnostic = "Collecting public host keys only. Authentication has not started."
        secureChannelHostKeys = []
        selectedSecureChannelHostKeyID = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let keys = try await secureChannelService.scanHostKey(profile: profile)
                guard secureChannelProfile.normalizedHost == profile.normalizedHost,
                      secureChannelProfile.port == profile.port else { return }
                secureChannelHostKeys = keys
                selectedSecureChannelHostKeyID = keys.first?.id
                let pinStates = try keys.map { key in
                    (key, try secureChannelService.pinState(for: key))
                }
                if pinStates.contains(where: { $0.1 == .changed }) {
                    secureChannelHasPinnedKey = false
                    secureChannelPhase = .failed
                    secureChannelDiagnostic = SecureChannelError.hostKeyChanged.localizedDescription
                } else if let pinned = pinStates.first(where: { $0.1 == .pinned }) {
                    selectedSecureChannelHostKeyID = pinned.0.id
                    secureChannelHasPinnedKey = true
                    secureChannelPhase = .pinned
                    secureChannelDiagnostic = "The selected key matches the app-managed pin. Authentication has not started."
                } else {
                    secureChannelHasPinnedKey = false
                    secureChannelPhase = .review
                    secureChannelDiagnostic = "Compare the selected SHA-256 fingerprint through an independent trusted channel before pinning it."
                }
            } catch {
                secureChannelPhase = .failed
                secureChannelDiagnostic = error.localizedDescription
                ifsOperationTask?.cancel()
                ifsWritePlan = nil
                isIFSWriteReviewPresented = false
                ifsPhase = .offline
                ifsDiagnostic = "Secure channel discovery failed. The local draft was preserved; remote operations are blocked."
            }
        }
    }

    func pinSelectedSecureChannelHostKey() {
        guard secureChannelPhase == .review, let key = selectedSecureChannelHostKey else {
            secureChannelDiagnostic = "Collect and select a host key first."
            return
        }
        do {
            try secureChannelService.pin(key)
            secureChannelHasPinnedKey = true
            secureChannelPhase = .pinned
            secureChannelDiagnostic = "Pinned \(key.algorithm) · \(key.fingerprint). Authentication has not started."
            showNotice("Pinned the verified SSH host key. No credential was sent.")
        } catch {
            secureChannelPhase = .failed
            secureChannelDiagnostic = error.localizedDescription
        }
    }

    func testPinnedSecureChannel() {
        guard !secureChannelPhase.isBusy else { return }
        let profile = secureChannelProfile
        secureChannelPhase = .authenticating
        secureChannelDiagnostic = "Testing the pinned SSH channel and SFTP subsystem with system OpenSSH."
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await secureChannelService.testPinnedChannel(profile: profile)
                guard secureChannelProfile == profile else { return }
                secureChannelPhase = .connected
                secureChannelDiagnostic = "Pinned host identity, SSH authentication, and SFTP subsystem verified."
                ifsPhase = .idle
                if ifsPathText == "/home", !profile.normalizedUsername.isEmpty {
                    ifsPathText = "/home/\(profile.normalizedUsername)"
                }
                showNotice("SSH + SFTP provider is ready for this app session.")
            } catch {
                secureChannelPhase = .failed
                secureChannelDiagnostic = error.localizedDescription
                ifsOperationTask?.cancel()
                ifsWritePlan = nil
                isIFSWriteReviewPresented = false
                ifsPhase = .offline
                ifsDiagnostic = "The secure channel test failed. The local draft was preserved; remote operations are blocked."
            }
        }
    }

    var sourceWritePreflight: SourceWritePreflight {
        let isRemoteIFS: Bool
        if case .ifs = sourceDocument.identity { isRemoteIFS = true } else { isRemoteIFS = false }
        let sourceProviderConnected: Bool = switch sourceDocument.identity {
        case .ifs:
            secureChannelPhase == .connected
        case .member, .localScratch:
            false
        }
        let roundTrip: Bool?
        if isRemoteIFS {
            roundTrip = (try? IFSUTF8DocumentCodec().encode(sourceDocument)) != nil
        } else {
            roundTrip = nil
        }
        return SourceWritePreflight(
            document: sourceDocument,
            context: SourceWritePreflightContext(
                providerConnected: sourceProviderConnected,
                targetStillCurrent: isRemoteIFS ? ifsRevisionState == .match : nil,
                ccsidRoundTripSucceeded: roundTrip,
                remoteContentCompared: isRemoteIFS && ifsRevisionState != .unverified
            )
        )
    }

    var openedSourceMemberIdentity: SourceMemberIdentity? {
        guard case let .member(library, sourceFile, member, _) = sourceDocument.identity else {
            return nil
        }
        return try? SourceMemberIdentity(
            library: library,
            sourceFile: sourceFile,
            member: member
        )
    }

    var sourceMemberCapabilityConnected: Bool {
        guard db2Phase.isConnected, let receipt = db2Receipt else { return false }
        return receipt.accessMode == .sourceMemberRead
            || receipt.accessMode == .reviewedSourceMemberWrite
    }

    var sourceMemberWriteCapabilityConnected: Bool {
        db2Phase.isConnected
            && db2Receipt?.accessMode == .reviewedSourceMemberWrite
            && db2Receipt?.environment != .production
    }

    var sourceMemberWriteEligibility: SourceMemberWriteEligibility? {
        guard let sourceMemberSnapshot,
              sourceMemberSnapshot.metadata.identity == openedSourceMemberIdentity else { return nil }
        return SourceMemberWriteEligibility(snapshot: sourceMemberSnapshot)
    }

    var sourceMemberEditorRecords: [SourceMemberRecord]? {
        guard let sourceMemberSnapshot,
              sourceMemberSnapshot.metadata.identity == openedSourceMemberIdentity else { return nil }
        return sourceMemberWritePlan?.records ?? sourceMemberSnapshot.records
    }

    func restoreSourceMemberReplay(openMember: Bool = true) {
        guard !sourceDocument.identity.isHostBacked || !sourceDocument.isDirty else {
            showNotice("Review or discard the current remote draft before restoring the local member replay.")
            return
        }
        sourceMemberTask?.cancel()
        sourceMemberTask = nil
        activeSourceMemberGeneration = nil
        sourceMemberLibraries = SourceMemberWorkspaceSamples.libraries
        sourceMemberFiles = SourceMemberWorkspaceSamples.sourceFiles
        sourceMembers = SourceMemberWorkspaceSamples.members
        selectedSourceMemberLibrary = SourceMemberWorkspaceSamples.developmentLibrary
        selectedSourceMemberFile = SourceMemberWorkspaceSamples.sourceFiles.first
        selectedSourceMemberID = SourceMemberWorkspaceSamples.snapshot.metadata.identity
        sourceMemberCurrentRemoteSnapshot = nil
        sourceMemberRevisionState = .unverified
        sourceMemberWritePlan = nil
        sourceMemberCommittedSnapshot = nil
        isSourceMemberWriteReviewPresented = false
        sourceMemberDatePolicy = .preserve
        sourceMemberPhase = .localReplay
        sourceMemberDiagnostic = "Showing a deterministic local source-member catalog. No library, file, member, source record, or authority was read from a host."
        guard openMember else { return }
        openSourceMemberSnapshot(SourceMemberWorkspaceSamples.snapshot)
        sourceMemberPhase = .localReplay
        sourceMemberDiagnostic = "Opened deterministic record-aware member evidence locally. No host query or write occurred."
        showNotice("Local source-member replay opened.")
    }

    func refreshSourceMemberCatalog(search: String? = nil) {
        guard let context = sourceMemberConnection(requireWrite: false) else { return }
        let generation = UUID()
        sourceMemberTask?.cancel()
        activeSourceMemberGeneration = generation
        sourceMemberPhase = .loadingLibraries
        sourceMemberDiagnostic = "Reading bounded source-library metadata through the selected member capability."
        let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines)

        sourceMemberTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let libraries = try await context.provider.listLibraries(
                    search: normalizedSearch?.isEmpty == false ? normalizedSearch : nil
                )
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                sourceMemberLibraries = libraries
                let library = selectedSourceMemberLibrary.flatMap { selected in
                    libraries.first(where: { $0 == selected })
                } ?? libraries.first
                selectedSourceMemberLibrary = library
                sourceMemberFiles = []
                sourceMembers = []
                selectedSourceMemberFile = nil
                selectedSourceMemberID = nil
                guard let library else {
                    activeSourceMemberGeneration = nil
                    sourceMemberPhase = .catalogReady
                    sourceMemberDiagnostic = "No caller-visible source libraries matched this catalog request."
                    return
                }

                sourceMemberPhase = .loadingFiles
                let files = try await context.provider.listSourceFiles(in: library)
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                sourceMemberFiles = files
                let file = files.first
                selectedSourceMemberFile = file
                guard let file else {
                    activeSourceMemberGeneration = nil
                    sourceMemberPhase = .catalogReady
                    sourceMemberDiagnostic = "No caller-visible source physical files were returned for \(library.value)."
                    return
                }

                sourceMemberPhase = .loadingMembers
                let members = try await context.provider.listMembers(
                    in: library,
                    sourceFile: file.sourceFile
                )
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                sourceMembers = members
                selectedSourceMemberID = members.first?.identity
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .catalogReady
                sourceMemberDiagnostic = "Loaded \(libraries.count) source libraries, \(files.count) source files, and \(members.count) members from \(context.receipt.targetName). No member records were read."
            } catch is CancellationError {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
            } catch {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .failed
                sourceMemberDiagnostic = "Source catalog read stopped locally: \(incidentFailureReason(error)). Prior evidence was retained."
            }
        }
    }

    func selectSourceMemberLibrary(_ library: IBMSystemObjectName) {
        guard selectedSourceMemberLibrary != library || sourceMemberFiles.isEmpty else { return }
        selectedSourceMemberLibrary = library
        selectedSourceMemberFile = nil
        selectedSourceMemberID = nil
        sourceMemberFiles = []
        sourceMembers = []
        loadSourceMemberFiles(in: library)
    }

    func selectSourceMemberFile(_ file: SourceMemberFileSummary) {
        guard selectedSourceMemberFile?.id != file.id || sourceMembers.isEmpty else { return }
        selectedSourceMemberLibrary = file.library
        selectedSourceMemberFile = file
        selectedSourceMemberID = nil
        sourceMembers = []
        loadSourceMembers(in: file)
    }

    func openSourceMember(_ member: SourceMemberSummary) {
        guard !sourceDocument.identity.isHostBacked || !sourceDocument.isDirty else {
            showNotice("Review or discard the current remote draft before opening another member.")
            return
        }
        if sourceMemberPhase == .localReplay,
           member.identity == SourceMemberWorkspaceSamples.snapshot.metadata.identity {
            restoreSourceMemberReplay(openMember: true)
            return
        }
        guard let context = sourceMemberConnection(requireWrite: false) else { return }
        let generation = UUID()
        sourceMemberTask?.cancel()
        activeSourceMemberGeneration = generation
        selectedSourceMemberID = member.identity
        sourceMemberPhase = .opening
        sourceMemberDiagnostic = "Reading the exact source-member metadata and record stream through a generated QTEMP alias."

        sourceMemberTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await context.provider.read(member.identity)
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                activeSourceMemberGeneration = nil
                openSourceMemberSnapshot(snapshot)
                sourceMemberPhase = .ready
                sourceMemberDiagnostic = "Opened \(snapshot.records.count) records from \(snapshot.metadata.identity.description) at revision \(snapshot.revision.shortFingerprint). No host write occurred."
            } catch is CancellationError {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
            } catch {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .failed
                sourceMemberDiagnostic = "Member read stopped locally: \(incidentFailureReason(error))."
            }
        }
    }

    func compareSourceMemberRevision() {
        guard let snapshot = sourceMemberSnapshot,
              snapshot.metadata.identity == openedSourceMemberIdentity else {
            showNotice("Open a source member before checking its revision.")
            return
        }
        guard sourceMemberPhase != .localReplay else {
            sourceMemberCurrentRemoteSnapshot = snapshot
            sourceMemberRevisionState = .match
            sourceMemberDiagnostic = "The deterministic replay is internally consistent. No host comparison occurred."
            showNotice("Local replay revision verified without contacting a host.")
            return
        }
        guard let context = sourceMemberConnection(requireWrite: false) else { return }
        let generation = UUID()
        sourceMemberTask?.cancel()
        activeSourceMemberGeneration = generation
        sourceMemberPhase = .comparing
        sourceMemberDiagnostic = "Re-reading the exact member to compare its canonical record revision."

        sourceMemberTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let current = try await context.provider.read(snapshot.metadata.identity)
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                activeSourceMemberGeneration = nil
                sourceMemberCurrentRemoteSnapshot = current
                if current.revision == snapshot.revision {
                    sourceMemberSnapshot = current
                    sourceMemberRevisionState = .match
                    sourceMemberPhase = .revisionMatch
                    sourceMemberDiagnostic = "Remote revision \(current.revision.shortFingerprint) still matches the opened snapshot."
                    showNotice("Source-member revision matches.")
                } else {
                    sourceMemberRevisionState = .conflict
                    sourceMemberWritePlan = nil
                    isSourceMemberWriteReviewPresented = false
                    sourceMemberPhase = .revisionConflict
                    sourceMemberDiagnostic = "The remote member changed after it was opened. The write path is blocked until the current records are reviewed."
                    showNotice("Source-member revision changed; write blocked.")
                }
            } catch is CancellationError {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
            } catch {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .failed
                sourceMemberDiagnostic = "Revision comparison stopped locally: \(incidentFailureReason(error))."
            }
        }
    }

    func requestSourceMemberWriteReview() {
        guard let opened = sourceMemberSnapshot,
              opened.metadata.identity == openedSourceMemberIdentity else {
            showNotice("Open a source member before preparing a write review.")
            return
        }
        guard sourceDocument.isDirty else {
            showNotice("The member has no local changes to review.")
            return
        }
        guard let context = sourceMemberConnection(requireWrite: true) else { return }
        let editedText = sourceDocument.text
        let datePolicy = sourceMemberDatePolicy
        let generation = UUID()
        sourceMemberTask?.cancel()
        activeSourceMemberGeneration = generation
        sourceMemberPhase = .preparingWrite
        sourceMemberDiagnostic = "Re-reading the exact member and building an immutable transactional write plan."

        sourceMemberTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let current = try await context.provider.read(opened.metadata.identity)
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                sourceMemberCurrentRemoteSnapshot = current
                guard current.revision == opened.revision else {
                    activeSourceMemberGeneration = nil
                    sourceMemberRevisionState = .conflict
                    sourceMemberWritePlan = nil
                    isSourceMemberWriteReviewPresented = false
                    sourceMemberPhase = .revisionConflict
                    sourceMemberDiagnostic = "The source member changed before review. The write path is blocked."
                    showNotice("Source-member revision changed before review.")
                    return
                }
                let eligibility = SourceMemberWriteEligibility(snapshot: current)
                guard eligibility.isEligible else {
                    activeSourceMemberGeneration = nil
                    sourceMemberPhase = .failed
                    sourceMemberDiagnostic = eligibility.checks.first(where: { $0.state == .blocked })?.detail
                        ?? "The source member failed its write-eligibility checks."
                    showNotice("Source-member write eligibility failed closed.")
                    return
                }
                let plan = try SourceMemberWritePlan(
                    snapshot: current,
                    editedText: editedText,
                    sourceDatePolicy: datePolicy
                )
                guard sourceDocument.text == editedText,
                      openedSourceMemberIdentity == current.metadata.identity else { return }
                activeSourceMemberGeneration = nil
                sourceMemberSnapshot = current
                sourceMemberRevisionState = .match
                sourceMemberWritePlan = plan
                sourceMemberPhase = .reviewReady
                sourceMemberDiagnostic = "The immutable write plan is bound to one member, expected revision, proposed revision, CCSID, width, date policy, and journaled transaction."
                isSourceMemberWriteReviewPresented = true
            } catch is CancellationError {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
            } catch {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .failed
                sourceMemberDiagnostic = "Write-plan preparation stopped locally: \(incidentFailureReason(error))."
                showNotice("Source-member write review was blocked.")
            }
        }
    }

    func commitReviewedSourceMemberWrite() {
        guard sourceMemberPhase == .reviewReady,
              let plan = sourceMemberWritePlan,
              plan.identity == openedSourceMemberIdentity,
              let context = sourceMemberConnection(requireWrite: true) else {
            showNotice("The reviewed source-member plan is no longer valid.")
            return
        }
        let generation = UUID()
        sourceMemberTask?.cancel()
        activeSourceMemberGeneration = generation
        sourceMemberPhase = .writing
        sourceMemberDiagnostic = "Re-checking the revision inside a serializable transaction before replacing any records."

        sourceMemberTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let committed = try await context.provider.write(plan)
                let transportStillConnected = await context.transport.isConnected
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context, allowClosedTransport: !transportStillConnected) else { return }
                activeSourceMemberGeneration = nil
                sourceMemberSnapshot = committed
                sourceMemberCurrentRemoteSnapshot = committed
                sourceMemberCommittedSnapshot = committed
                sourceDocument = committed.sourceDocument
                refreshSourceIntelligence()
                sourceSaveState = .remoteClean
                sourceMemberRevisionState = .match
                sourceMemberWritePlan = nil
                isSourceMemberWriteReviewPresented = false
                sourceMemberPhase = .written
                sourceMemberDiagnostic = "Committed and re-read \(committed.records.count) records at revision \(committed.revision.shortFingerprint)."
                if !transportStillConnected {
                    db2Transport = nil
                    db2Receipt = nil
                    db2Phase = .idle
                    db2Diagnostic = "The reviewed write committed and verified; the session then closed to clear uncertain QTEMP alias state."
                }
                showNotice("Reviewed source-member transaction committed and verified.")
            } catch is CancellationError {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
            } catch {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
                sourceMemberWritePlan = nil
                isSourceMemberWriteReviewPresented = false
                if (error as? SourceMemberWorkspaceError) == .revisionChanged
                    || (error as? Db2ODBCTransportError) == .revisionChanged {
                    sourceMemberRevisionState = .conflict
                    sourceMemberPhase = .revisionConflict
                    sourceMemberDiagnostic = "The source member changed inside the transaction. It was rolled back and the write path is blocked."
                } else {
                    sourceMemberPhase = .failed
                    sourceMemberDiagnostic = "The reviewed transaction failed closed: \(incidentFailureReason(error))."
                }
                showNotice("Source-member transaction did not commit.")
            }
        }
    }

    func cancelSourceMemberWriteReview() {
        guard sourceMemberPhase != .writing else { return }
        sourceMemberWritePlan = nil
        isSourceMemberWriteReviewPresented = false
        sourceMemberPhase = sourceMemberSnapshot == nil ? .catalogReady : .ready
        sourceMemberDiagnostic = "The reviewed write plan was discarded. No host write occurred."
    }

    func discardSourceMemberDraft() {
        guard sourceMemberPhase != .writing,
              let snapshot = sourceMemberSnapshot,
              snapshot.metadata.identity == openedSourceMemberIdentity else { return }
        sourceDocument = snapshot.sourceDocument
        refreshSourceIntelligence()
        sourceSaveState = .remoteClean
        sourceMemberCurrentRemoteSnapshot = nil
        sourceMemberRevisionState = .unverified
        sourceMemberWritePlan = nil
        isSourceMemberWriteReviewPresented = false
        sourceMemberPhase = sourceMemberPhase == .localReplay ? .localReplay : .ready
        sourceMemberDiagnostic = "Local member edits were discarded. No host write occurred."
        showNotice("Source-member draft discarded locally.")
    }

    func setSourceMemberDatePolicy(_ policy: SourceMemberDatePolicy) {
        guard sourceMemberPhase != .writing else { return }
        sourceMemberDatePolicy = policy
        sourceMemberWritePlan = nil
        isSourceMemberWriteReviewPresented = false
        if sourceMemberPhase == .reviewReady { sourceMemberPhase = .ready }
    }

    func updateSourceText(_ text: String) {
        guard ifsPhase != .writing, sourceMemberPhase != .writing else { return }
        guard openedSourceWorkspaceSnapshotPath == nil else { return }
        guard sourceDocument.text != text else { return }
        dismissSourceCompletion()
        sourceDocument.text = text
        scheduleSourceIntelligenceAnalysis()
        if case .member = sourceDocument.identity {
            sourceSaveTask?.cancel()
            sourceSaveTask = nil
            sourceSaveState = sourceDocument.isDirty ? .remoteDraft : .remoteClean
            sourceMemberWritePlan = nil
            isSourceMemberWriteReviewPresented = false
            if sourceMemberPhase == .reviewReady || sourceMemberPhase == .written {
                sourceMemberPhase = .ready
            }
            return
        }
        if case .ifs = sourceDocument.identity {
            sourceSaveTask?.cancel()
            sourceSaveTask = nil
            sourceSaveState = sourceDocument.isDirty ? .remoteDraft : .remoteClean
            ifsWritePlan = nil
            isIFSWriteReviewPresented = false
            if ifsPhase == .reviewReady { ifsPhase = .fileReady }
            return
        }
        sourceSaveState = .saving
        sourceSaveTask?.cancel()
        sourceSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            persistSourceScratch(text)
        }
    }

    func flushSourceScratch() {
        guard !sourceDocument.identity.isHostBacked,
              openedSourceWorkspaceSnapshotPath == nil else { return }
        sourceSaveTask?.cancel()
        sourceSaveTask = nil
        persistSourceScratch(sourceDocument.text)
    }

    func browseIFSPath() {
        guard secureChannelPhase == .connected else {
            ifsPhase = .offline
            ifsDiagnostic = "Test a pinned SSH + SFTP channel before browsing the IFS."
            showNotice(ifsDiagnostic ?? "IFS provider is offline.")
            return
        }
        let path: IFSPath
        do {
            path = try IFSPath(ifsPathText)
        } catch {
            ifsPhase = .failed
            ifsDiagnostic = error.localizedDescription
            return
        }
        browseIFSDirectory(path)
    }

    func openIFSParentDirectory() {
        guard let parent = ifsDirectory?.parent else { return }
        ifsPathText = parent.value
        browseIFSDirectory(parent)
    }

    func openIFSDirectory(_ entry: IFSDirectoryEntry) {
        guard entry.kind == .directory else { return }
        ifsPathText = entry.metadata.path.value
        browseIFSDirectory(entry.metadata.path)
    }

    func openIFSFile(_ entry: IFSDirectoryEntry) {
        guard entry.kind == .file else {
            ifsDiagnostic = "Symbolic links and special objects are visible but read-only in this provider."
            return
        }
        if sourceDocument.identity.isHostBacked, sourceDocument.isDirty {
            showNotice("The current remote draft has edits. Review or discard it before opening another file.")
            return
        }
        guard secureChannelPhase == .connected else {
            showNotice("The pinned SFTP channel is not ready.")
            return
        }

        let profile = secureChannelProfile
        let metadata = entry.metadata
        ifsOperationTask?.cancel()
        ifsPhase = .opening
        ifsDiagnostic = "Downloading the exact remote bytes into a restricted temporary directory."
        ifsOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let decoded = try await ifsWorkspaceService.readFile(profile: profile, metadata: metadata)
                guard !Task.isCancelled,
                      secureChannelProfile == profile,
                      secureChannelPhase == .connected else { return }
                sourceSaveTask?.cancel()
                sourceSaveTask = nil
                openedSourceWorkspaceSnapshotPath = nil
                sourceDocument = decoded.document
                refreshSourceIntelligence()
                sourceSaveState = .remoteClean
                ifsSelectedMetadata = decoded.metadata
                ifsRemoteBaselineText = decoded.document.originalText
                ifsLatestRemoteText = nil
                ifsRevisionState = .match
                ifsWritePlan = nil
                ifsWriteReceipt = nil
                ifsPhase = .fileReady
                ifsDiagnostic = "Opened \(decoded.metadata.path.value) at revision \(decoded.revision.shortFingerprint)."
            } catch {
                guard !Task.isCancelled else { return }
                ifsPhase = .failed
                ifsDiagnostic = error.localizedDescription
            }
        }
    }

    func compareIFSRemoteRevision() {
        guard secureChannelPhase == .connected,
              let metadata = ifsSelectedMetadata,
              case .ifs(let rawPath) = sourceDocument.identity,
              rawPath == metadata.path.value else {
            showNotice("Open a remote IFS file before comparing revisions.")
            return
        }
        let profile = secureChannelProfile
        let expectedRevision = sourceDocument.remoteRevision
        ifsOperationTask?.cancel()
        ifsPhase = .comparing
        ifsDiagnostic = "Reading the current remote bytes for an exact SHA-256 comparison."
        ifsOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let latest = try await ifsWorkspaceService.readFile(profile: profile, metadata: metadata)
                guard !Task.isCancelled, secureChannelProfile == profile else { return }
                if latest.document.remoteRevision == expectedRevision {
                    ifsLatestRemoteText = nil
                    ifsRevisionState = .match
                    ifsPhase = .revisionMatch
                    ifsDiagnostic = "The remote bytes still match \(latest.revision.shortFingerprint)."
                } else {
                    ifsLatestRemoteText = latest.document.originalText
                    ifsRevisionState = .conflict
                    ifsWritePlan = nil
                    isIFSWriteReviewPresented = false
                    ifsPhase = .revisionConflict
                    ifsDiagnostic = "The remote revision changed to \(latest.revision.shortFingerprint). Compare before editing or writing."
                }
            } catch {
                guard !Task.isCancelled else { return }
                ifsPhase = .failed
                ifsDiagnostic = error.localizedDescription
            }
        }
    }

    func requestIFSWriteReview() {
        guard secureChannelPhase == .connected,
              let metadata = ifsSelectedMetadata,
              case .ifs(let rawPath) = sourceDocument.identity,
              rawPath == metadata.path.value else {
            showNotice("Open a remote IFS file through the pinned channel before preparing a write.")
            return
        }
        guard sourceDocument.isDirty else {
            showNotice("The remote draft has no local changes to write.")
            return
        }

        let profile = secureChannelProfile
        let expectedRevision = sourceDocument.remoteRevision
        ifsOperationTask?.cancel()
        ifsPhase = .preparingWrite
        ifsDiagnostic = "Re-reading the remote bytes before building the immutable write plan."
        ifsOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let latest = try await ifsWorkspaceService.readFile(profile: profile, metadata: metadata)
                guard !Task.isCancelled, secureChannelProfile == profile else { return }
                guard latest.document.remoteRevision == expectedRevision else {
                    ifsLatestRemoteText = latest.document.originalText
                    ifsRevisionState = .conflict
                    ifsWritePlan = nil
                    ifsPhase = .revisionConflict
                    ifsDiagnostic = "The remote bytes changed while the review was being prepared. No write was attempted."
                    return
                }

                let plan = try IFSWritePlan(document: sourceDocument)
                ifsLatestRemoteText = nil
                ifsRevisionState = .match
                ifsWritePlan = plan
                ifsPhase = .reviewReady
                ifsDiagnostic = "Review the exact target, expected revision, byte count, and generated sibling path."
                isIFSWriteReviewPresented = true
            } catch {
                guard !Task.isCancelled else { return }
                ifsPhase = .failed
                ifsDiagnostic = error.localizedDescription
            }
        }
    }

    func commitReviewedIFSWrite() {
        guard secureChannelPhase == .connected,
              ifsPhase == .reviewReady,
              let plan = ifsWritePlan,
              let metadata = ifsSelectedMetadata else {
            showNotice("The reviewed write plan is no longer current.")
            return
        }
        let profile = secureChannelProfile
        let document = sourceDocument
        ifsOperationTask?.cancel()
        ifsPhase = .writing
        ifsDiagnostic = "Verifying the remote revision, staged bytes, rename result, and committed bytes."
        ifsOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let receipt = try await ifsWorkspaceService.writeFile(
                    profile: profile,
                    document: document,
                    metadata: metadata,
                    plan: plan
                )
                guard secureChannelProfile == profile else { return }
                var committed = document
                committed.originalText = document.text
                committed.remoteRevision = receipt.committedRevision.token
                sourceDocument = committed
                refreshSourceIntelligence()
                sourceSaveState = .remoteClean
                ifsSelectedMetadata = IFSResourceMetadata(
                    path: metadata.path,
                    kind: metadata.kind,
                    permissions: metadata.permissions,
                    owner: metadata.owner,
                    group: metadata.group,
                    byteCount: Int64(receipt.committedRevision.byteCount),
                    modifiedDescription: "Verified just now"
                )
                ifsRemoteBaselineText = committed.text
                ifsLatestRemoteText = nil
                ifsRevisionState = .match
                ifsWriteReceipt = receipt
                ifsWritePlan = nil
                ifsPhase = .written
                ifsDiagnostic = "Committed and re-downloaded \(receipt.committedRevision.shortFingerprint)."
                isIFSWriteReviewPresented = false
                showNotice("IFS write completed and the committed bytes were verified.")
            } catch {
                ifsWritePlan = nil
                isIFSWriteReviewPresented = false
                if (error as? IFSWorkspaceError) == .revisionChanged {
                    ifsRevisionState = .conflict
                    ifsPhase = .revisionConflict
                } else {
                    ifsPhase = .failed
                }
                ifsDiagnostic = error.localizedDescription
            }
        }
    }

    func cancelIFSWriteReview() {
        guard ifsPhase != .writing else { return }
        isIFSWriteReviewPresented = false
        ifsWritePlan = nil
        if ifsSelectedMetadata != nil { ifsPhase = .fileReady }
    }

    func discardRemoteSourceDraft() {
        guard case .ifs = sourceDocument.identity, ifsPhase != .writing else { return }
        sourceDocument.text = sourceDocument.originalText
        refreshSourceIntelligence()
        sourceSaveState = .remoteClean
        ifsWritePlan = nil
        isIFSWriteReviewPresented = false
        ifsPhase = .fileReady
        showNotice("Discarded the local draft. No host operation was attempted.")
    }

    func returnToLocalSourceScratch() {
        guard !sourceDocument.identity.isHostBacked || !sourceDocument.isDirty else {
            showNotice("Discard or review the current remote draft before returning to the local scratch file.")
            return
        }
        sourceMemberTask?.cancel()
        sourceMemberTask = nil
        activeSourceMemberGeneration = nil
        sourceMemberSnapshot = nil
        sourceMemberCurrentRemoteSnapshot = nil
        sourceMemberRevisionState = .unverified
        sourceMemberWritePlan = nil
        isSourceMemberWriteReviewPresented = false
        openedSourceWorkspaceSnapshotPath = nil
        resetIFSWorkspace(restoreLocalDocument: true)
    }

    private func browseIFSDirectory(_ path: IFSPath) {
        let profile = secureChannelProfile
        ifsOperationTask?.cancel()
        ifsPhase = .browsing
        ifsDiagnostic = "Listing \(path.value) through the pinned system SFTP client."
        ifsOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await ifsWorkspaceService.listDirectory(profile: profile, path: path)
                guard !Task.isCancelled,
                      secureChannelProfile == profile,
                      secureChannelPhase == .connected else { return }
                ifsDirectory = snapshot.directory
                ifsPathText = snapshot.directory.value
                ifsEntries = snapshot.entries
                ifsPhase = .directoryReady
                ifsDiagnostic = "Listed \(snapshot.entries.count) typed remote objects."
            } catch {
                guard !Task.isCancelled else { return }
                ifsPhase = .failed
                ifsDiagnostic = error.localizedDescription
            }
        }
    }

    var sqlAnalysis: SQLStatementAnalysis {
        SQLStatementAnalyzer().analyze(sqlText)
    }

    var sqlExecutionPreflight: SQLExecutionPreflight {
        let receipt = db2Receipt
        return SQLExecutionPreflight(
            sql: sqlText,
            policy: sqlPolicy,
            context: SQLExecutionContext(
                providerConnected: db2Phase.isConnected && receipt?.accessMode == .readOnly,
                targetName: receipt?.targetName,
                environment: receipt?.environment
            )
        )
    }

    var selectedSQLService: IBMServiceQuery? {
        guard let sqlSelectedServiceID else { return nil }
        return IBMIServicesCatalog.queries.first(where: { $0.id == sqlSelectedServiceID })
    }

    func selectSQLService(_ query: IBMServiceQuery) {
        sqlSelectedServiceID = query.id
        sqlBaselineText = query.sql
        updateSQLText(query.sql)
        showNotice("Loaded the read-only \(query.serviceName) template. Nothing was executed.")
    }

    func updateSQLText(_ text: String) {
        sqlExplainReview = nil
        isSQLExplainPresented = false
        sqlExplainDiagnostic = "SQL changed. Open Explain to build a fresh local static review."
        sqlText = text
        sqlSaveState = .saving
        sqlSaveTask?.cancel()
        sqlSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            persistSQLScratch(text)
        }
    }

    func updateSQLCursor(line: Int, column: Int) {
        sqlCursorLine = max(1, line)
        sqlCursorColumn = max(1, column)
    }

    func updateSQLSelection(_ range: NSRange) {
        sqlSelection = range.length > 0
            ? AITextSelection(locationUTF16: range.location, lengthUTF16: range.length)
            : nil
    }

    func requestSQLExecution() {
        let preflight = sqlExecutionPreflight
        guard preflight.isReady else {
            let firstFailure = preflight.checks.first(where: { $0.state != .ready })
            showNotice(firstFailure?.detail ?? "The Db2 execution gate is not ready.")
            return
        }
        guard let transport = db2Transport, let receipt = db2Receipt else {
            showNotice("The Db2 connection receipt is no longer current. Connect again before execution.")
            return
        }
        let request = SQLExecutionRequest(
            sql: sqlText,
            maximumRows: sqlPolicy.maximumRows,
            timeoutSeconds: sqlPolicy.timeoutSeconds,
            readOnly: true
        )
        let profileID = receipt.profileID
        sqlExecutionTask?.cancel()
        sqlResult = nil
        sqlResultQueryText = nil
        sqlResultProviderName = nil
        sqlResultEnvironment = nil
        sqlTypedExportPlan = nil
        isSQLTypedExportPresented = false
        sqlExplainReview = nil
        isSQLExplainPresented = false
        sqlExplainDiagnostic = "A live query is in progress. Open Explain again to review the current SQL locally."
        sqlExecutionPhase = .running
        sqlExecutionDiagnostic = "Executing one bounded read-only statement against \(receipt.targetName)."
        sqlExecutionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await transport.execute(request)
                guard !Task.isCancelled,
                      db2Receipt?.profileID == profileID,
                      db2Transport === transport else { return }
                sqlResult = result
                sqlResultQueryText = request.sql
                sqlResultProviderName = receipt.driverName
                sqlResultEnvironment = receipt.environment
                sqlExecutionPhase = .succeeded
                sqlExecutionDiagnostic = "Returned \(result.rows.count) row(s) in \(result.elapsedMilliseconds) ms\(result.wasTruncated ? " at the configured cap" : "")."
                showNotice("Read-only Db2 query completed.")
            } catch is CancellationError {
                guard db2Receipt?.profileID == profileID else { return }
                sqlExecutionPhase = .idle
                sqlExecutionDiagnostic = "The local query task was cancelled. The driver timeout remains authoritative."
            } catch {
                guard db2Receipt?.profileID == profileID else { return }
                sqlExecutionPhase = .failed
                sqlExecutionDiagnostic = error.localizedDescription
                showNotice("Db2 query failed. Review the result message.")
            }
        }
    }

    func presentSQLTypedExportStudio() {
        rebuildSQLTypedExportPlan()
        guard sqlTypedExportPlan != nil else {
            showNotice("Typed export is blocked. Review the result evidence first.")
            return
        }
        isSQLTypedExportPresented = true
    }

    func presentSQLExplainStudio() {
        do {
            let review = try SQLExplainReviewBuilder().build(sql: sqlText, policy: sqlPolicy)
            sqlExplainReview = review
            sqlExplainDiagnostic = "Built local static review \(review.shortFingerprint). No provider call or SQL execution occurred."
            isSQLExplainPresented = true
        } catch {
            sqlExplainReview = nil
            isSQLExplainPresented = false
            sqlExplainDiagnostic = error.localizedDescription
            showNotice("Explain review is blocked. \(error.localizedDescription)")
        }
    }

    func selectSQLTypedExportFormat(_ format: SQLTypedExportFormat) {
        sqlTypedExportFormat = format
        rebuildSQLTypedExportPlan()
    }

    func rebuildSQLTypedExportPlan() {
        guard let result = sqlResult,
              let query = sqlResultQueryText,
              let providerName = sqlResultProviderName,
              let environment = sqlResultEnvironment else {
            sqlTypedExportPlan = nil
            sqlTypedExportDiagnostic = "The result, exact executed query, provider, and environment receipt must all be retained before export."
            return
        }
        do {
            let plan = try SQLTypedExportBuilder().build(
                result: result,
                query: query,
                providerName: providerName,
                environment: environment,
                format: sqlTypedExportFormat
            )
            sqlTypedExportPlan = plan
            sqlTypedExportDiagnostic = "Plan \(plan.shortFingerprint) is ready. Saving creates only a verified local artifact and never re-runs the query."
        } catch {
            sqlTypedExportPlan = nil
            sqlTypedExportDiagnostic = error.localizedDescription
        }
    }

    func saveSQLTypedExport() {
        guard let plan = sqlTypedExportPlan else {
            sqlTypedExportDiagnostic = "Prepare a valid typed export plan before choosing a destination."
            return
        }
        terminalExport.saveSQLTypedExport(plan) { [weak self] result in
            switch result {
            case .success(let url):
                self?.sqlTypedExportDiagnostic = "Saved \(plan.files.count) verified local artifact file\(plan.files.count == 1 ? "" : "s") to \(url.lastPathComponent)."
                self?.showNotice("Typed Db2 export saved locally.")
            case .failure(let error):
                self?.sqlTypedExportDiagnostic = "Local typed export failed: \(error.localizedDescription)"
                self?.showNotice("Typed Db2 export failed.")
            }
        }
    }

    func prepareSQLTypedExportAssist() {
        guard let plan = sqlTypedExportPlan else {
            sqlTypedExportDiagnostic = "Prepare a valid typed export plan before pinning its schema summary."
            return
        }
        do {
            let fragment = try AIContextFragment(
                kind: .sqlResult,
                documentName: "db2-result-schema.txt",
                language: "Db2 for i result schema",
                sourceText: plan.assistContextText()
            )
            let bundle = try pinPreparedAssistantContext(
                fragment,
                label: "Db2 result export schema"
            )
            assistantInput = "Review this Db2 for i result schema and export contract. Identify type, CCSID, NULL, decimal, timestamp, binary, or spreadsheet fidelity risks without assuming access to the omitted query or cell values."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            sqlTypedExportDiagnostic = "Schema-only context \(plan.shortFingerprint) was pinned locally. Review it before sending."
            showNotice("Db2 export schema pinned for review.")
        } catch {
            sqlTypedExportDiagnostic = error.localizedDescription
            showNotice("Db2 export schema context was blocked.")
        }
    }

    func selectIncidentJob(_ job: JobInventoryRecord) {
        selectedIncidentJobID = job.qualifiedName
    }

    func refreshJobIncidentSnapshot() {
        guard !jobIncidentPhase.isCollecting else { return }
        guard db2Phase.isConnected,
              let transport = db2Transport,
              let receipt = db2Receipt,
              receipt.accessMode == .readOnly else {
            jobIncidentDiagnostic = "Connect the reviewed read-only Db2 provider before collecting a live incident snapshot. No query was executed."
            showNotice("Incident refresh needs a read-only Db2 connection.")
            return
        }
        guard receipt.environment != .production else {
            jobIncidentPhase = .failed
            jobIncidentDiagnostic = "Live incident collection is blocked for PROD. Select a non-production profile and review the target again."
            showNotice("Production incident collection is blocked by policy.")
            return
        }

        let planner = JobIncidentSQLPlanner()
        let decoder = JobIncidentSQLDecoder()
        let profileID = receipt.profileID
        let preferredJobID = selectedIncidentJobID
        let generation = UUID()
        jobIncidentTask?.cancel()
        activeJobIncidentGeneration = generation
        jobIncidentPhase = .collecting
        jobIncidentDiagnostic = "Collecting bounded JOB_INFO evidence. Lock, job-log, and QSYSOPR evidence are optional and will be reported separately."

        jobIncidentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let jobRequest = planner.jobInventory
                let jobResult = try await transport.execute(jobRequest)
                try Task.checkCancellation()
                let jobs = try decoder.decodeJobs(jobResult)
                var receipts = [incidentReceipt(.jobInfo, result: jobResult, request: jobRequest)]

                var locks: [JobLockRecord] = []
                let lockRequest = planner.objectLocks
                do {
                    let lockResult = try await transport.execute(lockRequest)
                    try Task.checkCancellation()
                    locks = try decoder.decodeLocks(lockResult)
                    receipts.append(incidentReceipt(.objectLockInfo, result: lockResult, request: lockRequest))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    receipts.append(incidentGap(.objectLockInfo, request: lockRequest, error: error))
                }

                let selectedID = preferredJobID.flatMap { preferred in
                    jobs.contains(where: { $0.qualifiedName == preferred }) ? preferred : nil
                } ?? locks.first(where: { lock in
                    (lock.status == .waiting || lock.status == .requested)
                        && jobs.contains(where: { $0.qualifiedName == lock.job })
                })?.job
                    ?? jobs.first(where: { $0.status == .active })?.qualifiedName
                    ?? jobs.first?.qualifiedName

                var jobLogMessages: [JobLogMessage] = []
                if let selectedID {
                    let logRequest = planner.jobLog(for: selectedID)
                    do {
                        let logResult = try await transport.execute(logRequest)
                        try Task.checkCancellation()
                        jobLogMessages = try decoder.decodeJobLog(logResult)
                        receipts.append(incidentReceipt(.joblogInfo, result: logResult, request: logRequest))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        receipts.append(incidentGap(.joblogInfo, request: logRequest, error: error))
                    }
                } else {
                    receipts.append(JobIncidentEvidenceReceipt(
                        source: .joblogInfo,
                        rowCount: 0,
                        wasTruncated: false,
                        queryFingerprint: AIContentFingerprint.sha256("JOBLOG_INFO NOT EXECUTED: NO SELECTED JOB"),
                        outcome: .unavailable("No job was available for a bounded JOBLOG_INFO request.")
                    ))
                }

                var operatorMessages: [OperatorMessageRecord] = []
                let messageRequest = planner.operatorInquiries
                do {
                    let messageResult = try await transport.execute(messageRequest)
                    try Task.checkCancellation()
                    operatorMessages = try decoder.decodeOperatorMessages(messageResult)
                    receipts.append(incidentReceipt(.messageQueueInfo, result: messageResult, request: messageRequest))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    receipts.append(incidentGap(.messageQueueInfo, request: messageRequest, error: error))
                }

                guard !Task.isCancelled,
                      activeJobIncidentGeneration == generation,
                      db2Receipt?.profileID == profileID,
                      db2Transport === transport else { return }
                jobIncidentSnapshot = JobIncidentSnapshot(
                    targetName: receipt.targetName,
                    capturedAt: Date(),
                    jobs: jobs,
                    locks: locks,
                    jobLogMessages: jobLogMessages,
                    operatorMessages: operatorMessages,
                    receipts: receipts
                )
                selectedIncidentJobID = selectedID
                activeJobIncidentGeneration = nil
                jobIncidentPhase = .ready
                let gapCount = receipts.filter { !$0.outcome.isCollected }.count
                jobIncidentDiagnostic = gapCount == 0
                    ? "Collected four bounded read-only evidence surfaces from \(receipt.targetName)."
                    : "Collected JOB_INFO from \(receipt.targetName) with \(gapCount) optional evidence gap(s). Review each receipt before drawing conclusions."
                showNotice("Incident snapshot collected without changing the host.")
            } catch is CancellationError {
                guard activeJobIncidentGeneration == generation else { return }
                activeJobIncidentGeneration = nil
                jobIncidentPhase = jobIncidentSnapshot.targetName == "LOCAL INCIDENT REPLAY" ? .localReplay : .failed
                jobIncidentDiagnostic = "The local incident collection task was cancelled. The prior snapshot was retained."
            } catch {
                guard activeJobIncidentGeneration == generation,
                      db2Receipt?.profileID == profileID else { return }
                activeJobIncidentGeneration = nil
                jobIncidentPhase = .failed
                jobIncidentDiagnostic = "JOB_INFO collection failed: \(incidentFailureReason(error)). The prior snapshot was retained."
                showNotice("Incident collection failed before a complete job inventory was available.")
            }
        }
    }

    func prepareIncidentAssist() {
        guard let analysis = jobIncidentAnalysis else {
            jobIncidentDiagnostic = "Select a job before preparing reviewed Assist context."
            return
        }
        do {
            let context = JobIncidentAssistContextBuilder().build(
                snapshot: jobIncidentSnapshot,
                analysis: analysis
            )
            let fragment = try AIContextFragment(
                kind: .jobIncident,
                documentName: "\(analysis.selectedJob.qualifiedName.name)-incident-evidence.txt",
                language: "IBM i incident evidence",
                sourceText: context
            )
            let bundle = try pinPreparedAssistantContext(
                fragment,
                label: "\(analysis.selectedJob.qualifiedName.name) incident evidence"
            )
            assistantInput = "Review this read-only IBM i job incident evidence. Separate exact observations from inference, explain the strongest waiting hypothesis, identify evidence gaps, and propose only the smallest safe read-only checks."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("Incident evidence pinned. Review the exact Context Shelf before sending.")
        } catch {
            jobIncidentDiagnostic = "Assist context was blocked: \(incidentFailureReason(error))"
            showNotice("Incident Assist context was blocked.")
        }
    }

    func selectSpooledFile(_ file: SpooledFileRecord) {
        guard spoolOutputSnapshot.files.contains(where: { $0.identity == file.identity }) else { return }
        spoolPreviewTask?.cancel()
        spoolPreviewTask = nil
        activeSpoolPreviewGeneration = nil
        selectedSpoolFileID = file.identity

        if spoolOutputSnapshot.targetName == "LOCAL OUTPUT REPLAY",
           file.identity == SpooledOutputSamples.selectedIdentity {
            spoolTextPreview = SpooledOutputSamples.makePreview()
            spoolComparisonBaseline = SpooledOutputSamples.makeBaseline()
            spoolPreviewPhase = .localReplay
            spoolPreviewDiagnostic = "Showing deterministic text records. No host content read occurred."
        } else {
            spoolTextPreview = nil
            if spoolComparisonBaseline?.identity.file != file.identity.file {
                spoolComparisonBaseline = nil
            }
            spoolPreviewPhase = .notLoaded
            spoolPreviewDiagnostic = "Content is not loaded. Opening exact text is a separate explicit, auditable request."
        }
    }

    func refreshSpoolOutputInventory() {
        guard !spoolInventoryPhase.isCollecting else { return }
        guard db2Phase.isConnected,
              let transport = db2Transport,
              let receipt = db2Receipt,
              receipt.accessMode == .readOnly else {
            spoolInventoryDiagnostic = "Connect the reviewed read-only Db2 provider before refreshing output inventory. No query was executed."
            showNotice("Output inventory needs a read-only Db2 connection.")
            return
        }
        guard receipt.environment != .production else {
            spoolInventoryPhase = .failed
            spoolInventoryDiagnostic = "Live output collection is blocked for PROD. Select a non-production profile and review the target again."
            showNotice("Production output collection is blocked by policy.")
            return
        }

        let planner = SpooledOutputSQLPlanner()
        let decoder = SpooledOutputSQLDecoder()
        let limits = planner.limits
        let profileID = receipt.profileID
        let preferredID = selectedSpoolFileID
        let generation = UUID()
        spoolInventoryTask?.cancel()
        spoolPreviewTask?.cancel()
        spoolPreviewTask = nil
        activeSpoolPreviewGeneration = nil
        spoolPreviewPhase = spoolTextPreview == nil ? .notLoaded : .failed
        spoolPreviewDiagnostic = spoolTextPreview == nil
            ? "Inventory refresh is in progress; no spooled-file content is loaded."
            : "Inventory refresh is in progress; the prior text preview remains local and is not current for the pending snapshot."
        activeSpoolInventoryGeneration = generation
        spoolInventoryPhase = .collecting
        spoolInventoryDiagnostic = "Collecting bounded SPOOLED_FILE_INFO inventory. File content is not opened by this refresh."

        spoolInventoryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let inventoryRequest = planner.inventory
                let inventoryResult = try await transport.execute(inventoryRequest)
                try Task.checkCancellation()
                let files = try decoder.decodeInventory(inventoryResult)
                var receipts = [spoolReceipt(
                    .spooledFileInfo,
                    result: inventoryResult,
                    request: inventoryRequest,
                    configuredLimit: limits.maximumInventoryRows
                )]

                var queues: [OutputQueueRecord] = []
                let queueRequest = planner.outputQueues
                do {
                    let queueResult = try await transport.execute(queueRequest)
                    try Task.checkCancellation()
                    queues = try decoder.decodeQueues(queueResult)
                    receipts.append(spoolReceipt(
                        .outputQueueInfo,
                        result: queueResult,
                        request: queueRequest,
                        configuredLimit: limits.maximumQueueRows
                    ))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    receipts.append(spoolGap(.outputQueueInfo, request: queueRequest, error: error))
                }

                let selectedID = preferredID.flatMap { preferred in
                    files.contains(where: { $0.identity == preferred }) ? preferred : nil
                } ?? files.first?.identity
                let previewFingerprint = selectedID.map {
                    AIContentFingerprint.sha256(planner.preview($0).sql)
                } ?? AIContentFingerprint.sha256("SPOOLED_FILE_DATA NOT REQUESTED: NO SELECTED FILE")
                receipts.append(SpooledOutputEvidenceReceipt(
                    source: .spooledFileData,
                    rowCount: 0,
                    boundWasReached: false,
                    queryFingerprint: previewFingerprint,
                    outcome: .unavailable("Content was not requested. Select an exact file and explicitly load its text preview.")
                ))

                guard !Task.isCancelled,
                      activeSpoolInventoryGeneration == generation,
                      db2Receipt?.profileID == profileID,
                      db2Transport === transport else { return }
                spoolOutputSnapshot = SpooledOutputSnapshot(
                    targetName: receipt.targetName,
                    capturedAt: Date(),
                    files: files,
                    queues: queues,
                    receipts: receipts
                )
                selectedSpoolFileID = selectedID
                spoolTextPreview = nil
                spoolComparisonBaseline = nil
                spoolPreviewPhase = .notLoaded
                spoolPreviewDiagnostic = selectedID == nil
                    ? "No accessible spooled file is available for content review."
                    : "Inventory collected without opening content. Load the selected exact text explicitly."
                activeSpoolInventoryGeneration = nil
                spoolInventoryPhase = .ready
                let gapCount = receipts.filter { !$0.outcome.isCollected }.count
                spoolInventoryDiagnostic = gapCount == 1
                    ? "Collected bounded output and queue inventory from \(receipt.targetName). Content remains unopened by design."
                    : "Collected output inventory from \(receipt.targetName) with \(gapCount - 1) optional metadata gap(s). Content remains unopened."
                showNotice("Output inventory collected without opening spooled-file content.")
            } catch is CancellationError {
                guard activeSpoolInventoryGeneration == generation else { return }
                activeSpoolInventoryGeneration = nil
                spoolInventoryPhase = spoolOutputSnapshot.targetName == "LOCAL OUTPUT REPLAY" ? .localReplay : .failed
                spoolInventoryDiagnostic = "The output inventory task was cancelled. The prior snapshot was retained."
            } catch {
                guard activeSpoolInventoryGeneration == generation,
                      db2Receipt?.profileID == profileID else { return }
                activeSpoolInventoryGeneration = nil
                spoolInventoryPhase = .failed
                spoolInventoryDiagnostic = "SPOOLED_FILE_INFO collection failed: \(incidentFailureReason(error)). The prior snapshot was retained."
                showNotice("Output inventory failed before a complete file list was available.")
            }
        }
    }

    func loadSelectedSpoolTextPreview() {
        guard !spoolPreviewPhase.isLoading else { return }
        guard let file = selectedSpooledFile else {
            spoolPreviewDiagnostic = "Select a spooled file before loading content."
            return
        }
        guard file.isContentAvailable else {
            spoolPreviewPhase = .failed
            spoolPreviewDiagnostic = "Deleted spooled-file metadata has no content available for preview."
            return
        }
        guard db2Phase.isConnected,
              let transport = db2Transport,
              let receipt = db2Receipt,
              receipt.accessMode == .readOnly else {
            spoolPreviewDiagnostic = "Connect the reviewed read-only Db2 provider before opening exact text. No content request was executed."
            showNotice("Text preview needs a read-only Db2 connection.")
            return
        }
        guard receipt.environment != .production else {
            spoolPreviewPhase = .failed
            spoolPreviewDiagnostic = "Spooled-file content reads are blocked for PROD by this development policy."
            showNotice("Production spooled-file content reads are blocked by policy.")
            return
        }
        guard spoolOutputSnapshot.targetName == receipt.targetName else {
            spoolPreviewPhase = .failed
            spoolPreviewDiagnostic = "The inventory belongs to another target. Refresh the inventory before opening content."
            return
        }

        let planner = SpooledOutputSQLPlanner()
        let decoder = SpooledOutputSQLDecoder()
        let request = planner.preview(file.identity)
        let profileID = receipt.profileID
        let generation = UUID()
        spoolPreviewTask?.cancel()
        activeSpoolPreviewGeneration = generation
        spoolPreviewPhase = .loading
        spoolPreviewDiagnostic = "Opening bounded text records for \(file.identity.description). This IBM i content read can be audited."

        spoolPreviewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await transport.execute(request)
                try Task.checkCancellation()
                let preview = try decoder.decodePreview(result, identity: file.identity)
                guard !Task.isCancelled,
                      activeSpoolPreviewGeneration == generation,
                      selectedSpoolFileID == file.identity,
                      db2Receipt?.profileID == profileID,
                      db2Transport === transport else { return }
                spoolTextPreview = preview
                activeSpoolPreviewGeneration = nil
                spoolPreviewPhase = .ready
                spoolPreviewDiagnostic = preview.isComplete
                    ? "Loaded \(preview.records.count) ordered text record(s). This is not a page-layout or AFP/IPDS fidelity claim."
                    : "Loaded the first \(preview.records.count) ordered text record(s) at the configured bound."
                replaceSpoolReceipt(spoolReceipt(
                    .spooledFileData,
                    result: result,
                    request: request,
                    configuredLimit: planner.limits.maximumPreviewRecords
                ))
                showNotice("Exact spooled-file text loaded for local review.")
            } catch is CancellationError {
                guard activeSpoolPreviewGeneration == generation else { return }
                activeSpoolPreviewGeneration = nil
                spoolPreviewPhase = spoolTextPreview == nil ? .notLoaded : .failed
                spoolPreviewDiagnostic = "The spooled-file content request was cancelled. Any prior preview was retained for local review only."
            } catch {
                guard activeSpoolPreviewGeneration == generation,
                      db2Receipt?.profileID == profileID else { return }
                activeSpoolPreviewGeneration = nil
                spoolPreviewPhase = .failed
                spoolPreviewDiagnostic = "SPOOLED_FILE_DATA failed: \(incidentFailureReason(error))."
                replaceSpoolReceipt(spoolGap(.spooledFileData, request: request, error: error))
                showNotice("Spooled-file text preview failed. Inventory remains available.")
            }
        }
    }

    func freezeSpoolPreviewAsBaseline() {
        guard let preview = spoolTextPreview,
              preview.identity == selectedSpoolFileID else {
            spoolPreviewDiagnostic = "Load the selected exact text before freezing a local comparison baseline."
            return
        }
        spoolComparisonBaseline = preview
        spoolPreviewDiagnostic = "Frozen a device-memory baseline for \(preview.identity.description). No host data changed."
        showNotice("Local spool comparison baseline frozen in memory.")
    }

    func copySpoolPreviewText() {
        guard let preview = spoolTextPreview,
              preview.identity == selectedSpoolFileID else {
            spoolPreviewDiagnostic = "Load the selected exact text before copying it."
            return
        }
        terminalExport.copyString(spoolTextExportArtifact(preview))
        showNotice("Copied the local spooled-text artifact with exact identity and fidelity notes.")
    }

    func exportSpoolPreviewText() {
        guard let preview = spoolTextPreview,
              preview.identity == selectedSpoolFileID else {
            spoolPreviewDiagnostic = "Load the selected exact text before exporting it."
            return
        }
        terminalExport.saveText(
            spoolTextExportArtifact(preview),
            suggestedName: "\(preview.identity.file.value)-\(preview.identity.number)-spool",
            panelTitle: "Export Spooled Text Records"
        ) { [weak self] result in
            switch result {
            case .success(let url):
                self?.showNotice("Saved local spooled-text artifact to \(url.lastPathComponent).")
            case .failure(let error):
                self?.spoolPreviewDiagnostic = "Local text export failed: \(error.localizedDescription)"
                self?.showNotice("Spooled-text export failed.")
            }
        }
    }

    func prepareSpoolAssist() {
        guard let file = selectedSpooledFile else {
            spoolPreviewDiagnostic = "Select a spooled file before preparing reviewed Assist context."
            return
        }
        let preview = spoolTextPreview.flatMap { $0.identity == file.identity ? $0 : nil }
        do {
            let context = SpoolOutputAssistContextBuilder().build(
                snapshot: spoolOutputSnapshot,
                file: file,
                preview: preview,
                comparison: spoolTextComparison
            )
            let fragment = try AIContextFragment(
                kind: .spoolOutput,
                documentName: "\(file.identity.file.value)-\(file.identity.number)-spool-evidence.txt",
                language: "IBM i spooled-output evidence",
                sourceText: context
            )
            let bundle = try pinPreparedAssistantContext(
                fragment,
                label: "\(file.identity.file.value) #\(file.identity.number) spool evidence"
            )
            assistantInput = "Review this IBM i spooled-output evidence. Separate exact metadata and text records from inference, explain likely output or writer issues, flag fidelity and authority gaps, and propose only the smallest safe read-only checks."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("Spooled-output evidence pinned. Review the exact Context Shelf before sending.")
        } catch {
            spoolPreviewDiagnostic = "Assist context was blocked: \(incidentFailureReason(error))"
            showNotice("Spooled-output Assist context was blocked.")
        }
    }

    func importTransferSource(_ data: Data, fileName: String) {
        guard !transferValidationPhase.isBusy else { return }
        transferValidationPhase = .profiling
        transferDiagnostic = "Profiling bounded local UTF-8 delimited data. No host operation is running."
        do {
            let source = try DelimitedTextProfiler().parse(data, fileName: fileName)
            let report = TransferSchemaAnalyzer().validate(
                source: source,
                target: transferValidationReport.target
            )
            transferValidationReport = report
            transferValidationPhase = report.blockerCount == 0 && transferSchemaIsCurrent ? .ready : .blocked
            let schemaNote = transferSchemaIsCurrent
                ? "current target schema evidence"
                : "stale target schema evidence that must be refreshed"
            transferDiagnostic = "Profiled \(source.rowCount) local row(s) against \(report.target.columns.count) target column(s) using \(schemaNote): \(report.blockerCount) blocker(s), \(report.warningCount) warning(s), and zero host writes."
            showNotice("Local transfer dry run completed without changing target data.")
        } catch {
            transferValidationPhase = .failed
            transferDiagnostic = "Local transfer profiling was blocked: \(incidentFailureReason(error))"
            showNotice("The local transfer source was rejected before any host operation.")
        }
    }

    func editTransferTargetLibrary(_ value: String) {
        guard value != transferTargetLibraryText else { return }
        transferTargetLibraryText = value
        transferTargetDraftDidChange()
    }

    func editTransferTargetTable(_ value: String) {
        guard value != transferTargetTableText else { return }
        transferTargetTableText = value
        transferTargetDraftDidChange()
    }

    func restoreTransferReplay() {
        transferSchemaTask?.cancel()
        transferSchemaTask = nil
        activeTransferSchemaGeneration = nil
        transferValidationReport = DataTransferSamples.makeReport()
        transferTargetLibraryText = DataTransferSamples.targetTable.library.value
        transferTargetTableText = DataTransferSamples.targetTable.table.value
        transferValidationPhase = .localReplay
        transferSchemaPhase = .localReplay
        transferSchemaIsCurrent = true
        transferDiagnostic = "Restored the deterministic local CSV-to-table dry run. No host schema query or data write occurred."
        showNotice("Local transfer replay restored.")
    }

    func refreshTransferTargetSchema() {
        guard !transferSchemaPhase.isCollecting else { return }
        guard db2Phase.isConnected,
              let transport = db2Transport,
              let receipt = db2Receipt,
              receipt.accessMode == .readOnly else {
            transferDiagnostic = "Connect the reviewed read-only Db2 provider before refreshing target schema. No query was executed."
            showNotice("Target schema needs a read-only Db2 connection.")
            return
        }
        guard receipt.environment != .production else {
            transferSchemaPhase = .failed
            transferSchemaIsCurrent = false
            transferDiagnostic = "Target schema collection is blocked for PROD by this development policy."
            showNotice("Production transfer schema collection is blocked by policy.")
            return
        }

        let table: IBMTableIdentity
        do {
            table = IBMTableIdentity(
                library: try IBMSystemObjectName(transferTargetLibraryText),
                table: try IBMSystemObjectName(transferTargetTableText)
            )
        } catch {
            transferSchemaPhase = .failed
            transferSchemaIsCurrent = false
            transferDiagnostic = "Enter classic one-to-ten-character system library and table names before schema refresh."
            return
        }

        let planner = TransferSchemaSQLPlanner()
        let decoder = TransferSchemaSQLDecoder()
        let request = planner.targetSchema(table)
        let profileID = receipt.profileID
        let generation = UUID()
        transferSchemaTask?.cancel()
        activeTransferSchemaGeneration = generation
        transferSchemaPhase = .collecting
        transferSchemaIsCurrent = false
        transferDiagnostic = "Reading bounded QSYS2.SYSCOLUMNS2 metadata for \(table.description). Source rows stay local and no target data is read or written."

        transferSchemaTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await transport.execute(request)
                try Task.checkCancellation()
                let target = try decoder.decode(result, table: table, request: request)
                let report = TransferSchemaAnalyzer().validate(
                    source: transferValidationReport.source,
                    target: target,
                    targetElapsedMilliseconds: result.elapsedMilliseconds
                )
                guard !Task.isCancelled,
                      activeTransferSchemaGeneration == generation,
                      db2Receipt?.profileID == profileID,
                      db2Transport === transport else { return }
                transferValidationReport = report
                transferTargetLibraryText = table.library.value
                transferTargetTableText = table.table.value
                activeTransferSchemaGeneration = nil
                transferSchemaPhase = .ready
                transferSchemaIsCurrent = true
                transferValidationPhase = report.blockerCount == 0 ? .ready : .blocked
                transferDiagnostic = "Validated \(report.source.rowCount) local row(s) against \(target.columns.count) live schema column(s): \(report.blockerCount) blocker(s), \(report.warningCount) warning(s), and zero host writes."
                showNotice("Target schema refreshed read-only; the local dry run was recalculated.")
            } catch is CancellationError {
                guard activeTransferSchemaGeneration == generation else { return }
                activeTransferSchemaGeneration = nil
                transferSchemaPhase = transferValidationReport.target.isBundledReplay ? .localReplay : .failed
                transferDiagnostic = "Target schema refresh was cancelled. Prior local evidence was retained and is not current for the pending identity."
            } catch {
                guard activeTransferSchemaGeneration == generation,
                      db2Receipt?.profileID == profileID else { return }
                activeTransferSchemaGeneration = nil
                transferSchemaPhase = .failed
                transferSchemaIsCurrent = false
                transferDiagnostic = "SYSCOLUMNS2 schema collection failed: \(incidentFailureReason(error)). Prior local evidence was retained."
                showNotice("Target schema refresh failed before a complete schema was available.")
            }
        }
    }

    func exportTransferValidationReport() {
        let report = transferValidationReport
        let artifact = TransferValidationArtifactBuilder().build(
            report: report,
            schemaIsCurrent: transferSchemaIsCurrent
        )
        let baseName = report.source.fileName.split(separator: ".").dropLast().joined(separator: ".")
        terminalExport.saveText(
            artifact,
            suggestedName: (baseName.isEmpty ? report.source.fileName : baseName) + "-transfer-validation",
            panelTitle: "Export Data Transfer Validation Report"
        ) { [weak self] result in
            switch result {
            case .success(let url):
                self?.showNotice("Saved local transfer validation report to \(url.lastPathComponent).")
            case .failure(let error):
                self?.transferDiagnostic = "Local validation-report export failed: \(error.localizedDescription)"
                self?.showNotice("Transfer validation report export failed.")
            }
        }
    }

    func prepareTransferAssist() {
        do {
            let report = transferValidationReport
            let context = TransferAssistContextBuilder().build(
                report: report,
                schemaIsCurrent: transferSchemaIsCurrent
            )
            let fragment = try AIContextFragment(
                kind: .dataTransfer,
                documentName: "\(report.source.fileName)-transfer-validation.txt",
                language: "IBM i data-transfer validation evidence",
                sourceText: context
            )
            let bundle = try pinPreparedAssistantContext(
                fragment,
                label: "\(report.source.fileName) transfer validation"
            )
            assistantInput = "Review this IBM i data-transfer dry run. Explain every blocker and warning, separate proven schema facts from inference, and propose only safe validation steps. Do not propose executing a transfer."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("Transfer validation evidence pinned. Review the metadata-only Context Shelf before sending.")
        } catch {
            transferDiagnostic = "Transfer Assist context was blocked: \(incidentFailureReason(error))"
            showNotice("Transfer Assist context was blocked.")
        }
    }

    func restoreSystemHealthReplay() {
        systemHealthTask?.cancel()
        systemHealthTask = nil
        activeSystemHealthGeneration = nil
        systemHealthSnapshot = SystemHealthSamples.makeSnapshot()
        systemHealthPhase = .localReplay
        systemHealthDiagnostic = "Restored deterministic local health evidence. No host query, certificate access, or system change occurred."
        showNotice("Local System Health replay restored.")
    }

    func refreshSystemHealthEvidence() {
        guard !systemHealthPhase.isCollecting else { return }
        guard db2Phase.isConnected,
              let transport = db2Transport,
              let receipt = db2Receipt,
              receipt.accessMode == .readOnly else {
            systemHealthDiagnostic = "Connect the reviewed read-only Db2 provider before refreshing health evidence. No query was executed."
            showNotice("System Health needs a read-only Db2 connection.")
            return
        }
        guard receipt.environment != .production else {
            systemHealthPhase = .failed
            systemHealthDiagnostic = "Live System Health collection is blocked for PROD by this development policy."
            showNotice("Production System Health collection is blocked by policy.")
            return
        }

        let planner = SystemHealthSQLPlanner()
        let decoder = SystemHealthSQLDecoder(limits: planner.limits)
        let profileID = receipt.profileID
        let generation = UUID()
        systemHealthTask?.cancel()
        activeSystemHealthGeneration = generation
        systemHealthPhase = .collecting
        systemHealthDiagnostic = "Collecting five independent bounded read-only surfaces. The CPU sample may require *JOBCTL; certificates remain unavailable."

        systemHealthTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var status: SystemStatusEvidence?
                var cpu: SystemCPUActivitySample?
                var asps: [ASPHealthRecord] = []
                var systemLimits: [SystemLimitOccurrence] = []
                var ptfGroups: [PTFGroupRecord] = []
                var receipts: [SystemHealthEvidenceReceipt] = []

                let statusRequest = planner.systemStatus
                do {
                    let result = try await transport.execute(statusRequest)
                    try Task.checkCancellation()
                    status = try decoder.decodeSystemStatus(result)
                    receipts.append(systemHealthReceipt(.systemStatus, result: result, request: statusRequest))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    receipts.append(systemHealthGap(.systemStatus, request: statusRequest, error: error))
                }

                let activityRequest = planner.systemActivity
                do {
                    let result = try await transport.execute(activityRequest)
                    try Task.checkCancellation()
                    cpu = try decoder.decodeSystemActivity(result)
                    receipts.append(systemHealthReceipt(.systemActivity, result: result, request: activityRequest))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    receipts.append(systemHealthGap(.systemActivity, request: activityRequest, error: error))
                }

                let aspRequest = planner.aspInfo
                do {
                    let result = try await transport.execute(aspRequest)
                    try Task.checkCancellation()
                    asps = try decoder.decodeASPs(result)
                    receipts.append(systemHealthReceipt(.aspInfo, result: result, request: aspRequest))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    receipts.append(systemHealthGap(.aspInfo, request: aspRequest, error: error))
                }

                let limitRequest = planner.systemLimits
                do {
                    let result = try await transport.execute(limitRequest)
                    try Task.checkCancellation()
                    systemLimits = try decoder.decodeSystemLimits(result)
                    receipts.append(systemHealthReceipt(.systemLimits, result: result, request: limitRequest))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    receipts.append(systemHealthGap(.systemLimits, request: limitRequest, error: error))
                }

                let ptfRequest = planner.groupPTFInfo
                do {
                    let result = try await transport.execute(ptfRequest)
                    try Task.checkCancellation()
                    ptfGroups = try decoder.decodePTFGroups(result)
                    receipts.append(systemHealthReceipt(.groupPTFInfo, result: result, request: ptfRequest))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    receipts.append(systemHealthGap(.groupPTFInfo, request: ptfRequest, error: error))
                }

                receipts.append(SystemHealthEvidenceReceipt(
                    source: .certificateInfo,
                    rowCount: 0,
                    boundWasReached: false,
                    elapsedMilliseconds: nil,
                    queryFingerprint: AIContentFingerprint.sha256("CERTIFICATE_INFO INTENTIONALLY NOT EXECUTED"),
                    outcome: .unavailable("Separate privileged DCM capability; no store password or elevated authority was requested.")
                ))

                guard !Task.isCancelled,
                      activeSystemHealthGeneration == generation,
                      db2Receipt?.profileID == profileID,
                      db2Transport === transport else { return }
                let collectedCount = receipts.filter { $0.outcome.isCollected }.count
                activeSystemHealthGeneration = nil
                guard collectedCount > 0 else {
                    systemHealthPhase = .failed
                    systemHealthDiagnostic = "All five read-only System Health sources were unavailable. Prior evidence was retained."
                    showNotice("System Health collection returned no usable evidence.")
                    return
                }
                systemHealthSnapshot = SystemHealthSnapshot(
                    targetName: receipt.targetName,
                    capturedAt: Date(),
                    status: status,
                    cpu: cpu,
                    asps: asps,
                    limits: systemLimits,
                    ptfGroups: ptfGroups,
                    receipts: receipts
                )
                systemHealthPhase = .ready
                let gapCount = receipts.filter { !$0.outcome.isCollected }.count
                systemHealthDiagnostic = "Collected \(collectedCount) of 5 read-only health surfaces from \(receipt.targetName) with \(gapCount) documented capability gap(s) and zero host writes."
                showNotice("System Health evidence collected without changing the host.")
            } catch is CancellationError {
                guard activeSystemHealthGeneration == generation else { return }
                activeSystemHealthGeneration = nil
                systemHealthPhase = systemHealthSnapshot.isBundledReplay ? .localReplay : .failed
                systemHealthDiagnostic = "The local System Health collection task was cancelled. Prior evidence was retained."
            } catch {
                guard activeSystemHealthGeneration == generation else { return }
                activeSystemHealthGeneration = nil
                systemHealthPhase = .failed
                systemHealthDiagnostic = "System Health collection stopped locally: \(incidentFailureReason(error)). Prior evidence was retained."
            }
        }
    }

    func exportSystemHealthSnapshot() {
        let artifact = SystemHealthArtifactBuilder().build(snapshot: systemHealthSnapshot)
        terminalExport.saveText(
            artifact,
            suggestedName: "itelas-system-health-evidence",
            panelTitle: "Export System Health Evidence"
        ) { [weak self] result in
            switch result {
            case .success(let url):
                self?.showNotice("Saved local System Health evidence to \(url.lastPathComponent).")
            case .failure(let error):
                self?.systemHealthDiagnostic = "Local System Health export failed: \(error.localizedDescription)"
                self?.showNotice("System Health export failed.")
            }
        }
    }

    func prepareSystemHealthAssist() {
        do {
            let context = SystemHealthAssistContextBuilder().build(snapshot: systemHealthSnapshot)
            let fragment = try AIContextFragment(
                kind: .systemHealth,
                documentName: "system-health-evidence.txt",
                language: "IBM i system-health evidence",
                sourceText: context
            )
            let bundle = try pinPreparedAssistantContext(fragment, label: "System Health evidence")
            assistantInput = "Review this bounded read-only IBM i health evidence. Separate observations from the local score, treat system-limit rows as high-water occurrences rather than trends, identify evidence gaps, and propose only safe read-only checks."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("System Health evidence pinned. Review the metadata-only Context Shelf before sending.")
        } catch {
            systemHealthDiagnostic = "System Health Assist context was blocked: \(incidentFailureReason(error))"
            showNotice("System Health Assist context was blocked.")
        }
    }

    func restoreObjectImpactReplay() {
        objectImpactTask?.cancel()
        objectImpactTask = nil
        activeObjectImpactGeneration = nil
        objectImpactSnapshot = ObjectImpactSamples.makeSnapshot()
        objectImpactLibraryText = objectImpactSnapshot.target.library.value
        objectImpactNameText = objectImpactSnapshot.target.name.value
        objectImpactType = objectImpactSnapshot.target.type
        objectImpactPhase = .localReplay
        objectImpactDiagnostic = "Restored deterministic direct dependency evidence. No host query or system change occurred."
        showNotice("Local Dependency Atlas replay restored.")
    }

    func objectImpactTargetDraftDidChange() {
        objectImpactTask?.cancel()
        objectImpactTask = nil
        activeObjectImpactGeneration = nil
        let target = try? currentObjectImpactIdentity()
        let replayMatches = objectImpactSnapshot.isBundledReplay && target == objectImpactSnapshot.target
        objectImpactPhase = replayMatches ? .localReplay : .failed
        objectImpactDiagnostic = target == nil
            ? "Enter valid 1–10 character IBM i system names before collecting. No query was executed."
            : "Object identity changed. Collect exact bounded evidence before using this atlas for review."
    }

    func refreshObjectImpactEvidence() {
        guard !objectImpactPhase.isCollecting else { return }
        let target: IBMObjectIdentity
        do {
            target = try currentObjectImpactIdentity()
        } catch {
            objectImpactPhase = .failed
            objectImpactDiagnostic = "Enter valid 1–10 character IBM i system names before collecting. No query was executed."
            showNotice("Dependency collection needs an exact object identity.")
            return
        }
        guard db2Phase.isConnected,
              let transport = db2Transport,
              let receipt = db2Receipt,
              receipt.accessMode == .readOnly else {
            objectImpactDiagnostic = "Connect the reviewed read-only Db2 provider before collecting dependency evidence. No query was executed."
            showNotice("Dependency Atlas needs a read-only Db2 connection.")
            return
        }
        guard receipt.environment != .production else {
            objectImpactPhase = .failed
            objectImpactDiagnostic = "Live Dependency Atlas collection is blocked for PROD by this development policy."
            showNotice("Production dependency collection is blocked by policy.")
            return
        }

        let planner = ObjectImpactSQLPlanner(target: target)
        let decoder = ObjectImpactSQLDecoder(limits: planner.limits)
        let profileID = receipt.profileID
        let generation = UUID()
        objectImpactTask?.cancel()
        activeObjectImpactGeneration = generation
        objectImpactPhase = .collecting
        objectImpactDiagnostic = "Collecting six independent exact or tightly bounded read-only surfaces. Program-reference coverage remains an explicit gap."

        objectImpactTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var metadata: ObjectImpactMetadata?
                var edges: [ObjectImpactEdge] = []
                var receipts: [ObjectImpactEvidenceReceipt] = []

                for (source, request) in planner.liveRequests {
                    do {
                        let result = try await transport.execute(request)
                        try Task.checkCancellation()
                        switch source {
                        case .objectStatistics:
                            metadata = try decoder.decodeMetadata(result, target: target)
                        case .boundServiceProgramInfo:
                            edges += try decoder.decodeBoundServicePrograms(result)
                        case .boundModuleInfo:
                            edges += try decoder.decodeBoundModules(result)
                        case .bindingDirectoryInfo:
                            edges += try decoder.decodeBindingDirectories(result)
                        case .sysroutines:
                            edges += try decoder.decodeSQLRoutines(result)
                        case .sysviewdep:
                            edges += try decoder.decodeViewDependencies(result)
                        case .programReferences:
                            break
                        }
                        receipts.append(objectImpactReceipt(source, result: result, request: request))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        receipts.append(objectImpactGap(source, request: request, error: error))
                    }
                }

                receipts.append(ObjectImpactEvidenceReceipt(
                    source: .programReferences,
                    rowCount: 0,
                    boundWasReached: false,
                    elapsedMilliseconds: nil,
                    queryFingerprint: AIContentFingerprint.sha256("PROGRAM REFERENCES INTENTIONALLY NOT COLLECTED"),
                    outcome: .unavailable("DSPPGMREF output requires creating a host outfile; this read-only milestone performs no host writes.")
                ))

                guard !Task.isCancelled,
                      activeObjectImpactGeneration == generation,
                      db2Receipt?.profileID == profileID,
                      db2Transport === transport,
                      (try? currentObjectImpactIdentity()) == target else { return }
                let collectedCount = receipts.filter { $0.outcome.isCollected }.count
                activeObjectImpactGeneration = nil
                guard collectedCount > 0 else {
                    objectImpactPhase = .failed
                    objectImpactDiagnostic = "All six read-only dependency sources were unavailable. Prior evidence was retained."
                    showNotice("Dependency collection returned no usable evidence.")
                    return
                }
                objectImpactSnapshot = ObjectImpactSnapshot(
                    targetName: receipt.targetName,
                    target: target,
                    capturedAt: Date(),
                    metadata: metadata,
                    edges: edges,
                    receipts: receipts
                )
                objectImpactPhase = .ready
                let gapCount = receipts.filter { !$0.outcome.isCollected }.count
                objectImpactDiagnostic = "Collected \(collectedCount) of 6 read-only surfaces and \(edges.count) direct edge(s) from \(receipt.targetName), with \(gapCount) documented gap(s) and zero host writes."
                showNotice("Dependency evidence collected without changing the host.")
            } catch is CancellationError {
                guard activeObjectImpactGeneration == generation else { return }
                activeObjectImpactGeneration = nil
                objectImpactPhase = objectImpactSnapshot.isBundledReplay ? .localReplay : .failed
                objectImpactDiagnostic = "The local dependency collection task was cancelled. Prior evidence was retained."
            } catch {
                guard activeObjectImpactGeneration == generation else { return }
                activeObjectImpactGeneration = nil
                objectImpactPhase = .failed
                objectImpactDiagnostic = "Dependency collection stopped locally: \(incidentFailureReason(error)). Prior evidence was retained."
            }
        }
    }

    func exportObjectImpactSnapshot() {
        let snapshot = objectImpactSnapshot
        let artifact = ObjectImpactArtifactBuilder().build(snapshot: snapshot)
        terminalExport.saveText(
            artifact,
            suggestedName: "itelas-\(snapshot.target.library.value.lowercased())-\(snapshot.target.name.value.lowercased())-impact",
            panelTitle: "Export Dependency and Impact Evidence"
        ) { [weak self] result in
            switch result {
            case .success(let url):
                self?.showNotice("Saved local dependency evidence to \(url.lastPathComponent).")
            case .failure(let error):
                self?.objectImpactDiagnostic = "Local dependency-evidence export failed: \(error.localizedDescription)"
                self?.showNotice("Dependency evidence export failed.")
            }
        }
    }

    func prepareObjectImpactAssist() {
        do {
            let context = ObjectImpactAssistContextBuilder().build(snapshot: objectImpactSnapshot)
            let fragment = try AIContextFragment(
                kind: .objectImpact,
                documentName: "object-impact-evidence.txt",
                language: "IBM i dependency evidence",
                sourceText: context
            )
            let bundle = try pinPreparedAssistantContext(fragment, label: "Dependency Atlas evidence")
            assistantInput = "Review this bounded IBM i dependency evidence. Preserve BOUND, CATALOG, and CANDIDATE distinctions, identify every evidence gap, and propose only read-only verification steps. Do not claim a change is safe."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("Dependency evidence pinned. Review the identity-withheld Context Shelf before sending.")
        } catch {
            objectImpactDiagnostic = "Dependency Assist context was blocked: \(incidentFailureReason(error))"
            showNotice("Dependency Assist context was blocked.")
        }
    }

    func restoreAuthorityInsightReplay() {
        authorityInsightTask?.cancel()
        authorityInsightTask = nil
        activeAuthorityInsightGeneration = nil
        authorityInsightSnapshot = AuthorityInsightSamples.makeSnapshot()
        authoritySubjectText = authorityInsightSnapshot.subject.description
        authorityLibraryText = authorityInsightSnapshot.target.library.value
        authorityObjectText = authorityInsightSnapshot.target.name.value
        authorityObjectType = authorityInsightSnapshot.target.type
        authoritySimulationRemovedPathIDs = []
        authorityInsightPhase = .localReplay
        authorityInsightDiagnostic = "Restored deterministic authority evidence. No host query, grant, revoke, profile change, authorization-list change, or collection change occurred."
        showNotice("Local Authority Path Atlas replay restored.")
    }

    func authorityInsightScopeDraftDidChange() {
        authorityInsightTask?.cancel()
        authorityInsightTask = nil
        activeAuthorityInsightGeneration = nil
        authoritySimulationRemovedPathIDs = []
        let scope = try? currentAuthorityInsightScope()
        let replayMatches = authorityInsightSnapshot.isBundledReplay
            && scope?.subject == authorityInsightSnapshot.subject
            && scope?.target == authorityInsightSnapshot.target
        authorityInsightPhase = replayMatches ? .localReplay : .failed
        authorityInsightDiagnostic = scope == nil
            ? "Enter a valid profile plus exact 1–10 character IBM i library and object names. No query was executed."
            : "Authority scope changed. Collect independent read-only evidence before using this atlas for review."
    }

    func refreshAuthorityInsightEvidence() {
        guard !authorityInsightPhase.isCollecting else { return }
        let scope: (subject: AuthoritySubject, target: IBMObjectIdentity)
        do {
            scope = try currentAuthorityInsightScope()
        } catch {
            authorityInsightPhase = .failed
            authorityInsightDiagnostic = "Enter a valid profile plus exact 1–10 character IBM i library and object names. No query was executed."
            showNotice("Authority collection needs an exact subject and object scope.")
            return
        }
        guard db2Phase.isConnected,
              let transport = db2Transport,
              let connectionReceipt = db2Receipt,
              connectionReceipt.accessMode == .readOnly else {
            authorityInsightDiagnostic = "Connect the reviewed read-only Db2 provider before collecting authority evidence. No query was executed."
            showNotice("Authority Path Atlas needs a read-only Db2 connection.")
            return
        }
        guard connectionReceipt.environment != .production else {
            authorityInsightPhase = .failed
            authorityInsightDiagnostic = "Live Authority Path Atlas collection is blocked for PROD by this development policy."
            showNotice("Production authority collection is blocked by policy.")
            return
        }

        let planner = AuthoritySQLPlanner(subject: scope.subject, target: scope.target)
        let decoder = AuthoritySQLDecoder(limits: planner.limits)
        let profileID = connectionReceipt.profileID
        let generation = UUID()
        authorityInsightTask?.cancel()
        activeAuthorityInsightGeneration = generation
        authorityInsightPhase = .collecting
        authorityInsightDiagnostic = "Collecting five independent bounded read-only authority surfaces. Effective resolution remains an explicit review gap."

        authorityInsightTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var profile: AuthorityProfileSnapshot?
                var groups: [AuthorityGroupMembership] = []
                var objectGrants: [AuthorityObjectGrant] = []
                var authorizationListGrants: [AuthorityAuthorizationListGrant] = []
                var observations: [AuthorityRuntimeObservation] = []
                var receipts: [AuthorityEvidenceReceipt] = []

                for (source, request) in planner.initialRequests {
                    do {
                        let result = try await transport.execute(request)
                        try Task.checkCancellation()
                        switch source {
                        case .userInfo:
                            profile = try decoder.decodeProfile(result, subject: scope.subject)
                        case .groupProfileEntries:
                            groups = try decoder.decodeGroups(result, subject: scope.subject)
                        case .objectPrivileges:
                            objectGrants = try decoder.decodeObjectGrants(result, target: scope.target)
                        case .authorityCollection:
                            observations = try decoder.decodeRuntimeObservations(
                                result,
                                subject: scope.subject,
                                target: scope.target
                            )
                        case .authorizationListUserInfo, .effectiveAuthorityResolution:
                            break
                        }
                        receipts.append(authorityInsightReceipt(source, result: result, request: request))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        receipts.append(authorityInsightGap(source, request: request, error: error))
                    }
                }

                let authorizationLists = Set(objectGrants.compactMap(\.authorizationList))
                if authorizationLists.count == 1,
                   let listName = authorizationLists.first,
                   let authorizationList = try? IBMSystemObjectName(listName) {
                    let request = planner.authorizationListUserInfo(authorizationList)
                    do {
                        let result = try await transport.execute(request)
                        try Task.checkCancellation()
                        authorizationListGrants = try decoder.decodeAuthorizationListGrants(
                            result,
                            authorizationList: authorizationList
                        )
                        receipts.append(authorityInsightReceipt(
                            .authorizationListUserInfo,
                            result: result,
                            request: request
                        ))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        receipts.append(authorityInsightGap(
                            .authorizationListUserInfo,
                            request: request,
                            error: error
                        ))
                    }
                } else if authorizationLists.isEmpty {
                    receipts.append(AuthorityEvidenceReceipt(
                        source: .authorizationListUserInfo,
                        rowCount: 0,
                        boundWasReached: false,
                        elapsedMilliseconds: nil,
                        queryFingerprint: AIContentFingerprint.sha256("NO CALLER-VISIBLE AUTHORIZATION LIST IDENTITY"),
                        outcome: .unavailable("No caller-visible authorization-list identity was available from OBJECT_PRIVILEGES, so no authorization-list entry query was issued.")
                    ))
                } else {
                    receipts.append(AuthorityEvidenceReceipt(
                        source: .authorizationListUserInfo,
                        rowCount: 0,
                        boundWasReached: false,
                        elapsedMilliseconds: nil,
                        queryFingerprint: AIContentFingerprint.sha256("CONFLICTING AUTHORIZATION LIST IDENTITIES"),
                        outcome: .unavailable("OBJECT_PRIVILEGES returned conflicting authorization-list identities for the exact object.")
                    ))
                }

                receipts.append(AuthorityEvidenceReceipt(
                    source: .effectiveAuthorityResolution,
                    rowCount: 0,
                    boundWasReached: false,
                    elapsedMilliseconds: nil,
                    queryFingerprint: AIContentFingerprint.sha256("NO SINGLE EFFECTIVE AUTHORITY PROOF"),
                    outcome: .unavailable("No single read-only service proves every function-usage, adopted-authority, cached-check, and unexercised runtime path.")
                ))

                guard !Task.isCancelled,
                      activeAuthorityInsightGeneration == generation,
                      db2Receipt?.profileID == profileID,
                      db2Transport === transport,
                      let currentScope = try? currentAuthorityInsightScope(),
                      currentScope.subject == scope.subject,
                      currentScope.target == scope.target else { return }
                let collectedCount = receipts.filter { $0.outcome.isCollected }.count
                activeAuthorityInsightGeneration = nil
                guard collectedCount > 0 else {
                    authorityInsightPhase = .failed
                    authorityInsightDiagnostic = "All read-only authority sources were unavailable. Prior evidence was retained."
                    showNotice("Authority collection returned no usable evidence.")
                    return
                }
                let snapshot = AuthorityInsightSnapshot(
                    targetName: connectionReceipt.targetName,
                    subject: scope.subject,
                    target: scope.target,
                    capturedAt: Date(),
                    profile: profile,
                    groups: groups,
                    objectGrants: objectGrants,
                    authorizationListGrants: authorizationListGrants,
                    observations: observations,
                    receipts: receipts
                )
                authorityInsightSnapshot = snapshot
                authoritySimulationRemovedPathIDs = []
                authorityInsightPhase = .ready
                authorityInsightDiagnostic = "Collected \(collectedCount) of 6 authority surfaces, explained \(snapshot.assessment.reachableStaticPathCount) reachable static path(s), retained \(snapshot.observations.count) runtime observation(s), documented \(snapshot.gaps.count) gap(s), and performed zero host writes."
                showNotice("Authority evidence collected without changing the host.")
            } catch is CancellationError {
                guard activeAuthorityInsightGeneration == generation else { return }
                activeAuthorityInsightGeneration = nil
                authorityInsightPhase = authorityInsightSnapshot.isBundledReplay ? .localReplay : .failed
                authorityInsightDiagnostic = "The local authority collection task was cancelled. Prior evidence was retained."
            } catch {
                guard activeAuthorityInsightGeneration == generation else { return }
                activeAuthorityInsightGeneration = nil
                authorityInsightPhase = .failed
                authorityInsightDiagnostic = "Authority collection stopped locally: \(incidentFailureReason(error)). Prior evidence was retained."
            }
        }
    }

    func toggleAuthoritySimulationPath(_ pathID: String) {
        guard authorityInsightSnapshot.staticPaths.contains(where: { $0.id == pathID }) else { return }
        if authoritySimulationRemovedPathIDs.contains(pathID) {
            authoritySimulationRemovedPathIDs.remove(pathID)
        } else {
            authoritySimulationRemovedPathIDs.insert(pathID)
        }
        let result = authorityInsightSnapshot.simulate(removing: authoritySimulationRemovedPathIDs)
        authorityInsightDiagnostic = "Local what-if excludes \(result.removedPathIDs.count) evidence path(s); \(result.remainingPaths.filter(\.grantsAccess).count) reported-access path(s) remain. No host change occurred."
    }

    func clearAuthoritySimulation() {
        authoritySimulationRemovedPathIDs = []
        authorityInsightDiagnostic = "Local what-if reset. Evidence remains unchanged and no host change occurred."
    }

    func exportAuthorityInsightSnapshot() {
        let snapshot = authorityInsightSnapshot
        let artifact = AuthorityArtifactBuilder().build(snapshot: snapshot)
        terminalExport.saveText(
            artifact,
            suggestedName: "itelas-\(snapshot.subject.description.lowercased())-\(snapshot.target.library.value.lowercased())-\(snapshot.target.name.value.lowercased())-authority",
            panelTitle: "Export Authority Path Evidence"
        ) { [weak self] result in
            switch result {
            case .success(let url):
                self?.showNotice("Saved local authority evidence to \(url.lastPathComponent).")
            case .failure(let error):
                self?.authorityInsightDiagnostic = "Local authority-evidence export failed: \(error.localizedDescription)"
                self?.showNotice("Authority evidence export failed.")
            }
        }
    }

    func prepareAuthorityInsightAssist() {
        do {
            let context = AuthorityAssistContextBuilder().build(snapshot: authorityInsightSnapshot)
            let fragment = try AIContextFragment(
                kind: .authorityReview,
                documentName: "authority-review-context.txt",
                language: "IBM i authority evidence",
                sourceText: context
            )
            let bundle = try pinPreparedAssistantContext(fragment, label: "Authority Path Atlas evidence")
            assistantInput = "Review this bounded IBM i authority evidence. Keep static and observed paths separate, preserve every evidence gap, flag data-change surfaces, and propose only read-only verification steps. Do not claim effective authority or recommend an automatic grant or revoke."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("Authority evidence pinned. Review the identity-withheld Context Shelf before sending.")
        } catch {
            authorityInsightDiagnostic = "Authority Assist context was blocked: \(incidentFailureReason(error))"
            showNotice("Authority Assist context was blocked.")
        }
    }

    func restoreRunbookReplay() {
        runbookLibrary.removeAll {
            if case .localImport = $0.origin { true } else { false }
        }
        selectedRunbookID = RunbookSamples.selectedID
        selectedRunbookStepNumber = RunbookSamples.selectedStepNumber
        let replay = RunbookSamples.makeResolution()
        runbookResolution = replay
        runbookParameterValues = replay.parameterValues
        runbookTargetName = replay.targetName
        runbookEnvironment = replay.environment
        runbookOperatorReason = ""
        runbookApprovals = replay.approvals
        runbookPhase = .localReplay
        runbookDiagnostic = "Restored deterministic local blueprint resolution. No command, query, approval, schedule, or host action occurred."
        showNotice("Local runbook replay restored without contacting a host.")
    }

    func selectRunbook(_ id: String) {
        guard let item = runbookLibrary.first(where: { $0.id == id }) else { return }
        guard let blueprint = item.blueprint else {
            runbookDiagnostic = "\(item.title) remains a blueprint study. Import a validated runbook document or restore the implemented compile replay."
            showNotice("That runbook remains a design study; no action was performed.")
            return
        }
        selectedRunbookID = item.id
        selectedRunbookStepNumber = blueprint.steps.first?.number ?? 1
        runbookTargetName = item.origin == .bundledReplay
            ? "DEV ORION"
            : (selectedProfile?.name ?? "LOCAL TARGET")
        runbookEnvironment = blueprint.allowedEnvironments.first(where: { $0 != .production })
            ?? blueprint.allowedEnvironments[0]
        runbookParameterValues = RunbookSamples.defaultValues(for: blueprint)
        runbookOperatorReason = ""
        runbookApprovals = []
        runbookResolution = nil

        let missing = blueprint.parameters.filter {
            $0.required && runbookParameterValues[$0.key] == nil
        }
        if missing.isEmpty {
            validateSelectedRunbook()
        } else {
            runbookPhase = .draft
            runbookDiagnostic = "Enter \(missing.count) required typed parameter value(s), then validate locally. No host action is available."
        }
    }

    func selectRunbookStep(_ number: Int) {
        guard runbookResolution?.steps.contains(where: { $0.number == number }) == true else { return }
        selectedRunbookStepNumber = number
    }

    func editRunbookParameter(_ key: RunbookParameterKey, value: String) {
        runbookParameterValues[key] = value
        invalidateRunbookPlan(reason: "A typed parameter changed. Revalidate the exact resolved plan before review.")
    }

    func editRunbookTargetName(_ value: String) {
        guard value != runbookTargetName else { return }
        runbookTargetName = value
        invalidateRunbookPlan(reason: "The target identity changed. Prior resolution and local approvals are stale.")
    }

    func editRunbookEnvironment(_ environment: IBMEnvironment) {
        guard environment != runbookEnvironment else { return }
        runbookEnvironment = environment
        invalidateRunbookPlan(reason: "The environment changed. Prior resolution and local approvals are stale.")
    }

    func editRunbookOperatorReason(_ value: String) {
        guard value != runbookOperatorReason else { return }
        runbookOperatorReason = value
        runbookResolution = nil
        runbookPhase = .draft
        runbookDiagnostic = "The operator reason changed. Revalidate locally; plan-bound approvals remain unchanged."
    }

    func validateSelectedRunbook() {
        guard let blueprint = selectedRunbookBlueprint else {
            runbookPhase = .failed
            runbookResolution = nil
            runbookDiagnostic = "Select an implemented or imported blueprint before validation."
            return
        }
        runbookPhase = .validating
        do {
            let reason = runbookOperatorReason.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolution = try RunbookResolver().resolve(
                blueprint: blueprint,
                targetName: runbookTargetName,
                environment: runbookEnvironment,
                values: runbookParameterValues,
                operatorReason: reason.isEmpty ? nil : reason,
                approvals: runbookApprovals,
                resolvedAt: Date(),
                isBundledReplay: selectedRunbookItem?.origin == .bundledReplay
            )
            runbookResolution = resolution
            if !resolution.steps.contains(where: { $0.number == selectedRunbookStepNumber }) {
                selectedRunbookStepNumber = resolution.steps.first?.number ?? 1
            }
            runbookPhase = selectedRunbookItem?.origin == .bundledReplay ? .localReplay : .ready
            runbookDiagnostic = "Resolved \(resolution.steps.count) typed step(s) with \(resolution.assessment.openCheckCount) review or blocked check(s). Execution remains unavailable and no host was contacted."
            showNotice("Runbook validated locally. Nothing was executed or approved.")
        } catch {
            runbookResolution = nil
            runbookPhase = .failed
            runbookDiagnostic = "Local runbook validation was blocked: \(incidentFailureReason(error))"
            showNotice("Runbook validation stopped before any host operation.")
        }
    }

    func importRunbookBlueprint(_ data: Data, fileName: String) {
        do {
            let blueprint = try RunbookBlueprintCodec().decode(data)
            let itemID = "\(blueprint.id.rawValue)-LOCAL-\(UUID().uuidString.prefix(8))"
            let item = RunbookCatalogItem(
                id: itemID,
                title: blueprint.name,
                category: "LOCAL IMPORT",
                stepCount: blueprint.steps.count,
                status: "VALIDATE",
                origin: .localImport(fileName: fileName),
                blueprint: blueprint
            )
            runbookLibrary.insert(item, at: 0)
            selectRunbook(itemID)
            runbookDiagnostic = runbookResolution == nil
                ? "Imported \(fileName) locally. Complete its typed parameters, then validate; no host was contacted."
                : "Imported and validated \(fileName) locally. Execution remains unavailable and no host was contacted."
            showNotice("Runbook blueprint imported locally.")
        } catch {
            runbookPhase = .failed
            runbookDiagnostic = "Local runbook import was blocked: \(incidentFailureReason(error))"
            showNotice("The local runbook document was rejected.")
        }
    }

    func copySelectedRunbookAction() {
        guard let action = selectedResolvedRunbookStep?.resolvedAction else {
            runbookDiagnostic = "The selected local step has no command or SQL preview to copy."
            return
        }
        terminalExport.copyString(action)
        showNotice("Resolved preview copied locally. Nothing was submitted.")
    }

    func recordRunbookLocalAttestation(role: RunbookApprovalRole, reviewerAlias: String) {
        guard let runbookResolution else {
            runbookDiagnostic = "Validate the exact plan before recording a local review attestation."
            return
        }
        do {
            let attestation = try RunbookLocalApproval(
                role: role,
                reviewerAlias: reviewerAlias,
                planFingerprint: runbookResolution.planFingerprint,
                recordedAt: Date()
            )
            runbookApprovals.removeAll { $0.role == role }
            runbookApprovals.append(attestation)
            validateSelectedRunbook()
            runbookDiagnostic = "Recorded a plan-bound local \(role.label.lowercased()) attestation. Identity was not cryptographically verified; no approval or host action occurred."
            showNotice("Local review attestation recorded for this exact plan.")
        } catch {
            runbookDiagnostic = "Local review attestation was blocked: \(incidentFailureReason(error))"
            showNotice("Local review attestation was not recorded.")
        }
    }

    func removeRunbookLocalAttestation(role: RunbookApprovalRole) {
        let priorCount = runbookApprovals.count
        runbookApprovals.removeAll { $0.role == role }
        guard runbookApprovals.count != priorCount else { return }
        validateSelectedRunbook()
        runbookDiagnostic = "Removed the local \(role.label.lowercased()) attestation and revalidated the review plan. No host action occurred."
        showNotice("Local review attestation removed.")
    }

    func exportRunbookReviewArtifact() {
        guard let runbookResolution else {
            runbookDiagnostic = "Validate the current blueprint before exporting its review artifact."
            return
        }
        let artifact = RunbookArtifactBuilder().build(runbookResolution)
        terminalExport.saveText(
            artifact,
            suggestedName: "itelas-\(runbookResolution.blueprint.id.rawValue.lowercased())-review",
            panelTitle: "Export Runbook Review Artifact"
        ) { [weak self] result in
            switch result {
            case .success(let url):
                self?.showNotice("Saved local runbook review to \(url.lastPathComponent).")
            case .failure(let error):
                self?.runbookDiagnostic = "Local runbook export failed: \(error.localizedDescription)"
                self?.showNotice("Runbook review export failed.")
            }
        }
    }

    func prepareRunbookAssist() {
        guard let runbookResolution else {
            runbookDiagnostic = "Validate the current blueprint before preparing Assist context."
            return
        }
        do {
            let context = RunbookAssistContextBuilder().build(runbookResolution)
            let fragment = try AIContextFragment(
                kind: .runbook,
                documentName: "runbook-review-context.txt",
                language: "IBM i runbook contract",
                sourceText: context
            )
            let bundle = try pinPreparedAssistantContext(fragment, label: "Runbook review contract")
            assistantInput = "Review this identity-withheld IBM i runbook contract. Identify missing preconditions, evidence, stop conditions, approval roles, and rollback questions. Do not approve, execute, or reconstruct withheld values."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("Runbook evidence pinned. Review the identity-withheld Context Shelf before sending.")
        } catch {
            runbookDiagnostic = "Runbook Assist context was blocked: \(incidentFailureReason(error))"
            showNotice("Runbook Assist context was blocked.")
        }
    }

    private func invalidateRunbookPlan(reason: String) {
        runbookResolution = nil
        runbookApprovals = []
        runbookPhase = .draft
        runbookDiagnostic = reason + " No host action is available."
    }

    func prepareSQLAssistReview() {
        isAssistantVisible = true
        latestAIEditProposal = nil
        latestAIProposalExplanation = nil
        aiProposalDiagnostic = nil
        aiProposalWasApplied = false
        let hasSelection = sqlSelection.flatMap { try? $0.selectedText(in: sqlText) }?.isEmpty == false
        aiReviewDraft = AIReviewDraft(
            target: .sqlDraft,
            documentName: selectedSQLService.map { "\($0.id).sql" } ?? "active-query.sql",
            language: "SQL",
            sourceText: sqlText,
            selection: hasSelection ? sqlSelection : nil,
            scope: hasSelection ? .selection : .wholeDraft,
            question: "Review this Db2 for i query for correctness, read-only safety, likely access-path issues, and the smallest useful improvement."
        )
        isAIReviewDossierPresented = true
        showNotice("Assist dossier prepared. Review the exact SQL context before sending.")
    }

    func flushLocalDrafts() {
        flushSourceScratch()
        sqlSaveTask?.cancel()
        sqlSaveTask = nil
        persistSQLScratch(sqlText)
    }

    func updateSourceCursor(line: Int, column: Int) {
        sourceCursorLine = max(1, line)
        sourceCursorColumn = max(1, column)
    }

    func updateSourceSelection(_ range: NSRange) {
        sourceCursorUTF16 = min(max(0, range.location), sourceDocument.text.utf16.count)
        sourceSelection = range.length > 0
            ? AITextSelection(locationUTF16: range.location, lengthUTF16: range.length)
            : nil
    }

    var sourceWorkspaceSearchResults: [SourceWorkspaceSearchResult] {
        let query = sourceWorkspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return sourceWorkspaceIndex.documents.prefix(200).map { document in
                SourceWorkspaceSearchResult(
                    kind: .file,
                    relativePath: document.relativePath,
                    line: 1,
                    column: 1,
                    label: document.displayName,
                    detail: "\(document.format.rawValue) · \(document.lineCount) lines",
                    excerpt: document.relativePath,
                    score: 0
                )
            }
        }
        return currentSourceWorkspaceSearchReport?.results ?? []
    }

    var currentSourceWorkspaceIndexBuildReport: SourceWorkspaceIndexBuildReport? {
        guard let sourceWorkspaceIndexBuildReport,
              sourceWorkspaceIndexBuildReport.isCurrent(for: sourceWorkspaceIndex) else { return nil }
        return sourceWorkspaceIndexBuildReport
    }

    var sourceWorkspaceIndexRefreshStatusLabel: String {
        if sourceWorkspaceIndexPhase.isIndexing { return "INDEXING CHANGES" }
        guard let report = currentSourceWorkspaceIndexBuildReport else {
            return sourceWorkspaceIndexPhase.label
        }
        if !report.isIncremental {
            return "FULL · \(report.analyzedDocumentCount) ANALYZED"
        }
        return "\(report.reusedAnalysisCount) REUSED · \(report.analyzedDocumentCount) ANALYZED"
    }

    var sourceWorkspaceIndexRefreshReceiptLabel: String {
        guard let report = currentSourceWorkspaceIndexBuildReport else { return "DELTA NONE" }
        let duration = sourceWorkspaceIndexDurationMilliseconds.map { " · \($0) MS" } ?? ""
        return "DELTA \(report.shortFingerprint)\(duration)"
    }

    var sourceWorkspaceHasPendingDrift: Bool {
        guard sourceWorkspaceDriftPhase != .localReplay else { return false }
        return sourceWorkspaceDriftReceipt?.hasPendingSignals == true
            || sourceWorkspaceDriftPhase == .pending
            || sourceWorkspaceDriftPhase == .paused
            || sourceWorkspaceDriftPhase == .failed
    }

    var sourceWorkspaceEvidenceIsCurrent: Bool {
        if sourceWorkspaceDriftPhase == .localReplay { return true }
        return sourceWorkspaceIndexPhase == .ready
            && sourceWorkspaceDriftPhase == .watching
            && !sourceWorkspaceHasPendingDrift
            && sourceWorkspaceRootURL?.standardizedFileURL == sourceWorkspaceDriftRootURL?.standardizedFileURL
    }

    var sourceWorkspaceDriftStatusLabel: String {
        if sourceWorkspaceIndexPhase.isIndexing, sourceWorkspaceHasPendingDrift {
            return "VERIFYING \(sourceWorkspaceDriftReceipt?.uniquePathCount ?? 0) PATHS"
        }
        if let receipt = sourceWorkspaceDriftReceipt, sourceWorkspaceDriftPhase != .watching {
            return "\(sourceWorkspaceDriftPhase.label) · \(receipt.uniquePathCount) PATHS"
        }
        return sourceWorkspaceDriftPhase.label
    }

    var sourceWorkspaceDriftReceiptLabel: String {
        guard let receipt = sourceWorkspaceDriftReceipt else { return "SIGNAL NONE" }
        return "SIGNAL \(receipt.shortFingerprint) · \(receipt.rawEventCount) EVENTS"
    }

    var currentSourceWorkspaceSearchReport: SourceWorkspaceSearchReport? {
        guard let sourceWorkspaceSearchReport,
              sourceWorkspaceSearchReport.isCurrent(
                for: sourceWorkspaceIndex,
                query: sourceWorkspaceSearchQuery
              ) else { return nil }
        return sourceWorkspaceSearchReport
    }

    var sourceWorkspaceSearchReportIsCurrent: Bool {
        currentSourceWorkspaceSearchReport != nil
    }

    var sourceWorkspaceSearchStatusLabel: String {
        if sourceWorkspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "BROWSE"
        }
        if sourceWorkspaceSearchPhase.isSearching { return "SEARCHING" }
        if sourceWorkspaceHasPendingDrift { return "FROZEN · VERIFY FIRST" }
        guard let sourceWorkspaceSearchReport = currentSourceWorkspaceSearchReport else {
            return sourceWorkspaceSearchPhase.label
        }
        let duration = sourceWorkspaceSearchDurationMilliseconds.map { " · \($0) MS" } ?? ""
        return "\(sourceWorkspaceSearchReport.completion.label)\(duration)"
    }

    var selectedSourceWorkspaceDocument: SourceWorkspaceDocumentIndex? {
        guard let selectedSourceWorkspacePath else { return nil }
        return sourceWorkspaceIndex.document(at: selectedSourceWorkspacePath)
    }

    var selectedSourceWorkspaceOutboundDependencies: [SourceWorkspaceDependencyEdge] {
        guard let selectedSourceWorkspacePath else { return [] }
        return sourceWorkspaceIndex.outboundDependencies(for: selectedSourceWorkspacePath)
    }

    var selectedSourceWorkspaceInboundDependencies: [SourceWorkspaceDependencyEdge] {
        guard let selectedSourceWorkspacePath else { return [] }
        return sourceWorkspaceIndex.inboundDependencies(for: selectedSourceWorkspacePath)
    }

    var currentSourceWorkspaceIncludeChain: SourceWorkspaceIncludeChain? {
        guard sourceWorkspaceEvidenceIsCurrent,
              let selectedSourceWorkspacePath,
              let sourceWorkspaceIncludeChain,
              sourceWorkspaceIncludeChain.isCurrent(
                for: sourceWorkspaceIndex,
                rootPath: selectedSourceWorkspacePath
              ) else { return nil }
        return sourceWorkspaceIncludeChain
    }

    var sourceWorkspaceIncludeChainStatusLabel: String {
        if sourceWorkspaceHasPendingDrift { return "FROZEN · VERIFY FIRST" }
        guard let chain = currentSourceWorkspaceIncludeChain else { return "MAP NEEDED" }
        return "\(chain.completion.label) · \(chain.documents.count) DOCS"
    }

    var selectedSourceWorkspaceIncludeBoundary: SourceWorkspaceIncludeBoundary? {
        guard let chain = currentSourceWorkspaceIncludeChain else { return nil }
        if let selectedSourceWorkspaceIncludeBoundaryID,
           let selected = chain.boundaries.first(where: { $0.id == selectedSourceWorkspaceIncludeBoundaryID }) {
            return selected
        }
        return chain.boundaries.first
    }

    var sourceWorkspaceDependencyReviewIsCurrent: Bool {
        sourceWorkspaceEvidenceIsCurrent
            && sourceWorkspaceDependencyReview?.isCurrent(for: sourceWorkspaceIndex) == true
    }

    var sourceWorkspaceUsesSelectedFolder: Bool {
        sourceWorkspaceRootURL != nil && sourceWorkspaceIndexPhase == .ready
    }

    var sourceWorkspaceHostIncludeCandidates: [SourceWorkspaceDependencyEdge] {
        selectedSourceWorkspaceOutboundDependencies.filter {
            ($0.kind == .copy || $0.kind == .include) && $0.resolution == .hostBacked
        }
    }

    var selectedSourceWorkspaceHostIncludeCandidate: SourceWorkspaceDependencyEdge? {
        sourceWorkspaceHostIncludeCandidates.first
    }

    var sourceWorkspaceHostIncludeNeedsLibrary: Bool {
        guard let candidate = selectedSourceWorkspaceHostIncludeCandidate,
              case .member(let library, _, _) = candidate.target else { return false }
        return library == nil
    }

    var sourceWorkspaceHostIncludeReviewIsCurrent: Bool {
        sourceWorkspaceEvidenceIsCurrent
            && sourceWorkspaceHostIncludeReview?.isCurrent(for: sourceWorkspaceIndex) == true
    }

    var sourceWorkspaceHostIncludeCanRead: Bool {
        sourceWorkspaceHostIncludePhase == .reviewReady
            && sourceWorkspaceHostIncludeAttested
            && sourceWorkspaceHostIncludeReviewIsCurrent
    }

    var sourceWorkspaceHostIncludeProviderLabel: String {
        sourceWorkspaceHostIncludeReview?.target.providerKind.label
            ?? selectedSourceWorkspaceHostIncludeCandidate.map { candidate in
                switch candidate.target {
                case .member: "SOURCE MEMBER"
                case .ifsPath: "IFS PATH"
                default: "UNAVAILABLE"
                }
            }
            ?? sourceWorkspaceHostIncludeContent?.target.providerKind.label
            ?? "NO TARGET"
    }

    var selectedSourceWorkspaceCompileRun: CompileRunRecord? {
        guard let sourceWorkspaceCompileRunID else { return nil }
        return compileRuns.first(where: { $0.id == sourceWorkspaceCompileRunID })
    }

    var sourceWorkspaceCompileReviewIsCurrent: Bool {
        guard sourceWorkspaceEvidenceIsCurrent,
              let run = selectedSourceWorkspaceCompileRun,
              let review = sourceWorkspaceCompileReview else { return false }
        return review.isCurrent(for: sourceWorkspaceIndex, compileRunFingerprint: run.fingerprint)
    }

    var sourceWorkspaceCompileAttachmentIsCurrent: Bool {
        guard sourceWorkspaceEvidenceIsCurrent,
              let attachment = sourceWorkspaceCompileAttachment,
              let run = compileRuns.first(where: { $0.fingerprint == attachment.compileRunFingerprint }) else {
            return false
        }
        return attachment.isCurrent(for: sourceWorkspaceIndex, compileRunFingerprint: run.fingerprint)
    }

    var sourceWorkspaceCompileCanAttach: Bool {
        sourceWorkspaceCompileAttested && sourceWorkspaceCompileReviewIsCurrent
    }

    var sourceWorkspaceCompileStatusLabel: String {
        if sourceWorkspaceCompileAttachment != nil {
            return sourceWorkspaceCompileAttachmentIsCurrent ? "ATTACHED" : "STALE ATTACHMENT"
        }
        return sourceWorkspaceCompileReviewIsCurrent ? "REVIEW READY" : "EVIDENCE GAP"
    }

    var sourceWorkspaceCompileDiagnosticsForSelectedDocument: [SourceWorkspaceCompileDiagnosticLink] {
        guard sourceWorkspaceCompileAttachmentIsCurrent,
              let selectedSourceWorkspacePath else { return [] }
        return sourceWorkspaceCompileAttachment?.diagnostics(for: selectedSourceWorkspacePath) ?? []
    }

    var selectedSourceWorkspaceCompileDiagnostic: SourceWorkspaceCompileDiagnosticLink? {
        guard let selectedSourceWorkspaceCompileDiagnosticID else { return nil }
        let source = sourceWorkspaceCompileAttachmentIsCurrent
            ? sourceWorkspaceCompileAttachment
            : sourceWorkspaceCompileReview
        return source?.diagnostics.first(where: { $0.id == selectedSourceWorkspaceCompileDiagnosticID })
    }

    func sourceWorkspaceCompileCandidates(
        for file: CompileEvidenceSourceFile
    ) -> [SourceWorkspaceCompileMappingCandidate] {
        SourceWorkspaceCompileEvidenceMatcher().candidates(for: file, in: sourceWorkspaceIndex)
    }

    func presentSourceWorkspaceCompileEvidence() {
        if sourceWorkspaceCompileRunID == nil {
            sourceWorkspaceCompileRunID = compileRuns.first?.id
        }
        if sourceWorkspaceCompileObservedRelease.isEmpty {
            sourceWorkspaceCompileObservedRelease = selectedSourceWorkspaceCompileRun?.observedHostRelease?.value ?? ""
        }
        rebuildSourceWorkspaceCompileReview(resetMappings: sourceWorkspaceCompileMappings.isEmpty)
        isSourceWorkspaceCompileEvidencePresented = true
    }

    func selectSourceWorkspaceCompileRun(_ id: UUID) {
        guard let run = compileRuns.first(where: { $0.id == id }) else { return }
        sourceWorkspaceCompileRunID = id
        sourceWorkspaceCompileObservedRelease = run.observedHostRelease?.value ?? ""
        sourceWorkspaceCompileAttested = false
        selectedSourceWorkspaceCompileDiagnosticID = nil
        rebuildSourceWorkspaceCompileReview(resetMappings: true)
    }

    func updateSourceWorkspaceCompileObservedRelease(_ value: String) {
        sourceWorkspaceCompileObservedRelease = value
        sourceWorkspaceCompileAttested = false
        rebuildSourceWorkspaceCompileReview(resetMappings: false)
    }

    func selectSourceWorkspaceCompileMapping(
        compileFileID: String,
        documentPath: String
    ) {
        guard selectedSourceWorkspaceCompileRun?.evidence.sourceFiles.contains(where: {
            SourceWorkspaceCompileEvidenceMatcher.fileID(for: $0) == compileFileID
        }) == true,
        sourceWorkspaceIndex.document(at: documentPath) != nil else { return }
        sourceWorkspaceCompileMappings[compileFileID] = documentPath
        sourceWorkspaceCompileAttested = false
        rebuildSourceWorkspaceCompileReview(resetMappings: false)
    }

    func attachReviewedSourceWorkspaceCompileEvidence() {
        guard sourceWorkspaceCompileCanAttach,
              let review = sourceWorkspaceCompileReview else {
            sourceWorkspaceCompileDiagnostic = "Review and attest the current file mapping and target-release context before attachment."
            showNotice(sourceWorkspaceCompileDiagnostic)
            return
        }
        sourceWorkspaceCompileAttachment = review
        selectedSourceWorkspaceCompileDiagnosticID = review.diagnostics.first(where: \.canNavigate)?.id
            ?? review.diagnostics.first?.id
        sourceWorkspaceCompileDiagnostic = "Attached \(review.diagnostics.count) compiler diagnostic(s) to \(review.mappings.count) exact indexed document(s). No compile or host action occurred."
        showNotice("Compiler evidence attached locally to the current source index.")
    }

    func removeSourceWorkspaceCompileEvidenceAttachment() {
        sourceWorkspaceCompileAttachment = nil
        selectedSourceWorkspaceCompileDiagnosticID = sourceWorkspaceCompileReview?.diagnostics.first?.id
        sourceWorkspaceCompileDiagnostic = "Removed the local compiler-evidence attachment. Source and retained compile runs were unchanged."
        showNotice("Compiler evidence attachment removed locally.")
    }

    @discardableResult
    func openSourceWorkspaceCompileDiagnostic(_ id: String) -> Bool {
        guard sourceWorkspaceCompileAttachmentIsCurrent,
              let diagnostic = sourceWorkspaceCompileAttachment?.diagnostics.first(where: { $0.id == id }) else {
            sourceWorkspaceCompileDiagnostic = "That diagnostic attachment is stale. Review the current index and compile evidence again."
            showNotice(sourceWorkspaceCompileDiagnostic)
            return false
        }
        guard diagnostic.canNavigate else {
            sourceWorkspaceCompileDiagnostic = "Navigation blocked: \(diagnostic.navigationState.label.lowercased()). The diagnostic remains visible as evidence."
            showNotice(sourceWorkspaceCompileDiagnostic)
            return false
        }
        let result = SourceWorkspaceSearchResult(
            kind: .text,
            relativePath: diagnostic.documentPath,
            line: diagnostic.range.startLine,
            column: diagnostic.range.startColumn,
            label: diagnostic.messageID,
            detail: "Compiler severity \(diagnostic.severity)",
            excerpt: diagnostic.message,
            score: 0
        )
        selectedSourceWorkspacePath = diagnostic.documentPath
        selectedSourceWorkspaceCompileDiagnosticID = diagnostic.id
        let opened = openSourceWorkspaceResult(result)
        if opened {
            isSourceWorkspaceCompileEvidencePresented = false
            sourceWorkspaceCompileDiagnostic = "Opened the exact retained source revision at \(diagnostic.messageID) line \(diagnostic.range.startLine)."
        }
        return opened
    }

    private func rebuildSourceWorkspaceCompileReview(resetMappings: Bool) {
        guard let run = selectedSourceWorkspaceCompileRun else {
            sourceWorkspaceCompileMappings = [:]
            sourceWorkspaceCompileReview = nil
            sourceWorkspaceCompileDiagnostic = "No retained compile run is available."
            return
        }
        do {
            let releaseEvidence = try CompileTargetReleaseEvidence(
                commandText: "\(run.recipe.compiler)\n\(run.recipe.commandPreview)",
                observedHostRelease: sourceWorkspaceCompileObservedRelease
            )
            if resetMappings {
                sourceWorkspaceCompileMappings = [:]
                for file in run.evidence.sourceFiles {
                    let fileID = SourceWorkspaceCompileEvidenceMatcher.fileID(for: file)
                    let candidates = sourceWorkspaceCompileCandidates(for: file)
                    if let first = candidates.first,
                       candidates.filter({ $0.rank == first.rank }).count == 1 {
                        sourceWorkspaceCompileMappings[fileID] = first.documentPath
                    }
                }
            } else {
                let validFileIDs = Set(run.evidence.sourceFiles.map {
                    SourceWorkspaceCompileEvidenceMatcher.fileID(for: $0)
                })
                sourceWorkspaceCompileMappings = sourceWorkspaceCompileMappings.filter {
                    validFileIDs.contains($0.key) && sourceWorkspaceIndex.document(at: $0.value) != nil
                }
            }
            var sourceFingerprints: [String: String] = [:]
            if let sourceRevision = run.sourceRevision {
                let exactFiles = run.evidence.sourceFiles.filter {
                    $0.path.caseInsensitiveCompare(run.recipe.sourceIdentity) == .orderedSame
                }
                if exactFiles.count == 1, let file = exactFiles.first {
                    sourceFingerprints[SourceWorkspaceCompileEvidenceMatcher.fileID(for: file)] = sourceRevision
                } else if run.evidence.sourceFiles.count == 1, let file = run.evidence.sourceFiles.first {
                    sourceFingerprints[SourceWorkspaceCompileEvidenceMatcher.fileID(for: file)] = sourceRevision
                }
            }
            let review = try ReviewedSourceWorkspaceCompileEvidence(
                index: sourceWorkspaceIndex,
                evidence: run.evidence,
                compileRunFingerprint: run.fingerprint,
                releaseEvidence: releaseEvidence,
                selectedMappings: sourceWorkspaceCompileMappings,
                sourceFingerprintsByFileID: sourceFingerprints
            )
            sourceWorkspaceCompileReview = review
            selectedSourceWorkspaceCompileDiagnosticID = review.diagnostics.first(where: \.canNavigate)?.id
                ?? review.diagnostics.first?.id
            sourceWorkspaceCompileDiagnostic = "Review \(review.shortFingerprint) maps \(review.mappings.count) compile file(s), with \(review.exactNavigationCount) exact navigable diagnostic(s)."
        } catch {
            sourceWorkspaceCompileReview = nil
            selectedSourceWorkspaceCompileDiagnosticID = nil
            sourceWorkspaceCompileDiagnostic = error.localizedDescription
        }
    }

    var sourceWorkspaceRenameReviewIsCurrent: Bool {
        guard sourceWorkspaceEvidenceIsCurrent,
              let plan = sourceWorkspaceRenamePlan,
              let review = sourceWorkspaceRenameReview else { return false }
        return review.isCurrent(plan: plan, index: sourceWorkspaceIndex)
    }

    var sourceWorkspaceRenameCanApply: Bool {
        sourceWorkspaceUsesSelectedFolder
            && sourceWorkspaceRenameApplyPhase == .reviewReady
            && sourceWorkspaceRenameAttested
            && sourceWorkspaceRenameReviewIsCurrent
    }

    var openedSourceWorkspaceSnapshotIsCurrent: Bool {
        guard sourceWorkspaceEvidenceIsCurrent,
              let openedSourceWorkspaceSnapshotPath,
              let receipt = sourceDocument.remoteRevision,
              let document = sourceWorkspaceIndex.document(at: openedSourceWorkspaceSnapshotPath) else {
            return false
        }
        return document.contentFingerprint == receipt
    }

    var reviewedSourceWorkspaceCompletionSymbols: [SourceWorkspaceCompletionSymbol] {
        guard sourceWorkspaceEvidenceIsCurrent,
              let sourceWorkspaceDependencyReview else { return [] }
        return (try? sourceWorkspaceIndex.reviewedCompletionSymbols(using: sourceWorkspaceDependencyReview)) ?? []
    }

    func presentSourceWorkspaceIndex() {
        if selectedSourceWorkspacePath == nil {
            selectedSourceWorkspacePath = sourceWorkspaceIndex.documents.first?.relativePath
        }
        refreshSourceWorkspaceIncludeChain()
        ensureSourceWorkspaceSearch()
        isSourceWorkspaceIndexPresented = true
    }

    func refreshSourceWorkspaceIncludeChain() {
        guard sourceWorkspaceEvidenceIsCurrent,
              let selectedSourceWorkspacePath else {
            sourceWorkspaceIncludeChain = nil
            selectedSourceWorkspaceIncludeBoundaryID = nil
            return
        }
        do {
            let chain = try sourceWorkspaceIndex.includeChain(for: selectedSourceWorkspacePath)
            sourceWorkspaceIncludeChain = chain
            if !chain.boundaries.contains(where: { $0.id == selectedSourceWorkspaceIncludeBoundaryID }) {
                selectedSourceWorkspaceIncludeBoundaryID = chain.boundaries.first?.id
            }
        } catch {
            sourceWorkspaceIncludeChain = nil
            selectedSourceWorkspaceIncludeBoundaryID = nil
            sourceWorkspaceIndexDiagnostic = "Include map stopped: \(error.localizedDescription)"
        }
    }

    func presentSourceWorkspaceIncludeChain() {
        guard sourceWorkspaceEvidenceIsCurrent else {
            sourceWorkspaceIndexDiagnostic = "Include mapping is locked until pending workspace signals are verified."
            showNotice(sourceWorkspaceIndexDiagnostic)
            return
        }
        refreshSourceWorkspaceIncludeChain()
        guard let chain = currentSourceWorkspaceIncludeChain else {
            showNotice("Build a current include map before opening the navigator.")
            return
        }
        isSourceWorkspaceIncludeChainPresented = true
        sourceWorkspaceIndexDiagnostic = "Include map \(chain.shortFingerprint) traces \(chain.directives.count) lexical directive(s) across \(chain.documents.count) exact indexed document(s); no provider or host was contacted."
    }

    func selectSourceWorkspaceIncludeBoundary(_ boundaryID: String) {
        guard currentSourceWorkspaceIncludeChain?.boundaries.contains(where: { $0.id == boundaryID }) == true else {
            return
        }
        selectedSourceWorkspaceIncludeBoundaryID = boundaryID
    }

    func useSourceWorkspaceIncludeClosure() {
        guard sourceWorkspaceEvidenceIsCurrent,
              let chain = currentSourceWorkspaceIncludeChain else {
            sourceWorkspaceIndexDiagnostic = "Exact closure staging is locked until the include map and workspace evidence are current."
            showNotice(sourceWorkspaceIndexDiagnostic)
            return
        }
        sourceWorkspaceDependencySelection = Set(chain.exactDocumentPaths)
        sourceWorkspaceDependencyReview = nil
        sourceWorkspaceIndexDiagnostic = "Staged \(chain.documents.count) exact include-map document(s) for separate completion review; \(chain.boundaries.count) visible boundary item(s) stayed excluded."
        showNotice("Exact include closure staged. Completion review remains a separate gate.")
    }

    @discardableResult
    func openSourceWorkspaceIncludeDirective(_ directive: SourceWorkspaceIncludeDirective) -> Bool {
        openSourceWorkspaceResult(SourceWorkspaceSearchResult(
            kind: .reference,
            relativePath: directive.sourcePath,
            line: directive.range.startLine,
            column: directive.range.startColumn,
            label: directive.targetLabel,
            detail: "\(directive.kind.label) · \(directive.resolution.label)",
            excerpt: "\(directive.kind.label) \(directive.targetLabel)",
            score: 0
        ))
    }

    @discardableResult
    func openSourceWorkspaceIncludeBoundary(_ boundary: SourceWorkspaceIncludeBoundary) -> Bool {
        openSourceWorkspaceResult(SourceWorkspaceSearchResult(
            kind: .reference,
            relativePath: boundary.sourcePath,
            line: boundary.range.startLine,
            column: boundary.range.startColumn,
            label: boundary.targetLabel,
            detail: boundary.kind.label,
            excerpt: boundary.detail,
            score: 0
        ))
    }

    func updateSourceWorkspaceSearchQuery(_ value: String) {
        sourceWorkspaceSearchQuery = value
        scheduleSourceWorkspaceSearch(debounce: true)
    }

    func refreshSourceWorkspaceSearch() {
        scheduleSourceWorkspaceSearch(debounce: false)
    }

    func ensureSourceWorkspaceSearch() {
        let query = sourceWorkspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            sourceWorkspaceSearchPhase = .idle
            sourceWorkspaceSearchReport = nil
            sourceWorkspaceSearchDurationMilliseconds = nil
            sourceWorkspaceSearchDiagnostic = "Browse mode shows the first 200 exact indexed paths without running a text query."
            return
        }
        guard !sourceWorkspaceSearchReportIsCurrent,
              !sourceWorkspaceSearchPhase.isSearching else { return }
        scheduleSourceWorkspaceSearch(debounce: false)
    }

    func cancelSourceWorkspaceSearch() {
        activeSourceWorkspaceSearchGeneration = nil
        sourceWorkspaceSearchTask?.cancel()
        sourceWorkspaceSearchTask = nil
        sourceWorkspaceSearchPhase = sourceWorkspaceSearchReportIsCurrent ? .ready : .idle
        sourceWorkspaceSearchDiagnostic = "Search cancelled. The exact source index and any current prior receipt were unchanged."
    }

    private func scheduleSourceWorkspaceSearch(debounce: Bool) {
        sourceWorkspaceSearchTask?.cancel()
        sourceWorkspaceSearchTask = nil
        let query = sourceWorkspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            activeSourceWorkspaceSearchGeneration = nil
            sourceWorkspaceSearchReport = nil
            sourceWorkspaceSearchPhase = .idle
            sourceWorkspaceSearchDurationMilliseconds = nil
            sourceWorkspaceSearchDiagnostic = "Browse mode shows exact indexed paths. No background query is running."
            return
        }

        let generation = UUID()
        let frozenIndex = sourceWorkspaceIndex
        activeSourceWorkspaceSearchGeneration = generation
        sourceWorkspaceSearchPhase = .searching
        sourceWorkspaceSearchDurationMilliseconds = nil
        sourceWorkspaceSearchDiagnostic = "Searching index \(frozenIndex.shortFingerprint) off the main interface. Superseded query generations are discarded."
        sourceWorkspaceSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if debounce { try await Task.sleep(for: .milliseconds(140)) }
                let startedAt = Date()
                let worker = Task.detached(priority: .userInitiated) {
                    try frozenIndex.searchReport(query)
                }
                let report = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled,
                      activeSourceWorkspaceSearchGeneration == generation,
                      sourceWorkspaceIndex.fingerprint == frozenIndex.fingerprint,
                      sourceWorkspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                    return
                }
                sourceWorkspaceSearchReport = report
                sourceWorkspaceSearchDurationMilliseconds = max(
                    0,
                    Int(Date().timeIntervalSince(startedAt) * 1_000)
                )
                sourceWorkspaceSearchPhase = .ready
                sourceWorkspaceSearchTask = nil
                activeSourceWorkspaceSearchGeneration = nil
                sourceWorkspaceSearchDiagnostic = "Search \(report.shortFingerprint) returned \(report.results.count) result(s) from \(report.examinedDocumentCount)/\(report.scopeDocumentCount) indexed file(s); coverage is \(report.completion.label.lowercased())."
            } catch is CancellationError {
                guard activeSourceWorkspaceSearchGeneration == generation else { return }
                sourceWorkspaceSearchTask = nil
                activeSourceWorkspaceSearchGeneration = nil
                sourceWorkspaceSearchPhase = sourceWorkspaceSearchReportIsCurrent ? .ready : .idle
                sourceWorkspaceSearchDiagnostic = "Search cancelled. The source index was unchanged."
            } catch {
                guard activeSourceWorkspaceSearchGeneration == generation else { return }
                sourceWorkspaceSearchTask = nil
                activeSourceWorkspaceSearchGeneration = nil
                sourceWorkspaceSearchPhase = .failed
                sourceWorkspaceSearchDurationMilliseconds = nil
                sourceWorkspaceSearchDiagnostic = error.localizedDescription
            }
        }
    }

    func scanSourceWorkspace(at url: URL) {
        guard !sourceWorkspaceRenameApplyPhase.isApplying else {
            showNotice("Wait for the reviewed rename batch to finish before refreshing the index.")
            return
        }
        let standardizedURL = url.standardizedFileURL
        let isSameRoot = sourceWorkspaceRootURL?.standardizedFileURL == standardizedURL
        let isSameDriftRoot = sourceWorkspaceDriftRootURL?.standardizedFileURL == standardizedURL
        if !isSameDriftRoot {
            startSourceWorkspaceDriftMonitoring(at: standardizedURL, resetSignals: true)
        } else if sourceWorkspaceDriftMonitor == nil, sourceWorkspaceDriftPhase != .paused {
            startSourceWorkspaceDriftMonitoring(at: standardizedURL, resetSignals: false)
        }
        sourceWorkspaceDriftAutoRefreshTask?.cancel()
        sourceWorkspaceDriftAutoRefreshTask = nil
        activeSourceWorkspaceDriftAutoRefreshGeneration = nil
        let driftBoundary = sourceWorkspaceDriftObservations.map(\.eventID).max() ?? 0
        let requiresFullVerification = sourceWorkspaceDriftReceipt?.requiresFullVerification == true
        sourceWorkspaceIndexTask?.cancel()
        activeSourceWorkspaceSearchGeneration = nil
        sourceWorkspaceSearchTask?.cancel()
        sourceWorkspaceSearchTask = nil
        sourceWorkspaceHostIncludeTask?.cancel()
        sourceWorkspaceHostIncludeTask = nil
        activeSourceWorkspaceHostIncludeGeneration = nil
        sourceWorkspaceHostIncludeReview = nil
        sourceWorkspaceHostIncludeAttested = false
        isSourceWorkspaceHostIncludeReviewPresented = false
        sourceWorkspaceHostIncludePhase = sourceWorkspaceHostIncludeContent == nil ? .idle : .installed
        let previousIndex = isSameRoot && !requiresFullVerification ? sourceWorkspaceIndex : nil
        if !isSameRoot {
            sourceWorkspaceRenameApplyReceipt = nil
        }
        let generation = UUID()
        activeSourceWorkspaceIndexGeneration = generation
        sourceWorkspaceIndexPhase = .indexing
        sourceWorkspaceIndexDiagnostic = previousIndex == nil
            ? "Reading and analyzing the bounded operator-selected folder for a full local index."
            : "Re-reading exact source bytes and reusing only analysis whose path, format, and content still match."
        let accessStarted = standardizedURL.startAccessingSecurityScopedResource()
        sourceWorkspaceIndexTask = Task { @MainActor [weak self] in
            defer {
                if accessStarted { standardizedURL.stopAccessingSecurityScopedResource() }
            }
            guard let self else { return }
            do {
                let startedAt = Date()
                let worker = Task.detached(priority: .userInitiated) {
                    try SourceWorkspaceIndexService().scan(
                        rootURL: standardizedURL,
                        previousIndex: previousIndex
                    )
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, activeSourceWorkspaceIndexGeneration == generation else { return }
                let durationMilliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                installSourceWorkspaceScanResult(
                    result,
                    preservingDependencyReview: true,
                    durationMilliseconds: durationMilliseconds
                )
                completeSourceWorkspaceDriftVerification(through: driftBoundary)
                sourceWorkspaceRenamePlan = nil
                clearSourceWorkspaceRenameReview()
                activeSourceWorkspaceIndexGeneration = nil
                sourceWorkspaceIndexDiagnostic = "Indexed \(result.index.fileCount) files and \(result.index.symbolCount) symbols locally; reused \(result.buildReport.reusedAnalysisCount) exact analysis snapshot(s), analyzed \(result.buildReport.analyzedDocumentCount), removed \(result.buildReport.removedDocumentCount), and skipped \(result.index.skippedFiles.count)."
                showNotice("Local source index refreshed. No source content was sent or written.")
            } catch is CancellationError {
                guard activeSourceWorkspaceIndexGeneration == generation else { return }
                activeSourceWorkspaceIndexGeneration = nil
                sourceWorkspaceIndexPhase = sourceWorkspaceRootURL == nil ? .localReplay : .ready
                sourceWorkspaceIndexDiagnostic = "Indexing was cancelled. The previous local index remains visible."
            } catch {
                guard activeSourceWorkspaceIndexGeneration == generation else { return }
                activeSourceWorkspaceIndexGeneration = nil
                sourceWorkspaceIndexPhase = .failed
                sourceWorkspaceIndexDiagnostic = error.localizedDescription
                if !isSameRoot {
                    stopSourceWorkspaceDriftMonitoring(clearSignals: true)
                    sourceWorkspaceDriftPhase = .failed
                    sourceWorkspaceDriftDiagnostic = "Recursive monitoring stopped because the selected source root could not be indexed."
                }
                showNotice("Source indexing stopped before a complete bounded index was available.")
            }
        }
    }

    func refreshSourceWorkspaceIndex() {
        guard let sourceWorkspaceRootURL else {
            showNotice("Choose a local source folder before refreshing the index.")
            return
        }
        scanSourceWorkspace(at: sourceWorkspaceRootURL)
    }

    func setSourceWorkspaceAutoRefreshEnabled(_ enabled: Bool) {
        sourceWorkspaceAutoRefreshEnabled = enabled
        if enabled {
            scheduleSourceWorkspaceDriftAutoRefresh()
        } else {
            sourceWorkspaceDriftAutoRefreshTask?.cancel()
            sourceWorkspaceDriftAutoRefreshTask = nil
            activeSourceWorkspaceDriftAutoRefreshGeneration = nil
            sourceWorkspaceDriftDiagnostic = sourceWorkspaceHasPendingDrift
                ? "Automatic verification is off; exactness gates remain locked until Verify now runs."
                : "Automatic verification is off; recursive path monitoring remains active."
        }
    }

    func pauseSourceWorkspaceDriftMonitoring() {
        guard sourceWorkspaceDriftRootURL != nil,
              sourceWorkspaceDriftPhase != .localReplay else { return }
        stopSourceWorkspaceDriftMonitoring(clearSignals: false)
        let nextEventID = nextSourceWorkspaceDriftEventID()
        if let gap = try? SourceWorkspaceDriftObservation(
            relativePath: nil,
            kinds: [.rescanRequired],
            eventID: nextEventID
        ) {
            recordSourceWorkspaceDrift([gap])
        }
        sourceWorkspaceDriftPhase = .paused
        sourceWorkspaceDriftDiagnostic = "Recursive monitoring is paused; exactness gates stay locked until monitoring resumes and exact bytes are verified."
    }

    func resumeSourceWorkspaceDriftMonitoring() {
        guard let rootURL = sourceWorkspaceDriftRootURL,
              sourceWorkspaceDriftPhase == .paused else { return }
        startSourceWorkspaceDriftMonitoring(at: rootURL, resetSignals: false)
        if sourceWorkspaceDriftMonitor != nil {
            if sourceWorkspaceDriftObservations.isEmpty {
                let nextEventID = nextSourceWorkspaceDriftEventID()
                if let gap = try? SourceWorkspaceDriftObservation(
                    relativePath: nil,
                    kinds: [.rescanRequired],
                    eventID: nextEventID
                ) {
                    recordSourceWorkspaceDrift([gap])
                }
            } else {
                sourceWorkspaceDriftPhase = .pending
                scheduleSourceWorkspaceDriftAutoRefresh()
            }
        }
    }

    func verifySourceWorkspaceDriftNow() {
        guard let sourceWorkspaceRootURL else {
            showNotice("Choose a local source folder before verifying workspace signals.")
            return
        }
        scanSourceWorkspace(at: sourceWorkspaceRootURL)
    }

    func recordSourceWorkspaceDrift(_ observations: [SourceWorkspaceDriftObservation]) {
        guard !observations.isEmpty,
              sourceWorkspaceDriftPhase != .localReplay else { return }
        let maximumRawObservations = SourceWorkspaceDriftLimits().maximumRawEvents
        let combined = sourceWorkspaceDriftObservations + observations
        if combined.count <= maximumRawObservations {
            sourceWorkspaceDriftObservations = combined
        } else {
            let overflowCount = combined.count - (maximumRawObservations - 1)
            let dropped = combined.prefix(overflowCount)
            let retained = combined.suffix(maximumRawObservations - 1)
            let overflowRawCount = dropped.reduce(0) { $0 + $1.rawEventCount }
            let overflowEventID = dropped.map(\.eventID).max() ?? 0
            let overflow = try? SourceWorkspaceDriftObservation(
                relativePath: nil,
                kinds: [.rescanRequired],
                rawEventCount: overflowRawCount,
                eventID: overflowEventID
            )
            sourceWorkspaceDriftObservations = overflow.map { [$0] + retained } ?? Array(retained)
        }
        sourceWorkspaceDriftReceipt = SourceWorkspaceDriftReceipt(
            baselineIndexFingerprint: sourceWorkspaceIndex.fingerprint,
            observations: sourceWorkspaceDriftObservations
        )
        if sourceWorkspaceDriftPhase != .paused, sourceWorkspaceDriftPhase != .failed {
            sourceWorkspaceDriftPhase = .pending
        }
        let receipt = sourceWorkspaceDriftReceipt
        sourceWorkspaceDriftDiagnostic = "Observed \(receipt?.uniquePathCount ?? 0) recursive path signal(s) across \(receipt?.rawEventCount ?? 0) raw event(s). No source byte was read; exactness gates are locked."
        if sourceWorkspaceHostIncludePhase.isReading {
            invalidateSourceWorkspaceHostIncludeRead(
                reason: "Host include intake stopped because local workspace evidence changed before installation."
            )
        }
        scheduleSourceWorkspaceDriftAutoRefresh()
    }

    private func startSourceWorkspaceDriftMonitoring(at url: URL, resetSignals: Bool) {
        let standardizedURL = url.standardizedFileURL
        if sourceWorkspaceDriftMonitor != nil,
           sourceWorkspaceDriftRootURL?.standardizedFileURL == standardizedURL {
            return
        }
        stopSourceWorkspaceDriftMonitoring(clearSignals: resetSignals)
        sourceWorkspaceDriftRootURL = standardizedURL
        if resetSignals {
            sourceWorkspaceDriftObservations = []
            sourceWorkspaceDriftReceipt = nil
        }

        let generation = UUID()
        activeSourceWorkspaceDriftGeneration = generation
        let accessStarted = standardizedURL.startAccessingSecurityScopedResource()
        if accessStarted { sourceWorkspaceDriftSecurityScopeURL = standardizedURL }
        let monitor = SourceWorkspaceDriftMonitor(
            rootURL: standardizedURL,
            initialFallbackEventID: sourceWorkspaceDriftObservations.map(\.eventID).max() ?? 0
        ) { [weak self] observations in
            Task { @MainActor [weak self] in
                guard let self,
                      self.activeSourceWorkspaceDriftGeneration == generation else { return }
                self.recordSourceWorkspaceDrift(observations)
            }
        }
        do {
            try monitor.start()
            sourceWorkspaceDriftMonitor = monitor
            sourceWorkspaceDriftPhase = sourceWorkspaceDriftObservations.isEmpty ? .watching : .pending
            sourceWorkspaceDriftDiagnostic = sourceWorkspaceDriftObservations.isEmpty
                ? "Recursively watching supported local source paths through \(monitor.mode.label.lowercased()). Signals contain metadata only; source bytes are read only by exact verification."
                : "Recursive monitoring resumed; pending signals still lock exactness gates."
            scheduleSourceWorkspaceDriftAutoRefresh()
        } catch {
            activeSourceWorkspaceDriftGeneration = nil
            if let scopedURL = sourceWorkspaceDriftSecurityScopeURL {
                scopedURL.stopAccessingSecurityScopedResource()
                sourceWorkspaceDriftSecurityScopeURL = nil
            }
            sourceWorkspaceDriftMonitor = nil
            sourceWorkspaceDriftPhase = .failed
            sourceWorkspaceDriftDiagnostic = error.localizedDescription
        }
    }

    private func stopSourceWorkspaceDriftMonitoring(clearSignals: Bool) {
        activeSourceWorkspaceDriftGeneration = nil
        sourceWorkspaceDriftAutoRefreshTask?.cancel()
        sourceWorkspaceDriftAutoRefreshTask = nil
        activeSourceWorkspaceDriftAutoRefreshGeneration = nil
        sourceWorkspaceDriftMonitor?.stop(flushPending: false)
        sourceWorkspaceDriftMonitor = nil
        if let scopedURL = sourceWorkspaceDriftSecurityScopeURL {
            scopedURL.stopAccessingSecurityScopedResource()
            sourceWorkspaceDriftSecurityScopeURL = nil
        }
        if clearSignals {
            sourceWorkspaceDriftObservations = []
            sourceWorkspaceDriftReceipt = nil
        }
    }

    private func scheduleSourceWorkspaceDriftAutoRefresh() {
        sourceWorkspaceDriftAutoRefreshTask?.cancel()
        sourceWorkspaceDriftAutoRefreshTask = nil
        activeSourceWorkspaceDriftAutoRefreshGeneration = nil
        guard sourceWorkspaceAutoRefreshEnabled,
              sourceWorkspaceDriftPhase == .pending,
              sourceWorkspaceDriftMonitor != nil,
              sourceWorkspaceRootURL != nil,
              !sourceWorkspaceIndexPhase.isIndexing,
              !sourceWorkspaceRenameApplyPhase.isApplying,
              !sourceWorkspaceHostIncludePhase.isReading else { return }
        let generation = UUID()
        activeSourceWorkspaceDriftAutoRefreshGeneration = generation
        sourceWorkspaceDriftAutoRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                guard let self,
                      !Task.isCancelled,
                      self.activeSourceWorkspaceDriftAutoRefreshGeneration == generation,
                      self.sourceWorkspaceDriftPhase == .pending else { return }
                self.sourceWorkspaceDriftAutoRefreshTask = nil
                self.activeSourceWorkspaceDriftAutoRefreshGeneration = nil
                self.refreshSourceWorkspaceIndex()
            } catch {
                guard let self,
                      self.activeSourceWorkspaceDriftAutoRefreshGeneration == generation else { return }
                self.sourceWorkspaceDriftAutoRefreshTask = nil
                self.activeSourceWorkspaceDriftAutoRefreshGeneration = nil
            }
        }
    }

    private func nextSourceWorkspaceDriftEventID() -> UInt64 {
        let maximum = max(
            sourceWorkspaceDriftObservations.map(\.eventID).max() ?? 0,
            sourceWorkspaceDriftReceipt?.maximumEventID ?? 0
        )
        return maximum == UInt64.max ? UInt64.max : maximum + 1
    }

    private func completeSourceWorkspaceDriftVerification(through eventID: UInt64) {
        sourceWorkspaceDriftObservations = SourceWorkspaceDriftReceipt.observations(
            sourceWorkspaceDriftObservations,
            afterClearingThrough: eventID
        )
        if sourceWorkspaceDriftObservations.isEmpty {
            sourceWorkspaceDriftReceipt = nil
            if sourceWorkspaceDriftPhase == .paused {
                sourceWorkspaceDriftDiagnostic = "Exact bytes were verified, but monitoring remains paused; evidence gates stay locked."
            } else if sourceWorkspaceDriftMonitor != nil {
                sourceWorkspaceDriftPhase = .watching
                sourceWorkspaceDriftDiagnostic = "Every signal at or before the scan boundary was verified against exact source bytes; recursive monitoring is current."
            } else {
                sourceWorkspaceDriftPhase = .failed
                sourceWorkspaceDriftDiagnostic = "\(sourceWorkspaceDriftDiagnostic) Exact bytes were verified, but recursive monitoring is unavailable; evidence gates stay locked."
            }
        } else {
            sourceWorkspaceDriftReceipt = SourceWorkspaceDriftReceipt(
                baselineIndexFingerprint: sourceWorkspaceIndex.fingerprint,
                observations: sourceWorkspaceDriftObservations
            )
            if sourceWorkspaceDriftPhase != .paused, sourceWorkspaceDriftPhase != .failed {
                sourceWorkspaceDriftPhase = .pending
            }
            sourceWorkspaceDriftDiagnostic = "Later workspace signals remain pending after the scan boundary; exactness gates stay locked for another verification."
            scheduleSourceWorkspaceDriftAutoRefresh()
        }
    }

    func restoreSourceWorkspaceIndexReplay() {
        guard !sourceWorkspaceRenameApplyPhase.isApplying else {
            showNotice("Wait for the reviewed rename batch to finish before opening the replay.")
            return
        }
        sourceWorkspaceIndexTask?.cancel()
        activeSourceWorkspaceIndexGeneration = nil
        stopSourceWorkspaceDriftMonitoring(clearSignals: true)
        sourceWorkspaceDriftRootURL = nil
        resetSourceWorkspaceHostIncludeState()
        sourceWorkspaceRootURL = nil
        sourceWorkspaceIndex = SourceWorkspaceIndexSamples.index
        sourceWorkspaceIndexPhase = .localReplay
        sourceWorkspaceIndexDiagnostic = "Showing deterministic local source topology. No folder, provider, or host was read."
        sourceWorkspaceIndexBuildReport = SourceWorkspaceIndexSamples.refreshBuildReport
        sourceWorkspaceIndexDurationMilliseconds = 18
        sourceWorkspaceDriftPhase = .localReplay
        sourceWorkspaceDriftReceipt = SourceWorkspaceDriftSamples.receipt
        sourceWorkspaceDriftDiagnostic = "Showing deterministic path-only change signals. No folder bytes were monitored or read."
        sourceWorkspaceAutoRefreshEnabled = true
        sourceWorkspaceSearchQuery = "CalculateTax"
        selectedSourceWorkspacePath = "qrpglesrc/taxservice.rpgle"
        sourceWorkspaceIncludeChain = try? sourceWorkspaceIndex.includeChain(
            for: "qrpglesrc/taxservice.rpgle"
        )
        selectedSourceWorkspaceIncludeBoundaryID = sourceWorkspaceIncludeChain?.boundaries.first?.id
        isSourceWorkspaceIncludeChainPresented = false
        sourceWorkspaceDependencySelection = Set(SourceWorkspaceIndexSamples.reviewedScope.selectedPaths)
        sourceWorkspaceDependencyReview = SourceWorkspaceIndexSamples.reviewedScope
        sourceWorkspaceRenameCurrentName = "CalculateTax"
        sourceWorkspaceRenameProposedName = "CalculateOrderTax"
        sourceWorkspaceRenamePlan = try? sourceWorkspaceIndex.makeRenamePlan(
            currentName: sourceWorkspaceRenameCurrentName,
            proposedName: sourceWorkspaceRenameProposedName
        )
        clearSourceWorkspaceRenameReview(preserveReceipt: false)
        scheduleSourceWorkspaceSearch(debounce: false)
    }

    func selectSourceWorkspaceResult(_ result: SourceWorkspaceSearchResult) {
        selectedSourceWorkspacePath = result.relativePath
        refreshSourceWorkspaceIncludeChain()
        if result.kind == .symbol {
            sourceWorkspaceRenameCurrentName = result.label
            sourceWorkspaceRenamePlan = nil
            clearSourceWorkspaceRenameReview()
        }
        let suggested = sourceWorkspaceIndex.suggestedDependencyPaths(for: result.relativePath)
        if !suggested.isEmpty {
            sourceWorkspaceDependencySelection = Set(suggested)
            if sourceWorkspaceDependencyReview?.selectedPaths.map({ $0.uppercased() }).sorted()
                != suggested.map({ $0.uppercased() }).sorted() {
                sourceWorkspaceDependencyReview = nil
            }
        }
    }

    @discardableResult
    func openSourceWorkspaceResult(_ result: SourceWorkspaceSearchResult) -> Bool {
        guard sourceWorkspaceEvidenceIsCurrent else {
            sourceWorkspaceIndexDiagnostic = "Navigation is locked until pending workspace signals are verified against exact source bytes."
            showNotice(sourceWorkspaceIndexDiagnostic)
            return false
        }
        guard let document = sourceWorkspaceIndex.document(at: result.relativePath) else {
            showNotice("That indexed source result is no longer current. Refresh the Atlas.")
            return false
        }
        guard !sourceDocument.identity.isHostBacked || !sourceDocument.isDirty else {
            showNotice("Review or discard the current remote draft before opening an indexed snapshot.")
            return false
        }
        if openedSourceWorkspaceSnapshotPath == nil, sourceDocument.isDirty {
            flushSourceScratch()
        }
        sourceSaveTask?.cancel()
        sourceSaveTask = nil
        resetIFSWorkspace(restoreLocalDocument: false)
        openedSourceWorkspaceSnapshotPath = document.relativePath
        sourceDocument = SourceDocument(
            identity: .localScratch(name: document.displayName),
            format: document.format,
            sourceDatePolicy: .preserve,
            originalText: document.text,
            remoteRevision: document.contentFingerprint
        )
        sourceSaveState = .clean
        sourceCursorLine = result.line
        sourceCursorColumn = result.column
        sourceCursorUTF16 = 0
        sourceSelection = nil
        refreshSourceIntelligence()
        sourceNavigationRequest = SourceNavigationRequest(range: SourceTextRange(
            startLine: result.line,
            startColumn: result.column,
            endColumn: result.column + max(1, result.label.utf16.count)
        ))
        showNotice("Opened a read-only indexed snapshot at line \(result.line). The source file was not written.")
        return true
    }

    func selectSourceWorkspaceDocument(_ relativePath: String) {
        guard sourceWorkspaceIndex.document(at: relativePath) != nil else { return }
        selectedSourceWorkspacePath = relativePath
        refreshSourceWorkspaceIncludeChain()
        let suggested = sourceWorkspaceIndex.suggestedDependencyPaths(for: relativePath)
        sourceWorkspaceDependencySelection = Set(suggested)
        sourceWorkspaceDependencyReview = nil
        sourceWorkspaceRenamePlan = nil
        clearSourceWorkspaceRenameReview()
    }

    func toggleSourceWorkspaceDependency(_ relativePath: String) {
        guard sourceWorkspaceIndex.document(at: relativePath) != nil else { return }
        if sourceWorkspaceDependencySelection.remove(relativePath) == nil {
            sourceWorkspaceDependencySelection.insert(relativePath)
        }
        sourceWorkspaceDependencyReview = nil
    }

    func attestSourceWorkspaceDependencies() {
        guard sourceWorkspaceEvidenceIsCurrent else {
            sourceWorkspaceIndexDiagnostic = "Dependency review is locked until pending workspace signals are verified."
            showNotice(sourceWorkspaceIndexDiagnostic)
            return
        }
        do {
            let review = try ReviewedSourceDependencyScope(
                index: sourceWorkspaceIndex,
                selectedPaths: Array(sourceWorkspaceDependencySelection)
            )
            sourceWorkspaceDependencyReview = review
            sourceWorkspaceIndexDiagnostic = "Reviewed \(review.selectedPaths.count) exact dependency file(s) for local completion receipt \(review.shortFingerprint)."
            showNotice("Reviewed dependency symbols are now available to local content assist.")
        } catch {
            sourceWorkspaceIndexDiagnostic = "Dependency review blocked: \(error.localizedDescription)"
            showNotice(sourceWorkspaceIndexDiagnostic)
        }
    }

    func presentSourceWorkspaceHostIncludeReview(_ dependencyID: String) {
        guard !sourceWorkspaceHostIncludePhase.isReading,
              sourceWorkspaceEvidenceIsCurrent else {
            sourceWorkspaceIndexDiagnostic = "Host-include review is locked until pending workspace signals are verified."
            showNotice(sourceWorkspaceIndexDiagnostic)
            return
        }
        do {
            let review = try ReviewedSourceWorkspaceHostInclude(
                index: sourceWorkspaceIndex,
                dependencyID: dependencyID,
                sourceMemberLibrary: sourceWorkspaceHostIncludeLibrary
            )
            sourceWorkspaceHostIncludeReview = review
            sourceWorkspaceHostIncludeAttested = false
            sourceWorkspaceHostIncludePhase = .reviewReady
            isSourceWorkspaceHostIncludeReviewPresented = true
            sourceWorkspaceIndexDiagnostic = "Review \(review.shortFingerprint) binds one \(review.dependencyKind.label) edge to \(review.target.displayName). No provider was contacted."
        } catch {
            sourceWorkspaceHostIncludeReview = nil
            sourceWorkspaceHostIncludeAttested = false
            sourceWorkspaceHostIncludePhase = .failed
            sourceWorkspaceIndexDiagnostic = "Host include review blocked: \(error.localizedDescription)"
            showNotice(sourceWorkspaceIndexDiagnostic)
        }
    }

    func cancelSourceWorkspaceHostIncludeReview() {
        guard !sourceWorkspaceHostIncludePhase.isReading else { return }
        sourceWorkspaceHostIncludeReview = nil
        sourceWorkspaceHostIncludeAttested = false
        isSourceWorkspaceHostIncludeReviewPresented = false
        sourceWorkspaceHostIncludePhase = sourceWorkspaceHostIncludeContent == nil ? .idle : .installed
    }

    func readReviewedSourceWorkspaceHostInclude() {
        guard let review = sourceWorkspaceHostIncludeReview,
              sourceWorkspaceHostIncludeCanRead else {
            showNotice("Review and attest the exact host target before reading it.")
            return
        }
        sourceWorkspaceHostIncludeTask?.cancel()
        let generation = UUID()
        activeSourceWorkspaceHostIncludeGeneration = generation
        sourceWorkspaceHostIncludePhase = .reading
        sourceWorkspaceIndexDiagnostic = "Reading only \(review.target.displayName) through the reviewed read-only provider route."

        if sourceWorkspaceIndexPhase == .localReplay {
            do {
                let content = try SourceWorkspaceHostIncludeSamples.content(for: review)
                try installReviewedSourceWorkspaceHostInclude(content, review: review)
                showNotice("Bundled host-include replay installed locally. No provider or host was contacted.")
            } catch {
                failSourceWorkspaceHostInclude(error, generation: generation)
            }
            return
        }

        switch review.target {
        case .sourceMember(let identity):
            guard let context = sourceMemberConnection(requireWrite: false) else {
                sourceWorkspaceHostIncludePhase = .failed
                sourceWorkspaceIndexDiagnostic = "Connect Source-member read before executing this exact reviewed intake."
                activeSourceWorkspaceHostIncludeGeneration = nil
                return
            }
            let providerName = context.provider.providerName
            let targetName = context.provider.targetName
            sourceWorkspaceHostIncludeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let snapshot = try await context.provider.read(identity)
                    try Task.checkCancellation()
                    guard activeSourceWorkspaceHostIncludeGeneration == generation,
                          db2Transport === context.transport,
                          db2Phase.isConnected,
                          db2Receipt?.profileID == context.receipt.profileID,
                          db2Receipt?.accessMode == context.receipt.accessMode,
                          review.isCurrent(for: sourceWorkspaceIndex) else {
                        throw SourceWorkspaceHostIncludeError.staleReview
                    }
                    let content = try SourceWorkspaceHostIncludeContent(
                        request: review,
                        snapshot: snapshot,
                        providerName: providerName,
                        targetName: targetName
                    )
                    try installReviewedSourceWorkspaceHostInclude(content, review: review)
                    showNotice("Exact source-member include loaded into the local read-only overlay.")
                } catch is CancellationError {
                    guard activeSourceWorkspaceHostIncludeGeneration == generation else { return }
                    failSourceWorkspaceHostInclude(CancellationError(), generation: generation)
                } catch {
                    failSourceWorkspaceHostInclude(error, generation: generation)
                }
            }
        case .ifs(let path):
            guard secureChannelPhase == .connected else {
                sourceWorkspaceHostIncludePhase = .failed
                sourceWorkspaceIndexDiagnostic = "Connect the pinned SSH + SFTP provider before executing this exact reviewed intake."
                activeSourceWorkspaceHostIncludeGeneration = nil
                showNotice("Host include intake needs a connected SFTP provider.")
                return
            }
            guard let parent = path.parent else {
                failSourceWorkspaceHostInclude(
                    SourceWorkspaceHostIncludeError.invalidTarget,
                    generation: generation
                )
                return
            }
            let profile = secureChannelProfile
            sourceWorkspaceHostIncludeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let directory = try await ifsWorkspaceService.listDirectory(
                        profile: profile,
                        path: parent
                    )
                    guard let metadata = directory.entries.first(where: {
                        $0.metadata.path == path && $0.metadata.kind == .file
                    })?.metadata else {
                        throw SourceWorkspaceHostIncludeError.exactTargetUnavailable
                    }
                    guard metadata.byteCount >= 0,
                          metadata.byteCount <= review.maximumContentUTF8Bytes else {
                        throw SourceWorkspaceHostIncludeError.contentTooLarge(
                            review.maximumContentUTF8Bytes
                        )
                    }
                    let decoded = try await ifsWorkspaceService.readFile(
                        profile: profile,
                        metadata: metadata
                    )
                    try Task.checkCancellation()
                    guard activeSourceWorkspaceHostIncludeGeneration == generation,
                          secureChannelProfile == profile,
                          secureChannelPhase == .connected,
                          review.isCurrent(for: sourceWorkspaceIndex) else {
                        throw SourceWorkspaceHostIncludeError.staleReview
                    }
                    let content = try SourceWorkspaceHostIncludeContent(
                        request: review,
                        decodedIFS: decoded,
                        providerName: "SYSTEM OPENSSH SFTP",
                        targetName: profile.name
                    )
                    try installReviewedSourceWorkspaceHostInclude(content, review: review)
                    showNotice("Exact IFS include loaded into the local read-only overlay.")
                } catch is CancellationError {
                    guard activeSourceWorkspaceHostIncludeGeneration == generation else { return }
                    failSourceWorkspaceHostInclude(CancellationError(), generation: generation)
                } catch {
                    failSourceWorkspaceHostInclude(error, generation: generation)
                }
            }
        }
    }

    func removeSourceWorkspaceHostIncludes() {
        guard !sourceWorkspaceHostIncludePhase.isReading else { return }
        guard sourceWorkspaceIndex.hostIncludeFileCount > 0 else {
            showNotice("No host include overlay is loaded.")
            return
        }
        do {
            let sourcePath = sourceWorkspaceHostIncludeContent?.sourcePath
            sourceWorkspaceIndex = try sourceWorkspaceIndex.removingHostIncludes()
            scheduleSourceWorkspaceSearch(debounce: false)
            selectedSourceWorkspacePath = selectedSourceWorkspacePath.flatMap {
                sourceWorkspaceIndex.document(at: $0)?.relativePath
            } ?? sourcePath.flatMap { sourceWorkspaceIndex.document(at: $0)?.relativePath }
                ?? sourceWorkspaceIndex.documents.first?.relativePath
            refreshSourceWorkspaceIncludeChain()
            sourceWorkspaceDependencySelection = []
            sourceWorkspaceDependencyReview = nil
            sourceWorkspaceRenamePlan = nil
            clearSourceWorkspaceRenameReview()
            resetSourceWorkspaceHostIncludeState()
            sourceWorkspaceIndexDiagnostic = "Removed the in-memory host include overlay. No local file or host content was changed."
            showNotice("Host include overlay removed locally.")
        } catch {
            sourceWorkspaceHostIncludePhase = .failed
            sourceWorkspaceIndexDiagnostic = "Host include overlay removal stopped: \(error.localizedDescription)"
            showNotice(sourceWorkspaceIndexDiagnostic)
        }
    }

    private func installReviewedSourceWorkspaceHostInclude(
        _ content: SourceWorkspaceHostIncludeContent,
        review: ReviewedSourceWorkspaceHostInclude
    ) throws {
        guard review.isCurrent(for: sourceWorkspaceIndex),
              content.requestFingerprint == review.reviewFingerprint else {
            throw SourceWorkspaceHostIncludeError.staleReview
        }
        let expanded = try sourceWorkspaceIndex.appendingHostInclude(content)
        sourceWorkspaceIndex = expanded
        scheduleSourceWorkspaceSearch(debounce: false)
        selectedSourceWorkspacePath = content.sourcePath
        refreshSourceWorkspaceIncludeChain()
        sourceWorkspaceDependencySelection = []
        sourceWorkspaceDependencyReview = nil
        sourceWorkspaceRenamePlan = nil
        clearSourceWorkspaceRenameReview()
        sourceWorkspaceHostIncludeContent = content
        sourceWorkspaceHostIncludeReview = nil
        sourceWorkspaceHostIncludeAttested = false
        sourceWorkspaceHostIncludePhase = .installed
        sourceWorkspaceHostIncludeLibrary = ""
        isSourceWorkspaceHostIncludeReviewPresented = false
        sourceWorkspaceHostIncludeTask = nil
        activeSourceWorkspaceHostIncludeGeneration = nil
        sourceWorkspaceIndexDiagnostic = "Loaded one exact \(content.target.providerKind.label.lowercased()) include into local memory at \(content.overlayRelativePath); index \(expanded.shortFingerprint)."
    }

    private func failSourceWorkspaceHostInclude(_ error: Error, generation: UUID) {
        guard activeSourceWorkspaceHostIncludeGeneration == generation else { return }
        sourceWorkspaceHostIncludeTask = nil
        activeSourceWorkspaceHostIncludeGeneration = nil
        sourceWorkspaceHostIncludePhase = .failed
        sourceWorkspaceIndexDiagnostic = "Host include intake stopped: \(incidentFailureReason(error))"
        showNotice(sourceWorkspaceIndexDiagnostic)
    }

    private func resetSourceWorkspaceHostIncludeState() {
        sourceWorkspaceHostIncludeTask?.cancel()
        sourceWorkspaceHostIncludeTask = nil
        activeSourceWorkspaceHostIncludeGeneration = nil
        sourceWorkspaceHostIncludeReview = nil
        sourceWorkspaceHostIncludeAttested = false
        sourceWorkspaceHostIncludeContent = nil
        sourceWorkspaceHostIncludePhase = .idle
        sourceWorkspaceHostIncludeLibrary = ""
        isSourceWorkspaceHostIncludeReviewPresented = false
    }

    private func invalidateSourceWorkspaceHostIncludeRead(reason: String) {
        guard sourceWorkspaceHostIncludePhase.isReading else { return }
        sourceWorkspaceHostIncludeTask?.cancel()
        sourceWorkspaceHostIncludeTask = nil
        activeSourceWorkspaceHostIncludeGeneration = nil
        sourceWorkspaceHostIncludePhase = .failed
        sourceWorkspaceIndexDiagnostic = reason
    }

    func prepareSourceWorkspaceRenamePlan() {
        clearSourceWorkspaceRenameReview()
        guard sourceWorkspaceEvidenceIsCurrent else {
            sourceWorkspaceRenamePlan = nil
            sourceWorkspaceIndexDiagnostic = "Rename preview is locked until pending workspace signals are verified."
            showNotice(sourceWorkspaceIndexDiagnostic)
            return
        }
        do {
            let plan = try sourceWorkspaceIndex.makeRenamePlan(
                currentName: sourceWorkspaceRenameCurrentName,
                proposedName: sourceWorkspaceRenameProposedName
            )
            sourceWorkspaceRenamePlan = plan
            sourceWorkspaceIndexDiagnostic = "Prepared exact preview \(plan.shortFingerprint) across \(plan.baselines.count) file(s). No file was changed."
            showNotice("Rename preview prepared from current content and source-date baselines.")
        } catch {
            sourceWorkspaceRenamePlan = nil
            sourceWorkspaceIndexDiagnostic = "Rename preview blocked: \(error.localizedDescription)"
            showNotice(sourceWorkspaceIndexDiagnostic)
        }
    }

    func invalidateSourceWorkspaceRenamePreview() {
        guard !sourceWorkspaceRenameApplyPhase.isApplying else { return }
        sourceWorkspaceRenamePlan = nil
        clearSourceWorkspaceRenameReview()
    }

    func presentSourceWorkspaceRenameReview() {
        guard !sourceWorkspaceRenameApplyPhase.isApplying,
              sourceWorkspaceEvidenceIsCurrent,
              let plan = sourceWorkspaceRenamePlan,
              plan.isCurrent(for: sourceWorkspaceIndex) else {
            sourceWorkspaceIndexDiagnostic = "Prepare a current exact rename preview before opening review."
            showNotice(sourceWorkspaceIndexDiagnostic)
            return
        }
        do {
            let review = try ReviewedSourceWorkspaceRename(index: sourceWorkspaceIndex, plan: plan)
            sourceWorkspaceRenameReview = review
            sourceWorkspaceRenameAttested = false
            sourceWorkspaceRenameRecovery = nil
            sourceWorkspaceRenameApplyPhase = .reviewReady
            isSourceWorkspaceRenameReviewPresented = true
            if sourceWorkspaceUsesSelectedFolder {
                sourceWorkspaceIndexDiagnostic = "Review \(review.shortFingerprint) freezes \(review.affectedPaths.count) path(s) and \(review.occurrenceCount) exact token replacement(s)."
            } else {
                sourceWorkspaceIndexDiagnostic = "Review \(review.shortFingerprint) is read-only replay evidence. Choose a folder before applying."
            }
        } catch {
            clearSourceWorkspaceRenameReview()
            sourceWorkspaceIndexDiagnostic = "Rename review blocked: \(error.localizedDescription)"
            showNotice(sourceWorkspaceIndexDiagnostic)
        }
    }

    func cancelSourceWorkspaceRenameReview() {
        guard !sourceWorkspaceRenameApplyPhase.isApplying else { return }
        isSourceWorkspaceRenameReviewPresented = false
        sourceWorkspaceRenameReview = nil
        sourceWorkspaceRenameAttested = false
        if sourceWorkspaceRenameApplyPhase == .reviewReady {
            sourceWorkspaceRenameApplyPhase = .idle
        }
    }

    func applyReviewedSourceWorkspaceRename() {
        guard let rootURL = sourceWorkspaceRootURL,
              let plan = sourceWorkspaceRenamePlan,
              let review = sourceWorkspaceRenameReview,
              sourceWorkspaceRenameCanApply else {
            showNotice("Review every affected path and attest the exact rename before applying it.")
            return
        }
        sourceWorkspaceIndexTask?.cancel()
        sourceWorkspaceRenameApplyPhase = .applying
        sourceWorkspaceRenameRecovery = nil
        sourceWorkspaceIndexDiagnostic = "Re-checking every baseline before the rollback-protected local batch."
        let frozenIndex = sourceWorkspaceIndex
        let driftBoundary = sourceWorkspaceDriftObservations.map(\.eventID).max() ?? 0
        let accessStarted = rootURL.startAccessingSecurityScopedResource()
        sourceWorkspaceRenameTask = Task { @MainActor [weak self] in
            defer {
                if accessStarted { rootURL.stopAccessingSecurityScopedResource() }
            }
            guard let self else { return }
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    let service = SourceWorkspaceIndexService(limits: frozenIndex.limits)
                    let receipt = try service.applyReviewedRename(
                        rootURL: rootURL,
                        index: frozenIndex,
                        plan: plan,
                        review: review
                    )
                    let refreshed = try service.scan(rootURL: rootURL, previousIndex: frozenIndex)
                    return (receipt, refreshed)
                }
                let (receipt, refreshed) = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else { return }
                installSourceWorkspaceScanResult(refreshed, preservingDependencyReview: false)
                completeSourceWorkspaceDriftVerification(through: driftBoundary)
                refreshOpenedSourceWorkspaceSnapshotIfNeeded()
                sourceWorkspaceRenamePlan = nil
                sourceWorkspaceRenameReview = nil
                sourceWorkspaceRenameAttested = false
                sourceWorkspaceRenameApplyReceipt = receipt
                sourceWorkspaceRenameApplyPhase = .applied
                sourceWorkspaceRenameRecovery = nil
                isSourceWorkspaceRenameReviewPresented = false
                sourceWorkspaceRenameTask = nil
                sourceWorkspaceIndexDiagnostic = "Applied \(receipt.replacementCount) exact token replacement(s) across \(receipt.changedPaths.count) file(s), then rebuilt index \(refreshed.index.shortFingerprint)."
                showNotice("Reviewed local rename applied and verified by a fresh index.")
            } catch {
                if case .applyFailed(_, let recovery) = error as? LocalSourceWorkspaceRenameError {
                    sourceWorkspaceRenameRecovery = recovery
                }
                let refreshed = try? await Task.detached(priority: .utility) {
                    try SourceWorkspaceIndexService(limits: frozenIndex.limits).scan(
                        rootURL: rootURL,
                        previousIndex: frozenIndex
                    )
                }.value
                if let refreshed {
                    installSourceWorkspaceScanResult(refreshed, preservingDependencyReview: false)
                    completeSourceWorkspaceDriftVerification(through: driftBoundary)
                    refreshOpenedSourceWorkspaceSnapshotIfNeeded()
                }
                sourceWorkspaceRenamePlan = nil
                sourceWorkspaceRenameReview = nil
                sourceWorkspaceRenameAttested = false
                sourceWorkspaceRenameApplyPhase = .failed
                sourceWorkspaceRenameTask = nil
                sourceWorkspaceIndexDiagnostic = "Rename application stopped: \(error.localizedDescription)"
                showNotice(sourceWorkspaceRenameRecovery?.isComplete == false
                    ? "Rename recovery needs local file inspection."
                    : "Rename application stopped; the local index was refreshed.")
            }
        }
    }

    private func clearSourceWorkspaceRenameReview(preserveReceipt: Bool = true) {
        sourceWorkspaceRenameReview = nil
        sourceWorkspaceRenameAttested = false
        sourceWorkspaceRenameRecovery = nil
        isSourceWorkspaceRenameReviewPresented = false
        if !sourceWorkspaceRenameApplyPhase.isApplying {
            sourceWorkspaceRenameApplyPhase = .idle
        }
        if !preserveReceipt { sourceWorkspaceRenameApplyReceipt = nil }
    }

    private func installSourceWorkspaceScanResult(
        _ result: SourceWorkspaceScanResult,
        preservingDependencyReview: Bool,
        durationMilliseconds: Int? = nil
    ) {
        resetSourceWorkspaceHostIncludeState()
        let priorReview = preservingDependencyReview ? sourceWorkspaceDependencyReview : nil
        sourceWorkspaceIndex = result.index
        sourceWorkspaceRootURL = result.rootURL
        sourceWorkspaceIndexPhase = .ready
        sourceWorkspaceIndexBuildReport = result.buildReport
        sourceWorkspaceIndexDurationMilliseconds = durationMilliseconds
        selectedSourceWorkspacePath = selectedSourceWorkspacePath
            .flatMap { result.index.document(at: $0)?.relativePath }
            ?? result.index.documents.first?.relativePath
        if let priorReview, priorReview.isCurrent(for: result.index) {
            sourceWorkspaceDependencySelection = Set(priorReview.selectedPaths)
            sourceWorkspaceDependencyReview = priorReview
        } else if let selectedSourceWorkspacePath {
            sourceWorkspaceDependencySelection = Set(
                result.index.suggestedDependencyPaths(for: selectedSourceWorkspacePath)
            )
            sourceWorkspaceDependencyReview = nil
        } else {
            sourceWorkspaceDependencySelection = []
            sourceWorkspaceDependencyReview = nil
        }
        refreshSourceWorkspaceIncludeChain()
        scheduleSourceWorkspaceSearch(debounce: false)
    }

    private func refreshOpenedSourceWorkspaceSnapshotIfNeeded() {
        guard let openedSourceWorkspaceSnapshotPath,
              let document = sourceWorkspaceIndex.document(at: openedSourceWorkspaceSnapshotPath) else { return }
        sourceDocument = SourceDocument(
            identity: .localScratch(name: document.displayName),
            format: document.format,
            sourceDatePolicy: .preserve,
            originalText: document.text,
            remoteRevision: document.contentFingerprint
        )
        sourceSaveState = .clean
        sourceSelection = nil
        refreshSourceIntelligence()
    }

    func reanalyzeSource() {
        dismissSourceCompletion()
        sourceIntelligenceTask?.cancel()
        sourceIntelligenceTask = nil
        sourceIntelligence = sourceIntelligenceAnalyzer.analyze(sourceDocument)
        sourceIntelligenceIsCurrent = true
    }

    func requestSourceCompletion(caretUTF16 requestedCaret: Int? = nil) {
        let caret = requestedCaret ?? sourceCursorUTF16
        let currentFingerprint = SourceIntelligenceAnalyzer.fingerprint(of: sourceDocument.text)
        if !sourceIntelligenceIsCurrent
            || sourceIntelligence.fingerprint != currentFingerprint
            || sourceIntelligence.format != sourceDocument.format {
            sourceIntelligenceTask?.cancel()
            sourceIntelligenceTask = nil
            sourceIntelligence = sourceIntelligenceAnalyzer.analyze(sourceDocument)
            sourceIntelligenceIsCurrent = true
        }

        let session = sourceCompletionEngine.complete(
            text: sourceDocument.text,
            format: sourceDocument.format,
            caretUTF16: caret,
            snapshot: sourceIntelligence,
            workspaceSymbols: reviewedSourceWorkspaceCompletionSymbols
        )
        sourceCompletionSelectionIndex = 0
        sourceCompletionSession = session.isPresentable ? session : nil

        switch session.status {
        case .ready:
            break
        case .noMatches:
            showNotice("No local completion matches the current source prefix.")
        case .suppressed:
            showNotice("Content assist stays quiet inside comments and string literals.")
        case .staleSnapshot:
            showNotice("Source completion needs a current local analysis snapshot. Try again.")
        case .invalidCaret:
            showNotice("Source completion could not resolve the current insertion point.")
        case .analysisLimited:
            showNotice("Source completion stopped at its local analysis boundary.")
        }
    }

    func moveSourceCompletionSelection(delta: Int) {
        guard let session = sourceCompletionSession, !session.items.isEmpty else { return }
        let count = session.items.count
        sourceCompletionSelectionIndex = (sourceCompletionSelectionIndex + delta % count + count) % count
    }

    func dismissSourceCompletion() {
        sourceCompletionSession = nil
        sourceCompletionSelectionIndex = 0
    }

    func openSourceCompletionAssist(itemID: String) {
        guard let session = sourceCompletionSession,
              session.documentFingerprint == SourceIntelligenceAnalyzer.fingerprint(of: sourceDocument.text),
              let item = session.items.first(where: { $0.id == itemID }),
              item.action == .openAssistReview else {
            dismissSourceCompletion()
            showNotice("That completion is no longer current. Request content assist again.")
            return
        }
        let symbol = item.sourceSymbolID.flatMap { id in
            sourceIntelligence.symbols.first(where: { $0.id == id })
        }
        dismissSourceCompletion()
        prepareSourceAssistReview(symbol: symbol)
    }

    func navigateToSource(_ range: SourceTextRange) {
        dismissSourceCompletion()
        sourceNavigationRequest = SourceNavigationRequest(range: range)
    }

    func prepareSourceAssistReview(symbol: SourceSymbol? = nil) {
        isAssistantVisible = true
        latestAIEditProposal = nil
        latestAIProposalExplanation = nil
        aiProposalDiagnostic = nil
        aiProposalWasApplied = false
        if let symbol, let symbolSelection = sourceAISelection(for: symbol.range) {
            sourceSelection = symbolSelection
            sourceNavigationRequest = SourceNavigationRequest(range: symbol.range)
        }
        let hasSelection = sourceSelection.flatMap {
            try? $0.selectedText(in: sourceDocument.text)
        }?.isEmpty == false
        let question: String
        if let symbol {
            question = "Review the \(symbol.kind.label.lowercased()) \(symbol.name) for correctness, IBM i compatibility, job-scope side effects, and the smallest safe improvement. Treat local source intelligence as navigation evidence, not compiler evidence."
        } else {
            question = "Review this \(sourceDocument.format.rawValue) change for correctness, IBM i compatibility, job-scope side effects, and the smallest safe improvement."
        }
        aiReviewDraft = AIReviewDraft(
            target: .sourceDraft,
            documentName: sourceDocument.identity.hostLocation ?? sourceDocument.identity.displayName,
            language: sourceDocument.format.rawValue,
            sourceText: sourceDocument.text,
            selection: hasSelection ? sourceSelection : nil,
            scope: hasSelection ? .selection : .wholeDraft,
            question: question
        )
        isAIReviewDossierPresented = true
        showNotice(symbol == nil
            ? "Assist dossier prepared. Review the exact source context before sending."
            : "Assist dossier prepared for \(symbol?.name ?? "the selected symbol"). Review the exact source context before sending.")
    }

    func selectCompileRun(_ id: UUID) {
        guard let run = compileRuns.first(where: { $0.id == id }) else { return }
        selectedCompileRunID = id
        selectedCompileDiagnosticID = run.analysis.primaryDiagnostic?.id
            ?? run.evidence.diagnostics.first?.id
        compileImportDiagnostic = nil
    }

    func selectCompileDiagnostic(_ id: String) {
        guard selectedCompileRun?.evidence.diagnostics.contains(where: { $0.id == id }) == true else {
            return
        }
        selectedCompileDiagnosticID = id
    }

    func presentCompileLineage() {
        guard let current = selectedCompileRun ?? compileRuns.first else {
            compileLineageDiagnostic = "No retained compile run is available."
            return
        }
        compileLineageCurrentRunID = current.id
        if compileLineageBaselineRun?.id == current.id
            || compileLineageBaselineRun?.recipe.targetIdentity != current.recipe.targetIdentity {
            compileLineageBaselineRunID = compileRuns.first(where: {
                $0.id != current.id && $0.recipe.targetIdentity == current.recipe.targetIdentity
            })?.id
        }
        if let comparison = compileLineageComparison {
            compileLineageDiagnostic = "Bound \(comparison.runs.count) retained runs to local receipt \(comparison.shortFingerprint). Nothing was executed."
        } else {
            compileLineageDiagnostic = compileLineageValidationMessage
                ?? "Choose two retained runs for the same exact target."
        }
        isCompileLineagePresented = true
    }

    func selectCompileLineageCurrent(_ id: UUID) {
        guard let run = compileRuns.first(where: { $0.id == id }) else { return }
        compileLineageCurrentRunID = run.id
        selectedCompileRunID = run.id
        selectedCompileDiagnosticID = run.analysis.primaryDiagnostic?.id
            ?? run.evidence.diagnostics.first?.id
        if compileLineageBaselineRun?.id == run.id
            || compileLineageBaselineRun?.recipe.targetIdentity != run.recipe.targetIdentity {
            compileLineageBaselineRunID = compileRuns.first(where: {
                $0.id != run.id && $0.recipe.targetIdentity == run.recipe.targetIdentity
            })?.id
        }
        compileLineageDiagnostic = compileLineageComparison.map {
            "Current run set to \(run.displaySequence); comparison receipt \($0.shortFingerprint) is local only."
        } ?? (compileLineageValidationMessage ?? "Choose a compatible baseline run.")
    }

    func selectCompileLineageBaseline(_ id: UUID) {
        guard let current = compileLineageCurrentRun,
              let run = compileRuns.first(where: { $0.id == id }),
              run.id != current.id,
              run.recipe.targetIdentity == current.recipe.targetIdentity else {
            compileLineageDiagnostic = "A baseline must be a different retained run for the same exact target."
            return
        }
        compileLineageBaselineRunID = run.id
        compileLineageDiagnostic = compileLineageComparison.map {
            "Baseline set to \(run.displaySequence); comparison receipt \($0.shortFingerprint) is local only."
        } ?? (compileLineageValidationMessage ?? "The comparison could not be built.")
    }

    func presentCompileRecipeStudio() {
        if let selectedCompileRecipe {
            compileRecipeDraft = CompileRecipeDraft(recipe: selectedCompileRecipe)
        } else if let first = compileRecipeLibrary.recipes.first {
            selectedCompileRecipeID = first.id
            compileRecipeDraft = CompileRecipeDraft(recipe: first)
        } else {
            compileRecipeDraft = CompileRecipeDraft()
        }
        isCompileRecipeStudioPresented = true
    }

    func selectCompileRecipe(_ id: UUID) {
        guard let recipe = compileRecipeLibrary.recipes.first(where: { $0.id == id }) else { return }
        selectedCompileRecipeID = recipe.id
        compileRecipeDraft = CompileRecipeDraft(recipe: recipe)
        compileRecipeDiagnostic = "Loaded \(recipe.name) from the local recipe library. Nothing was executed."
    }

    func createCompileRecipeDraft() {
        let source = selectedCompileRecipe
        compileRecipeDraft = CompileRecipeDraft(
            name: "New RPG recipe",
            toolchain: source?.toolchain ?? .ileRPG,
            sourceLibrary: source?.sourceLibrary.value ?? "DEVLIB",
            sourceFile: source?.sourceFile.value ?? "QRPGLESRC",
            sourceMember: "PROGRAM",
            targetLibrary: source?.targetLibrary.value ?? "DEVLIB",
            targetObject: "PROGRAM",
            environment: source?.environment ?? .development,
            targetRelease: source?.targetRelease.commandValue ?? "*CURRENT",
            debugView: source?.debugView ?? .source,
            sqlCommitment: source?.toolchain.isSQL == true ? (source?.sqlCommitment ?? .none) : .none,
            rpgPreprocessor: source?.toolchain.isSQL == true ? (source?.rpgPreprocessor ?? .none) : .none,
            replaceExisting: source?.replaceExisting ?? true
        )
        selectedCompileRecipeID = nil
        compileRecipeDiagnostic = "New local recipe draft. Save is explicit; no host or provider is involved."
    }

    func duplicateCompileRecipeDraft() {
        guard let recipe = compileRecipePreview else {
            compileRecipeDiagnostic = compileRecipeValidationMessage ?? "Correct the recipe before duplicating it."
            return
        }
        compileRecipeDraft = CompileRecipeDraft(
            name: "\(recipe.name) copy",
            toolchain: recipe.toolchain,
            sourceLibrary: recipe.sourceLibrary.value,
            sourceFile: recipe.sourceFile.value,
            sourceMember: recipe.sourceMember.value,
            targetLibrary: recipe.targetLibrary.value,
            targetObject: recipe.targetObject.value,
            environment: recipe.environment,
            targetRelease: recipe.targetRelease.commandValue,
            debugView: recipe.debugView,
            sqlCommitment: recipe.sqlCommitment,
            rpgPreprocessor: recipe.rpgPreprocessor,
            replaceExisting: recipe.replaceExisting
        )
        selectedCompileRecipeID = nil
        compileRecipeDiagnostic = "Duplicated into a new unsaved recipe draft."
    }

    func updateCompileRecipeToolchain(_ toolchain: CompileRecipeToolchain) {
        compileRecipeDraft.toolchain = toolchain
        if !toolchain.isSQL {
            compileRecipeDraft.sqlCommitment = .none
            compileRecipeDraft.rpgPreprocessor = .none
        }
    }

    func saveCompileRecipe() {
        do {
            let recipe = try compileRecipeDraft.makeRecipe()
            var candidate = compileRecipeLibrary
            try candidate.upsert(recipe)
            try compileRecipeStore.write(candidate)
            compileRecipeLibrary = candidate
            selectedCompileRecipeID = recipe.id
            compileRecipeDraft = CompileRecipeDraft(recipe: recipe)
            compileRecipeUsesBundledDefaults = false
            compileRecipeDiagnostic = "Saved \(recipe.name) locally with receipt \(recipe.shortFingerprint). Nothing was sent or executed."
            showNotice("Compile recipe saved locally.")
        } catch {
            compileRecipeDiagnostic = error.localizedDescription
            showNotice("Compile recipe save was blocked.")
        }
    }

    func importCompileEvidence(_ data: Data, fileName: String) {
        do {
            let evidence = try EVFEVENTParser().parse(data: data)
            let sourceIdentity = evidence.sourceFiles.first?.path ?? "Source identity not present"
            let objectName = Self.compileObjectName(from: sourceIdentity, fallback: fileName)
            let run = CompileRunRecord(
                id: UUID(),
                sequence: nil,
                objectName: objectName,
                startedAtLabel: evidence.timestamp.map(Self.shortCompileTimestamp) ?? "Imported",
                durationLabel: "Not included",
                jobIdentity: "Not included in EVFEVENT",
                outcome: .evidenceOnly,
                origin: .localImport(fileName: fileName),
                recipe: CompileRecipeRecord(
                    name: "Imported EVFEVENT evidence",
                    language: "Compiler event file",
                    sourceIdentity: sourceIdentity,
                    targetIdentity: "Not asserted by local import",
                    compiler: "Not included in local import",
                    commandPreview: "Not included in local import",
                    eventFileIdentity: fileName,
                    environment: selectedProfile?.environment ?? .development
                ),
                evidence: evidence,
                sourceText: nil,
                sourceRevision: nil,
                objectWasChanged: nil,
                observedHostRelease: nil
            )
            compileRuns.insert(run, at: 0)
            selectedCompileRunID = run.id
            selectedCompileDiagnosticID = run.analysis.primaryDiagnostic?.id
                ?? run.evidence.diagnostics.first?.id
            compileImportDiagnostic = evidence.hasExpansionMappings
                ? "Imported \(evidence.recordCount) records locally. EXPANSION records are retained as a visible mapping limitation."
                : "Imported \(evidence.recordCount) records locally. No host was contacted."
            showNotice("Compile evidence imported locally.")
        } catch {
            compileImportDiagnostic = error.localizedDescription
            showNotice("Compile evidence import was blocked.")
        }
    }

    func prepareCompileAssist() {
        guard let run = selectedCompileRun else {
            compileImportDiagnostic = "Select a compile run before preparing Assist context."
            return
        }
        do {
            let fragment = try AIContextFragment(
                kind: .compileEvidence,
                documentName: "\(run.objectName)-compile-evidence.txt",
                language: "IBM i EVFEVENT",
                sourceText: run.assistContextText()
            )
            let bundle = try pinPreparedAssistantContext(
                fragment,
                label: "\(run.objectName) compile evidence"
            )
            assistantInput = "Diagnose this compile evidence. Separate the first actionable diagnostic from related messages, cite message IDs and exact source locations, and propose the smallest safe next edit or read-only check."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("Compile evidence pinned. Review the exact Context Shelf before sending.")
        } catch {
            compileImportDiagnostic = error.localizedDescription
            showNotice("Compile Assist context was blocked.")
        }
    }

    func prepareCompileLineageAssist() {
        guard let comparison = compileLineageComparison else {
            compileLineageDiagnostic = compileLineageValidationMessage
                ?? "Choose two retained runs for the same exact target before pinning comparison evidence."
            return
        }
        do {
            let fragment = try AIContextFragment(
                kind: .compileEvidence,
                documentName: "\(compileLineageCurrentRun?.objectName ?? "compile")-lineage.txt",
                language: "IBM i compile lineage",
                sourceText: comparison.assistContextText()
            )
            let bundle = try pinPreparedAssistantContext(
                fragment,
                label: "\(compileLineageCurrentRun?.objectName ?? "Compile") lineage"
            )
            assistantInput = "Review this retained compile lineage. Separate exact facts from inference, explain introduced, resolved, and persistent message identities, and identify the smallest additional evidence needed before changing source or build settings."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            compileLineageDiagnostic = "Comparison \(comparison.shortFingerprint) was pinned locally. Review the exact Context Shelf before sending."
            showNotice("Compile lineage pinned for review.")
        } catch {
            compileLineageDiagnostic = error.localizedDescription
            showNotice("Compile lineage context was blocked.")
        }
    }

    func clearPreparedAssistantContext() {
        preparedAssistantContextBundle = nil
        preparedAssistantContextLabel = nil
        latestAIContextReceipt = nil
    }

    @discardableResult
    private func pinPreparedAssistantContext(
        _ fragment: AIContextFragment,
        label: String
    ) throws -> AIContextBundle {
        try pinPreparedAssistantContexts([fragment], label: label)
    }

    @discardableResult
    private func pinPreparedAssistantContexts(
        _ fragments: [AIContextFragment],
        label: String
    ) throws -> AIContextBundle {
        var shelf = try AIContextShelf(
            fragments: preparedAssistantContextBundle?.fragments ?? []
        )
        for fragment in fragments {
            shelf = try shelf.pinning(fragment)
        }
        guard let bundle = try shelf.requestBundle() else {
            throw AIContextError.emptyContext
        }
        var requestFragments = bundle.fragments
        if let automaticScreen = try automaticScreenContextFragment(),
           !requestFragments.contains(where: { $0.kind == .terminalScreen }) {
            requestFragments.append(automaticScreen)
            _ = try AIContextBundle(fragments: requestFragments)
        }
        preparedAssistantContextBundle = bundle
        preparedAssistantContextLabel = bundle.fragments.count == 1
            ? label
            : "Context Shelf · \(bundle.fragments.count) pinned sources"
        return bundle
    }

    func removePreparedAssistantContext(_ kind: AIContextKind) {
        guard let current = preparedAssistantContextBundle else { return }
        do {
            let shelf = try AIContextShelf(fragments: current.fragments).removing(kind)
            preparedAssistantContextBundle = try shelf.requestBundle()
            preparedAssistantContextLabel = shelf.isEmpty
                ? nil
                : "Context Shelf · \(shelf.count) pinned source\(shelf.count == 1 ? "" : "s")"
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: currentAssistantContextBundle,
                conversationTurns: assistantMessages.count
            )
            showNotice("Removed \(kind.label.lowercased()) from the local Context Shelf.")
        } catch {
            assistantError = "Context Shelf update was blocked: \(error.localizedDescription)"
        }
    }

    func selectContinuityCase(_ id: UUID) {
        guard continuityCasebook.cases.contains(where: { $0.id == id }) else { return }
        selectedContinuityCaseID = id
    }

    func createContinuityCase(kind: ContinuityCaseKind = .general) {
        do {
            var casebook = continuityCasebookUsesReplay ? ContinuityCasebook.empty : continuityCasebook
            let continuityCase = try ContinuityCase(
                code: nextContinuityCaseCode(kind: kind, in: casebook),
                kind: kind,
                title: "New \(kind.label.lowercased()) handoff",
                target: selectedProfile?.name ?? "LOCAL WORKBENCH",
                environment: selectedProfile?.environment ?? .development,
                summary: "Record exact evidence, decisions, open questions, and the next verified action.",
                nextAction: "Review the exact retained evidence and record the next verified action.",
                staleBoundary: "Refresh time-sensitive host evidence before relying on it."
            )
            casebook = try casebook.adding(continuityCase)
            try commitContinuityCasebook(
                casebook,
                selectedCaseID: continuityCase.id,
                message: "Created \(continuityCase.code) locally."
            )
            selectedTool = .casebook
        } catch {
            continuityCasebookDiagnostic = error.localizedDescription
            showNotice("Continuity Case creation was blocked.")
        }
    }

    func capturePreparedAssistantContextInCasebook() {
        do {
            guard let bundle = try buildCurrentAssistantContextBundle(), !bundle.fragments.isEmpty else {
                continuityCasebookDiagnostic = "Pin at least one Context Shelf artifact before adding it to a case."
                return
            }
            let artifacts = try bundle.fragments.map { try ContinuityArtifact(fragment: $0) }
            let result = try writableContinuityCase(
                kind: inferredContinuityCaseKind(for: bundle),
                title: preparedAssistantContextLabel ?? "Reviewed evidence handoff",
                summary: "Exact artifacts captured from the operator-reviewed Assist Context Shelf."
            )
            let updatedCase = try result.continuityCase.adding(artifacts: artifacts)
            let updatedBook = try result.casebook.replacing(updatedCase)
            try commitContinuityCasebook(
                updatedBook,
                selectedCaseID: updatedCase.id,
                message: "Added \(artifacts.count) exact Context Shelf artifact\(artifacts.count == 1 ? "" : "s") to \(updatedCase.code)."
            )
            selectedTool = .casebook
            isAIContextPreviewPresented = false
        } catch {
            continuityCasebookDiagnostic = error.localizedDescription
            showNotice("Casebook evidence capture was blocked.")
        }
    }

    func recordAssistantMessageInCasebook(_ message: AssistantMessage) {
        guard message.role == .assistant, let provenance = message.provenance else {
            continuityCasebookDiagnostic = "Only a response with a current request receipt can enter the Assist Answer Ledger."
            return
        }
        do {
            let state: ContinuityAnswerState = switch message.completionState {
            case .complete: .complete
            case .stopped: .stopped
            case .interrupted: .interrupted
            }
            let answer = try ContinuityAssistAnswer(
                id: message.id,
                question: provenance.question,
                answer: message.content,
                state: state,
                commandRisk: message.commandRisk,
                contextFingerprint: provenance.contextFingerprint,
                contextItemCount: provenance.contextItemCount,
                endpointHost: provenance.endpointHost,
                model: provenance.model,
                createdAt: provenance.requestedAt
            )
            let result = try writableContinuityCase(
                kind: .general,
                title: "Assist evidence handoff",
                summary: "Evidence-linked Assist answers retained with completion state and request provenance."
            )
            let updatedCase = try result.continuityCase.adding(answer: answer)
            let updatedBook = try result.casebook.replacing(updatedCase)
            try commitContinuityCasebook(
                updatedBook,
                selectedCaseID: updatedCase.id,
                message: "Recorded the \(state.label.lowercased()) Assist answer in \(updatedCase.code)."
            )
        } catch {
            continuityCasebookDiagnostic = error.localizedDescription
            showNotice("Assist Answer Ledger update was blocked.")
        }
    }

    func isAssistantMessageRecorded(_ message: AssistantMessage) -> Bool {
        continuityCasebook.cases.contains { continuityCase in
            continuityCase.answers.contains(where: { $0.id == message.id })
        }
    }

    func importContinuityReference(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let pack = try continuityCasebookStore.readReferencePack(at: url)
            pendingContinuityReferenceReview = ContinuityReferenceReviewDraft(
                sourceName: url.lastPathComponent,
                pack: pack
            )
            isContinuityReferenceReviewPresented = true
            continuityCasebookDiagnostic = "Review every imported entry before attaching it to a case."
        } catch {
            pendingContinuityReferenceReview = nil
            continuityCasebookDiagnostic = "Reference import was blocked: \(error.localizedDescription)"
            showNotice("Reviewed reference import was blocked.")
        }
    }

    func toggleContinuityReferenceEntry(_ id: UUID) {
        guard var draft = pendingContinuityReferenceReview,
              draft.pack.entries.contains(where: { $0.id == id }) else { return }
        if draft.selectedEntryIDs.contains(id) {
            draft.selectedEntryIDs.remove(id)
        } else {
            draft.selectedEntryIDs.insert(id)
        }
        pendingContinuityReferenceReview = draft
    }

    func attachReviewedContinuityReference() {
        guard let draft = pendingContinuityReferenceReview else { return }
        do {
            let reference = try draft.pack.reviewing(entryIDs: draft.selectedEntryIDs)
            let result = try writableContinuityCase(
                kind: draft.pack.kind == .runbook ? .general : .change,
                title: "Reviewed reference handoff",
                summary: "Explicitly selected local reference entries retained with an exact pack receipt."
            )
            let updatedCase = try result.continuityCase.adding(reference: reference)
            let updatedBook = try result.casebook.replacing(updatedCase)
            try commitContinuityCasebook(
                updatedBook,
                selectedCaseID: updatedCase.id,
                message: "Attached \(reference.entries.count) reviewed \(reference.kind.label.lowercased()) entr\(reference.entries.count == 1 ? "y" : "ies") to \(updatedCase.code)."
            )
            pendingContinuityReferenceReview = nil
            isContinuityReferenceReviewPresented = false
            selectedTool = .casebook
        } catch {
            continuityCasebookDiagnostic = error.localizedDescription
            showNotice("Reviewed reference attachment was blocked.")
        }
    }

    func prepareContinuityReferenceForAssist(referenceID: UUID, entryID: UUID) {
        guard let continuityCase = selectedContinuityCase,
              let reference = continuityCase.references.first(where: { $0.id == referenceID }),
              let entry = reference.entries.first(where: { $0.id == entryID }) else {
            continuityCasebookDiagnostic = "Select an attached reviewed reference entry before preparing Assist context."
            return
        }
        do {
            let fragment = try AIContextFragment(
                kind: .reviewedReference,
                documentName: "Reviewed \(reference.kind.rawValue) \(shortFingerprint(reference.fingerprint))",
                language: reference.kind == .repository
                    ? "Reviewed IBM i repository reference"
                    : "Reviewed IBM i runbook reference",
                sourceText: entry.content
            )
            let bundle = try pinPreparedAssistantContext(
                fragment,
                label: "\(reference.title) · \(entry.locator)"
            )
            assistantInput = "Use the explicitly reviewed \(reference.kind.label.lowercased()) entry \"\(entry.locator)\" as advice-only context. Cite what it supports, separate unsupported assumptions, and do not execute anything."
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: bundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            continuityCasebookDiagnostic = "Pinned one explicitly reviewed reference entry. No provider request or host action occurred."
            showNotice("Reviewed reference pinned. Inspect the exact Context Shelf before sending.")
        } catch {
            continuityCasebookDiagnostic = "Reviewed reference context was blocked: \(error.localizedDescription)"
            showNotice("Reviewed reference Assist context was blocked.")
        }
    }

    func discardContinuityReferenceReview() {
        pendingContinuityReferenceReview = nil
        isContinuityReferenceReviewPresented = false
    }

    func updateSelectedContinuityWorkflow(
        title: String,
        summary: String,
        openQuestions: [String],
        nextAction: String,
        staleBoundary: String,
        receiverAcknowledged: Bool
    ) {
        guard !continuityCasebookUsesReplay, let selectedContinuityCase else {
            continuityCasebookDiagnostic = "Create or capture a local case before editing the replay."
            return
        }
        do {
            let updatedCase = try selectedContinuityCase.updatingWorkflow(
                title: title,
                summary: summary,
                openQuestions: openQuestions,
                nextAction: nextAction,
                staleBoundary: staleBoundary,
                receiverAcknowledged: receiverAcknowledged,
                phase: selectedContinuityCase.phase == .handedOff ? .reopened : selectedContinuityCase.phase
            )
            let updatedBook = try continuityCasebook.replacing(updatedCase)
            try commitContinuityCasebook(
                updatedBook,
                selectedCaseID: updatedCase.id,
                message: "Updated \(updatedCase.code) locally."
            )
        } catch {
            continuityCasebookDiagnostic = error.localizedDescription
            showNotice("Case details were not changed.")
        }
    }

    func createContinuityHandoffSnapshot() {
        guard !continuityCasebookUsesReplay, let selectedContinuityCase else {
            continuityCasebookDiagnostic = "Create or capture a local case before making an immutable snapshot."
            return
        }
        do {
            var workingBook = continuityCasebook
            var caseForSnapshot = selectedContinuityCase
            if caseForSnapshot.readinessGaps.isEmpty {
                caseForSnapshot = try caseForSnapshot.updatingWorkflow(phase: .handedOff)
                workingBook = try workingBook.replacing(caseForSnapshot)
            }
            let result = try workingBook.snapshotting(caseID: caseForSnapshot.id)
            try commitContinuityCasebook(
                result.casebook,
                selectedCaseID: caseForSnapshot.id,
                message: result.snapshot.readinessGaps.isEmpty
                    ? "Created a ready immutable snapshot for \(caseForSnapshot.code)."
                    : "Created an immutable snapshot with \(result.snapshot.readinessGaps.count) open gate\(result.snapshot.readinessGaps.count == 1 ? "" : "s")."
            )
            latestContinuitySnapshot = result.snapshot
            isContinuitySnapshotPresented = true
        } catch {
            continuityCasebookDiagnostic = error.localizedDescription
            showNotice("Handoff snapshot creation was blocked.")
        }
    }

    func previewLatestContinuitySnapshot() {
        guard let snapshot = latestContinuitySnapshot ?? selectedContinuitySnapshots.first else {
            continuityCasebookDiagnostic = "Create a handoff snapshot before opening its immutable manifest."
            return
        }
        latestContinuitySnapshot = snapshot
        isContinuitySnapshotPresented = true
    }

    func exportLatestContinuitySnapshot() {
        guard let snapshot = latestContinuitySnapshot ?? selectedContinuitySnapshots.first else {
            continuityCasebookDiagnostic = "Create a handoff snapshot before exporting it."
            return
        }
        do {
            let json = try continuityCasebookStore.snapshotJSON(snapshot)
            terminalExport.saveJSON(
                json,
                suggestedName: "\(snapshot.caseRecord.code)-handoff-\(shortFingerprint(snapshot.fingerprint))"
            ) { [weak self] result in
                switch result {
                case .success(let url): self?.showNotice("Exported \(url.lastPathComponent).")
                case .failure(let error): self?.showNotice("Handoff export failed: \(error.localizedDescription)")
                }
            }
        } catch {
            continuityCasebookDiagnostic = error.localizedDescription
            showNotice("Handoff export was blocked.")
        }
    }

    private func writableContinuityCase(
        kind: ContinuityCaseKind,
        title: String,
        summary: String
    ) throws -> (casebook: ContinuityCasebook, continuityCase: ContinuityCase) {
        if !continuityCasebookUsesReplay,
           let selectedContinuityCase,
           selectedContinuityCase.phase != .closed {
            return (continuityCasebook, selectedContinuityCase)
        }
        var casebook = ContinuityCasebook.empty
        if !continuityCasebookUsesReplay {
            casebook = continuityCasebook
        }
        let continuityCase = try ContinuityCase(
            code: nextContinuityCaseCode(kind: kind, in: casebook),
            kind: kind,
            title: title,
            target: selectedProfile?.name ?? "LOCAL WORKBENCH",
            environment: selectedProfile?.environment ?? .development,
            summary: summary,
            nextAction: "Review the exact retained evidence and record the next verified action.",
            staleBoundary: "Refresh time-sensitive host evidence before relying on it."
        )
        casebook = try casebook.adding(continuityCase)
        return (casebook, continuityCase)
    }

    private func inferredContinuityCaseKind(for bundle: AIContextBundle) -> ContinuityCaseKind {
        let kinds = Set(bundle.fragments.map(\.kind))
        if kinds.contains(.jobIncident) || kinds.contains(.spoolOutput) || kinds.contains(.systemHealth) {
            return .incident
        }
        if kinds.contains(.compileEvidence) || kinds.contains(.sourceDraft) || kinds.contains(.sourceSelection) {
            return .build
        }
        if kinds.contains(.dataTransfer) { return .transfer }
        if kinds.contains(.objectImpact) || kinds.contains(.authorityReview) { return .change }
        return .general
    }

    private func nextContinuityCaseCode(
        kind: ContinuityCaseKind,
        in casebook: ContinuityCasebook
    ) -> String {
        let highest = casebook.cases
            .filter { $0.kind == kind }
            .compactMap { Int($0.code.suffix(4)) }
            .max() ?? 0
        return String(format: "%@-%04d", kind.codePrefix, min(highest + 1, 9_999))
    }

    private func commitContinuityCasebook(
        _ updated: ContinuityCasebook,
        selectedCaseID: UUID,
        message: String
    ) throws {
        try continuityCasebookStore.write(updated)
        continuityCasebook = updated
        self.selectedContinuityCaseID = selectedCaseID
        continuityCasebookUsesReplay = false
        continuityCasebookDiagnostic = message
        showNotice(message)
    }

    private func shortFingerprint(_ value: String) -> String {
        String(value.prefix(8)).uppercased() + "-" + String(value.suffix(4)).uppercased()
    }

    func saveProfile(_ profile: SessionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        if selectedTerminalSession?.profileID != profile.id {
            selectedTerminalSessionID = nil
        }
        selectedProfileID = profile.id
        persistProfiles()
    }

    func presentNewSession() {
        cancelTestConnection()
        editingProfile = nil
        connectionDiagnostic = nil
        connectionDiagnosticSucceeded = false
        isConnectionStudioPresented = true
    }

    func presentEditSession(_ profile: SessionProfile) {
        cancelTestConnection()
        editingProfile = profile
        connectionDiagnostic = nil
        connectionDiagnosticSucceeded = false
        isConnectionStudioPresented = true
    }

    func requestDeleteProfile(_ profile: SessionProfile) {
        profilePendingDeletion = profile
    }

    func deleteProfile(_ profile: SessionProfile) {
        let sessionIDs = terminalSessions
            .filter { $0.profileID == profile.id }
            .map(\.id)
        for sessionID in sessionIDs {
            closeTerminalSession(sessionID, announces: false)
        }
        profiles.removeAll { $0.id == profile.id }
        if selectedProfileID == profile.id {
            selectedProfileID = selectedTerminalSession?.profileID
        }
        profilePendingDeletion = nil
        persistProfiles()
        showNotice("Removed session profile “\(profile.name)”.")
    }

    func copyVisibleScreen(_ sourceScreen: TerminalScreen? = nil) {
        terminalExport.copyText(sourceScreen ?? screen)
        showNotice("Visible 5250 screen copied with sensitive fields hidden.")
    }

    func copyTerminalSelection(_ selection: TerminalSelection) {
        let text = selection.text(from: screen)
        guard !text.isEmpty else {
            showNotice("The terminal selection does not contain visible text.")
            return
        }
        terminalExport.copyString(text)
        showNotice("Copied a \(selection.selectedRowCount)×\(selection.selectedColumnCount) terminal selection with sensitive cells hidden.")
    }

    func copyAssistantText(_ text: String) {
        terminalExport.copyString(text)
        showNotice("Assistant response copied.")
    }

    func captureScreen(_ sourceScreen: TerminalScreen? = nil) {
        let sourceScreen = sourceScreen ?? screen
        let name = selectedProfile?.name ?? "itelas-screen"
        terminalExport.savePNG(sourceScreen, suggestedName: name) { [weak self] result in
            switch result {
            case .success(let url):
                self?.showNotice("Saved screen capture to \(url.lastPathComponent).")
            case .failure(let error):
                self?.showNotice("Screen capture failed: \(error.localizedDescription)")
            }
        }
    }

    func exportScreenPDF(_ sourceScreen: TerminalScreen? = nil) {
        let sourceScreen = sourceScreen ?? screen
        let name = selectedProfile?.name ?? "itelas-screen"
        terminalExport.savePDF(sourceScreen, suggestedName: name) { [weak self] result in
            switch result {
            case .success(let url):
                self?.showNotice("Exported redacted screen PDF to \(url.lastPathComponent).")
            case .failure(let error):
                self?.showNotice("Screen PDF export failed: \(error.localizedDescription)")
            }
        }
    }

    func printScreenSnapshot(_ sourceScreen: TerminalScreen? = nil) {
        let sourceScreen = sourceScreen ?? screen
        let name = selectedProfile?.name ?? "itelas-screen"
        if terminalExport.printSnapshot(sourceScreen, suggestedName: name) {
            showNotice("Submitted the redacted screen snapshot to the selected macOS printer workflow.")
        }
    }

    func selectProfile(_ profile: SessionProfile) {
        selectedProfileID = profile.id
        if let session = terminalSessions.last(where: { $0.profileID == profile.id }) {
            selectTerminalSession(session.id)
        } else {
            selectedTerminalSessionID = nil
        }
    }

    func selectTerminalSession(_ sessionID: UUID) {
        guard let session = terminalSessions.first(where: { $0.id == sessionID }) else { return }
        selectedTerminalSessionID = sessionID
        selectedProfileID = session.profileID
        selectedTool = .terminal
    }

    func selectAdjacentTerminalSession(_ direction: Int) {
        guard !terminalSessions.isEmpty, direction != 0 else { return }
        let targetIndex: Int
        if let selectedTerminalSessionIndex {
            targetIndex = (selectedTerminalSessionIndex + direction % terminalSessions.count + terminalSessions.count)
                % terminalSessions.count
        } else {
            targetIndex = direction < 0 ? terminalSessions.count - 1 : 0
        }
        selectTerminalSession(terminalSessions[targetIndex].id)
    }

    func connect(_ profile: SessionProfile) {
        if let selectedTerminalSession,
           selectedTerminalSession.profileID == profile.id,
           selectedTerminalSession.isTransportActive {
            selectedProfileID = profile.id
            selectedTool = .terminal
            showNotice("\(profile.name) is already open in the selected session.")
            return
        }
        if let activeSession = terminalSessions.last(where: {
            $0.profileID == profile.id && $0.isTransportActive
        }) {
            selectTerminalSession(activeSession.id)
            showNotice("Switched to the open \(profile.name) session.")
            return
        }
        if let retainedSession = terminalSessions.last(where: { $0.profileID == profile.id }) {
            selectTerminalSession(retainedSession.id)
            start(profile, sessionID: retainedSession.id, reconnecting: false)
            return
        }
        openAdditionalSession(profile)
    }

    func openAdditionalSession(_ profile: SessionProfile) {
        guard profile.validationErrors.isEmpty else {
            showNotice(profile.validationErrors.joined(separator: " "))
            return
        }
        let session = TerminalSessionState(profile: profile)
        terminalSessions.append(session)
        sessionTransports[session.id] = TerminalSessionTransportRuntime()
        selectTerminalSession(session.id)
        start(profile, sessionID: session.id, reconnecting: false)
    }

    func testConnection(_ profile: SessionProfile) {
        guard profile.validationErrors.isEmpty else {
            connectionDiagnostic = profile.validationErrors.joined(separator: " ")
            connectionDiagnosticSucceeded = false
            return
        }
        cancelTestConnection()
        let generation = UUID()
        activeTestGeneration = generation
        isTestingConnection = true
        connectionDiagnostic = "Opening an isolated transport probe. Existing terminal sessions remain untouched."
        connectionDiagnosticSucceeded = false
        do {
            let probe = try TN5250Client(profile: profile) { [weak self] event in
                Task { @MainActor in
                    self?.handleTestConnection(event, generation: generation)
                }
            }
            testClient = probe
            probe.connect()
        } catch {
            activeTestGeneration = nil
            testClient = nil
            isTestingConnection = false
            connectionDiagnostic = error.localizedDescription
        }
    }

    func disconnect() {
        guard let selectedTerminalSessionID else {
            showNotice("No open terminal session is selected.")
            return
        }
        disconnect(sessionID: selectedTerminalSessionID)
    }

    func disconnect(sessionID: UUID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let activeClient = sessionTransports[sessionID]?.invalidate()
        terminalSessions[index].reconnectAttempt = 0
        terminalSessions[index].connectionState = .disconnected
        terminalSessions[index].screen.inputInhibited = true
        terminalSessions[index].protocolNotice = "Session disconnected. The last screen remains available for reference."
        terminalSessions[index].lastActivityAt = Date()
        activeClient?.disconnect()
    }

    func closeTerminalSession(_ sessionID: UUID, announces: Bool = true) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let profileName = profiles.first(where: { $0.id == terminalSessions[index].profileID })?.name
            ?? "terminal"
        let activeClient = sessionTransports.removeValue(forKey: sessionID)?.invalidate()
        activeClient?.disconnect()
        terminalRecorderArmedSessionIDs.remove(sessionID)
        terminalMacroRunState = nil
        terminalSessions.remove(at: index)

        if selectedTerminalSessionID == sessionID {
            if terminalSessions.isEmpty {
                selectedTerminalSessionID = nil
            } else {
                let replacement = terminalSessions[min(index, terminalSessions.count - 1)]
                selectedTerminalSessionID = replacement.id
                selectedProfileID = replacement.profileID
            }
        }
        if announces {
            showNotice("Closed the \(profileName) terminal session. Its host connection is no longer active.")
        }
    }

    func presentTerminalFlightRecorder() {
        if let profileID = selectedProfile?.id,
           let latest = terminalFlightRecorder.frames.last(where: { $0.profileID == profileID }) {
            selectedTerminalEvidenceFrameID = latest.id
        } else if selectedTerminalEvidenceFrameID == nil {
            selectedTerminalEvidenceFrameID = terminalFlightRecorder.frames.last?.id
        }
        isScreenHistoryPresented = true
    }

    func selectTerminalEvidenceFrame(_ frameID: UUID) {
        guard terminalFlightRecorder.frames.contains(where: { $0.id == frameID }) else { return }
        selectedTerminalEvidenceFrameID = frameID
    }

    func selectTerminalMacro(_ macroID: UUID) {
        guard terminalFlightRecorder.macros.contains(where: { $0.id == macroID }) else { return }
        selectedTerminalMacroID = macroID
        terminalMacroRunState = nil
    }

    func toggleTerminalFlightRecorder() {
        guard let sessionID = selectedTerminalSessionID else {
            showNotice("Open a terminal session before arming the recorder.")
            return
        }
        if terminalRecorderArmedSessionIDs.remove(sessionID) != nil {
            terminalMacroRunState = nil
            terminalFlightRecorderDiagnostic = "Recording stopped for this session. Existing redacted evidence remains in local custody."
            showNotice("Session recorder disarmed. Retained evidence was not deleted.")
            return
        }
        terminalRecorderArmedSessionIDs.insert(sessionID)
        _ = captureTerminalEvidence(
            screen: screen,
            sessionID: sessionID,
            source: "Recorder armed by operator"
        )
        terminalFlightRecorderDiagnostic = "Recorder armed for the selected session. Only redacted host frames are retained."
        showNotice("Recorder armed for this session. Input and non-display fields are cleared before persistence.")
    }

    @discardableResult
    func bookmarkCurrentTerminalFrame() -> Bool {
        guard let sessionID = selectedTerminalSessionID else {
            showNotice("Open a terminal session before bookmarking evidence.")
            return false
        }
        let frame = captureTerminalEvidence(
            screen: screen,
            sessionID: sessionID,
            source: "Operator bookmark"
        )
        if frame != nil { showNotice("Bookmarked a redacted terminal evidence frame.") }
        return frame != nil
    }

    func updateTerminalHistoryRetention(_ retention: TerminalHistoryRetention) {
        prepareTerminalRecorderForActualUse()
        terminalFlightRecorder.policy.retention = retention
        terminalFlightRecorder.prune()
        selectedTerminalEvidenceFrameID = terminalFlightRecorder.frames.last?.id
        persistTerminalFlightRecorder(
            success: "Retention set to \(retention.rawValue) days; expired redacted frames were removed."
        )
    }

    func clearTerminalRecorderEvidence() {
        prepareTerminalRecorderForActualUse()
        terminalFlightRecorder.frames.removeAll()
        terminalFlightRecorder.receipts.removeAll()
        terminalFlightRecorder.updatedAt = recorderTimestamp()
        selectedTerminalEvidenceFrameID = nil
        terminalMacroRunState = nil
        persistTerminalFlightRecorder(success: "Cleared durable terminal frames and execution receipts. Macro drafts remain local.")
    }

    func copySelectedTerminalEvidence() {
        guard let frame = selectedTerminalEvidenceFrame else {
            showNotice("Select a terminal evidence frame first.")
            return
        }
        terminalExport.copyString(frame.visibleText)
        showNotice("Copied the redacted evidence frame. Cleared input cannot be recovered.")
    }

    func exportSelectedTerminalEvidence() {
        guard let frame = selectedTerminalEvidenceFrame else {
            showNotice("Select a terminal evidence frame first.")
            return
        }
        do {
            try frame.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(frame)
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            terminalExport.saveJSON(
                text + "\n",
                suggestedName: "itelas-terminal-frame-\(frame.shortFingerprint)",
                panelTitle: "Export Redacted Terminal Evidence"
            ) { [weak self] result in
                switch result {
                case .success:
                    self?.showNotice("Exported the redacted terminal evidence frame.")
                case .failure(let error):
                    self?.showNotice("Evidence export failed: \(error.localizedDescription)")
                }
            }
        } catch {
            showNotice("Evidence export blocked: \(error.localizedDescription)")
        }
    }

    func exportTerminalFlightRecorderArchive() {
        do {
            let text = try terminalFlightRecorderStore.exportJSON(terminalFlightRecorder)
            terminalExport.saveJSON(
                text,
                suggestedName: "itelas-session-flight-recorder",
                panelTitle: "Export Session Flight Recorder Archive"
            ) { [weak self] result in
                switch result {
                case .success:
                    self?.showNotice("Exported the redacted recorder archive. Treat it as sensitive local evidence.")
                case .failure(let error):
                    self?.showNotice("Recorder export failed: \(error.localizedDescription)")
                }
            }
        } catch {
            showNotice("Recorder export blocked: \(error.localizedDescription)")
        }
    }

    func beginNewTerminalMacroDraft() {
        let baseline = selectedTerminalEvidenceFrame?.screenFingerprint
        var steps: [TerminalMacroEditorStepDraft] = []
        if let baseline {
            steps.append(TerminalMacroEditorStepDraft(
                name: "Match selected screen",
                kind: .matchFrame,
                frameFingerprint: baseline
            ))
        }
        steps.append(TerminalMacroEditorStepDraft())
        terminalMacroEditorDraft = TerminalMacroEditorDraft(
            name: "New reviewed macro",
            targetProfileID: selectedProfile?.id ?? selectedTerminalEvidenceFrame?.profileID,
            steps: steps
        )
    }

    func editSelectedTerminalMacroAsDraft() {
        guard let macro = selectedTerminalMacro else {
            beginNewTerminalMacroDraft()
            return
        }
        terminalMacroEditorDraft = TerminalMacroEditorDraft(macro: macro)
    }

    func duplicateSelectedTerminalMacroAsDraft() {
        guard let macro = selectedTerminalMacro else {
            beginNewTerminalMacroDraft()
            return
        }
        terminalMacroEditorDraft = TerminalMacroEditorDraft(
            name: "\(macro.name) copy",
            targetProfileID: macro.targetProfileID,
            steps: macro.steps.map { step in
                var draft = TerminalMacroEditorStepDraft(step: step)
                draft.id = UUID()
                return draft
            }
        )
    }

    @discardableResult
    func saveTerminalMacroDraft(_ draft: TerminalMacroEditorDraft) -> Bool {
        prepareTerminalRecorderForActualUse()
        let macro = draft.resolvedMacro()
        do {
            try terminalFlightRecorder.upsert(macro)
            selectedTerminalMacroID = macro.id
            terminalMacroRunState = nil
            terminalMacroEditorDraft = nil
            persistTerminalFlightRecorder(success: "Saved the macro as an unreviewed local draft.")
            return true
        } catch {
            terminalFlightRecorderDiagnostic = "Macro draft blocked: \(error.localizedDescription)"
            showNotice(terminalFlightRecorderDiagnostic)
            return false
        }
    }

    func attestSelectedTerminalMacroReview() {
        guard let selectedTerminalMacroID,
              let index = terminalFlightRecorder.macros.firstIndex(where: { $0.id == selectedTerminalMacroID }) else {
            showNotice("Select a macro draft first.")
            return
        }
        var macro = terminalFlightRecorder.macros[index]
        do {
            try macro.attestReview(by: "LOCAL OPERATOR")
            terminalFlightRecorder.macros[index] = macro
            terminalMacroRunState = nil
            persistTerminalFlightRecorder(
                success: "Recorded a local review attestation for macro \(macro.shortFingerprint)."
            )
        } catch {
            terminalFlightRecorderDiagnostic = "Macro review blocked: \(error.localizedDescription)"
            showNotice(terminalFlightRecorderDiagnostic)
        }
    }

    func deleteSelectedTerminalMacro() {
        if terminalFlightRecorderUsesReplay {
            prepareTerminalRecorderForActualUse()
            persistTerminalFlightRecorder(success: "Closed the deterministic recorder replay. No sample macro was saved.")
            return
        }
        guard let selectedTerminalMacroID,
              let index = terminalFlightRecorder.macros.firstIndex(where: { $0.id == selectedTerminalMacroID }) else {
            return
        }
        terminalFlightRecorder.macros.remove(at: index)
        terminalFlightRecorder.receipts.removeAll { $0.macroID == selectedTerminalMacroID }
        self.selectedTerminalMacroID = terminalFlightRecorder.macros.first?.id
        terminalMacroRunState = nil
        persistTerminalFlightRecorder(success: "Deleted the selected local macro and its execution receipts.")
    }

    func resetSelectedTerminalMacroRun() {
        guard let macro = selectedTerminalMacro else { return }
        terminalMacroRunState = TerminalMacroRunState(macro: macro)
        terminalFlightRecorderDiagnostic = "Macro reset to step 1. Nothing was sent to a host."
    }

    func runSelectedTerminalMacroStep() {
        guard let macro = selectedTerminalMacro else {
            showNotice("Select a reviewed macro first.")
            return
        }
        guard macro.isReviewCurrent else {
            showNotice("Review this exact macro draft before running a step.")
            return
        }
        guard let session = selectedTerminalSession,
              let profile = profile(for: session) else {
            showNotice("Select an open terminal session before running a macro step.")
            return
        }
        guard macro.targetProfileID == nil || macro.targetProfileID == profile.id else {
            showNotice("The selected macro is bound to a different session profile.")
            return
        }

        var run = terminalMacroRunState
        if run?.macroID != macro.id || run?.macroFingerprint != macro.contentFingerprint {
            run = TerminalMacroRunState(macro: macro)
        }
        guard var activeRun = run, activeRun.nextStepIndex < macro.steps.count else {
            showNotice("Every step in this macro route is complete. Reset it to begin again.")
            return
        }

        let stepIndex = activeRun.nextStepIndex
        let step = macro.steps[stepIndex]
        let observedFrame = TerminalEvidenceFrame(
            profileID: profile.id,
            profileName: profile.name,
            deviceName: startupResponse?.deviceName ?? profile.deviceName,
            screen: screen
        )
        let expectedFingerprint: String? = if case .matchFrame(let fingerprint) = step.action {
            fingerprint
        } else {
            nil
        }

        let passed: Bool
        let detail: String
        switch step.action {
        case .matchFrame(let fingerprint):
            passed = observedFrame.screenFingerprint == fingerprint
            detail = passed
                ? "Exact redacted screen matched."
                : "Current redacted screen does not match the reviewed baseline."
        case .stageReadOnlyCommand(let command):
            passed = stageReadOnlyHostCommand(command)
            detail = passed
                ? "Read-only command staged in the visible field without submission."
                : "The command was not staged; the terminal gate remained closed."
        case .fieldExit(let kind):
            let mapped: TerminalFieldExitKind = switch kind {
            case .neutral: .neutral
            case .positive: .positive
            case .negative: .negative
            }
            passed = performTerminalFieldExit(mapped)
            detail = passed
                ? "The selected field-exit action completed; the route paused."
                : "The field-exit action was blocked by the current field contract."
        case .sendAID(let code):
            passed = sendAID(code)
            detail = passed
                ? "\(TerminalMacroAction.aidLabel(code)) was sent by explicit operator action; the route paused."
                : "The host key was not sent; the route remains on this step."
        case .bookmark:
            passed = bookmarkCurrentTerminalFrame()
            detail = passed
                ? "Captured a redacted durable evidence frame."
                : "No evidence frame was captured."
        }

        let receipt = TerminalMacroStepReceipt(
            macroID: macro.id,
            macroFingerprint: macro.contentFingerprint,
            stepID: step.id,
            stepOrdinal: stepIndex + 1,
            actionLabel: step.action.kindLabel,
            expectedScreenFingerprint: expectedFingerprint,
            observedScreenFingerprint: observedFrame.screenFingerprint,
            outcome: passed ? .passed : .blocked,
            detail: detail
        )
        do {
            try terminalFlightRecorder.append(receipt)
            if passed {
                activeRun.completedStepIDs.append(step.id)
                activeRun.nextStepIndex += 1
            }
            terminalMacroRunState = activeRun
            persistTerminalFlightRecorder(
                success: passed
                    ? "Step \(stepIndex + 1) passed. The macro route is paused before the next step."
                    : "Step \(stepIndex + 1) was blocked. No later step ran."
            )
        } catch {
            terminalFlightRecorderDiagnostic = "Macro receipt could not be retained: \(error.localizedDescription)"
            showNotice(terminalFlightRecorderDiagnostic)
        }
    }

    @discardableResult
    func sendAID(_ aid: UInt8) -> Bool {
        guard case .connected = connectionState,
              let selectedTerminalSessionID,
              let client = sessionTransports[selectedTerminalSessionID]?.client else {
            showNotice("Connect an IBM i session before sending a host key.")
            return false
        }
        guard !screen.inputInhibited else {
            showNotice("Keyboard is inhibited while IBM i is processing.")
            return false
        }
        switch screen.prepareForAID(aid) {
        case .ready:
            break
        case .rejected(let issue):
            showNotice(issue.message)
            return false
        }
        screen.inputInhibited = true
        client.sendAID(aid, screen: screen)
        return true
    }

    @discardableResult
    func sendFunctionKey(slot: Int) -> Bool {
        guard let binding = terminalFunctionKeyBinding(for: slot),
              let aid = TN5250AID.function(binding.hostFunction) else {
            showNotice("The selected function key does not have a valid host AID.")
            return false
        }
        return sendAID(aid)
    }

    @discardableResult
    func insertTerminalCharacter(_ character: Character) -> Bool {
        guard case .connected = connectionState, !screen.inputInhibited else { return false }
        do {
            let codec = try EBCDICCodec(ccsid: selectedProfile?.ccsid ?? 37)
            _ = try codec.encode(String(character))
        } catch {
            showNotice("That character is not representable in CCSID \(selectedProfile?.ccsid ?? 37).")
            return false
        }
        let result = screen.typeCharacter(character, insertMode: isTerminalInsertMode)
        guard result.wasAccepted else {
            if case .rejected(let issue) = result {
                let contract = screen.currentEditableFieldContract.map { " Field contract: \($0)." } ?? ""
                showNotice(issue.message + contract)
            }
            return false
        }
        if result == .autoEnter {
            sendAID(TN5250AID.enter.rawValue)
        } else if result == .forwardEdgeTrigger {
            sendAID(TN5250AID.forwardEdgeTrigger.rawValue)
        }
        return true
    }

    @discardableResult
    func performTerminalFieldExit(_ kind: TerminalFieldExitKind = .neutral) -> Bool {
        guard case .connected = connectionState, !screen.inputInhibited else {
            showNotice("Connect an unlocked IBM i session before using a field-exit key.")
            return false
        }
        let result = screen.performFieldExit(kind)
        switch result {
        case .rejected(let issue):
            showNotice(issue.message)
            return false
        case .advanced:
            return true
        case .autoEnter:
            sendAID(TN5250AID.enter.rawValue)
            return true
        case .forwardEdgeTrigger:
            sendAID(TN5250AID.forwardEdgeTrigger.rawValue)
            return true
        }
    }

    @discardableResult
    func duplicateTerminalField() -> Bool {
        guard case .connected = connectionState, !screen.inputInhibited else {
            showNotice("Connect an unlocked IBM i session before using Dup.")
            return false
        }
        let result = screen.duplicateCurrentField()
        switch result {
        case .rejected(let issue):
            showNotice(issue.message)
            return false
        case .advanced:
            return true
        case .autoEnter:
            sendAID(TN5250AID.enter.rawValue)
            return true
        case .forwardEdgeTrigger:
            sendAID(TN5250AID.forwardEdgeTrigger.rawValue)
            return true
        }
    }

    func pasteTerminalText(_ text: String) -> TerminalPasteResult {
        guard case .connected = connectionState, !screen.inputInhibited else {
            showNotice("Keyboard is inhibited; clipboard text was not inserted.")
            return TerminalPasteResult(insertedCharacters: 0, skippedCharacters: text.count, fieldsTouched: 0)
        }

        let codec = try? EBCDICCodec(ccsid: selectedProfile?.ccsid ?? 37)
        var skippedForEncoding = 0
        let filtered = String(text.filter { character in
            if character == "\t" || character == "\n" || character == "\r" { return true }
            guard let codec, (try? codec.encode(String(character))) != nil else {
                skippedForEncoding += 1
                return false
            }
            return true
        })
        let inserted = screen.pasteText(filtered, insertMode: isTerminalInsertMode)
        let result = TerminalPasteResult(
            insertedCharacters: inserted.insertedCharacters,
            skippedCharacters: inserted.skippedCharacters + skippedForEncoding,
            fieldsTouched: inserted.fieldsTouched
        )
        if screen.isCurrentInputFieldForwardEdgeTrigger {
            let skippedSuffix = result.skippedCharacters == 0
                ? ""
                : " Skipped \(result.skippedCharacters) remaining or incompatible character(s) at that boundary."
            showNotice(
                "Inserted \(result.insertedCharacters) characters. The forward-edge field is staged; paste sent no AID.\(skippedSuffix) Use Field Exit to submit it."
            )
        } else {
            showNotice(result.skippedCharacters == 0
                ? "Inserted \(result.insertedCharacters) characters across \(result.fieldsTouched) field(s)."
                : "Inserted \(result.insertedCharacters); skipped \(result.skippedCharacters) incompatible or overflowing characters.")
        }
        return result
    }

    func toggleTerminalInsertMode() {
        isTerminalInsertMode.toggle()
        showNotice(isTerminalInsertMode ? "5250 insert mode enabled." : "5250 overwrite mode enabled.")
    }

    func terminalClipboardText() -> String? {
        terminalExport.readString()
    }

    func hostCommandStagingStatus(for command: String) -> HostCommandStagingStatus {
        guard commandClassifier.classify(command) == .readOnly else { return .notReadOnly }
        guard case .connected = connectionState else { return .disconnected }
        guard !screen.inputInhibited else { return .keyboardInhibited }
        guard screen.currentEditableFieldOrdinal != nil else { return .noCurrentField }
        guard !screen.isCurrentInputFieldNonDisplay else { return .nonDisplayField }
        guard screen.isLikelyCommandEntryScreen else { return .notCommandEntry }
        let capacity = screen.currentEditableFieldLength ?? 0
        guard command.count <= capacity else { return .commandTooLong(capacity: capacity) }
        return .ready(field: screen.currentEditableFieldOrdinal ?? 1, total: screen.editableFieldCount)
    }

    @discardableResult
    func stageReadOnlyHostCommand(_ command: String) -> Bool {
        let status = hostCommandStagingStatus(for: command)
        guard status.isReady else {
            showNotice(status.message)
            return false
        }

        do {
            let codec = try EBCDICCodec(ccsid: selectedProfile?.ccsid ?? 37)
            _ = try codec.encode(command)
        } catch {
            showNotice("The command cannot be represented in CCSID \(selectedProfile?.ccsid ?? 37).")
            return false
        }

        let result = screen.stageTextInCurrentInputField(command)
        guard result.insertedCharacters == command.count,
              result.skippedCharacters == 0,
              result.fieldsTouched == 1 else {
            showNotice("The command was not staged because the host field changed.")
            return false
        }
        selectedTool = .terminal
        showNotice("Staged \(command). Review the host screen, then press Enter yourself.")
        return true
    }

    func updateAIConfiguration(_ configuration: AIConfiguration, apiKey: String?) throws {
        guard configuration.validationErrors.isEmpty else {
            throw AIConfigurationError.invalid(configuration.validationErrors)
        }
        aiConfiguration = configuration
        if let apiKey {
            let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedKey.isEmpty {
                try keychain.writeAPIKey(normalizedKey)
            }
        }
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: DefaultsKey.aiConfiguration)
        }
        if configuration.contextMode == .visibleScreen {
            updateAutomaticScreenContext(true)
        } else {
            includeScreenContext = false
        }
    }

    func forgetAPIKey() throws {
        try keychain.deleteAPIKey()
        showNotice("Removed the AI provider key from macOS Keychain.")
    }

    var currentRedactedAIContext: String? {
        guard includeScreenContext, aiConfiguration.contextMode == .visibleScreen else { return nil }
        return redactor.redact(screen: screen)
    }

    var currentAssistantContextBundle: AIContextBundle? {
        try? buildCurrentAssistantContextBundle()
    }

    func buildCurrentAssistantContextBundle() throws -> AIContextBundle? {
        var fragments = preparedAssistantContextBundle?.fragments ?? []
        if let screenFragment = try automaticScreenContextFragment(),
           !fragments.contains(where: { $0.kind == .terminalScreen }),
           !screenFragment.content.isEmpty {
            fragments.append(screenFragment)
        }
        guard !fragments.isEmpty else { return nil }
        return try AIContextBundle(fragments: fragments)
    }

    private func automaticScreenContextFragment() throws -> AIContextFragment? {
        guard let context = currentRedactedAIContext else { return nil }
        return try AIContextFragment(
            kind: .terminalScreen,
            documentName: selectedProfile?.name ?? "Active TN5250 session",
            language: "TN5250",
            sourceText: context
        )
    }

    func updateAutomaticScreenContext(_ enabled: Bool) {
        includeScreenContext = enabled
        do {
            _ = try buildCurrentAssistantContextBundle()
            assistantError = nil
        } catch {
            includeScreenContext = false
            assistantError = "Automatic screen context was not enabled: \(error.localizedDescription)"
        }
    }

    func buildAIReviewContextBundle() throws -> AIContextBundle {
        guard let draft = aiReviewDraft else { throw AIContextError.emptyContext }
        let primary = try AIContextFragment(
            kind: draft.contextKind,
            documentName: draft.documentName,
            language: draft.language,
            sourceText: draft.sourceText,
            selection: draft.proposalSelection
        )
        var fragments = [primary]
        if draft.includeTerminalScreen, let terminalContextText = draft.terminalContextText {
            fragments.append(try AIContextFragment(
                kind: .terminalScreen,
                documentName: draft.terminalDocumentName ?? "Active TN5250 session",
                language: "TN5250",
                sourceText: terminalContextText
            ))
        }
        return try AIContextBundle(fragments: fragments)
    }

    func pinAIReviewContextToShelf() {
        do {
            let reviewBundle = try buildAIReviewContextBundle()
            let shelfBundle = try pinPreparedAssistantContexts(
                reviewBundle.fragments,
                label: "\(reviewBundle.fragments[0].documentName) review context"
            )
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: shelfBundle,
                conversationTurns: assistantMessages.count
            )
            isAssistantVisible = true
            isAIContextPreviewPresented = true
            showNotice("Review context pinned. Inspect the Context Shelf before sending.")
        } catch {
            aiProposalDiagnostic = "Context Shelf update was blocked: \(error.localizedDescription)"
        }
    }

    func updateAIReviewScope(_ scope: AIReviewContextScope) {
        guard var draft = aiReviewDraft else { return }
        draft.scope = scope == .selection && draft.selection == nil ? .wholeDraft : scope
        aiReviewDraft = draft
        latestAIEditProposal = nil
        latestAIProposalExplanation = nil
        aiProposalDiagnostic = nil
        aiProposalWasApplied = false
    }

    func updateAIReviewQuestion(_ question: String) {
        guard var draft = aiReviewDraft, draft.question != question else { return }
        draft.question = question
        aiReviewDraft = draft
        latestAIEditProposal = nil
        latestAIProposalExplanation = nil
        aiProposalDiagnostic = nil
        aiProposalWasApplied = false
    }

    func updateAIReviewIncludesTerminal(_ includesTerminal: Bool) {
        guard var draft = aiReviewDraft else { return }
        draft.includeTerminalScreen = includesTerminal
        draft.terminalContextText = includesTerminal ? redactor.redact(screen: screen) : nil
        draft.terminalDocumentName = includesTerminal
            ? selectedProfile?.name ?? "Active TN5250 session"
            : nil
        aiReviewDraft = draft
        latestAIEditProposal = nil
        latestAIProposalExplanation = nil
        aiProposalDiagnostic = nil
        aiProposalWasApplied = false
    }

    func previewCurrentAIContext() {
        do {
            latestAIContextReceipt = makeContextReceipt(
                contextBundle: try buildCurrentAssistantContextBundle(),
                conversationTurns: assistantMessages.count
            )
            isAIContextPreviewPresented = true
        } catch {
            assistantError = "Context Shelf preview was blocked: \(error.localizedDescription)"
        }
    }

    func assistantRequestReceipt(for message: AssistantMessage) -> AIContextReceipt? {
        guard message.role == .assistant else { return nil }
        return assistantRequestReceipts.receipt(for: message.id)
    }

    func isAssistantRequestReceiptExpired(for message: AssistantMessage) -> Bool {
        message.role == .assistant
            && message.provenance != nil
            && assistantRequestReceipts.receipt(for: message.id) == nil
    }

    func presentAssistantRequestReceipt(for message: AssistantMessage) {
        selectedAssistantRequestReceipt = assistantRequestReceipt(for: message)
    }

    func clearAssistantConversation() {
        cancelAssistantResponse(preservingPartial: false)
        assistantMessages.removeAll()
        assistantRequestReceipts.removeAll()
        selectedAssistantRequestReceipt = nil
        assistantError = nil
        clearPreparedAssistantContext()
    }

    func cancelAssistantResponse() {
        cancelAssistantResponse(preservingPartial: true)
    }

    func askAssistant() {
        let question = assistantInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAssistantResponding else { return }
        let contextBundle: AIContextBundle?
        do {
            contextBundle = try buildCurrentAssistantContextBundle()
        } catch {
            assistantError = "Context Shelf request was blocked: \(error.localizedDescription)"
            return
        }
        let priorConversation = assistantMessages
        assistantInput = ""
        assistantError = nil
        assistantMessages.append(.init(role: .user, content: question))

        guard aiConfiguration.isEnabled else {
            assistantError = "Enable AI Assist in Settings first."
            isAISettingsPresented = true
            return
        }
        guard let apiKey = (try? keychain.readAPIKey()) ?? nil, !apiKey.isEmpty else {
            assistantError = "Add an API key in AI Assist Settings."
            isAISettingsPresented = true
            return
        }

        isAssistantResponding = true
        let configuration = aiConfiguration
        let requestReceipt = makeContextReceipt(
            contextBundle: contextBundle,
            conversationTurns: priorConversation.count,
            configuration: configuration,
            question: question
        )
        latestAIContextReceipt = requestReceipt
        let provenance = makeAssistantProvenance(
            question: question,
            receipt: requestReceipt
        )

        let generation = UUID()
        activeAssistantGeneration = generation
        activeAssistantRequestKind = .chat
        activeAssistantProvenance = provenance
        activeAssistantRequestReceipt = requestReceipt
        assistantStreamingText = ""
        assistantResponsePhase = .connecting
        assistantTask = Task { [weak self] in
            guard let self else { return }
            do {
                let answer = try await aiService.askStreaming(
                    question: question,
                    conversation: priorConversation,
                    contextBundle: contextBundle,
                    configuration: configuration,
                    apiKey: apiKey,
                    onDelta: { [weak self] delta in
                        guard let self, self.activeAssistantGeneration == generation else { return }
                        self.assistantStreamingText.append(delta)
                        self.assistantResponsePhase = .streaming
                    }
                )
                guard activeAssistantGeneration == generation else { return }
                appendAssistantResponse(
                    content: answer,
                    commandRisk: inferCommandRisk(in: answer),
                    provenance: provenance,
                    requestReceipt: requestReceipt
                )
            } catch is CancellationError {
                guard activeAssistantGeneration == generation else { return }
                preservePartialAssistantResponse(as: .stopped)
            } catch {
                guard activeAssistantGeneration == generation else { return }
                preservePartialAssistantResponse(as: .interrupted)
                assistantError = error.localizedDescription
            }
            finishAssistantRequest(generation)
        }
    }

    func sendAIReviewRequest() {
        guard let draft = aiReviewDraft, !isAssistantResponding else { return }
        let question = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            aiProposalDiagnostic = "Write a review question before sending."
            return
        }
        guard aiConfiguration.isEnabled else {
            aiProposalDiagnostic = "Enable AI Assist in Settings before sending."
            isAISettingsPresented = true
            return
        }
        guard let apiKey = (try? keychain.readAPIKey()) ?? nil, !apiKey.isEmpty else {
            aiProposalDiagnostic = "Add an API key in AI Assist Settings before sending."
            isAISettingsPresented = true
            return
        }

        let bundle: AIContextBundle
        do {
            bundle = try buildAIReviewContextBundle()
        } catch {
            aiProposalDiagnostic = error.localizedDescription
            return
        }
        guard let primary = bundle.fragments.first(where: { $0.kind != .terminalScreen }) else {
            aiProposalDiagnostic = "A source or SQL context item is required."
            return
        }
        let contract = primary.wasRedacted ? nil : AIProposalContract(
            target: draft.target,
            documentName: primary.documentName,
            baselineSHA256: primary.baselineSHA256,
            selection: draft.proposalSelection
        )
        let priorConversation = assistantMessages
        let configuration = aiConfiguration
        let draftID = draft.id
        let requestReceipt = makeContextReceipt(
            contextBundle: bundle,
            conversationTurns: priorConversation.count,
            configuration: configuration,
            question: question
        )
        latestAIContextReceipt = requestReceipt
        let provenance = makeAssistantProvenance(
            question: question,
            receipt: requestReceipt
        )
        latestAIEditProposal = nil
        latestAIProposalExplanation = nil
        aiProposalWasApplied = false
        aiProposalDiagnostic = primary.wasRedacted
            ? "Sensitive markers were redacted. This request is advice-only; local proposals are disabled."
            : "Sending one bounded review request."
        assistantError = nil
        assistantMessages.append(.init(role: .user, content: question))
        isAssistantResponding = true

        let generation = UUID()
        activeAssistantGeneration = generation
        activeAssistantRequestKind = .review
        activeAssistantProvenance = provenance
        activeAssistantRequestReceipt = requestReceipt
        assistantStreamingText = ""
        assistantResponsePhase = .reviewing
        assistantTask = Task { [weak self] in
            guard let self else { return }
            do {
                let answer = try await aiService.ask(
                    question: question,
                    conversation: priorConversation,
                    contextBundle: bundle,
                    proposalContract: contract,
                    configuration: configuration,
                    apiKey: apiKey
                )
                guard activeAssistantGeneration == generation,
                      aiReviewDraft?.id == draftID else { return }
                do {
                    let parsed = try proposalParser.parse(answer)
                    if let proposal = parsed.proposal {
                        guard let contract,
                              proposal.target == contract.target,
                              proposal.documentName == contract.documentName,
                              proposal.baselineSHA256 == contract.baselineSHA256,
                              proposal.selection == contract.selection else {
                            throw AIProposalError.contractMismatch
                        }
                    }
                    let explanation = parsed.explanation.isEmpty
                        ? "Assist returned a local edit proposal for review."
                        : parsed.explanation
                    latestAIProposalExplanation = explanation
                    latestAIEditProposal = parsed.proposal
                    appendAssistantResponse(
                        content: explanation,
                        commandRisk: inferCommandRisk(in: explanation),
                        provenance: provenance,
                        requestReceipt: requestReceipt
                    )
                    aiProposalDiagnostic = parsed.proposal == nil
                        ? "Advice received. No local edit proposal was included."
                        : "One inert local proposal was parsed. Review every changed line before applying."
                } catch {
                    latestAIProposalExplanation = answer
                    latestAIEditProposal = nil
                    aiProposalDiagnostic = "Proposal blocked: \(error.localizedDescription)"
                    appendAssistantResponse(
                        content: "The response was received, but its edit proposal failed iTelAS validation. No draft changed.",
                        provenance: provenance,
                        requestReceipt: requestReceipt
                    )
                }
            } catch is CancellationError {
                guard activeAssistantGeneration == generation else { return }
                aiProposalDiagnostic = "Review request stopped. No proposal changed."
            } catch {
                guard activeAssistantGeneration == generation else { return }
                assistantError = error.localizedDescription
                aiProposalDiagnostic = error.localizedDescription
            }
            finishAssistantRequest(generation)
        }
    }

    private func appendAssistantResponse(
        content: String,
        commandRisk: CommandRisk? = nil,
        completionState: AssistantMessage.CompletionState = .complete,
        provenance: AssistantResponseProvenance?,
        requestReceipt: AIContextReceipt?
    ) {
        let message = AssistantMessage(
            role: .assistant,
            content: content,
            commandRisk: commandRisk,
            completionState: completionState,
            provenance: provenance
        )
        assistantMessages.append(message)
        if let requestReceipt {
            assistantRequestReceipts.record(requestReceipt, for: message.id)
        }
    }

    private func cancelAssistantResponse(preservingPartial: Bool) {
        guard isAssistantResponding else { return }
        let requestKind = activeAssistantRequestKind
        activeAssistantGeneration = nil
        activeAssistantRequestKind = nil
        assistantTask?.cancel()
        assistantTask = nil

        if preservingPartial, requestKind == .chat {
            preservePartialAssistantResponse(as: .stopped)
        }
        if requestKind == .review {
            if preservingPartial {
                appendAssistantResponse(
                    content: "Review stopped before a complete proposal envelope was received. No proposal changed.",
                    completionState: .stopped,
                    provenance: activeAssistantProvenance,
                    requestReceipt: activeAssistantRequestReceipt
                )
            }
            aiProposalDiagnostic = "Review request stopped. No proposal changed."
        }
        assistantStreamingText = ""
        assistantResponsePhase = .idle
        isAssistantResponding = false
        activeAssistantProvenance = nil
        activeAssistantRequestReceipt = nil
    }

    private func preservePartialAssistantResponse(as completionState: AssistantMessage.CompletionState) {
        let content: String
        if assistantStreamingText.isEmpty {
            content = completionState == .stopped
                ? "Response stopped before any provider text arrived."
                : "Response interrupted before any provider text arrived."
        } else {
            content = assistantStreamingText
        }
        appendAssistantResponse(
            content: content,
            commandRisk: nil,
            completionState: completionState,
            provenance: activeAssistantProvenance,
            requestReceipt: activeAssistantRequestReceipt
        )
    }

    private func finishAssistantRequest(_ generation: UUID) {
        guard activeAssistantGeneration == generation else { return }
        activeAssistantGeneration = nil
        activeAssistantRequestKind = nil
        assistantTask = nil
        assistantStreamingText = ""
        assistantResponsePhase = .idle
        isAssistantResponding = false
        activeAssistantProvenance = nil
        activeAssistantRequestReceipt = nil
    }

    func applyLatestAIProposal() {
        guard let proposal = latestAIEditProposal else { return }
        do {
            switch proposal.target {
            case .sourceDraft:
                let documentName = sourceDocument.identity.hostLocation
                    ?? sourceDocument.identity.displayName
                let updated = try proposal.applying(
                    to: sourceDocument.text,
                    documentName: documentName
                )
                updateSourceText(updated)
            case .sqlDraft:
                let documentName = selectedSQLService.map { "\($0.id).sql" }
                    ?? "active-query.sql"
                let updated = try proposal.applying(
                    to: sqlText,
                    documentName: documentName
                )
                updateSQLText(updated)
            }
            aiProposalWasApplied = true
            aiProposalDiagnostic = "Applied to the local editor buffer. No host write or execution occurred."
            showNotice("Assist proposal applied locally. Review and save separately when ready.")
        } catch {
            aiProposalWasApplied = false
            aiProposalDiagnostic = error.localizedDescription
        }
    }

    func queueLatestAIProposal() {
        guard let proposal = latestAIEditProposal else {
            aiProposalPatchDiagnostic = "No validated Assist proposal is ready to queue."
            return
        }
        do {
            let updated = try aiProposalPatchStack.appending(
                proposal: proposal,
                explanation: latestAIProposalExplanation ?? "Assist proposed a local draft change."
            )
            guard let newPatch = updated.patches.last else { return }
            aiProposalPatchStack = updated
            aiProposalPatchWasApplied = false
            aiProposalPatchLastApplication = nil

            var candidate = selectedAIProposalPatchIDs
            candidate.insert(newPatch.id)
            do {
                let preview = try makeAIProposalPatchPreview(patchIDs: candidate)
                selectedAIProposalPatchIDs = candidate
                aiProposalPatchPreview = preview
                aiProposalPatchDiagnostic = "Queued and selected one baseline-bound proposal. The local draft is unchanged."
            } catch {
                refreshAIProposalPatchPreview()
                aiProposalPatchDiagnostic = "Queued as an unselected alternative: \(error.localizedDescription)"
            }
            aiProposalDiagnostic = "Proposal added to the local Patch Stack. No draft or host content changed."
            showNotice("Assist proposal queued locally for atomic review.")
        } catch {
            aiProposalPatchDiagnostic = error.localizedDescription
            aiProposalDiagnostic = "Patch Stack update blocked: \(error.localizedDescription)"
        }
    }

    func openAIProposalPatchStack() {
        aiProposalPatchWasApplied = false
        if selectedAIProposalPatchIDs.isEmpty {
            selectCompatibleAIProposalPatches()
        } else {
            refreshAIProposalPatchPreview()
        }
        isAIProposalPatchStackPresented = true
    }

    func toggleAIProposalPatchSelection(_ id: UUID) {
        guard aiProposalPatchStack.patches.contains(where: { $0.id == id }) else { return }
        if selectedAIProposalPatchIDs.contains(id) {
            selectedAIProposalPatchIDs.remove(id)
        } else {
            selectedAIProposalPatchIDs.insert(id)
        }
        aiProposalPatchWasApplied = false
        aiProposalPatchLastApplication = nil
        refreshAIProposalPatchPreview()
    }

    func selectOnlyAIProposalPatch(_ id: UUID) {
        guard aiProposalPatchStack.patches.contains(where: { $0.id == id }) else { return }
        selectedAIProposalPatchIDs = [id]
        aiProposalPatchWasApplied = false
        aiProposalPatchLastApplication = nil
        refreshAIProposalPatchPreview()
    }

    func selectCompatibleAIProposalPatches() {
        var compatible: Set<UUID> = []
        var skipped = 0
        for patch in aiProposalPatchStack.patches {
            let document = currentLocalPatchDocument(for: patch.proposal.target)
            guard patch.proposal.documentName == document.name,
                  patch.proposal.baselineSHA256 == AIContentFingerprint.sha256(document.text) else {
                skipped += 1
                continue
            }
            var candidate = compatible
            candidate.insert(patch.id)
            if (try? makeAIProposalPatchPreview(patchIDs: candidate)) != nil {
                compatible = candidate
            } else {
                skipped += 1
            }
        }
        selectedAIProposalPatchIDs = compatible
        aiProposalPatchWasApplied = false
        aiProposalPatchLastApplication = nil
        refreshAIProposalPatchPreview()
        if !compatible.isEmpty, skipped > 0 {
            aiProposalPatchDiagnostic = "Selected \(compatible.count) compatible patch\(compatible.count == 1 ? "" : "es"); left \(skipped) stale or conflicting alternative\(skipped == 1 ? "" : "s") unselected."
        }
    }

    func moveAIProposalPatch(_ id: UUID, toward direction: AIProposalPatchMove) {
        do {
            aiProposalPatchStack = try aiProposalPatchStack.moving(id, toward: direction)
            refreshAIProposalPatchPreview()
        } catch {
            aiProposalPatchDiagnostic = error.localizedDescription
        }
    }

    func removeAIProposalPatch(_ id: UUID) {
        aiProposalPatchStack = aiProposalPatchStack.removing(id)
        selectedAIProposalPatchIDs.remove(id)
        aiProposalPatchWasApplied = false
        aiProposalPatchLastApplication = nil
        refreshAIProposalPatchPreview()
    }

    func removeSelectedAIProposalPatches() {
        guard !selectedAIProposalPatchIDs.isEmpty else { return }
        let removedCount = selectedAIProposalPatchIDs.count
        aiProposalPatchStack = aiProposalPatchStack.removing(selectedAIProposalPatchIDs)
        selectedAIProposalPatchIDs.removeAll()
        aiProposalPatchPreview = nil
        aiProposalPatchLastApplication = nil
        aiProposalPatchWasApplied = false
        aiProposalPatchDiagnostic = "Removed \(removedCount) queued proposal\(removedCount == 1 ? "" : "s"). The local draft was not changed."
    }

    func clearAIProposalPatchStack() {
        aiProposalPatchStack = AIProposalPatchStack()
        selectedAIProposalPatchIDs.removeAll()
        aiProposalPatchPreview = nil
        aiProposalPatchLastApplication = nil
        aiProposalPatchWasApplied = false
        aiProposalPatchDiagnostic = "Patch Stack cleared. No local draft or host content changed."
    }

    func refreshAIProposalPatchPreview() {
        guard !selectedAIProposalPatchIDs.isEmpty else {
            aiProposalPatchPreview = nil
            aiProposalPatchDiagnostic = aiProposalPatchStack.isEmpty
                ? "The Patch Stack is empty. Add a validated proposal from an Assist review."
                : "Select one or more compatible proposals to assemble an atomic local preview."
            return
        }
        do {
            aiProposalPatchPreview = try makeAIProposalPatchPreview(
                patchIDs: selectedAIProposalPatchIDs
            )
            aiProposalPatchDiagnostic = "Atomic preview ready. Every selected hunk maps to one exact current baseline."
        } catch {
            aiProposalPatchPreview = nil
            aiProposalPatchDiagnostic = error.localizedDescription
        }
    }

    func applySelectedAIProposalPatches() {
        do {
            let preview = try makeAIProposalPatchPreview(
                patchIDs: selectedAIProposalPatchIDs
            )
            let appliedLatestProposal = latestAIEditProposal.map { latest in
                aiProposalPatchStack.patches.contains {
                    preview.patchIDs.contains($0.id) && $0.proposal == latest
                }
            } ?? false

            switch preview.target {
            case .sourceDraft:
                updateSourceText(preview.revisedText)
                guard sourceDocument.text == preview.revisedText else {
                    aiProposalPatchDiagnostic = "The source editor could not accept the atomic preview while another write transition is active. Nothing was removed from the stack."
                    return
                }
            case .sqlDraft:
                updateSQLText(preview.revisedText)
                guard sqlText == preview.revisedText else {
                    aiProposalPatchDiagnostic = "The SQL editor could not accept the atomic preview. Nothing was removed from the stack."
                    return
                }
            }

            let appliedIDs = Set(preview.patchIDs)
            aiProposalPatchStack = aiProposalPatchStack.removing(appliedIDs)
            selectedAIProposalPatchIDs.subtract(appliedIDs)
            aiProposalPatchPreview = nil
            aiProposalPatchLastApplication = preview
            aiProposalPatchWasApplied = true
            if appliedLatestProposal { aiProposalWasApplied = true }
            aiProposalPatchDiagnostic = "Applied \(preview.patchIDs.count) patch\(preview.patchIDs.count == 1 ? "" : "es") atomically to the local draft. Save, compile, test, and host writes remain separate."
            aiProposalDiagnostic = "Patch Stack applied locally. No host write or execution occurred."
            showNotice("Atomic Patch Stack applied to the local draft.")
        } catch {
            aiProposalPatchWasApplied = false
            aiProposalPatchDiagnostic = error.localizedDescription
        }
    }

    private func makeAIProposalPatchPreview(
        patchIDs: Set<UUID>
    ) throws -> AIProposalPatchPreview {
        guard let first = aiProposalPatchStack.patches.first(where: { patchIDs.contains($0.id) }) else {
            throw AIProposalPatchStackError.noPatchesSelected
        }
        let document = currentLocalPatchDocument(for: first.proposal.target)
        return try aiProposalPatchStack.preview(
            patchIDs: patchIDs,
            currentText: document.text,
            target: first.proposal.target,
            documentName: document.name
        )
    }

    private func currentLocalPatchDocument(
        for target: AIProposalTarget
    ) -> (text: String, name: String) {
        switch target {
        case .sourceDraft:
            (
                sourceDocument.text,
                sourceDocument.identity.hostLocation ?? sourceDocument.identity.displayName
            )
        case .sqlDraft:
            (
                sqlText,
                selectedSQLService.map { "\($0.id).sql" } ?? "active-query.sql"
            )
        }
    }

    func rejectLatestAIProposal() {
        latestAIEditProposal = nil
        aiProposalWasApplied = false
        aiProposalDiagnostic = "Proposal rejected. The local draft was not changed."
    }

    private func start(_ profile: SessionProfile, sessionID: UUID, reconnecting: Bool) {
        guard let sessionIndex = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard profile.validationErrors.isEmpty else {
            terminalSessions[sessionIndex].connectionState = .failed(profile.validationErrors.joined(separator: " "))
            terminalSessions[sessionIndex].protocolNotice = "The saved session profile is invalid; no connection was attempted."
            return
        }

        let runtime = sessionTransports[sessionID] ?? TerminalSessionTransportRuntime()
        sessionTransports[sessionID] = runtime
        let previousClient = runtime.invalidate()
        previousClient?.disconnect()
        let generation = UUID()
        runtime.generation = generation

        if !reconnecting {
            terminalSessions[sessionIndex].reconnectAttempt = 0
        }
        terminalSessions[sessionIndex].connectionState = .connecting
        terminalSessions[sessionIndex].protocolNotice = reconnecting
            ? "Opening a fresh TLS/TN5250 transport; retained input will not be resubmitted."
            : "Opening a native TN5250 session."
        terminalSessions[sessionIndex].startupResponse = nil
        terminalSessions[sessionIndex].screen.inputInhibited = true
        terminalSessions[sessionIndex].lastActivityAt = Date()

        do {
            let newClient = try TN5250Client(profile: profile) { [weak self] event in
                Task { @MainActor in
                    self?.handleSession(event, sessionID: sessionID, generation: generation)
                }
            }
            runtime.client = newClient
            newClient.connect()
        } catch {
            runtime.generation = nil
            terminalSessions[sessionIndex].connectionState = .failed(error.localizedDescription)
            terminalSessions[sessionIndex].protocolNotice = "Connection setup failed. The local screen remains retained."
            scheduleReconnect(sessionID: sessionID, profile: profile, reason: error.localizedDescription)
        }
    }

    private func handleSession(_ event: TN5250ClientEvent, sessionID: UUID, generation: UUID) {
        guard let runtime = sessionTransports[sessionID],
              runtime.generation == generation,
              let sessionIndex = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        terminalSessions[sessionIndex].lastActivityAt = Date()

        switch event {
        case .state(let state):
            terminalSessions[sessionIndex].connectionState = state
            switch state {
            case .connected:
                terminalSessions[sessionIndex].protocolNotice = "TN5250 transport is connected; waiting for host display data."
            case .failed(let message):
                let failedClient = runtime.client
                runtime.client = nil
                runtime.generation = nil
                failedClient?.disconnect()
                if let profile = profiles.first(where: { $0.id == terminalSessions[sessionIndex].profileID }) {
                    scheduleReconnect(sessionID: sessionID, profile: profile, reason: message)
                }
            case .waiting(let message):
                terminalSessions[sessionIndex].protocolNotice = message
            case .disconnected:
                let disconnectedClient = runtime.client
                runtime.client = nil
                runtime.generation = nil
                disconnectedClient?.disconnect()
                if let profile = profiles.first(where: { $0.id == terminalSessions[sessionIndex].profileID }) {
                    scheduleReconnect(
                        sessionID: sessionID,
                        profile: profile,
                        reason: "The remote session closed."
                    )
                }
            case .connecting, .negotiating:
                break
            }

        case .screen(let updatedScreen):
            // A negotiated socket is not yet proof of a usable recovered session.
            // Reset the retry budget only after IBM i delivers a display record.
            terminalSessions[sessionIndex].reconnectAttempt = 0
            if terminalSessions[sessionIndex].applyHostScreen(updatedScreen) {
                terminalAlarmSignal &+= 1
            }
            recordSnapshot(updatedScreen, sessionID: sessionID)

        case .negotiation(let negotiation):
            switch negotiation {
            case .terminalTypeSent(let terminalType):
                terminalSessions[sessionIndex].protocolNotice = "Negotiated \(terminalType)."
            case .environmentSent(let names):
                terminalSessions[sessionIndex].protocolNotice = names.isEmpty
                    ? "RFC 4777 environment negotiation completed with host defaults."
                    : "RFC 4777 sent: \(names.joined(separator: ", "))."
            case .deviceNameRetried(let previous, let next, let attempt):
                terminalSessions[sessionIndex].protocolNotice = "Device \(previous) was unavailable; trying \(next) (retry \(attempt))."
            case .deviceNameRetryExhausted(let deviceName):
                terminalSessions[sessionIndex].protocolNotice = "Device-name retries ended after \(deviceName). Choose another explicit device name."
            case .transparentModeReady:
                terminalSessions[sessionIndex].protocolNotice = "TN5250 transparent mode negotiated."
            }

        case .startupResponse(let response):
            terminalSessions[sessionIndex].startupResponse = response
            terminalSessions[sessionIndex].protocolNotice = "\(response.message) [\(response.responseCode)]"

        case .protocolNotice(let notice):
            terminalSessions[sessionIndex].protocolNotice = notice
        }
    }

    private func scheduleReconnect(
        sessionID: UUID,
        profile: SessionProfile,
        reason: String
    ) {
        guard let sessionIndex = terminalSessions.firstIndex(where: { $0.id == sessionID }),
              let runtime = sessionTransports[sessionID] else { return }
        let maximumAttempts = profile.reconnectPolicy.maximumAttempts
        let attempt = terminalSessions[sessionIndex].reconnectAttempt + 1
        guard let delaySeconds = profile.reconnectPolicy.delaySeconds(forAttempt: attempt) else {
            terminalSessions[sessionIndex].connectionState = .failed(reason)
            terminalSessions[sessionIndex].protocolNotice = maximumAttempts == 0
                ? "Session ended. Automatic recovery is disabled for this profile."
                : "Session recovery stopped after \(maximumAttempts) attempts. The last screen is preserved."
            terminalSessions[sessionIndex].screen.inputInhibited = true
            return
        }

        terminalSessions[sessionIndex].reconnectAttempt = attempt
        terminalSessions[sessionIndex].connectionState = .waiting(
            "Reconnect \(attempt)/\(maximumAttempts) in \(delaySeconds)s · \(reason)"
        )
        terminalSessions[sessionIndex].protocolNotice = "Last screen preserved; edited fields and credentials will not be resubmitted."
        terminalSessions[sessionIndex].screen.inputInhibited = true
        runtime.reconnectTask?.cancel()
        runtime.reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled,
                  let self,
                  self.terminalSessions.contains(where: { $0.id == sessionID }),
                  let currentProfile = self.profiles.first(where: { $0.id == profile.id }) else { return }
            self.start(currentProfile, sessionID: sessionID, reconnecting: true)
        }
    }

    private func handleTestConnection(_ event: TN5250ClientEvent, generation: UUID) {
        guard activeTestGeneration == generation else { return }
        switch event {
        case .state(.connected):
            connectionDiagnostic = "The isolated transport and TN5250 option negotiation succeeded; existing terminal sessions were not changed."
            connectionDiagnosticSucceeded = true
            isTestingConnection = false
            let completedClient = testClient
            testClient = nil
            activeTestGeneration = nil
            completedClient?.disconnect()
        case .state(.failed(let message)):
            connectionDiagnostic = message
            connectionDiagnosticSucceeded = false
            isTestingConnection = false
            let failedClient = testClient
            testClient = nil
            activeTestGeneration = nil
            failedClient?.disconnect()
        case .state(.disconnected):
            connectionDiagnostic = "The remote endpoint closed the isolated connection probe before TN5250 became ready."
            connectionDiagnosticSucceeded = false
            isTestingConnection = false
            testClient = nil
            activeTestGeneration = nil
        case .state(.connecting):
            connectionDiagnostic = "Opening the isolated network transport…"
        case .state(.negotiating):
            connectionDiagnostic = "Negotiating BINARY, EOR, terminal type, and RFC 4777 environment…"
        case .state(.waiting(let message)):
            connectionDiagnostic = message
        case .startupResponse(let response):
            connectionDiagnostic = "\(response.message) [\(response.responseCode)]"
        case .protocolNotice(let notice):
            connectionDiagnostic = notice
        case .screen, .negotiation:
            break
        }
    }

    private func cancelTestConnection() {
        activeTestGeneration = nil
        let activeClient = testClient
        testClient = nil
        isTestingConnection = false
        activeClient?.disconnect()
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: DefaultsKey.profiles)
    }

    private func persistDb2Profile() {
        guard let data = try? JSONEncoder().encode(db2Profile) else { return }
        defaults.set(data, forKey: DefaultsKey.db2Profile)
    }

    private func invalidateJobIncidentCollection(reason: String) {
        jobIncidentTask?.cancel()
        jobIncidentTask = nil
        activeJobIncidentGeneration = nil
        jobIncidentPhase = jobIncidentSnapshot.targetName == "LOCAL INCIDENT REPLAY" ? .localReplay : .failed
        jobIncidentDiagnostic = reason
    }

    private func invalidateSpoolOutputCollection(reason: String) {
        spoolInventoryTask?.cancel()
        spoolInventoryTask = nil
        activeSpoolInventoryGeneration = nil
        spoolPreviewTask?.cancel()
        spoolPreviewTask = nil
        activeSpoolPreviewGeneration = nil
        if spoolOutputSnapshot.targetName == "LOCAL OUTPUT REPLAY" {
            spoolInventoryPhase = .localReplay
            spoolPreviewPhase = spoolTextPreview == nil ? .notLoaded : .localReplay
        } else {
            spoolInventoryPhase = .failed
            spoolPreviewPhase = spoolTextPreview == nil ? .notLoaded : .failed
        }
        spoolInventoryDiagnostic = reason
        spoolPreviewDiagnostic = reason
    }

    private func invalidateTransferSchema(reason: String) {
        transferSchemaTask?.cancel()
        transferSchemaTask = nil
        activeTransferSchemaGeneration = nil
        let reportTarget = transferValidationReport.target.table
        let replayStillSelected = transferValidationReport.target.isBundledReplay
            && transferTargetLibraryText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == reportTarget.library.value
            && transferTargetTableText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == reportTarget.table.value
        transferSchemaIsCurrent = replayStillSelected
        transferSchemaPhase = replayStillSelected ? .localReplay : .failed
        if !replayStillSelected, transferValidationPhase != .profiling {
            transferValidationPhase = .blocked
        }
        transferDiagnostic = reason
    }

    private func invalidateSystemHealthCollection(reason: String) {
        systemHealthTask?.cancel()
        systemHealthTask = nil
        activeSystemHealthGeneration = nil
        systemHealthPhase = systemHealthSnapshot.isBundledReplay ? .localReplay : .failed
        systemHealthDiagnostic = reason
    }

    private func invalidateObjectImpactCollection(reason: String) {
        objectImpactTask?.cancel()
        objectImpactTask = nil
        activeObjectImpactGeneration = nil
        objectImpactPhase = objectImpactSnapshot.isBundledReplay ? .localReplay : .failed
        objectImpactDiagnostic = reason
    }

    private func invalidateAuthorityInsightCollection(reason: String) {
        authorityInsightTask?.cancel()
        authorityInsightTask = nil
        activeAuthorityInsightGeneration = nil
        authorityInsightPhase = authorityInsightSnapshot.isBundledReplay ? .localReplay : .failed
        authorityInsightDiagnostic = reason
    }

    private func currentObjectImpactIdentity() throws -> IBMObjectIdentity {
        try IBMObjectIdentity(
            library: objectImpactLibraryText.trimmingCharacters(in: .whitespacesAndNewlines),
            name: objectImpactNameText.trimmingCharacters(in: .whitespacesAndNewlines),
            type: objectImpactType
        )
    }

    private func currentAuthorityInsightScope() throws -> (subject: AuthoritySubject, target: IBMObjectIdentity) {
        let subject = try AuthoritySubject(
            authoritySubjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let target = try IBMObjectIdentity(
            library: authorityLibraryText.trimmingCharacters(in: .whitespacesAndNewlines),
            name: authorityObjectText.trimmingCharacters(in: .whitespacesAndNewlines),
            type: authorityObjectType
        )
        return (subject, target)
    }

    private func transferTargetDraftDidChange() {
        transferSchemaTask?.cancel()
        transferSchemaTask = nil
        activeTransferSchemaGeneration = nil
        transferSchemaIsCurrent = false
        transferSchemaPhase = .failed
        if transferValidationPhase != .profiling {
            transferValidationPhase = .blocked
        }
        transferDiagnostic = "Target identity changed. Refresh the exact read-only target schema before treating this mapping as current."
    }

    private func spoolReceipt(
        _ source: SpooledOutputEvidenceSource,
        result: SQLResult,
        request: SQLExecutionRequest,
        configuredLimit: Int
    ) -> SpooledOutputEvidenceReceipt {
        SpooledOutputEvidenceReceipt(
            source: source,
            rowCount: result.rows.count,
            boundWasReached: result.wasTruncated || result.rows.count >= configuredLimit,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }

    private func spoolGap(
        _ source: SpooledOutputEvidenceSource,
        request: SQLExecutionRequest,
        error: Error
    ) -> SpooledOutputEvidenceReceipt {
        SpooledOutputEvidenceReceipt(
            source: source,
            rowCount: 0,
            boundWasReached: false,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .unavailable(incidentFailureReason(error))
        )
    }

    private func replaceSpoolReceipt(_ replacement: SpooledOutputEvidenceReceipt) {
        var receipts = spoolOutputSnapshot.receipts.filter { $0.source != replacement.source }
        receipts.append(replacement)
        receipts.sort { lhs, rhs in
            let order = SpooledOutputEvidenceSource.allCases
            return (order.firstIndex(of: lhs.source) ?? order.endIndex)
                < (order.firstIndex(of: rhs.source) ?? order.endIndex)
        }
        spoolOutputSnapshot = SpooledOutputSnapshot(
            targetName: spoolOutputSnapshot.targetName,
            capturedAt: spoolOutputSnapshot.capturedAt,
            files: spoolOutputSnapshot.files,
            queues: spoolOutputSnapshot.queues,
            receipts: receipts
        )
    }

    private func spoolTextExportArtifact(_ preview: SpooledTextPreview) -> String {
        [
            "iTelAS SPOOLED TEXT RECORD ARTIFACT",
            "Target: \(preview.targetName)",
            "Job: \(preview.identity.job.rawValue)",
            "Spooled file: \(preview.identity.file.value)",
            "Spooled file number: \(preview.identity.number)",
            "System: \(preview.identity.system?.value ?? "UNAVAILABLE")",
            "Captured: \(preview.capturedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)))",
            "Complete within bound: \(preview.isComplete ? "YES" : "NO")",
            "Content SHA-256: \(preview.contentFingerprint)",
            "Fidelity: ordered text records only; not page layout, overlays, graphics, fonts, AFP resources, IPDS, or PDF equivalence.",
            "",
            preview.text
        ].joined(separator: "\n")
    }

    private func incidentReceipt(
        _ source: JobIncidentEvidenceSource,
        result: SQLResult,
        request: SQLExecutionRequest
    ) -> JobIncidentEvidenceReceipt {
        JobIncidentEvidenceReceipt(
            source: source,
            rowCount: result.rows.count,
            wasTruncated: result.wasTruncated,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }

    private func systemHealthReceipt(
        _ source: SystemHealthEvidenceSource,
        result: SQLResult,
        request: SQLExecutionRequest
    ) -> SystemHealthEvidenceReceipt {
        SystemHealthEvidenceReceipt(
            source: source,
            rowCount: result.rows.count,
            boundWasReached: result.wasTruncated,
            elapsedMilliseconds: result.elapsedMilliseconds,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }

    private func systemHealthGap(
        _ source: SystemHealthEvidenceSource,
        request: SQLExecutionRequest,
        error: Error
    ) -> SystemHealthEvidenceReceipt {
        SystemHealthEvidenceReceipt(
            source: source,
            rowCount: 0,
            boundWasReached: false,
            elapsedMilliseconds: nil,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .unavailable(incidentFailureReason(error))
        )
    }

    private func objectImpactReceipt(
        _ source: ObjectImpactEvidenceSource,
        result: SQLResult,
        request: SQLExecutionRequest
    ) -> ObjectImpactEvidenceReceipt {
        ObjectImpactEvidenceReceipt(
            source: source,
            rowCount: result.rows.count,
            boundWasReached: result.wasTruncated,
            elapsedMilliseconds: result.elapsedMilliseconds,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }

    private func objectImpactGap(
        _ source: ObjectImpactEvidenceSource,
        request: SQLExecutionRequest,
        error: Error
    ) -> ObjectImpactEvidenceReceipt {
        ObjectImpactEvidenceReceipt(
            source: source,
            rowCount: 0,
            boundWasReached: false,
            elapsedMilliseconds: nil,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .unavailable(incidentFailureReason(error))
        )
    }

    private func authorityInsightReceipt(
        _ source: AuthorityEvidenceSource,
        result: SQLResult,
        request: SQLExecutionRequest
    ) -> AuthorityEvidenceReceipt {
        AuthorityEvidenceReceipt(
            source: source,
            rowCount: result.rows.count,
            boundWasReached: result.wasTruncated,
            elapsedMilliseconds: result.elapsedMilliseconds,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .collected
        )
    }

    private func authorityInsightGap(
        _ source: AuthorityEvidenceSource,
        request: SQLExecutionRequest,
        error: Error
    ) -> AuthorityEvidenceReceipt {
        AuthorityEvidenceReceipt(
            source: source,
            rowCount: 0,
            boundWasReached: false,
            elapsedMilliseconds: nil,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .unavailable(incidentFailureReason(error))
        )
    }

    private func incidentGap(
        _ source: JobIncidentEvidenceSource,
        request: SQLExecutionRequest,
        error: Error
    ) -> JobIncidentEvidenceReceipt {
        JobIncidentEvidenceReceipt(
            source: source,
            rowCount: 0,
            wasTruncated: false,
            queryFingerprint: AIContentFingerprint.sha256(request.sql),
            outcome: .unavailable(incidentFailureReason(error))
        )
    }

    private func incidentFailureReason(_ error: Error) -> String {
        let sanitized = Db2DiagnosticSanitizer().sanitize(error.localizedDescription)
        let singleLine = sanitized
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(singleLine.prefix(300))
    }

    private func prepareTerminalRecorderForActualUse() {
        guard terminalFlightRecorderUsesReplay else { return }
        let policy = terminalFlightRecorder.policy
        terminalFlightRecorder = TerminalFlightRecorderArchive(policy: policy)
        selectedTerminalEvidenceFrameID = nil
        selectedTerminalMacroID = nil
        terminalMacroRunState = nil
        terminalFlightRecorderUsesReplay = false
    }

    @discardableResult
    private func captureTerminalEvidence(
        screen sourceScreen: TerminalScreen,
        sessionID: UUID,
        source: String
    ) -> TerminalEvidenceFrame? {
        guard let session = terminalSessions.first(where: { $0.id == sessionID }),
              let profile = profile(for: session) else {
            terminalFlightRecorderDiagnostic = "Recorder capture blocked because the session profile is unavailable."
            return nil
        }
        prepareTerminalRecorderForActualUse()
        let frame = TerminalEvidenceFrame(
            profileID: profile.id,
            profileName: profile.name,
            deviceName: session.startupResponse?.deviceName ?? profile.deviceName,
            screen: sourceScreen
        )
        do {
            let appended = try terminalFlightRecorder.append(frame)
            let retained = appended ? frame : terminalFlightRecorder.frames.last
            selectedTerminalEvidenceFrameID = retained?.id
            persistTerminalFlightRecorder(
                success: appended
                    ? "\(source). Stored redacted frame \(frame.shortFingerprint)."
                    : "\(source). The identical newest redacted frame was collapsed."
            )
            return retained
        } catch {
            terminalFlightRecorderDiagnostic = "Recorder capture blocked: \(error.localizedDescription)"
            showNotice(terminalFlightRecorderDiagnostic)
            return nil
        }
    }

    private func persistTerminalFlightRecorder(success: String) {
        terminalFlightRecorder.updatedAt = recorderTimestamp()
        do {
            try terminalFlightRecorderStore.write(terminalFlightRecorder)
            terminalFlightRecorderDiagnostic = success
            showNotice(success)
        } catch {
            terminalFlightRecorderDiagnostic = "Local recorder persistence blocked: \(error.localizedDescription)"
            showNotice(terminalFlightRecorderDiagnostic)
        }
    }

    private func recorderTimestamp(_ date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
    }

    private func recordSnapshot(_ updatedScreen: TerminalScreen, sessionID: UUID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }),
              terminalSessions[index].screenHistory.last?.screen != updatedScreen else { return }
        let profileName = profiles.first(where: { $0.id == terminalSessions[index].profileID })?.name
            ?? "TN5250 session"
        terminalSessions[index].screenHistory.append(TerminalSnapshot(
            source: profileName,
            screen: updatedScreen
        ))
        if terminalSessions[index].screenHistory.count > 100 {
            terminalSessions[index].screenHistory.removeFirst(
                terminalSessions[index].screenHistory.count - 100
            )
        }
        if terminalRecorderArmedSessionIDs.contains(sessionID) {
            _ = captureTerminalEvidence(
                screen: updatedScreen,
                sessionID: sessionID,
                source: "Received a new host frame"
            )
        }
    }

    private func makeContextReceipt(
        contextBundle: AIContextBundle?,
        conversationTurns: Int,
        configuration: AIConfiguration? = nil,
        question: String? = nil
    ) -> AIContextReceipt {
        let configuration = configuration ?? aiConfiguration
        let includesScreen = contextBundle?.fragments.contains(where: { $0.kind == .terminalScreen }) == true
        return AIContextReceipt(
            endpointHost: URL(string: configuration.endpoint)?.host ?? "Invalid endpoint",
            model: configuration.model,
            conversationTurns: conversationTurns,
            question: question,
            screenRows: includesScreen ? screen.rows : nil,
            screenColumns: includesScreen ? screen.columns : nil,
            contextBundle: contextBundle
        )
    }

    private func makeAssistantProvenance(
        question: String,
        receipt: AIContextReceipt
    ) -> AssistantResponseProvenance {
        AssistantResponseProvenance(
            question: question,
            endpointHost: receipt.endpointHost,
            model: receipt.model,
            contextFingerprint: receipt.bundleFingerprint,
            contextItemCount: receipt.contextBundle?.fragments.count ?? 0,
            requestedAt: receipt.createdAt
        )
    }

    func showNotice(_ message: String) {
        transientNotice = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.transientNotice == message {
                self?.transientNotice = nil
            }
        }
    }

    private func inferCommandRisk(in answer: String) -> CommandRisk? {
        let risks = answer.split(separator: "\n").map { line in
            commandClassifier.classify(String(line).replacingOccurrences(of: "`", with: ""))
        }
        if risks.contains(.destructive) { return .destructive }
        if risks.contains(.mutating) { return .mutating }
        if risks.contains(.readOnly) { return .readOnly }
        return nil
    }

    private func sourceMemberConnection(
        requireWrite: Bool
    ) -> SourceMemberConnectionContext? {
        guard db2Phase.isConnected,
              let transport = db2Transport,
              let receipt = db2Receipt else {
            sourceMemberPhase = .offline
            sourceMemberDiagnostic = "Connect a source-member Db2 capability before reading or reviewing host members. No query was executed."
            showNotice("Source Member Workbench needs a member-capability connection.")
            return nil
        }
        let capabilityIsValid = requireWrite
            ? receipt.accessMode == .reviewedSourceMemberWrite
            : receipt.accessMode == .sourceMemberRead || receipt.accessMode == .reviewedSourceMemberWrite
        guard capabilityIsValid else {
            sourceMemberPhase = .offline
            sourceMemberDiagnostic = requireWrite
                ? "Reconnect with Reviewed source-member write before building a transaction."
                : "Reconnect with Source-member read or Reviewed source-member write before browsing the catalog."
            showNotice(sourceMemberDiagnostic)
            return nil
        }
        guard receipt.environment != .production else {
            sourceMemberPhase = .failed
            sourceMemberDiagnostic = "Source-member alias and write workflows are blocked for PROD by this development policy."
            showNotice("Production source-member operations are blocked by policy.")
            return nil
        }
        return SourceMemberConnectionContext(
            provider: Db2SourceMemberProvider(transport: transport),
            receipt: receipt,
            transport: transport
        )
    }

    private func sourceMemberOperationIsCurrent(
        _ generation: UUID,
        context: SourceMemberConnectionContext,
        allowClosedTransport: Bool = false
    ) -> Bool {
        guard !Task.isCancelled,
              activeSourceMemberGeneration == generation,
              db2Transport === context.transport else { return false }
        if allowClosedTransport { return db2Receipt?.profileID == context.receipt.profileID }
        return db2Phase.isConnected
            && db2Receipt?.profileID == context.receipt.profileID
            && db2Receipt?.accessMode == context.receipt.accessMode
    }

    private func loadSourceMemberFiles(in library: IBMSystemObjectName) {
        guard let context = sourceMemberConnection(requireWrite: false) else { return }
        let generation = UUID()
        sourceMemberTask?.cancel()
        activeSourceMemberGeneration = generation
        sourceMemberPhase = .loadingFiles
        sourceMemberDiagnostic = "Reading bounded source-file metadata for \(library.value)."

        sourceMemberTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let files = try await context.provider.listSourceFiles(in: library)
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                sourceMemberFiles = files
                selectedSourceMemberFile = files.first
                sourceMembers = []
                selectedSourceMemberID = nil
                guard let file = files.first else {
                    activeSourceMemberGeneration = nil
                    sourceMemberPhase = .catalogReady
                    sourceMemberDiagnostic = "No caller-visible source physical files were returned for \(library.value)."
                    return
                }
                sourceMemberPhase = .loadingMembers
                let members = try await context.provider.listMembers(
                    in: library,
                    sourceFile: file.sourceFile
                )
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                sourceMembers = members
                selectedSourceMemberID = members.first?.identity
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .catalogReady
                sourceMemberDiagnostic = "Loaded \(files.count) source files and \(members.count) members from \(library.value)."
            } catch is CancellationError {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
            } catch {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .failed
                sourceMemberDiagnostic = "Source-file catalog read stopped locally: \(incidentFailureReason(error))."
            }
        }
    }

    private func loadSourceMembers(in file: SourceMemberFileSummary) {
        guard let context = sourceMemberConnection(requireWrite: false) else { return }
        let generation = UUID()
        sourceMemberTask?.cancel()
        activeSourceMemberGeneration = generation
        sourceMemberPhase = .loadingMembers
        sourceMemberDiagnostic = "Reading bounded member metadata for \(file.id)."

        sourceMemberTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let members = try await context.provider.listMembers(
                    in: file.library,
                    sourceFile: file.sourceFile
                )
                try Task.checkCancellation()
                guard sourceMemberOperationIsCurrent(generation, context: context) else { return }
                sourceMembers = members
                selectedSourceMemberID = members.first?.identity
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .catalogReady
                sourceMemberDiagnostic = "Loaded \(members.count) members from \(file.id). No source records were read."
            } catch is CancellationError {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
            } catch {
                guard activeSourceMemberGeneration == generation else { return }
                activeSourceMemberGeneration = nil
                sourceMemberPhase = .failed
                sourceMemberDiagnostic = "Member catalog read stopped locally: \(incidentFailureReason(error))."
            }
        }
    }

    private func openSourceMemberSnapshot(_ snapshot: SourceMemberSnapshot) {
        resetIFSWorkspace(restoreLocalDocument: false)
        sourceSaveTask?.cancel()
        sourceSaveTask = nil
        sourceMemberSnapshot = snapshot
        sourceMemberCurrentRemoteSnapshot = nil
        sourceMemberRevisionState = .unverified
        sourceMemberWritePlan = nil
        sourceMemberCommittedSnapshot = nil
        isSourceMemberWriteReviewPresented = false
        sourceMemberDatePolicy = .preserve
        selectedSourceMemberLibrary = snapshot.metadata.identity.library
        selectedSourceMemberFile = sourceMemberFiles.first(where: {
            $0.library == snapshot.metadata.identity.library
                && $0.sourceFile == snapshot.metadata.identity.sourceFile
        })
        selectedSourceMemberID = snapshot.metadata.identity
        openedSourceWorkspaceSnapshotPath = nil
        sourceDocument = snapshot.sourceDocument
        refreshSourceIntelligence()
        sourceSaveState = .remoteClean
    }

    private func invalidateSourceMemberConnection(reason: String) {
        sourceMemberTask?.cancel()
        sourceMemberTask = nil
        activeSourceMemberGeneration = nil
        sourceMemberCurrentRemoteSnapshot = nil
        sourceMemberRevisionState = .unverified
        sourceMemberWritePlan = nil
        isSourceMemberWriteReviewPresented = false
        if sourceMemberPhase != .localReplay {
            sourceMemberPhase = .offline
            sourceMemberDiagnostic = reason
        }
    }

    private func resetIFSWorkspace(restoreLocalDocument: Bool) {
        ifsOperationTask?.cancel()
        ifsOperationTask = nil
        ifsDirectory = nil
        ifsEntries = []
        ifsSelectedMetadata = nil
        ifsRemoteBaselineText = nil
        ifsLatestRemoteText = nil
        ifsRevisionState = .unverified
        ifsWritePlan = nil
        ifsWriteReceipt = nil
        isIFSWriteReviewPresented = false
        ifsDiagnostic = nil
        ifsPhase = secureChannelPhase == .connected ? .idle : .offline

        guard restoreLocalDocument else { return }
        sourceSaveTask?.cancel()
        sourceSaveTask = nil
        openedSourceWorkspaceSnapshotPath = nil
        let storedText = ((try? sourceScratchStore.read()) ?? nil) ?? Self.defaultSourceScratch
        sourceDocument = SourceDocument(
            identity: .localScratch(name: "CUSTOMER.rpgle"),
            format: .rpgle,
            sourceDatePolicy: .preserve,
            originalText: storedText
        )
        refreshSourceIntelligence()
        sourceSaveState = .saved
    }

    private func scheduleSourceIntelligenceAnalysis() {
        let document = sourceDocument
        sourceIntelligenceIsCurrent = false
        sourceIntelligenceTask?.cancel()
        sourceIntelligenceTask = Task { @MainActor [weak self, document] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            let snapshot = sourceIntelligenceAnalyzer.analyze(document)
            guard sourceDocument.identity == document.identity,
                  sourceDocument.format == document.format,
                  sourceDocument.text == document.text else { return }
            sourceIntelligence = snapshot
            sourceIntelligenceIsCurrent = true
        }
    }

    private func refreshSourceIntelligence() {
        dismissSourceCompletion()
        sourceIntelligenceTask?.cancel()
        sourceIntelligenceTask = nil
        sourceIntelligence = sourceIntelligenceAnalyzer.analyze(sourceDocument)
        sourceIntelligenceIsCurrent = true
        sourceCursorUTF16 = min(sourceCursorUTF16, sourceDocument.text.utf16.count)
    }

    private func sourceAISelection(for range: SourceTextRange) -> AITextSelection? {
        guard let range = range.utf16Range(in: sourceDocument.text), range.length > 0 else { return nil }
        return AITextSelection(locationUTF16: range.location, lengthUTF16: range.length)
    }

    private func persistSourceScratch(_ text: String) {
        do {
            try sourceScratchStore.write(text)
            sourceSaveState = .saved
        } catch {
            sourceSaveState = .failed
            showNotice("Local source autosave failed: \(error.localizedDescription)")
        }
    }

    private func persistSQLScratch(_ text: String) {
        do {
            try sqlScratchStore.write(text)
            sqlSaveState = .saved
        } catch {
            sqlSaveState = .failed
            showNotice("Local SQL autosave failed: \(error.localizedDescription)")
        }
    }

    private static func compileObjectName(from sourceIdentity: String, fallback: String) -> String {
        if let opening = sourceIdentity.lastIndex(of: "("),
           let closing = sourceIdentity[opening...].firstIndex(of: ")"),
           opening < closing {
            let member = sourceIdentity[sourceIdentity.index(after: opening)..<closing]
            if !member.isEmpty { return String(member).uppercased() }
        }
        let lastComponent = URL(fileURLWithPath: sourceIdentity).lastPathComponent
        let candidate = lastComponent
            .replacingOccurrences(of: ".MBR", with: "", options: .caseInsensitive)
            .split(separator: ".")
            .first
            .map(String.init)
        if let candidate, !candidate.isEmpty {
            return candidate.uppercased()
        }
        return URL(fileURLWithPath: fallback)
            .deletingPathExtension()
            .lastPathComponent
            .uppercased()
    }

    private static func shortCompileTimestamp(_ timestamp: String) -> String {
        guard timestamp.count == 14 else { return timestamp }
        let time = timestamp.suffix(6)
        return "\(time.prefix(2)):\(time.dropFirst(2).prefix(2)):\(time.suffix(2))"
    }

    private static let defaultSourceScratch = """
    **free
    ctl-opt option(*srcstmt : *nodebugio);

    dcl-pr FindCustomer ind;
      customerNumber packed(9:0) const;
    end-pr;

    dcl-s customerNumber packed(9:0) inz(100120);
    dcl-s customerFound ind inz(*off);

    customerFound = FindCustomer(customerNumber);
    if customerFound;
      dsply ('Customer found');
    else;
      dsply ('Customer is missing');
    endif;

    *inlr = *on;
    """
}
