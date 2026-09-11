# iOS Bluetooth/standalone app experience plan

This document records the user's confirmed standalone app choices and the remaining feature-specific decisions. Implement the agreed behavior incrementally; resolve open choices when reaching the relevant feature.

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
- Full onboarding explains the experience and includes a deliberate NFC scan, followed by a wait for the first sensor glucose value to verify that collection works. Scan success alone is not setup verification. Use a newly saved reading from the current setup attempt.
- Onboarding is skippable immediately, including the wait for the first value. Users can enter the app without a sensor and set one up later. Skipping must not falsely mark collection as verified.
- Skipping the wait leaves the already-started connection/collection attempt running while the user explores the app. Its progress and outcome remain available in the Sensor tab (the BLE menu), including sensor state, BLE connection state and the last successful reading.
- While waiting for the first value, show a plain-language waiting message, troubleshooting access and a **Continue to app** action. Setup remains unverified until the first qualifying reading arrives.
- Replacement sensors are set up from the Sensor tab: scan via NFC and wait for the first qualifying reading, without repeating the introductory explanations. The user can leave the setup screen while waiting.
- Initial setup, replacement setup and deliberate NFC reconnection share the same first-reading verification, success notification, five-minute timeout and retry settings. Request a native iOS success notification when the first qualifying reading for the current attempt arrives, or an error notification if no reading arrives within **5 minutes after successful NFC setup**. Five minutes is the selected product default under the user's delegated choice; check it against actual sensor cadence during device testing. The user can opt out of the timeout notification in settings.
- **Keep trying after setup timeout** is a separate option, enabled by default. When enabled, continue connection attempts after the timeout and still send the success notification if the first qualifying reading arrives later. When disabled, stop automatic setup connection attempts at the timeout. This option concerns first-reading setup recovery; it does not define ordinary reconnection after an established sensor disconnects.
- Notification delivery remains subject to permission and platform validation; the Sensor tab also exposes setup state and outcome. Continuing attempts after timeout never overrides the requirement to stop collection when switching to Viewer.

Still to decide: how unfinished or timed-out setup resumes. Timeout-duration customization has not been requested; the confirmed settings are the timeout-notification and continued-retry opt-outs.

## Bluetooth/standalone navigation

Bluetooth/standalone uses a bottom tab bar with four primary destinations:

| Tab | Requested experience |
| --- | --- |
| **Graph** | Preserve the current Viewer graph's appearance and interactions, with a small sensor-status message only when something needs attention. Keep it clean and compact. Adapt its data source to committed local sensor readings. |
| **Stats** | Lead with time in range and include average glucose, time above/below range and glucose variability. Offer Today, 7, 14, 30 and 90 days, opening on 14 days. Show a simple overview with tappable details and plain-language metric explanations. The user welcomes further statistics that help them understand their glucose patterns. |
| **Sensor** | The single home for all sensor management, also referred to as the BLE menu. Show sensor state and age, BLE connection state, the last successful reading, setup progress/outcome, and NFC setup for a new sensor. Include sensor/BLE settings, redacted log access and **Reconnect sensor** via a deliberate NFC rescan of the existing sensor. |
| **Settings** | Replace the standalone settings experience with a clear native iOS-style menu of focused sub-screens. |

The standalone home experience should feel continuous with the current graph rather than like a diagnostics console. Connection and stale-data state must remain distinct from a current glucose reading.

### Stats direction

The confirmed starting set is time in range, average glucose, time above range, time below range and variability. The user requests useful insight beyond this set where appropriate; this is a direction to curate understandable statistics, not an agreed exhaustive metric list.

Confirmed time windows are **Today, 7, 14, 30 and 90 days**, with **14 days** as the initial selection. Lead with a simple overview; each metric can open more detail with a plain-language explanation. Use appropriate icons and theme colors consistently with the rest of the app.

