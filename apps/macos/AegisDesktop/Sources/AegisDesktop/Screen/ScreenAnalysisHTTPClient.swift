import Foundation

struct ScreenAnalysisHTTPResult: @unchecked Sendable {
  let data: Data
  let response: URLResponse
}

protocol ScreenAnalysisHTTPClient: Sendable {
  func data(for request: URLRequest) async throws -> ScreenAnalysisHTTPResult
}

struct URLSessionScreenAnalysisClient: ScreenAnalysisHTTPClient, @unchecked Sendable {
  private let session: URLSession

  init(timeout: TimeInterval) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout + 15
    configuration.waitsForConnectivity = false
    session = URLSession(configuration: configuration)
  }

  func data(for request: URLRequest) async throws -> ScreenAnalysisHTTPResult {
    let (data, response) = try await session.data(for: request)
    return ScreenAnalysisHTTPResult(data: data, response: response)
  }
}
