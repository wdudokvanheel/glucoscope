# Testing the temporary Libre 2 connection screen

This build opens Libre 2 Diagnostics instead of the viewer/onboarding. It is a connection and decoding harness: it can show transient experimental glucose calculations, but does not write them to a database, graph them, or upload them as readings. Existing viewer code and saved configuration remain available for later integration.

## Current source increment and next useful check

The transactional foundation was committed as `30c1ffc`. The user reports that it builds and launches without visible errors; no build log was supplied and no agent-run Xcode build was performed. That revision did not open the store, so the report did not exercise runtime persistence. Its expanded four-executable regression suite passed on 10 September 2026. The earlier v5 clock evidence below remains unchanged.

The current source identifies itself as **v8 locked-device storage-only probe**. V6 is committed as `8350127`, while its transactional foundation remains `30c1ffc`. V6 adds an immutable payload/session/calibration/clock envelope, synchronized rejection of stale callbacks, and an app-owned coordinator that opens protected reading storage at launch. V7 adds an explicit diagnostics action backed by a separately isolated SQLite store. It saves and verifies synthetic session/clock metadata only, requires zero reading and delivery rows, inspects the actual database/WAL/SHM protection attributes, and distinguishes reopen verification from a later-process relaunch verification. The first user-owned v7 reports verify retained synthetic metadata after reopen/relaunch and expected foreground file attributes.

V8 adds a second isolated store and explicit arm/cancel controls for one bounded locked-device sequence. Arming in the foreground obtains a temporary iOS background-task lease. The service proceeds only after directly observing both background state and `isProtectedDataAvailable == false`, then performs a fresh synthetic metadata save, read, close and reopen while checking those conditions at every boundary. Protected-data notifications are prompts to inspect current state, not evidence by themselves. Cancellation, expiration, foreground/protected-data return, or no qualifying observation is inconclusive. The probe performs no filesystem work at launch and has no sensor, NFC, BLE, reading, delivery or upload dependency. All seven portable executables, including the v8 lifecycle fixtures, passed on 11 September 2026. They verify control flow but cannot establish real iOS locked access. Experimental glucose remains unpersisted and canonical ingestion remains disabled.

On 11 September 2026 the user reported that v6 built, launched and showed **Collection storage: open and waiting**. No build log or diagnostic export was supplied. This is startup/store-open evidence only: no arriving frame or metadata-ready transition was reported, and it does not establish SQLite/WAL/SHM protection while locked, persistence across reopen or relaunch, or glucose accuracy.

The first user-owned physical v8 run below completes the bounded isolated locked-device storage check after first unlock. Production-store locked durability and access before first unlock after reboot remain untested. The disconnected production decoder is now implemented against [ios-libre2-decoder-contract.md](ios-libre2-decoder-contract.md). It validates the captured frame, caller-supplied ownership snapshot and reconciled canonical session; its normal entry point rejects every valid frame as `unqualifiedPolicy` with zero slots. A separate compile-time-only fixture entry point exercises seven sparse slot outcomes, canonical-clock dates and integer policy. The app target has no fixture flag, decoder caller or candidate adapter, and its diagnostic revision remains v8. This ownership comparison supplies no atomic writer-commit guarantee. The expanded `./ios/Libre2Tests/run.sh` passed all nine executable runs on 11 September 2026, including separate normal-gate and engineering-fixture builds; these are deterministic software checks only. Decoder promotion still needs independent timestamp-matched evidence plus lifecycle/status and clock/freshness qualification. Normal graph, upload and NFC ingestion remain unimplemented; no sensor action is requested for this source work. The existing isolated v7/v8 device checks do not need repeating for it. Xcode builds and app/device runs remain user-owned and unverified for the new decoder increment.

On 10 September 2026 the user reported switching the sensor back to their known-working CGM reader and that the diagnostic app values seem to match that device. No exact values, matched timestamps or tolerance were supplied. Record this as qualitative, unpaired evidence only; it does not qualify accuracy and does not call for switching the sensor again.

## First isolated storage-probe device result — 11 September 2026

The two latest user-owned reports were exported at 07:52:27 and 07:52:52 UTC from an iPhone on iOS 18.7.8 running app `1.0.6 (1)`. Both report **Relaunch verified**, metadata reopen/relaunch true and zero readings/deliveries. In both reports the retained SQLite, WAL and SHM files showed `completeUntilFirstUserAuthentication` before open and while the verification store was open. Diagnostics coordinator initialization at 07:52:12 and 07:52:42 UTC corroborates separate app launches.

