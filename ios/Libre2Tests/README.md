# Libre 2 portable regression tests

Run from the repository root on a Mac with the Swift toolchain:

```sh
./ios/Libre2Tests/run.sh
```

The runner compiles app-owned Swift protocol, decoder, coordination and Core Data code into standalone executables. It needs no sensor, app launch, device Keychain or xDrip dependency. Persistence fixtures use in-memory stores or temporary SQLite files removed after each run. Expected corrupt-store tests print Core Data error 259 / SQLite error 26.

## Coverage

| Fixtures | Behavior checked |
| --- | --- |
| Protocol/assembly/NFC recovery | Authentication, BLE/FRAM decrypt and CRC, wrong identity, revision/counter boundaries, arbitrary fragment splits, overflow/timeout reset, transient read retries and cancellation. |
| Diagnostic decoder | Seven sparse offsets, packed fields, signed adjustment, invalid domains, mixed slot failures, warmup/lifetime/date limits, independent numeric expectations and persisted clock reuse. |
| Production decoder | Ordinary checked slot acceptance and rejection, ownership/calibration/session integrity, canonical dates, `20...600` integer policy and rounding boundaries. Fixture builds additionally expose isolated evaluation hooks. |
| Identity/persistence bridge | Stable wear UUID, save-before-return migration, restart between Keychain/SQLite operations, mutable patch word, clock reconciliation and rejected stale ownership. |
| Reading store | Sparse deduplication, reverse/concurrent arrival, conflicts, BLE/NFC trend overlap, distinct coarse history, atomic delivery records, rollback, publication failure and SQLite reopen. |
| Commit ownership | Revocation before save rolls back; a save winning the epoch lock remains durable. Exact duplicates also require current ownership. |
| Candidate adapter | Ordinary decoder-to-candidate-to-store path plus fixture-driven mixed rejection, provenance and conflict cases. |
| Ordered ingestion | Eight retained frames including active work, FIFO, drop-newest, 120-second residence limit, sequence gaps and deterministic invalidation races. |
| Transport handoff | Synchronous offer before diagnostics, rejected-body suppression, bounded relay, metadata-only notification storms and lifecycle/drain races. |
| Runtime composition | Actual coordinator/handoff/queue/adapter/store composition with synthetic frames; saved-reading refresh and reopen. |
| Storage probe | Separate synthetic metadata reopen/relaunch, injected lock/background state and cancellation. Device-only protection outcomes stay distinct from injected Mac behavior. |

The ordinary app path saves readings without fixture flags. Test-only flags expose deterministic barriers/evaluation helpers and are absent from the app target. The runner is the source of truth for executable selection; avoid maintaining a second per-revision test-count ledger here.

## Fixture provenance

UIDs and packets are synthetic. BLE plaintext is bytes 0 through 41 plus its reference CRC. FRAM follows `(index × 7) mod 256`, with lifecycle byte 4 set to 3 and independently computed section CRCs. Ciphertext/unlock expectations were checked against supplied reference functions in a temporary comparison harness. [Protocol source hashes](../../docs/libre2-eu-protocol.md) identify that reference.

Five glucose expectations were calculated independently using Python Decimal at precision 60, the full nonlinear equation and selected reference coefficient entries. The tests contain fixed constants. Absolute tolerances are `1e-8 mg/dL`, `1e-10 °C` and `1e-14` for coefficients at regime boundaries. Integer acceptance/rounding is checked exactly. CRC mutation fixtures use a separate unreflected polynomial recurrence.

The diagnostic algorithm `libre2-nonlinear-diagnostic-v2` and ordinary decoder `libre2-nonlinear-production-v1` share the documented finite coefficient reconstruction. The selected nonlinear equation differs from the reference transmitter's rounded four-point bilinear approximation. Software equality does not establish physical glucose accuracy.

Stable-clock fixtures model recapture shifts of −6 and +22 seconds while retaining sample minute 1000 at epoch 1700000000, including reload. Store and ownership fixtures inspect actual rows and commits after failures, rather than treating a returned success value as persistence proof.

For actual NFC/BLE, app relaunch, locked collection and phone storage, use [device testing](../../docs/libre2-ble-testing.md). Simulator compilation and portable tests cannot establish radio or UIKit scheduling behavior.
