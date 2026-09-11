# Disconnected Libre 2 transport handoff contract

This document describes the engineering boundary implemented by `LibreTransportHandoff`. The component is uninstantiated: the app's Core Bluetooth producer and diagnostics consumers still use their existing paths. Synthetic fixtures for this component cannot establish that those runtime paths obey the contract. Decoder qualification, canonical runtime ingestion, normal graphs, upload and physical-device testing remain separate work.

The existing transport still emits a completed raw frame before `makeFrame`, dispatches raw and verified events independently to the main queue, and formats every F002 notification as full hex before dispatch. Limiting the eventual UI log array does not bound those queued captures. The new component provides a disconnected replacement seam; it does not fix that runtime behavior until an independently reviewed integration replaces the old relays.

## Producer and admission

One serial producer queue owns `notification(data:receivedAt:)`, `completeFrame(raw:verifiedPayload:receivedAt:)`, `control`, `activate` and `invalidate`. The component checks that these calls run on the supplied producer queue. The caller must supply an actually serial queue; queue identity alone cannot turn a concurrent queue into a serial producer.

For a valid completed frame, the required order is:

1. Assemble the 46-byte raw frame and decrypt/verify it using the same transport activation that owns the callback.
2. Pass the raw frame and optional 44-byte verified payload to `completeFrame`. Its length/CRC checks are defensive validation, not decoder qualification or proof that arbitrary caller-supplied plaintext came from that raw frame.
3. Call the shared gate's `makeFrame`, then immediately call the fixed canonical mailbox's synchronous `offer` with that exact immutable envelope.
4. Only after `offer` returns may the handoff retain completed raw/verified diagnostic payloads or schedule their relay.

No per-frame task, main-queue callback, diagnostic formatting closure or parallel preparation may be inserted between sequence allocation and canonical offer. Activation and decrypt/frame construction must share producer ordering so an old payload cannot be relabelled with a newer session snapshot. The component serializes its lifecycle calls with ingress; direct revocation of the shared gate elsewhere can still race a canonical offer. The next ownership check and guarded writer admission remain responsible for rejecting stale work.

The handoff carries the caller's wall-clock receipt date. It does not add a paired transport monotonic timestamp or qualify receipt latency; that extension is deferred. The canonical mailbox still captures its own monotonic enqueue instant for the existing residence rule.

An `offer` result of `true` means the mailbox retained work, not that decoding accepted candidates or a transaction committed. A cached currentness sample can allow an old offer to enter the mailbox after purge. The disconnected queue fixtures establish that it is rejected at the next ownership check and retains its reservation until then.

An `offer` result of `false` permits counters only for that completed frame. The relay clears pending raw/verified payloads and pending notification metadata; it does not turn canonical overflow, unavailable storage or another rejection into a second diagnostic payload queue. A callback already in flight cannot have its captured value forcibly reclaimed. Its consumer must recheck currentness before use.

`completeFrame` also returns `false` when no canonical offer occurred. The counters distinguish these cases: malformed lengths increment `invalidFrames` and clear pending bodies; an inactive gate increments `inactiveFrames` and clears them; a nil or CRC-invalid plaintext increments `invalidFrames` and may retain the bounded 46-byte raw observation alone for verification diagnostics. That raw-only case creates no verified envelope or canonical offer. Only `canonicalRejected` records an actual `offer(false)`. The raw-only exception does not authorize retaining a valid frame whose canonical offer was rejected.

## Separate retention bounds

| Owner | Bound and policy |
| --- | --- |
| Canonical mailbox | At most **8 retained frames total**, including the suspended active item; FIFO with drop-newest overflow. This bound is unchanged by diagnostic activity. |
| Diagnostic pending state | One aggregate with at most one latest raw frame of 46 bytes and one latest verified payload of 44 bytes, plus fixed metadata and counters. Repeated events replace/coalesce pending state. |
| Diagnostic callback in flight | At most one immutable aggregate with the same payload limits. Its reservation lasts through the synchronous consumer callback. |
| Total relay payload bodies | At most **180 bytes**: two aggregates × (46 raw + 44 verified). This is a relay payload-body bound, not a total process-memory estimate. Captured session metadata, canonical reservations, producer-local transient values and any copies retained by external consumers are separate. |
| Notification diagnostics | Fixed metadata only: source/generation, receipt time, byte count and an oversized indication. **Zero notification payload bytes or hex strings retained or formatted**, including before frame assembly completes. |
| Other diagnostic categories | Fixed-category counts/summaries for Bluetooth state, status, log, session change and error. No arbitrary message-string or payload-bearing log API. Counters saturate rather than grow an event history. |

The notification entry point accepts bytes only to record bounded metadata; a notification over 46 bytes produces an oversized indication without retaining its contents. Even a whole frame arriving in one notification cannot bypass canonical admission through a notification-hex relay. This deliberately changes the proposed handoff's diagnostic detail; it does not remove hex from the current runtime, which has no caller of this component.

