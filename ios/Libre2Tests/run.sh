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
compile_production_decoder() {
  swiftc "$@" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
    "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/Libre2DiagnosticDecoder.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/Libre2ProductionDecoder.swift" \
    "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
    "$root/ios/Libre2Tests/ProductionDecoderSmoke.swift"
}
# Compile and execute the ordinary source shape with no engineering evaluation API.
# This is the same closed qualification gate compiled into the app.
compile_production_decoder -o "$tmp/libre2-production-gate-smoke"
"$tmp/libre2-production-gate-smoke"
# Compile the deterministic engineering seam only into this portable executable.
compile_production_decoder -D LIBRE2_ENGINEERING_DECODER_FIXTURES \
  -o "$tmp/libre2-production-engineering-smoke"
"$tmp/libre2-production-engineering-smoke"
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
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/Libre2Tests/ReadingStoreSmoke.swift" \
  -o "$tmp/libre2-reading-store-smoke"
"$tmp/libre2-reading-store-smoke"
swiftc -D LIBRE2_COMMIT_OWNERSHIP_FIXTURES \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/Libre2Tests/CommitOwnershipSmoke.swift" \
  -o "$tmp/libre2-commit-ownership-smoke"
"$tmp/libre2-commit-ownership-smoke"
swiftc \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSessionStore.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2DiagnosticDecoder.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2ProductionDecoder.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/GlucoScope/Service/LibrePersistenceBridge.swift" \
  "$root/ios/GlucoScope/Service/LibreOrderedIngestion.swift" \
  "$root/ios/GlucoScope/Service/LibreCandidateAdapter.swift" \
  "$root/ios/GlucoScope/Service/LibreTransportHandoff.swift" \
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
  "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/GlucoScope/Service/LibrePersistenceBridge.swift" \
  "$root/ios/Libre2Tests/PersistenceBridgeSmoke.swift" \
  -o "$tmp/libre2-persistence-bridge-smoke"
"$tmp/libre2-persistence-bridge-smoke"
compile_ordered_ingestion() {
  output="$1"
  smoke="$2"
  shift 2
  swiftc "$@" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreSessionStore.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/Libre2DiagnosticDecoder.swift" \
    "$root/ios/GlucoScope/Sensor/Libre2/Libre2ProductionDecoder.swift" \
    "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
    "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
    "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
    "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
    "$root/ios/GlucoScope/Service/LibrePersistenceBridge.swift" \
    "$root/ios/GlucoScope/Service/LibreOrderedIngestion.swift" \
    "$root/ios/GlucoScope/Service/LibreCandidateAdapter.swift" \
    "$smoke" \
    -o "$output"
}
# The ordinary adapter source shape keeps the production qualification gate closed.
compile_ordered_ingestion \
  "$tmp/libre2-candidate-adapter-gate-smoke" \
  "$root/ios/Libre2Tests/CandidateAdapterSmoke.swift"
"$tmp/libre2-candidate-adapter-gate-smoke"
# The positive and adversarial mapping seam exists only in this portable executable.
compile_ordered_ingestion \
  "$tmp/libre2-candidate-adapter-fixture-smoke" \
  "$root/ios/Libre2Tests/CandidateAdapterSmoke.swift" \
  -D LIBRE2_CANDIDATE_ADAPTER_FIXTURES \
  -D LIBRE2_ENGINEERING_DECODER_FIXTURES \
  -D LIBRE2_ORDERED_INGESTION_FIXTURES \
  -D LIBRE2_COMMIT_OWNERSHIP_FIXTURES
"$tmp/libre2-candidate-adapter-fixture-smoke"
# Exercise the disconnected ordered mailbox without enabling adapter/decoder fixtures.
compile_ordered_ingestion \
  "$tmp/libre2-ordered-ingestion-smoke" \
  "$root/ios/Libre2Tests/OrderedIngestionSmoke.swift" \
  -D LIBRE2_ORDERED_INGESTION_FIXTURES
"$tmp/libre2-ordered-ingestion-smoke"
swiftc \
  -D LIBRE2_TRANSPORT_HANDOFF_FIXTURES \
  -D LIBRE2_ORDERED_INGESTION_FIXTURES \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreCalibration.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorClockAnchor.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSensorSession.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreSessionStore.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2Protocol.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/LibreVerifiedFrame.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2DiagnosticDecoder.swift" \
  "$root/ios/GlucoScope/Sensor/Libre2/Libre2ProductionDecoder.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingCommitAdmission.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreTypes.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStoreModel.swift" \
  "$root/ios/GlucoScope/Persistence/ReadingStore.swift" \
  "$root/ios/GlucoScope/Service/LibrePersistenceBridge.swift" \
  "$root/ios/GlucoScope/Service/LibreOrderedIngestion.swift" \
  "$root/ios/GlucoScope/Service/LibreCandidateAdapter.swift" \
  "$root/ios/GlucoScope/Service/LibreTransportHandoff.swift" \
  "$root/ios/Libre2Tests/TransportHandoffSmoke.swift" \
  -o "$tmp/libre2-transport-handoff-smoke"
"$tmp/libre2-transport-handoff-smoke"
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
  "$root/ios/GlucoScope/Service/LibreStorageProbe.swift" \
  "$root/ios/Libre2Tests/StorageProbeSmoke.swift" \
  -o "$tmp/libre2-storage-probe-smoke"
"$tmp/libre2-storage-probe-smoke"
