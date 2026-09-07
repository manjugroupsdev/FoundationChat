import Foundation

enum MobileStoragePurpose: String, Sendable {
  case attendancePhoto = "attendance.photo"
  case staffDocument = "staff.document"
  case chatAttachment = "chat.attachment"
  case projectMedia = "project.media"
  case mobileGeneric = "mobile.generic"

  var maxBytes: Int {
    self == .attendancePhoto ? 10 * 1_024 * 1_024 : 100 * 1_024 * 1_024
  }
}

enum MobileStorageError: LocalizedError, Sendable {
  case invalidURL
  case invalidContract(String)
  case rejected(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "The storage service address is invalid."
    case .invalidContract(let message):
      return message
    case .rejected(let status, let message):
      return message.isEmpty ? "File upload failed (HTTP \(status))." : message
    }
  }
}

enum MobileStorageService {
  private struct CreateRequest: Encodable {
    let fileName: String
    let contentType: String
    let sizeBytes: Int
    let purpose: String
  }

  private struct CreateResponse: Decodable {
    let success: Bool
    let fileId: String?
    let storageId: String?
    let uploadUrl: String?
    let method: String?
    let requiredHeaders: [String: String]?
    let maxSizeBytes: Int?
    let error: String?
  }

  private struct CompleteRequest: Encodable {
    let storageId: String
  }

  private struct CompleteResponse: Decodable {
    let success: Bool
    let status: String?
    let storageId: String?
    let error: String?
  }

  private struct CompatibilityResponse: Decodable {
    let success: Bool?
    let storageId: String?
    let error: String?
  }

  private enum PreferredResult {
    case success(String)
    case unavailable
  }

  static func upload(
    token: String,
    data: Data,
    fileName: String,
    contentType: String,
    purpose: MobileStoragePurpose,
    attempts: Int = 3
  ) async throws -> String {
    guard !data.isEmpty else {
      throw MobileStorageError.invalidContract("The selected file is empty.")
    }
    let maxBytes = min(AppConfig.storageMaxFileBytes, purpose.maxBytes)
    guard data.count <= maxBytes else {
      throw MobileStorageError.invalidContract(
        "File is too large. Maximum is \(maxBytes / (1_024 * 1_024)) MB."
      )
    }
    guard contentType.lowercased() != "image/svg+xml",
          !fileName.lowercased().hasSuffix(".svg") else {
      throw MobileStorageError.invalidContract("SVG files are not supported.")
    }

    if AppConfig.storageUploadsEnabled {
      switch try await preferredUpload(
        token: token,
        data: data,
        fileName: fileName,
        contentType: contentType,
        purpose: purpose,
        attempts: max(1, attempts)
      ) {
      case .success(let storageId):
        return storageId
      case .unavailable:
        break
      }
    }

    return try await compatibilityUpload(
      token: token,
      data: data,
      fileName: fileName,
      contentType: contentType,
      purpose: purpose,
      attempts: max(1, attempts)
    )
  }

  private static func preferredUpload(
    token: String,
    data: Data,
    fileName: String,
    contentType: String,
    purpose: MobileStoragePurpose,
    attempts: Int
  ) async throws -> PreferredResult {
    guard let createURL = URL(string: "\(AppConfig.storageBaseURL)/api/storage/uploads") else {
      throw MobileStorageError.invalidURL
    }
    let idempotencyKey = "mobile-upload-\(UUID().uuidString.lowercased())"
    var createRequest = URLRequest(url: createURL)
    createRequest.httpMethod = "POST"
    createRequest.timeoutInterval = 30
    createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    createRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    createRequest.httpBody = try JSONEncoder().encode(
      CreateRequest(
        fileName: fileName,
        contentType: contentType,
        sizeBytes: data.count,
        purpose: purpose.rawValue
      )
    )

    let (createData, createResponse) = try await performWithRetry(
      createRequest,
      attempts: attempts,
      retryServiceUnavailable: false
    )
    guard let createHTTP = createResponse as? HTTPURLResponse else {
      throw MobileStorageError.invalidContract("Storage service returned an invalid response.")
    }
    if createHTTP.statusCode == 404 || createHTTP.statusCode == 503 {
      return .unavailable
    }
    try requireSuccess(createHTTP, data: createData, stage: "Upload creation")

    let contract = try JSONDecoder().decode(CreateResponse.self, from: createData)
    guard contract.success,
          let fileId = contract.fileId?.storageNonBlank,
          let storageId = contract.storageId?.storageNonBlank,
          let uploadURLString = contract.uploadUrl?.storageNonBlank,
          let uploadURL = URL(string: uploadURLString),
          contract.method?.uppercased() == "PUT" else {
      throw MobileStorageError.invalidContract(
        contract.error ?? "Storage service returned an incomplete upload contract."
      )
    }
    if let serverMax = contract.maxSizeBytes, data.count > serverMax {
      await abort(token: token, fileId: fileId)
      throw MobileStorageError.invalidContract("File is larger than the server limit.")
    }

    var putRequest = URLRequest(url: uploadURL)
    putRequest.httpMethod = "PUT"
    putRequest.timeoutInterval = 180
    for (name, value) in contract.requiredHeaders ?? [:] {
      putRequest.setValue(value, forHTTPHeaderField: name)
    }
    do {
      let (putData, putResponse) = try await uploadWithRetry(
        putRequest,
        data: data,
        attempts: attempts
      )
      guard let putHTTP = putResponse as? HTTPURLResponse else {
        throw MobileStorageError.invalidContract("File host returned an invalid response.")
      }
      try requireSuccess(putHTTP, data: putData, stage: "File upload")
    } catch {
      await abort(token: token, fileId: fileId)
      throw error
    }

    let encodedFileId = fileId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileId
    guard let completeURL = URL(
      string: "\(AppConfig.storageBaseURL)/api/storage/uploads/\(encodedFileId)/complete"
    ) else { throw MobileStorageError.invalidURL }
    var completeRequest = URLRequest(url: completeURL)
    completeRequest.httpMethod = "POST"
    completeRequest.timeoutInterval = 30
    completeRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    completeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    completeRequest.httpBody = try JSONEncoder().encode(CompleteRequest(storageId: storageId))
    let (completeData, completeResponse) = try await performWithRetry(
      completeRequest,
      attempts: attempts
    )
    guard let completeHTTP = completeResponse as? HTTPURLResponse else {
      throw MobileStorageError.invalidContract("Storage completion returned an invalid response.")
    }
    try requireSuccess(completeHTTP, data: completeData, stage: "Upload completion")
    let completed = try JSONDecoder().decode(CompleteResponse.self, from: completeData)
    guard completed.success, completed.status == "ready", completed.storageId == storageId else {
      throw MobileStorageError.invalidContract(
        completed.error ?? "Storage completion was not confirmed."
      )
    }
    return .success(storageId)
  }

