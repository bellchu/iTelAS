# Research notes

Research was performed in July 2026 using public primary sources and repository metadata.

## Protocol references

RFC 1205 specifies TN5250’s Telnet option requirements and general record header, including BINARY, END-OF-RECORD, terminal type, the `0x12A0` record type, and the opcode position. It also defines the exact Query command/reply layout and capability bits, corrects the Insert Cursor order value to `0x13`, documents Move Cursor and transparent data/field behavior, and defines Read MDT Alternate's null preservation. RFC 4777 obsoletes RFC 2877 and is the current IBM i Telnet enhancements reference for named devices, environment attributes, collision retries, and startup response records. IBM's current 5250 Data Stream Details document is the primary source for Write-to-Display control timing, display-address initialization, keyboard/cursor/message/alarm bits, MDT operations, and the color-display attribute table. IBM's Set Field contract supplies the exact FFW input-type and flag table, row-one/column-zero boundary, controller-supplied ending attribute, redefinition rules, and optional FCW registry. In particular, it defines last-position auto-enter, nondata satisfaction of Field Exit Required, MDT-based Mandatory Enter, null-based Mandatory Fill, right blank/zero adjustment, Dup `X'1C'`, and signed-numeric exit behavior. It also defines `X'8501'` as Forward Edge Trigger: the same completion behavior as Auto Enter, with the FFW Auto Enter bit ignored and the distinct QSN_FET AID `X'50'` returned. IBM's Read Input, Read Modified Fields, and Read Modified Alternate contracts distinguish concatenated all-input-field data from SBA-delimited modified fields, define standard versus alternate null formatting, and require an inbound Transparent Data order and length for transparent MDT fields. IBM's device-type guidance confirms 3179-2 for 24×80 color and 3477-FC for 27×132 color. The IBM 5494 Functions Reference supplies the exact Erase-to-Address length/type/range contract, Write Extended Attribute primary/foreground-color behavior, and Start-of-Header layout. SOH bytes 5–7 are PF24-through-PF1 exclusion switches; a set bit suppresses field data for that PF AID, while shorter headers leave all PF keys unmasked. The historical IBM 5250 Functions Reference Manual defines `X'80nn'` read resequencing: one-based entry-field numbering in screen order includes bypass entries, a missing FCW advances normally, and the chain must finish with `X'80FF'`. iTelAS treats undefined targets, missing terminators, more than 128 entries, and closed loops as protocol errors and sends no partial input.

- <https://www.rfc-editor.org/info/rfc1205/>
- <https://www.rfc-editor.org/info/rfc4777/>
- <https://www.rfc-editor.org/info/rfc1572/>
- <https://www.ibm.com/docs/en/i/7.4.0?topic=ssw_ibm_i_74%2Fapis%2Fdsm1f.html>
- <https://www.ibm.com/docs/en/i/7.4.0?topic=q-set-field-qsnsetfld>
- <https://www.ibm.com/docs/en/i/7.4.0?topic=q-read-input-fields-qsnreadinp>
- <https://www.ibm.com/docs/en/i/7.5.0?topic=q-read-modified-fields-qsnreadmdt>
- <https://www.ibm.com/docs/en/i/7.5.0?topic=q-read-modified-alternate-qsnreadmdtalt>
- <https://www.ibm.com/support/pages/node/636245>
- <https://www.ibm.com/docs/en/hats/9.7.0?topic=tasks-using-extended-field-attributes>
- <https://bitsavers.org/pdf/ibm/5494/SC30-3533-02_5494_Remote_Control_Unit_Functions_Reference_Rel_2.0_199311.pdf>
- <https://bitsavers.org/pdf/ibm/5250_5251/SA21-9247-6_IBM_5250_Information_Display_System_Functions_Reference_Manual_198703.pdf>

Because credentials over plain Telnet are unsafe, iTelAS defaults to TLS and deliberately does not implement RFC 4777 auto-sign-on password exchange. Interactive sign-on remains a host-screen operation and passwords are not saved by default.

## Keyboard behavior references

The Mac key map follows IBM's published 5250 conventions where the operating system provides an equivalent: keypad Enter for Field Exit, keypad Plus/Minus for Field Plus/Minus, Shift-Insert for Dup, Shift-F1 through Shift-F12 for F13 through F24, Page Up for Roll Down, Page Down for Roll Up, plus Home, End/Erase EOF, Insert, and the standard AID keys. iTelAS presents these mappings in an in-app reference because compact Mac keyboards do not label the underlying 5250 function.

