# iOS Libre 2 live-state and clock-freshness policy proposal

**Documentation proposal, 11 September 2026. No runtime implementation or decoder promotion.** This document makes conservative engineering decisions reviewable. Its proposed numbers are unqualified screening thresholds, not measured error bounds, sensor guarantees, medical accuracy criteria or agreed UI/alarm settings. The [app experience plan](ios-ble-app-experience-plan.md) still owns the unresolved user-visible stale threshold and alert behavior.

Proposed policy ID: `libre2-live-state-clock-engineering-v1`. This identifies the complete rules and thresholds below, not a constructible or qualified production policy. Any changed threshold or acceptance semantics require an explicit version change and evidence review.

Read with the [production decoder contract](ios-libre2-decoder-contract.md), [ingestion design](ios-libre2-ingestion-design.md), [independent decoder-evidence protocol](ios-libre2-decoder-evidence.md), and [implementation plan](ios-libre2-implementation-plan.md). The normal production decoder remains closed for every recognized revision, including historical readings. Defining a policy does not satisfy its evidence requirements.

## Distinct facts and their owners

| Fact | Meaning and limit |
| --- | --- |
| Persisted NFC lifecycle | `LibreCalibration.lifecycle` is a CRC-validated observation at `capturedAt` and `sensorMinute`. `02` means starting and `03` ready in the current NFC contract. Either may supply calibration; neither proves the sensor's present condition. An old starting snapshot does not prove continuing warmup, and an old ready snapshot does not rule out a subsequent error. |
| App wear lifecycle | `ReadingSessionLifecycle.active`, `.ended` and `.replaced` describe the app's persisted wear record. Active is necessary for this ingestion path but does not assert sensor health. The writer prevents terminal-to-active regression. |
| BLE transport | Connected, subscribed, unlocked, CRC-valid receipt, and packet cadence describe communication. They do not establish live sensor validity or glucose freshness. A transport error is not evidence of an expired sensor. |
| Live sensor/sample status | A future revision-qualified interpretation must positively establish applicability and validity for the relevant frame/sample. The current parser has no such interpretation. In particular, bytes `28..<40` remain CRC-covered, uninterpreted bytes. |
| Canonical clock | `LibreSensorClockAnchor` and the matching SQLite clock define a stable mapping from a wear's sensor minute to UTC. Stability preserves identity and duplicate timestamps; it does not certify absolute time accuracy. |
| Process elapsed time | `LibreOrderedIngestion` uses `ContinuousClock` to bound work residence. It has an enqueue instant, not an independently measured sensor sample time. A wall-clock date or process sequence is not a substitute for this duration. |
| Canonical current eligibility | A future consumer may designate a successfully committed reading as current only after qualified status, clock, novelty and age checks. Origin `.bleLive` alone is insufficient. |

The current `LibreVerifiedFrame` contains payload, wall-clock receipt, sequence, generation, captured session and durable wear ID. It contains no frame-bound live-status evidence, monotonic receipt instant, phone-clock assurance record or cross-process elapsed-time proof. Existing decoder/context/admission types cannot express all proposed checks below. Do not infer those facts from a successful existing initializer or save.

## Proposed live-state rules

The following are proposed semantic states, not existing Swift cases or decoded byte assignments:

| State | Proposed canonical action |
| --- | --- |
| Unknown, unsupported or unavailable status evidence | Reject the entire new frame from canonical ingestion with zero accepted slots. Continue redacted diagnostics. Do not interpret absence of an error as ready. This is the state of the current implementation for all revisions. |
| Positively identified starting/not-ready state | No current designation. Admit no frame under the initial conservative policy. Retain the existing independent per-slot `S < 60` warmup rejection; crossing minute 60 alone cannot establish readiness. |
| Positively identified ready/valid state | Eligible for further checks only when the exact revision and status-policy version are qualified and the evidence covers the evaluated frame/slots. This does not bypass numerical, identity, clock, ownership or durable-write gates. |
| Positively identified error, shutdown, expired or other unsupported state | Reject new canonical ingestion and clear current eligibility immediately. Never infer this state from a gap, constant glucose, all-zero raw values or an over-age phone timestamp alone. No grace-period interpretation is authorized by this proposal. |
| App wear ended/replaced, collection stopped or ownership revoked | Reject work using that ownership and clear its current eligibility. Preserve committed history. A later callback cannot reopen the wear or reset readiness. |