  private static func compatibilityUpload(
    token: String,
    data: Data,
    fileName: String,
    contentType: String,
    purpose: MobileStoragePurpose,
    attempts: Int
  ) async throws -> String {
    guard let url = URL(string: "\(AppConfig.baseURL)/api/storage/upload") else {
      throw MobileStorageError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 180
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue(purpose.rawValue, forHTTPHeaderField: "X-Storage-Purpose")
    request.setValue(fileName, forHTTPHeaderField: "X-File-Name")
    let (responseData, response) = try await uploadWithRetry(request, data: data, attempts: attempts)
    guard let http = response as? HTTPURLResponse else {
      throw MobileStorageError.invalidContract("Upload server returned an invalid response.")
    }
    try requireSuccess(http, data: responseData, stage: "Upload")
    let wrapper = try JSONDecoder().decode(CompatibilityResponse.self, from: responseData)
    guard wrapper.success != false, let storageId = wrapper.storageId?.storageNonBlank else {
      throw MobileStorageError.invalidContract(
        wrapper.error ?? "The upload did not return a storage ID."
      )
    }
    return storageId
  }

  private static func abort(token: String, fileId: String) async {
    let encoded = fileId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileId
    guard let url = URL(string: "\(AppConfig.storageBaseURL)/api/storage/uploads/\(encoded)") else {
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.timeoutInterval = 15
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    _ = try? await URLSession.shared.data(for: request)
  }

  private static func performWithRetry(
    _ request: URLRequest,
    attempts: Int,
    retryServiceUnavailable: Bool = true
  ) async throws -> (Data, URLResponse) {
    var lastError: Error?
    for attempt in 0..<attempts {
      do {
        let result = try await URLSession.shared.data(for: request)
        if let http = result.1 as? HTTPURLResponse,
           http.statusCode >= 500,
           (http.statusCode != 503 || retryServiceUnavailable),
           attempt + 1 < attempts {
          try await Task.sleep(for: .milliseconds(1_500 * (attempt + 1)))
          continue
        }
        return result
      } catch {
        if error is CancellationError { throw error }
        lastError = error
        guard attempt + 1 < attempts else { throw error }
        try await Task.sleep(for: .milliseconds(1_500 * (attempt + 1)))
      }
    }
    throw lastError ?? MobileStorageError.invalidContract("Storage request failed.")
  }

  private static func uploadWithRetry(
    _ request: URLRequest,
    data: Data,
    attempts: Int
  ) async throws -> (Data, URLResponse) {
    var lastError: Error?
    for attempt in 0..<attempts {
      do {
        let result = try await URLSession.shared.upload(for: request, from: data)
        if let http = result.1 as? HTTPURLResponse,
           http.statusCode >= 500,
           attempt + 1 < attempts {
          try await Task.sleep(for: .milliseconds(1_500 * (attempt + 1)))
          continue
        }
        return result
      } catch {
        if error is CancellationError { throw error }
        lastError = error
        guard attempt + 1 < attempts else { throw error }
        try await Task.sleep(for: .milliseconds(1_500 * (attempt + 1)))
      }
    }
    throw lastError ?? MobileStorageError.invalidContract("File upload failed.")
  }

  private static func requireSuccess(
    _ response: HTTPURLResponse,
    data: Data,
    stage: String
  ) throws {
    guard (200..<300).contains(response.statusCode) else {
      let message = serverMessage(from: data) ?? "\(stage) failed (HTTP \(response.statusCode))."
      throw MobileStorageError.rejected(response.statusCode, message)
    }
  }

  private static func serverMessage(from data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return (object["error"] as? String)?.storageNonBlank
      ?? (object["message"] as? String)?.storageNonBlank
  }
}

private extension String {
  var storageNonBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
