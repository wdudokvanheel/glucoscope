# iOS Libre 2 independent decoder evidence protocol

**Proposed protocol v1 — 11 September 2026. Documentation only; no qualification result or runtime promotion.** This defines the next evidence work from [the implementation plan](ios-libre2-implementation-plan.md) and [decoder contract](ios-libre2-decoder-contract.md). The normal production decoder remains closed for every revision. The user's successful build/run report and qualitative value comparison remain their original bounded evidence.

The procedure and software comparison rules below are defined. A physical run still needs a feasible acquisition method, reference configuration, timestamp semantics, matching window, coverage/count and device acceptance criterion recorded **before evaluation**. Those facts are currently unavailable; no numerical device run can pass yet. [The live-state and clock policy](ios-libre2-live-state-clock-policy.md) is a separate prerequisite: agreement between numbers cannot establish current sensor health or a trustworthy current-value age.

## Three distinct claims

| Evidence | What a passing result can establish | What it cannot establish |
| --- | --- | --- |
| Independent software oracle | Parsing/equation/quantizer conformance for specified inputs and versions. | Agreement with an official reader, physical measurement accuracy, current lifecycle or clock alignment. |
| Timestamp-matched reader comparison | Agreement with a named reader/configuration at its documented sample and display resolution, for the captured scope. | Clinical accuracy, official algorithm equivalence when the reference is unofficial, or correctness outside the observed revision/wear/conditions. |
| Qualification review | Whether separately documented numerical, lifecycle/status, clock, ownership and device evidence supports a specified future policy. | Automatic runtime enablement from this document or a device comparison alone. |

The selected full nonlinear equation differs from the supplied transmitter's rounded four-point bilinear path and its optional calibration adjustments. A comparison must identify which algorithm actually produced its reference values; “xDrip,” “Libre” or “my usual reader” alone is insufficient. A second display fed by this app, its backend or its copied calculation is not an independent reference.

## 1. Freeze a run manifest

Create a private, dated manifest and give its reviewed version an immutable identifier before scoring samples. Preserve later amendments as new versions; never relax a threshold or choose a different time shift after seeing differences and call the original run passing.

| Manifest field | Required content |
| --- | --- |
| Scope | Run ID; evidence class from the table above; EU revision (`7F` non-Plus, `9D` or `C5`); pseudonymous wear ID; planned wear phases and collection conditions. Excluded revisions stay excluded. |
| App | Repository commit and dirty-file hashes if any; app/build and OS/device version; diagnostic, production and policy identifiers; fixture/harness source hash and toolchain where used. |
| Inputs | Private artifact references/checksums for original frames and exact captured calibration/clock snapshots; calibration format, capture minute/date/lifecycle; canonical anchor format, reference minute/date and provenance. Missing data is recorded as missing. |
| Reference | Device/app/firmware/software version; acquisition method; algorithm and any smoothing, user calibration, extra slope/offset or cloud processing; original units, resolution and rounding; source of sample timestamps and their meaning. Mark undisclosed settings unknown. |
| Timing | Supported UTC clock offset/uncertainty for each source, how and when assessed, timestamp quantization/capture latency, allowed matching window `W`, ambiguity rule and any independently established fixed offset correction. |
| Coverage | Prospective run duration/stop rule, minimum unique matched sample count and wear count, required revision/wear/sequence strata, and maximum allowed missing/rejected/ambiguous fraction if the proposed decision uses one. None is established for physical qualification today. |
| Decision | Chosen metric and exact acceptance rule for the stated claim; rationale; reviewer and review date. Distinguish software equality, display-resolution agreement and any separate proposed device-accuracy criterion. |

Historical data can be exploratory. A protocol selected after inspecting that data does not turn it into prospectively collected validation. A subsequent independent set is needed for a newly selected rule.

## 2. Establish a reproducible software oracle

Use an implementation independent of the Swift decoder under test. Preserve its source, executable command, language/runtime and numeric precision, coefficient inputs, expected-output artifact and hashes. It must evaluate the documented equation from independently transcribed/reviewed inputs rather than invoke the app, share its coefficient helper, copy its output or generate expectations during the assertion. Sharing the documented equation is intentional; this is implementation independence, not independent empirical validation of that equation.

