# EU Libre 2 connection diagnostic protocol

This documents the implemented EU Libre 2 protocol, calibration and nonlinear conversion. NFC/BLE and diagnostic decoding have been exercised on one physical non-Plus `7F`. The ordinary checked decoder now feeds local reading storage; the detailed diagnostic decoder remains available for inspection. NFC history import and uploads are future work. See [current app work](ios-libre2-implementation-plan.md) and [device observations](libre2-ble-testing.md).

## Reference provenance

The supplied `docs/xdripswift` checkout reports commit `53b3d6bf1b550c99b19c3d5d2c2f80dd226465d8`. File hashes below identify the actual inspected source even if the checkout has local changes. Its supplied license is GPL-3.0; the new code does not import or link the snapshot.

```text
3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986  LICENSE
bd947c4c6af3501ffc5263633e8a8802cd29e452483a61532d0df1c794dd6324  xDrip/BluetoothTransmitter/CGM/Libre/Libre2/CGMLibre2Transmitter.swift
11ae969e5c31cb5af37c65626d584cd388f037e4915b16ff8ca88594325cd9cf  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/Libre2BLEUtilities.swift
996ba0cdbef4a2e0e3f7709426c2a087db52718eac9e03a0226fa596437bacdd  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/PreLibre2.swift
c3caaaf1192b15e633fc2d4e013dbeae42d05a9603d8c110c5c007347e8d78bc  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreNFC.swift
ebe01adf98a5047689f0bcd14e85c39bb316ffe192198c9dc14f883037fc4ef8  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreSensorType.swift
bf2a3d1fd02e4345928810914b2a9f33937b6dd76ad64e47f5a23b4fcca964d9  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreSensorSerialNumber.swift
18096bad64d7cd76ce33dff703411eee8eeb046b76113cb42bf4bc484fea781e  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/CRC.swift
38f1f8d406b9c5b0d0f5ee33eee381f47a5ad0b86c81a65f23f06e3703bfb327  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreSensorState.swift
d1cb5449b2f40c6c029d09afa3ed5e095cd79a4d02e03933499a801483d373dd  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreCalibrationInfo.swift
091f74449ba773f49fe435e847539e82c07059741cd38e24d32bdb248ad22599  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreMeasurement.swift
ef775dfaa1fe73bbb94374445b95cf3d959e61a0eaa976469e97baa6eb487252  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/Libre1DerivedAlgorithmParameters.swift
0a8a1164e932b656cde430a1b99fb93f309029ea70a282fdb56038c447685d11  xDrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreDataParser.swift
```

Paths below are relative to `docs/xdripswift/xDrip/BluetoothTransmitter/CGM/Libre/`.

## Identity and setup

`Utilities/LibreNFC.swift` reads ISO 15693 patch information using custom command `A1` with empty parameters. Reverse Core NFC's eight-byte tag identifier to obtain the protocol UID. Require at least six patch-information bytes. `Utilities/LibreSensorType.swift` classifies `9D` and `C5` as EU Libre 2; `7F` is non-Plus only when the low nibble of patch byte 2 is zero. Other sensor families and incomplete patch information are rejected.

Only streaming enablement is in scope, for an already activated sensor. No activation, reset, or lifetime extension command is sent. Setup persists a pending session before sending the enable command; an interrupted or uncertain write requires another deliberate NFC setup. Automatic BLE reconnect must not use pending setup credentials.

`Utilities/LibreSensorSerialNumber.swift` encodes reversed UID bytes 0...5 as ten five-bit symbols (two zero padding bits) using alphabet `0123456789ACDEFGHJKLMNPQRTUVWXYZ`, prefixed with `3` for EU Libre 2. Older revisions advertise `ABBOTT` plus this serial. Non-Plus `7F` uses the six-byte enable response in reverse order as uppercase hexadecimal with no separators. Core Bluetooth's peripheral UUID is a separate identifier, learned on connection.

## Authentication primitives

The following describes the observed algorithm in `Utilities/PreLibre2.swift` and `Utilities/Libre2BLEUtilities.swift`. All word additions wrap modulo 65536; serialized words are little-endian unless stated otherwise. Let `u0`, `u1`, `u2` be the little-endian UID words at offsets 0, 2, and 4.

For a 16-bit word define `T(v) = (v >> 2) XOR (0x6860 if bit 0 is set) XOR (0xA0C5 if bit 1 is set)`.

For four input words `(a,b,c,d)`, compute:

```text
r0 = T(a) XOR d
r1 = T(r0) XOR c
r2 = T(r1) XOR b
r3 = T(r2) XOR a
r4 = T(r3)
r5 = T(r4 XOR r0)
r6 = T(r5 XOR r1)
r7 = T(r6 XOR r2)
C(a,b,c,d) = (r3 XOR r7, r2 XOR r6, r1 XOR r5, r0 XOR r4)
P(x,y) = (u2 + x + y, u1, u0 + 2*x, 0x241A XOR 0x14C6)
Q(a,b,c,d) = (u2+a, u1+b, u0+c, d+0x14C6)
F(x,y) = LE16(C(P(x,y))[0] XOR 0x4163)
         || LE16(C(P(x,y))[1] XOR 0x4344)
```

`F` returns four bytes. For an enable code `e`, the NFC command is `A1` with parameters `1E || LE32(e) || F(0x1E, patchWord4 XOR low16(e))`. The response must contain six bytes. The reference uses enable code 42. Counter use starts at 1 after successful setup and increases for each authentication attempt. Reserve the next counter in Keychain before writing; exhaustion requires NFC repair instead of wraparound or reuse.

For BLE unlock, let `t=e+counter`, `A=F(0x1B,0x1B6A)`, `E=F(0x1E,patchWord4 XOR low16(e))` and index `A`/`E` as little-endian words:

```text
W = C(Q(E0 XOR high16(t), A0, E1 XOR low16(t), A1))
h0 = H(C1 C4 C3 C0 D4 E1 E7 BA || LE16(W0))
h1 = H(LE16(W1) || LE16(W2) || LE16(W3))
h2 = H(A || firstTwoBytes(E))
h3 = H(lastTwoBytes(E) || LE32(t))
BLE unlock = LE32(t) || serializeLE(C(Q(h0,h1,h2,h3)))
```

Here `H` is the reflected CRC recurrence with polynomial `0x8408`, seed `0xFFFF`, no final XOR, followed by reversal of all 16 bits. This definition corresponds to the reference's `crc16(...).byteSwapped`; a bitwise implementation avoids importing the reference lookup table.

## NFC lifecycle validation

Read all 43 eight-byte FRAM blocks using addressed ISO 15693 reads, then decrypt each block `i` with the little-endian serialization of:

```text
C(u2 + (patchWord4 XOR 0x0044) + i,
  u1,
  u0 + 2*i,
  0x241A XOR 0x14C6)
```

XOR this eight-byte key with the encrypted block. For these EU revisions the same argument applies to header, body and footer; the reference's `0xCADC` branch is used by its separate US-family implementation, which is excluded here.

Validate each plaintext section `0..<24`, `24..<320`, and `320..<344`. Its first two bytes contain `H` (defined above) little-endian, covering the remaining bytes in that section. Only after all three section checks pass may byte 4 be trusted as lifecycle state. Permit `02` (starting) and `03` (ready). Reject not started, expired, shutdown and unknown states before sending streaming enablement. Calibration capture now follows these integrity checks; importing history remains later work.

## BLE transport and frame integrity

`Libre2/CGMLibre2Transmitter.swift` discovers GATT service `FDE3`, write characteristic `F001`, and notification characteristic `F002`. Enable notifications before sending the 12-byte unlock to `F001` with response. Receiving a write acknowledgement confirms transport only. Initial discovery is an unfiltered foreground scan matching the NFC-derived name; do not assume the sensor advertises its GATT service UUID. Subsequent connections retrieve the saved peripheral UUID first.

A complete encrypted frame is exactly 46 bytes. The first two bytes supply an unencrypted little-endian nonce; the other 44 bytes are encrypted. A fragment accumulator has a strict 46-byte cap and a timeout, and is cleared for each connection. Truncation, overflow, timeouts, and CRC failures are logged.

```text
A = F(0x1B,0x1B6A)
x = (A0 XOR A1) OR 0x0063
y = LE16(frame[0...1]) XOR 0x0063
K0 = C(P(x,y))
Kn+1 = C(Kn)
plaintext = frame[2...45] XOR concatenated little-endian K words
```

The first 42 plaintext bytes are protected by the final two bytes. The reference returns `byteSwap(H(plaintext[0..<42]))` and compares it with the last two bytes interpreted big-endian; equivalently, compare `H` with the trailer interpreted little-endian. Reject a wrong length or failed CRC before showing a frame as validated.

The sensor minute is little-endian at plaintext offsets 40–41. Seven packed four-byte samples begin at offsets 0,4,...,24; their ages relative to sensor minute are 0,2,4,6,7,12,15 minutes. Each sample holds raw glucose in bits 0–13, temperature in bits 14–25 (scale by 4), adjustment magnitude in bits 26–30 (scale by 4), and adjustment sign in bit 31. The experimental decoder below preserves these seven positions and does not interpolate the missing minutes.

