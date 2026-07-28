# Security model

## Defaults

- TLS on port 992 is the default session transport.
- macOS validates the server certificate chain; the current client does not implement a trust-all switch.
- Plain Telnet is available only as an explicit profile choice and is labelled as exposing terminal traffic.
- IBM i passwords are entered into host-provided non-display fields and are not persisted by iTelAS.
- AI assistance is disabled until the operator opts in.

For operator-authorized development testing only, this workspace may contain an
ignored `devenv.secrets.json` file with mode `0600`. It is a local test artifact,
not an iTelAS session-profile feature. Routine tests, screen exports, diagnostics,
and AI context must not read it; authenticated probes must be explicitly requested.

## Source drafts

- Local source scratch content is not stored in `UserDefaults` and is never written into a session profile.
- The current scratch editor uses atomic UTF-8 autosave under the user's iTelAS Application Support directory. Its workspace directory is enforced to mode `0700` and the source file to mode `0600`.
- Local source is not attached to AI requests automatically. “Prepare Assist Review” opens a dossier where the operator explicitly chooses the current selection or whole draft and reviews the exact redacted text, byte count, document identity, baseline hash, provider host, and model before one send.
- Source completion is local and deterministic. It performs no host lookup and reads no API key. Each insertion is bound to the exact source fingerprint and UTF-16 replacement range, is rejected after any intervening edit, and enters through the native text system so it remains undoable. The separate Assist completion only prepares the existing review dossier; it never inserts a model response or sends context automatically.
- Source workspace indexing starts only after an explicit macOS folder choice. File and symbolic-link roots are rejected; hidden/package descendants and every symbolic-link entry are skipped. Only supported, NUL-free UTF-8 source is held in memory, with 5,000-file, 2 MiB-per-file, 128 MiB-total, path, symbol, reference, search-result, and rename-occurrence limits. The base scan performs no provider call, host lookup, Keychain read, or AI request and persists no index cache.
- A same-root index refresh rereads every supported file's exact bytes; modification time and size never authorize analysis reuse. Reuse requires an exact path, format, and UTF-8 byte match, every dependency edge is rebuilt, and the delta receipt is bound to both before and current index fingerprints. Source, reused analysis, and the report remain memory-only and have no provider, host, Keychain, credential-file, or Assist effect.
- Workspace drift monitoring begins only for the operator-selected root. Native FSEvents carries paths and flags; its bounded fallback enumerates only path and file metadata and never reads source content. Unsafe, hidden, unsupported, traversal, symlink, and out-of-root paths are rejected or ignored. Signals are capped, coalesced, session-only, and advisory; dropped/root/overflow/pause gaps require full verification. Any pending signal revokes index-bound completion, compiler mapping/navigation, rename, and snapshot navigation. Exact refresh clears only events at or before its captured boundary, so a concurrent later change cannot inherit the completed scan. Monitoring performs no provider, host, Keychain, credential-file, or Assist action and persists no path ledger.
- Workspace search stays local and runs in a cancellable off-main task. Search reports bind the normalized query to the exact index fingerprint, disclose incomplete per-document, result, or candidate coverage, and are discarded when a newer query or index generation wins. Cancellation and stale-generation rejection have no provider, host, Keychain, credential-file, or Assist effect.
- The Include Chain Navigator reads only `/COPY` and `/INCLUDE` dependency edges and content fingerprints already present in the current in-memory index. Traversal is capped at 64 documents, 512 directives, and 24 levels by default; ambiguity, missing host content, unresolved targets, cycles, and every cap become visible boundaries. The receipt binds the exact index, root, resolved document fingerprints, directive ranges, routes, candidates, limits, and boundaries. Any pending drift or index/root change revokes current use. “Use Exact Closure” changes only the draft dependency selection and cannot approve completion, read source, persist content, contact a provider or host, access Keychain or the ignored development credential file, or prepare/send Assist context.
- Host-backed `/COPY` and `/INCLUDE` content has a separate exact-read gate. Review binds the current index fingerprint, one source edge and range, one typed source-member or absolute non-root IFS target, one provider identity, and the remaining per-file/workspace byte budget. Unqualified member references require an explicit library. Checkbox attestation precedes one exact provider read; returned identity, revision, CCSID, regular-file status, and bounds must match before a provenance-marked in-memory overlay is installed. There is no fallback library/path search, directory crawl beyond the exact IFS parent metadata check, persistence, host write, Keychain read, or Assist send. Refresh, overlay removal, provider disconnect, or target change invalidates the applicable evidence.
- Cross-file completion accepts symbols only from an exact operator-reviewed path/content/index receipt; any workspace change, including host-overlay installation or removal, revokes that receipt. Opening a result creates a read-only, non-autosaving snapshot and marks it stale when its index receipt changes. Rename excludes every host-backed document plus recognized local comments and strings, fails closed on limited highlight evidence, and freezes exact token ranges plus content/modification baselines. Applying requires the original operator-selected root, a separate immutable review, and explicit checkbox attestation. The complete bounded batch validates before writing; every parent and leaf is rechecked as a regular non-symbolic path; each file is replaced atomically with permissions preserved and committed bytes verified; an error triggers reverse rollback of earlier replacements; and success requires a fresh index. Rollback never overwrites a target changed by another writer and names unresolved paths. This is rollback-protected, not a crash-atomic multi-file transaction: no persistent recovery journal exists, and power loss or an external edit in the final check-to-replace interval can require inspection. The rename path has no host, provider, Keychain, or AI effect.
- IFS browse/read/write is available only after the operator completes the pinned SSH + SFTP test for the current app session. It never reads the ignored development credential file or starts a host operation automatically.
- IFS paths must be absolute and traversal-free. The provider generates a small typed SFTP command set and centrally quotes every remote and local path; caller-provided batch text, remote shell commands, links, and special-file writes are not accepted.
- Remote text is capped at 2 MiB and currently requires UTF-8/CCSID 1208 with no BOM, NUL bytes, or mixed line endings. Unsupported data is blocked to avoid lossy rewriting.
- Open remote text and edits remain session-only; unlike the explicit local scratch file, remote IFS content is not silently persisted as a draft cache.
- Every write is bound to the opened SHA-256 revision and a reviewed payload hash. The provider re-downloads the target before upload, uploads to a generated same-directory sibling, re-downloads the staged bytes, re-checks the target immediately before rename, requests rename, then re-downloads the target. It never deletes the target and never automatically retries an uncertain rename result. Because portable SFTP rename is not compare-and-swap, the final check-to-rename interval remains a documented concurrency boundary.
- IFS transfer files live in a fresh temporary directory with mode `0700`; downloaded and generated files are changed to `0600` and removed after the operation. File content is not included in process diagnostics.
- Future provider credentials must use Keychain or an equivalent OS credential facility; they must never be embedded in `SourceIdentity`, source documents, logs, or write plans.

