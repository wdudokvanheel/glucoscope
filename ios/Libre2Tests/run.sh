#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreFrameAssembler.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreReadRetry.swift" \
  "$root/ios/Libre2Tests/ProtocolSmoke.swift" \
  -o "$tmp/libre2-smoke"
"$tmp/libre2-smoke"
swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2DiagnosticDecoder.swift" \
  "$root/ios/Libre2Tests/DiagnosticDecoderSmoke.swift" \
  -o "$tmp/libre2-decoder-smoke"
"$tmp/libre2-decoder-smoke"
swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSessionStore.swift" \
  "$root/ios/Libre2Tests/IdentitySmoke.swift" \
  -o "$tmp/libre2-identity-smoke"
"$tmp/libre2-identity-smoke"
swiftc \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/Libre2Tests/ReadingStoreSmoke.swift" \
  -o "$tmp/libre2-reading-store-smoke"
"$tmp/libre2-reading-store-smoke"
swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
  "$root/ios/GlucoScope/Service/LibreCollectionCoordinator.swift" \
  "$root/ios/Libre2Tests/CollectionCoordinatorSmoke.swift" \
  -o "$tmp/libre2-collection-smoke"
"$tmp/libre2-collection-smoke"
swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSessionStore.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/GlucoScope/Service/LibrePersistenceBridge.swift" \
  "$root/ios/Libre2Tests/PersistenceBridgeSmoke.swift" \
  -o "$tmp/libre2-persistence-bridge-smoke"
"$tmp/libre2-persistence-bridge-smoke"
swiftc \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/GlucoScope/Service/LibreStorageProbe.swift" \
  "$root/ios/Libre2Tests/StorageProbeSmoke.swift" \
  -o "$tmp/libre2-storage-probe-smoke"
"$tmp/libre2-storage-probe-smoke"
