# Product direction

## Product promise

iTelAS should answer the questions IBM i professionals lose time on every day:

- Where is the source, object, job, message, lock, or output involved?
- Which environment am I operating in, and what can this action change?
- Why did a compile, query, transfer, writer, or job fail?
- What depends on this object, and what evidence supports that dependency?
- How do I repeat an expert procedure safely and leave a useful handoff?
- How can AI help without silently receiving secrets or executing risky commands?

The long-term bar is a Swiss-army workbench that is faster and clearer than assembling a workflow from a terminal, editor, SQL client, FTP tool, spool viewer, spreadsheets, and personal notes.

## Pain-point map

| Pain | iTelAS workflow | Safety or quality bar |
| --- | --- | --- |
| Confusing host profiles and wrong-system changes | Persistent environment colors, system badges, production guard | Target is visible beside every consequential action |
| Parallel terminals lose context or disconnect each other | Concurrent session deck with per-tab state, retained screens, and independent recovery | Switching never replaces a transport; closing affects only the chosen session |
| 5250 setup and opaque connection failures | TLS-first Connection Studio with endpoint diagnostics | Fail closed on invalid certificates; explain DNS/TLS/port failures |
| Fragmented member and IFS editing | Unified source explorer, local outline/references/checks, exact navigation, compare, build recipe | Preserve source dates and expose CCSID conversion; never label local checks as compiler results |
| Compile errors scattered across event files and logs | Source-linked diagnostic timeline | Keep original message IDs, job log, and command evidence |
| Job and lock incident hopping | Job → waiter → holder → message → log trace | Read-only diagnosis first; review hold/end actions |
| SQL context and spreadsheet type loss | Query catalog, plan view, typed results and export | Row limit and transaction state are always visible |
| Dependency and impact uncertainty | Dependency Atlas with evidence-bearing edges and gaps | Never present candidates or missing evidence as facts |
| Spool-file hunting and poor conversion | Multi-identifier search, accurate preview, compare/export | Preview before delete; flag sensitive output |
| CCSID, decimals, dates, and truncation in transfers | Schema-first mapping and dry-run validation | Reject silent conversion or truncation |
| Operational knowledge trapped in notes | Typed runbooks with preconditions, gates, evidence, resume points | No embedded secrets; destructive steps require approval |
| Shift handoffs lose evidence, uncertainty, and AI provenance | Continuity Casebook with exact artifacts, answer receipts, reviewed references, open questions, and immutable snapshots | No ambient capture; stale boundaries and receiver acknowledgement remain explicit |
| Authority reports that obscure why access may occur | Evidence-backed access-path lattice and local what-if | Never claim complete effective authority; collection is read-only and remediation is unavailable |
| AI suggestions with unclear data exposure or no way to combine evidence | Opt-in provider, redacted Context Shelf, live bounded response channel, explicit Stop, command risk classification | Every pinned source and byte stays visible; provisional text stays labeled; no automatic execution |

## Delivery sequence

### Foundation — implemented here