## Source-member records

- Source-member identity accepts only classic one-to-ten-character IBM system names and normalizes them to uppercase. Catalog values use bindings; the only generated SQL identifiers are validated library/file/member names and a deterministic `QTEMP` alias.
- Reads are bounded and ordered by relative record number. The revision digest covers the exact identity, record length, CCSID, sequence, source date, and source text for every record, so metadata-only changes cannot pass as unchanged source.
- Editing supports only the standard `SRCSEQ`, `SRCDAT`, and `SRCDTA` layout. It rejects invalid sequence order, implicit renumbering, field-width overflow, unsupported CCSIDs, and text that cannot round-trip through the declared EBCDIC codec.
- A write plan requires read/write/update/delete authority, no triggers, journal before-and-after images, and an exact opening revision. The transport contract must execute the replacement as a serializable transaction and verify the committed revision; uncertain or mismatched results stop without automatic replay.
- The native ODBC actor implements only generated source metadata/member operations behind distinct source-read and reviewed-source-write connection capabilities. The UI requires the operator to select one capability before connecting, blocks source write for production profiles, and requires a separate immutable write review before commit. The ignored development credential file is never a password source.

## AI credentials and context

- Provider API keys are stored as device-only macOS Keychain items.
- Keys are not written to `UserDefaults`, project files, logs, prompt text, or exported runbooks.
- Provider endpoints must use HTTPS, except loopback development endpoints.
- Ordinary chat requests use a bounded Server-Sent Events parser: each line and event is limited to 128 KiB, accumulated assistant text is limited to 2 MiB, only choice index zero text/refusal deltas are accepted, and malformed, oversized, or truncated streams fail closed.
- A chat response requires `[DONE]` or a clean finish reason. Stop cancels the active task, closes the response path, ignores stale generation callbacks, and preserves any received text only as visibly stopped output without completed-response command classification. Stopped or interrupted user/assistant pairs are not sent as conversation history in later requests.
- The default context mode sends no automatic terminal context.
- Optional visible-screen context removes non-display fields and lines likely to contain passwords, tokens, API keys, or secrets.
- Source, SQL, compile, incident, spool, transfer, health, dependency, runbook, authority, and Casebook-reviewed reference context is explicitly selected and may be pinned into the local Context Shelf. The shelf accepts at most eight distinct evidence kinds, 32 KiB per item, and 48,000 UTF-8 bytes per request bundle. Editor context is built from a Unicode-boundary-checked selection or exact opened draft snapshot; evidence context is built only from the explicitly selected local artifact or reviewed reference entry.
- Repinning one evidence kind transactionally replaces its stale shelf item instead of attaching an ambiguous duplicate. Removing or clearing items is local. Pinning, previewing, and clearing cannot read an API key, contact a provider, save a file, query or mutate a host, or execute a command.
- Every provider request freezes a new immutable bundle and receipt from the visible shelf. The completed, stopped, or interrupted answer is bound to that exact receipt rather than the later mutable shelf. The 32 newest answer receipts remain inspectable in the current chat; older receipts roll off and New Chat clears the ledger. Optional automatic screen context counts against the same eight-item and 48,000-byte limits. If it would overflow, enabling it, pinning the conflicting item, previewing, or sending fails visibly; the implementation never drops the shelf and sends a smaller or empty context silently.
- An optional 5250 context item is redacted and frozen when selected; it does not silently follow later host-screen changes.
- The exact bundle is represented as delimiter-safe JSON, fingerprinted, and kept with the submitted question, provider host, model, timestamp, and prior-message count in a local answer receipt. The receipt is evidence rather than a raw HTTP-body archive: it excludes the API key, authorization header, system policy, and prior conversation text. Its inspector is read-only and cannot resend the request. Host, source, SQL, and screen text is always untrusted reference data, not instructions that may override the assistant safety policy.
- An assistant edit must use one versioned proposal envelope whose target, SHA-256 baseline, and UTF-16 selection exactly match the reviewed request contract. Duplicate, malformed, oversized, binary, stale-baseline, or contract-changing proposals fail closed.
- Proposal review remains whole-response rather than incremental. Cancelling review produces no partial proposal or Apply surface.
- If redaction changes the selected Source or SQL text, the request becomes advice-only. iTelAS does not issue a proposal contract that could replace undisclosed local text with redaction placeholders.
- A validated proposal remains inert until the operator applies it. Apply can only replace a range in the local Source or SQL editor buffer. Host save, upload, compile, query execution, and command execution remain separate explicit actions.
- The optional Proposal Patch Stack remains local and inert. It accepts at most twelve immutable proposals, 262,144 UTF-8 replacement bytes, and 16,384 explanation bytes; it reads no API key and cannot contact a provider or host.
- Stack preview fails closed for duplicate fingerprints, mixed targets or documents, stale or mixed baselines, invalid UTF-16 boundaries, overlapping ranges, and a whole-draft replacement combined with another patch. Apply rebuilds the exact preview and performs one local-buffer update; entries remain queued if that update cannot be verified.
- The Local Impact Lens states only exact local byte, UTF-16, line, range, and affected-line facts. Compile status, host dependencies or query plans, authority, and runtime behavior remain explicit evidence gaps; no save, compile, query, host collection, or execution is implied.
- Compile, job-incident, spooled-output, transfer, health, dependency, runbook, and authority evidence never receives an edit proposal contract. Pinning one opens the exact Context Shelf and fills a draft question; the operator must still send from Assist, and the response remains advice-only.

