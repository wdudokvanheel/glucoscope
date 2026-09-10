import Foundation

enum LibreReadRetry {
    @MainActor
    static func run<Value>(
        maxAttempts: Int,
        delayNanoseconds: UInt64,
        isCancelled: () -> Bool = { false },
        shouldRetry: (Error) -> Bool,
        onRetry: (Int, Error) async -> Void = { _, _ in },
        operation: (Int) async throws -> Value
    ) async throws -> Value {
        precondition(maxAttempts > 0)

        for attempt in 1...maxAttempts {
            if isCancelled() { throw CancellationError() }
            do {
                let value = try await operation(attempt)
                if isCancelled() { throw CancellationError() }
                return value
            } catch {
                if error is CancellationError { throw error }
                guard attempt < maxAttempts, shouldRetry(error) else { throw error }
                await onRetry(attempt + 1, error)
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                if isCancelled() { throw CancellationError() }
            }
        }

        preconditionFailure("A positive attempt count always returns or throws")
    }
}
