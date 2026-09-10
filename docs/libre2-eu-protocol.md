# EU Libre 2 connection diagnostic protocol

This document records the connection subset implemented for the temporary iOS diagnostic home screen on 10 September 2026. It was independently derived from the supplied source snapshot, then exercised on one physical non-Plus `7F` sensor as recorded in `ios-libre2-implementation-plan.md`. Glucose conversion, calibration, reading storage, upload, NFC history, and broad hardware qualification remain outside this first connection implementation. A CRC-valid frame is not a validated glucose measurement.

## Reference provenance

The supplied `docs/xdripswift` checkout reports commit `53b3d6bf1b550c99b19c3d5d2c2f80dd226465d8`. File hashes below identify the actual inspected source even if the checkout has local changes. Its supplied license is GPL-3.0; the new code does not import or link the snapshot. An independent implementation is not a legal-clearance claim.

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

Validate each plaintext section `0..<24`, `24..<320`, and `320..<344`. Its first two bytes contain `H` (defined above) little-endian, covering the remaining bytes in that section. Only after all three section checks pass may byte 4 be trusted as lifecycle state. Permit `02` (starting) and `03` (ready). Reject not started, expired, shutdown and unknown states before sending streaming enablement. This FRAM read establishes lifecycle integrity only; extracting calibration and importing history are later work.

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

For later decoding, the sensor minute is little-endian at plaintext offsets 40–41. Seven packed four-byte samples begin at offsets 0,4,...,24; their ages relative to sensor minute are 0,2,4,6,7,12,15 minutes. Each sample holds raw glucose in bits 0–13, temperature in bits 14–25 (scale by 4), adjustment magnitude in bits 26–30 (scale by 4), and adjustment sign in bit 31. This first implementation intentionally does not convert these raw values to glucose. Calibration mathematics and conversion tolerances must be specified and independently tested before doing so.

## iOS lifecycle

Initialize one app-owned collector in the app delegate at launch. Its Core Bluetooth manager uses a stable restoration identifier and dedicated serial queue. Restore only the selected, enabled session, reattach delegates, and inspect existing services/subscriptions before initiating new discovery. Keep an OS-managed connection request pending while out of range. Stop and forget disable further reconnection; user-driven setup stops the previous BLE session first.

The app declares `bluetooth-central`, a Bluetooth usage description, NFC usage description, and the NFC `TAG` entitlement. These follow Apple's [Core Bluetooth background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html) and [NFC entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats). Restored delivery and background reconnection remain hardware tests, not established guarantees. Force-quitting requires manually reopening the app; Keychain state uses accessibility after first unlock.

## NFC recovery diagnostic revision

Following an initial physical report of connection loss during the empty `A1` patch query, the harness retries transient connect/read operations up to three attempts per step with a 180 ms delay. A lost/not-connected tag can trigger up to two polling restarts in the same sheet, locked to the first UID. A polling restart discards the old tag handle. Cancellation and session-generation checks run around awaited operations on the main actor. Explicit ISO 15693 rejection codes do not take the generic no-response retry path.

Streaming enablement is excluded from automatic retry/reacquisition. Once its command is attempted, a failed/uncertain outcome retains pending credentials and requires deliberate new setup. Logs now record the tag identity before patch interrogation, the command/FRAM batch, and Core NFC domain/code plus selected underlying response details. These changes are tested with simulated operations. A later physical setup succeeded with every NFC read on its first attempt, so recovery itself is still not physically confirmed and must not be credited as the cause of that success.
