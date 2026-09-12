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
            return (response(request, 200), Data(#"{"status":"ok","uploadsEnabled":true}"#.utf8))
        }
        guard case .success(200) = await transport.test(destination: custom, secret: "private-token") else {
            fatalError("custom connection test failed")
        }
        RequestRecorder.handler = { request in
            (response(request, 200), Data(#"{"status":"ok","uploadsEnabled":false}"#.utf8))
        }
        guard case .failure(.uploadsNotConfigured) = await transport.test(destination: custom, secret: "private-token") else {
            fatalError("read-only custom server must not pass a write configuration test")
        }

        let nightscout = destination(.nightscout, "https://nightscout.example")
        var testStep = 0
        RequestRecorder.handler = { request in
            testStep += 1
            switch testStep {
            case 1:
                expect(request.url?.path == "/api/v1/status.json", "Nightscout connectivity route mismatch")
                expect(request.url?.query == nil, "public status check must not expose token")
                return (response(request, 200), Data(#"{"status":"ok","apiEnabled":true}"#.utf8))
            case 2:
                expect(request.url?.path.contains("/api/v2/authorization/request/token=access-token") == true, "Nightscout token validation route mismatch")
                return (response(request, 200), Data(#"{"token":"short-lived-jwt"}"#.utf8))
            default:
                expect(request.url?.path == "/api/v3/status", "Nightscout permission route mismatch")
                expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer short-lived-jwt", "JWT missing")
                return (response(request, 200), Data(#"{"result":{"apiPermissions":{"entries":"crud"}}}"#.utf8))
            }
        }
        guard case .success(200) = await transport.test(destination: nightscout, secret: "access-token") else {
            fatalError("Nightscout connection and write-permission test failed")
        }
        expect(testStep == 3, "Nightscout test must verify connectivity, token, and create permission")

        testStep = 0
        RequestRecorder.handler = { request in
            testStep += 1
            if testStep == 1 {
                return (response(request, 200), Data(#"{"status":"ok","apiEnabled":true}"#.utf8))
            }
            return (response(request, 404), Data())
        }
        guard case .failure(.writePermissionUnavailable) = await transport.test(destination: nightscout, secret: "access-token") else {
            fatalError("Nightscout without permission introspection must report write verification unavailable")
        }

        testStep = 0
        RequestRecorder.handler = { request in
            testStep += 1
            switch testStep {
            case 1: return (response(request, 200), Data(#"{"status":"ok","apiEnabled":true}"#.utf8))
            case 2: return (response(request, 200), Data(#"{"token":"short-lived-jwt"}"#.utf8))
            default: return (response(request, 200), Data(#"{"result":{"apiPermissions":{"entries":"r"}}}"#.utf8))
            }
        }
        guard case .failure(.writePermissionDenied) = await transport.test(destination: nightscout, secret: "access-token") else {
            fatalError("read-only Nightscout token must fail a write configuration test")
        }

        RequestRecorder.handler = { request in
            expect(request.url?.path == "/api/v1/entries.json", "Nightscout upload route mismatch")
            expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "access-token", "Nightscout token missing")
            let object = try JSONSerialization.jsonObject(with: bodyData(request)) as! [[String: Any]]
            expect(object[0]["sgv"] as? Int == 126, "Nightscout must upload mg/dL")
            expect((object[0]["_id"] as? String)?.count == 36, "Nightscout idempotency UUID mismatch")
            // The v1 handler echoes stored entries. A nonempty success body is
            // affirmative acceptance, not a list of rejected records.
            return (response(request, 200), Data(#"[{"_id":"507f1f77bcf86cd799439011","sgv":126}]"#.utf8))
        }
        guard case .success(200) = await transport.send(delivery(), to: nightscout, secret: "access-token") else {
            fatalError("Nightscout stored-entry response must complete the delivery")
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