## iOS lifecycle

Initialize one app-owned collector in the app delegate at launch. Its Core Bluetooth manager uses a stable restoration identifier and dedicated serial queue. Restore only the selected, enabled session, reattach delegates, and inspect existing services/subscriptions before initiating new discovery. Keep an OS-managed connection request pending while out of range. Stop and forget disable further reconnection; user-driven setup stops the previous BLE session first.

The app declares `bluetooth-central`, a Bluetooth usage description, NFC usage description, and the NFC `TAG` entitlement. These follow Apple's [Core Bluetooth background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html) and [NFC entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats). Restored delivery and background reconnection remain hardware tests, not established guarantees. Force-quitting requires manually reopening the app; Keychain state uses accessibility after first unlock.

## NFC recovery diagnostic revision

Following an initial physical report of connection loss during the empty `A1` patch query, the harness retries transient connect/read operations up to three attempts per step with a 180 ms delay. A lost/not-connected tag can trigger up to two polling restarts in the same sheet, locked to the first UID. A polling restart discards the old tag handle. Cancellation and session-generation checks run around awaited operations on the main actor. Explicit ISO 15693 rejection codes do not take the generic no-response retry path.

Streaming enablement is excluded from automatic retry/reacquisition. Once its command is attempted, a failed/uncertain outcome retains pending credentials and requires deliberate new setup. Logs now record the tag identity before patch interrogation, the command/FRAM batch, and Core NFC domain/code plus selected underlying response details. These changes are tested with simulated operations. A later physical setup succeeded with every NFC read on its first attempt, so recovery itself is still not physically confirmed and must not be credited as the cause of that success.

## Calibration capture revision

`LibreCalibration.swift` independently extracts the EU layout described by the supplied `Utilities/LibreCalibrationInfo.swift` (hash above). Bits are numbered least-significant first within each byte. At FRAM byte 2, `i1` is bits 0–2 and `i2` bits 3–12. At byte 336 (`0x150`), `i3` has an 8-bit magnitude at bit 0 and sign at bit 33, `i4` occupies bits 8–21, `i5` occupies bits 40–51 multiplied by four, and `i6` occupies bits 52–63 multiplied by four. The compact stored source is bytes `2..<4` and `336..<344`; metadata also records UID, exact patch information, format version, capture date, lifecycle and sensor minute. The full FRAM is not retained. These fields are calibration inputs, not glucose measurements.

Existing Keychain records lacking calibration remain paired and report needs-calibration. A deliberate **Read calibration with NFC** action requires complete pairing, checks UID before connecting and stable patch identity/revision before FRAM reads, validates all FRAM sections and lifecycle, then returns before any pairing save or `A1/1E` streaming-enable command. Stable identity excludes the observed mutable patch word at bytes 4–5, as explained below. The empty-parameter `A1` identity query and FRAM reads are read-only operations. New deliberate setup also captures calibration before enabling streaming.

The BLE serial queue merges the capture into its latest persisted session only when its pairing generation still matches the scan's expected session. It also checks the in-memory session, saves before publishing, and preserves the latest peripheral and unlock counter. Calibration does not stop/reconnect BLE, change collection preference, or clear frame assembly/diagnostic counters. Failure leaves the current collection untouched. No raw calibration values are added to diagnostics. Two corrected mutable-word read-only recaptures succeeded on hardware during this increment. They also exposed the timestamp issue described below. Synthetic model tests do not establish Core NFC/Core Bluetooth callback behavior, Keychain fault recovery, or glucose accuracy.

## Experimental diagnostic decoder

`Libre2DiagnosticDecoder` is pure Foundation Swift. Its boundary accepts a complete decrypted payload, `LibreCalibration`, an explicitly supplied saved `LibreSensorClockAnchor`, and the UID/patch information of the authenticated transport session. It rechecks the exact 44-byte length and CRC before extraction, checks calibration/clock ownership and version plus supported revision, then returns a frame rejection or exactly seven independent slot results. A missing clock argument value produces a rejection rather than an implicit replacement. Payloads do not contain a UID: supplying the actual transport identity remains the caller's responsibility, and CRC is not cryptographic identity authentication. Nothing here commits readings to a store, graph or canonical glucose upload queue.

A same-UID physical NFC rescan during this increment showed patch bytes 4–5 change after setup. Identity comparison therefore requires equal UID and patch length plus equality of every patch byte except 4–5; classification must still be supported. The decoder delegates this to `LibreCalibration.validateOwnership`. The original paired patch word remains an authentication input and is preserved in the BLE session; calibration retains the patch observed at capture. Mutable patch-word equality is not required to establish calibration ownership. Read-only scans therefore preserve the saved authentication patch.

