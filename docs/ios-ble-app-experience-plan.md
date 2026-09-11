# iOS Bluetooth/standalone app experience plan

> **Product direction only — user interview required before UI implementation.** This document records the requested iOS experience. It does not authorize UI source changes, runtime BLE ingestion, decoder promotion, sensor actions, notifications, Live Activities or upload behavior. Before any UI implementation begins, interview the user on the open decisions below and update this plan with their answers.

## Product intent

GlucoScope should offer two clearly separated modes without making the existing Viewer experience harder to use:

- **Viewer** retains the current app and current UI. It continues to show read-only glucose values obtained from Nightscout or the configured custom backend. Its only requested additions are a mode switch in Settings and the initial onboarding choice between Viewer and Bluetooth/standalone mode.
- **Bluetooth/standalone** collects from the user's sensor and presents a clear, easy, native iOS experience. The user specifically does not want the dense or difficult interaction style they associate with xDrip.

The two modes may share visual components such as the existing graph, but their data-source and lifecycle state must remain explicit. Viewer data must not be mixed into the standalone sensor's local history.

The user's suggested labels and wording describe intent, not fixed UI copy. Refine names and explanations freely for clarity while preserving the agreed behavior.

Visual polish and UI consistency are product requirements throughout the standalone experience. Continue using the existing theming framework and themeable SVG assets; extend the established visual system where needed rather than introducing a parallel theme or icon system. Use appropriate icons, the app's theme colors, consistent spacing and typography, and polished native controls and states. Keep screens clean and compact while giving them a cohesive, finished appearance. Preserve the agreed Viewer experience.

## Entry and onboarding

First-run onboarding asks the user to choose **Viewer** or **Bluetooth/standalone**.

Choosing Viewer enters the current Viewer app and leaves its existing navigation and screens intact. The first entry into Bluetooth/standalone offers full onboarding that explains, in plain language, how direct sensor collection works and guides the user through connecting their first sensor. Sensor scanning or streaming setup remains a deliberate user action.

### Confirmed interview decisions

The earlier wording that Bluetooth/standalone “always starts onboarding” is clarified by the user: **full onboarding happens only the first time**, not on every launch or mode switch.

- Returning users land directly on the graph after relaunch.
- Switching from Viewer back to Bluetooth/standalone remembers the previously configured sensor and setup. It does not repeat full onboarding; a brief connection check is appropriate only when attention is needed.
- Full onboarding explains the experience and includes a deliberate NFC scan, followed by a wait for the first sensor glucose value to verify that collection works. Scan success alone is not setup verification. The qualifying reading remains subject to the existing ingestion and freshness gates.
- Onboarding is skippable immediately, including the wait for the first value. Users can enter the app without a sensor and set one up later. Skipping must not falsely mark collection as verified.
- Skipping the wait leaves the already-started connection/collection attempt running while the user explores the app. Its progress and outcome remain available in the Sensor tab (the BLE menu), including sensor state, BLE connection state and the last successful reading.
- While waiting for the first value, show a plain-language waiting message, troubleshooting access and a **Continue to app** action. Setup remains unverified until the first qualifying reading arrives.
- Replacement sensors are set up from the Sensor tab: scan via NFC and wait for the first qualifying reading, without repeating the introductory explanations. The user can leave the setup screen while waiting.
- Initial setup, replacement setup and deliberate NFC reconnection share the same first-reading verification, success notification, five-minute timeout and retry settings. Request a native iOS success notification when the first qualifying reading for the current attempt arrives, or an error notification if no reading arrives within **5 minutes after successful NFC setup**. Five minutes is the selected product default under the user's delegated choice; validate it against actual sensor cadence and startup behavior before implementation. The user can opt out of the timeout notification in settings.
- **Keep trying after setup timeout** is a separate option, enabled by default. When enabled, continue connection attempts after the timeout and still send the success notification if the first qualifying reading arrives later. When disabled, stop automatic setup connection attempts at the timeout. This option concerns first-reading setup recovery; it does not define ordinary reconnection after an established sensor disconnects.
- Notification delivery remains subject to permission and platform validation; the Sensor tab also exposes setup state and outcome. Continuing attempts after timeout never overrides the requirement to stop collection when switching to Viewer.