Redaction is defense in depth, not a guarantee that arbitrary business data is non-sensitive. Organization policy should still add host/library/object allowlists, data classification, retention controls, and provider allowlists where required.

## Continuity Casebook

- The Casebook persists only after an explicit create, Context Shelf capture, Assist-answer record, reviewed-reference attachment, workflow edit, or snapshot action. It has no ambient workspace, provider, Keychain, host, or credential access.
- The versioned local JSON store is written atomically under the iTelAS Application Support directory. The directory is enforced to mode `0700`, the file to `0600`, and reads reject symlinked parent or leaf paths, broadly readable custody paths, nonregular files, invalid fingerprints, unsupported versions, oversized documents, duplicate identities, and broken bounds.
- Cases retain exact validated target/environment metadata, bounded artifacts, answer completion state and request provenance, reviewed references, open questions, next action, stale-evidence boundary, and receiver acknowledgement. Millisecond timestamp normalization makes the durable record match its in-memory value.
- Reference packs are explicit local JSON imports capped at 256 KiB and 24 entries. Repository locators reject absolute paths, traversal, empty components, and backslashes. Nothing scans a repository or runbook directory. After review, only one operator-chosen entry may be pinned into the advice-only Context Shelf, where ordinary redaction and request caps apply.
- Stopped or interrupted Assist output can be retained only with its incomplete state and no completed-response risk classification. Every recorded answer retains the exact question, provider host, model, context fingerprint/count, answer hash, and deterministic ledger fingerprint.
- Answer receipts are session-only. Recording an answer in the Casebook persists the request provenance summary, not the full answer receipt; exact redacted context becomes durable only through the separate explicit Context Shelf capture action.
- Handoff snapshots embed immutable case values plus readiness gaps and their own fingerprint. They are local continuity evidence, not authenticated approval, current host state, or proof that open questions are resolved. Exported JSON can contain sensitive operational, source, or business data and remains under operator custody.