Status evidence must be bound to the immutable frame, physical revision, wear and supported interpretation version. Initially require contemporaneous frame-bound evidence; there is **no positive cache lifetime for an old NFC lifecycle capture**. A deliberate NFC scan may provide research evidence, but a ready read does not grant a subsequent period of assumed BLE validity. Do not request repeated NFC automatically or promote a snapshot on a freshness timer.

For recovery slots, readiness at receipt does not by itself prove those earlier samples were valid when produced. Qualification must establish either trustworthy per-slot status or documented and independently checked frame semantics covering all supplied slots. If validity applies only to the newest slot, reject the uncovered historical slots individually. If the status interpretation cannot distinguish frame-wide validity from slot validity, reject the frame until that distinction is resolved. Future support for error states with recoverable history requires its own versioned review; it is excluded from this initial proposal.

## Stable timestamps and separate clock assurance

For sample minute `S`, retain exactly:

```text
T(S) = canonicalReferenceDate + 60 × (S − canonicalReferenceSensorMinute)
```

The decoder's checked arithmetic, store date domain (inclusive 2000-01-01 through 2100-01-01 UTC), whole-frame minute floor and `20880` ceiling remain in force. A frame with minute `M < referenceSensorMinute` fails as a whole; a recovery slot may precede the reference if its own minute/date and warmup checks pass. The ceiling is the current engineering ingestion domain, not proof of expiration timing or support for every minute in it. No counter-wrap extension is proposed.

SQLite's established clock remains authoritative for its wear. The existing 0.001-second reconciliation tolerance handles representation; it is not an absolute clock-error budget. `uncertaintySeconds == 60` and provenance `libre2-nfc-minute-clock-v1-u60` describe nominal NFC minute resolution. They do not bound capture latency, phone-clock offset, later phone correction or sensor drift. Two equal persisted anchors may be equally misaligned with actual time.

Clock assurance must be a separate, versioned evidence record, whose storage/API design is future work. It must bind the wear and unchanged canonical anchor to an independently supported UTC uncertainty interval, evidence source, observed interval and validity horizon. The interval must cover initial reference error, NFC capture timing/quantization, phone-time error, subsequent sensor drift and the receipt-clock relationship. An unknown contribution means unknown assurance, not zero. Do not derive a reassuring bound from the same packets being evaluated or by choosing the glucose/time alignment that best matches a reference.

For compact engineering fixtures a conservative symmetric bound `U ≥ 0` may represent the combined uncertainty of a receipt-minus-sample-time comparison. A future qualified implementation may use asymmetric intervals. **No usable `U`, maximum evidence age or drift horizon has been established for current hardware.** All such absent or expired assurance blocks new canonical acceptance, including history. A finite anchor date, automatic phone date setting, packet cadence or passing the screens below cannot create assurance.

A deliberate supported repair may restore a missing Keychain anchor from the exact matched canonical SQLite metadata. That copies a mapping; it does not improve its accuracy. Read-only calibration recapture, reconnect, relaunch, phone-clock correction, receiving a newer sample or receiving a late sample must never rewrite the established mapping. Existing same-wear setup's 120-second coherence check is a separate engineering repair rule and does not qualify clock freshness. An unexplained valid-anchor disagreement remains repair-required; do not split the wear or reinterpret a backward minute as proof of a sensor reset.

## Proposed engineering screens