- <https://www.ibm.com/docs/en/personal-communications/15.0.0?topic=assignments-default-key-functions-5250-layout>
- <https://www.ibm.com/support/pages/steps-map-keyboard-host-functions-using-access-client-solutions>

## Official-client baseline

IBM i Access Client Solutions establishes the parity baseline: 5250 display/printer/session management, data transfer, SQL scripts, IFS access, spool viewing/downloading, SSL configuration, consoles, languages, and code pages. It can run on Apple Silicon through its Java distribution; iTelAS is compiled as a native arm64 application.

- <https://www.ibm.com/support/pages/ibm-i-access-client-solutions>

IBM's current macOS application-package guidance states that IBM i Access Client Solutions supports Apple Silicon on supported macOS releases and supplies an ODBC driver that works with unixODBC. IBM's Mac update instructions also describe driver registration under `/Library/IBMiAccess` and supported OpenSSL prerequisites. iTelAS treats each of these as an independently proven local gate; it does not bundle or install IBM's licensed package.

- <https://www.ibm.com/support/pages/ibm-i-access-acs-updates-mac>
- <https://www.ibm.com/support/pages/odbc-driver-ibm-i-access-client-solutions>
- <https://www.ibm.com/docs/en/i/7.5.0?topic=packages-linux-macos-pase-application>

IBM i Services provide supported SQL surfaces for active jobs, locks, spool files, ASP/storage, system limits, and system status. These are the preferred foundation for transparent, read-only operational views.

- <https://www.ibm.com/support/pages/ibm-i-services>

The first Db2 Query Flight Deck catalog uses the official `QSYS2` services below. Templates are intentionally bounded and remain local until the operator explicitly connects the native read-only provider and every execution gate passes.

Build 41 also follows IBM's documented IBM i Access ODBC type mappings when constructing the local typed-result contract: BIGINT, BOOLEAN, DATE/TIME/TIMESTAMP, DECIMAL, character/graphic, binary/BLOB, and CCSID 65535 values retain their declared database type and an observed value kind. IBM notes that large-precision decimal values should be bound as character data when exactness matters; iTelAS therefore exports exact decimal text and treats CSV spreadsheet-safety transformations as an explicit product policy, not an IBM conversion guarantee. Typed JSON and CSV/manifest packages are local representations with receipts, not host-side ACS export semantics.

- IBM i Access ODBC overview: <https://www.ibm.com/docs/en/i/7.5.0?topic=administration-overview-i-access-odbc-driver>
- IBM i Access ODBC programming: <https://www.ibm.com/docs/en/i/7.5.0?topic=programming-i-access-odbc>
- IBM i Access ODBC data-type mappings: <https://www.ibm.com/docs/en/i/7.5.0?topic=iaodsd-odbc-data-types-how-they-correspond-db2-i-database-types>
- IBM i allowable data-type conversions: <https://www.ibm.com/docs/en/i/7.5.0?topic=definition-allowable-conversions-data-types>

- Active jobs: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-active-job-info-table-function>
- Object locks: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-object-lock-info-view>
- IFS object locks: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-ifs-object-lock-info-table-function>
- Output queue entries: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-output-queue-entries-table-function>
- System status: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-system-status-info-view>
- ASP capacity: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-asp-info-view>

## Job incident service references

The Jobs & Queues Incident Thread uses four documented IBM i Services surfaces. `JOB_INFO` provides the broad job inventory and queue fields used by work-with-job views. `OBJECT_LOCK_INFO` supplies exact object, lock status/state/scope, job, and execution-location fields. `JOBLOG_INFO` returns ordered first- and second-level message text for one qualified job. `MESSAGE_QUEUE_INFO` reads queue messages without changing their new/old designation and supports QSYSOPR inquiry filtering. Authority and column availability can vary by object, release, and IBM i Services group PTF, so only job inventory is required and every other source retains an explicit unavailable receipt.

- Job inventory: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-job-info-table-function>
- Active-job comparison surface: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-active-job-info-table-function>
- Object locks: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-object-lock-info-view>
- Job log: <https://www.ibm.com/docs/en/i/7.6.0?topic=services-joblog-info-table-function>
- Message queue: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-message-queue-info-table-function>

