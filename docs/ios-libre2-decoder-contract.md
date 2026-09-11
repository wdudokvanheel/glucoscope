# iOS Libre 2 decoder

The ordinary `Libre2ProductionDecoder.decode` path validates frames, evaluates the existing engineering conversion and returns accepted slots for local development storage. `LibreCandidateAdapter` submits those slots to the existing SQLite store. There is no separate decoder mode or experimental database.

The algorithm is `libre2-nonlinear-production-v1`, policy `engineeringV1`, quality `engineeringChecksPassed-v1`. These identify the implementation and its checks; they do not claim tested clinical accuracy. Detailed math and provenance remain in [the protocol](libre2-eu-protocol.md).

## Frame inputs and checks

The decoder consumes an immutable `LibreVerifiedFrame`, reconciled `ReadingSessionSnapshot`, matching `Libre2DecodeOwnership` and policy. Captured bytes, identity, calibration and clock travel together; later pairing changes cannot relabel an old frame. The pure decoder performs no Keychain or database access.

| Input | Check |
| --- | --- |
| Ownership | Enabled matching generation, completed setup, captured session and durable wear UUID. |
| Integrity | Exactly 44 plaintext bytes; CRC over `0..<42` equals little-endian trailer `42..<44`. Normalize sliced `Data` before indexing. |
| Revision | EU `9D`, `C5` or non-Plus `7F`; reject Plus, US, incomplete and unknown patches. |
| Calibration | Format 1, ten compact source bytes, eight-byte UID, stable patch identity (excluding mutable bytes 4–5), lifecycle capture `02` or `03`, minute `0...20880` and valid date. |
| Clock | Format 1, matching wear/identity, supported provenance and 60-second nominal resolution. Use the reconciled SQLite mapping; no re-anchoring at receipt or recapture. |
| Dates | Finite metadata and receipt dates in inclusive epoch range `946684800...4102444800` (2000–2100 UTC), with coherent observation order. |
| Frame minute | Little-endian bytes 40–41, `referenceSensorMinute <= M <= 20880`. No minute-wrap extension. |
| Coefficients | `i2` in `1...1023`, `i4 > i3`, `i6 > 0`, finite coefficients and positive sensitivity. |

A whole-frame rejection returns zero slots and a redacted reason. CRC checks corruption, not identity; the transport owns identity binding. NFC lifecycle is a historical observation, and BLE bytes `28..<40` remain uninterpreted. See [sensor state and reading time](ios-libre2-live-state-clock-policy.md).

## Seven slot outcomes

Offsets are `0, 2, 4, 6, 7, 12, 15` minutes, in wire order. Each little-endian four-byte word at `4 × slotIndex` contains:

| Field | Encoding |
| --- | --- |
| Glucose G | Bits 0–13; `0...16383`. |
| Temperature T | Bits 14–25 × 4; `0...16380`. |
| Adjustment A | Bits 26–30 × 4, negative when bit 31 is set; `-124...124`, negative zero equals zero. |

For sample minute `S = M − offset`, reject negative minutes and warmup `S < 60` individually. Recovery slots may precede the reference minute. Derive `referenceDate + 60 × (S − referenceMinute)` with checked arithmetic and the same store date range.

Evaluate the full nonlinear equation with each slot's signed adjustment. Reject zero glucose/temperature, invalid division or logarithm domains, nonfinite intermediates and temperature outside `-10...60 °C`. Then require unrounded glucose in **20...600 mg/dL inclusive**, round once to nearest integer with ties away from zero, and recheck the integer domain. Thus 19.9 and 600.1 are rejected, 20 and 600 are accepted, and 20.5 becomes 21. No clipping, fallback, averaging or interpolation occurs. These are engineering bounds aligned with storage.

A bad slot does not discard good siblings. Evaluable frames return seven explicit outcomes even if every slot fails. The separate diagnostic decoder retains Double values in its broader `1...1000` diagnostic range; those transient results are not converted into persisted candidates.

## Persistence

The adapter prepares metadata from the captured frame, calls the ordinary decoder and maps only its accepted slots. Candidates use `.trend`, `.bleLive` for offset 0 and `.bleHistory` for other offsets. They carry the captured receipt time; the store derives sample dates from its canonical wear clock.

`LibreFrameGenerationGate` issues a revocable `ReadingCommitAdmission` bound to frame sequence, complete canonical session and receipt time. The store stages its transaction, then checks ownership and saves under the same short epoch lock. Revocation before save rolls back; a save that finishes first remains durable. The adapter rechecks after awaited work.

The [ordered worker](ios-libre2-ingestion-design.md) serializes frames; the store deduplicates `(wear UUID, sensorMinute, sampleKind)` and preserves the first committed value on conflicts. A successful save atomically includes each new reading and required delivery row. Zero accepted slots produce no reading transaction. The diagnostics screen loads its latest saved values from SQLite after startup and processing, using a bounded query of 15 readings.

## Verification

[Portable tests](../ios/Libre2Tests/README.md) cover ordinary decoder acceptance, structural/per-slot rejection, independent numeric expectations, rounding edges, ownership races, adapter mapping and persistence. Fixture compilation adds deterministic test hooks; the app does not need fixture flags to save readings. [Comparison notes](ios-libre2-decoder-evidence.md) describe the available numerical observations.