The existing five fixed expectations used Python Decimal at precision 60 and source coefficient entries, with calibration indices 1, 513, 720, 952 and 1023. The committed tests contain constants, and [the test README](../ios/Libre2Tests/README.md) describes their provenance. Do not imply that a reusable oracle generator or complete empirical corpus already exists. A new reproducible run must preserve its generator and input/output artifacts, and independently check coefficient regime boundaries rather than obtain expected coefficients from the helper shared by both Swift decoders.

For synthetic vectors, retain packed bytes and independently calculated decoded fields so matching numerical output cannot hide a shared parsing error. For private physical replay, bind each frame to its original captured calibration, wear and saved clock; later calibration or current pairing must not be substituted. A fixture-only offline harness may evaluate production engineering slots without enabling fixture flags in the app. The harness itself is future work, not implemented by this protocol.

Apply these existing engineering rules without enlarging their meaning:

- Raw fields, signed adjustments, sparse offsets/minutes, rejection reasons and outcome shape must match exactly. Whole-frame rejection has zero slots; otherwise all seven wire outcomes must be accounted for.
- For the existing independently calculated moderate-temperature vectors, use absolute `1e-8 mg/dL`, `1e-10 °C` and `1e-14` coefficient tolerances. New extreme or near-singular vectors require an independently reviewed precision/error analysis before assigning tolerances; those constants are not a universal floating-point error bound.
- Proposed canonical integer mg/dL must equal the independently computed integer exactly. Require unrounded `20...600` inclusive, round once to nearest integer with ties away from zero, and enforce the integer domain. A floating-point comparison tolerance never authorizes crossing a rejection or rounding boundary. Exercise exact ties and representable neighbors independently.
- Sensor minute and the canonical-clock timestamp expression must agree with independently derived expectations. Keep timestamp representation checks separate from physical clock accuracy. The bridge's 0.001-second reconciliation allowance and store duplicate tolerance are not evidence matching windows.

Record every mismatch; an unexplained mismatch fails the affected conformance claim. A passing selected vector set states its coverage explicitly, not “all inputs verified.” The ordinary production source shape must still return `unqualifiedPolicy` for otherwise valid frames on every recognized revision.

## 3. Choose a user-owned physical acquisition method

First establish what the user's usual reader can export or show: its exact model/app/version, units, original per-sample timestamps and their semantics, whether historical records remain available, and whether those records identify corresponding samples from the same wear. A previously retained reference history may be usable without a new sensor interaction if matching samples can be demonstrated. Separate sensors or a blood measurement do not identify the same sensor sample and cannot be silently mixed into the paired decoder dataset.

Two-phone coexistence and takeover are unqualified. A collector switch by itself supplies no paired evidence. This protocol requests no NFC setup, streaming enablement, collector switch, induced glucose change or interruption of the working reader. The user owns physical collection and app execution. If the available method cannot produce identifiable corresponding samples, mark acquisition blocked and continue only software evidence work. Review a concrete feasible method before asking the user to perform a device run.

The current diagnostic export is useful but incomplete for exact replay: it includes slot minute/time, raw glucose/temperature/adjustment and rounded glucose (`%.1f` mg/dL and `%.2f` mmol/L), with only the latest transient decoded frame retained. It does not preserve an unrounded Double or the compact calibration bytes needed for an independent full replay. The export's mmol/L is calculated using `18.0182 mg/dL` per `mmol/L`. Neither formatted number can reconstruct the original Double or reliably determine the proposed canonical integer near a rounding boundary. The normal production decoder yields no accepted canonical integer today.

Existing exports may therefore support explicitly rounded diagnostic/display comparisons when timing provenance is sufficient. Exact oracle replay and production-engineering comparisons need a separately reviewed private capture/offline evaluation mechanism retaining the necessary snapshots and precision. Do not expose Keychain secrets, enable app fixture flags or label a hand-rounded diagnostic export as a production result to fill that gap.