The implementation deliberately does not infer causality from a matching held/requested object pair. It records the exact identity and presents holder jobs as candidates for operator review. It also does not assign timestamps to lock rows because that service surface describes sampled state rather than a lock event time.

## Spool and output service references

The Spool & Output Document Inspector deliberately separates passive metadata from file content. `QSYS2.SPOOLED_FILE_INFO` supplies visible file identity and status, while `QSYS2.OUTPUT_QUEUE_INFO` supplies output-queue, writer, authority, and pressure evidence. An exact, operator-selected content request uses bounded `SYSTOOLS.SPOOLED_FILE_DATA` records; IBM documents that this function internally embeds a spool-copy command, so iTelAS labels the read as explicit and potentially audited even though the application exposes no spool mutation control.

The current preview is a text-record view, not a page renderer. IBM's `SYSTOOLS.GENERATE_PDF` requires the Transform Services product option and writes a PDF to the IFS, so it remains outside this read-only milestone. AFP/IPDS fidelity, overlays, fonts, graphics, writer control, printer sessions, and host-side conversion require separate capability and authority designs.

- Spooled-file inventory: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-spooled-file-info-table-function>
- Output-queue information: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-output-queue-info-view>
- Ordered spooled-file text records: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-spooled-file-data-table-function>
- PDF generation boundary: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-generate-pdf-scalar-function>

## Data transfer references

IBM i Access Client Solutions establishes the user expectation for transferring data between workstation files and IBM i database files, including spreadsheet-oriented formats. IBM support guidance also documents automation and format-specific considerations. iTelAS treats that behavior as a parity reference, not as permission to reuse the ACS interface or to infer conversions silently.

The current Integrity Lab deliberately narrows its implemented input to bounded UTF-8 CSV. Target metadata comes from `QSYS2.SYSCOLUMNS2`, which IBM documents as one row per table or view column and as the preferred faster surface when requesting one exact table. The selected fields preserve both SQL and system column names, ordinal, type, length, numeric scale, nullable/updateable/default status, CCSID, identity generation, hidden state, field-procedure state, and date formatting evidence.

IBM's import tooling and `CPYFRMIMPF` notes demonstrate that delimiter, decimal, date, null, CCSID, and record-shape choices materially affect outcomes. Consequently, iTelAS keeps values as strings, accepts only ISO dates for date targets in this milestone, proves target-CCSID round trips without substitution, and leaves every host write unavailable until a separate staged and reversible protocol exists.

- ACS baseline: <https://www.ibm.com/support/pages/ibm-i-access-client-solutions>
- Downloading into Excel: <https://www.ibm.com/support/pages/node/666965>
- Uploading from Excel: <https://www.ibm.com/support/pages/transferring-data-excel-using-access-client-solutions>
- Automating ACS transfer: <https://www.ibm.com/support/pages/automating-acs-data-transfer>
- PC file-type considerations: <https://www.ibm.com/support/pages/data-transfer-pc-file-types-and-considerations>
- `SYSCOLUMNS2`: <https://www.ibm.com/docs/en/i/7.5.0?topic=views-syscolumns2>
- `CPYFRMIMPF` notes: <https://www.ibm.com/docs/en/i/7.5.0?topic=systems-notes-cpyfrmimpf-command>

## System health service references

The System Health Evidence Cockpit uses five official IBM i Services surfaces. `SYSTEM_STATUS_INFO` supplies a non-resetting system snapshot for job, job-table, temporary-storage, attention, restricted-state, and system-ASP fields. IBM documents that its average CPU columns always return zero on IBM i 7.5, so iTelAS instead uses `SYSTEM_ACTIVITY_INFO(1)` for a measured interval of at least one second; that table function requires `*JOBCTL` special authority and can remain independently unavailable.

`ASP_INFO` supplies ASP state, capacity, threshold, disk-unit presence, and encryption evidence. `SYSLIMITS` supplies recorded high-water occurrences; these rows are not a time series, root-cause proof, or exhaustion forecast. IBM support guidance recommends tracking important system limits, which informs the pressure-ranked ledger while preserving that distinction. `GROUP_PTF_INFO` supplies installed group status only and cannot establish whether a newer group level exists on the internet.

`CERTIFICATE_INFO` was evaluated and deliberately excluded. IBM documents a certificate-store password parameter plus elevated authority requirements, so certificate posture remains a separate future DCM capability instead of prompting for privileged secrets inside this read-only cockpit or Assist.

