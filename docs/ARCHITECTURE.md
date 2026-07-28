# Architecture

## Principles

1. Native macOS presentation and networking: SwiftUI, Observation, Network.framework, Security.framework, and Foundation.
2. Clean-room protocol implementation from published RFCs and observed interoperability requirements.
3. Workflows depend on typed capabilities, not on view code or terminal scraping.
4. Read-only diagnostics precede mutations. Environment, target, command, and risk remain visible.
5. AI is a replaceable assistant service. It cannot become an execution authority.

## Current layers

```text
iTelAS SwiftUI application
├── AppModel: profiles, concurrent terminal deck, per-session bounded recovery, source intelligence/navigation/completion/index-review state, source/IFS/SQL/job/spool/transfer/health/impact/runbook/authority/casebook workflow state, assistant state and response provenance
├── Workbench views
│   ├── Command Center and professional tool workspaces
│   │   └── Host Command Deck (read-only classification → recognized field → local staging)
│   ├── Universal Command Palette (search → scope → availability → explicit action)
│   ├── Connection Studio, concurrent session switcher, and terminal canvas with AppKit first-responder input
│   ├── Source & IFS studio with an AppKit text surface, line gutter, metadata ribbon, and switchable Intelligence/Safety desk
│   │   ├── Source Intelligence Desk (bounded semantic coloring + outline/references/local checks → exact editor navigation → receipt-bound content assist → reviewed Assist handoff)
│   │   ├── Source Cross-Reference Atlas (explicit folder → recursive Workspace Drift Radar → bounded local index → exact-byte incremental refresh → recursive lexical Include Chain Navigator → reviewed exact host-include overlay → compiler-evidence bridge → dependency review → indexed completion → immutable rename review → rollback-protected local apply)
│   │   └── Source Member Record Workbench (object navigator → record editor → integrity desk)
│   ├── Db2 Query Flight Deck with services catalog, SQL editor, execution gate, typed result plane, and Typed Export Studio
│   ├── Compile Evidence Timeline with run ledger, source-linked diagnostics, evidence dossier, local import, typed Compile Recipe Studio, and exact-target Compile Lineage Board
│   ├── Jobs & Queues Incident Thread with workload ledger, exact wait chain, readable log, dossier, and receipts
│   ├── Spool & Output Document Inspector with output runway, text record plane, comparison, dossier, and receipts
│   ├── Data Transfer Integrity Lab with flight plans, mapping matrix, exception ledger, dossier, and receipts
│   ├── System Health Evidence Cockpit with pulse band, limit ledger, capacity correlation, maintenance dossier, and receipts
│   ├── Dependency and Impact Atlas with an evidence graph, relation ledger, decision dossier, and source receipts
│   ├── Runbook Flight Deck with a blueprint library, typed parameter rack, resolved step map, and preflight dossier
│   ├── Authority Path Atlas with an evidence ledger, access lattice, authority matrix, local what-if, and review dossier
│   ├── Continuity Casebook with case queue, evidence relay, custody gates, Assist answer ledger, reviewed references, and immutable snapshot manifest
│   ├── System Provider Bay with fixed-path local runtime evidence and fail-closed capability gates
│   ├── Secure Channel Dossier with target validation, host-key evidence, exact pins, and explicit channel test
│   └── AI Assist and settings
└── Services
    ├── KeychainStore plus permission-restricted LocalTextDocumentStore, CompileRecipeStore, ContinuityCasebookStore, and TerminalFlightRecorderStore
    ├── SecureChannelService and IFSWorkspaceService (direct system OpenSSH processes; no shell)
    ├── SourceWorkspaceDriftMonitor (recursive FSEvents plus bounded metadata-only fallback) and SourceWorkspaceIndexService (operator-selected folder enumeration plus review-bound local rename application), with exact host-include intake through existing typed source-member/IFS providers
    ├── Db2ODBCTransport (dynamic unixODBC ABI, typed capability authorization, no bundled driver)
    ├── TerminalExportService (redacted copy, PNG/PDF, and native macOS print workflow)
    └── AIService + AIChatStreamParser + AssistantRequestReceiptStore (bounded SSE chat, whole-response proposal review, 32 answer-bound session receipts)

iTelASCore
├── SessionProfile, truthful 3179/3477 device capabilities, terminal screen/null-buffer/read-mode model, validated FFW field execution, protected-field editing, input encoding, and rectangular selection
├── SourceDocument, member/IFS identity, SourceProvider/IFSProvider contracts, draft delta, and write preflight
├── Bounded RPGLE/CLLE/COBOL/DDS/SQL source intelligence, typed references, local checks, fingerprints, semantic highlight spans, UTF-16 navigation ranges, and deterministic completion sessions
├── Bounded workspace drift observations/receipts, source index, evidence-labeled dependency resolution, recursive include-chain documents/directives/boundaries/limits/receipts, exact host-include review/content/provenance contracts, index-bound compiler evidence/release/revision contracts, reviewed completion symbols, exact rename ranges, and immutable rename-review contracts
├── Source-member identity, fixed-precision records, metadata/revision model, Db2 planner/provider, and write gates
├── IFSPath, bounded listing parser, UTF-8 codec, strong revision, typed SFTP batch, write plan, and receipt
├── SQL statement analysis, query policy/preflight, IBM i Services catalog, typed results, and DatabaseProvider contract
├── Bounded EVFEVENT parser, exact source identities/coordinates, severity model, inference-labeled triage analysis, and typed deterministic RPGLE/SQLRPGLE compile recipes
├── Bounded job, queue, object-lock, job-log, operator-message models and exact-correlation incident analysis
├── Bounded delimited-text profiler, target schema model, transfer mapping analyzer, and read-only schema planner
├── Bounded system-status, CPU, ASP, system-limit, PTF models, transparent assessment, and read-only health planner
├── Exact object identity, bounded direct-impact evidence, independent source receipts, privacy-reduced context, and read-only impact planner
├── Typed runbook blueprints, bounded JSON codec, exact resolver, risk assessment, plan fingerprint, local artifact, and privacy-withheld context
├── Typed authority profile/group/object/AUTL/runtime evidence, path analyzer, read-only planner, exact artifact, and identity-withheld context
├── Bounded ContinuityCasebook cases/artifacts/answers/reviewed references, deterministic fingerprints, readiness gaps, and immutable handoff snapshots
├── ProviderRuntimeProbe and typed evidence for architecture, SSH/SFTP, unixODBC, IBM i ODBC, and TLS prerequisites
├── SecureChannelProfile, host-key parser/fingerprints, hardened command plans, and ManagedKnownHostsStore
├── TelnetNegotiator (streaming IAC/EOR plus RFC 4777 environment negotiation)
├── TN5250Record and TN5250StartupResponse (RFC 1205/4777 headers and framing)
├── TN5250DataStreamParser (initial command/order subset plus Read Input/MDT mode selection)
├── TN5250DeviceQuery (strict Query recognition and model-specific capability reply)
├── TN5250Client (Network.framework TLS/TCP transport)
├── EBCDICCodec and CCSID catalog (native SBCS registry; explicit DBCS boundary)
└── AIContextRedactor, bounded AIContextShelf/AIContextBundle, AIProposalParser, AIProposalPatchStack, and IBMCommandSafetyClassifier
```