The user may have repeated the actions. Both latest reports are later-process verifications of retained state rather than the original first-save export, so they do not reconstruct the first run's in-memory observations. Repetition is acceptable for the bounded retained-metadata result: the fixture remained valid across process launches, reopen and relaunch verification continued to pass, and no reading or delivery rows appeared.

The saved collector was still **Connecting**, Bluetooth was powered on, and both frame counts were zero. The instruction to stop it first was therefore not followed. The storage probe is isolated from BLE and production storage, so this does not invalidate the probe result, but it supplies no arriving-frame, sensor-takeover or coexistence evidence.

This result establishes only retained synthetic session/clock metadata across reopen/relaunch and observed foreground attributes for the isolated store. It does not establish locked-device or post-reboot accessibility, the production reading transaction, upload durability, BLE behavior, sensor ownership, glucose accuracy or decoder correctness.

## First locked-device storage-only result — v8, 11 September 2026

The first user-owned report was exported at 13:06:44 UTC from an iPhone on iOS 18.7.8 running app `1.0.6 (1)`. It reports **Locked storage verified**, **Locked verification attempted: true**, and **Locked write/read/reopen verified on iOS: true**. Collection was stopped as requested, Bluetooth was powered on, production storage was open and waiting for current sensor metadata, frame counts were zero, and canonical ingestion remained disabled with zero candidates.

The qualifying background entry occurred at 12:52:44. Ten seconds later, all 14 checkpoints directly observed both unavailable protected data and background state while the new isolated store completed its initial read, fresh synthetic metadata save/read, close, reopen and retained read. The sequence retained zero readings and deliveries. SQLite, WAL and SHM were initially absent because this was the store's first open; after saving and again after reopening, all three reported `completeUntilFirstUserAuthentication`.

The phone remained backgrounded until 13:06:33 and the report was exported at 13:06:44. That roughly 13-minute-49-second interval does not mean the probe continuously exercised storage: its bounded operation completed at 12:52:54. Leaving it locked longer does not invalidate the evidence and no repeat is needed. The ordinary v7 metadata reopen and relaunch fields are false in this export because the locked action resets those separate probe results; the v8 checkpoint record independently verifies its own close/reopen sequence.

This result establishes only a fresh isolated synthetic metadata mutation/read/close/reopen after first unlock on this phone and OS. It does not establish access before the first unlock after reboot, production reading or delivery durability, relaunch persistence of the in-memory verdict, BLE behavior, glucose accuracy or general background scheduling reliability.

For a future deliberate full setup, the new source retains UUID and original clock only when stable identity, minute and lifecycle evidence are coherent and capture time agrees within 120 seconds. Clock disagreement or uncertain same-sensor continuity requires repair before streaming enablement; the tolerance is an unqualified engineering policy. Missing saved calibration/clock directs read-only capture. Different physical sensors get new UUIDs. This setup behavior and actual Keychain migration still need hardware validation when testing them becomes useful.

## Install and connect

These are reference instructions for a deliberate future sensor test, not steps required for the storage-only probe or its later bounded device check.

1. Open `ios/GlucoScope.xcodeproj` in Xcode and select the GlucoScope scheme and an NFC-capable physical iPhone. The app deployment target remains iOS 16.4. Signing must include the Near Field Communication Tag Reading capability; the project supplies its `TAG` entitlement and Bluetooth background mode. If Xcode reports a provisioning-profile mismatch, enable the NFC capability for the app identifier and refresh the profile.
2. Run the app and grant Bluetooth access. Use an already activated EU Libre 2 sensor. The implementation recognizes `9D`, `C5`, and non-Plus `7F`; only one non-Plus `7F` has passed the initial connection test. Other sensor types are rejected.
3. Tap **Set up with NFC** and hold the top edge of the iPhone near the sensor until the NFC sheet finishes. This sends a streaming enable command, which can change which collector receives the sensor stream. Coexistence with the official app or another collector has not been tested.
4. Keep the app in the foreground for the first BLE discovery. Observe identity, Bluetooth state, service discovery, notification subscription, counter reservation and unlock acknowledgement in the diagnostic log.
5. Wait for multiple complete frames. Successful transport ends in **receiving CRC-valid frames**, with timestamps and an increasing valid-frame counter. With matching calibration, **Experimental glucose** then shows each accepted or rejected sparse sample. A connected peripheral or successful unlock write alone is not sufficient.
6. Use **Copy diagnostics** or **Share diagnostics** to save the result. The diagnostic dump includes sensor identity and packet bytes. Pairing unlock material is not included. Save the dump before ending a test; this first harness keeps a bounded in-memory log, not durable recording.

