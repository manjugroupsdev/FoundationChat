import Foundation

private nonisolated struct UnsafeTransfer<Value>: @unchecked Sendable {
    let value: Value
}

enum BackgroundJSONDecoder {
    nonisolated static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) async throws -> T {
        let input = UnsafeTransfer(value: (type, data))
        let output: UnsafeTransfer<T> = try await Task.detached(priority: .userInitiated) {
            UnsafeTransfer(
                value: try JSONDecoder().decode(input.value.0, from: input.value.1)
            )
        }.value
        return output.value
    }
}
