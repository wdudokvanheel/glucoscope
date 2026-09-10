import CoreData
import Foundation

enum ReadingStoreEntity {
    static let session = "StoredSensorSession"
    static let reading = "StoredReading"
    static let delivery = "ReadingDelivery"
    static let destination = "UploadDestination"
    static let conflict = "ReadingConflict"
}

enum ReadingStoreModel {
    static let versionIdentifier = "GlucoScopeReadingStoreV1"

    static func make() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = [versionIdentifier]

        let session = entity(
            ReadingStoreEntity.session,
            attributes: [
                attribute("id", .UUIDAttributeType, optional: false),
                attribute("stableIdentityFingerprint", .binaryDataAttributeType, optional: false),
                attribute("sensorRevision", .stringAttributeType, optional: false),
                attribute("firstObservedAt", .dateAttributeType, optional: false),
                attribute("lastObservedAt", .dateAttributeType, optional: false),
                attribute("lifecycleState", .stringAttributeType, optional: false),
                attribute("clockReferenceSensorMinute", .integer64AttributeType, optional: false),
                attribute("clockReferenceDate", .dateAttributeType, optional: false),
                attribute("clockProvenance", .stringAttributeType, optional: false)
            ],
            unique: [["id"]]
        )

        let reading = entity(
            ReadingStoreEntity.reading,
            attributes: [
                attribute("id", .UUIDAttributeType, optional: false),
                attribute("sessionID", .UUIDAttributeType, optional: false),
                attribute("sensorMinute", .integer64AttributeType, optional: false),
                attribute("sampleKind", .stringAttributeType, optional: false),
                attribute("sampleDate", .dateAttributeType, optional: false),
                attribute("receivedAt", .dateAttributeType, optional: false),
                attribute("glucoseMGDL", .integer32AttributeType, optional: false),
                attribute("quality", .stringAttributeType, optional: false),
                attribute("primaryOrigin", .stringAttributeType, optional: false),
                attribute("observedOriginFlags", .integer64AttributeType, optional: false),
                attribute("decoderVersion", .stringAttributeType, optional: false),
                attribute("createdAt", .dateAttributeType, optional: false)
            ],
            unique: [["id"], ["sessionID", "sensorMinute", "sampleKind"]]
        )

        let delivery = entity(
            ReadingStoreEntity.delivery,
            attributes: [
                attribute("readingID", .UUIDAttributeType, optional: false),
                attribute("destinationID", .UUIDAttributeType, optional: true),
                attribute("state", .stringAttributeType, optional: false),
                attribute("payload", .binaryDataAttributeType, optional: true),
                attribute("payloadVersion", .integer32AttributeType, optional: true),
                attribute("attemptCount", .integer32AttributeType, optional: false, defaultValue: 0),
                attribute("leaseID", .UUIDAttributeType, optional: true),
                attribute("leaseExpiresAt", .dateAttributeType, optional: true),
                attribute("nextEligibleAt", .dateAttributeType, optional: true),
                attribute("lastError", .stringAttributeType, optional: true),
                attribute("acknowledgedAt", .dateAttributeType, optional: true)
            ],
            unique: [["readingID"]]
        )

        let destination = entity(
            ReadingStoreEntity.destination,
            attributes: [
                attribute("id", .UUIDAttributeType, optional: false),
                attribute("backendKind", .stringAttributeType, optional: false),
                attribute("normalizedEndpointIdentity", .stringAttributeType, optional: false),
                attribute("credentialReference", .stringAttributeType, optional: false),
                attribute("configurationRevision", .integer64AttributeType, optional: false),
                attribute("enabled", .booleanAttributeType, optional: false),
                attribute("selected", .booleanAttributeType, optional: false, defaultValue: false)
            ],
            unique: [["id"]]
        )

        let conflict = entity(
            ReadingStoreEntity.conflict,
            attributes: [
                attribute("id", .UUIDAttributeType, optional: false),
                attribute("readingID", .UUIDAttributeType, optional: false),
                attribute("observedAt", .dateAttributeType, optional: false),
                attribute("candidateOrigin", .stringAttributeType, optional: false),
                attribute("discrepancyFlags", .stringAttributeType, optional: false)
            ],
            unique: [["id"]]
        )

        model.entities = [session, reading, delivery, destination, conflict]
        return model
    }

    private static func entity(
        _ name: String,
        attributes: [NSAttributeDescription],
        unique: [[String]]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = attributes
        entity.uniquenessConstraints = unique
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }
}