- Native arm64 SwiftUI shell and original Pencil designs.
- Session profiles, TLS/plain transport choice, environment classification, and native Keychain storage for opt-in AI provider keys.
- Telnet/TN5250 record core, documented Write-to-Display control timing and keyboard state, exact color-display attributes, persistent extended-primary/color planes, type-selective Erase to Address, cursor/text blink, high intensity, message/alarm state, terminal rendering, and the AID path, including `X'8501'` Forward Edge Trigger and AID `X'50'`.
- Native Mac 5250 editing and profile-scoped F1–F24 routing, labels, and dock pins; semantic null/blank input buffering; auto-enter, Forward Edge Trigger, and automatic field advance; mandatory-entry/fill enforcement; right blank/zero adjustment; Field Exit/Plus/Minus and Dup; guarded paste review; mouse field targeting; accessibility; and a concurrent terminal deck with per-session transport, screen, history, input-mode, and bounded recovery state that never replays user input. Function-key layout changes are local profile settings and send no AID until the operator presses a mapped key; bulk paste never sends an automatic FET AID.
- A terminal-bound Host Command Deck for staging a small, curated set of read-only diagnostics into recognized command-entry fields; submission always remains an operator action.
- A keyboard-first universal command palette for navigating tools, connecting systems, staging diagnostics, opening history, copying redacted screens, and preparing AI questions without hunting through menus.
- Rectangular terminal selection, redacted copy, PNG/PDF capture, native screen printing, in-memory comparison, and editable session-profile workflows.
- A native Session Flight Recorder with explicit per-session arming, 7/30/90-day bounded retention, input/non-display clearing before persistence, exact redacted-frame fingerprints, duplicate collapse, `0700`/`0600` custody, local evidence export, reviewed profile-bound macros, durable execution receipts, and one-step-at-a-time operator playback. A macro never runs in the background or advances through a route automatically.
- A native Source & IFS workbench: local RPGLE scratch editing plus typed live IFS browse/read/compare/write behind the pinned system SFTP channel, fixed-column ruler and line gutter, path/ownership/permission/CCSID evidence, SHA-256 conflict detection, local-versus-current-remote review, and a staged-write flight recorder that never retries an uncertain result.
- A native Source Member Record Workbench: three-stage library/file/member catalog, exact identity, synchronized `SRCSEQ`/`SRCDAT` evidence, record-aware editing, CCSID byte validation, canonical conflict revisions, six visible write gates, deterministic member alias planning, and a separate reviewed-write ODBC capability. Live host behavior still requires lab verification.
- A native Source Intelligence Desk shared by scratch, member, and IFS drafts: bounded RPGLE/CLLE/COBOL/DDS structure, basic SQL object outline, typed include/call/file/format references, structural advisories, deterministic receipts, receipt-bound semantic coloring, clickable exact navigation, keyboard-driven local content assist, and symbol-scoped Assist review. Completion ranks qualified fields and current-document symbols before bounded format catalogs, validates the unchanged document before every undoable insertion, and performs no host lookup. It is explicitly local navigation evidence rather than a compiler or preprocessor.
- A native Source Cross-Reference Atlas: explicit folder selection, bounded and symlink-safe UTF-8 indexing, workspace search across files/symbols/references/text, exact occurrences opened as stale-aware read-only editor snapshots, exact-versus-ambiguous dependency evidence, review-fingerprinted cross-file completion, and reviewed local rename application bound to exact token ranges and content/modification baselines. A same-root refresh rereads every supported file byte, reuses analysis only for an exact path/format/UTF-8 match, rebuilds all dependency edges, and emits a deterministic in-memory change receipt. The Include Chain Navigator recursively follows exact indexed `/COPY` and `/INCLUDE` edges, records line and route provenance, identifies shared exact documents, and stops visibly at ambiguity, missing host content, unresolved targets, cycles, depth, document, or directive caps. Its deterministic session-only receipt can stage only the exact document closure for a separate completion review; it does not evaluate conditional compilation, SQL preprocessing, compiler expansion, binding, or release semantics. One exact host-backed `/COPY` or `/INCLUDE` edge can be frozen into a target/provider review and attested before a bounded source-member or IFS read installs a provenance-marked in-memory overlay for search, dependency resolution, recursive include mapping, and completion. A separate Compiler Evidence Bridge maps retained EVFEVENT file identities to exact current documents, binds `TGTRLS` and observed-host release context, records source-revision integrity, and allows navigation only when revision and coordinates are exact and no expansion remapping is required. It performs no fallback search, persistence, host write, compile, or Assist send, and host content is excluded from local rename. Local application validates every local file before writing, uses atomic per-file replacement with permission preservation and byte verification, rolls earlier replacements back on failure, and rebuilds the index after success. Remote compiler authority remains a separate evidence gap; a multi-file batch is not crash-atomic.
- A native Db2 Query Flight Deck, Typed Export Studio, and Connection Dossier: local SQL drafting, six searchable IBM i Services templates, explicit row/timeout/target/provider gates, conservative read-only syntax classification, a dynamically loaded TLS/read-only ODBC provider, typed result rendering, deterministic CSV/manifest and typed-JSON packages with schema and SHA-256 receipts, Keychain opt-in, and no automatic connection or execution.
- A native Compile Evidence Timeline: bounded local EVFEVENT parsing, source-linked diagnostics, exact message/coordinate evidence, a run ledger, explicit inference labeling, reviewed advice-only Assist context, and exact reviewed handoff into the current Source Atlas index. Its Compile Recipe Studio provides a permission-restricted local library of typed RPGLE and SQLRPGLE program recipes, deterministic command receipts, explicit target-release and SQL preprocessor contracts, and field-by-field comparison with one retained run. Its Compile Lineage Board compares two explicitly selected retained runs only within the same exact target identity, publishes deterministic field and exact-diagnostic deltas, and can pin an advice-only local context receipt. It generates previews and comparisons only; remote compile submission and compile-bound complete job-log collection remain connector work.
- A native Jobs & Queues Incident Thread: searchable job and queue inventory, exact waiting-lock and candidate-holder correlation, readable ordered job-log messages, QSYSOPR inquiry evidence, source receipts and gaps, a deterministic local replay, and an explicit non-production read-only refresh. It contains no hold, release, reply, end-job, or other host mutation path.
- A native Spool & Output Document Inspector: searchable file inventory, exact job/file/number identity, queue and writer pressure, bounded ordered text preview, local comparison and text export, evidence receipts, deterministic replay, and an explicit two-step non-production read-only collection path. It contains no host spool-copy, hold, release, move, writer, print, send, or delete path.
- A native Data Transfer Integrity Lab: bounded UTF-8 CSV profiling, exact source-to-target mapping, leading-zero preservation, decimal/date/boolean and CCSID loss checks, a deterministic local replay, exportable validation receipts, and an explicit non-production read-only target-schema refresh. Host writes are deliberately unavailable.
- A native System Health Evidence Cockpit: correlated system, CPU, ASP, job-table, temporary-storage, system-limit, and installed PTF-group evidence; an explainable local health index; independent capability receipts; deterministic replay; local export; and an explicit non-production read-only refresh. Certificate inspection and every host mutation are deliberately unavailable.
- A native Dependency and Impact Atlas: exact library/object/type identity, direct ILE binding and catalog evidence, separately labeled binding-directory candidates, independent source receipts, deterministic replay, local export, privacy-reduced Assist context, and an explicit non-production read-only collection path. Program-reference coverage, transitive analysis, runtime frequency, and safe-change verdicts are deliberately unavailable.
- A native Runbook Flight Deck: bounded local blueprint import, typed and exact substitutions, environment and mutation-budget gates, bounded read-only SQL analysis, CL preview classification, deterministic plan fingerprints, local plan-bound review attestations, evidence contracts, review export, and identity-withheld Assist preparation. It has no host executor, scheduler, command submitter, authenticated approval, or automatic resume path.
- A native Authority Path Atlas: exact profile and object scope, independently collected profile/group/object/AUTL/runtime evidence, caller-visibility gaps, separate static and observed paths, detailed authority-bit comparison, deterministic replay, local path-removal what-if, exact local artifact, and identity-withheld Assist preparation. It never claims complete effective authority and has no grant, revoke, profile, authorization-list, or collection-state mutation path.
- A System Provider Bay that distinguishes local runtime discovery from host trust and authority, exposes SSH/SFTP and Db2 prerequisites, and refuses to imply that a detected tool is a connected provider.
- A Secure Channel Dossier with validated SSH identity, explicit host-key collection/review, app-managed known-host pinning, and a bounded SSH plus SFTP subsystem test. The operator still chooses when to contact a host and when to pin evidence.
- AI provider adapter with bounded conversation continuity, incremental Server-Sent Events chat, immediate cancellation, preserved and visibly marked partial output, and an implemented Assist Context and Proposal Dossier for Source and SQL. The dossier provides explicit selection/whole-draft scope, exact redacted preview, frozen optional screen context, destination and baseline receipt, delimiter-safe untrusted-data envelope, conservative whole-response single-proposal parsing, and conflict-checked local-buffer apply with no host effect.
- A native Assist Context Shelf that composes up to eight distinct, operator-pinned evidence types across development, operations, and governance. Same-kind pins replace stale evidence in place; items remain removable; each request receives a newly frozen, deterministic bundle receipt; and the exact preview exposes source, scope, bytes, redaction state, fingerprints, destination, model, and prior-turn count. Each completed, stopped, or interrupted answer retains its own read-only receipt among the 32 newest answers, so later shelf changes cannot rewrite prior evidence; older rows show an explicit expired/session-limit state and New Chat clears the ledger. The 48,000-byte cap includes optional automatic screen context, so overflow blocks visibly instead of silently sending less context. The shelf and answer receipts are local state and have no send, provider, host, save, compile, or execution capability.
- A native Proposal Patch Stack that queues up to twelve immutable Source or SQL proposals, rejects mixed documents, stale baselines, invalid UTF-16 ranges, overlapping hunks, and combined whole-draft replacements, then previews one atomic local-buffer result. Its Local Impact Lens reports exact local byte, line, range, and affected-line changes while keeping compile, dependency, query-plan, authority, and runtime effects visibly unverified.
- A native Continuity Casebook with durable incident/change/build/transfer handoffs, exact Context Shelf artifacts, an evidence-linked Assist answer ledger, reviewed local repository/runbook references, explicit open questions and stale boundaries, and immutable exportable snapshots. Its local store is permission restricted, imports are bounded and traversal-safe, reference reuse is one explicit advice-only Context Shelf action, and no Casebook operation reads an API key or contacts a provider or host.
- Complete information architecture for the workbench modules.