These thresholds define an initial fixture/review target only. They must be versioned and supported by evidence before any production policy uses them. They do not choose the product's stale label, alert delay, alarm schedule or UI copy.

Let `R` be wall-clock receipt captured with the frame on the transport queue, `T` its canonical sample date, and `A = R − T` its **signed** age at receipt. Let `E` be nonnegative continuous elapsed time since that receipt, including sleep/suspension. With qualified combined uncertainty `U`, use the conservative age interval `[A + E − U, A + E + U]`; never replace `T` with `R`, clamp negative `A` to zero, or cap elapsed time to preserve eligibility.

| Screen | Proposed decision and exact boundary |
| --- | --- |
| Future lead | Require `A − U >= −120 seconds` for canonical sample acceptance. A possible lead beyond 120 seconds is a clock inconsistency and blocks the frame for clock review. Equality passes this engineering screen. It does not establish that a 120-second lead is accurate or acceptable to users. With missing assurance, acceptance already fails. |
| Current eligibility | For an otherwise qualified newest slot, require the complete estimated age interval at evaluation to lie within `[-120, 180] seconds`. Equality at either endpoint passes; an upper bound greater than 180 removes current eligibility. History has no 180-second admission cutoff. This engineering current-eligibility ceiling is separate from the unresolved user-visible stale/alert setting. |
| Wall/elapsed discontinuity | Capture paired wall and continuous times for a process comparison baseline. If `abs((wallNow − baselineWall) − continuousElapsed) > 5 seconds`, invalidate clock assurance for new admission and current eligibility. Exactly five seconds passes this detector, not clock qualification. Compare against a fixed validated baseline as well as event-adjacent pairs so incremental corrections cannot evade detection by resetting the baseline every frame. |
| Queue residence | Keep the existing independent inclusive 120-second enqueue-to-pre-submission limit and eight-frame capacity. It bounds backlog work, not sample age. A fresh packet can carry old slots; a short queue stay cannot make them current. |

The future-lead screen applies first to the frame's newest sample minute even if that numeric slot later fails, so an inconsistent frame cannot evade clock review by dropping offset 0. Each accepted slot still receives its date/domain checks. Old sample age alone is a history decision, not a reason to replace dates or reject all usable recovery slots. Nonfinite or negative monotonic durations are an invariant/clock failure and fail closed.

The v5 observations of newest sample dates 15–16 seconds ahead of receipt are compatible with a stable mapping and must remain signed observations. They are not evidence for a certified uncertainty interval or a 120-second production allowance. Similarly, the observed roughly minute-spaced frames motivate test scenarios but establish no general arrival guarantee.

## Current eligibility, novelty and history

All rules in this section are conditional on a future qualified decoder/status/clock policy and successful guarded persistence. The current ordinary decoder still accepts nothing.

1. Current eligibility is per active wear and collection generation. Only a valid offset-0 slot in a current frame can propose it under this initial policy. A slot received at a historical offset stays history even if its clock age is small. The `.bleLive` origin records the offset, not freshness or proof of novelty.
2. Keep a bounded in-memory high-water mark for the newest qualified offset-0 sensor minute and the original receipt/elapsed provenance of the current choice. Retain that mark across disconnect, reconnect, stop/start, calibration recapture and other generation transitions of the same wear; clearing current eligibility must not clear novelty history. A repeated or lower minute cannot refresh its timer, status evidence or clock assurance. Equal glucose at a higher valid minute may be new data; constant glucose is not a failure detector.
3. A frame below the current high-water mark but not below the canonical reference is not automatically a corrupt/replayed frame. Qualified missing slots may fill history through the normal unique `(wear UUID, sensorMinute, sampleKind)` keys. Equal duplicates add no new reading; conflicting duplicates preserve the first committed value and must not refresh current eligibility.
4. On a later valid higher minute, designate a current reading only after the writer's successful save and a current-generation/clock/status recheck. If a committed reading already exists identically because an earlier sparse slot supplied it, a qualified newer offset-0 observation may establish current eligibility without changing that row's timestamp/value, provided it also exceeds any process-gap durable floor described below. A duplicate alone is never evidence of a fresh observation; all novelty, frame-bound status and age checks still apply.
5. Recompute eligibility with elapsed time when consumers run and after any storage/publication delay. Never reset age to the commit time, refetch time, foreground time or successful upload. If the upper age bound exceeds the proposed ceiling, retain the committed value as history and remove current eligibility. No later packet with only rejected/old slots can undo that outcome.
6. Ineligibility is an ephemeral decision about using a reading as current. It neither deletes history nor retroactively labels a formerly admitted reading numerically invalid. Ownership/identity/integrity/status/clock failures instead block new canonical admission according to the relevant whole-frame or per-slot rule. A residence expiry drops queued work without diagnosing sensor health.