## Compile evidence

- Compile recipes accept only bounded visible names, existing IBM i system-object identifiers, two fixed RPG program toolchains, fixed debug/commit/preprocessor/environment/replace options, and `*CURRENT`, `*PRV`, or validated exact target releases. Free-form CL fragments are not accepted.
- Every generated recipe includes `OPTION(*EVENTF)` and receives deterministic command and contract fingerprints. A recipe-to-run comparison labels exact, changed, relative, and unavailable evidence without claiming that the run came from the recipe.
- The recipe library is capped at 64 entries and 256 KiB. Its Application Support directory is enforced to mode `0700`, its atomic JSON file to `0600`, and reads reject broad permissions, symlinked parents or leaves, nonregular files, unsupported schemas, duplicate identities/names, and invalid bounds.
- Recipes store identifiers and compiler choices, not passwords, API keys, source bodies, host output, execution authority, or provider state. Editing, saving, comparing, and copying a preview cannot contact or mutate a host.
- Local EVFEVENT import is UTF-8-only and capped at 4 MiB, 50,000 records, 4 KiB per record, 4,096 path characters, and 2,048 message characters.
- Binary/NUL data, invalid UTF-8, bare carriage returns, malformed recognized records, invalid numeric fields, and orphaned `FILEIDCONT` records fail closed.
- Processor-scoped file identifiers are reconstructed exactly. Diagnostics whose file identifier is unresolved remain explicitly unlocated; iTelAS does not attach them to the current editor by filename guess.
- `EXPANSION` records are counted and surfaced as a limitation. Generated-to-original precompiler line remapping is not claimed until a complete, fixture-backed implementation exists.
- Compiler-to-index mapping is bound to the exact index, retained run, EVFEVENT receipt, target-release context, mapped document fingerprints, reviewer, and review time. Duplicate document targets and stale receipts fail closed.
- `TGTRLS(*CURRENT)` and `TGTRLS(*PRV)` become exact release evidence only when an observed host release was retained; otherwise they remain relative. This context is not presented as a language-compatibility verdict.
- Diagnostic navigation requires a retained source fingerprint matching the indexed document, positive in-bounds line and column coordinates, and no `EXPANSION` gap. Changed, unrecorded, expansion-affected, and out-of-bounds evidence remains visible but non-navigable.
- Local attachment requires checkbox attestation and performs no compile, provider, host, Keychain, credential, or Assist operation.
- The “first actionable” diagnostic is a deterministic triage inference, not a causal fact. The selection rule and confidence remain visible beside the result.
- Compile lineage accepts at most 32 validated retained runs and 20,000 diagnostics, requires one exact target identity, and refuses duplicate fingerprints, same-run selections, malformed identities, cross-target scope, and over-limit input. Its SHA-256 receipt binds every scoped run plus the chosen pair. Comparison and advice-only Assist preparation expose no source body, API key, provider, credential, or host action and do not prove causality, complete job logs, replacement authority, or runtime behavior.
- The current workspace imports local evidence and presents a bundled replay. It does not submit a compile, read a host event file, fetch a complete job log, replace an object, or retry any remote action.

