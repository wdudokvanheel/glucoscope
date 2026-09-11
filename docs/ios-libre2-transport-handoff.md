# Libre 2 transport handoff

`LibreBluetoothCentral` routes completed frames through `LibreTransportHandoff` into the app-owned ordered queue, adapter and reading store. Notification diagnostics retain metadata rather than packet hex. Other Bluetooth/status/error controls still use the existing event relay.

## Producer ordering

One serial BLE queue owns notification, completion, activation and invalidation calls. For each complete frame:

1. Assemble the 46-byte encrypted frame and decrypt/verify the 44-byte plaintext using the callback's captured session.
2. Pass raw and verified bytes to `completeFrame`, which checks length and CRC.
3. Create the immutable frame with `makeFrame`, then immediately call the mailbox's synchronous `offer`.
4. After the offer returns, retain and schedule the bounded diagnostic snapshot.

No asynchronous payload relay goes between sequence allocation and offer. `offer(true)` means retained for processing, not saved. Ownership is checked again by the worker and guarded writer.

A rejected offer clears pending diagnostic bodies and notification metadata. Bad plaintext can retain one bounded raw-only observation for debugging without offering a verified frame. Invalid lengths and inactive ownership clear bodies and increment their respective counters. Actual mailbox rejection increments `canonicalRejected`.

## Bounds

| Owner | Bound |
| --- | --- |
| Ordered mailbox | Eight retained frames including active work; FIFO, drop newest when full. |
| Pending diagnostic state | One latest 46-byte raw + 44-byte verified payload, metadata and counters. |
| In-flight diagnostic callback | One aggregate of the same size, reserved until its synchronous callback returns. |
| Relay payload bodies | At most 180 bytes across pending and in-flight aggregates; captured metadata and consumer copies are separate. |
| Notification logging | Byte count, receipt/source metadata and oversized indication; no retained notification payload or formatted hex. |

Repeated observations replace/coalesce pending state. A stalled diagnostic consumer retains at most one in-flight and one pending aggregate. Each drain handles one aggregate and schedules a successor asynchronously, avoiding an unbounded synchronous loop. The current display keeps latest frame/payload hex and a diagnostic result; those copies are outside relay accounting.

## Lifecycle and locking

Activation/invalidation revoke the generation, release its lock, purge the mailbox synchronously, then clear/update diagnostic ownership. Stop/setup/reconnect/forget invoke that route before returning. Active work and in-flight callbacks keep their reservations until completion; lifecycle changes cannot create a second worker.

Mailbox/relay locks cover short state changes only. No decoder, store, scheduler or consumer callback runs while they are held. Consumers recheck source sequence/generation before publishing current state because invalidation can occur after dequeue. Diagnostic publication is a currentness check; database commits use the separate guarded writer lock.

Construction does not activate the route or open storage. The collection coordinator starts the canonical owner. Offers before readiness are rejected; the handoff has no replay buffer and does not own storage retries. Receipt time is the transport wall-clock observation; the mailbox independently captures monotonic enqueue time for its residence bound.

## Verification

Portable fixtures exercise offer-before-relay order, rejection suppression, metadata-only notification storms, retention bounds, lifecycle purge, in-flight invalidation and drain wakeups. Fixture hooks compile only with `LIBRE2_TRANSPORT_HANDOFF_FIXTURES`. The ordinary runtime smoke uses the actual composition and decoder/adapter/store route. Synthetic routing tests supply raw/plaintext fixtures; the separate protocol tests check decryption.

See [storage and ingestion](ios-libre2-ingestion-design.md), [test instructions](../ios/Libre2Tests/README.md) and [current app work](ios-libre2-implementation-plan.md).