After relaunch, reboot or loss of the same wear's in-memory novelty state, perform a bounded canonical lookup of the maximum committed sensor minute for that exact wear before processing observations for current eligibility. Retain that maximum as a durable floor for this process's reacquisition. The first current observation must be strictly newer than the floor and pass all other gates; equal/lower frames may supply qualified history but cannot establish current eligibility. This deliberately waits for a new sample instead of reusing a recently committed value as current. Distinguish a confirmed empty wear from a failed/unavailable lookup: an empty wear has no durable floor, while an unsuccessful lookup leaves current eligibility blocked. The lookup and its ordering with admission require future implementation; do not scan/refetch unbounded history or treat a maximum cached before a process gap as current evidence. Combine the durable floor with the surviving in-memory high-water mark by taking the stricter bound whenever both exist.

The sequence high-water mark in the ordered mailbox is a separate process-local callback-order check. It cannot authenticate payload ownership, identify sensor samples or prevent a replay re-enveloped as a later callback. A CRC-valid repeated payload and delayed valid data can be indistinguishable with the current fields. Minute progression supports novelty screening but is not a qualified anti-replay mechanism.

The app experience plan separately confirms that historical/backfilled values do not trigger historical glucose alarms, and that sustained-high/low timers reset when current readings become stale and start a fresh qualifying duration when current readings return. A future consumer must honor that direction without counting an unobserved gap. This proposal does not settle the remaining user-visible stale threshold or implement alarm behavior.

## Discontinuities and recovery

| Event | Required proposed behavior |
| --- | --- |
| Timezone or daylight-saving display change | Leave UTC anchor, samples and elapsed age unchanged. A display-zone change alone is not a UTC discontinuity. |
| Wall clock moves forward/backward or a significant-time-change event arrives | Clear current eligibility and invalidate assurance before evaluating further work. Revoke affected in-flight admission or use an equally strong reviewed writer check; a decoder-only check before an await is insufficient. Pause/flush proposed canonical work while diagnostics continue. Existing history keeps original dates. |
| Small correction or gradual slew | Passing the five-second detector is not proof of accuracy. The independent assurance interval/horizon must still cover the change. If coverage is unknown or expires, fail closed. Do not silently absorb the correction into the anchor or reset the comparison baseline. |
| Background/suspension then foreground | Continuous elapsed time continues to age the current observation. Recheck wall/elapsed coherence, evidence horizon and age before presenting anything as current. Lack of background execution is not a freshness exemption. |
| Disconnect/reconnect | Revoke old-generation ownership and current eligibility. Preserve canonical history and anchor. A new connection or first CRC-valid packet alone restores no eligibility; require new qualified status/clock evidence and a qualifying current sample. Sparse slots can recover only their explicit minutes. |
| Process exit/relaunch or reboot | Start without a current verdict and without a reusable process-monotonic baseline. Refetch committed rows as history, reconcile exact wear/clock and establish new independently supported assurance before admission. Recover the bounded durable maximum minute and require a strictly newer sample before current eligibility, as specified above. Never subtract monotonic instants from different processes or infer clock continuity solely from persisted wall times. Process sequence restarts supply no replay guarantee. |
| Storage unavailable or save/publication failure | Follow bounded pause/flush/recovery rules in the ingestion design. A durable save with failed publication remains history; its storage-integrity checkpoint or later refetch cannot refresh current status. Refetch consumers need a separately reviewed bounded design. |
| Deliberate calibration recapture or supported same-wear setup | Preserve the original canonical mapping and wear ID under the existing coherence checks. Invalidate captured old-generation work and acquire fresh evidence. A newer calibration lifecycle is still a historical NFC observation. No automatic NFC or streaming-enable command follows a stale/unknown result. |

