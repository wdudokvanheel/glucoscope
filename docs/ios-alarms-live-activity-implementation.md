# Standalone alarms and Live Activity implementation

Implemented against the confirmed [app experience plan](ios-ble-app-experience-plan.md). These features consume committed standalone readings. Viewer readings do not enter either service.

## Alarm requirements and evidence

| Requirement | Implementation / evidence |
| --- | --- |
| Multiple independent rules, including duplicate types | `GlucoseAlarmRule` identities; native alarm list; type-selection wizard, main settings, optional Advanced screen. |
| Starter high/low enabled; independent thresholds | First configuration copies `PreferenceService.bgLow/bgHigh` once. Subsequent graph edits do not change stored alarm thresholds. |
| High/low, sustained high/low, missing readings | `StandaloneAlarmEngine`; missing rules remain opt-in. |
| Shared settings and explicit overrides | Sound, requested DND override, snooze and recovery behavior each have nullable overrides. Every inherited control displays its resolved value. Repeat interval follows resolved snooze unless explicitly overridden. |
| Defaults and schedules | Automatic repetition; five-minute snooze; recovery stops repeats; DND off. Any active window applies. Each window supports Every day or all seven independent weekday checkboxes. Overnight windows belong to the starting weekday; equal endpoints mean an entire selected day. |
| Recovery, dismissal and snooze | Threshold-margin hysteresis; dismissal rearms only after recovery and a later crossing. Manual Snooze always checks the condition at expiry. Automatic repeats can continue after recovery when explicitly selected. Actions affect only their rule. |
| Sustained duration before a window opens | Current samples establish duration even while the rule is outside its window. Window opening evaluates that existing evidence. The timer does not retrospectively replay backfilled samples. |
| Stale gaps | Both a clock check and the next current sample detect the shared stale threshold. Sustained evidence resets across that gap. A dismissed episode remains dismissed until observed recovery. |
| Current/history boundary | Only fresh, monotonically newer `bleLive` trend observations enter the engine. Receipt time cannot make an old sample fresh. NFC observations, BLE history, out-of-order observations and future timestamps do not establish a glucose episode. The initial snapshot seeds only its newest eligible sample. |
| Notifications, sounds and individual actions | UserNotifications category supplies Snooze and Dismiss; foreground delivery uses the same category. Includes System, Gentle chime, Urgent pulse and Silent choices. The two original WAV resources are short mono PCM sounds. Notification permission is requested at deliberate sensor setup or from Alarm Settings, not over the introduction. |
| Background deadlines and cancellation | Pure engine projection prepares at most four notifications per rule, capped at 48 upcoming alarm requests across all rules, leaving capacity for setup notifications. Earliest deadlines win. Glucose projections never extend beyond the last observed sample's freshness; missing-reading projections shift when fresh samples arrive. Recovery, schedule changes, snooze, dismissal, deletion and mode changes remove obsolete requests. Unique request identities and generation/revision checks prevent a cancelled asynchronous request from removing a newer notification. |
| Durable episodes and history | Configuration, dismissed/active episodes, scheduled request identities and up to 30 days / 1,000 alarm events are persisted. History distinguishes a request or scheduled deadline from confirmed audible delivery. |
| Viewer switch | Stops the timer, clears runtime episodes, removes known pending/delivered standalone alarm notifications and rejects in-flight additions. Settings remain stored. |

The portable regression suite is `bash ios/StandaloneTests/run-alarms.sh`. It currently checks 93 temporal behaviors, including sustained hysteresis, stale gaps without clock callbacks, ordinary and overridden repeats, manual snooze, dismissal/rearming, weekday and overnight windows, immediate window-opening evaluation, history exclusion, independent simultaneous rules, restart persistence, mode shutdown and bounded native-notification projections.

The same runner also checks that a full 36-point / 12-hour Live Activity state round-trips between app and extension and remains under Apple's content budget (1,344 bytes including attributes in the fixture).

