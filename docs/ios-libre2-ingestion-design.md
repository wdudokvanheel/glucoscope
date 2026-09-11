# iOS Libre 2 storage and ingestion

`LibreCollectionCoordinator` owns the live route from BLE handoff through `LibreOrderedIngestion`, `LibreCandidateAdapter` and the existing `ReadingStore`. The ordinary checked decoder supplies local development readings. The diagnostics screen reloads the latest 15 saved readings on startup, completed frame processing and storage recovery. A deliberate NFC history scan submits one decoded batch directly to the existing `ReadingStore`, sharing the established clock and sample-kind deduplication with BLE. Graph integration and upload workers remain next app work.

## Data flow

1. The serial Bluetooth queue assembles/decrypts/CRC-checks a frame and captures receipt time, generation, wear identity, calibration and clock in `LibreVerifiedFrame`.
2. `LibreTransportHandoff` offers that frame synchronously to the ordered mailbox before relaying diagnostic payloads.
3. One worker reconciles session metadata, decodes and maps accepted slots, then awaits a guarded store transaction.
4. `ReadingStore` commits readings and their delivery records atomically. Saved-value consumers query committed rows.

The worker retains at most **eight active plus queued frames**, drops newest on overflow and expires work after **120 seconds** before submission. Process sequences order callbacks and may contain gaps. Exactly one worker completes each frame before beginning the next; it does not reorder by sensor minute. These limits control work, not reading freshness.

Stop, reconnect, setup and replacement revoke the captured generation and purge pending work. An active item retains its reservation until it completes and must pass ownership checks before saving. The guarded writer's short epoch lock ensures revocation either prevents a transaction or follows its completed save. No network work runs on the BLE queue or writer.

## Existing Core Data model

The iOS 16.4-compatible `NSPersistentContainer` uses SQLite in Application Support with a serial writer context.

| Entity | Purpose |
| --- | --- |
| `StoredSensorSession` | Stable wear UUID/fingerprint, revision, observed dates, lifecycle and canonical sensor clock. |
| `StoredReading` | Unique `(sessionID, sensorMinute, sampleKind)`, integer mg/dL, sample/receipt dates, quality, origin and decoder provenance. |
| `ReadingDelivery` | One required row per reading; destination, state, frozen payload when queued, attempts and acknowledgement metadata. No destination means `unassigned`. |
| `UploadDestination` | Backend, endpoint identity, configuration revision, enablement and Keychain credential reference. |

The existing delivery relationship supports a single required destination per reading. The confirmed product needs multiple independently tracked destinations; extend this when implementing uploads. Delivery states and payload storage alone do not constitute a running uploader.

BLE live/recovery and NFC trend use `.trend` and deduplicate together. NFC 15-minute history has a separate kind. Prefer trend in future graph queries when both cover the same minute. Preserve gaps and equal values at distinct minutes.

For duplicates, integer glucose must match exactly and dates must agree within the configured tolerance (default one second). Agreement can merge origin flags. Conflicts preserve the first value, date, quality, decoder and frozen payload, and record a redacted diagnostic. This comparison tolerance is not an accuracy threshold.

## Wear identity and clock

`persistenceSessionID` is a random UUID retained across counter changes, peripheral discovery, calibration capture, reconnect and coherent same-sensor setup. UID and stable patch bytes identify the sensor; patch bytes 4–5 are mutable authentication/calibration inputs and excluded from stable identity.

Keychain migration saves a missing UUID before SQLite insertion. A restart between those operations reuses the saved UUID. The bridge verifies fingerprint and clock against SQLite metadata; an unexplained mismatch reports repair required. A new physical sensor gets a new wear UUID. Reconnect and recapture never retimestamp an existing wear.

For each sample:

`sampleDate = canonicalReferenceDate + 60 × (sensorMinute − canonicalReferenceMinute)`

Pairing secrets/counters remain in Keychain with `AfterFirstUnlockThisDeviceOnly`; the database stores reading metadata. The [decoder](ios-libre2-decoder-contract.md) checks input domains and the [clock notes](ios-libre2-live-state-clock-policy.md) explain sample versus receipt time.

## Transactions and recovery

One writer transaction validates the session, inserts missing readings, merges agreeing duplicates, records conflicts and creates required delivery rows. Save once, then publish inserted reading IDs in chronological order. Failed saves roll back and publish no reading. Local-only `unassigned` delivery rows are normal and must not appear as upload errors.

If save succeeds but publication fails, data is already durable. The adapter verifies at most seven transaction-specific keys and their required delivery records; it does not replay the frame. Latest-value refresh uses a bounded store query. Full-history snapshots are test/debug utilities, not the refresh path.

Storage errors surface with redacted operation/reason, time and dropped-work counts. The queue pauses/flushes unhealthy work and uses the existing bounded lifecycle retry budget (three attempts). BLE diagnostics can continue. An unreadable or full database is an error; it is not automatically deleted or downgraded to an unbounded in-memory buffer. During development the user may reset the database.

The directory, SQLite file and WAL/SHM sidecars use complete-until-first-user-authentication protection. Pairing and storage are unavailable before first unlock after reboot. Device metadata checks confirmed reopen/relaunch and one locked save/read/reopen sequence on the tested phone; real BLE reading persistence for the newly enabled path still needs a phone run. See [device observations](libre2-ble-testing.md).

Retain full-resolution history by default. The current synthetic sizing estimate is roughly 150 MB/year plus WAL/OS overhead. Future user-requested purge should show affected history and pending delivery scope; no automatic age-based purge is implemented.

## Tests

Run `./ios/Libre2Tests/run.sh`. It covers actual decoder-to-adapter storage, sparse overlap, reversed arrival, duplicate/conflict handling, immutable clocks, save failures, SQLite reopen, generation revocation, queue capacity/order and transport offer-before-diagnostics. Deterministic races exercise invalidation during preparation and writer admission. Hardware NFC/BLE and locked-device behavior are checked separately using [the practical device sequence](libre2-ble-testing.md).