- System status: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-system-status-info-view>
- Measured CPU activity: <https://www.ibm.com/docs/en/i/7.4.0?topic=services-system-activity-info-table-function>
- ASP information: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-asp-info-view>
- System-limit occurrences: <https://www.ibm.com/docs/en/i/7.4.0?topic=services-syslimits-view>
- Lower-authority system-limit alternative: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-syslimits-basic-view>
- Group PTF status: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-group-ptf-info-view>
- IBM support on limits reached: <https://www.ibm.com/support/pages/options-when-physical-file-or-access-path-has-reached-system-limit>
- IBM support on tracking limits: <https://www.ibm.com/support/pages/tracking-important-system-limits>
- IBM i 7.5 services changes: <https://www.ibm.com/docs/en/i/7.5.0?topic=optimization-whats-new-i-75>

## Dependency and impact references

The Dependency Atlas starts from an exact library, object name, and IBM object type. `OBJECT_STATISTICS` is the metadata authority for that identity, but IBM documents that object authority can produce partial or no rows, so an empty result is never treated as proof of absence.

Direct ILE evidence comes from `BOUND_SRVPGM_INFO` and `BOUND_MODULE_INFO`. Binding-directory entries come from `BINDING_DIRECTORY_INFO`, but membership describes a build-search candidate rather than a proven runtime binding. `SYSROUTINES` supplies registered SQL-routine associations, and `SYSVIEWDEP` supplies direct view dependencies. The current planner gates these catalogs by target type and preserves every source independently rather than blending them into an inferred complete graph.

IBM documents `DSPPGMREF` with an output-file contract. Because invoking it would create or replace a host object, the current read-only Atlas does not call it and exposes program-reference coverage as a gap. Future expansion may add reviewed ingestion for that artifact and direct dependency catalogs such as `SYSROUTINEDEP`, `SYSTRIGDEP`, and `SYSCSTDEP`, but only with release and authority fixtures.

IBM support recommends tight predicates, row limits, and awareness that SQL service cost varies. Atlas requests therefore use exact or tightly bounded predicates, fixed result caps, 30-second timeouts, and independent failure receipts. None of these catalogs prove runtime frequency, transitive completeness, causality, or that a proposed change is safe.

- Object metadata: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-object-statistics-table-function>
- Bound service programs: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-bound-srvpgm-info-view>
- Bound modules: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-bound-module-info-view>
- Binding directories: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-binding-directory-info-view>
- SQL routines: <https://www.ibm.com/docs/en/i/7.5.0?topic=views-sysroutines>
- View dependencies: <https://www.ibm.com/docs/en/i/7.4.0?topic=views-sysviewdep>
- Program references: <https://www.ibm.com/docs/en/i/7.5.0?topic=ssw_ibm_i_75%2Fcl%2Fdsppgmref.html>
- SQL Services performance guidance: <https://www.ibm.com/support/pages/ibm-i-sql-services-information>
- List object security: <https://www.ibm.com/docs/en/i/7.5.0?topic=changes-list-object-security-protection>

## Runbook and operational procedure references

IBM documents CL validity checking as a way to detect command syntax, value, object-existence, and some authority problems before attempted processing. It is useful future preflight evidence, but it cannot establish that runtime state will remain unchanged between review and action. `QSYS2.COMMAND_INFO` can provide command metadata for a release-aware catalog, while IBM's CL coding rules reinforce that command parameters require explicit, correctly formed values. iTelAS therefore resolves exact typed previews and stops before submission rather than treating text classification as permission to run.

IBM documents commitment control as a coordinated transaction boundary and separately explains how `RUNSQLSTM` participates in it. That distinction matters for any future database-changing runbook connector: a local review plan cannot promise rollback without a provider-specific transaction and evidence contract. IBM i Services such as `JOB_INFO`, `ACTIVE_JOB_INFO`, and `HISTORY_LOG_INFO` are appropriate read-only evidence sources for preconditions and post-action review, but sampled rows do not prove causality or authorize an operation.

