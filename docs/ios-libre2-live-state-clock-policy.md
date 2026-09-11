# Libre 2 reading time and sensor state

## Saved timestamps

Each wear has one persisted sensor clock:

```text
sampleDate = referenceDate + 60 × (sensorMinute − referenceSensorMinute)
```

Reconnect, calibration recapture and app restart preserve that mapping. SQLite's established clock is authoritative when reconciling pairing metadata; the bridge allows 0.001 seconds for representation differences. Packet receipt is recorded separately and never replaces sample time. Timezone changes affect display only.

The decoder accepts frame minutes from the reference minute through `20880`. An older whole frame is rejected, but individual recovery slots may precede the anchor when their minute is at least 60 and their derived date is valid. Dates use the store's inclusive 2000–2100 UTC range. These are implemented engineering limits.

The NFC anchor records nominal 60-second resolution. That does not measure phone-clock error, capture latency or drift. On the tested `7F`, newest sample dates were 15–16 seconds ahead of receipt and stayed stable across recapture and relaunch. Keep that signed difference visible when investigating time alignment; do not silently re-anchor stored history.

## Latest saved value and freshness

A saved reading is historical data with a sample timestamp. Showing the latest saved value should include its age. A Bluetooth connection, successful fetch, duplicate frame or historical recovery slot must not make an old value look newly measured.

The standalone product's stale threshold remains an open choice. Implement that choice in the display/alarm consumers when building them. The queue's 120-second residence limit controls pending work and is unrelated to a reading's age.

For alarms, the [confirmed product decisions](ios-ble-app-experience-plan.md) require historical readings to update graphs/Stats without triggering alarms about the past. When readings become stale, reset sustained-high/low timers and begin a fresh duration when current readings return. After relaunch, use saved readings for history and evaluate their age before showing current state.

## Sensor state

NFC lifecycle `02` means starting and `03` means ready at the time of that scan. The app's active wear record is also distinct from the sensor's present state. BLE bytes `28..<40` remain uninterpreted; the parser does not provide a live health/status interpretation for them.

Keep connection state, setup state, last saved reading and reading age separate in the UI. Do not infer sensor expiration from constant values or missing packets. More status interpretation and broader clock observations can improve the app later; they are not prerequisites for saving checked development readings.

## Practical checks

- Overlapping minutes retain identical dates across calibration recapture, reconnect and store reopen.
- Delayed/repeated slots keep their original sample times and leave genuine gaps.
- Stop/replacement discards old-generation work without deleting saved history.
- Foreground return recomputes displayed age; it does not reset age to the refresh time.
- If investigating a phone-clock change, compare the established mapping and receipt dates before making any repair. Existing history should not shift silently.