Still to decide: how unfinished or timed-out setup resumes. Timeout-duration customization has not been requested; the confirmed settings are the timeout-notification and continued-retry opt-outs.

## Bluetooth/standalone navigation

Bluetooth/standalone uses a bottom tab bar with four primary destinations:

| Tab | Requested experience |
| --- | --- |
| **Graph** | Preserve the current Viewer graph's appearance and interactions, with a small sensor-status message only when something needs attention. Keep it clean and compact. Adapt its data source to committed local sensor readings only when canonical ingestion is qualified and connected. |
| **Stats** | Lead with time in range and include average glucose, time above/below range and glucose variability. Offer Today, 7, 14, 30 and 90 days, opening on 14 days. Show a simple overview with tappable details and plain-language metric explanations. The user welcomes further statistics that help them understand their glucose patterns. |
| **Sensor** | The single home for all sensor management, also referred to as the BLE menu. Show sensor state and age, BLE connection state, the last successful reading, setup progress/outcome, and NFC setup for a new sensor. Include sensor/BLE settings, redacted log access and **Reconnect sensor** via a deliberate NFC rescan of the existing sensor. |
| **Settings** | Replace the standalone settings experience with a clear native iOS-style menu of focused sub-screens. |

The standalone home experience should feel continuous with the current graph rather than like a diagnostics console. Connection and stale-data state must remain distinct from a current glucose reading.

### Stats direction

The confirmed starting set is time in range, average glucose, time above range, time below range and variability. The user requests useful insight beyond this set where appropriate; this is a direction to curate understandable statistics, not an agreed exhaustive metric list.

Confirmed time windows are **Today, 7, 14, 30 and 90 days**, with **14 days** as the initial selection. Lead with a simple overview; each metric can open more detail with a plain-language explanation. Use appropriate icons and theme colors consistently with the rest of the app.

Define range settings, variability measures, minimum data requirements and empty/incomplete-data presentation before implementation. Metric definitions and any clinical interpretation require later validation.

## Standalone Settings structure

Use a native iOS-style settings list with clear labels, standard controls and focused sub-screens for:

- **UI** — display and graph preferences.
- **Theming** — appearance choices, kept separate from functional settings.
- **Server uploads** — configure multiple Nightscout and/or existing custom-backend destinations, show each target's state independently, and provide per-destination history upload and diagnostics.
- **Alarms** — multiple independently configurable alarm rules, a small starter set, and a guided creation flow with optional advanced settings. Include high/low, sustained-high/low and missing-reading alarms; see the confirmed direction below.
- **Live Activity** — opt in to a persistent glucose display with current value, trend arrow, reading age and a mini graph; configure a separate theme if desired and optional lock-screen privacy.
- **Sensor settings** — the setup-timeout notification and **Keep trying after setup timeout** options are enabled by default and independently opt-out. All sensor management and BLE settings live in the Sensor tab; this supersedes the earlier separate Bluetooth management sub-screen in Settings. Any Settings shortcut should lead to that same destination.
- **About** — app, support and version information.
- **Switch to Viewer** — warn if readings are pending upload, pause standalone uploads, stop Bluetooth collection, scanning/reconnection and standalone recording, end the standalone Live Activity, then return to the Viewer experience.

This structure is an information-architecture request, not a promise that every feature is available under every iOS state. Notification timing, background execution, Live Activity refresh behavior, lock-screen presentation and supported OS/device combinations need later platform research, implementation and device validation. The UI must explain real limitations once those behaviors are known.

## Live Activity experience

### Confirmed interview decisions

