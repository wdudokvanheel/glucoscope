import Foundation
import Combine

@MainActor
final class LibreDiagnosticsUploader: ObservableObject {
    static let defaultEndpoint = "http://10.0.0.22:8765/diagnostics"
    static let endpointDefaultsKey = "libre2.diagnosticsEndpoint"
    static let automaticUploadDefaultsKey = "libre2.automaticDiagnosticsUpload"

    @Published private(set) var isUploading = false
    @Published private(set) var resultMessage = "Not sent yet"
    @Published private(set) var savedFilename: String?

    private var uploadTask: Task<Void, Never>?
    private var requestGeneration: UInt64 = 0
    private var pendingSnapshot: (text: String, endpoint: String)?

    func send(snapshot: String, endpoint: String) {
        guard uploadTask == nil else {
            pendingSnapshot = (snapshot, endpoint)
            return
        }

        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedEndpoint),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            resultMessage = "Enter a valid HTTP or HTTPS diagnostics URL"
            savedFilename = nil
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        isUploading = true
        resultMessage = "Sending…"
        savedFilename = nil

        uploadTask = Task { [weak self] in
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(snapshot.utf8)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw UploadError.invalidResponse
                }
                guard httpResponse.statusCode == 201 else {
                    let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    throw UploadError.httpStatus(httpResponse.statusCode, detail)
                }

                let receipt = try JSONDecoder().decode(UploadReceipt.self, from: data)
                guard !receipt.saved.isEmpty else { throw UploadError.invalidResponse }
                self?.finish(generation: generation, message: "Sent successfully", filename: receipt.saved)
            } catch is CancellationError {
                return
            } catch {
                self?.finish(generation: generation, message: "Send failed: \(error.localizedDescription)", filename: nil)
            }
        }
    }

    func endpointDidChange() {
        requestGeneration &+= 1
        uploadTask?.cancel()
        pendingSnapshot = nil
        uploadTask = nil
        isUploading = false
        resultMessage = "Not sent yet"
        savedFilename = nil
    }

    private func finish(generation: UInt64, message: String, filename: String?) {
        guard generation == requestGeneration else { return }
        uploadTask = nil
        isUploading = false
        resultMessage = message
        savedFilename = filename
        if let pending = pendingSnapshot {
            pendingSnapshot = nil
            send(snapshot: pending.text, endpoint: pending.endpoint)
        }
    }
}

private extension LibreDiagnosticsUploader {
    struct UploadReceipt: Decodable {
        let saved: String
    }

    enum UploadError: LocalizedError {
        case invalidResponse
        case httpStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The host returned an invalid response"
            case .httpStatus(let status, let detail):
                if let detail, !detail.isEmpty {
                    return "Host returned HTTP \(status): \(detail)"
                }
                return "Host returned HTTP \(status)"
            }
        }
    }
}
