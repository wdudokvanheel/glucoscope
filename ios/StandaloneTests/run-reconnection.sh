#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreNFCSession.swift" \
  "$root/ios/StandaloneTests/NFCReconnectionSmoke.swift" \
  -o "$temporary/reconnection"
"$temporary/reconnection"