## Recovery checks

- Tap **Reconnect Bluetooth** while receiving frames: it should preserve the healthy stream and avoid repeated unlock writes.
- Walk out of range and return. The app should keep a connection request pending and reconnect without an NFC scan.
- Toggle Bluetooth off and on. Check that the diagnostic state changes and reception resumes.
- Lock the screen for several transmission intervals, then unlock and export the log. Compare frame timestamps for gaps.
- Tap **Stop connection**. Reception and reconnect attempts should stop; relaunch should respect the stopped state. **Reconnect Bluetooth** resumes the saved setup.
- Cancel the NFC sheet and retry. A pending or uncertain streaming setup must require another NFC setup, rather than automatically using partially saved credentials.
- **Forget sensor** removes saved pairing state. A new NFC setup is needed afterward. This does not reset or deactivate the physical sensor.
- A sensor scanned by another collector may require deliberate NFC setup again. Do not assume simultaneous collection works.

For a failure report, include iPhone model, iOS version, sensor revision, action performed, elapsed time, whether another collector was active, and the diagnostic export. Never report a CRC-valid raw packet or an experimental calculated value as a verified clinical reading.

## Validation boundaries

Simulator builds can check compilation, layout and unavailable-radio handling; they cannot exercise sensor NFC/BLE. Unlock, streaming, a short locked-screen run, experimental decoding, one `willRestoreState` launch, and one pending-connection recovery after a gap consistent with range loss passed on one non-Plus `7F`. Repeated recovery/restoration, long-duration collection, glucose accuracy and per-revision compatibility remain. iOS force-quit requires reopening the app, and saved pairing state is accessible only after the first device unlock following reboot.

See [protocol and source provenance](libre2-eu-protocol.md) and [the full implementation plan](ios-libre2-implementation-plan.md) for decoding details and the later persistence and upload work.

## Experimental glucose check

The user has built and run the experimental decoder and completed corrected read-only calibration recapture. A calibration change clears the prior diagnostic result; only a later CRC-valid frame is displayed with the new snapshot.

For each accepted slot, compare the displayed timestamp and value with the user's established glucose source at the same timestamp. Record both values and units, the sparse offset, sensor minute, and any rejected-slot reason. Compare matched timestamps rather than the time the BLE packet happened to arrive. A small set of matching values is useful diagnostic evidence, but does not establish clinical accuracy or qualify a sensor revision.

Check these failure paths without changing the active sensor where possible:

1. Before calibration, CRC-valid frames should report that calibration is required and show no experimental value.
2. After calibration, wait for a new frame; the screen must not reinterpret an older payload automatically.
3. Confirm all seven sparse positions appear as accepted or rejected, including zero or malformed raw slots.
4. Export diagnostics and confirm frame-level and slot-level rejection reasons are present without calibration source bytes or new credential material.
5. Forgetting or replacing the sensor must immediately clear the prior experimental frame.

## Checks completed on 10 September 2026 (connection revision only)

- `./ios/Libre2Tests/run.sh` passes the authentication, decryption, integrity and frame-assembly regression tests. See `ios/Libre2Tests/README.md` for synthetic-fixture provenance and limits.
- Xcode 26.2 Debug builds pass for iPhoneOS (unsigned compilation) and iOS Simulator (ad-hoc signed).
- The ad-hoc-signed build launches on the iPhone 17 Pro / iOS 26.2 simulator. The diagnostics screen displays, initial Keychain lookup succeeds, and the simulator reports Bluetooth unsupported/NFC unavailable as expected.
- The built iPhone app contains the Bluetooth/NFC usage descriptions and `bluetooth-central` background mode.
- Physical NFC/BLE and a short locked-screen run passed on one non-Plus `7F`, as recorded below. Radio restoration and longer collection have not been tested.

Simulator launches should use Xcode's normal ad-hoc signing. An entirely unsigned simulator build can display Keychain error -34018 because its application identity entitlement is missing; the signed build resolves this.

## First physical test: initial NFC connection loss