The core library does not depend on SwiftUI. This keeps protocol fixtures, source write gates, and safety behavior testable without launching the application.

## Source intelligence path

```text
Current local scratch, source-member snapshot, or IFS draft
  → 2 MiB / 25,000-line / per-line resource gates
  → format-aware local analyzer
  → dialect + deterministic SHA-256 receipt
  → declaration outline + typed references + structural advisories + priority-ordered highlight spans
  → receipt-bound AppKit attribute refresh with text, selection, typing, undo, and write semantics preserved
  → Control-Space completion session bound to the exact document receipt, caret, prefix, qualifier, and replacement range
  → keyboard or pointer activation → validated undoable local insertion, or a distinct reviewed Assist handoff
  → exact one-based line/column to UTF-16 editor selection
  → optional symbol-scoped Assist context dossier
  → separate Compile Evidence authority for IBM diagnostics
```

The analyzer is deliberately lexical and local. It recognizes useful declarations and references for RPGLE, CLLE, COBOL, DDS, and a small SQL outline without contacting a host or reading included content. Its highlighter scans quoted literals and comments before vocabulary, layers declaration spans from the same snapshot, caps resource use, and applies colors only while the editor's current text fingerprint matches the analysis receipt. The completion engine reuses that exact receipt, refuses stale or invalid UTF-16 positions, stays quiet inside recognized strings and comments, caps candidates and visible items, and validates the unchanged fingerprint again before insertion. The Include Chain Navigator consumes only the resulting current-index `/COPY` and `/INCLUDE` edges. A deterministic depth-first walk traverses one exact indexed target, marks repeat visits as shared, records active-route cycles, and emits explicit boundaries for ambiguity, missing host content, unresolved targets, and depth/document/directive caps. The receipt binds the whole index, root content, document fingerprints, directive identities, limits, routes, and boundaries. Its exact-document list can replace only the draft completion selection; the existing review gate remains separate. The optional Assist item is a non-inserting action that only prepares the existing review dossier. None of these layers claims conditional preprocessing, binding, object existence, semantic type resolution, release-specific command validity, expanded source coordinates, or compiler correctness. The UI keeps the existing Change Lens, record-integrity, and write-flight-recorder surfaces available beside Intelligence so navigation convenience never replaces write evidence.

## Source cross-reference index path

```text
Explicit macOS folder selection
  → reject file or symbolic-link roots
  → start recursive FSEvents; use a bounded metadata-only fallback if the stream is unavailable
  → normalize supported path signals → coalesce 650 ms → deterministic session receipt
  → pending signal immediately locks index-bound completion, compiler mapping, rename, and navigation
  → skip hidden/package descendants, symbolic links, unsupported extensions, NUL data, non-UTF-8 data, and oversized files
  → bounded per-file and aggregate local analysis
  → deterministic document/index fingerprints
  → same-root refresh rereads every supported UTF-8 file byte
  → exact path + format + byte match reuses analysis; changed and added files are analyzed; removed files are retired
  → rebuild every current dependency edge → deterministic before/current index-bound delta receipt
  → clear only drift event identifiers at or before the scan boundary; retain later signals for another exact scan
  → debounced query → cancellable off-main file + symbol + reference + text search
  → query/index generation check → deterministic coverage, cap-state, duration, and search receipt
  → exact occurrence → stale-aware read-only editor snapshot
  → exact / ambiguous / host-content-not-loaded / unresolved dependency labels
  → one exact host-content edge → frozen index/source/target/provider review + explicit attestation
  → exact source-member or IFS read → identity/revision/CCSID validation → provenance-marked in-memory overlay
  → retained compile run → reviewed FILEID-to-document mapping + TGTRLS/observed-release context
  → exact source revision + in-bounds coordinates + no EXPANSION gap → attested local diagnostic navigation
  → changed/unrecorded revision or mapping gap → visible evidence without navigation
  → operator-selected dependency files → exact review receipt
  → reviewed workspace symbols enter local editor completion
  → token-aware rename preview freezes exact UTF-16 ranges plus content, modification-time, and optional source-date baselines
  → separate immutable review + explicit attestation
  → revalidate every local target → atomic per-file replacement + byte verification
  → reverse rollback on failure, or fresh index + apply receipt on success
```

The base index holds source text only in application memory. An explicit new-folder choice starts monitoring before the scan so changes cannot silently cross the initial scan boundary. FSEvents provides the primary recursive path/flag stream; if it cannot start, a bounded 650-millisecond metadata snapshot compares only supported paths, type, size, modification time, and resource identity. Neither signal path reads source bytes. Safe relative paths, kinds, raw counts, and event identifiers are coalesced into a deterministic receipt capped at 2,048 raw observations and 256 unique paths. Root changes, dropped or wrapped streams, overflow, and paused intervals require full verification. Signals are advisory rather than content evidence, so any pending observation immediately revokes index-bound completion, compiler attachment/navigation, rename review/application, opened-snapshot currency, and occurrence navigation. An exact scan captures a boundary and clears only observations at or before it; later events remain pending. Automatic verification is enabled by default, while pause/resume and Verify now remain explicit. No monitor or receipt survives application exit.

A same-root refresh still rereads every supported file's UTF-8 bytes; only an exact path, format, and byte match can reuse the prior analysis snapshot, while added or changed files are analyzed, removed files are retired, and every current dependency edge is rebuilt. The refresh report binds the previous and current index fingerprints to exact input, reuse, analysis, addition, removal, byte, duration, and changed-file evidence. No index or delta cache survives application exit, so a later launch performs full analysis. Each nonempty search is debounced for 140 milliseconds, runs in a cancellable detached task, checks cancellation throughout document and line traversal, and publishes only when its task generation, index fingerprint, and normalized query still match. The report discloses documents and lines examined, candidate and result caps, completion state, local duration, and a deterministic receipt; the UI never re-executes a full search during view rendering. Local scanning never follows a source symlink, contacts a provider, reads an API key, or sends source to Assist. The Include Chain Navigator performs a bounded depth-first traversal over only current lexical include edges, includes the root plus exact indexed targets in its closure, records source depth, exact line/column, route, candidates, content fingerprints, shared routes, and visible boundaries, and becomes unusable after any index or drift-gate change. Staging that closure changes only the draft dependency selection and never approves completion. A host-backed include remains content-not-loaded until the operator opens a separate review bound to the current index fingerprint, exact source edge and range, exact target, provider identity, and byte budget. After checkbox attestation, the app performs only that exact source-member or absolute non-root IFS read through an already authorized provider, validates returned identity/revision/CCSID evidence, and installs a synthetic-path overlay carrying immutable provenance. It never searches alternative libraries or paths, crawls the host, persists fetched content, writes to the host, or sends content to Assist. Dropping the overlay or refreshing returns to the local-only index; provider/target/index changes invalidate review. The Compiler Evidence Bridge is another independent local review: it binds one retained run and its SHA-256 evidence to the current index, maps each compiler file identity explicitly, records `TGTRLS` with an optional observed host release, and compares a retained source revision when present. Attachment requires attestation. A diagnostic may navigate only when its source revision is exact, its unmodified line and column coordinates are within the indexed document, and no `EXPANSION` record makes the source map incomplete; every other diagnostic remains visible as non-navigable evidence. The bridge does not compile, query a provider, read a host, access Keychain, or prepare Assist. Opening an occurrence copies indexed text into an immutable editor view; it cannot edit or autosave and becomes visibly stale if the current index receipt changes. Any index change invalidates dependency, include-chain, and compiler-evidence review. Rename excludes all host-backed documents plus recognized local comments and string literals, refuses limited highlighting evidence, and freezes exact local occurrence ranges and baselines. Application is available only for the operator-selected local root after a second immutable review and checkbox attestation. The service rejects symbolic roots, parents, and leaves; validates the complete bounded batch before writing; rechecks each target immediately before its atomic replacement; preserves POSIX permissions; verifies committed bytes; and restores earlier replacements in reverse order after a failure. Rollback refuses to overwrite a target that no longer equals iTelAS's replacement and reports every unresolved path. Success requires a fresh index. The batch has no persistent transaction journal and is not crash-atomic; sudden process or power loss, or an external edit in the final check-to-replace interval, can require local inspection. Dependency edges and include-chain routes remain lexical/path evidence rather than preprocessing, binding, compiler, or runtime proof.

