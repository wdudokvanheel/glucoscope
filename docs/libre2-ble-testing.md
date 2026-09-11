# Libre 2 testing

The current development build saves checked BLE slots into the existing local reading store and shows the latest 15 under **Saved experimental readings**. The detailed decoded-frame display remains separate. The user reports that v11 now commits live and recovered readings on the phone; relaunch and locked real-reading persistence remain to be checked.

## Software checks

From the repository root on a Mac:

```sh
./ios/Libre2Tests/run.sh
xcodebuild -project ios/GlucoScope.xcodeproj -scheme GlucoScope -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Commit `fe91b37` passed all 14 portable runs and the iPhone 16 / iOS 18.5 simulator Debug build under Xcode 26.2. The actual runtime composition saved two overlapping frames as 11 unique readings/deliveries, reopened SQLite with stable IDs/values/timestamps and loaded saved readings in a new coordinator before any packet arrived. The only build warning was the existing AppIntents absent-framework skip. The first v10 phone run exposed a fractional-timestamp comparison failure before storage; v11 fixes it, and the user now reports successful commits. The phone relaunch check remains.

The [test README](../ios/Libre2Tests/README.md) describes coverage and fixtures. Simulator compilation cannot exercise NFC/BLE. Use normal ad-hoc signing for simulator launches: a wholly unsigned app previously reported Keychain error `-34018`. Phone builds need development signing with NFC Tag Reading; the deployment target remains iOS 16.4.

## Next phone check

When resuming development-phone collection:

1. Build and launch. Confirm storage opens and any previously saved rows appear. Resetting the development database is acceptable if needed.
2. Reconnect the saved sensor, or deliberately use NFC setup if pairing needs it. Setup can change which collector receives the sensor; use it only when intending to switch collection.
3. Wait for frames. Confirm **Saved experimental readings** gains dated values and the accepted/saved status advances. An NFC success or CRC-valid packet alone does not demonstrate a saved reading.
4. Check overlapping packets produce one saved sample per sensor minute and leave sparse gaps. Compare the stored timestamps with the detailed frame's sensor-minute mapping.
5. Relaunch and confirm saved readings remain. During a short locked-screen interval, check new readings are saved and their timestamps appear after unlocking.
6. Stop collection and confirm new processing/reconnection stops. Saved history should remain visible.

For failures, include app revision, iPhone/iOS, sensor revision, action, elapsed time and an export via [the diagnostics host](diagnostics-host.md). Keep private exports out of commits. A physical comparison is useful when corresponding reference samples are available; it is not needed to keep building the app.

## Completed device observations

All observations below are from one non-Plus `7F` on iOS 18.7.8, app `1.0.6 (1)`, during 10–11 September 2026.

| Check | Observed result |
| --- | --- |
| NFC setup | Initial two attempts lost the tag at the empty `A1` patch query. A later scan read/validated all 344 FRAM bytes and enabled streaming on first read attempts. |
| Foreground BLE | `FDE3`/`F001`/`F002`, subscription and counter-1 unlock succeeded. Frames arrived in `20 + 18 + 8` fragments; the first two passed CRC 59 seconds apart. A continuation reached 28/28 valid frames over 27m 1s, with 58–62s intervals. |
| Locked reception | Five frames during a 5m 11s locked interval, spaced 62, 60, 59 and 60 seconds; no logged disconnect, additional unlock or CRC failure. The full 27-minute continuation was not all confirmed locked time. |
| Restoration | One `willRestoreState` callback restored the saved peripheral/calibration without NFC, reserved counter 2 once and received three valid frames. |
| Pending reconnection | After a timeout and 30m 59s valid-frame gap, the pending connection recovered without NFC and reserved counter 3 once. Subsequent intervals were 60, 60, 61 and 59 seconds. This was consistent with the user's range-loss/return report. |
| Sparse recovery | Reconnect frames contained older 12/15-minute slots. That diagnostic build did not save them and did not recover every minute of the gap. |
| Mutable patch word | The same sensor changed patch bytes 4–5 after setup. Corrected identity matching excludes those bytes; current FRAM decrypt uses newly read bytes while BLE retains the paired authentication patch. |
| Calibration recapture | Two corrected read-only scans retained pairing/peripheral/counter without streaming enablement or reconnect. One scan recovered after two transient tag losses. New frames continued after the first capture. |
| Stable clock | v5 retained sensor minute 4340 at 19:40:39 UTC across a capture at minute 4386 and relaunch. Overlapping sample times stayed equal; latest samples were 15, 16 and 15 seconds ahead of receipt. Counters advanced only for reconnect. |
| Numerical spot checks | The user reports two exact matches to their reference's preceding-minute display. No values/timestamps or demonstrated same-sample pairing were supplied. |
| Saved reading writes | The first v10 phone run verified a frame but committed no readings because of a fractional-timestamp comparison bug. The user reports that v11 now commits frames; phone relaunch remains unchecked. |
| Recovered historical comparison | The user reports that recovered readings from earlier times exactly matched their known-working xDrip/Zukka device at the corresponding times. No exported timestamped comparison dataset was supplied. |
| Metadata reopen/relaunch | Two v7 exports reported retained metadata across separate app launches, zero readings/deliveries and SQLite/WAL/SHM protection `completeUntilFirstUserAuthentication`. |
| Locked metadata storage | v8 saved/read/closed/reopened fresh synthetic metadata while backgrounded with protected data unavailable. All 14 checkpoints observed those states; files had the expected protection after save/reopen. The operation completed ten seconds after background entry, not continuously through the later 13m 49s background interval. |

The stable-clock fix followed recaptures whose implied start times moved by −6 and +22 seconds. Legacy sessions seed a missing clock once from saved calibration; malformed/foreign/out-of-lifetime anchors remain explicit repair cases. The ordinary valid-anchor sequence has device coverage; exceptional repair cases are covered by software fixtures.

## Remaining observations

Real BLE reading reopen and locked persistence are next. Broader reconnect/restoration, overnight use, reboot/first unlock, force-quit recovery and other sensor revisions remain useful device tests as development proceeds. Force-quit requires reopening the app; pairing/storage are available only after first unlock following reboot. No simultaneous-collector behavior is established.

The available runs do not establish glucose accuracy or general background reliability. [Decoder comparison notes](ios-libre2-decoder-evidence.md) preserve the numeric scope. Reference history was available for the user's reported manual comparison, but no timestamped comparison export was supplied.