These are ownership bounds. Sharing `Data` storage does not merge the canonical and diagnostic reservations into one eight-frame budget. Consumers that retain snapshots, launch a task per callback, or append payloads to an unbounded history create retention outside this contract. Future integration must account for their latest displayed snapshots and bounded logs explicitly.

## Lifecycle, locks and consumers

Activation and invalidation use this order: revoke/activate the shared generation gate, release its lock, directly purge the canonical mailbox, then clear pending diagnostic state and update diagnostic ownership. They finish that synchronous route before returning on the producer queue. An asynchronously delivered lifecycle event is not the purge mechanism. Future main-actor stop, setup, calibration and forget actions must route synchronously or report completion only after actual revocation and purge; this producer-only API is not an immediate-any-caller invalidation implementation. The canonical process-sequence high-water mark survives lifecycle changes.

The generation gate may acquire its private writer-ownership lock during revocation. The mailbox and diagnostic relay never acquire the generation gate while holding their own state locks. Relay locks protect only short state changes; there is no awaited work, scheduler call, decoder/store operation or consumer callback under those locks. Pending work is cleared together with its accounting. An active canonical item and an in-flight diagnostic callback retain their own reservations until completion; activating a replacement cannot start a second worker for either owner.

Diagnostic snapshots carry source sequence and generation. The relay checks ownership before handing a snapshot to its consumer, and the consumer can use `isCurrent` to recheck it. Any newer source event supersedes an older snapshot, even in the same generation. This is a currentness sample, not an atomic publication permit. Invalidation can happen after the relay's check or while a callback is blocked. Consumers must recheck immediately before current-state publication. Separate asynchronous consumer work must also recheck after suspension, and its retention is outside the relay bound. An already-performed external side effect cannot be undone by purge. No consumer callback runs while revocation is excluded. Canonical transactions instead use the separate guarded writer-ownership primitive.

## Drain and startup

All diagnostic categories share one pending aggregate and one coalesced drain reservation. Each drain invocation processes at most one aggregate. If updates arrive during its synchronous callback, they coalesce into the pending successor. The delivery helper returns and releases its snapshot before the outer drain clears the in-flight reservation or schedules a successor. Successor scheduling is asynchronous; there is no unbounded synchronous drain loop. Reservation and pending-state transitions are synchronized so an offer at the idle boundary cannot lose its wakeup or create a second drain.

There is no priority queue in which notification traffic can indefinitely displace status or error counters: each aggregate includes the cumulative category summaries. A newer source event may suppress an older snapshot; its counters remain available in the successor. The asynchronous successor yields execution between callbacks. This is bounded scheduling and category accounting, not guaranteed delivery of every observation or guaranteed progress of an external executor or stalled consumer. A stalled consumer leaves at most one in-flight and one pending aggregate.

Construction performs no activation, store opening or diagnostic scheduling. The canonical owner must be started explicitly; offers before it is ready are synchronously rejected under its existing state policy, with no replay buffer in the handoff. Activation may enqueue a bounded lifecycle summary. Storage failure and recovery remain owned by the canonical mailbox; diagnostic transport activity does not reset its retry budget or reopen storage.

## Validation and remaining integration

Portable tests can check synchronous offer-before-relay ordering, rejected payload suppression, the separate canonical and diagnostic bounds, metadata-only notification storms, lifecycle purge, in-flight consumer currentness, one worker and idle-boundary wakeups. The test scheduler and immutable `beforeDiagnosticCurrentnessCheck` hook belong only to `LIBRE2_TRANSPORT_HANDOFF_FIXTURES`; ordinary app source exposes neither. The hook runs after dequeue and outside relay locks, allowing a deterministic invalidation before the diagnostic ownership check. Record completed test/build results in the implementation plan and ingestion design, with their synthetic scope.

Actual runtime handoff remains unverified. Integration must route every producer and lifecycle path through this owner, replace the independent raw/verified/log dispatches, bound downstream display/export retention, and preserve the producer's fragment-assembly bounds. It must also retire or explicitly reconcile the metadata-only `LibreCollectionCoordinator`: its mutating metadata preparation, replaceable pending frame and separate retry budget must not run beside the candidate transaction path as another owner.

No sensor action or additional reader/export information is requested for this work. The user's two exact matches to the reference's preceding-minute value remain ordinary-use spot checks without numeric traces, timestamps or a demonstrated same-sample comparison. The reference has no timestamped history export, physical paired acquisition is unavailable, and this plumbing work supplies no new numerical, lifecycle/status or clock/freshness qualification.

See the [ingestion design](ios-libre2-ingestion-design.md), [implementation plan](ios-libre2-implementation-plan.md), [decoder evidence procedure](ios-libre2-decoder-evidence.md) and [live-state/clock policy](ios-libre2-live-state-clock-policy.md) for the surrounding gates.
