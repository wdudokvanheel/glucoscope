# iOS Libre 2 transactional ingestion design

> **Status: isolated foundation implemented in source; runtime ingestion remains unimplemented.** `Persistence/ReadingStoreTypes.swift`, `ReadingStoreModel.swift`, and `ReadingStore.swift` provide a separate Core Data transaction foundation and are registered in the app target. The versioned Keychain wear identity and conservative deliberate-setup preservation are also implemented. The expanded `./ios/Libre2Tests/run.sh` suite passed on 10 September 2026, including all four protocol, diagnostic-decoder, wear-identity and isolated-store executables. No app coordinator opens this store or submits live calculations. `Libre2DiagnosticDecoder` remains diagnostics only, with no canonical display, graph or upload connection.

## Current implementation boundary — 10 September 2026

The isolated store provides versioned Core Data model construction, a serial writer, session/clock validation, deduplicated reading-and-delivery transactions, explicit unassigned delivery, later deterministic destination assignment, redacted conflicts, committed snapshots, bounded explicit retry and injectable load/save/publication faults. Protected SQLite configuration is present for iOS; desktop SQLite tests cannot establish iPhone file-protection behavior. The completed synthetic suite covers injected faults, concurrent submissions, corrupt SQLite failure, reopen after SQLite saves and the actual commit stream. It exercises store operations directly and does not promote a decoder or create a production collection path.

Store operations remain serialized across each actor call through save and publication. Accepted dates are bounded to 2000–2100 and sensor minutes to 0–20,880; these are explicit ingestion-domain checks. Destination assignment freezes version-1 internal JSON for deterministic tests; it is not a Nightscout or Glucoscope backend payload adapter. Commit notifications are bounded hints to refetch committed data, not a durable replay log. Consumers must refetch on launch/reconnect and after missed notifications; historical notification replay is not guaranteed, including after a save succeeds but publication is interrupted.

`LibreSensorSession` now carries versioned `persistenceSessionID` metadata. `LibreSessionStore.loadForIngestion()` saves a missing legacy ID before returning it; malformed present metadata blocks ingestion but leaves pairing readable. In-process Keychain serialization and identity-preserving saves prevent an old BLE-held legacy value from erasing a migrated ID during a counter save. The stable fingerprint is a versioned SHA-256 of UID and stable patch bytes, excluding bytes 4–5 and pairing secrets.

Deliberate full NFC setup preserves UUID and the exact original clock only when physical identity, nonregressing sensor minute and lifecycle agree, and the new capture lies within 120 seconds of that clock mapping. This tolerance is an engineering repair policy, not a sensor-validated bound. Missing calibration/clock asks for read-only calibration; ambiguous continuity, backward minutes/lifecycle or a larger phone-clock correction blocks setup before pending credentials or streaming enablement. It never infers a fresh wear from clock disagreement alone. A different physical sensor receives a new UUID. Same-UID reset inference and reconciliation of a forgotten sensor remain unsupported. These new setup and Keychain paths have synthetic coverage only; existing v5 hardware evidence predates them.

Still unimplemented: a promoted decoder/result contract; the immutable connection-generation/session/calibration/clock frame envelope; the app-owned collection coordinator and stale-frame rejection; copying the canonical SQLite clock back into Keychain before accepting repair frames; main-actor collection health and diagnostic export integration; normal graph, upload and NFC ingestion. The store compares the supplied identity and clock to committed metadata, but that is not a completed end-to-end Keychain/SQLite bridge.

The user reports that the app builds and launches without visible errors with the isolated foundation registered in the target. No build log was supplied and no agent-run Xcode build was performed. Because the app does not open the store, this does not exercise persistence, migration or storage protection at runtime. Next, implement and test the immutable envelope carrying its connection generation and session snapshot, the collection coordinator, and the canonical-clock repair bridge while keeping diagnostic decoder output excluded. No sensor switch, additional streaming setup or new hardware check is needed for this source milestone; a physical storage-protection check becomes useful only once a deliberate runtime test path can open and inspect the store.

Continue this milestone without automatically starting NFC, repeating streaming setup, or changing the active sensor session. Any NFC capture or setup remains an explicit user action. Keep the new store and its tests isolated from the current diagnostic and production viewer paths until the transaction, identity bridge, and fault behavior below are verified.

## Boundary and flow

`LibreBluetoothCentral` should continue to do short transport work on its existing serial queue: assemble, decrypt, and CRC-check a frame, then emit an immutable payload with its receipt time, connection generation, persistence session ID, and the exact identity/calibration/clock snapshot which authenticated it. An app-owned collection coordinator rejects a stale generation or replaced active session before invoking the pure decoder; it must never look up a newer pairing and relabel an older callback. It submits only accepted slots to `ReadingStore`; it must not display, graph, or schedule them first.