## Db2 drafts and execution

- Local SQL drafts use the same permission-restricted, atomic text store as source drafts; they are not placed in profiles or `UserDefaults`.
- Choosing an IBM i Services template from the catalog or `⌘K` only replaces the local draft. It never opens a connection or executes SQL.
- The execution gate requires one syntactically read-only statement, an explicit row cap and timeout, a named non-production target, and a current read-only capability receipt. On this development Mac, Run remains blocked because unixODBC and the IBM driver are absent. Explain provides a bounded local static syntax review only: it does not execute SQL, contact a provider, or claim optimizer estimates, access paths, indexes, or a provider receipt.
- Non-secret target profiles are stored in `UserDefaults` without a password field. Passwords exist only in short-lived memory unless the operator explicitly chooses device-only macOS Keychain storage; removing or changing a target deletes the corresponding item.
- DSN-less connection attributes pin the exact IBM driver name, TLS, read-only connection type, commitment behavior, Unicode SQL, UTF-8 client CCSID, disabled tracing and procedure calls, and bounded sign-on/connection timeouts. The transport dynamically loads only fixed unixODBC library paths and returns no output connection string.
- Execution uses prepared ODBC statements, a driver query timeout, a maximum-row attribute, bounded cell/result memory, typed values, and sanitized diagnostics. Receipts omit user IDs, passwords, SQL text, connection strings, and result data.
- “Prepare Assist Review” uses the same one-send dossier and local-only proposal contract as Source. It never includes query results, connection strings, credentials, or other workspace text by implication.

Typed Export Studio is a local transformation of one retained typed result; it never re-runs a statement or contacts the provider. The contract caps results at 256 columns, 10,000 rows, 1 MiB per cell, 1 MiB query text, and 32 MiB per artifact; it rejects missing provenance, duplicate columns, width mismatch, invalid decimals, controls/NUL, unsafe paths, symlink destinations, and write-verification failures. CSV uses reversible `\\N`, formula defenses, and apostrophe-prefixed exact numeric text; temporal values are ISO 8601 UTC and binary values are Base64. Package directories are `0700`, files `0600`, and SHA-256 receipts cover query, result, schema, plan, and emitted bytes. Export Assist preparation is schema/receipt-only and excludes query text, provider/target identities, and cell values; it performs no API-key read or provider request.

The analyzer is a usability and defense-in-depth control, not a semantic SQL firewall. A syntactically read-only query can invoke a user-defined routine with external actions or consume excessive resources. Deployments must still use a least-privilege IBM i profile and organization policy for routines. Driver timeout is authoritative; true asynchronous `SQLCancel` is not yet exposed. Statement text and returned business data are not logged by default.

## Job incident evidence

- Collection is never automatic. It requires an explicit refresh, a current driver-enforced read-only Db2 receipt, and a non-production profile.
- `JOB_INFO`, `OBJECT_LOCK_INFO`, `JOBLOG_INFO`, and QSYSOPR `MESSAGE_QUEUE_INFO` requests are single read-only statements with fixed maximums of 250, 500, 500, and 100 rows and a 30-second timeout.
- Qualified job names require six ASCII digits plus two classic IBM system names. Object and queue identities use validated classic names; no operator-supplied text is interpolated into SQL.
- `JOB_INFO` is the required inventory. Lock, job-log, and operator-message queries fail independently into sanitized, 300-character evidence gaps so partial authority cannot be mistaken for an empty system.
- Decoding resolves unique column names, rejects ambiguous or malformed rows, caps message text, refuses NUL and control characters, and preserves first- and second-level message text without silently trimming it.
- Holder correlation requires the exact library, object, member, and type identity. It is labeled as a candidate relationship, never scheduler causality. Lock states are sampled and are not assigned invented timestamps.
- The workspace has no host-changing controls. It cannot reply to inquiries, hold, release, end, or reprioritize a job or queue.
- Prepared Assist context includes the exact selected job, visible locks and candidates, messages, receipts, gaps, and non-causal review boundary. It remains local until the operator reviews and sends it.

