#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

swiftc \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ServerUploadTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ServerUploadStore.swift" \
  "$root/ios/ServerUploadTests/ServerUploadStoreSmoke.swift" \
  -o "$tmp/server-upload-store-smoke"
"$tmp/server-upload-store-smoke"

swiftc \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ServerUploadTypes.swift" \
  "$root/ios/GlucoScope/Service/ServerUploadTransport.swift" \
  "$root/ios/ServerUploadTests/ServerUploadTransportSmoke.swift" \
  -o "$tmp/server-upload-transport-smoke"
"$tmp/server-upload-transport-smoke"

swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/ServerUploadTests/ReadingStoreBroadcastSmoke.swift" \
  -o "$tmp/reading-store-broadcast-smoke"
"$tmp/reading-store-broadcast-smoke"

swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/GlucoScope/Persistence/ServerUploadTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ServerUploadStore.swift" \
  "$root/ios/GlucoScope/Service/ServerUploadCredentialStore.swift" \
  "$root/ios/GlucoScope/Service/ServerUploadTransport.swift" \
  "$root/ios/GlucoScope/Service/ServerUploadCoordinator.swift" \
  "$root/ios/ServerUploadTests/ServerUploadCoordinatorSmoke.swift" \
  -o "$tmp/server-upload-coordinator-smoke"
"$tmp/server-upload-coordinator-smoke"