On 10 September 2026, an iPhone running iOS 18.7.8 detected and connected to an ISO 15693 tag twice, then reported `Tag connection lost` before the patch-info response was logged. The failure was at the initial `A1` patch query, before sensor classification, memory reads or streaming enablement. The export does not establish the sensor revision or the cause of RF loss.

The follow-up build identifies itself as `Diagnostics revision: NFC read recovery v2`. It adds bounded retries of read operations, same-sensor reacquisition within the NFC sheet, and step/error-code diagnostics. The streaming-enable write remains a single attempt because a missing response does not prove the sensor ignored the command. Retry setup deliberately if that write's outcome is uncertain.

When testing NFC recovery, keep the top of the iPhone by the sensor after the detection feedback until the sheet reports completion. If prompted to reposition, follow the message while leaving the NFC sheet open. Export the new log even if setup fails: it includes tag identity before the first command and the precise failed step and Core NFC error code. The later successful scan below used no retries, so the recovery paths themselves still require physical testing.

## First successful BLE test — 10 September 2026

The uploaded export at 18:10:23 UTC records successful setup on an iPhone running iOS 18.7.8 with a non-Plus `7F` Libre 2. NFC patch information and all 344 FRAM bytes were read on their first attempts, memory validation passed, and streaming enablement completed at 18:08:49 UTC. A manual Reconnect was tapped during discovery at 18:09:08; the sensor was matched at 18:09:22 with RSSI -71 dBm. This does not establish that the manual tap was necessary.

Service discovery, notification subscription and the counter-1 unlock completed at 18:09:23. Two frames arrived at 18:09:23 and 18:10:22 (59 seconds apart), each fragmented into 20 + 18 + 8 bytes. Both assembled to 46 bytes and passed decryption/CRC validation. The stored next unlock counter was 2. This is evidence for foreground connection and frame integrity on this one sensor, not glucose accuracy, background reliability or general revision qualification. Sensor identifiers and payloads are retained in the local diagnostic exports rather than copied into this document.

## Initial locked-screen test — 10 September 2026

The export at 18:16:39 UTC records background entry at 18:11:26 and foreground return at 18:16:37, matching the user's reported locked-phone test (5 minutes 11 seconds). Five complete frames were received and CRC-validated while backgrounded: 18:12:22, 18:13:24, 18:14:24, 18:15:23 and 18:16:23. Their intervals were 62, 60, 59 and 60 seconds. The session reached eight raw frames and eight verified frames overall. There were no logged disconnections, additional unlocks or integrity failures; the next unlock counter remained 2.

This passes the initial short locked-screen reception check for this non-Plus 7F sensor and iPhone/iOS combination. A later export records the first pending-connection recovery described below; Bluetooth toggles, reboot behavior, repeated restoration/recovery and longer-duration collection remain untested.

## Read-only calibration capture: first user-run result

The user-run v3 report exported at 18:37:13 UTC on 10 September 2026 (iOS 18.7.8, app `1.0.6 (1)`) confirms identity-checked read-only calibration capture and save at 18:37:13. Metadata reports format 1, sensor minute 4277 and lifecycle 3. No `A1/1E` enablement, stop or reconnect is logged during that capture. At that stage, automated test and Xcode build results for the increment had not been supplied and execution remained with the user.

At export, Bluetooth was powered on and foreground discovery had been running since 18:37:00. There were zero frames and no connection error in this 13-second snapshot. This is not evidence of BLE failure, and it does not yet show v3 frame reception.

The preceding v2 report records a deliberate full setup at 18:36:37–38 after 28 valid frames, leaving next unlock counter 1 and no discovered peripheral. The v3 report retains the same name, UID and patch information, with that same counter 1 and no discovered peripheral. Therefore this test does not establish migration preserving the pre-setup counter/peripheral, continuity of an active stream through calibration capture, or calibration persistence after relaunch.

The preceding v2 connection evidence separately extends to 28 raw and 28 CRC-valid frames from 18:09:23 through 18:36:24 (27 minutes 1 second), at 58–62 second intervals, without logged errors or CRC failures. Background entries at 18:11:26 and 18:16:42 were followed by continued reception; the whole 27-minute interval must not be described as a confirmed locked-phone test.

These continuation and relaunch checks were later completed in v5 as recorded below. Do not reset setup when repeating them on another build or sensor.

The earlier broader checklist was the basis for this sequence. Its ordinary same-sensor recapture and relaunch path is now covered once by v5; the exceptional cases and repeated runs remain open:

1. Upgrade over the working paired installation without deleting the app or tapping **Set up with NFC**. Confirm the existing sensor, peripheral UUID and next unlock counter survive, and calibration reports **Needs calibration**. Confirm BLE continues using the saved pair.
2. Record/export the current counter, peripheral, frame totals and timestamps. Tap **Read calibration with NFC** and scan the same sensor. Confirm logs show read-only capture and calibration saved, with no streaming-enable command, stop, reconnect or extra unlock attributable to this action. The empty `A1` patch query is expected; `A1/1E` enablement is not.
3. Confirm frame totals do not reset, new frames continue around the scan, and the peripheral/counter remain unchanged unless an independent Bluetooth reconnection advances the counter. If one occurs during the scan, confirm calibration completion preserves the newer counter/peripheral rather than restoring the pre-scan snapshot.
4. Relaunch and confirm calibration metadata is retained with the same saved pairing. A normal reconnect may reserve a new counter; calibration capture itself must never reset it.
5. Cancel a calibration scan and, if convenient without changing the pairing, present a different tag. Confirm failure/cancellation preserves the saved pair, calibration and continuing frames. Never use setup or forget as part of this same-sensor check.
6. Report the diagnostics revision, calibration summary/action status, frame timestamps and experimental slot outcomes. Queue/cancellation races, unavailable Keychain and a replaced session still need integration validation; synthetic fixtures do not establish hardware behavior or glucose accuracy.

## Mutable patch-word finding and corrected recapture

A later report exported at 19:26:27 UTC showed the same UID and stable patch bytes as setup, while patch bytes 4–5 differed after streaming enablement. Those two bytes feed FRAM decryption and Bluetooth authentication but are not stable physical-sensor identity. The earlier exact-patch check therefore rejected the same sensor before reading FRAM.

The corrected source compares the UID and every patch byte except 4–5 for ownership. It still requires supported patch records of equal length with matching trailing bytes. Read-only capture uses the newly observed bytes 4–5 to decrypt current FRAM and retains them with calibration provenance. It leaves the original paired patch, peripheral and counter untouched for BLE authentication; pairing-generation merge checks remain exact.

The report recorded six raw and six CRC-valid frames from 19:21:23 through 19:26:23, with intervals of 60, 61, 59, 61 and 59 seconds. Five arrived after the rejected read-only scan, with no disconnect or additional unlock. This supports stream continuity through the rejected scan; it does not validate corrected calibration capture or calculated glucose.

The corrected path subsequently completed two read-only captures from the same streaming sensor. Both validated all 344 FRAM bytes at lifecycle 3 and sensor minute 4340. The observed patch differed from the saved pairing only in bytes 4–5, and both saves retained the original paired patch, peripheral and next counter 3. No streaming-enable command, unlock, disconnect or reconnect occurred.

The first capture completed with seven raw and seven CRC-valid frames already counted; frame 8 arrived six seconds later, 59 seconds after its predecessor, and six of seven experimental slots were accepted. This demonstrates post-capture continuation for the first scan. The second capture recovered from two transient tag-loss responses and succeeded on its third patch-query attempt. Its export was taken ten seconds after saving, before another frame was due, so that snapshot does not independently demonstrate continuation after the second scan. The diagnostic sample display correctly cleared after each new calibration until a newer frame arrived.

Repeated capture also exposed a clock issue in the user-built v4 behavior. Both corrected scans observed the same sensor minute but were captured 22 seconds apart, so their inferred sensor-start anchors differ by 22 seconds; the first corrected anchor differed from the prior saved anchor by 6 seconds. The stable-clock v5 increment stores the first valid sensor-minute/date mapping separately and preserves it across recaptures and restarts so overlapping sensor minutes retain one timestamp. Calibration capture metadata still records each actual scan. Legacy sessions with valid calibration seed a missing anchor once; a present malformed/null anchor remains explicitly unavailable. A later source review found an inconsistent out-of-lifetime recovery case and now applies the 20,880-minute supported bound to anchor construction, decoding and stored-session recovery; deliberate recapture repair and boundary/null/malformed/foreign-anchor fixtures were added. The user has now built and run v5 through the ordinary valid-anchor sequence below, and the portable regression suite for the newest fixtures passes.

## First user-run experimental decode and restoration callback