## Source workspace path

```text
Local scratch or remote IFS document
  → typed identity (scratch, member, or IFS path)
  → source format, CCSID, source-date policy, line ending, remote revision
  → native editor + line/column instrumentation
  → current-vs-baseline draft delta
  → provider/identity/revision/CCSID/compare write preflight
  → immutable write review
  → revision re-read → staged upload → staged hash → pre-rename revision re-check → rename request
  → committed-byte re-download and receipt, or an explicit uncertain-outcome stop
```

The current milestone implements the model, local editor, permission-restricted atomic scratch autosave, and a typed IFS provider over the pinned system SFTP channel. IFS paths reject traversal/control input and are quoted only by the central batch encoder. Directory parsing and editable files are bounded; symlinks, special objects, binary files, BOM-bearing UTF-8, mixed line endings, files over 2 MiB, and CCSIDs other than 1208 are blocked rather than inferred. A remote write is available only after an exact SHA-256 comparison and a separate review bound to one host, path, expected revision, payload hash, byte count, and generated sibling path.

## Source-member record path

```text
Validated library + source physical file + member
  → bounded SYSFILES / SYSMEMBERSTAT / JOURNALED_OBJECTS metadata
  → deterministic QTEMP alias for the exact member
  → RRN-ordered SRCSEQ + SRCDAT + SRCDTA records
  → canonical revision over identity, layout, CCSID, and every record field
  → record-aware edit preserving unchanged sequence and source date
  → authority + standard-layout + trigger + CCSID + journal gates
  → exact revision re-read → serializable transaction → committed revision verification
```

Source members are not treated as ordinary SFTP text files because that would discard or blur record metadata. The core provides validated classic system-object names, exact fixed-precision sequence/date values, lossless CCSID width checks, typed catalog and member SQL requests, a deterministic `QTEMP` alias lifecycle, and a provider contract. Inserts use available sequence gaps without renumbering existing records; an exhausted gap blocks the edit. Writes require complete record authority, the standard three-field source layout, no triggers, journal before-and-after images, and an unchanged opening revision.

The native ODBC actor implements the exact source metadata/read lifecycle and a serializable delete-and-record-insert replacement with baseline and committed-revision checks. A separate authorizer rejects forged SQL, mismatched aliases, weakened journal evidence, or the wrong connection capability. The UI exposes source-read and reviewed-source-write as explicit, mutually visible session capabilities; member writes remain unavailable for production profiles, require a second review sheet, and have not been exercised against a host.

## Db2 query path

```text
Local SQL draft or curated IBM i Service
  → comment/string-aware statement analysis
  → single-statement + read-only syntax policy
  → row cap + timeout + explicit non-production target
  → connected DatabaseProvider gate
  → dynamically loaded native ODBC + driver-enforced read-only connection
  → typed columns, values, nulls, CCSIDs, timings, and provenance
  → typed result plane or sanitized diagnostic
```

The current milestone implements the editor, local atomic autosave, six official-service starting points, policy/preflight model, Db2 Connection Dossier, dynamic unixODBC transport, typed result plane, and Typed Export Studio. The transport uses one non-production identity, TLS-only connection keywords, read-only connection attributes, login/connection/query timeouts, prepared execution, row bounds, and typed result fetching. Profiles contain no password; optional password persistence uses a device-only Keychain item keyed by profile UUID. If the local driver stack is absent, connection fails before loading a driver or contacting a host.

Typed Export Studio consumes only the exact retained result plus its query, provider, environment, schema, and plan provenance; it never reruns SQL. Its bounded contract emits either a UTF-8 RFC4180 CSV package (`data.csv`, `schema.json`, `receipt.json`) or a typed JSON document, with reversible null/formula/decimal encodings, ISO 8601 UTC temporal values, Base64 binary values, observed Db2 kinds, and SHA-256 receipts for every input and output. Local saves use a confirmed destination, refuse symlink targets, create `0700` package directories and `0600` files, verify bytes after writing, and expose only schema and receipts to advice-only Assist preparation.

Syntax classification remains a usability control rather than a complete SQL authorization boundary: a read-only statement can invoke a routine with external effects. Interactive execution therefore additionally requires the read-only transport capability and rejects multi-result/procedure paths, but organization deployments still need a least-privilege IBM i profile and policy for callable routines. Explain plans and true asynchronous cancellation remain future work.

## Compile evidence path

```text
Typed local recipe draft
  → bounded name + exact IBM i source/target identifiers + fixed option vocabulary
  → deterministic CRTBNDRPG or CRTSQLRPGI program preview with OPTION(*EVENTF)
  → exact command and recipe fingerprints
  → permission-restricted schema-v1 local library
  → field-by-field comparison with one separately retained run
  → optional clipboard copy; no submission or execution path

Local UTF-8 EVFEVENT export or bundled replay
  → byte, record-count, record-size, path, message, UTF-8, and NUL gates
  → processor-scoped FILEID / FILEIDCONT identity reconstruction
  → exact ERROR message ID, severity, file, line, and column records
  → SHA-256 evidence receipt + visible unresolved/EXPANSION limitations
  → first source-linked diagnostic at the highest blocking severity
  → explicit “triage lead, not proof of causality” label
  → source replay, evidence table, summary records, command evidence, and timeline
  → optional Source Atlas bridge: exact index/run/evidence/release/revision review + local attachment
  → optional redacted compile-evidence context receipt for one reviewed Assist request
```