- Show current glucose, trend arrow, reading age and a mini graph.
- Follow the app's theme by default, with an option to choose a different theme for the Live Activity. Reuse the existing theming framework and assets for both choices.
- The Live Activity is **opt-in**. Once enabled, the user's requested behavior is **“always show” within Bluetooth/standalone mode**. Viewer support is explicitly deferred. End the standalone Live Activity when switching to Viewer, retain the opt-in preference, and request it again on returning to Bluetooth/standalone, subject to validated platform lifecycle behavior.
- Once enabled, glucose is visible while the device is locked by default. Offer an option to hide glucose information until unlocked; the mini graph must follow the same privacy choice.
- When readings become stale, keep the last value and graph visible, clearly mark them as outdated and show the reading's age. Do not present the old value as current.
- The mini graph shows **3 hours by default**, adjustable in Live Activity settings.

“Always show” records the desired experience, not a guarantee of uninterrupted iOS presentation. Validate lifecycle, refresh, privacy and recovery behavior on supported devices before implementation, then explain any concrete limits in the UI.

Still to decide: no-reading presentation, the stale threshold, update cadence and acceptable recovery when iOS ends or limits an activity.

## Alarm experience

### Confirmed interview direction

- Support multiple independently configurable rules, including multiple rules of the same type. The user wants freedom to add different alarms as needed, rather than a fixed high/low pair.
- Start with a small set of sensible defaults. The user's suggested starter set is high and low alarms, with other types opt-in. Initially copy the user's graph target-range boundaries into the starter high/low alarm thresholds; after creation, alarm thresholds are independently editable rather than linked to later graph-range changes. Default durations and initial enablement still need definition.
- Include high and low alarms, sustained-high and sustained-low alarms with a chosen duration, and **No new readings for X minutes** with its own enablement and delay. Further alarm types remain to be selected.
- **Add alarm** uses a short wizard: choose a type with a clear explanation, configure its main settings, then optionally open advanced settings. Keep the basic path approachable while allowing detailed customization.
- Provide general alarm settings for shared behavior, including the default sound/ringtone, requested Do Not Disturb override, snooze duration and **Stop repeating on recovery**. Each alarm inherits the general setting unless the user explicitly overrides it for that alarm. Make inheritance and overrides clear in the UI. Every inherited setting must show its current resolved value, such as **Use default · 5 min**, **Use default · [sound name]** or **Use default · On**, never just **Default**. These displayed values must follow changes to the general settings.
- Advanced settings per alarm include active time windows (such as daytime or outside working hours), overrides for shared behavior, and either single-fire behavior or repetition every user-selected X minutes until dismissed or an applicable stop condition is met.
- **Stop repeating on recovery** is enabled by default as a general setting and can be overridden per alarm. With it enabled, repeats stop when glucose recovers; users can opt out to require explicit dismissal even after recovery. The exact recovery boundary should be consistent with the agreed threshold margin and validated before implementation.
- Sustained-alarm timers reset only once glucose moves a small distance back inside the threshold. While glucose hovers within that margin, the timer keeps counting. Expose the margin in Advanced settings; its default size and allowed values still need definition.
- Offer **Dismiss** and **Snooze** for the individual alarm, leaving other alarms active. **Dismiss** silences the current episode without disabling the rule. The rule can fire again only after glucose recovers beyond the configured margin and subsequently crosses the trigger threshold again, satisfying any configured sustained duration.
- **Snooze** temporarily silences that alarm for its configured duration, inherited from the general snooze setting unless overridden. The general snooze default is **5 minutes**.
- When an alarm's active time window ends, stop its ongoing repeats as well as preventing new notifications outside that window. This applies even if the alarm was configured to repeat until dismissed.
- When snooze expires, notify again only if the alarm condition still applies, respecting the configured recovery margin and active time window.
- Historical readings that arrive late or are backfilled update graphs and Stats without triggering glucose alarms about the past. Distinguish those readings from qualified current readings during alarm evaluation; timestamp/freshness rules still require validation.

The Do Not Disturb override is requested product behavior, subject to later iOS capability, entitlement, permission and device validation. Do not present it as effective until the supported behavior is established.

Still to decide: remaining default rule values and enablement (including margin size), additional alarm types, recovery/rearming for non-glucose alarms, schedule details (including what happens when a window opens), and handling gaps in current readings during sustained-alarm evaluation. Validate alarm timing and metric semantics before implementation, including the freshness boundary for excluding historical readings.