When the selected window has incomplete data, show available statistics with an explicit coverage note, such as **2 days of data available** for a 14-day selection. Do not imply that the full selected period was recorded. Choose range settings, variability measures, minimum data requirements and the empty state when building Stats. Explain metric definitions and avoid implying that incomplete coverage represents the entire selected period.

## Standalone Settings structure

Use a native iOS-style settings list with clear labels, standard controls and focused sub-screens for:

- **UI** — display and graph preferences.
- **Theming** — appearance choices, kept separate from functional settings.
- **Server uploads** — configure multiple Nightscout and/or existing custom-backend destinations, show each target's state independently, and provide per-destination history upload and diagnostics.
- **Alarms** — multiple independently configurable alarm rules, a small starter set, and a guided creation flow with optional advanced settings. Include high/low, sustained-high/low and missing-reading alarms; see the confirmed direction below.
- **Live Activity** — opt in to a persistent glucose display with current value, trend arrow, reading age and a mini graph; configure a separate theme if desired and optional lock-screen privacy.
- **Sensor settings** — the setup-timeout notification and **Keep trying after setup timeout** options are enabled by default and independently opt-out. All sensor management and BLE settings live in the Sensor tab; this supersedes the earlier separate Bluetooth management sub-screen in Settings. Any Settings shortcut should lead to that same destination.
- **About** — app, support and version information.
- **Switch to Viewer** — warn if readings are pending upload, pause standalone uploads, stop Bluetooth collection, scanning/reconnection and standalone recording, stop all standalone alarms and pending repeats, end the standalone Live Activity, then return to the Viewer experience.

This structure is an information-architecture request, not a promise that every feature is available under every iOS state. Notification timing, background execution, Live Activity refresh behavior, lock-screen presentation and supported OS/device combinations need later platform research, implementation and device validation. The UI must explain real limitations once those behaviors are known.

## Live Activity experience

### Confirmed interview decisions

- Show current glucose, trend arrow, reading age and a mini graph.
- Follow the app's theme by default, with an option to choose a different theme for the Live Activity. Reuse the existing theming framework and assets for both choices.
- The Live Activity is **opt-in**. Once enabled, the user's requested behavior is **“always show” within Bluetooth/standalone mode**. Viewer support is explicitly deferred. End the standalone Live Activity when switching to Viewer, retain the opt-in preference, and request it again on returning to Bluetooth/standalone, within iOS lifecycle limits.
- Once enabled, glucose is visible while the device is locked by default. Offer an option to hide glucose information until unlocked; the mini graph must follow the same privacy choice.
- When readings become stale, keep the last value and graph visible, clearly mark them as outdated and show the reading's age. Do not present the old value as current.
- The mini graph shows **3 hours by default**, adjustable in Live Activity settings.

“Always show” records the desired experience, not a guarantee of uninterrupted iOS presentation. Test lifecycle, refresh, privacy and recovery on supported devices and explain concrete limits in the UI.

Still to decide: no-reading presentation, the stale threshold, update cadence and acceptable recovery when iOS ends or limits an activity.

## Alarm experience

### Confirmed interview direction