Algorithm identifier `libre2-nonlinear-diagnostic-v2` selects the full nonlinear equation in `LibreMeasurement.glucoseValueFromRaw`, evaluated in Double without rounding to integer glucose. Version 2 changes timestamp ownership to a separately persisted sensor clock; its glucose equation is unchanged from diagnostic version 1. It retains each slot's signed temperature adjustment. This is a deliberate diagnostic selection, not an assertion that it matches the reference application's displayed output. `CGMLibre2Transmitter.processValue` passes derived parameters only when `isWebOOPEnabled()` is true. That BLE path evaluates the bilinear `temperatureAlgorithmGlucose` approximation: `Libre1DerivedAlgorithmParameters` evaluates the full equation at glucose 1000/3000 and raw temperature 6000/9000 with adjustment zero, rounds each of those four answers, and fits temperature-dependent slope and intercept. It then applies `extraSlope`/`extraOffset`. With parameters absent the BLE parser instead uses raw glucose times its multiplier. The diagnostic decoder uses neither approximation, user calibration, multiplier fallback, gap interpolation nor the reference's repeated-value suppression. The fit's 6000/9000 temperatures are fitting coordinates, not established validity limits.

For decoded glucose `G`, temperature `T`, signed adjustment `A` and calibration `i2,i3,i4,i6`, the selected equation is:

```text
R = 72500*T / (i6 + A) - 1000
L = ln(R)
D = 0.0009180023 + 0.0001964561*L
    + 0.0000007061775*L² + 0.00000005283566*L³
C = 1/D - 273.15
N = 65*(G - i3)/(i4 - i3)
Q = N * 1.045^(32.5 - C)
glucose_mg_dL = (Q - offset(i2))/sensitivity(i2)
```

All constants above originate in the inspected `LibreMeasurement.glucoseValueFromRaw`: 72500 is its `1000 + 71500`, 1000 its resistance subtraction, the four decimal coefficients its inverse-temperature polynomial, 273.15 the Kelvin-to-Celsius shift, and 65/1.045/32.5 its glucose scaling and temperature compensation. Their underlying empirical/manufacturer derivation is not supplied and is not claimed here. `i1` and `i5` are retained calibration fields but unused by this selected equation. The implementation evaluates the same polynomial in Horner form and rejects invalid domains before logarithm/division.

### Finite coefficient reconstruction

The source contains 1023 entries each in `t1` (offset) and `t2` (sensitivity), indexed by `i2-1`. No tables are copied into the app. Independent static inspection establishes the following arithmetic structure. Let `p=i2-1`, restricted to `0...1022`:

| Position p | Row r | Column c | Offset |
| --- | --- | --- | --- |
| 0...511 | floor(p/8) | p mod 8 | 0.75+c/4 |
| 512...718 | 64+floor((p-512)/9) | (p-512) mod 9 | 0.75+c/4 |
| 719...950 | 87+floor((p-719)/8) | (p-719) mod 8 | 1+c/4 |
| 951...1022 | 116+floor((p-951)/9) | (p-951) mod 9 | 1+c/4 |

For the resulting `r=0...123`, sensitivity is `round(0.037744227 * 1.01^r * 10^7) / 10^7`. This is an **inferred finite-domain reconstruction of the supplied decimal data**, not a recovered original generator or a manufacturer formula. For each source row value `s[r]`, intersecting the seed intervals `(s[r] ± 0.5*10^-7)/1.01^r` gives approximately `[0.03774422680467033036, 0.03774422741644637658]`. The short decimal seed `0.037744227` lies strictly inside that interval. Independent static arithmetic inspection of all 124 rows/1023 indices confirmed the reconstruction reproduces every offset exactly and every sensitivity to the source's seven decimal places (the longer literals contain binary floating-point printing tails). The rounded first sensitivity `0.0377442` itself is not a valid seed. Nothing is inferred outside the 1023 available entries; index zero/out-of-range is rejected. This derivation avoids carrying the source arrays into runtime.

### Validation and clock policy

Structural extraction bounds `G` to 0...16383, `T` to 0...16380 in multiples of four, and `A` to -124...124 in multiples of four. Zero glucose or temperature rejects that slot only. Coefficients require `1 <= i2 <= 1023`, `i4 > i3` and `i6 > 0`. Each slot also requires `i6+A > 0`, finite positive `R`, and finite positive `D` before temperature conversion. Negative adjustment sign with zero magnitude means zero.

