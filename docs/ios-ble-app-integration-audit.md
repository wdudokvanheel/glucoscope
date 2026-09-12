# iOS Bluetooth app integration audit

This audit maps the core application experience in
`ios-ble-app-experience-plan.md` to the integrated iOS implementation. Alarm,
Live Activity, and server-upload details have their own implementation audits.

## Mode, onboarding, and lifecycle

| Requirement | Integrated behavior and evidence |
| --- | --- |
| First-run Viewer or Bluetooth choice | `AppView` shows a themed two-choice mode screen when no mode is stored. Viewer enters the existing onboarding and main view; Bluetooth enters its own skippable onboarding. |
| Preserve Viewer | Viewer still uses `OnboardingWizard` and `MainView` with its original `DataSourceService` and `RealtimeDataService`. Its Settings adds only the mode destination. Viewer demo rendering was inspected in the simulator. |
| Full Bluetooth onboarding once | Completion is stored separately from mode. Relaunch and return from Viewer skip the introduction. A normal launch always initializes the selected standalone tab to Graph; tab state is not persisted. |
| Deliberate setup and first-reading verification | NFC starts only from a user action. A successful NFC scan creates a persisted attempt containing an attempt ID, reading-store session ID, sensor fingerprint, and start time. Verification requires a newly created and received current `.bleLive` trend reading for that exact session and attempt. Scan success alone never verifies collection. |
| Skippable wait | Skip and Continue enter the app without changing a waiting attempt to verified. The Sensor tab restores waiting, verified, timed-out, and failed outcomes. Collection continues after leaving onboarding when retry remains enabled. |
| Five-minute outcome | Successful NFC setup schedules an attempt-specific native timeout notification as well as an in-process check. Success, a new attempt, or Viewer mode removes obsolete timeout and success requests. Timeout content has an attempt-and-retry-specific identifier, and each add completion rechecks mode, exact attempt, preference, outcome, and current identifier so an asynchronous request cannot survive cancellation or overwrite a newer retry choice. |
| Retry choice and relaunch | Timeout notification and continued retry are independent, enabled-by-default settings. A restored waiting attempt is evaluated against its original deadline. A timed-out attempt with retry disabled does not reconnect automatically; deliberate retry remains available. |
| Reconnect versus replacement | Reconnect supplies the saved sensor identity to `LibreNFCSession`. UID and stable patch identity are checked before any pairing write or streaming-enable command. Replacement setup intentionally accepts a new sensor. |
| Viewer boundary | The collector is disabled from the persisted mode before `AppRuntime` constructs the BLE coordinator. Entering Viewer stops BLE/NFC work, recording, alarms, and Live Activity. Uploads stop claiming work after an in-flight request records its result. An upload warning appears when queued work exists. |
| Transition races | Each mode transition has a generation. Work after an `await` checks both generation and the authoritative stored mode. An obsolete transition does not perform a compensating upload state write; the newest transition owns the final state. |

`ReadingStore.commitStream()` is a broadcast subscription. Standalone display,
setup verification, and uploads therefore each receive every commit instead of
competing for values from one `AsyncStream` iterator.

## Standalone navigation and local data

| Requirement | Integrated behavior and evidence |
| --- | --- |
| Four native tabs | Graph, Stats, Sensor, and Settings use a themed native tab bar and navigation stacks. Settings' Sensor shortcut changes to the same Sensor tab; sensor management is not duplicated in another settings hierarchy. |
| Store-backed Graph | `StandaloneGlucoseService` loads the complete durable `ReadingStore` snapshot and refreshes from commit broadcasts. It selects canonical trend/history readings, supports the existing hour/window controls, and feeds the existing colored graph. Viewer values never enter this store. |
| Current and stale state | The latest stored value remains visible when outdated, with its sample-time age and reduced emphasis. Connection/setup attention is shown separately. The default stale boundary is five minutes and is configurable from 2–30 minutes; Graph, alarms, and Live Activity receive the same boundary. |
| Stats windows and defaults | Today, 7, 14, 30, and 90 days are available, with 14 days initially selected. The service keeps the full snapshot so the 90-day view is not limited by the store's short recent-reading convenience list. |
| Stats definitions | Time in/below/above/very-high range, average, and coefficient of variation use shared display thresholds. Observations are time-weighted by at most their native preceding cadence (one minute trend, fifteen minutes history), clipped at the previous observation and selected window. This prevents mixed-cadence sample-count bias and excludes unobserved gaps. Coverage reports sample count, covered time, and days with data. Each metric opens a plain-language definition. |
| Sensor status | Sensor shows configured state, inferred sensor-reported age when a valid clock exists, setup date, collection state, transport connection text, Bluetooth power state, last successful reading, and setup outcome. NFC history and calibration actions retain their read-only paths. |
| Redacted diagnostics | The user-facing log replaces the advertised sensor name, full UUIDs, and long hexadecimal identifiers. Complete diagnostic export remains a separate explicit action; automatic post-NFC upload defaults off. |
| Native settings and theme | Standalone settings groups UI, Theming, Server uploads, Alarms, Live Activity, the single Sensor destination, About, and Switch to Viewer. Screens use the existing `Theme` colors, assets, thresholds, and light/dark choice. |