- CL command validity checking: <https://www.ibm.com/docs/en/i/7.5.0?topic=process-cl-command-validity-checking>
- Command metadata: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-command-info-view>
- CL command coding rules: <https://www.ibm.com/docs/en/i/7.5.0?topic=commands-cl-command-coding-rules>
- CL programming model: <https://www.ibm.com/docs/en/i/7.5.0?topic=language-cl-programming>
- Commitment control: <https://www.ibm.com/docs/en/i/7.5.0?topic=file-ensuring-data-integrity-commitment-control>
- `RUNSQLSTM` commitment behavior: <https://www.ibm.com/docs/en/i/7.5.0?topic=processor-commitment-control-in-sql-statement>
- IBM i Services overview: <https://www.ibm.com/docs/en/i/7.5.0?topic=optimization-i-services>
- Job information: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-job-info-table-function>
- Active-job information: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-active-job-info-table-function>
- History log information: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-history-log-info-table-function>

## Authority evidence references

IBM documents `OBJECT_PRIVILEGES` as an object-privilege view whose returned rows depend on the caller's authority. iTelAS therefore treats each exact object row as static evidence and never interprets an empty or incomplete result as proof that access is absent. The view's detailed object and data indicators support the Atlas authority-surface matrix without collapsing the result into a guessed effective-authority value.

`USER_INFO` supplies selected profile posture such as status, user class, group profile, supplemental-group count, special authorities, and authority-collection state; the Atlas deliberately selects no password-related column. `GROUP_PROFILE_ENTRIES` supplies primary or supplemental membership evidence. These rows explain possible paths but do not by themselves resolve function usage, adopted authority, owner behavior, or every runtime context.

`AUTHORIZATION_LIST_USER_INFO` describes caller-visible entries for one exact authorization list. The planner only requests it after `OBJECT_PRIVILEGES` yields one validated authorization-list identity; it never guesses a list name. IBM's authority-collection views preserve observed check fields including required/current authority, authority source, group and adopted-authority signals, and success. Those rows describe exercised checks only, so collection coverage stays unknown and observed evidence remains separate from static grants.

- Object privileges: <https://www.ibm.com/docs/en/i/7.6.0?topic=services-object-privileges-view>
- User profile information: <https://www.ibm.com/docs/en/i/7.6.0?topic=services-user-info-view>
- Group profile entries: <https://www.ibm.com/support/knowledgecenter/ssw_ibm_i_76/rzajq/rzajqviewgroupprof.htm>
- Authorization-list entries: <https://www.ibm.com/docs/ssw_ibm_i_74/rzajq/rzajqviewauthluserinfo.htm>
- Authority collection views: <https://www.ibm.com/docs/en/i/7.6.0?topic=collection-authority-views>

## Source-member record semantics

An IBM i source physical file is a fixed-record database file. Its conventional layout includes decimal `SRCSEQ` and `SRCDAT` fields followed by character `SRCDTA`; the record length includes the twelve metadata bytes. IBM documents that copying a member to a stream file removes sequence and date information, so iTelAS keeps source-member editing separate from its SFTP IFS provider.

The record provider therefore uses `QSYS2.SYSFILES` for file layout and authority evidence, `QSYS2.SYSMEMBERSTAT` for member metadata, `QSYS2.JOURNALED_OBJECTS` for journal evidence, a `QTEMP` alias bound to the selected member, and `RRN()` for stable read ordering. The native transport and workbench expose separate source-read and reviewed-source-write capabilities with serializable commitment control; journal before-and-after images remain mandatory before the core will construct a write plan. This path has not been exercised against a live host.

- Source physical file layout: <https://www.ibm.com/docs/en/i/7.5.0?topic=file-creating-source-without-dds>
- Source-member attributes: <https://www.ibm.com/docs/en/i/7.5.0?topic=file-source-attributes>
- `SYSMEMBERSTAT`: <https://www.ibm.com/docs/en/i/7.6.0?topic=services-sysmemberstat-view>
- `SYSFILES`: <https://www.ibm.com/docs/ssw_ibm_i_76/rzajq/rzajqviewsysfiles.htm>
- Alias names and member aliases: <https://www.ibm.com/docs/en/i/7.5.0?topic=language-creating-using-alias-names>
- IBM Support member-alias example: <https://www.ibm.com/support/pages/how-do-lightweight-jdbc-query-multi-member-file-db2-as400-6b429740a2015038852579190007a8d5>
- Relative record number: <https://www.ibm.com/docs/en/i/7.5.0?topic=functions-rrn>
- `JOURNALED_OBJECTS`: <https://www.ibm.com/docs/en/i/7.5.0?topic=services-journaled-objects-view>
- Journal operations: <https://www.ibm.com/docs/en/i/7.6.0?topic=auditing-operations-journal-jrn>
- Commitment control: <https://www.ibm.com/docs/en/i/7.5.0?topic=adf-using-commitment-control>

