import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RequestRecorder: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))!

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@main
enum ServerUploadTransportSmoke {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestRecorder.self]
        let transport = URLSessionServerUploadTransport(session: URLSession(configuration: configuration))

        let custom = destination(.glucoScope, "https://custom.example")
        RequestRecorder.handler = { request in
            expect(request.httpMethod == "GET", "test connection must not drain the queue")
            expect(request.url?.path == "/api/s1/status", "custom status route mismatch")
            expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-token", "custom bearer token missing")
            return (response(request, 200), Data(#"{"status":"ok"}"#.utf8))
        }
        guard case .success(200) = await transport.test(destination: custom, secret: "private-token") else {
            fatalError("custom connection test failed")
        }

        let nightscout = destination(.nightscout, "https://nightscout.example")
        RequestRecorder.handler = { request in
            expect(request.url?.path == "/api/v1/entries.json", "Nightscout upload route mismatch")
            expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "access-token", "Nightscout token missing")
            let object = try JSONSerialization.jsonObject(with: bodyData(request)) as! [[String: Any]]
            expect(object[0]["sgv"] as? Int == 126, "Nightscout must upload mg/dL")
            expect((object[0]["_id"] as? String)?.count == 24, "Nightscout idempotency id mismatch")
            return (response(request, 201), Data())
        }
        guard case .success(201) = await transport.send(delivery(), to: nightscout, secret: "access-token") else {
            fatalError("Nightscout send failed")
        }

        RequestRecorder.handler = { request in
            expect(request.url?.query == nil, "custom token must not appear in URL")
            let object = try JSONSerialization.jsonObject(with: bodyData(request)) as! [String: Any]
            let mmol = object["value"] as! Double
            expect(abs(mmol - 126 / 18.0182) < 0.000_001, "custom backend must receive mmol/L")
            return (response(request, 201), Data())
        }
        _ = await transport.send(delivery(), to: custom, secret: "private-token")
        print("ServerUploadTransportSmoke: PASS")
    }

    private static func destination(_ backend: ServerUploadBackend, _ endpoint: String) -> ServerUploadDestination {
        ServerUploadDestination(
            id: UUID(), name: "Test", backend: backend, endpoint: endpoint,
            credentialReference: "memory", endpointRevision: 1, enabled: true, paused: false,
            createdAt: Date(), automaticUploadSince: Date(), disabledAt: nil
        )
    }

    private static func delivery() -> ServerUploadDelivery {
        ServerUploadDelivery(
            id: UUID(), destinationID: UUID(), readingID: UUID(uuidString: "84A146BE-1A63-4D09-8F8D-704DA981F6A4")!,
            endpointRevision: 1, sampleDate: Date(timeIntervalSince1970: 1_742_644_800),
            committedAt: Date(), glucoseMGDL: 126, batchKind: .newReading, queuedAt: Date(),
            state: .sending, attemptCount: 1, nextEligibleAt: nil, lastError: nil,
            acknowledgedAt: nil, discardAfterAttempt: false
        )
    }

    private static func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func bodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw ServerUploadError.invalidResponse }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? ServerUploadError.invalidResponse }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