The parser is an independent Swift implementation of the published EVFEVENT record contract. It does not execute a compiler, query an event file, fetch a job log, or infer an object replacement. Local imports are capped at 4 MiB, 50,000 records, and 4 KiB per record. Unknown records are counted; malformed recognized records, invalid continuations, NUL bytes, invalid UTF-8, oversized paths, and oversized messages fail closed. `EXPANSION` records are counted but generated-to-original source remapping is not yet implemented, so the UI never claims those coordinates were resolved.

The Compile Recipe Studio stores at most 64 recipes in a private local file and permits only two verified program-command shapes: `CRTBNDRPG` and `CRTSQLRPGI`. Names are bounded, system identifiers pass the existing IBM object-name validator, target release is `*CURRENT`, `*PRV`, or exact `VvRrMm`, and every other emitted value comes from a fixed enum. SQL commitment control and `RPGPPOPT` are unavailable for plain RPG recipes. Timestamps use the store's millisecond precision; semantic receipts bind recipe identity, environment, source, target, and exact command rather than timestamps. The studio never stores source bodies or credentials and has no provider, submit, retry, or host path.

The Compile Lineage Board accepts at most 32 retained runs and 20,000 diagnostics, validates every run and exact diagnostic identity, and compares only an explicitly selected baseline/current pair with the same target identity. Twelve field deltas, introduced/resolved/persistent message identities, target-release state, trend, and the chosen run fingerprints feed one deterministic receipt. Duplicate run fingerprints, malformed evidence, same-selection comparison, cross-target scope, and input caps fail closed. The board does not infer causal order, complete job-log coverage, object replacement authority, or runtime behavior; its optional Assist item only prepares bounded local advice context.

The current Build & Test workspace uses a clearly labeled bundled replay and operator-selected local imports. Retained evidence can be attached to the Source Atlas only through the exact local review above; this is not a compiler compatibility verdict. Recipe comparison does not claim that a retained run was produced from the current recipe; it reports exact, changed, relative, or unavailable fields. A remote compiler connector remains future work and must bind a non-production target, exact source revision, reviewed command/library list, job identity, EVFEVENT member, complete job-log evidence, object outcome, and no-automatic-retry rule.

## Job incident evidence path

```text
Explicit refresh on a connected non-production read-only Db2 provider
  → bounded JOB_INFO inventory (required)
  → bounded OBJECT_LOCK_INFO snapshot (optional evidence surface)
  → preserve the selected exact NUMBER/USER/JOB identity or choose a visible waiter
  → bounded JOBLOG_INFO for that exact job (optional evidence surface)
  → bounded QSYSOPR MESSAGE_QUEUE_INFO inquiries (optional evidence surface)
  → typed decode by unique column name with row, text, identifier, and control-character gates
  → exact-object waiter-to-holder candidate correlation
  → visible source receipts, truncation state, query fingerprints, and unavailable gaps
  → optional redacted advice-only context for one reviewed Assist request
```

`JOB_INFO` is required; if it fails, the prior local or live snapshot remains intact. The other services are independently optional because release level, authority, or object visibility can differ. A failure on one creates a bounded sanitized evidence gap rather than erasing the successful inventory. Every request is a single read-only statement with an explicit row cap and 30-second timeout, and the application blocks this workflow for production profiles.

The correlation model compares the complete library/object/member/type identity. One different job with a `HELD` row for that identity is a strong candidate, but not proof that the scheduler is blocked by that job or that the lock modes are incompatible. Lock rows are labeled “at snapshot” because the service supplies state without a lock timestamp; only supplied message timestamps are shown chronologically. The UI exposes no reply, hold, release, or end-job operation.

## Spooled output evidence path

```text
Explicit refresh on a connected non-production read-only Db2 provider
  → bounded SPOOLED_FILE_INFO inventory (required; no file content)
  → bounded OUTPUT_QUEUE_INFO writer and authority snapshot (optional)
  → preserve or choose one exact job/file/number/system identity
  → explicit second action for bounded SYSTOOLS.SPOOLED_FILE_DATA records
  → column-keyed typed decode with identity, status, priority, text, control, and row gates
  → ordered local text preview plus exact-identity comparison and UTF-8 export
  → visible source receipts, truncation state, query fingerprints, and unavailable gaps
  → optional redacted advice-only context for one reviewed Assist request
```

Inventory and content are separate capabilities. `SPOOLED_FILE_INFO` and `OUTPUT_QUEUE_INFO` describe visible files, queues, writers, and authority without opening a file. Content requires a separate exact identity and explicit operator action because `SPOOLED_FILE_DATA` internally uses a spool-copy operation and may be audited. Every request is a single read-only statement with fixed limits and a 30-second timeout, and production collection is blocked by the application policy.

The preview preserves ordered text records, including leading and trailing spaces, and fingerprints the bytes. It does not claim page boundaries, fonts, overlays, graphics, AFP/IPDS fidelity, or lineage between two separately selected spool identities. Comparison is ordinal-aligned local evidence only. Export writes a local UTF-8 artifact with exact identity, completeness, digest, and fidelity notes. The UI exposes no hold, release, move, writer, host spool-copy, print, send, or delete operation.

## Data transfer integrity path

```text
Operator-selected UTF-8 CSV or bundled deterministic replay
  → byte, row, column, field, header, quote, control, and structure gates
  → immutable source profile with inferred types, leading-zero evidence, and SHA-256 receipt
  → validated classic library/table identity
  → explicit non-production read-only SYSCOLUMNS2 metadata request
  → column-name-keyed target decode with identity, ordinal, type, length, scale, nullable, CCSID, generation, and updateability gates
  → exact source-to-target mapping and local dry-run analysis
  → blockers for ambiguous dates, encoding loss, truncation, range/precision overflow, or missing required columns
  → local validation artifact or metadata-only reviewed Assist request
```

The parser accepts UTF-8 with an optional BOM and RFC 4180-style quotes, escaped quotes, CRLF/LF records, and embedded line breaks inside quoted cells. It rejects malformed quotes, duplicate or oversized headers, inconsistent columns, control characters, oversized cells, and inputs beyond 8 MiB, 25,000 data rows, or 256 columns. Source values remain strings; inference is evidence for mapping and never coerces leading-zero identifiers into numbers.

Target discovery is one generated, bounded, single-statement read-only query against `QSYS2.SYSCOLUMNS2`. Library and table identifiers must satisfy classic IBM system-name rules before they enter SQL, while result decoding uses unique column names rather than positional assumptions. This milestone cannot upload, insert, update, merge, call a procedure, stage an IFS file, or construct a host-write statement. Its local export contains schema, issue, completeness, and digest evidence but deliberately omits source cell values.

## System health evidence path

```text
Explicit refresh or bundled deterministic replay
  → connected driver-enforced read-only Db2 capability + non-production target gate
  → bounded SYSTEM_STATUS_INFO snapshot and one-second SYSTEM_ACTIVITY_INFO CPU sample
  → independent bounded ASP_INFO, SYSLIMITS, and GROUP_PTF_INFO requests
  → column-name-keyed typed decode with duplicate, missing, malformed, value, and row-cap gates
  → system/ASP/job-table/temporary-storage correlation plus pressure-ranked high-water occurrences
  → transparent local health-index penalties and independent collected/unavailable receipts
  → local evidence artifact or metadata-only reviewed Assist request
```