## Spooled output evidence

- Collection is never automatic and is blocked for production profiles. Inventory requires an explicit refresh and a current driver-enforced read-only Db2 receipt.
- Inventory uses bounded `QSYS2.SPOOLED_FILE_INFO` and `QSYS2.OUTPUT_QUEUE_INFO` statements. It does not open file content.
- Content requires a second explicit action bound to one validated job/file/number/system identity. The bounded `SYSTOOLS.SPOOLED_FILE_DATA` request may be audited because IBM documents that it internally uses a spool-copy operation.
- Decoding resolves unique column names, rejects malformed identities, statuses, priorities, duplicate ordinals, NUL/control characters, oversized records, and over-cap results, and preserves record spacing.
- Preview and comparison remain device-memory evidence. Comparison keeps both exact identities and does not claim lineage, page layout, fonts, overlays, graphics, AFP, or IPDS fidelity.
- Local UTF-8 copy/export includes the exact identity, target, capture time, completeness, digest, and fidelity warning. Exported spool data is potentially sensitive and is never written automatically.
- The workspace has no host-changing controls. It cannot hold, release, move, copy on host, start or stop a writer, print, send, or delete a spooled file.

## Data transfer integrity

- CSV import is local and operator initiated. Input must be bounded UTF-8 text and pass byte, row, column, cell, header, quote, structure, and control-character checks before it becomes a source profile.
- Source cells remain exact strings. Type inference is evidence only; leading-zero values are never silently coerced, and blank-to-NULL behavior is never assumed.
- Live target discovery requires an explicit refresh, a connected driver-enforced read-only Db2 receipt, and a non-production profile. It uses one fixed, bounded `QSYS2.SYSCOLUMNS2` statement after classic library/table identity validation.
- The dry run blocks ambiguous non-ISO dates, integer range failure, decimal precision or scale overflow, truncation, non-updatable/generated/hidden/field-procedure targets, missing required targets, and lossy target-CCSID conversion.
- Local validation export contains source identity, counts, fingerprints, target metadata, mappings, issues, and limitations but deliberately omits source cell values.
- Transfer Assist context is metadata-only, advice-only, and explicitly reviewed. It cannot carry an edit proposal or trigger a provider, upload, statement, procedure, or host mutation.
- This milestone exposes no host-write capability. XLSX/ODS ingestion, IFS staging, resumable batches, and write authorization require separate threat modeling and compatibility evidence.
- Prepared Assist context includes only bounded selected metadata, at most 60 reviewed text records, local comparison, receipts, and explicit limitations. It remains local until the operator reviews and sends it.

## System health evidence

- Collection is never automatic. It requires an explicit refresh, a connected driver-enforced read-only Db2 receipt, and a non-production profile.
- Five generated, bounded, single-statement requests collect system status, a one-second CPU activity sample, ASP capacity, system-limit high-water occurrences, and installed group PTF status. Each source fails independently and produces a sanitized receipt.
- Decoding resolves unique column names and rejects duplicate or missing columns, malformed rows, unsafe text, impossible capacity relationships, invalid dates/numbers, singleton ambiguity, and over-cap results.
- The displayed health index is a transparent local heuristic. It is never described as an IBM score, diagnosis, trend, root-cause finding, time-to-exhaustion estimate, or outage forecast.
- `CERTIFICATE_INFO` is intentionally not queried. Its store password and elevated-authority requirements belong to a separate reviewed DCM capability; Assist is told not to request either.
- Local export is operator initiated and may contain target, operational metrics, object identities, PTF status, and source receipts. Nothing is written automatically.
- Assist context is advice-only and explicitly reviewed. It withholds target identity, qualified job names, receipt error details, credentials, partition identity, business rows, and certificate-store data, and cannot trigger refresh or any host action.

## Dependency and impact evidence