### Terminal compatibility

- Remaining field orders, optional FCWs including check-digit, self-check, and cursor-progression, extended text/ideographic attributes, fourteen-shade device presentation, complete format-table semantics, AID edge cases, and TN5250E printer sessions. Core FFW auto-enter, `X'8501'` Forward Edge Trigger with AID `X'50'`, field-exit-required, mandatory-entry/fill, right-adjust, Dup, signed-numeric input, transparent input, SOH PF data masks, `X'80nn'` read resequencing, Read Input/MDT/MDT Alternate formatting, truthful 3179/3477 Query Reply, extended-primary and seven-color-plus-background WEA presentation, type-selective Erase to Address, local redacted PDF/printing, and reviewed one-step macros with durable redacted history are already available as deterministic local behavior and still require a host compatibility matrix.
- Full TN5250E negotiation coverage, device-allocation edge cases, and additional screen sizes.
- Full bidirectional field/cursor/OIA behavior plus CCSID 930/939 DBCS shift-state handling. Codec-only bidi profiles and mixed-byte sessions currently fail closed.
- Golden packet fixtures plus interoperability runs against supported IBM i releases and configurations.

### Developer workbench — next connector stage

- Qualify source-member catalog/read/write behavior across supported IBM i releases, authorities, CCSIDs, journal configurations, and concurrent edits; extend IFS support beyond UTF-8/CCSID 1208 and scale beyond the implemented responsive in-memory search, same-session drift monitoring, and exact-byte delta refresh with a persistent cross-session index and restart-safe change journal.
- Extend the Source Cross-Reference Atlas with release-aware semantic services and host-qualified large-workspace behavior; qualify its compiler-evidence bridge and reviewed source-member/IFS include reads across the supported release, CCSID, and authority matrix.
- Add the reviewed remote compile/job-log collector, EVFEVENT `EXPANSION` remapping, and test adapters to the implemented local evidence plane; extend the typed recipe set beyond RPGLE and SQLRPGLE programs.
- Add explain plans, true asynchronous ODBC cancellation, release-aware Dependency Atlas expansion, program-reference ingestion through a separately reviewed host-write boundary, and IBM i service compatibility checks.