## Source intelligence references

IBM documents `**FREE` as the first-line control for fully free RPG source and documents `/COPY` and `/INCLUDE` as preprocessing directives whose referenced content changes the source seen by the compiler. It also distinguishes prototypes and procedure interfaces, and describes the QSYSINC include library. Those contracts shape the local outline and typed-reference model, but they also establish why an editor-only scan cannot claim compiler equivalence: include expansion, conditional directives, templates, object binding, and generated coordinates require separate evidence.

The active Code for IBM i RPG language project demonstrates the professional expectation for outline, content assistance, linting, column assistance, references, and integrated compile feedback. iTelAS implements a deliberately bounded first layer—navigation, reference identity, local structural advisories, receipt-bound local completion, and reviewed Assist handoff—while retaining Compile Evidence as the authority for IBM diagnostics.

- Fully free RPG source: <https://www.ibm.com/docs/en/i/7.4.0?topic=statements-fully-free-form>
- `/COPY` and `/INCLUDE`: <https://www.ibm.com/docs/en/i/7.5?topic=directives-copy-include>
- RPG prototypes: <https://www.ibm.com/docs/en/i/7.6.0?topic=parameters-prototypes>
- SQL precompiler directives in RPG: <https://www.ibm.com/docs/en/i/7.6.0?topic=essiiratus-using-directives-in-ile-rpg-applications-that-use-sql>
- QSYSINC include files: <https://www.ibm.com/docs/en/i/7.6.0?topic=concepts-include-files-qsysinc-library>
- Code for IBM i RPG language tooling: <https://github.com/codefori/vscode-rpgle>

## Native ODBC and international display boundaries

IBM documents the IBM i Access ODBC connection keywords used by the Dossier contract, including system identity, SSL, connection type, commitment control, Unicode SQL, tracing, and procedure-call behavior. unixODBC's public headers define the 64-bit ABI and statement/connection attributes used by the dynamically loaded transport. iTelAS loads a fixed driver-manager path at runtime so the app remains a native arm64 bundle without redistributing IBM's licensed driver.

- Connection-string keywords: <https://www.ibm.com/docs/en/i/7.6.0?topic=details-connection-string-keywords>
- unixODBC headers: <https://github.com/lurcher/unixODBC/tree/master/include>

IBM's bidi documentation makes clear that Arabic and Hebrew 5250 support is more than decoding a code page: the workstation implements language selection, reverse/close functions, screen direction, typing direction, and OIA state. IBM i documentation also distinguishes legacy visual storage from logical order. For DBCS, the data-stream translation API calls out balanced shift-out/shift-in bytes, DBCS-field restrictions, dead positions, and invalid-character handling. iTelAS therefore keeps 420/424/918 as tested codec-only definitions and blocks them as terminal profiles; mixed-byte 930/933/935/937/939 remain unavailable until the full state machine exists.

- Bidirectional functions for 5250: <https://www.ibm.com/docs/en/personal-communications/15.0?topic=support-bidirectional-functions-5250>
- IBM i bidirectional application support: <https://www.ibm.com/docs/en/i/7.5.0?topic=data-bidirectional-application-support>
- Visual versus logical bidi data: <https://www.ibm.com/docs/en/i/7.4?topic=applications-working-bidirectional-data>
- 5250 data-stream translation integrity errors: <https://www.ibm.com/docs/en/i/7.6.0?topic=q-translate-data-stream-qd0trnds>

## Current professional signals

The active Code for IBM i project demonstrates demand for modern RPG/CL/COBOL editing, compile feedback, content assist, IFS/source-member work, and source-date preservation. Its public issue history also surfaces recurring friction around visible host/environment identity, profile automation, save/compile latency, CCSID behavior, actionable connection errors, navigation reliability, and AI behavior in engineering workflows.

- <https://github.com/codefori/vscode-ibmi>
- <https://github.com/codefori/vscode-ibmi/issues/3078>
- <https://github.com/codefori/vscode-ibmi/issues/2618>
- <https://github.com/codefori/vscode-ibmi/issues/3300>
- <https://github.com/codefori/vscode-ibmi/issues/2904>
- <https://github.com/codefori/vscode-ibmi/issues/2858>