## Chosen core defaults

- An unfinished setup restores its exact persisted outcome. Waiting attempts
  resume when still within five minutes. Past-deadline attempts apply the saved
  retry choice before reconnecting.
- A current setup sample may be at most 90 seconds before the NFC completion
  time to tolerate sensor-minute alignment. It must be newly created and
  received after the attempt, no more than 30 seconds in the future, and inside
  the configured freshness interval.
- Stats uses time-weighted observed coverage and population CV. CV needs at
  least two positive-weight observations. Empty or zero-coverage periods do not
  manufacture percentages.
- Returning standalone users always open Graph. Debug builds accept explicit
  launch arguments for deterministic screenshot tabs and Viewer demo data;
  these do not persist or change release behavior.
- Diagnostics upload is opt-in. Server reading destinations have independent
  consent and queues as documented in `ios-server-uploads-implementation.md`.

## Executable validation

The following checks passed on 12 September 2026:

| Check | Result |
| --- | --- |
| Full iOS BLE/store regression | `./ios/Libre2Tests/run.sh` passed all reported fixtures. `/tmp/glucoscope-final-libre-tests.log` |
| Setup and Stats policy | `bash ios/StandaloneTests/run-experience.sh` passed 34 checks. |
| Reconnect identity policy | `bash ios/StandaloneTests/run-reconnection.sh` passed nine checks. |
| Alarm and Activity policy | `bash ios/StandaloneTests/run-alarms.sh` passed 93 temporal checks and the shared 36-point Activity payload check. |
| Upload policy and persistence | `sh ios/ServerUploadTests/run.sh` passed store, transport, broadcast, and lifecycle smoke checks. |
| App and embedded extension | An iOS 16.4-targeted iPhone Simulator build compiled both targets, embedded `GlucoScopeLiveActivityExtension.appex`, and passed `ValidateEmbeddedBinary`. `/tmp/glucoscope-final-app-widget-build.log` |
| Signed simulator launch | The final locally signed iPhone 17 / iOS 26.2 build launched. This avoided the known unsigned-simulator Keychain `-34018` artifact. `/tmp/glucoscope-final-app-widget-build.log` |

Simulator render inspection covered mode choice, standalone onboarding, Graph,
Stats, Sensor, Settings, the unchanged Viewer onboarding, a populated Viewer
demo graph, and a normal returning-user launch. The clean standalone screens
showed useful empty states without a notification prompt. The returning launch
opened Graph after a prior forced Settings-tab capture. Captures are at:

- `/tmp/glucoscope-mode-choice-final.png`
- `/tmp/glucoscope-standalone-onboarding-clean2.png`
- `/tmp/glucoscope-returning-default-graph-final2.png`
- `/tmp/glucoscope-stats-final.png`
- `/tmp/glucoscope-sensor-signed-final.png`
- `/tmp/glucoscope-settings-consolidated-final.png`
- `/tmp/glucoscope-viewer-onboarding-final.png`
- `/tmp/glucoscope-viewer-demo-final.png`

The screenshots validate rendering and navigation states. They do not validate
sensor data, NFC, Bluetooth, background delivery, or locked-device behavior.

## Device and platform acceptance still required

No new physical-sensor observation was made during this integration. The
existing physical record in `libre2-ble-testing.md` remains the evidence for a
roughly one-minute BLE cadence, locked reception in the observed interval,
restoration, sparse recovery, NFC history, and retained readings. The following
remain acceptance checks rather than software claims:

1. Repeat complete onboarding, replacement, and same-sensor NFC reconnection on
   supported physical iPhones. Confirm the first current committed sample,
   success notification, five-minute timeout while suspended, late success, and
   retry opt-out behavior.
2. Verify ordinary reconnect/restoration, overnight and post-reboot/first-unlock
   storage, longer locked collection, repeat NFC-history deduplication, and
   history retention across relaunch. No simultaneous-collector behavior is
   established; the UI describes the rescan as intentional and conditional.
3. Verify alarm sound, action, schedule, stale-gap, and cancellation behavior in
   foreground, background, locked, suspended, and terminated states. Critical
   Alert / Do Not Disturb override is unavailable because the app does not have
   Apple's restricted entitlement.
4. Verify Live Activity Lock Screen, Dynamic Island, Always-On, stale, privacy,
   system expiry, user removal, and foreground recovery. ActivityKit controls
   lifetime and can end an activity; “always show” is a requested experience,
   not an uninterrupted guarantee.
5. Send to actual Nightscout and custom-server deployments, including auth
   failures, migration, long backfills, suspension, and Viewer switching. Local
   contract tests do not prove third-party availability.
6. Establish glucose accuracy with timestamped, same-sample reference data.
   Existing user reports and spot checks do not establish general accuracy.