## Upload destination experience

### Confirmed interview decisions

- Initially support **Nightscout** and the **existing custom backend**, with multiple independently tracked destinations.
- Each destination's settings includes **Test connection** to check connectivity and authentication using the entered configuration. Show a clear success result or an actionable connection/authentication error. This is a configuration check, not an action to drain the upload queue; validate the appropriate check for each backend during implementation.
- A newly added destination receives only new readings by default. Offer an optional **Upload existing history** action with a selectable lookback, including **all available local history from the beginning**. The user accepts that a full-history upload can take a while.
- Historical upload uses committed standalone readings and delivery tracking for the chosen destination; it must not duplicate local glucose records or include Viewer data.
- Each destination's settings includes a useful **Debug** screen. It must allow the user to inspect all queued readings and a log of successful and failed send attempts, including useful error messages. Keep credentials and other secrets redacted from diagnostic output.
- Include a manual **Retry now** action when failed readings remain pending for that destination. The exact label may be refined; the intent is to retry pending failures on demand.
- Switching to Viewer pauses uploads as well as collection. Warn the user before switching if any readings remain pending upload. Preserve the queues for resumption when returning to Bluetooth/standalone; pausing does not discard pending work.
- At a switch to Viewer, allow an upload request already in flight to finish and record its outcome, but start no further upload requests or retries while in Viewer.
- When an individual destination is disabled, record when it was disabled. On re-enabling, offer to upload all locally available readings missed during the disabled interval, optionally starting at a user-selected date within that interval. Catch-up is a user choice, not an automatic upload of everything missed. Preserve previously pending delivery state; disabling does not silently discard it.
- When a destination's server address changes, explicitly ask whether to send its pending readings to the new address. Also offer a fuller backfill from a selected date, including the beginning of available local history, to support migration to an empty database. Treat pending-reading transfer and additional history selection as explicit choices. Updating only a password/token keeps the same queue.

Still to decide: destination naming/ordering and credential setup, history-upload progress/cancellation and diagnostic-log retention, and the fate of old pending work if transfer to an edited address is declined. The delivery design must distinguish a migrated destination's history from acknowledgements for the previous endpoint and avoid duplicate delivery work where selected pending readings and backfill overlap. Manual retries must respect the selected mode and destination state; they must not bypass the Viewer upload pause.

## Mode and data boundaries

Switching to Viewer must stop all active BLE collection, scanning, reconnection and new standalone recording, pause standalone uploads for every destination, and end the standalone Live Activity. Warn before switching when readings are pending upload. Preserve the paired-sensor record, committed local history and durable delivery state, including queued uploads for later resumption. An upload request already in flight may finish and have its outcome recorded; no further upload requests or retries start while in Viewer.

The request for multiple upload targets supersedes the earlier single-target assumption in the Libre 2 implementation plan. The current persistence model assigns at most one delivery row and destination to each reading, and the planned worker assumes one selected destination. Supporting multiple targets will require a separately reviewed schema, migration, uniqueness, payload-freezing, worker, retry, acknowledgement and per-target status design. Do not retrofit this as a UI-only preference or duplicate committed readings.

### Sensor reconnection

The user clarified that “restart” means **reconnect the existing sensor by scanning it again with NFC**, for example after it has been connected to another app or device. Use **Reconnect sensor** as the working label in the Sensor tab. This action is distinct from setting up a replacement sensor and does not request restarting sensor wear, clearing history or repeating full onboarding.

The intended outcome is to restore collection from the existing sensor. Reconnection shares the initial/replacement setup first-reading verification, notification, five-minute timeout and retry policy. The qualifying success must come from the current attempt, not a previously stored reading. Validate actual sensor-specific reconnection behavior, including any interaction with another collector, before promising that an NFC rescan can restore the connection. Confirmation needs and manual failure recovery remain to be resolved.

## Required user interview before UI work

Do not create UI code, wireframes presented as final, navigation state, notification schedules, Live Activity attributes or upload-target schema until the user has answered these topics:

