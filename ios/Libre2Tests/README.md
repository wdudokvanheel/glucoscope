# Libre 2 connection regression tests

Run `./ios/Libre2Tests/run.sh` from the repository root on a Mac with the Swift toolchain. The script compiles only the app-owned Foundation protocol/models/frame assembler and these tests; it does not import xDrip or need NFC/BLE hardware.

The UID and packet fixtures are synthetic. BLE plaintext is bytes 0 through 41 with its reference CRC. FRAM plaintext follows byte `(index * 7) mod 256`, has lifecycle byte 4 set to 3, and has independently computed section CRCs. Ciphertexts and expected unlock commands were checked using the supplied reference functions in a temporary comparison harness outside the app/repository. Reference file hashes are recorded in `docs/libre2-eu-protocol.md`. No glucose conversion or algorithm configuration is involved.

Tests cover fixed NFC/BLE authentication payloads, encrypted BLE and full FRAM plaintext, single-bit corruption, wrong UID, malformed inputs, supported/rejected revisions, the last counter reservation, every two-fragment split, byte-at-a-time reception, overflow recovery, and connection/timeout buffer reset. Core Bluetooth callback ordering, actual timers, Keychain fault injection and physical NFC cancellation need hardware/integration validation; these pure tests do not establish those behaviors.

NFC read recovery tests additionally exercise success after transient failures, attempt exhaustion, cancellation between attempts, and immediate failure for a non-retryable operation. They use the same main-actor retry runner as the NFC session and do not communicate with a sensor. Polling/redetection and Core NFC error delivery still require physical validation.