A new process cannot detect a wall-clock correction that occurred while the previous process was absent by using its own new baseline. After such a gap, stable anchor persistence alone is insufficient. The evidence protocol must define an independent reassessment with a supported horizon; absent that, the clock gate stays closed. Reassessment may validate the existing mapping or report disagreement, but may not re-anchor it. Resolving an established incorrect mapping would require a separate reviewed migration/repair design covering existing history and frozen delivery payloads; none is proposed here.

## Revision scope and promotion evidence

| Revision | Current evidence and proposed scope |
| --- | --- |
| EU non-Plus `7F` | One physical sensor has diagnostic transport/decode and bounded clock-persistence observations. No qualified live-status semantics, absolute-time assurance or independent timestamp-matched numerical acceptance. Closed. |
| EU `9D` and `C5` | Recognized by parser and synthetic fixtures. No supplied hardware qualification for these revisions. Each remains independently closed; evidence from `7F` is not transferred. |
| Plus, US, unknown or incomplete patch | Unsupported by the current contract. Reject; no fallback revision or shared-status assumption. |

Qualification must identify the exact supported revision/patch scope, numerical algorithm version, status interpretation, clock-assurance source/horizon and engineering policy version. If patch distinctions matter, evidence for a broad prefix cannot silently cover them. A new revision or changed interpretation requires a new explicit evidence review. Status and clock qualification are independent of agreement in glucose values; none is obtained by declaring thresholds or passing synthetic tests.

Required evidence before implementation/promotion can close these gates:

- Revision-specific status semantics, including not-ready, ready, error, terminal/unknown states and how validity covers sparse earlier samples. Document inaccessible states as untested; do not induce a hazardous condition to obtain them.
- Independently supported sample-time semantics, capture latency/quantization, phone offset and drift over a declared observation horizon. Use the decoder-evidence protocol's predeclared matching procedure; receipt/screenshot time is not sample time and best-fit time/value adjustment is not validation.
- Boundary fixtures for signed age, all proposed inclusive endpoints, unknown/expired uncertainty, future newest minute with rejected glucose, warmup/lifetime/date domain, old history, duplicate/conflicting/reordered slots and constant values at new minutes.
- A clock harness for forward/backward corrections, cumulative small changes, suspension, discontinuity during bridge/decode/save, process restart and missing assurance. Verify exact canonical timestamp equality across recapture/relaunch and that stale or revoked completions cannot restore current eligibility.
- Runtime handoff proof that paired wall/continuous receipt is captured before asynchronous dispatch, elapsed time includes suspension, status/clock invalidation reaches the serialized writer, and commit consumers recheck age/ownership before current designation. Existing generation admission does not currently bind a clock-assurance epoch or status result.
- User-owned device runs for the supported revision, including repeated reconnect/restoration, longer background intervals, clock reassessment across process gaps and the agreed comparison captures. The agent may compile; the user owns app execution. Existing v7/v8 isolated metadata results do not cover these boundaries.

No hardware action is needed to review this proposal. Future evidence collection needs explicit instructions for the user and must disclose any NFC setup or collector-switch dependency before it is attempted. There is no request here to switch away from the user's known-working reader. Production ingestion, normal current value/graphs and delivery remain gated while these evidence and implementation gaps are open.