`ReadingStore` owns one serial Core Data writer context. One writer transaction resolves the sensor wear session, deduplicates every candidate, and creates both each new reading and its delivery record. Only a successful save publishes a commit containing the affected reading IDs. Local graph queries and the future upload coordinator consume that commit or refetch committed objects. Core Bluetooth never waits for network work, and SwiftUI never observes uncommitted candidates.

The decoder promotion is a separate gate. Until its numerical behavior has the agreed timestamp-matched evidence and its input/rejection contract is accepted, `Libre2DiagnosticDecoder`, `Libre2DiagnosticFrame`, and `Libre2DiagnosticSlot` must not feed `ReadingStore`. Production ingestion should use a deliberately promoted decoder/result type so an accidental reference to the diagnostic path is review-visible. Diagnostic UI and exports may show an unpersisted calculation, but must label it experimental and must never expose it through `GlucoseMeasurement`, `DataSource`, the normal graph, or upload code.

## Core Data model for iOS 16.4

Use `NSPersistentContainer` with an SQLite store under a dedicated Application Support directory. Use an explicit model version and lightweight migration only for compatible additions; fail visibly rather than deleting or silently recreating an unreadable store.

| Entity | Fields and constraints |
| --- | --- |
| `StoredSensorSession` | `id: UUID` (unique), stable-identity fingerprint, sensor revision, first/last observed dates, lifecycle state, and non-secret clock provenance needed to interpret stored timestamps. It represents one physical sensor wear session, not one BLE pairing attempt. |
| `StoredReading` | `id: UUID` (unique), `sessionID`, `sensorMinute`, `sampleKind`, UTC sample date, received date, integer canonical mg/dL, quality, primary origin, observed-origin flags, decoder version, and creation date. Unique constraint: `(sessionID, sensorMinute, sampleKind)`. |
| `ReadingDelivery` | One required row per reading, unique by `readingID`; optional `destinationID`, state (`unassigned`, `queued`, `claimed`, `acknowledged`, `quarantined`), immutable payload/version once queued, attempt and lease fields, last error, and acknowledgement date. |
| `UploadDestination` | Stable ID, backend kind, normalized endpoint identity, credential reference, configuration revision, and enabled state. Credentials stay in Keychain. |

`sampleKind` is `trend` or `history15Minute` initially. BLE live/recovery slots and NFC trend slots share `trend`, so the same sensor minute deduplicates across those origins. Coarse NFC history remains a distinct internal kind. Graph queries prefer trend when both kinds cover the same minute and retain missing minutes as gaps; ingestion never interpolates. `origin` is provenance, not identity.

Store integer mg/dL as the canonical value and convert for presentation or backend contracts. Persist sensor minute because it is the stable sample coordinate. The UTC date is derived once from the validated session clock and retained for querying; timezone changes do not rewrite it. If a duplicate candidate disagrees with an already committed value or date beyond defined tolerances, retain the first canonical reading, record a redacted conflict diagnostic, and do not silently mutate an acknowledged or dispatched payload.

## Sensor wear identity and Keychain bridge

Add a random `persistenceSessionID` to the versioned Keychain `LibreSensorSession`. It survives calibration capture, peripheral changes, counter reservations, reconnects, and same-sensor pairing repair. `createdAt`, the peripheral UUID, unlock material, the full patch, calibration capture metadata, and clock recapture details are pairing/operation state and must not form the reading key. Stable physical identity comparison continues to use the UID and stable patch bytes, excluding mutable bytes 4–5.

Repeated full NFC setup can currently replace `createdAt` for the same physical sensor. Setup preserves `persistenceSessionID` only when stable identity matches and the sensor-minute/lifecycle evidence is consistent with the same wear session. A different physical identity creates a new UUID; ambiguous evidence for the same physical identity blocks repair rather than silently splitting the wear. Preserving the UUID must also preserve that session's original persisted clock anchor. A fresh setup capture must not move UTC dates for already known sensor minutes. A replaced sensor always creates a new UUID. Re-pairing a previously forgotten sensor may reconcile against retained Core Data metadata only under the same checks; this policy needs fixture and device validation before implementation.

Keychain and SQLite cannot share an atomic transaction. Reconcile them before accepting frames:

1. If a legacy Keychain session lacks an ID, generate one and save the upgraded Keychain record first. A failed Keychain write blocks ingestion.
2. On launch and before every ingest, upsert `StoredSensorSession` for that exact ID and verify its stable fingerprint in the Core Data writer transaction. Once present, the Core Data session clock is canonical for ingestion. Same-wear repair must copy that anchor back into the replacement Keychain pairing before frames are accepted; an unexplained clock disagreement is repair-required.
3. A crash after the Keychain save but before the Core Data insert is repaired by the next upsert. A crash before the Keychain save creates no durable ID and no reading. An ID/fingerprint disagreement is a repair-required error; never guess, merge rows, re-anchor an existing wear session, or ingest under the current pairing `createdAt`.

This bridge keeps pairing secrets and the unlock counter in Keychain with `AfterFirstUnlockThisDeviceOnly` accessibility while Core Data stores only the stable reference and non-secret reading metadata.

## Transaction and ordering rules

Give each decoded frame a process-local monotonically increasing sequence before leaving the Bluetooth queue. The store accepts frames in that submission order through one asynchronous serial writer. Correctness still comes from the unique sample key, so delayed, repeated, overlapping, or reverse-order frames produce the same rows.

Within one writer-context `perform` block and one save:

1. Resolve and validate the bridged sensor session.
2. For every accepted sparse slot, fetch `(sessionID, sensorMinute, sampleKind)`. Insert only missing readings; merge only non-canonical observation metadata on exact duplicates.
3. Create each inserted reading's required `ReadingDelivery`. If no destination is selected, save it as `unassigned` with no payload. If a destination exists, save it as `queued` with the destination and deterministic payload/version in the same transaction.
4. Obtain permanent object IDs, save once, then publish the committed IDs in chronological order. Roll back the context on any error and publish nothing.

Choosing a destination later runs a separate transaction that converts eligible `unassigned` rows to `queued` and freezes their payloads. Thus a reading is always committed with explicit delivery state, even when configuration is absent. Future delivery claims use persisted leases and acknowledgements; those behaviors remain outside this ingestion milestone.

## Protection, failure visibility, and recovery

Create the store directory with complete-until-first-user-authentication protection before loading the store and set `NSPersistentStoreFileProtectionKey` to the corresponding file-protection value on the persistent-store description. Validate on device that the SQLite file and its `-wal` and `-shm` sidecars inherit the same class. Any future file-backed upload batch must use that protection too. A reboot before first unlock is an expected unavailable-store state, not permission to hold readings indefinitely in memory or downgrade protection.

Store initialization, migration, bridge, fetch, constraint, and save errors become a main-actor collection status with operation, timestamp, redacted underlying error, and a dropped/uncommitted candidate count. Log the same redacted event through the existing diagnostics path. No failed candidate becomes a canonical reading. Stop accepting further canonical candidates while the store is unhealthy; allow BLE transport diagnostics to continue, retry store opening on a bounded lifecycle opportunity, and explain that sparse BLE recovery may recover some missed minutes but is not guaranteed. Never delete the store automatically.

## Meaningful implementation tests

Use an in-memory Core Data store for transaction semantics and a temporary protected SQLite store for migration/restart checks. Tests should prove:

- overlapping sparse frames, exact repeats, reverse arrival, and concurrent submissions yield one row and one delivery row per `(sessionID, sensorMinute, sampleKind)`, with genuine gaps left absent;
- BLE and NFC trend collide while NFC 15-minute history remains distinct, and graph selection prefers trend without rewriting history;
- no configured destination commits `reading + unassigned delivery` atomically, and later destination assignment queues all eligible rows exactly once with deterministic payloads;
- injected save/constraint/store-load failures publish no commit and expose an unhealthy status; a later retry does not create half a reading or orphan delivery;
- termination after Keychain ID migration but before the Core Data session insert, and termination after the Core Data save but before commit publication, reconcile without changing the session ID or duplicating readings;
- same-sensor setup repair, mutable patch bytes 4–5, pairing `createdAt` replacement, clock recapture, phone-clock/timezone changes, sensor replacement, and restart preserve or split session identity according to the rules above, with same-wear repair retaining both UUID and original clock;
- a delayed frame from an old connection generation or replaced sensor is rejected rather than decoded with the current pairing/clock or relabeled into its session;
- an acknowledged reading is immutable when a later candidate conflicts, and sparse recovery never manufactures a missing minute.

Fault tests need explicit save-failure injection and reopen of an on-disk test store; tests which merely call the same insertion method twice are insufficient. Hardware validation remains separate and pending: these tests cannot establish decoder accuracy, background callbacks, file accessibility while locked, or behavior of untested sensor revisions.