- The operator supplies an exact classic library, object, and IBM object type. Each component is restricted to 1–10 uppercase system-name characters before it can influence a query.
- Live collection requires an explicit action, a connected driver-enforced read-only Db2 receipt, and a non-production profile. Six generated statements are collected independently, use fixed 30-second timeouts and row caps, and cannot contain caller-provided SQL.
- Object type gates prevent same-name objects of different types from being joined through an irrelevant catalog. Column-name decoding rejects duplicate, missing, malformed, unsafe, mismatched, truncated, and over-cap evidence.
- `BOUND`, `CATALOG`, and `CANDIDATE` evidence remain distinct. Binding-directory membership does not prove a runtime binding, insufficient authority can hide rows, and `*LIBL` is never resolved by guessing.
- Program-reference coverage remains an explicit gap because `DSPPGMREF` requires an output file and would write to the host. The Atlas performs no host write and makes no runtime-frequency, transitive-completeness, causal-use, or safe-change claim.
- Local export is operator initiated and contains exact identities, direct edges, receipts, and limitations. Assist context instead aliases object identities and omits host/object names, owners, descriptions, queries, diagnostics, and fingerprints; it is advice-only and cannot collect evidence or trigger a host action.

## Runbook review plane

- JSON import is local, operator initiated, and read through a 128 KiB bounded handle before decoding. Blueprints are capped at 32 contiguous steps, 24 typed parameters, 4 KiB of UTF-8 per action template, and 512 characters for bounded text. Malformed schema, unsafe controls, duplicate parameter or step definitions, invalid identifiers, and exceeded limits fail closed.
- Parameter keys that appear to name passwords, API keys, tokens, secrets, or credentials are rejected. Free-text parameters cannot interpolate into SQL or CL action previews; system names, positive integers, booleans, and enumerated choices are normalized by their declared type.
- SQL steps must resolve to one bounded read-only statement with a maximum of 250 rows and 30 seconds. CL steps are previews only, reject line breaks and command separators, receive a conservative risk label, and count against the blueprint mutation budget when mutating or destructive.
- Blueprint metadata, exact target, environment, normalized definitions and values, resolved step text and bounds, evidence requirements, and approval roles are encoded with byte-length framing into a deterministic SHA-256 plan fingerprint. Target, environment, or value changes discard the stale resolution and its local attestations.
- Review attestations are local alias records bound to one plan fingerprint. They are not authenticated identities, cryptographic signatures, host authority, or permission to act. Evidence requirements are declarations, not fabricated proof of collection.
- Every assessment remains `REVIEW REQUIRED` and reports the missing reviews, open checks, risk counts, and unavailable connector. There is no executor, scheduler, remote runner, command submitter, automatic resume, or host contact in this milestone.
- Local export contains the exact review plan and should be treated as sensitive. Assist context withholds blueprint, target, parameter, action, owner, reviewer, fingerprint, and timestamp values; it remains local until the operator reviews and sends it.

## Authority Path Atlas

- The operator supplies one exact user profile and exact classic library/object/type scope. Values must pass the typed IBM system-name and object-type gates before they can influence generated SQL.
- Live collection is explicit, requires the connected driver-enforced read-only Db2 capability, and is blocked for production profiles. Four initial sources and at most one dependent authorization-list source use fixed statements, 30-second timeouts, and bounded overflow probes; no caller-provided SQL is accepted.
- Result decoding is keyed by unique column name and rejects missing or duplicate columns, cross-scope identities, malformed or truncated rows, unsafe text, invalid authority indicators, and exceeded caps. Each source failure remains a sanitized evidence gap.
- Caller authority can hide security rows. Static grants, runtime authority-check observations, adopted-authority signals, and function-usage gaps remain distinct; missing rows never prove no access and the product never claims a complete effective-authority calculation.
- The local what-if only filters immutable evidence paths in memory. The code exposes no grant, revoke, user-profile change, authorization-list change, authority-collection start/end/delete, or other host-write operation.
- Operator-initiated export contains exact profile, object, grant, observation, and receipt details and must be treated as sensitive. Assist context aliases or withholds system, profile, object, owner, authorization-list, group, timestamp, diagnostic, and fingerprint values; it stays local until reviewed and sent.

## Provider discovery

- Local provider discovery checks only a small compiled list of executable and library paths. It does not inspect `PATH`, environment variables, shell configuration or history, project secret files, or another application's credential store.
- Detection is evidence of local availability only. It does not establish host authenticity, user authority, configuration correctness, or a live connection.
- The Provider Bay never installs packages, registers drivers, prompts for passwords, or contacts a host. The separate Db2 Connection Dossier resolves the fixed driver/runtime evidence, validates one target, and contacts it only after an explicit Connect action.
- The SSH/SFTP connector presents host-key evidence before authentication. Db2 relies on TLS certificate validation and a fixed driver contract; it does not reuse SSH host pins or accept a trust-all mode.

