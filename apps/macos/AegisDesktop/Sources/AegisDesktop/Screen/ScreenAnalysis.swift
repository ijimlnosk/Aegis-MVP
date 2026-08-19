import Foundation

struct ScreenAnalysis: Codable, Equatable {
  let summary: String
  let detectedApplication: String?
  let detectedWindow: String?
  let visibleErrors: [String]
  let visibleWarnings: [String]
  let visibleCodeContext: String?
  let visibleUIState: String?
  let confidence: Double?
  let limitations: [String]
}

protocol ScreenAnalysisProviding {
  var availabilityDescription: String { get }
  func analyze(snapshot: ScreenSnapshot, trustedContext: String?) async throws -> ScreenAnalysis
}

protocol VisionModelStatusProviding {
  func isModelLoaded() async -> Bool?
}

enum ScreenAnalysisError: LocalizedError {
  case connectionTimeout, inferenceTimeout(TimeInterval), httpFailure(Int)
  case modelUnavailable(String), malformedResponse, cancelled
  case memoryPressureCritical, concurrentRequest
  var errorDescription: String? {
    switch self {
    case .connectionTimeout: "Ollama Vision 서비스 연결 시간이 초과되었습니다."
    case .inferenceTimeout: "화면 캡처에는 성공했지만 Vision 모델 분석 시간이 초과되었습니다. 모델이 처음 로드되는 경우 시간이 더 걸릴 수 있습니다."
    case .httpFailure(let status): "Vision 모델 HTTP 요청에 실패했습니다. (상태 코드: \(status))"
    case .modelUnavailable(let model): "Vision 모델을 사용할 수 없습니다: \(model)"
    case .malformedResponse: "화면 캡처에는 성공했지만 Vision 모델의 응답을 해석하지 못했습니다."
    case .cancelled: "화면 분석이 취소되었습니다."
    case .memoryPressureCritical: "현재 Mac 메모리 사용량이 높아 화면 분석을 시작하지 않았습니다. 일부 앱을 닫거나 저메모리 화면 분석을 사용해 주세요."
    case .concurrentRequest: "이미 다른 화면 분석이 실행 중입니다. 잠시 후 다시 시도해 주세요."
    }
  }
}
