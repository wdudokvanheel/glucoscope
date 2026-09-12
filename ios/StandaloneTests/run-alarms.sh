#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
swiftc "$root/ios/GlucoScope/Alarms/AlarmModels.swift" "$root/ios/StandaloneTests/AlarmEngineSmoke.swift" -o "$temporary/alarms"
"$temporary/alarms"
swiftc "$root/ios/GlucoScope/LiveActivity/GlucoseActivityAttributes.swift" "$root/ios/StandaloneTests/LiveActivityPayloadSmoke.swift" -o "$temporary/activity-payload"
"$temporary/activity-payload"