1. **Onboarding and re-entry (partly answered):** Full onboarding is first-time-only and skippable, returning users go to the graph, and configured sensors are remembered across mode switches. Skipping the first-reading wait leaves collection attempts running, with state visible in the Sensor tab. Initial setup, replacement setup and NFC reconnection share first-reading success and five-minute timeout error notifications. Timeout notifications and continued attempts after timeout are independently opt-out; continued attempts still notify on eventual success. Resolve unfinished/timed-out setup resumption; validate the selected timeout against actual sensor behavior.
2. **Graph, tabs and Stats (partly answered):** Preserve the current Viewer graph's appearance and interactions with only a small sensor-status message when attention is needed. All sensor management belongs in the Sensor tab. Stats includes time in range, average glucose, time above/below range and variability, with room for further useful insights. Windows are Today, 7, 14, 30 and 90 days, initially 14 days; use an overview with tappable details and plain-language explanations. Resolve additional metrics, range settings and empty/incomplete-data behavior.
3. **Alarms (partly answered):** Multiple rules, a small starter set (suggested high/low; others opt-in), and a type → settings → optional advanced settings wizard are confirmed. Starter thresholds copy the graph target range, then remain independent. General sound, requested DND override, snooze duration and stop-on-recovery settings are inherited with per-alarm overrides; inherited controls show the current default value. Snooze defaults to five minutes and stop-on-recovery defaults on. Advanced controls include active time windows and single-fire/repeating behavior. Sustained timers keep counting within an adjustable threshold margin and reset further inside the range. Dismiss silences the current episode; recovery beyond the margin rearms the rule for a later threshold crossing. Dismiss/Snooze affect only the individual alarm. Repeats stop when the active window ends; snooze expiry re-alerts only if the condition still applies. Historical/backfilled readings update graphs/Stats without triggering historical glucose alarms. Missing-reading alarms are supported. Resolve remaining default values/enablement, remaining alarm types, schedule-window opening, non-glucose rearming and gaps in current readings. Validate platform support and freshness semantics.
4. **Multiple upload targets (partly answered):** Support Nightscout and the existing custom backend, with Test connection, queue inspection, success/failure logs and Retry now per destination. New destinations receive new readings by default, with optional history upload through all available local history. Switching to Viewer warns about pending readings and pauses uploads; an in-flight request may finish. Record destination disablement time and offer optional catch-up on re-enabling, from the start of the disabled interval or a selected date within it. Address changes ask about pending-reading transfer and offer a fuller backfill from a chosen date; credential-only changes retain the queue. Resolve naming/ordering and credential setup, history-upload progress/cancellation, diagnostic-log retention and pending work when transfer to a changed address is declined.
5. **Live Activity (partly answered):** Show current glucose, trend arrow, reading age and a mini graph (3 hours by default, configurable). Follow the app theme with an optional separate theme. Opt-in, then “always show” within standalone mode; Viewer support is deferred and switching to Viewer ends it. Glucose is visible while locked by default with an optional hide-until-unlocked setting. Keep stale values/graphs visible with an outdated label and reading age. Resolve no-reading presentation, stale threshold, update cadence and recovery when iOS ends or limits an activity. Validate lifecycle and privacy support.
6. **Sensor reconnection and recovery (partly answered):** “Restart” means an NFC rescan to reconnect the existing sensor, with **Reconnect sensor** as the working label. Use the same first-reading verification, notifications, timeout and retry settings as initial/replacement setup. Resolve confirmation needs and manual failure recovery. Validate sensor-specific behavior when another app/device has been connected.

Record the answers here as explicit decisions and identify any remaining platform or sensor validation before implementation. Use the interview to reduce steps and terminology; do not copy xDrip's navigation or expose protocol details merely because they exist in diagnostics.

## Implementation gate

UI implementation starts only after the interview is complete and its decisions are reviewed against the data-source, sensor-lifecycle, notification and delivery contracts. Runtime BLE connection remains separately gated by decoder evidence, live-status/clock-freshness qualification and the ingestion reviews in [the implementation plan](ios-libre2-implementation-plan.md). A polished screen must never make experimental or uncommitted glucose appear canonical.