The five sources fail independently so a release, PTF, or authority gap does not erase usable evidence from another surface. Every request is a generated single read-only statement with a 30-second timeout; plural surfaces are capped at 64 ASPs, 100 limit occurrences, and 100 PTF groups. Connection identity changes cancel collection and retain prior evidence without presenting it as current. Production refresh and every host-changing operation are blocked.

CPU comes from `SYSTEM_ACTIVITY_INFO(1)` because the average CPU columns in `SYSTEM_STATUS_INFO` do not provide the intended sample on current IBM i releases; the authority-dependent sample may remain visibly unavailable. `SYSLIMITS` rows are labeled recorded high-water occurrences, never time-series trends or exhaustion forecasts. Installed group PTF status does not establish internet currency. `CERTIFICATE_INFO` is not queried because its certificate-store password and elevated-authority contract belongs to a separate reviewed DCM capability.

## Dependency and impact evidence path

```text
Exact library + object + IBM object type or bundled deterministic replay
  → connected driver-enforced read-only Db2 capability + non-production target gate
  → independent bounded OBJECT_STATISTICS, BOUND_SRVPGM_INFO, BOUND_MODULE_INFO,
    BINDING_DIRECTORY_INFO, SYSROUTINES, and SYSVIEWDEP requests
  → column-name-keyed typed decode with identity, duplicate, malformed, control, and row-cap gates
  → BOUND and CATALOG direct edges kept distinct from CANDIDATE binding-directory entries
  → source receipts plus explicit authority, release, *LIBL, and program-reference gaps
  → REVIEW REQUIRED assessment, local evidence artifact, or privacy-reduced advice-only Assist request
```

The six sources are requested independently so unsupported services or insufficient authority remain visible gaps without erasing collected evidence. Queries are type-gated, exact or tightly bounded, single-statement, read-only, limited, and timed out after 30 seconds. Duplicate-looking edges are deduplicated without upgrading their evidence class. An unresolved `*LIBL` binding remains unresolved rather than being assigned to a guessed library.

`DSPPGMREF` is deliberately not invoked because its output-file contract writes an object on the host. The Atlas therefore exposes program-reference coverage as a gap until a separately reviewed collection boundary exists. It makes no claim about runtime frequency, transitive completeness, causal use, release compatibility, or whether a change is safe. Every assessment remains `REVIEW REQUIRED`.

## Runbook review path

```text
Bundled deterministic replay or explicit bounded local JSON import
  → schema, size, identifier, step-count, parameter-count, and secret-name validation
  → exact target + allowed environment + typed parameter normalization
  → one bounded read-only SQL statement or one separator-free CL preview per action step
  → conservative risk classification + mutation-budget gate
  → deterministic SHA-256 resolved-plan fingerprint
  → fingerprint-bound local review attestations + declared evidence contract
  → REVIEW REQUIRED assessment
  → local review artifact or identity-withheld advice-only Assist context
  → stop: no executor, scheduler, command submitter, approval authority, or automatic resume path
```

Changing a target, environment, or typed value invalidates the resolution and clears its local attestations. Changing the operator reason also requires revalidation, while attestations remain usable only if the exact plan fingerprint still matches. Free text cannot interpolate into an action; parameter names associated with credentials or secrets are rejected; destructive and unknown actions fail closed. Local attestations record an alias and fingerprint but do not authenticate identity. Evidence entries state what a future operator must collect and never fabricate a receipt.

## Authority evidence path

```text
Exact user profile + library + object + IBM object type or bundled deterministic replay
  → connected driver-enforced read-only Db2 capability + non-production target gate
  → independent bounded USER_INFO, GROUP_PROFILE_ENTRIES, OBJECT_PRIVILEGES,
    and AUTHORITY_COLLECTION requests
  → conditional AUTHORIZATION_LIST_USER_INFO request only when one caller-visible AUTL identity exists
  → column-name-keyed decode with identity, duplicate, malformed, control, truncation, and row-cap gates
  → static direct/group/public/owner/*ALLOBJ/AUTL paths kept separate from observed authority checks
  → caller-visibility, function-usage, adopted-authority, cached-check, and runtime-coverage gaps
  → REVIEW REQUIRED assessment, local path-removal what-if, exact artifact,
    or identity-withheld advice-only Assist context
```

The planner emits only fixed single-statement read-only queries with exact validated identities, 30-second timeouts, and overflow rows beyond caps of 16 memberships, 100 object grants, 100 authorization-list entries, and 100 runtime observations. Each source fails independently. If `OBJECT_PRIVILEGES` does not expose exactly one authorization-list identity, no authorization-list entry query is guessed; the missing dependency stays visible as a gap. Connection or scope changes cancel collection and prior evidence is not relabeled as current.

The analyzer is deliberately explanatory rather than authoritative. Static rows describe reported grants; authority-collection rows describe only checks that were exercised while collection was active. A local what-if removes selected reported static paths in memory and never predicts every runtime outcome. The implementation contains no grant, revoke, profile change, authorization-list change, authority-collection control, or host-write API, and every result remains `REVIEW REQUIRED`.

## Assist review path

```text
Explicit Source/SQL selection, whole-draft choice, prepared compile evidence, selected job incident evidence, selected spooled-output evidence, prepared transfer metadata, prepared system-health metadata, prepared object-impact evidence, a prepared runbook review contract, prepared authority-path evidence, or one explicitly selected Casebook-reviewed reference entry
  → strict UTF-16 selection-boundary validation
  → credential-marker redaction + per-item and bundle byte caps
  → optional operator pin into the local Context Shelf; same-kind evidence replaces its stale predecessor
  → exact multi-source preview + destination/model/document/baseline/content receipt
  → one immutable request snapshot from the currently visible shelf and optional automatic redacted screen
  → delimiter-safe untrusted JSON envelope + deterministic bundle fingerprint
  → advice-only streaming chat, or one whole-response Source/SQL review with an immutable target/baseline/selection proposal contract
  → prose response and optional single versioned proposal parse
  → bind the completed, stopped, or interrupted answer to its immutable question/destination/model/context receipt
  → retain the 32 newest receipts for read-only answer-level inspection; older rows disclose expiry and New Chat clears the ledger
  → target + baseline + selection contract match
  → current local draft SHA-256 re-check
  → direct operator review, or optional immutable Proposal Patch Stack queue
  → exact document/baseline/UTF-16/overlap/whole-draft compatibility preview
  → local impact facts + explicit unverified IBM i evidence gaps
  → one atomic local-buffer replacement, or a fail-closed stop
```

The dossier snapshots editor text and any optional redacted 5250 screen before sending; it has no ambient workspace access. It can also pin that already bounded snapshot into the shelf without contacting a provider. `AIContextShelf` preserves operator order, permits at most one item of each evidence kind, replaces that kind in place when repinned, and validates the complete candidate set transactionally before changing visible state. The request bundle permits at most eight items, 32 KiB per item, and 48,000 UTF-8 bytes total. Optional automatic screen context participates in those same count and byte limits; enabling it or pinning an item that would overflow fails visibly, and request construction never falls back to an empty or partial bundle. `AssistantRequestReceiptStore` then binds the exact frozen bundle plus submitted question, provider host, model, timestamp, and prior-message count to the resulting answer ID. It is session-only, prunes the oldest entry after 32 answers, and has no request-replay path.