## 4. Match samples before comparing values

1. Normalize original reference times to UTC using recorded timezone/offset rules while preserving their original representation. Distinguish **measurement/sample time**, receipt time and screenshot/export time. The latter two cannot substitute for a missing reference sample time.
2. Derive app sample minute `S = frameMinute - offset` and UTC time from the immutable canonical anchor, `referenceDate + 60 * (S - referenceMinute)`. Record original receipt time separately and preserve its signed difference from sample time. Stable/reloaded anchors must map overlapping minutes identically; no re-anchoring to fit the reader is permitted.
3. Prefer a demonstrably common same-wear sample identity/minute where the reference actually exposes one. Otherwise, apply only the predeclared time rule using documented sample-time semantics and independently supported uncertainty. Nominal 60-second anchor resolution is not a bound on phone error or latency. The observed 15–16-second sample lead in v5 is neither a failure by itself nor a qualified offset correction.
4. For time-only matching, require each candidate pair to satisfy `abs(appSampleUTC - correctedReferenceSampleUTC) <= W`. Account for both sources' timestamp uncertainties in the predeclared method. If those uncertainties permit more than one reference sample for an app sample, or the reverse, mark the affected observations ambiguous rather than choose the closest value. If uncertainty cannot be bounded sufficiently to establish correspondence, timing remains unqualified even when displayed timestamps are close.
5. Freeze a one-to-one match table using identities/times before inspecting glucose differences. Do not search for a glucose-dependent lag, expand `W`, interpolate, average adjacent minutes or reuse one reference sample for several app minutes. Any independently justified time correction is comparison metadata; it never rewrites the canonical anchor or sample timestamps.
6. Count one unique `(wear, sensorMinute, trend)` pair in the main numerical denominator. Preserve overlapping/replayed observations separately; choose the earliest captured eligible app occurrence by a predeclared rule, never the closest-valued occurrence. Conflicting values for one minute remain discrepancies to investigate. Report live-offset and recovery observations separately; sparse repeats are not independent extra samples.

The 120-second mailbox residence bound controls engineering work and is unrelated to `W` or current freshness. A matched old recovery sample is still historical. Numerical matching does not override unknown live state or any clock/freshness blocker in the companion policy.

## 5. Compare in declared units without inventing accuracy thresholds

Retain original units and precision. Keep three distinct app quantities when available: unrounded diagnostic mg/dL, offline production-engineering canonical integer mg/dL, and formatted diagnostic display. Record unavailable quantities as unavailable. Compare the reference against the particular quantity named in the manifest; passing diagnostic display agreement does not establish canonical integer agreement.

For an unrounded software oracle, use section 2. For a rounded reader, reproduce its **documented** display transform on the chosen app quantity and require exact equality of displayed values for a pair to pass *display-resolution agreement*. This is a software/display claim, not a physiological tolerance. A rejected or `LO`/`HI`/error reference is categorical evidence; do not substitute a numeric endpoint or count it as a numerical match.

If conversion is needed, predeclare the reference-supported conversion factor and transform order. Preserve the app export's actual `18.0182` factor as provenance; do not assume every reader uses it. Unknown rounding/conversion semantics permit a descriptive difference report, not exact display agreement. With documented nearest-step rounding of size `q`, a displayed value corresponds to a quantization interval bounded by half a step, with endpoint inclusion determined by the documented tie rule. An app value inside that interval can establish consistency with that display bin; it does not gain an additional accuracy allowance. Do not stack `q/2`, a software error tolerance and an arbitrary physiological margin.

For each numerical pair report signed difference `app - reference` and absolute difference in the declared common unit, distinguishing a rounded display center from an unrounded reference. Summarize count, signed mean, mean absolute difference, maximum absolute difference and display-agreement count over the frozen matched denominator, alongside the full acquisition denominator. These are descriptive metrics. **No clinical accuracy threshold, percentage-error target, minimum physical sample count or acceptable mismatch fraction is adopted here.** They require a separate justified, prospective review for the intended claim. A finite run with all display bins agreeing may be reported exactly as that finite result; it does not qualify a revision for canonical use.