- Support multiple independently configurable rules, including multiple rules of the same type. The user wants freedom to add different alarms as needed, rather than a fixed high/low pair.
- Start with **high and low alarms enabled by default**, with other types opt-in. Initially copy the user's graph target-range boundaries into the starter high/low alarm thresholds; after creation, alarm thresholds are independently editable rather than linked to later graph-range changes. Starter alarms trigger without a sustained delay, then automatically snooze and repeat unless dismissed or another applicable stop condition is met. Automatic snoozing uses the resolved snooze duration: **5 minutes by default**, following general-setting changes unless overridden for that alarm. The user selected automatic snoozing rather than the proposed single-fire starter behavior.
- Include high and low alarms, sustained-high and sustained-low alarms with a chosen duration, and **No new readings for X minutes** with its own enablement and delay. Further alarm types remain to be selected.
- **Add alarm** uses a short wizard: choose a type with a clear explanation, configure its main settings, then optionally open advanced settings. Keep the basic path approachable while allowing detailed customization.
- Provide general alarm settings for shared behavior, including the default sound/ringtone, requested Do Not Disturb override, snooze duration and **Stop repeating on recovery**. Each alarm inherits the general setting unless the user explicitly overrides it for that alarm. Make inheritance and overrides clear in the UI. Every inherited setting must show its current resolved value, such as **Use default · 5 min**, **Use default · [sound name]** or **Use default · On**, never just **Default**. These displayed values must follow changes to the general settings.
- Advanced settings per alarm include active time windows (such as daytime or outside working hours), overrides for shared behavior, and either single-fire behavior or repetition every user-selected X minutes until dismissed or an applicable stop condition is met.
- **Stop repeating on recovery** is enabled by default as a general setting and can be overridden per alarm. With it enabled, repeats stop when glucose recovers; users can opt out to require explicit dismissal even after recovery. Use the configured threshold margin for the recovery boundary.
- Sustained-alarm timers reset only once glucose moves a small distance back inside the threshold. While glucose hovers within that margin, the timer keeps counting. Expose the margin in Advanced settings; its default size and allowed values still need definition.
- Offer **Dismiss** and **Snooze** for the individual alarm, leaving other alarms active. **Dismiss** silences the current episode without disabling the rule. The rule can fire again only after glucose recovers beyond the configured margin and subsequently crosses the trigger threshold again, satisfying any configured sustained duration.
- **Snooze** temporarily silences that alarm for its configured duration, inherited from the general snooze setting unless overridden. The general snooze default is **5 minutes**.
- When an alarm's active time window ends, stop its ongoing repeats as well as preventing new notifications outside that window. This applies even if the alarm was configured to repeat until dismissed.
- When an active time window opens, evaluate immediately and sound the alarm if its conditions are already met. Qualified current readings from before the window opens count toward a sustained rule's required duration, with the same recovery-margin and stale-gap reset rules. For example, a **high for 20 minutes** rule becoming active at 09:00 sounds immediately if valid readings establish that condition from 08:40. This evaluates the condition at window opening; it does not permit later backfills to trigger retrospective alarms.
- When snooze expires, notify again only if the alarm condition still applies, respecting the configured recovery margin and active time window.
- Historical readings that arrive late or are backfilled update graphs and Stats without triggering glucose alarms about the past. Distinguish those readings from current readings during alarm evaluation; use sample time and reading age.
- When current readings become stale, reset any sustained-high/low timer. Start a fresh qualifying duration when current readings return; do not count an unobserved gap as continuous high/low glucose.
- Alarms apply only to Bluetooth/standalone mode for now. Switching to Viewer stops **all standalone alarms**, including active sounds, automatic snoozes, repeats and pending alarm notifications, while retaining rule settings for return. Future Viewer alarms would use the Viewer data source; that extension is explicitly deferred.

The Do Not Disturb override is requested product behavior, subject to later iOS capability, entitlement, permission and device validation. Do not present it as effective until the supported behavior is established.

Still to decide: remaining default values (including margin size), additional alarm types, recovery/rearming for non-glucose alarms and detailed schedule controls. Test alarm timing, historical-reading exclusion and sustained-timer resets during implementation.

## Upload destination experience

### Confirmed interview decisions

