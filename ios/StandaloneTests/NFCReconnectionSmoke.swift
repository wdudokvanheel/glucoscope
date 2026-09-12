import Foundation

@main
struct NFCReconnectionSmoke {
    static func main() {
        let uid = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let patch = Data([0x7F, 0x0E, 0x30, 1, 4, 5])
        let paired = LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "test", unlockCode: 42,
                                        setupComplete: true, sensorKind: .libre2_7F)
        let reconnect = LibreNFCScanPurpose.reconnect(paired)
        precondition(reconnect.pairedSensor == paired, "reconnect retains expected sensor before scanning")
        precondition(reconnect.acceptsDetectedIdentity(uid: uid), "paired UID accepted at tag detection")
        var otherUID = uid; otherUID[0] = 99
        precondition(!reconnect.acceptsDetectedIdentity(uid: otherUID), "different UID rejected before any sensor commands")
        precondition(!reconnect.acceptsDetectedIdentity(uid: otherUID, patchInfo: patch), "matching patch cannot override UID mismatch")
        var stableChange = patch; stableChange[1] = 99
        precondition(!reconnect.acceptsDetectedIdentity(uid: uid, patchInfo: stableChange), "stable identity change rejected before streaming or save")
        var mutableChange = patch; mutableChange[4] = 99; mutableChange[5] = 98
        precondition(reconnect.acceptsDetectedIdentity(uid: uid, patchInfo: mutableChange), "mutable patch tail does not imply replacement")
        precondition(LibreNFCScanPurpose.setup.acceptsDetectedIdentity(uid: otherUID, patchInfo: stableChange), "replacement setup remains explicitly unconstrained")
        precondition(!LibreNFCScanPurpose.calibration(paired).acceptsDetectedIdentity(uid: otherUID), "calibration retains same sensor guard")
        precondition(!LibreNFCScanPurpose.history(paired).acceptsDetectedIdentity(uid: uid, patchInfo: stableChange), "history retains stable identity guard")
        print("NFC reconnect: 9 identity-boundary checks passed; no physical NFC operations")
    }
}
