import Foundation
import Testing
@testable import AegisDesktop

@Test func normalVisionResponseCompletesBeforeTimeout() async throws {
  let provider = OllamaScreenAnalysisProvider(timeout: 1, client: VisionClient(delay: .zero))
  let result = try await provider.analyze(snapshot: try snapshot(), trustedContext: nil)
  #expect(result.summary == "화면 설명")
}

@Test func slowVisionResponseWithinTimeoutSucceeds() async throws {
  let provider = OllamaScreenAnalysisProvider(timeout: 0.2,
    client: VisionClient(delay: .milliseconds(50)))
  let result = try await provider.analyze(snapshot: try snapshot(), trustedContext: nil)
  #expect(result.summary == "화면 설명")
}

@Test func inferenceTimeoutIsTypedAndRetrySucceeds() async throws {
  let client = SequencedVisionClient(delays: [.milliseconds(100), .zero])
  let provider = OllamaScreenAnalysisProvider(timeout: 0.02, client: client)
  do {
    _ = try await provider.analyze(snapshot: try snapshot(), trustedContext: nil)
    Issue.record("Expected inference timeout")
  } catch let error as ScreenAnalysisError {
    guard case .inferenceTimeout = error else { Issue.record("Wrong typed error"); return }
    #expect(error.localizedDescription.contains("분석 시간이 초과"))
  }
  let retried = try await provider.analyze(snapshot: try snapshot(), trustedContext: nil)
  #expect(retried.summary == "화면 설명")
}

@Test func cancellationIsTypedAndDoesNotCrash() async throws {
  let provider = OllamaScreenAnalysisProvider(timeout: 1,
    client: VisionClient(delay: .milliseconds(300)))
  let task = Task { try await provider.analyze(snapshot: try snapshot(), trustedContext: nil) }
  try await Task.sleep(for: .milliseconds(10)); task.cancel()
  do { _ = try await task.value; Issue.record("Expected cancellation") }
  catch let error as ScreenAnalysisError {
    guard case .cancelled = error else { Issue.record("Wrong typed error"); return }
  }
}

@Test func timeoutConfigurationIsBounded() {
  #expect(ScreenAnalysisConfiguration.parsedTimeout(environment: [:]) == 120)
  #expect(ScreenAnalysisConfiguration.parsedTimeout(
    environment: ["AEGIS_VISION_TIMEOUT_SECONDS": "180"]) == 180)
  #expect(ScreenAnalysisConfiguration.parsedTimeout(
    environment: ["AEGIS_VISION_TIMEOUT_SECONDS": "0"]) == 120)
  #expect(ScreenAnalysisConfiguration.parsedTimeout(
    environment: ["AEGIS_VISION_TIMEOUT_SECONDS": "unlimited"]) == 120)
}

private func snapshot() throws -> ScreenSnapshot {
  let url = FileManager.default.temporaryDirectory.appending(path: "vision-(UUID()).png")
  try Data("image".utf8).write(to: url)
  return ScreenSnapshot(displayCount: 1, activeApplication: "Code", activeWindowTitle: "App",
    temporaryImageURL: url, width: 100, height: 100, captureSource: .activeWindow)
}

private struct VisionClient: ScreenAnalysisHTTPClient {
  let delay: Duration
  func data(for request: URLRequest) async throws -> ScreenAnalysisHTTPResult {
    try await Task.sleep(for: delay)
    return response()
  }
}

private actor SequencedVisionClient: ScreenAnalysisHTTPClient {
  private var delays: [Duration]
  init(delays: [Duration]) { self.delays = delays }
  func data(for request: URLRequest) async throws -> ScreenAnalysisHTTPResult {
    let delay = delays.removeFirst(); try await Task.sleep(for: delay)
    return response()
  }
}

private func response() -> ScreenAnalysisHTTPResult {
  let body = #"{"message":{"role":"assistant","content":"{\"summary\":\"화면 설명\"}"},"done":true}"#
  let url = ScreenAnalysisConfiguration.endpoint
  let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
    headerFields: ["Content-Type": "application/json"])!
  return ScreenAnalysisHTTPResult(data: Data(body.utf8), response: http)
}