Two further independent portable suites exercise shared production policies:

- `bash ios/StandaloneTests/run-experience.sh`: 34 setup and statistics checks. Exact current-attempt/session, fresh live origin, new receipt and creation timestamps, Viewer exclusion, timeout/retry boundaries, restored timeout opt-out, canonical trend/history deduplication, initial 14-day window, Today boundary, all range fractions, time-weighted average/CV, and incomplete/empty coverage.
- `bash ios/StandaloneTests/run-reconnection.sh`: nine NFC intent identity checks. Reconnection rejects a different UID or stable patch identity before any pairing write or streaming-enable command, accepts mutable patch changes for the paired sensor, and leaves deliberate replacement and read-only capture behavior intact. These tests perform no physical NFC operations.

The statistics policy weights each observation by up to its native preceding sample interval (one minute for trend, 15 minutes for history), clipped to the previous observation and selected period. Mixed-cadence history therefore does not distort “time in range” into a raw sample-count fraction, and unobserved gaps do not count as recorded time.

## Chosen alarm defaults

- Recovery margin: **0.3 mmol/L**, editable from **0 to 2 mmol/L** in 0.1 steps. This is approximately 5 mg/dL. It is a small product hysteresis setting intended to avoid resetting on tiny threshold fluctuations, not a claim about sensor accuracy. The existing physical sensor record reports approximately one-minute BLE cadence (58–62 seconds), supporting the separate five-minute stale default. Margin suitability still needs observation with real readings.
- New sustained rule: **20 minutes**. New missing-reading rule: **10 minutes**. Both are independently editable.
- Missing-reading episodes begin from the latest qualifying live sample, or entry into standalone before any sample exists. A fresh live reading supplies recovery and rearms a dismissed missing episode. Recovery-repeat overrides continue to apply.
- General-setting changes affect future repetitions and inherited displayed values. A snooze already counting down retains its existing deadline; later snoozes use the new value.
- No additional alarm kinds were invented beyond the five confirmed types.

## Live Activity requirements and evidence

| Requirement | Implementation / evidence |
| --- | --- |
| Actual iOS presentation | WidgetKit extension `GlucoScopeLiveActivity`, `GlucoseLiveActivityWidget`, and shared `GlucoseActivityAttributes`. The app declares `NSSupportsLiveActivities`. |
| Value, trend, age and graph | Lock Screen and expanded Dynamic Island show mmol/L, trend, a system-updated age label and mini graph. Compact Island shows a value with stale strike-through; minimal presentation uses a status icon. Trend is unavailable when a suitable prior sample does not exist. |
| Opt-in and standalone lifecycle | Disabled initially. The service ends all its activities when disabled or entering Viewer, retains the preference and requests one again in standalone when the app is foregrounded. It adopts an existing activity across relaunch and removes accidental duplicates. |
| No readings and stale state | Before any local reading: “Waiting for a reading”. The last sample's timestamp supplies ActivityKit `staleDate`; stale state keeps the value/graph with “Outdated”, age and strike-through. The graph remains anchored to the last reading during an outage. |
| Three-hour default, adjustable | Choices: 1, 2, 3, 6 or 12 hours. Min/max sampling retains excursions within 18 time buckets, producing at most 36 points and keeping the ActivityKit state compact. Gaps longer than 20 minutes are not joined. |
| Existing theme framework | Follows the current `Theme` by default; independent choice uses the exact existing `themes.json` collection and theme swatches. Existing graph target colors/boundaries are supplied to the extension. |
| Lock-screen privacy — platform-limited; strict hide-until-unlocked behavior unverified | Visible by default. The optional privacy setting marks the value, trend, age and graph privacy-sensitive. The Lock Screen replaces system-redacted content with an unlock message, and the Canvas explicitly omits glucose paths under privacy redaction. Dynamic Island glucose views use the same privacy choice. This requests system privacy behavior; it cannot by itself enforce hiding until unlock independently of iOS/user settings. The confirmed strict privacy intent therefore remains a physical acceptance check, not a completed guarantee. |
| Cadence and recovery | Updates follow committed local snapshots and theme/settings changes; runtime reconciliation also runs every 30 seconds while executable. Data updates are deduplicated. If iOS ends the activity, foreground reconciliation requests a replacement; the settings explain that opening the app may be necessary. |