### Operations workbench

- Extend the implemented read-only Jobs & Queues incident plane with release-aware compatibility probes, richer subsystem/queue aging, durable incident export, and separately reviewed operational actions only after lab evidence.
- Extend the implemented Spool & Output plane with release-aware compatibility probes, AFP/IPDS/page rendering, printer-device workflows, and separately reviewed mutations only after authority and lab evidence.
- Extend the implemented System Health evidence plane with release-aware compatibility probes, durable baseline comparison, scheduled local reports, and a separately reviewed certificate/DCM capability that never solicits a store password through Assist.
- Extend the implemented CSV/schema dry run with reviewed XLSX/ODS ingestion, IFS staging, resumable batches, and a separately authorized host-write protocol.

### Governance and assisted workflows

- Extend the implemented local Runbook review plane with a schema editor, durable versioning, authenticated signatures, organization policy, and separately authorized execution connectors with explicit stop and resume evidence.
- Extend the implemented Authority Path Atlas with release-aware service probes, function-usage evidence, broader object classes, audit baselines, and separately reviewed remediation planning that remains disconnected from execution.
- Provider adapters, optional local models, and organization policy.

## Version 1.0 gap ledger

Build 41 advances developer-workbench group 10 with the Db2 Typed Export Studio layered on an already-retained typed result. It emits deterministic RFC4180 CSV plus schema/receipt files or typed JSON, preserves nulls, exact decimals, temporal values, binary bytes, observed Db2 types, query/result/schema/plan SHA-256 receipts, and local file custody, and refuses re-query, missing provenance, unsafe destinations, symlinks, formula ambiguity, truncation, and resource-limit overruns. Schema-only Assist preparation remains local and advice-only. Explain plans, true asynchronous ODBC cancellation, release-aware Dependency Atlas expansion, program-reference ingestion, IBM i service compatibility checks, and broader export formats remain open, so sixteen major feature groups remain for a credible version 1.0; this is a planning count of substantial capability groups, not a count of screens, buttons, small fixes, or optional post-1.0 ideas.

