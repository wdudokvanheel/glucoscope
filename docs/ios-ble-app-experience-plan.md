# iOS Bluetooth/standalone app experience plan

> **Product direction only — user interview required before UI implementation.** This document records the requested iOS experience. It does not authorize UI source changes, runtime BLE ingestion, decoder promotion, sensor actions, notifications, Live Activities or upload behavior. Before any UI implementation begins, interview the user on the open decisions below and update this plan with their answers.

## Product intent

GlucoScope should offer two clearly separated modes without making the existing Viewer experience harder to use:

- **Viewer** retains the current app and current UI. It continues to show read-only glucose values obtained from Nightscout or the configured custom backend. Its only requested additions are a mode switch in Settings and the initial onboarding choice between Viewer and Bluetooth/standalone mode.
- **Bluetooth/standalone** collects from the user's sensor and presents a clear, easy, native iOS experience. The user specifically does not want the dense or difficult interaction style they associate with xDrip.

The two modes may share visual components such as the existing graph, but their data-source and lifecycle state must remain explicit. Viewer data must not be mixed into the standalone sensor's local history.

## Entry and onboarding

First-run onboarding asks the user to choose **Viewer** or **Bluetooth/standalone**.

Choosing Viewer enters the current Viewer app and leaves its existing navigation and screens intact. Choosing Bluetooth/standalone starts onboarding that explains, in plain language, how direct sensor collection works and guides the user through connecting their first sensor. Sensor scanning or streaming setup remains a deliberate user action.

The user's stated direction is that Bluetooth/standalone “always starts onboarding.” The required interview must preserve that wording and clarify what “always” means for a returning user: every app launch, every switch into Bluetooth mode, only until the first sensor is connected, or a short status/re-entry flow after setup. Do not infer this behavior during implementation.

## Bluetooth/standalone navigation

Bluetooth/standalone uses a bottom tab bar with four primary destinations:

| Tab | Requested experience |
| --- | --- |
| **Graph** | Use the same graph view users already know. Adapt its data source to committed local sensor readings only when canonical ingestion is qualified and connected. |
| **Stats** | Lead with time in range. The user may want additional statistics; the interview must establish which ones, their time windows and their layout. |
| **Sensor** | Show connection status, sensor age and direct sensor actions. Include BLE settings/log access, deliberate NFC scan, and a clearly explained restart action whose exact meaning remains open. |
| **Settings** | Replace the standalone settings experience with a clear native iOS-style menu of focused sub-screens. |

The standalone home experience should feel continuous with the current graph rather than like a diagnostics console. Connection and stale-data state must remain distinct from a current glucose reading.

## Standalone Settings structure

Use a native iOS-style settings list with clear labels, standard controls and focused sub-screens for:

- **UI** — display and graph preferences.
- **Theming** — appearance choices, kept separate from functional settings.
- **Server uploads** — configure **multiple upload targets** and show each target's state independently.
- **Alarms** — highly configurable glucose alarms delivered through native iOS notifications, including sustained-high and sustained-low alarms that trigger only after glucose has remained outside the chosen range for a user-selected number of minutes.
- **Live Activity** — configure a Live Activity intended to show the current value and a small graph.
- **Bluetooth** — connection settings, status and a useful redacted log.
- **About** — app, support and version information.
- **Switch to Viewer** — stop Bluetooth collection, scanning/reconnection and standalone recording, then return to the Viewer experience.

This structure is an information-architecture request, not a promise that every feature is available under every iOS state. Notification timing, background execution, Live Activity refresh behavior, lock-screen presentation and supported OS/device combinations need later platform research, implementation and device validation. The UI must explain real limitations once those behaviors are known.

## Mode and data boundaries

Switching to Viewer must stop all active BLE collection, scanning, reconnection and new standalone recording. It must not silently erase the paired-sensor record, committed local history or durable delivery state. The required interview must decide what happens to already queued uploads and in-flight work for each configured target when the user switches modes.

The request for multiple upload targets supersedes the earlier single-target assumption in the Libre 2 implementation plan. The current persistence model assigns at most one delivery row and destination to each reading, and the planned worker assumes one selected destination. Supporting multiple targets will require a separately reviewed schema, migration, uniqueness, payload-freezing, worker, retry, acknowledgement and per-target status design. Do not retrofit this as a UI-only preference or duplicate committed readings.

“Restart” is deliberately undefined here. It could mean retry the BLE connection, restart collection services, repair setup, restart onboarding, or perform a sensor-specific operation. Some interpretations could interrupt collection or affect a sensor wear. The UI must not expose a restart action until the interview establishes its exact scope, confirmation needs and recovery behavior.

## Required user interview before UI work

Do not create UI code, wireframes presented as final, navigation state, notification schedules, Live Activity attributes or upload-target schema until the user has answered these topics:

1. **Onboarding and re-entry:** What does “always starts onboarding” mean after a sensor is connected, after relaunch, after switching modes, after replacement and when setup is incomplete? What can be skipped or resumed?
2. **Graph, tabs and Stats:** Which existing graph interactions must remain identical? What is shown above/below the graph? Which statistics beyond time in range are wanted, for which ranges, and how should empty or incomplete data appear?
3. **Alarms:** Exact high/low thresholds, sustained-duration behavior, timer reset rules, repeats, snooze, quiet hours, critical-alert expectations, notification sounds, missing/stale-data alarms and behavior when readings arrive late or are backfilled.
4. **Multiple upload targets:** Supported target types, target ordering/naming, independent enablement, credential setup, per-target status, retry controls, and the fate of queued/in-flight deliveries when switching to Viewer, disabling a target or editing it.
5. **Live Activity:** Desired current-value and mini-graph layout, update cadence, stale/offline presentation, privacy on locked devices, start/stop controls and acceptable behavior when iOS limits updates.
6. **Sensor restart and recovery:** What “restart” must do, which state it may clear, whether it is connection-only, how NFC repair differs, when confirmation is required and how the user returns from failure.

Record the answers here as explicit decisions and identify any remaining platform or sensor validation before implementation. Use the interview to reduce steps and terminology; do not copy xDrip's navigation or expose protocol details merely because they exist in diagnostics.

## Implementation gate

UI implementation starts only after the interview is complete and its decisions are reviewed against the data-source, sensor-lifecycle, notification and delivery contracts. Runtime BLE connection remains separately gated by decoder evidence, live-status/clock-freshness qualification and the ingestion reviews in [the implementation plan](ios-libre2-implementation-plan.md). A polished screen must never make experimental or uncommitted glucose appear canonical.