## Platform research and limits

Reviewed primary Apple documentation during implementation:

- [ActivityKit lifecycle and constraints](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities): an activity lasts at most eight hours; static and dynamic content together are limited to 4 KB. ActivityKit does not promise permanent “always show” presentation.
- [ActivityContent staleDate](https://developer.apple.com/documentation/activitykit/activitycontent/staledate): the system marks content stale at the supplied date.
- [Creating custom Live Activity views](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities): Lock Screen appearance and Always-On reduced luminance need appropriate presentation.
- [Widget extension privacy](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension) and [SwiftUI privacySensitive](https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:)): privacy-sensitive views participate in system privacy redaction. Actual locked-device rendering is controlled by iOS and user settings and must be verified physically.
- [Apple Platform Security: WidgetKit security](https://support.apple.com/guide/security/secbb0a1f9b4/web) documents that users control sensitive Lock Screen widget data under **Settings → Face ID & Passcode → Allow Access When Locked**. Settings provides that guidance and asks users to verify the result on their locked device. The cited documentation establishes WidgetKit's system behavior, not an unconditional ActivityKit-specific lock-state guarantee.
- [Scheduling local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app): iOS can deliver already scheduled requests while the app is not running; changing conditions require explicit cancellation.
- [Critical Alerts entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts): overriding mute/Do Not Disturb requires Apple's entitlement plus permission. This implementation does **not** add an unapproved entitlement. The requested preference is saved and clearly labeled unavailable until actual critical-alert permission exists.
- [Notification sounds](https://developer.apple.com/documentation/usernotifications/unnotificationsound): bundled notification sounds must use supported formats and remain under 30 seconds.
- [Core Bluetooth background execution](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html): background Bluetooth does not make application timers continuously executable. System termination and suspension remain possible. iOS 26 adds some Live Activity-related Bluetooth privileges, but this app does not depend on those to promise uninterrupted collection.

Native scheduling improves known upcoming deadlines, but it does not guarantee unlimited background repetitions. Once the prepared reminders are exhausted, another reading or app execution must replenish them. Future glucose notifications stop at the last sample's stale boundary. Focus, silent mode, notification authorization, user removal and system scheduling can affect presentation and sound. Removing notifications cannot be taken as proof that an already-started operating-system sound was interrupted.

## Required physical checks

Software tests do not validate a physical NFC/BLE connection or prove lock-screen delivery. Verify on supported iPhone/iOS combinations:

1. First live reading starts the expected independent alarms; late NFC/BLE history never sounds an alarm. Cross a threshold, hover within the margin, recover, dismiss, snooze and repeat across app foreground/background transitions.
2. A scheduled missing-reading alarm delivers while locked without BLE traffic; a new current reading cancels it. Check each selected sound and both notification actions after suspension and after process termination.
3. Schedule openings/closings, overnight weekday ownership, DST/time-zone changes, recovery and Viewer switching cancel all obsolete scheduled requests, including a mode switch during a pending `add` operation.
4. In Viewer, no standalone alarm notification appears and no Live Activity remains. Returning to standalone retains preferences without old repeat episodes.
5. Live Activity value, graph, age, theme changes and stale marking on the Lock Screen, compact/expanded/minimal Island and Always-On display. With privacy enabled, confirm that every glucose-derived view is hidden when locked and reappears after unlock.
6. Disable/re-enable iOS notifications and Live Activities; remove an activity manually; test eight-hour expiry and foreground recovery. Confirm the displayed status never implies delivery or Critical Alert capability that iOS has not granted.