The v4 export at 19:35:47 UTC records an actual Core Bluetooth `willRestoreState` callback at 19:33:31. The app retrieved the previously paired peripheral and retained the saved calibration without NFC setup, reserved counter 2 once, and advanced the next counter to 3. This demonstrates one successful restoration callback on the tested phone and sensor. That export alone does not establish recovery after process eviction, reboot, force-quit, or repeated restoration cycles; a later export supplies the separate first pending-connection recovery evidence below.

Three raw frames arrived and all three passed CRC validation at 19:33:31, 19:34:25 and 19:35:23, with intervals of 54 and 58 seconds. The decoder accepted seven of seven sparse slots in the first two frames and six of seven in the latest frame; its 15-minute slot was rejected because raw glucose was zero. The newest sample timestamps anchored to sensor time were 19:33:23, 19:34:23 and 19:35:23, respectively 8, 2 and 0 seconds before packet receipt. No errors or disconnects were logged.

The user reports that the displayed values seem in line with their established glucose source. This is useful qualitative feedback, but the export alone does not contain a timestamp-matched independent comparison or an agreed tolerance, so glucose accuracy remains unverified. Exact comparison values should remain in the local test record rather than this committed document.

## First observed pending-connection recovery

The user-run v4 export at 20:19:01 UTC records the last pre-gap valid frame at 19:43:25 and a Bluetooth connection timeout at 19:43:57, after which **Connecting** remained pending. The sensor connected at 20:14:24 without an NFC setup, reserved counter 3 once after the prior counter 2, and immediately produced a valid frame. Further valid frames arrived at 20:15:24, 20:16:24, 20:17:25, and 20:18:24. All 16 raw frames in the export were CRC-valid. The valid-frame gap was 1,859 seconds (30 minutes 59 seconds), and post-return intervals were 60, 60, 61, and 59 seconds. The latest transport frame also exposed its normal sparse 12- and 15-minute slots at 20:06:39 and 20:03:39. Those historical points are limited recent recovery, not continuous minute data, and the diagnostic build did not persist them.

The user describes roughly 15 metres of distance with several walls between sensor and phone and a return near 22:15 Amsterdam time. The duration is unknown and may have been about 30 minutes. The trace is consistent with one range-loss and return recovery, but it cannot prove the cause of the gap or exact return time. It establishes neither repeated recovery nor v5 persistent-clock behavior; the app was still v4.

## First user-run v5 persistent-clock sequence

After rebuilding and relaunching over the existing installation, the 20:26:22 UTC baseline export identified v5, restored the saved pair and showed three CRC-valid frames. Its saved clock reference was sensor minute 4340 at 19:40:39 UTC, matching the latest v4 calibration from which migration could seed the new field. The connection reserved counter 4 once, leaving next counter 5.

The user then deliberately tapped **Read calibration with NFC**. At 20:26:33 UTC the scan completed its reads on the first attempts, validated all 344 FRAM bytes at lifecycle 3 and saved calibration at sensor minute 4386. It logged no streaming-enable command, disconnect, reconnect or additional unlock. The next counter remained 5, while the saved clock remained minute 4340 at 19:40:39. As designed, the transient experimental result cleared until a newer frame arrived.

A CRC-valid frame arrived at 20:27:23 UTC, 50 seconds after the calibration save, and all seven sparse slots were accepted. Its overlapping sensor minutes retained the baseline timestamps derived from the unchanged clock. The user relaunched again at 20:27:59; the saved calibration and clock remained present, the connection reserved counter 5 once and left next counter 6, and a CRC-valid frame at 20:28:24 again accepted all seven slots. An overlapping sensor minute retained the same timestamp seen before relaunch. The newest sensor timestamps in the baseline, post-capture and relaunch exports were respectively 15, 16 and 15 seconds ahead of packet receipt. This is consistent with one stable mapping; its absolute alignment remains subject to the initial NFC minute-resolution and phone-clock uncertainty.

This passes one bounded recapture-and-relaunch persistent-clock test on the tested non-Plus `7F`. It does not qualify glucose accuracy, repeated recapture or relaunch reliability, the out-of-lifetime repair path on hardware, other hardware migration states, or other sensor revisions. Exact identifiers, payloads and glucose comparison values remain outside this document. The authorized `./ios/Libre2Tests/run.sh` execution also passed the protocol, integrity, fragment and diagnostic-decoder synthetic fixtures; that result is not physical accuracy validation. The isolated transactional foundation is now present in source as described above; runtime ingestion is the next implementation stage. Keep diagnostic calculations isolated from the viewer, production persistence and upload paths until the decoder and ingestion gates are met.
