import Foundation

enum ServerUploadBackend: String, Codable, CaseIterable, Sendable {
    case nightscout
    case glucoScope

    var title: String {
        switch self {
        case .nightscout: return "Nightscout"
        case .glucoScope: return "GlucoScope Server"
        }
    }
}

struct ServerUploadDestination: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var backend: ServerUploadBackend
    /// Canonical address only. Credentials and URL query items are never persisted here.
    var endpoint: String
    var credentialReference: String
    var endpointRevision: Int
    var enabled: Bool
    var paused: Bool
    let createdAt: Date
    var automaticUploadSince: Date
    var disabledAt: Date?
}

enum ServerUploadBatchKind: String, Codable, CaseIterable, Sendable {
    case newReading
    case history
    case disabledCatchUp
    case migratedPending
    case migrationBackfill

    var isBulk: Bool { self != .newReading }
}

enum ServerUploadDeliveryState: String, Codable, CaseIterable, Sendable {
    case queued
    case sending
    case failed
    case acknowledged
}

struct ServerUploadDelivery: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let destinationID: UUID
    let readingID: UUID
    let endpointRevision: Int
    let sampleDate: Date
    let committedAt: Date
    let glucoseMGDL: Int
    let batchKind: ServerUploadBatchKind
    let queuedAt: Date
    var state: ServerUploadDeliveryState
    var attemptCount: Int
    var nextEligibleAt: Date?
    var lastError: String?
    var acknowledgedAt: Date?
    var discardAfterAttempt: Bool
}

enum ServerUploadAttemptOutcome: String, Codable, Sendable {
    case succeeded
    case failed
    case cancelled
    case interrupted
}

struct ServerUploadAttempt: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let destinationID: UUID
    let readingID: UUID?
    let endpointRevision: Int
    let occurredAt: Date
    let outcome: ServerUploadAttemptOutcome
    let responseCode: Int?
    let message: String
}

struct ServerUploadProgress: Equatable, Sendable {
    let pendingCount: Int
    let failedCount: Int
    let currentSampleDate: Date?
    let targetStartDate: Date?
}

struct ServerUploadSnapshot: Equatable, Sendable {
    let destinations: [ServerUploadDestination]
    let deliveries: [ServerUploadDelivery]
    let attempts: [ServerUploadAttempt]

    var pendingCount: Int {
        deliveries.lazy.filter { $0.state != .acknowledged }.count
    }

    func progress(for destinationID: UUID) -> ServerUploadProgress {
        let pending = deliveries.filter {
            $0.destinationID == destinationID && $0.state != .acknowledged
        }
        return ServerUploadProgress(
            pendingCount: pending.count,
            failedCount: pending.lazy.filter { $0.state == .failed }.count,
            currentSampleDate: pending.first(where: { $0.state == .sending })?.sampleDate,
            targetStartDate: pending.map(\.sampleDate).min()
        )
    }
}

enum ServerUploadHistorySelection: Equatable, Sendable {
    case since(Date)
    case allAvailable
}

enum ServerUploadError: Error, LocalizedError, Equatable, Sendable {
    case invalidName
    case invalidEndpoint
    case destinationNotFound
    case destinationDisabled
    case persistence(String)
    case authentication
    case uploadsNotConfigured
    case writePermissionDenied
    case writePermissionUnavailable
    case server(status: Int, message: String)
    case network(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a destination name."
        case .invalidEndpoint: return "Enter a valid HTTP or HTTPS server address."
        case .destinationNotFound: return "This destination no longer exists."
        case .destinationDisabled: return "Enable this destination before retrying."
        case .persistence: return "Upload data could not be saved."
        case .authentication: return "Authentication failed. Check the token and server permissions."
        case .uploadsNotConfigured: return "The server is reachable, but uploads are disabled. Configure its API token first."
        case .writePermissionDenied: return "The token is valid but cannot create glucose entries. Give it entries create permission."
        case .writePermissionUnavailable: return "The server is reachable, but this version cannot verify write permission without creating data."
        case .server(let status, let message): return "Server error \(status): \(message)"
        case .network(let message): return "Could not reach the server: \(message)"
        case .invalidResponse: return "The server returned an unexpected response."
        }
    }
}

enum ServerUploadEndpoint {
    static func normalize(_ entered: String) throws -> String {
        let trimmed = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            throw ServerUploadError.invalidEndpoint
        }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let result = components.url?.absoluteString else {
            throw ServerUploadError.invalidEndpoint
        }
        return result.hasSuffix("/") ? String(result.dropLast()) : result
    }
}

enum ServerUploadRedactor {
    static func message(_ value: String, secrets: [String] = []) -> String {
        var result = String(value.prefix(500))
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: "<redacted>")
        }
        // Remove URL query strings, which commonly carry Nightscout access tokens.
        result = result.replacingOccurrences(
            of: #"(https?://[^\s?]+)\?[^\s]+"#,
            with: "$1?<redacted>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(authorization|token|secret|password)\s*[:=]\s*[^\s,;]+"#,
            with: "$1=<redacted>",
            options: .regularExpression
        )
        return result
    }
}
