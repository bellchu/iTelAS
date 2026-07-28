import SwiftUI

struct ToolWorkspaceView: View {
    @Environment(AppModel.self) private var model
    let tool: WorkbenchTool

    var body: some View {
        let content = ToolContent.content(for: tool)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(content)
                painPointStrip(content)

                HStack(alignment: .top, spacing: 14) {
                    primaryWorkspace(content)
                    workflowRail(content)
                }

                foundationNotice(content)
            }
            .padding(20)
        }
        .background(AppPalette.window)
    }

    private func header(_ content: ToolContent) -> some View {
        HStack(spacing: 14) {
            WorkbenchGlyph(tool: tool, color: .white, size: 25)
                .frame(width: 48, height: 48)
                .background(AppPalette.instrument, in: ChamferedRectangle(cut: 7))
                .overlay {
                    ChamferedRectangle(cut: 7)
                        .stroke(AppPalette.registrationBlue, lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(content.eyebrow)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppPalette.ibmBlue)
                Text(tool.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppPalette.text)
                Text(content.promise)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
            if let profile = model.selectedProfile {
                EnvironmentBadge(environment: profile.environment)
            }
        }
    }

    private func painPointStrip(_ content: ToolContent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bandage.fill").foregroundStyle(AppPalette.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("PAIN REMOVED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppPalette.warning)
                Text(content.pain)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(AppPalette.warning.opacity(0.075), in: ChamferedRectangle(cut: 4))
        .overlay {
            ChamferedRectangle(cut: 4)
                .stroke(AppPalette.warning.opacity(0.22), lineWidth: 0.8)
        }
    }

    private func primaryWorkspace(_ content: ToolContent) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(content.workspaceTitle)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                    Spacer()
                    Text("DESIGNED WORKFLOW")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ibmBlue)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(AppPalette.raised)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.border).frame(height: 1) }

                ForEach(Array(content.capabilities.enumerated()), id: \.offset) { index, capability in
                    HStack(alignment: .top, spacing: 11) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.ibmBlue)
                            .frame(width: 25, height: 25)
                            .background(AppPalette.ibmBlue.opacity(0.09), in: ChamferedRectangle(cut: 3))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(capability.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppPalette.text)
                            Text(capability.detail)
                                .font(.system(size: 9.5))
                                .foregroundStyle(AppPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    if index < content.capabilities.count - 1 {
                        Rectangle().fill(AppPalette.border).frame(height: 1).padding(.leading, 50)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func workflowRail(_ content: ToolContent) -> some View {
        VStack(spacing: 12) {
            Panel {
                VStack(alignment: .leading, spacing: 13) {
                    Text("SAFE DEFAULTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                    ForEach(content.guards, id: \.self) { guardrail in
                        Label(guardrail, systemImage: "checkmark.shield")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppPalette.secondary)
                    }
                }
                .padding(14)
            }

            Button {
                model.isAssistantVisible = true
                model.assistantInput = content.aiPrompt
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        UtilityGlyph(kind: .assistant, color: AppPalette.registrationBlue, size: 13)
                        Text("ASK ITELAS ASSIST")
                    }
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ibmBlue)
                    Text(content.aiPrompt)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.text)
                        .multilineTextAlignment(.leading)
                    Text("Nothing is executed automatically")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppPalette.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.ibmBlue.opacity(0.07), in: ChamferedRectangle(cut: 5))
                .overlay { ChamferedRectangle(cut: 5).stroke(AppPalette.ibmBlue.opacity(0.2), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260)
    }

    private func foundationNotice(_ content: ToolContent) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "shippingbox.fill").foregroundStyle(AppPalette.ibmBlue)
            Text(content.foundation)
                .font(.system(size: 9.5))
                .foregroundStyle(AppPalette.secondary)
            Spacer()
        }
        .padding(12)
        .background(AppPalette.raised, in: ChamferedRectangle(cut: 4))
    }
}

private struct ToolCapability {
    let title: String
    let detail: String
}

private struct ToolContent {
    let eyebrow: String
    let promise: String
    let pain: String
    let workspaceTitle: String
    let capabilities: [ToolCapability]
    let guards: [String]
    let aiPrompt: String
    let foundation: String