## 6. Preserve a private record and complete denominator

Use three linked private records; fields marked unavailable remain explicit rather than reconstructed from nearby observations:

| Record | Minimum fields |
| --- | --- |
| Frame/slot observation | Run ID, pseudonymous wear, frame/slot ID, process sequence/generation if captured, revision, source artifact reference, captured calibration/anchor reference, frame minute, wire index/offset, sample minute/UTC, receipt UTC, diagnostic/production/policy versions, raw or precise values if available, whole-frame or per-slot rejection reason. |
| Reference observation | Reference ID and source artifact, original value/unit/resolution/status, original sample time/timezone and UTC, clock uncertainty/correction provenance, capture time separately, reference configuration ID. |
| Match/decision | App and reference IDs; identity/time rule and manifest version; time delta/uncertainty; selected app quantity and any unit transform; signed/absolute difference and display result; inclusion/exclusion/ambiguity reason; reviewer and unresolved discrepancy. |

Retain original private artifacts unchanged and checksum them for audit. Keep UID, serial, wear UUID/fingerprint, calibration, payloads, exact glucose/time traces and screenshots out of the repository and routine logs; pseudonyms and hashes alone do not anonymize a glucose trace. Store the private mapping separately, use user-controlled protected storage and record access/retention arrangements. There is no automatic diagnostics upload under this protocol. Commit only methodology, synthetic fixtures and appropriately redacted aggregate review results without identifying traces.

Report acquired frames, whole-frame rejections, seven-slot outcomes for evaluable frames, unique observed minutes, repeated/conflicting occurrences, eligible unique app samples, reference samples, uniquely matched pairs and unmatched/ambiguous/rejected counts. Explain every exclusion by a stable reason such as missing input, unknown time, wrong wear, outside the declared window, ambiguous match, nonnumeric reference or decoder rejection. Keep rejected/nonmatching observations in the acquisition accounting; they must not disappear because only successful pairs are convenient to score. Seven slots in a frame are not seven new independent samples.

## 7. Coverage and review gate

Maintain one evidence ledger per **revision + decoder/equation + numeric policy + reference configuration**, with calibration/clock provenance and wear count. The present ledger is: one non-Plus `7F` with qualitative diagnostic hardware evidence; no passing timestamp-matched numerical set; no `9D` or `C5` physical qualification. Results from another revision, a rebuilt equation or an alternative reader algorithm cannot be silently inherited. A change assessment must identify which software vectors and physical observations need repeating; always retain the old version's verdict and scope.

Track synthetic coverage separately from ordinary-use observations. Synthetic coverage includes coefficient regimes, signed adjustments, raw/domain/CRC/identity failures, mixed outcomes, warmup and lifetime edges, quantizer boundaries, before-anchor recovery, and immutable clock/reload behavior. Physical coverage records observed wear phase, naturally occurring lower/middle/higher values under predeclared descriptive strata, stable/changing sequences, recovery and relaunch where actually observed. Empty categories remain gaps; no one should change food, medication, activity or reader use to fill them. Historical NFC lifecycle `02`/`03`, an app wear record marked active and uninterpreted BLE bytes `28..<40` do not establish live status.

An independent review records one of **conformance pass for stated vectors**, **display comparison completed for stated pairs**, **failed**, or **inconclusive**, together with missing coverage and exact artifact/manifest versions. Review checks provenance independence, reproducibility, predeclared timing and numeric rules, denominator accounting, all discrepancies and per-revision limits. Missing required inputs, ambiguous correspondence or absent required coverage is inconclusive; it cannot be waived into a pass by a favorable mean difference.

Runtime promotion requires a later explicit implementation/review that resolves numerical evidence for the proposed scope **and** the separate live-status, clock/freshness, cross-boundary ordering/ownership and transport handoff gates. No result in this procedure removes `qualificationBlockers`, enables canonical storage/graphs/uploads, or authorizes NFC ingestion. The immediate user input needed for a future physical plan is the usual reader's exact configuration and available sample-time/history evidence; no hardware verification action is requested by this documentation change.
