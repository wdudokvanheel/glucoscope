import Foundation

protocol ServerUploadTransport: Sendable {
    func test(destination: ServerUploadDestination, secret: String?) async -> Result<Int, ServerUploadError>
    func send(
        _ delivery: ServerUploadDelivery,
        to destination: ServerUploadDestination,
        secret: String?
    ) async -> Result<Int, ServerUploadError>
}

struct URLSessionServerUploadTransport: ServerUploadTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func test(
        destination: ServerUploadDestination,
        secret: String?
    ) async -> Result<Int, ServerUploadError> {
        do {
            let url: URL
            switch destination.backend {
            case .nightscout:
                url = try nightscoutURL(destination: destination, path: "/api/v1/status.json", secret: secret)
            case .glucoScope:
                url = try customURL(destination: destination, path: "/api/s1/status")
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            applyBearer(secret, to: &request, backend: destination.backend)
            let (data, response) = try await session.data(for: request)
            let code = try validate(response: response, data: data)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["status"] as? String)?.lowercased() == "ok" else {
                return .failure(.invalidResponse)
            }
            return .success(code)
        } catch let error as ServerUploadError {
            return .failure(error)
        } catch {
            return .failure(.network(Self.safeNetworkMessage(error)))
        }
    }

    func send(
        _ delivery: ServerUploadDelivery,
        to destination: ServerUploadDestination,
        secret: String?
    ) async -> Result<Int, ServerUploadError> {
        do {
            let url: URL
            let body: Data
            switch destination.backend {
            case .nightscout:
                url = try nightscoutURL(destination: destination, path: "/api/v1/entries.json", secret: secret)
                body = try JSONSerialization.data(withJSONObject: [[
                    "_id": Self.nightscoutID(delivery.readingID),
                    "device": "GlucoScope",
                    "type": "sgv",
                    "sgv": delivery.glucoseMGDL,
                    "date": Int64(delivery.sampleDate.timeIntervalSince1970 * 1_000),
                    "dateString": ISO8601DateFormatter().string(from: delivery.sampleDate)
                ]])
            case .glucoScope:
                url = try customURL(destination: destination, path: "/api/s1/entries")
                body = try JSONSerialization.data(withJSONObject: [
                    "id": delivery.readingID.uuidString.lowercased(),
                    "time": Int64(delivery.sampleDate.timeIntervalSince1970),
                    "value": Double(delivery.glucoseMGDL) / 18.0182
                ])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            applyBearer(secret, to: &request, backend: destination.backend)
            let (data, response) = try await session.data(for: request)
            return .success(try validate(response: response, data: data))
        } catch let error as ServerUploadError {
            return .failure(error)
        } catch {
            return .failure(.network(Self.safeNetworkMessage(error)))
        }
    }

    private func nightscoutURL(
        destination: ServerUploadDestination,
        path: String,
        secret: String?
    ) throws -> URL {
        guard var components = URLComponents(string: destination.endpoint + path) else {
            throw ServerUploadError.invalidEndpoint
        }
        if let secret, !secret.isEmpty {
            components.queryItems = [URLQueryItem(name: "token", value: secret)]
        }
        guard let url = components.url else { throw ServerUploadError.invalidEndpoint }
        return url
    }

    private func customURL(destination: ServerUploadDestination, path: String) throws -> URL {
        guard let url = URL(string: destination.endpoint + path) else {
            throw ServerUploadError.invalidEndpoint
        }
        return url
    }

    private func applyBearer(
        _ secret: String?,
        to request: inout URLRequest,
        backend: ServerUploadBackend
    ) {
        guard backend == .glucoScope, let secret, !secret.isEmpty else { return }
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    private func validate(response: URLResponse, data: Data) throws -> Int {
        guard let response = response as? HTTPURLResponse else {
            throw ServerUploadError.invalidResponse
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ServerUploadError.authentication
        }
        guard (200...299).contains(response.statusCode) else {
            let message = String(data: data.prefix(300), encoding: .utf8) ?? "Request was rejected"
            throw ServerUploadError.server(
                status: response.statusCode,
                message: ServerUploadRedactor.message(message)
            )
        }
        return response.statusCode
    }

    private static func nightscoutID(_ id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24))
    }

    private static func safeNetworkMessage(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code))"
    }
}
