import Foundation

enum OllamaBackendError: LocalizedError {
  case invalidConfiguration, unavailable, timeout, modelUnavailable, httpFailure(Int)
  case malformedResponse

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration: "AI 백엔드 URL 설정이 올바르지 않습니다."
    case .unavailable: "원격 AI 백엔드에 연결할 수 없습니다. deterministic 도구는 계속 사용할 수 있습니다."
    case .timeout: "원격 AI 백엔드 응답 시간이 초과되었습니다."
    case .modelUnavailable: "원격 AI 백엔드에 설정된 모델이 없습니다."
    case .httpFailure(let status): "원격 AI 백엔드 요청에 실패했습니다. (상태 코드: \(status))"
    case .malformedResponse: "원격 AI 백엔드 응답을 해석하지 못했습니다."
    }
  }
}

struct OllamaBackendStatus: Sendable {
  let backend: VisionBackend
  let endpoint: VisionEndpoint?
  let model: String
  let availability: VisionBackendAvailability
}

struct OllamaTransport: Sendable {
  let endpoint: VisionEndpoint?
  let model: String
  let timeout: TimeInterval
  private let client: any ScreenAnalysisHTTPClient
  private let coordinator: OllamaInferenceCoordinator

  init(environment: [String: String]? = nil,
       client: (any ScreenAnalysisHTTPClient)? = nil,
       coordinator: OllamaInferenceCoordinator = .shared) {
    if let environment {
      endpoint = ScreenAnalysisConfiguration.normalEndpoint(environment: environment)
      model = ScreenAnalysisConfiguration.normalModel(environment: environment)
      timeout = ScreenAnalysisConfiguration.normalTimeout(environment: environment)
    } else {
      endpoint = ScreenAnalysisConfiguration.normalEndpoint()
      model = ScreenAnalysisConfiguration.normalModel()
      timeout = ScreenAnalysisConfiguration.normalTimeout()
    }
    self.client = client ?? URLSessionScreenAnalysisClient(timeout: timeout)
    self.coordinator = coordinator
  }

  func chat(body: [String: Any]) async throws -> Data {
    guard let endpoint else { throw OllamaBackendError.invalidConfiguration }
    var request = URLRequest(url: endpoint.chatURL)
    request.httpMethod = "POST"; request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let configuredRequest = request
    do {
      let result = try await coordinator.perform { try await client.data(for: configuredRequest) }
      guard let response = result.response as? HTTPURLResponse else {
        throw OllamaBackendError.malformedResponse
      }
      guard response.statusCode == 200 else {
        if response.statusCode == 404 { throw OllamaBackendError.modelUnavailable }
        throw OllamaBackendError.httpFailure(response.statusCode)
      }
      return result.data
    } catch let error as OllamaBackendError { throw error }
    catch let error as URLError where error.code == .timedOut { throw OllamaBackendError.timeout }
    catch is CancellationError { throw CancellationError() }
    catch { throw OllamaBackendError.unavailable }
  }

  func status() async -> OllamaBackendStatus {
    guard let endpoint else {
      return .init(backend: .unavailable, endpoint: nil, model: model,
        availability: .invalidConfiguration)
    }
    var request = URLRequest(url: endpoint.tagsURL)
    request.timeoutInterval = min(timeout, 10)
    let availability: VisionBackendAvailability
    do {
      let result = try await client.data(for: request)
      guard let response = result.response as? HTTPURLResponse,
        (200..<300).contains(response.statusCode) else {
        return .init(backend: endpoint.isLoopback ? .local : .remote, endpoint: endpoint,
          model: model, availability: .serverUnavailable)
      }
      let root = try JSONSerialization.jsonObject(with: result.data) as? [String: Any]
      let models = root?["models"] as? [[String: Any]]
      availability = models?.contains { ($0["name"] as? String) == model } == true
        ? .available : .modelUnavailable
    } catch let error as URLError where error.code == .timedOut { availability = .timeout }
    catch { availability = .serverUnavailable }
    return .init(backend: endpoint.isLoopback ? .local : .remote, endpoint: endpoint,
      model: model, availability: availability)
  }
}
