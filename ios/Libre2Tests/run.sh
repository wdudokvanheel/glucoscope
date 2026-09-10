#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreFrameAssembler.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreReadRetry.swift" \
  "$root/ios/Libre2Tests/ProtocolSmoke.swift" \
  -o "$tmp/libre2-smoke"
"$tmp/libre2-smoke"