Unlike ordinary chat, proposal review does not expose incremental provider text to the proposal parser. Stop cancels the request and leaves no partial proposal that can apply. Source, SQL, compile evidence, job incident evidence, spooled-output evidence, transfer metadata, system-health metadata, object-impact evidence, runbook contracts, authority-path evidence, and terminal strings remain untrusted data even when they resemble instructions or proposal delimiters. Prepared compile, incident, spooled-output, transfer, health, impact, runbook, and authority evidence is advice-only and carries no edit proposal contract. Transfer context contains schema, mappings, issue codes, counts, and fingerprints but no raw source cell values. Health context withholds target identity, qualified job names, receipt error text, credentials, partition identity, and certificate-store data. Impact context aliases object identities and withholds the host, target and related object names, owners, descriptions, source queries, receipt diagnostics, and fingerprints. Runbook context withholds blueprint, target, parameter, action, owner, reviewer, fingerprint, and timestamp values while retaining only the typed step/risk/evidence contract and open check codes. Authority context aliases or withholds the host, profile, object, owner, authorization-list, group, timestamp, diagnostic, and fingerprint identities while retaining path kinds, reported authority, source availability, and interpretation limits. If redaction changes the primary Source/SQL text, that request also becomes advice-only so an edit cannot replace undisclosed text with placeholders. The provider may otherwise omit a proposal entirely. If it includes one, duplicate envelopes, malformed JSON, oversized text, NUL bytes, changed contract fields, an invalid Unicode selection, a different document, or a changed local baseline disable Apply.

The optional patch stack is bounded to twelve proposals, 262,144 UTF-8 replacement bytes, and 16,384 explanation bytes. It deduplicates deterministic proposal fingerprints, preserves operator ordering and selection, and builds a preview only when every selected proposal matches one target, document, baseline, and current local draft. Ranges must be valid UTF-16 boundaries and non-overlapping; a whole-draft replacement must be selected alone. Preview assembly is inert and computes exact local deltas and affected line spans. Compile status, host dependencies or query plans, authority, and runtime behavior remain explicit evidence gaps. Apply rebuilds the preview immediately before one existing local editor update and removes queued entries only after the resulting buffer exactly matches; it cannot invoke a provider, save a host file, run SQL, stage a terminal command, compile, transfer data, refresh health evidence, collect impact or authority evidence, resolve a runbook, or press Enter.

## Continuity Casebook path

```text
Explicit local case creation, reviewed Context Shelf capture, Assist-answer record, or bounded reference-pack import
  → exact metadata/content validation + fixed collection and byte limits
  → credential-marker redaction for captured Context Shelf artifacts
  → deterministic content, provenance, reference, case, and snapshot fingerprints
  → atomic permission-restricted local JSON persistence (directory 0700, file 0600)
  → evidence relay + open questions + next action + stale boundary + receiver acknowledgement
  → immutable local handoff snapshot and optional reviewed JSON export
```

The Casebook has no ambient workspace reader. Context enters only from the currently reviewed shelf; Assist output enters only when the operator chooses the Casebook control on a completed, stopped, or interrupted response that still carries its request provenance. Stopped/interrupted answers cannot carry a completed-response risk classification. Reference packs are local bounded JSON documents rather than directory scans; repository locators reject traversal and only reviewed entries attach to a case. Reusing a reference requires choosing one exact entry, which pins an advice-only `reviewedReference` fragment and opens the existing Context Shelf preview without reading an API key or contacting a provider or host.

`ContinuityCasebookStore` validates the entire document before atomic writes and after reads, rejects symlinked parent or leaf paths, broadly readable custody paths, nonregular or oversized files, and normalizes timestamps to the millisecond representation used by the durable codec. Handoff snapshots embed value copies of the case plus readiness gaps and an independent fingerprint; later case edits cannot mutate the snapshot. The snapshot is continuity evidence, not an authenticated approval or claim of current host state.

## Provider readiness path

```text
Fixed, noncredential local paths
  → architecture and executable/library evidence
  → runtime prerequisite state
  → explicit connection identity + target + Keychain choice
  → typed, short-lived host capability receipt
```

The local probe remains deliberately separate from the connector. It checks a bounded list of system and conventional install locations, never searches shell history or environment variables, never loads project secrets, never installs software, and never contacts an IBM i host. System SSH/SFTP availability can therefore be ready while Db2 remains blocked until unixODBC, the IBM i Access ODBC driver, and a supported TLS library are all present. Only an explicit Connect action can exchange a password for an ephemeral capability receipt.

## SSH/SFTP trust path

```text
Validated target + user + authentication method
  → explicit ssh-keyscan request with fixed options and deadline
  → parse supported public host keys + compute SHA-256 fingerprints
  → operator compares evidence through an independent channel
  → exact app-managed known_hosts pin (0600)
  → strict BatchMode SSH authentication test
  → fixed `pwd`/`quit` SFTP subsystem probe
  → ephemeral provider-ready state
```

OpenSSH is executed directly with argument arrays; there is no intermediary shell. The plan ignores user SSH configuration, uses only the app-managed known-host file, requires strict checking, disables agent/X11/port forwarding and local commands, requests no TTY, caps elapsed time and combined output, and runs only a constant `true` command for the SSH test. The SFTP probe accepts no caller-provided batch text. A changed key for any presented pinned algorithm blocks the channel instead of replacing evidence.

The provider-ready state enables explicit IFS browse/read actions for the app session; it never starts browsing automatically. Typed batches permit only long-list, get, put, rename, and cleanup of an exact generated sibling path. Remote file content is held in a fresh `0700` temporary directory with `0600` files and removed after each operation. Writes re-check the expected revision immediately before requesting rename, never delete the target, and never retry an ambiguous rename. SFTP does not offer a portable compare-and-swap rename, so a concurrent change in the final check-to-rename interval cannot be excluded; the committed-byte receipt detects the resulting bytes but cannot restore another writer's version. If committed bytes cannot be re-downloaded and matched, the operator is told to inspect the target before any retry.

## Planned capability boundary

Each host-backed feature should implement a small typed interface:

```text
SessionProvider       SourceProvider        DatabaseProvider
JobProvider           SpoolProvider         SystemHealthProvider
ObjectImpactProvider  AuthorityProvider     FutureRunbookConnector EvidenceStore
```

Providers may use TN5250, SSH/SFTP, Db2, HTTP, or supported IBM i Services, but the views consume domain models. This avoids coupling product workflows to one transport and makes mock-host testing possible.

## TN5250 path

```text
Network.framework TLS/TCP
  → Telnet byte-state machine
  → TERMINAL-TYPE / BINARY / EOR / NEW-ENVIRON readiness
  → RFC 4777 startup response and device-name retry handling
  → EOR-delimited record bytes
  → validated 10-byte TN5250 record header
  → data-stream commands and orders
  → terminal screen/field model
  → SwiftUI Canvas renderer
```