    static func content(for tool: WorkbenchTool) -> ToolContent {
        switch tool {
        case .sourceWorkspace:
            return .init(eyebrow: "DEVELOPMENT", promise: "Browse members and stream files without losing source dates or library context.", pain: "No more bouncing among SEU/PDM, FTP, and a separate editor just to understand one change.", workspaceTitle: "SOURCE WORKSPACE", capabilities: [
                .init(title: "Unified member + IFS explorer", detail: "Search across source physical files and stream files with library-list and CCSID visibility."),
                .init(title: "RPG, CL, COBOL, DDS intelligence", detail: "Outline, references, copybook/include navigation, fixed/free format, and source-date preservation."),
                .init(title: "Side-by-side change review", detail: "Compare local, member, and last-deployed content before a save or upload."),
                .init(title: "Compile from the file", detail: "Bind a build recipe and keep event-file diagnostics beside the exact line.")
            ], guards: ["Show CCSID before conversion", "Preserve source dates by policy", "Preview every upload"], aiPrompt: "Explain this source and propose a minimal IBM i-safe change.", foundation: "The native workbench shell is in place. SSH/IFS and source-member providers are the next connector milestone."
            )
        case .sqlStudio:
            return .init(eyebrow: "DB2 FOR i", promise: "Query, explain, compare, and export with library and commitment context visible.", pain: "Replaces fragile copy/paste between Run SQL Scripts, spreadsheets, and terminal commands.", workspaceTitle: "QUERY WORKBENCH", capabilities: [
                .init(title: "IBM i Services catalog", detail: "Curated, searchable starting points for jobs, locks, spool, limits, storage, PTFs, and authorities."),
                .init(title: "Plan and cost inspection", detail: "Explain access paths, indexes, estimates, and query-engine messages without leaving the editor."),
                .init(title: "Result comparison", detail: "Pin and diff result sets across DEV, QA, and PROD with environment color always visible."),
                .init(title: "Typed export", detail: "CSV and spreadsheet exports retain dates, decimals, nulls, CCSID metadata, and query provenance.")
            ], guards: ["Read-only mode by default", "Row limit before execution", "Transaction state always visible"], aiPrompt: "Review this Db2 for i query for correctness, safety, and likely access-path issues.", foundation: "The native editor, IBM i Services catalog, execution gate, and typed result contract are implemented; Db2 connectivity and live result rendering remain the connector milestone."
            )
        case .objectGraph:
            return .init(eyebrow: "DISCOVERY", promise: "Answer what an object is, who uses it, and what a change could break.", pain: "Ends the hunt across DSP* commands, source scans, job logs, and tribal knowledge.", workspaceTitle: "DEPENDENCY GRAPH", capabilities: [
                .init(title: "Definition in one click", detail: "Object type, library, owner, authority, text, creation, change, and save metadata."),
                .init(title: "Inbound + outbound references", detail: "Programs, files, service programs, modules, SQL dependencies, and command usage."),
                .init(title: "Impact radius", detail: "Rank likely breakage by production usage, binding, interface changes, and recent activity."),
                .init(title: "Modernization trail", detail: "Attach notes, owners, tests, and replacement plans to the graph instead of a spreadsheet.")
            ], guards: ["Evidence links on every edge", "Environment-aware graph", "No silent object changes"], aiPrompt: "Summarize this object's role and give me an evidence-first impact checklist.", foundation: "Graph contracts and UX are specified; object metadata and cross-reference collectors are planned."
            )
        case .buildAndTest:
            return .init(eyebrow: "DELIVERY", promise: "Turn compile messages and job logs into a short, repeatable fix loop.", pain: "Stops save/compile latency, hidden batch job failures, and error-list archaeology.", workspaceTitle: "BUILD PIPELINE", capabilities: [
                .init(title: "Recipe-based compile", detail: "Per-project commands, library lists, binding directories, options, and environment variables."),
                .init(title: "Inline event diagnostics", detail: "Parse event files, spool, and job logs into source-linked errors and warnings."),
                .init(title: "Impact-aware tests", detail: "Run the tests and service checks related to changed objects, with reproducible evidence."),
                .init(title: "Artifact comparison", detail: "Compare signatures, exports, size, owner, authority, and timestamps before promotion.")
            ], guards: ["Build outside PROD by default", "Command preview + copy", "Keep complete job-log evidence"], aiPrompt: "Diagnose this compile failure and separate the root cause from follow-on messages.", foundation: "Compile workflow and safety contracts are designed; remote execution and event-file adapters remain."
            )
        case .jobsAndQueues:
            return .init(eyebrow: "OPERATIONS", promise: "Trace a stuck job from symptom to waiter, lock, message, queue, and log.", pain: "Replaces WRKACTJOB → WRKJOB → DSPJOBLOG → WRKOBJLCK hopping during incidents.", workspaceTitle: "INCIDENT TRACE", capabilities: [
                .init(title: "Wait-chain explanation", detail: "Active job state, SQL wait, object locks, holder jobs, and message waits in one timeline."),
                .init(title: "Job log that stays readable", detail: "Filter noise, correlate message IDs, expand causes/recovery, and bookmark evidence."),
                .init(title: "Queue pressure", detail: "Subsystem, job queue, output queue, held/released status, priorities, and aging work."),
                .init(title: "Handoff report", detail: "Export a timestamped incident brief with queries used and actions proposed or taken.")
            ], guards: ["Read-only diagnosis only", "No reply, hold, release, or end controls", "Production collection blocked"], aiPrompt: "Build a read-only plan to explain why this IBM i job is waiting.", foundation: "The native Incident Thread, deterministic replay, bounded IBM i Services collector, evidence receipts, and reviewed Assist context are implemented; live release and authority coverage still requires lab verification."
            )
        case .spoolAndOutput:
            return .init(eyebrow: "OUTPUT", promise: "Find the right spool file, inspect it clearly, and deliver it in a useful format.", pain: "Eliminates output-queue hunting, weak previews, and manual text-to-PDF or spreadsheet cleanup.", workspaceTitle: "OUTPUT FINDER", capabilities: [
                .init(title: "Search all the identifiers", detail: "Job, user, number, file, form type, queue, user data, date range, and text content."),
                .init(title: "Bounded text preview", detail: "Ordered text records, exact attributes, fidelity limits, and side-by-side local comparison."),
                .init(title: "Reliable local delivery", detail: "Copy or export UTF-8 text with exact identity, provenance, completeness, and fidelity notes."),
                .init(title: "Exception radar", detail: "Surface held output, writer errors, unusual volume, aging files, and queue congestion.")
            ], guards: ["Content read is explicit and auditable", "No spool mutation controls", "Production collection blocked"], aiPrompt: "Review this exact spool evidence and separate output facts from rendering or writer assumptions.", foundation: "The native Document Inspector, deterministic replay, bounded IBM i Services inventory, explicit SYSTOOLS text preview, local comparison/export, evidence receipts, and reviewed Assist context are implemented; live release and authority coverage still requires lab verification."
            )
        case .transferCenter:
            return .init(eyebrow: "DATA MOVEMENT", promise: "Move database and IFS data with types, CCSIDs, deltas, and validation intact.", pain: "Fixes brittle transfers, mojibake, lost leading zeros, silent truncation, and spreadsheet type guessing.", workspaceTitle: "TRANSFER PLAN", capabilities: [
                .init(title: "Schema-first mapping", detail: "Preview names, types, lengths, decimals, null handling, CCSID, date/time, and encoding."),
                .init(title: "Diff before movement", detail: "Counts, keys, checksums, samples, and conflict policy shown before any write."),
                .init(title: "Repeatable recipes", detail: "Save parameters without secrets; rerun with a new source, target, or environment."),
                .init(title: "Auditable result", detail: "Record rows read/written/rejected, conversions, elapsed time, and validation queries.")
            ], guards: ["Dry run is the default", "Never infer PROD target", "Reject silent truncation"], aiPrompt: "Review this data transfer mapping for CCSID, decimal, date, and truncation risks.", foundation: "The native Transfer Integrity workbench, bounded local CSV profiler, exact SYSCOLUMNS2 schema reader, fail-closed mapping analyzer, local validation report, and reviewed metadata-only Assist context are implemented. Target writes, XLSX/ODS engines, IFS streaming, and resumable execution remain separate future capabilities."
            )
        case .systemHealth:
            return .init(eyebrow: "OBSERVABILITY", promise: "See capacity, limits, PTF posture, and unusual workload before users report it.", pain: "Turns scattered service commands and snapshots into prioritized, explainable health signals.", workspaceTitle: "HEALTH BOARD", capabilities: [
                .init(title: "System limits headroom", detail: "Track high-water marks, remaining capacity, trend, affected resource, and recovery guidance."),
                .init(title: "Storage and ASP trend", detail: "Used/free, growth rate, temporary storage, largest consumers, and projected exhaustion."),
                .init(title: "Workload anomalies", detail: "CPU, faulting, jobs, pool activity, SQL pressure, and changes from the normal baseline."),
                .init(title: "Maintenance posture", detail: "Group PTF levels, superseded fixes, certificate expiry, and planned maintenance notes.")
            ], guards: ["Source query shown", "Thresholds per system", "No alarm without evidence"], aiPrompt: "Explain these IBM i health signals and rank the safest next checks.", foundation: "Health cards map to supported IBM i Services; scheduling, baselines, and live collection remain."
            )
        case .automation:
            return .init(eyebrow: "RUNBOOKS", promise: "Make expert procedures repeatable without hiding what each step will do.", pain: "Moves critical operations out of personal notes, brittle macros, and unreviewed command history.", workspaceTitle: "RUNBOOK DESIGNER", capabilities: [
                .init(title: "Bounded step contract", detail: "Local assertions, read-only SQL checks, CL previews, review gates, evidence requirements, and operator notes."),
                .init(title: "Typed exact resolution", detail: "Validated inputs, allowed environments, mutation budgets, and no hidden substitutions."),
                .init(title: "Plan-bound review", detail: "Deterministic fingerprints, local attestations, explicit open checks, and permanent review-required status."),
                .init(title: "Review handoff", detail: "Export the exact local plan or prepare identity-withheld advice-only Assist context.")
            ], guards: ["No embedded credentials", "No execution connector", "Local attestations are not authenticated"], aiPrompt: "Review this runbook contract for checks, stops, evidence, and rollback questions.", foundation: "The native local Runbook Flight Deck is implemented; durable versioning, authenticated approvals, organization policy, and remote execution connectors remain separate future capabilities."
            )
        case .securityAdvisor:
            return .init(eyebrow: "GOVERNANCE", promise: "Explain authority and exposure in terms developers and administrators can act on.", pain: "Replaces one-off authority dumps with paths, owners, evidence, and least-privilege remediation.", workspaceTitle: "AUTHORITY REVIEW", capabilities: [
                .init(title: "Evidence-backed access paths", detail: "Keep direct, group, authorization-list, public, blocked, and observed routes distinct."),
                .init(title: "Exact authority surface", detail: "Compare object and data authority bits without implying uncollected effective authority."),
                .init(title: "Local what-if", detail: "Remove selected static paths locally and show whether another reported path remains."),
                .init(title: "Review artifact", detail: "Export exact scope, source receipts, gaps, findings, and the permanent review posture.")
            ], guards: ["Read-only collection", "No secrets in AI context", "Authority changes never automatic"], aiPrompt: "Explain this IBM i authority evidence and propose a least-privilege review plan.", foundation: "The native Authority Path Atlas, bounded IBM i Services planner, fail-closed decoders, deterministic replay, local what-if, exact export, evidence receipts, and identity-withheld Assist context are implemented; live release, authority visibility, and effective-access coverage still require lab verification."
            )
        case .casebook:
            return .init(eyebrow: "CONTINUITY", promise: "Carry exact evidence, decisions, open questions, and AI provenance into the next shift.", pain: "Replaces screenshots, chat fragments, and personal notes with one bounded local handoff.", workspaceTitle: "CONTINUITY CASEBOOK", capabilities: [], guards: [], aiPrompt: "", foundation: "")
        case .terminal, .commandCenter:
            return .init(eyebrow: "WORKSPACE", promise: tool.subtitle, pain: "", workspaceTitle: tool.title, capabilities: [], guards: [], aiPrompt: "", foundation: "")
        }
    }
}