## SSH/SFTP host trust

- Host, port, and user values are validated as single tokens and passed to `/usr/bin/ssh`, `/usr/bin/ssh-keyscan`, and `/usr/bin/sftp` as argument arrays; no shell evaluates them.
- Host-key collection is an explicit operator action and is unauthenticated evidence, not proof. The UI requires independent fingerprint comparison before pinning.
- Pins are kept in an app-managed `known_hosts` file with directory mode `0700` and file mode `0600`. Symlink targets and changed keys for the same algorithm are rejected rather than replaced.
- Authentication uses either the macOS SSH agent or an explicit absolute key path. Batch mode disables password prompts, agent forwarding, X11 forwarding, port forwarding, local commands, user SSH configuration, and pseudo-terminals.
- The current live test executes only a constant remote `true` command and then a fixed `pwd`/`quit` SFTP batch. Both subprocess time and combined output are capped.
- A successful transport test is ephemeral evidence, not authorization to upload. IFS write still requires a regular-file target, exact remote revision, UTF-8 round trip, current comparison, generated sibling, immutable review, and a second operator action.

## Session Flight Recorder custody

- Durable recording is off by default and must be armed independently for each open terminal session. Armed state is never restored after restart.
- Before persistence, every unprotected input field is cleared whether or not it is marked modified; non-display cells are cleared; and rows labeled as passwords, passphrases, API keys, tokens, or secrets are cleared in full.
- Evidence cells are rewritten as protected, display-only cells. A reconstructed frame has no input fields, no recoverable host buffer, and no transport capability.
- The recorder archive is size bounded, date bounded, duplicate bounded, fingerprint validated, atomically written, and restricted to a non-symlink directory and regular file with `0700`/`0600` permissions. Broadly readable or symlinked custody paths are refused on read.
- Macro definitions reject NULs, control text, oversized commands, common credential assignments, unsupported AIDs, duplicate steps, and over-limit routes. Live command staging must additionally pass the existing read-only classifier and visible command-entry-field gate.
- Forward Edge Trigger AID `X'50'` is emitted only after the host marks a field with exact FCW `X'8501'` and a valid interactive completion occurs. Reviewed bulk paste never emits it; a staged FET field requires an explicit Field Exit and reports that boundary locally.
- Any macro edit invalidates its local review fingerprint. A macro is bound to its reviewed profile when configured, each live step requires one operator action, and the route pauses after passed or blocked execution. There is no background playback or automatic chain.
- Macro reviews are local attestations, not identities or signatures. Recorder JSON exports and protected host output can still contain sensitive business data; local file permissions and retention are not encryption or data-loss prevention.

## Command safety

AI responses receive a conservative first-pass label: read-only, mutating, destructive, or unknown. Labels are advisory. iTelAS does not execute AI output. The implemented Runbook review plane enforces the local subset below; any future execution connector must preserve and extend it:

- exact environment and target review;
- resolved command preview without hidden substitutions;
- typed inputs and validation;
- preconditions and expected-state checks;
- separate approval for destructive steps;
- a reason for production mutations;
- complete output/evidence capture and safe stop behavior.

## Threats to test

- Malicious or malformed Telnet/TN5250 records, oversized records, negotiation loops, and control-byte injection.
- TLS downgrade attempts, certificate errors, DNS rebinding, and connection-state races.
- Prompt injection embedded in screen, source, job-log, spool, or database content; every attached text item must remain inside the untrusted-data envelope and outside trusted proposal policy.
- Accidental cross-environment commands, stale profile state, and misleading environment aliases.
- CCSID conversion that changes command or identifier meaning.
- Sensitive spool/source/query data leaking into exports, logs, crash reports, or AI context.
- Sensitive protected terminal output entering a recorder archive, stale review fingerprints, cross-profile macro reuse, symlinked custody paths, and accidental multi-step playback.

## Distribution

The local packaging script applies an ad-hoc signature for development. Public distribution requires a Developer ID signature, hardened runtime review, entitlement minimization, notarization, update-signature verification, and a documented vulnerability response process.
