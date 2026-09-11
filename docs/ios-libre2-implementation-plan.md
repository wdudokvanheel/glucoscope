# iOS Libre 2 development

GlucoScope is building an offline iOS Libre 2 collector alongside its existing Viewer. This is development and device testing: use the ordinary decoder and existing reading store to make the app useful. Accuracy comparisons and broader device testing continue alongside app development.

## Current implementation

The runtime route is:

`LibreBluetoothCentral → LibreTransportHandoff → LibreOrderedIngestion → LibreCandidateAdapter → ReadingStore`

The BLE queue assembles and verifies frames, then offers their captured identity, calibration and clock to the ordered worker. The adapter decodes valid slots and saves readings through the guarded writer. The diagnostics screen reads the latest saved values from that store. It also retains the separate detailed diagnostic calculation for troubleshooting.

| Area | Implemented |
| --- | --- |
| NFC | EU sensor identity, 344-byte FRAM read/decrypt/CRC, calibration capture, streaming setup and read retries. Read-only calibration capture preserves pairing and the established clock. |
| BLE | `FDE3` / `F001` / `F002` discovery, persisted unlock counters, fragment assembly, decryption, CRC, restoration and pending reconnection. |
| Decoder | Seven sparse slots, sensor-specific nonlinear conversion, ownership and date checks, per-slot rejection and integer mg/dL conversion. |
| Local storage | Core Data SQLite, stable wear identity/clock, deduplication, atomic readings and delivery records, ordered ingestion and bounded work. |
| Diagnostics | Connection/setup status, latest frames/calculations, storage status, saved readings, log export and local upload. |

Connecting saved local readings to the existing graph, mode selection, standalone tabs, uploads, alarms, Live Activity and NFC history import still need implementation. Existing delivery records are storage groundwork; no upload worker runs yet. The current schema supports one required delivery row per reading; multiple destinations need that relationship extended when uploads are built.

## Next app work

**Next coding task:** connect a local `DataSource` to the existing graph and add Viewer/standalone mode selection. The user can run the phone check in parallel; coding does not need to wait for it.

Workflow preference: use Sol/Astra child agents for implementation and testing; agents may compile, while the user owns app and physical-device runs.

1. Exercise real BLE → saved readings on the phone, including reopening the app and a short locked-screen interval. Inspect the saved timestamps and sparse overlap. The development database may be reset as needed.
2. Connect a local `DataSource` to the existing graph and add Viewer/standalone selection. Preserve Viewer behavior and stop obsolete polling/results when switching sources. Collection and graphs must work with no server or credentials.
3. Build first-time skippable onboarding, Sensor management, Stats and standalone Settings from [the app experience decisions](ios-ble-app-experience-plan.md). Resolve feature-specific open choices when implementing that feature.
4. Add multiple upload destinations with independent queues and the agreed newest-first history controls. Implement and test each backend's actual write contract, including authentication, units, retries and duplicate handling.
5. Add NFC history import, then alarms and Live Activity using saved readings and explicit reading age.

Use the existing theme framework, SVG assets and graph components. Avoid adding more policy layers or separate ingestion modes to advance these tasks.

## Product and protocol scope

- iOS 16.4+, one active already-activated EU Libre 2 sensor. Android and sensor activation/reset/lifetime extension are outside this work.
- Parser support is EU `9D`, `C5` and non-Plus `7F`; physical testing so far covers one `7F`. Plus, US, Libre 1, Libre 3 and unknown patches are rejected.
- Bluetooth packets carry offsets **0, 2, 4, 6, 7, 12, 15 minutes**. They recover only those slots; gaps stay visible.
- Planned NFC backfill reads 16 recent trend slots and 32 history slots spaced 15 minutes apart, roughly eight hours subject to sensor age and available data. Use **Scan sensor for history (NFC)**; a BLE scan cannot download arbitrary history.
- Keep full-resolution local history indefinitely while space permits. A year is a sizing benchmark, not a retention limit. A synthetic 28-day run (40,320 readings plus delivery rows) used 11.17 MB of closed SQLite storage, projecting roughly 150 MB/year plus WAL/OS overhead. This was a Mac test.
- Mode switches and sensor replacement preserve local history and upload queues. Viewer pauses collection, standalone alarms/Live Activity and new upload requests; an in-flight upload may finish. Existing installations should enter Viewer on upgrade.
- Future deletion is a deliberate user action showing the affected date range, count and pending deliveries. Storage errors should be visible, with no automatic database deletion.

For the custom backend, uploads will require authenticated writes and server startup without mandatory LibreLink credentials. Preserve the existing Viewer read format. Nightscout and custom-backend retries must retain stable sample identity and timestamps; implement delivery mechanics when those features are built.

## Testing and observed results

[Testing instructions and device observations](libre2-ble-testing.md) are the single record of completed physical checks. One `7F` has streamed in foreground and during a short locked-screen interval, recovered one pending connection, and retained a stable clock across calibration capture and relaunch. Two user-reported values matched the reference's preceding-minute display. Separately, the user reports that recovered historical readings exactly matched their xDrip/Zukka device at the corresponding times; no exported timestamp-matched comparison dataset exists.

The local-saving change (`fe91b37`) passed all 14 portable runs and an unsigned iPhone 16 / iOS 18.5 simulator Debug build under Xcode 26.2. The runtime test saved two overlapping frames as 11 unique readings and delivery rows, stopped collection, reopened SQLite with stable IDs/values/timestamps, and loaded saved values in a fresh coordinator before new packets. The build's only warning was the existing AppIntents skip because that framework is absent. Initial validation was software-only.

The first v10 phone run exposed a fractional-timestamp comparison bug. v11 uses the same `Date` arithmetic in decoding, adapter checks and storage. The regression fails on the old code and passes with the fix; all 14 portable tests and the unsigned simulator Debug build pass. The user reports that live and recovered frames now commit; the phone relaunch check remains.

```sh
./ios/Libre2Tests/run.sh
xcodebuild -project ios/GlucoScope.xcodeproj -scheme GlucoScope -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Use normal development signing and the NFC capability for a phone build. Simulator launches need an application identity/ad-hoc signing for Keychain; a wholly unsigned launch previously produced error `-34018`.

## References

- [App experience and confirmed choices](ios-ble-app-experience-plan.md)
- [Protocol, calibration math and source provenance](libre2-eu-protocol.md)
- [Decoder inputs and checks](ios-libre2-decoder-contract.md)
- [Storage and ingestion](ios-libre2-ingestion-design.md)
- [Transport ordering and bounds](ios-libre2-transport-handoff.md)
- [Reading time and sensor-state notes](ios-libre2-live-state-clock-policy.md)
- [Decoder comparisons](ios-libre2-decoder-evidence.md)
- [Portable tests](../ios/Libre2Tests/README.md) and [local diagnostics host](diagnostics-host.md)

The untracked `docs/xdripswift` checkout is reference material only. Keep it, private exports, identifiers and glucose traces out of commits.