NEW-ENVIRON request filtering and RFC 1572 marker escaping are implemented. Explicit DEVNAME collision requests advance through configured or generated device names instead of repeating the same rejected value. CODEPAGE and CHARSET creation attributes are separate from the local display CCSID.

Write-to-Display resets the display address and processes its first control byte before screen orders and its second control byte afterward. The screen model preserves host keyboard inhibition, strict addresses, persistent system Home from Insert Cursor, transient Move Cursor, cursor blink, repeated alarm events, message-waiting state, MDT reset/null operations, non-wrapping Repeat-to-Address, controller-supplied field-ending attributes, and the complete documented color-display attribute table. The display model keeps screen attributes separate from persistent extended-primary and extended-color change planes. Write Extended Attribute changes presentation at the current address without consuming it; null values remove a marker so the prior value continues, normal values return control to screen attributes, and extended changes can repaint existing content. Erase to Address validates its inclusive range and type list before clearing only the requested display, primary, or color layers, then advances to one cell after the target without wrapping. RFC 1205 corrects Insert Cursor to `0x13`; order `0x03` remains the distinct Erase-to-Address order.

Start-of-Header decoding clears the format table, selects the one-based read-resequencing start entry, and converts IBM's PF24-through-PF1 exclusion switches into a local inclusion mask. Masked PF AIDs still return cursor and AID state but carry no field data or field validation. Start-of-Field decoding preserves all eight FFW input types plus duplication, MDT, auto-enter, field-exit-required, monocase, mandatory-entry, adjustment, `X'80nn'` read resequencing, `X'84xx'` transparent-input state, and exact `X'8501'` Forward Edge Trigger state. Redefining a field preserves its original length and ignores replacement FCWs. Keyboard, insert-mode, paste, and command staging share one character-admission and monocase contract, while the operator information area identifies the active field type, transparency, FET AID, pending-exit state, and current host read mode. Interactive typing advances ordinary full fields or produces an explicit auto-enter/FET outcome; FET takes precedence over the FFW Auto Enter flag and maps to the distinct `X'50'` data-carrying AID. Validation treats FET as Enter-like for mandatory-entry/fill and active right-adjust checks. Field Exit/Plus/Minus performs right blank/zero adjustment and signed-numeric handling, while Dup places the workstation `X'1C'` value behind its display glyph.

Each `SessionProfile` also owns exactly 24 validated `TerminalFunctionKeyBinding` values. A binding keeps the physical Mac slot, host F-key number, operator label, and dock-pin state separate. Existing profiles and undecodable persisted layouts migrate to an identity map; a decoded but structurally invalid layout remains invalid for connection while presentation falls back to identity. Both the hardware event path and pinned dock resolve the current profile binding before producing the existing TN5250 AID, so host PF data-inclusion masks and field validation continue to apply to the routed host function.

The screen model retains null versus EBCDIC-blank state and raw bytes from Transparent Data. Read Input checks the global master MDT, then concatenates every field selected by normal or host-resequenced order; Read MDT emits SBA-delimited modified fields and standard null formatting; Read MDT Alternate preserves leading and embedded nulls; transparent MDT fields carry the required inbound Transparent Data order and length without formatting. Resequencing numbers only FFW-backed entries in screen order, includes protected bypass entries while following the chain, excludes output-only fields, assumes the next sequential entry when `X'80nn'` is absent, and requires `X'80FF'` termination. Undefined starts/targets, over-128 tables, missing terminators, and loops fail before any payload can be sent. The signed-numeric-plus-transparent combination likewise fails closed because IBM defines its result as unpredictable. Device Query accepts only the complete command and returns the selected 3179-2 or 3477-FC identity with Row 1/Column 1, Read MDT Alternate, Move Cursor, screen size, and color—without claiming PA keys, Cursor Select, DBCS, graphics, light pen, or magnetic-stripe support. Other optional FCWs such as check digit, self-check, and cursor progression remain unimplemented. SwiftUI presents host-controlled cursor/text blink, high intensity, extended colors, and column separators; local PNG, PDF, and print paths use the same effective attributes, and AppKit plays each alarm event once. Unsupported extended-text and ideographic attribute types stop the current WTD rather than being rendered as a plausible but incorrect SBCS result.

Unrecognized data-stream elements currently produce a protocol notice or are safely skipped. Production compatibility still requires structured-field, extended-text/ideographic-attribute, and complete field-format layers rather than guessing.

Mac key events enter through a small AppKit first-responder bridge so system focus traversal cannot steal host keys such as Shift-Tab. The bridge maps common 5250 operations into typed screen-model edits or AID records; it does not mutate protocol buffers directly. Keypad Enter and Shift-Return provide Field Exit, keypad Plus/Minus provide their signed exit variants, and Shift-Insert provides Dup when enabled by the host field. Paste is always reviewed, respects protected and non-display fields, validates the active CCSID and decoded host field type, applies monocase consistently, and reports skipped input; bulk insertion never silently creates an AID. If paste ends in a FET field, the OIA retains the FET contract and the notice explicitly says the field is staged until Field Exit.

Mouse drag creates a local rectangular terminal selection, which is especially useful for fixed-column job, spool, and object lists. Copying preserves the rectangle's columns, trims only trailing row padding, and replaces non-display cells with spaces. It does not send input or change the host cursor.

Screen capture, PDF export, and printing use local presentation snapshots. Non-display cells are always blanked, a PDF/print footer records that no host input or AI request was generated, and the native print action never sends the 5250 Print AID. These artifacts are separate from future TN5250E printer-device sessions.

The codec layer can transcode Arabic/Hebrew/Urdu SBCS values, but those profiles are not offered as terminal-ready. IBM's bidi contract also requires language layers, field/screen direction, cursor reversal, close behavior, and OIA state. Mixed-byte CCSIDs additionally require balanced shift-out/shift-in and dead-position semantics. Until those layers and fixtures exist, bidi and DBCS sessions fail validation instead of rendering plausible but incorrect text.

Unexpected transport failure can create a fresh client generation after bounded 1/2/4-second delays. Old client events are ignored, the last screen becomes read-only, and local edits—including non-display password fields—are never replayed. Manual disconnect cancels pending recovery immediately.

## Concurrent terminal deck

```text
Saved SessionProfile
  → one or more TerminalSessionState values
  → one TerminalSessionTransportRuntime per open session
  → generation-bound TN5250 events and recovery task
  → independent screen, history, input mode, startup receipt, and notice
  → selected-session projection into the terminal canvas and OIA
```

The session switcher is not a second profile list. A profile is reusable connection configuration; every open tab is a distinct terminal identity with its own client and recovery budget. Inactive tabs continue to accept only events tagged with their exact session ID and current transport generation. Switching changes the selected projection without disconnecting anything; ⌘T opens another terminal for the selected profile and ⌘[ / ⌘] wrap through the deck. Host alarm requests advance one app-level signal when their session event arrives, so a background alarm is neither lost nor replayed later merely because the operator selected its tab. Manual disconnect preserves that tab's last screen, closing removes only that runtime, and profile deletion explicitly closes every associated runtime before removing the saved configuration. Connection Studio's endpoint test uses a separate short-lived client so it cannot replace or interrupt an active terminal.