- Initially support **Nightscout** and the **existing custom backend**, with multiple independently tracked destinations.
- Each destination's settings includes **Test connection** to check connectivity and authentication using the entered configuration. Show a clear success result or an actionable connection/authentication error. This is a configuration check, not an action to drain the upload queue; validate the appropriate check for each backend during implementation.
- A newly added destination receives only new readings by default. Offer an optional **Upload existing history** action with a selectable lookback, including **all available local history from the beginning**. The user accepts that a full-history upload can take a while.
- Historical upload uses committed standalone readings and delivery tracking for the chosen destination; it must not duplicate local glucose records or include Viewer data.
- Each destination's settings includes a useful **Debug** screen. It must allow the user to inspect all queued readings and a log of successful and failed send attempts, including useful error messages. Keep credentials and other secrets redacted from diagnostic output.
- Include a manual **Retry now** action when failed readings remain pending for that destination. The exact label may be refined; the intent is to retry pending failures on demand.
- Send queued readings in **reverse chronological order (newest first)**, including history backfills. Show progress with the date/time of the reading currently being sent and the target start date being worked back toward.
- Provide **Pause**, **Resume** and **Cancel remaining upload**, plus the ability to **Clear upload queue** for the selected destination. Cancel/clear removes the selected pending upload work while preserving local history and readings already sent; it cannot undo remote uploads. Keep clear-queue behavior distinct from temporarily pausing or disabling a destination.
- Switching to Viewer pauses uploads as well as collection. Warn the user before switching if any readings remain pending upload. Preserve the queues for resumption when returning to Bluetooth/standalone; pausing does not discard pending work.
- At a switch to Viewer, allow an upload request already in flight to finish and record its outcome, but start no further upload requests or retries while in Viewer.
- When an individual destination is disabled, record when it was disabled. On re-enabling, offer to upload all locally available readings missed during the disabled interval, optionally starting at a user-selected date within that interval. Catch-up is a user choice, not an automatic upload of everything missed. Preserve previously pending delivery state; disabling does not silently discard it.
- When a destination's server address changes, explicitly ask whether to send its pending readings to the new address. Also offer a fuller backfill from a selected date, including the beginning of available local history, to support migration to an empty database. Treat pending-reading transfer and additional history selection as explicit choices. Updating only a password/token keeps the same queue.

Still to decide: destination naming/ordering and credential setup, diagnostic-log retention, the fate of old pending work if transfer to an edited address is declined, and handling requests already in flight during cancellation or queue clearing. The delivery design must distinguish a migrated destination's history from acknowledgements for the previous endpoint and avoid duplicate delivery work where selected pending readings and backfill overlap. Manual retries must respect the selected mode and destination state; they must not bypass the Viewer upload pause.

## Mode and data boundaries

Switching to Viewer must stop all active BLE collection, scanning, reconnection and new standalone recording, stop all standalone alarms and their pending work, pause standalone uploads for every destination, and end the standalone Live Activity. Warn before switching when readings are pending upload. Preserve alarm settings, the paired-sensor record, committed local history and durable delivery state, including queued uploads for later resumption. An upload request already in flight may finish and have its outcome recorded; no further upload requests or retries start while in Viewer.

The existing model has one delivery row per reading. Multiple targets need independent delivery tracking per destination when uploads are implemented; local glucose records remain shared.

### Sensor reconnection

The user clarified that “restart” means **reconnect the existing sensor by scanning it again with NFC**, for example after it has been connected to another app or device. Use **Reconnect sensor** as the working label in the Sensor tab. This action is distinct from setting up a replacement sensor and does not request restarting sensor wear, clearing history or repeating full onboarding.

The intended outcome is to restore collection from the existing sensor. Reconnection shares the initial/replacement setup first-reading verification, notification, five-minute timeout and retry policy. The qualifying success must come from the current attempt, not a previously stored reading. Validate actual sensor-specific reconnection behavior, including any interaction with another collector, before promising that an NFC rescan can restore the connection. Confirmation needs and manual failure recovery remain to be resolved.

## Open choices by feature

- **Setup:** how unfinished/timed-out setup resumes, NFC reconnection confirmation and manual failure recovery.
- **Stats:** additional metrics, range settings, variability definition, minimum useful data and the empty state.
- **Alarms:** threshold margin/defaults, further alarm types and non-glucose rearming.
- **Uploads:** destination naming/ordering and credential setup, log retention, in-flight cancel/clear behavior and pending work when address-change transfer is declined.
- **Live Activity:** no-reading presentation, stale threshold, update cadence and recovery when iOS ends or limits an activity.

Keep sensor management in the Sensor tab and reuse the existing visual system. Store-backed graph work can proceed with the confirmed choices above; remaining alarm, upload and Live Activity decisions concern those features.