These signals shaped iTelAS around environment safety, clear connection diagnostics, CCSID visibility, source-to-build continuity, and opt-in AI with explicit context boundaries.

## Compile evidence references

IBM documents `OPTION(*EVENTF)` as the compiler option that creates file `EVFEVENT` in the target library, with a member named for the object being created, so client tooling can provide editor-integrated feedback. IBM's support guidance for user-written compile commands likewise requires a source member plus `*EVENTF` and describes the target-library/member identity contract.

IBM documents `TGTRLS` as the target release for the created object. On IBM i 7.6, `*CURRENT` means V7R6M0 and `*PRV` means V7R5M0; IBM also lists V7R4M0 as an allowed explicit earlier value. Because relative tokens depend on the release where the retained command ran, iTelAS records an observed host release separately and otherwise labels the target as relative rather than guessing it. IBM's RPG source-listing documentation also distinguishes source sections and `/COPY` expansion, supporting the bridge's refusal to navigate expanded coordinates until remapping evidence exists.

IBM's command references establish the two bounded shapes used by the local Compile Recipe Studio. `CRTBNDRPG` accepts a qualified `PGM`, `SRCFILE`, `SRCMBR`, `OPTION(*EVENTF)`, `DBGVIEW`, `TGTRLS`, and `REPLACE`. `CRTSQLRPGI` uses qualified `OBJ`, supports `OBJTYPE(*PGM)`, `COMMIT`, `OPTION(*EVENTF)`, `RPGPPOPT(*NONE|*LVL1|*LVL2)`, `DBGVIEW(*NONE|*SOURCE)`, `TGTRLS`, and `REPLACE`. iTelAS deliberately exposes only their shared program workflow and fixed enumerated choices; it does not accept `COMPILEOPT`, passwords, arbitrary parameter text, modules, service programs, or command submission.

These contracts justify binding retained lineage by exact target, object, event-file, source-revision, compiler-command, and release context. They do not establish causal ordering, complete job-log coverage, successful object replacement, authority, or runtime behavior, so the Compile Lineage Board keeps those as explicit evidence gaps.

- <https://www.ibm.com/docs/en/ssw_ibm_i_74/rzarf/compile_option.htm>
- <https://www.ibm.com/docs/en/i/7.5.0?topic=cbc-create-bound-c-program>
- <https://www.ibm.com/support/pages/rational-developer-power-systems-user-written-compile-command-not-sending-output-error-list>
- <https://www.ibm.com/docs/en/i/7.6.0?topic=support-current-release-previous-release>
- <https://www.ibm.com/docs/en/i/7.6.0?topic=statements-set-option>
- <https://www.ibm.com/docs/en/i/7.5.0?topic=command-description-crtbndrpg>
- <https://www.ibm.com/docs/en/i/7.4.0?topic=c-create-sql-ile-rpg-object>
- <https://www.ibm.com/docs/en/i/7.5.0?topic=listing-source-section>

The current Code for IBM i implementation was inspected read-only as a professional-demand and interoperability reference. It reads `EVFEVENT` through a temporary database-file override, converts each record to the connection CCSID, and delegates parsing to IBM's maintained `@ibm/ibmi-eventf-parser` package. iTelAS does not copy that parser or its interface; it independently implements a bounded Swift subset and keeps `EXPANSION` remapping visibly unsupported until complete fixtures prove it.

- <https://github.com/codefori/vscode-ibmi>
- <https://codefori.github.io/docs/dev/scope/>
- <https://www.npmjs.com/package/@ibm/ibmi-eventf-parser>

IBM's `JOBLOG_INFO` table function is the implemented read-only source for a selected Jobs & Queues incident, while binding a complete job log to a particular remote compile run remains future work. EVFEVENT import alone is never presented as a complete job log.

- <https://www.ibm.com/docs/en/i/7.5.0?topic=services-joblog-info-table-function>

## OpenSSH provider references

The secure-channel boundary follows the OpenSSH client model: a destination and optional constant remote command, explicit identity selection, strict host-key checking through a known-hosts file, and SFTP batch mode. The OpenSSH `ssh-keyscan` manual explicitly warns that collected keys must be verified before constructing a trusted known-hosts set; iTelAS therefore separates collection, independent comparison, pinning, and authentication into distinct states.

- <https://man.openbsd.org/ssh.1>
- <https://man.openbsd.org/ssh-keyscan.1>
- <https://man.openbsd.org/sftp.1>