## Session Flight Recorder

```text
Operator arms one TerminalSessionState
  → each new host screen becomes a TerminalEvidenceFrame candidate
  → clear every input-field position, non-display cell, and sensitive-labeled row
  → preserve only protected presentation cells and workstation attributes
  → compute the exact redacted-screen SHA-256 fingerprint
  → collapse an identical newest frame
  → prune to the selected 7/30/90-day and 250-frame bounds
  → validate and atomically persist in the local 0700/0600 archive
```

Arming is ephemeral and session-specific; it never survives an app restart. The in-memory 100-screen session history remains separate and cannot silently become durable history. A manual bookmark passes through the identical redaction and validation path. Durable frames are display-only reconstructions with no fields, editable buffer, or visible cursor, so evidence replay cannot restore operator input or become a transport payload.

Reviewed macros are typed routes of exact-screen matches, read-only command staging, field actions, one whitelisted AID, and evidence bookmarks. Saving or editing creates a draft; local review freezes the exact name, profile target, ordered steps, and action values into a content fingerprint. Runtime staging reuses the conservative IBM command classifier and recognized visible-command-field gate. Each operator click evaluates and records only the current step, then pauses. No timer, background worker, reconnect callback, or host-screen event advances a macro. Passed and blocked steps create tamper-evident local receipts; local review attestations are not authenticated approvals.

## AI path

```text
Operator question
  + optional visible-screen snapshot
  → redact non-display fields and sensitive lines
  → freeze question, destination, model, prior-message count, and exact redacted context receipt
  → HTTPS request with stream=true to operator-configured provider
  → bounded SSE lines/events and choices[0] text deltas
  → generation-isolated provisional response with visible Stop
  → [DONE] or clean finish reason
  → complete answer and command-like-line classification
  → answer-bound read-only receipt action
  → operator reviews and chooses what to do
```

Each SSE line and event is capped at 128 KiB and accumulated assistant output at 2 MiB. Malformed, oversized, or truncated events fail closed. Stop cancels the active task immediately; received text is retained as visibly stopped output with no completed-response risk classification, while stale callbacks are ignored by request generation. Complete, stopped, and interrupted answers retain the active frozen receipt; later shelf previews or sends cannot mutate it. The local ledger retains only the 32 newest answer receipts, shows a disabled expired/session-limit state on older answer rows, and clears with New Chat. Stopped/interrupted user-answer pairs are excluded from later provider conversation continuity. There is deliberately no arrow from AI output or its receipt inspector to a provider replay or host executor.

## Host command staging

The first workbench-to-terminal bridge is intentionally narrower than a command executor:

```text
Curated diagnostic command
  → IBM command risk classifier must return read-only
  → active, unlocked 5250 session
  → recognized visible command-entry field
  → CCSID and field-capacity validation
  → replace the local field contents
  → operator reviews and presses Enter
```

Non-display fields, unknown/mutating/destructive commands, unrecognized screens, and overflowing commands fail closed. Staging emits no AID record, so choosing a deck item cannot execute it.

The native command palette is an orchestration surface rather than a second navigation tree. Its results are assembled from the current workbench tools, saved session profiles, screen/history actions, the guarded diagnostic library, IBM i Services query templates, and opt-in Assist settings. Query results navigate to the Db2 studio and populate a local draft; they never execute. The search field uses an AppKit first-responder bridge so Up/Down, Return, and Escape remain deterministic on macOS.

## Verification strategy

- Byte-level unit tests for codecs, fragmented Telnet input, IAC escaping, record headers, orders, AIDs, malformed data, protected-field editing, guarded paste, redacted rectangular selection, and profile recovery policy.
- Display fixtures for 24×80 and exact 27×132 presentation spaces, field attributes, bidi-codec/terminal-readiness separation, and explicit mixed-byte rejection. DBCS and structured-field golden packets remain required.
- Fake providers for workflow tests and failure-state visual snapshots; source fixtures cover identity, delta, and every write-preflight gate, source-member fixtures cover object-name validation, fixed-precision metadata, canonical revisions, date preservation, gap allocation, CCSID/width loss prevention, journaling, and safe SQL planning, IFS fixtures cover path traversal, batch quoting, listing parsing, UTF-8/line-ending loss prevention, revision hashing, staged paths, and strict command plans, SQL fixtures cover statement classification, catalog bounds, and offline/production gates, incident fixtures cover qualified-job validation, generated-query authorization, column-keyed decoding, exact-object correlation, message integrity, and caps, and secure-channel fixtures cover injection rejection, host-key parsing, command hardening, fixed SFTP input, pin permissions, and changed-key refusal.
- Spooled-output fixtures cover exact identity validation, independently bounded inventory/queue/content requests, column-keyed decoding, writer and authority states, whitespace-preserving text records, duplicate/control/cap refusal, exact-identity comparison limits, and advice-only Assist context.
- Data-transfer fixtures cover quoted and multiline CSV records, structure and resource caps, validated read-only schema SQL, column-keyed metadata decoding, type/length/precision/date/CCSID blockers, leading-zero preservation, and metadata-only advice context.
- Object-impact fixtures cover classic identity and type gates, six independently bounded read-only requests, column-keyed decoding, evidence-class separation, duplicate/control/cap refusal, explicit source gaps, non-safe assessment wording, artifacts, and privacy-reduced advice context.
- Runbook fixtures cover bounded schema import/export, secret-name refusal, exact typed substitution, malformed and unknown placeholders, free-text interpolation refusal, SQL/CL action gates, mutation budgets, deterministic fingerprints, plan-bound attestations, permanent non-executability, exact local artifacts, and identity-withheld advice context.
- Authority fixtures cover exact profile/object gates, five bounded read-only plans, column-keyed fail-closed decoding, per-bit grant preservation, primary and supplemental group paths, static/observed/adopted separation, explicit source gaps, permanent review posture, local no-write simulation, exact artifacts, and identity-withheld advice context.
- Assist fixtures cover Unicode selection boundaries, deterministic fingerprints, byte/item caps, same-kind shelf replacement, removal, full-shelf automatic-screen overflow refusal, credential redaction, delimiter escaping, single-envelope parsing, selection replacement, ambiguous-envelope rejection, stale-baseline refusal, fragmented CRLF/LF SSE, comments and multiline data, refusal text, malformed/truncated/oversized streams, `[DONE]`, request headers/body, incremental delivery, API-key separation, distinct answer-bound receipts, oldest-entry pruning, stopped-answer inspection, New Chat clearing, and native panel/sheet rendering.
- Compatibility lab matrix across IBM i releases, TLS policies, terminal models, CCSIDs, and device allocation behavior.
- Opt-in live probes that load host locations from local operator artifacts without committing or logging credentials; see [compatibility evidence](COMPATIBILITY.md).
- Signed/notarized release checks and an arm64 binary assertion.