The decoder applies explicit, deliberately broad **engineering diagnostic bounds** of -10...60 °C and 1...1000 mg/dL inclusive after the mathematical checks. These are app policy, not source-derived sensor operating limits or clinical validity criteria. Finite results outside them receive a named diagnostic-range rejection; no clipping or substitution occurs. The selected reference BLE parser has a separate extreme-value check at 3000 mg/dL in its derived path, which is not the same policy. Real comparisons may justify revising these diagnostic bounds. Accepted means only that the specified structural/domain/policy checks passed, not that the sensor measurement is medically accurate.

The NFC calibration lifecycle must be starting (`02`) or ready (`03`). It is a historical snapshot: neither value proves current BLE lifecycle, and currently uninterpreted BLE bytes are not presented as a live state. A starting snapshot may support later samples without another NFC scan; every sample minute must be at least 60. This warmup threshold follows `LibreDataParser.handleGlucoseData`. Frame minute, calibration capture minute and saved clock reference minute must be within 20880 minutes, the 14.5-day maximum returned for the three supported revisions by `LibreSensorType.maxSensorAgeInDays`; this is a strict diagnostic ceiling. `LibreDataParser` allows an expired state's grace period, while this decoder has no fresh lifecycle to evaluate. A frame minute preceding the saved clock reference minute is rejected as stale/rollback. The seven sample offsets themselves may precede that reference and are individually warmup-checked. A newer calibration capture does not move this rollback boundary. There is no counter-wrap extension.

For sample offset `o`, timestamp is `clockAnchor.referenceDate + 60*(frameMinute-o-clockAnchor.referenceSensorMinute)`. `LibreSensorClockAnchor` is a separate versioned, sensor-owned session record. The decoder requires it explicitly and rejects missing/invalid/foreign references; it never derives an anchor from a packet or the latest capture. Date conversion validates finite usable dates before diagnostic formatting. Repeated/overlapping sensor minutes retain identical timestamps across calibration recapture and session reload. Calibration capture date/minute remain provenance metadata and are shown separately from the saved clock reference in diagnostic export revision **v5**.

Two v4 read-only recaptures changed the calibration-derived clock estimate by -6 seconds and then +22 seconds. That shifted timestamps for previously seen sensor minutes despite unchanged sensor identity, motivating the independent saved clock. Migration seeds an old session once from its currently stored valid calibration when the clock key is absent. First calibration supplies a clock when none is available; later captures retain a valid existing clock. The merged session writes that original clock to Keychain together with the new capture. An explicitly missing or invalid modern clock is reported as needing a clock until repaired by deliberate capture. The current phone's old first-capture anchor was already overwritten in v4: migration can only preserve the latest available estimate, and does not reconstruct unavailable historical metadata. Stability begins from that saved migration/first-capture reference onward.

The initial UTC uncertainty includes NFC read duration, sensor-minute quantization, phone clock error and subsequent sensor drift. The stored 60-second resolution allowance is not a bound on those other errors. There is no per-frame or per-recapture anchor correction, receipt-time freshness/clock-skew check, replay detection or monotonic stream state in this pure decoder. Display reading age separately from connection state; repeated unchanged valid glucose is never itself an expiration condition.

### Numerical fixtures and outstanding evidence

`ios/Libre2Tests/DiagnosticDecoderSmoke.swift` supplies synthetic packing, sparse offsets, mixed valid/zero slots, CRC/length, owner/revision/version, warmup/age/rollback, snapshot lifecycle, slice indexing, persistence-anchor and coefficient-regime fixtures. Five glucose expectations were independently calculated from the equation above with Python Decimal precision 60 and the selected source coefficient entries; neither app nor reference Swift was executed. They cover positive/negative adjustments and calibration indices 1, 513, 720, 952 and 1023. Absolute fixture tolerance is `1e-8 mg/dL`; the moderate-temperature fixture tolerance is `1e-10 °C`. Coefficient boundary tolerance is `1e-14`. These are arithmetic comparison tolerances, not sensor accuracy specifications. Whole-table inspection supports coefficient reconstruction only, not end-to-end glucose correctness.

The stable-clock fixtures reproduce the two recapture offsets with synthetic dates, reuse the saved clock across captures/reload and require overlapping sample minutes to retain their exact timestamps. They also cover missing/foreign anchors, nonfinite dates, session migration and merge preservation. Run `./ios/Libre2Tests/run.sh`; see [test coverage](../ios/Libre2Tests/README.md) and [completed device observations](libre2-ble-testing.md). No physical identifiers or private packet exports are included in committed fixtures.