### Terminal and compatibility — 6

1. Remaining 5250 orders, optional FCWs, AID edge cases, and complete format-table semantics.
2. Extended text/ideographic attributes and release-accurate fourteen-shade presentation.
3. Full TN5250E negotiation, device-allocation edge cases, and additional negotiated geometries.
4. Complete DBCS CCSID 930/939 and bidirectional field, cursor, and OIA behavior.
5. TN5250E printer-device sessions with truthful printer capability boundaries.
6. Golden-packet and supported-release compatibility lab coverage, including recovery and authority matrices.

### Developer workbench — 4

7. Source-member host qualification plus non-UTF-8 IFS conversion and resilient large-workspace search.
8. Host-qualified large-workspace behavior, supported-release compiler/CCSID qualification, and release-aware semantic services for the implemented index, host-include overlay, evidence bridge, and rename path.
9. Remote compile/job-log collection, EVFEVENT expansion remapping, broader language/object recipes, and test adapters.
10. Db2 explain plans and typed exports, true asynchronous cancellation, and release-aware dependency/program-reference expansion.

### Operations workbench — 4

11. Durable incident cases, subsystem/queue aging, compatibility probes, and separately reviewed operational actions.
12. AFP/IPDS/page fidelity, printer workflows, release probes, and separately reviewed spool mutations.
13. Health baselines, scheduled local reports, release probes, and a separately reviewed certificate/DCM capability.
14. XLSX/ODS ingestion, IFS staging, resumable transfer batches, and a separately authorized host-write protocol.

### Governance and assisted workflows — 2

15. Runbook schema editing, versioning, authenticated signatures, organization policy, and stop/resume execution evidence.
16. Authority baselines, function-usage and broader-object evidence, release probes, and disconnected remediation planning.

## Success measures

- Median time to explain a waiting job or object lock.
- Time from compile submission to the first source-linked root cause.
- Percentage of operations completed without opening a second client.
- Wrong-environment actions caught before execution.
- Transfers completed with explicit type/CCSID validation.
- AI turns with a visible context receipt and zero automatic command execution.
- AI responses that can be stopped without losing the operator's draft or creating an applicable partial proposal.
