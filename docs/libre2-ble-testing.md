# Testing the temporary Libre 2 connection screen

This build opens Libre 2 Diagnostics instead of the viewer/onboarding. It is a connection harness: it does not calculate glucose, write readings to a database, or upload to a backend. Existing viewer code and saved configuration remain available for later integration.

## Install and connect

1. Open `ios/GlucoScope.xcodeproj` in Xcode and select the GlucoScope scheme and an NFC-capable physical iPhone. The app deployment target remains iOS 16.4. Signing must include the Near Field Communication Tag Reading capability; the project supplies its `TAG` entitlement and Bluetooth background mode. If Xcode reports a provisioning-profile mismatch, enable the NFC capability for the app identifier and refresh the profile.
2. Run the app and grant Bluetooth access. Use an already activated EU Libre 2 sensor. The implementation recognizes `9D`, `C5`, and non-Plus `7F`; only one non-Plus `7F` has passed the initial connection test. Other sensor types are rejected.
3. Tap **Set up with NFC** and hold the top edge of the iPhone near the sensor until the NFC sheet finishes. This sends a streaming enable command, which can change which collector receives the sensor stream. Coexistence with the official app or another collector has not been tested.
4. Keep the app in the foreground for the first BLE discovery. Observe identity, Bluetooth state, service discovery, notification subscription, counter reservation and unlock acknowledgement in the diagnostic log.
5. Wait for multiple complete frames. Successful transport ends in **receiving CRC-valid frames**, with timestamps and an increasing valid-frame counter. A connected peripheral or successful unlock write alone is not sufficient.
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

For a failure report, include iPhone model, iOS version, sensor revision, action performed, elapsed time, whether another collector was active, and the diagnostic export. Never report a CRC-valid raw packet as a verified glucose reading.

## Validation boundaries

Simulator builds can check compilation, layout and unavailable-radio handling; they cannot exercise sensor NFC/BLE. Unlock, streaming, and a short locked-screen run passed on one non-Plus `7F`; range recovery, restoration, long-duration collection, glucose correctness, and per-revision compatibility remain. iOS force-quit requires reopening the app, and saved pairing state is accessible only after the first device unlock following reboot.

See [protocol and source provenance](libre2-eu-protocol.md) and [the full implementation plan](ios-libre2-implementation-plan.md) for the later calibration, glucose, persistence and upload work.

## Checks completed on 10 September 2026

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

This passes the initial short locked-screen reception check for this non-Plus 7F sensor and iPhone/iOS combination. Range-loss recovery, Bluetooth toggles, process restoration, reboot behavior and longer-duration collection remain untested.
