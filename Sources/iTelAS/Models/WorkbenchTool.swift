import Foundation

enum WorkbenchTool: String, CaseIterable, Identifiable {
    case terminal
    case commandCenter
    case sourceWorkspace
    case sqlStudio
    case objectGraph
    case buildAndTest
    case jobsAndQueues
    case spoolAndOutput
    case transferCenter
    case systemHealth
    case automation
    case securityAdvisor
    case casebook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: "5250 Sessions"
        case .commandCenter: "Command Center"
        case .sourceWorkspace: "Source & IFS"
        case .sqlStudio: "Db2 SQL Studio"
        case .objectGraph: "Dependency Atlas"
        case .buildAndTest: "Build & Test"
        case .jobsAndQueues: "Jobs & Queues"
        case .spoolAndOutput: "Spool & Output"
        case .transferCenter: "Data Transfer"
        case .systemHealth: "System Health"
        case .automation: "Runbooks"
        case .securityAdvisor: "Security Advisor"
        case .casebook: "Continuity Casebook"
        }
    }

    var subtitle: String {
        switch self {
        case .terminal: "Native TN5250 sessions"
        case .commandCenter: "Everything urgent, one view"
        case .sourceWorkspace: "Members, stream files, search"
        case .sqlStudio: "SQL, plans, services, exports"
        case .objectGraph: "Evidence-backed change impact"
        case .buildAndTest: "Compile, diagnostics, tests"
        case .jobsAndQueues: "Jobs, locks, queues, logs"
        case .spoolAndOutput: "Find, inspect, compare, export"
        case .transferCenter: "Database and IFS movement"
        case .systemHealth: "Limits, ASP, PTF, performance"
        case .automation: "Typed plans, gates, evidence"
        case .securityAdvisor: "Authorities and exposure"
        case .casebook: "Handoffs and Assist provenance"
        }
    }

    var symbol: String {
        switch self {
        case .terminal: "rectangle.inset.filled.and.person.filled"
        case .commandCenter: "square.grid.2x2"
        case .sourceWorkspace: "curlybraces.square"
        case .sqlStudio: "cylinder.split.1x2"
        case .objectGraph: "point.3.connected.trianglepath.dotted"
        case .buildAndTest: "hammer"
        case .jobsAndQueues: "waveform.path.ecg.rectangle"
        case .spoolAndOutput: "printer"
        case .transferCenter: "arrow.left.arrow.right"
        case .systemHealth: "gauge.with.dots.needle.50percent"
        case .automation: "gearshape.arrow.triangle.2.circlepath"
        case .securityAdvisor: "lock.shield"
        case .casebook: "point.forward.to.point.capsulepath"
        }
    }

    var group: ToolGroup {
        switch self {
        case .terminal, .commandCenter: .workspace
        case .sourceWorkspace, .sqlStudio, .objectGraph, .buildAndTest: .development
        case .jobsAndQueues, .spoolAndOutput, .transferCenter, .systemHealth: .operations
        case .automation, .securityAdvisor, .casebook: .governance
        }
    }
}

enum ToolGroup: String, CaseIterable, Identifiable {
    case workspace = "WORKSPACE"
    case development = "DEVELOPMENT"
    case operations = "OPERATIONS"
    case governance = "AUTOMATION & SAFETY"

    var id: String { rawValue }
}
