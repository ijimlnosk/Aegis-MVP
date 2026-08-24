import Foundation
import Testing
@testable import AegisDesktop

private let sharedRemoteURL = "http://100.64.0.9:11434"

@Test func normalPlannerUsesConfiguredRemoteBackendModelAndTimeout() {
  let transport = OllamaTransport(environment: [
    "AEGIS_OLLAMA_URL": sharedRemoteURL,
    "OLLAMA_MODEL": "planner-model",
    "AEGIS_OLLAMA_REMOTE_TIMEOUT_SECONDS": "240",
  ])
  #expect(transport.endpoint?.baseURL.absoluteString == sharedRemoteURL)
  #expect(transport.model == "planner-model")
  #expect(transport.timeout == 240)
}

@Test func sameRemoteServerCanServePlannerAndVisionWithSeparateModels() {
  let environment = [
    "AEGIS_OLLAMA_URL": sharedRemoteURL,
    "AEGIS_VISION_OLLAMA_URL": sharedRemoteURL,
    "OLLAMA_MODEL": "planner-model",
    "AEGIS_VISION_MODEL": "vision-model",
  ]
  let planner = OllamaTransport(environment: environment)
  let vision = VisionRoutingProvider(environment: environment)
  #expect(planner.endpoint == vision.endpoint)
  #expect(planner.model == "planner-model")
  #expect(vision.model == "vision-model")
}

@Test func missingPlannerURLNeverDependsOnLocalhost() async {
  let client = CoordinatedOllamaClient()
  let transport = OllamaTransport(environment: [:], client: client)
  await #expect(throws: OllamaBackendError.self) {
    _ = try await transport.chat(body: [:])
  }
  #expect(await client.callCount == 0)
}

@Test func plannerTimeoutIsTypedAndDoesNotFallback() async {
  let client = TimeoutOllamaClient()
  let transport = OllamaTransport(environment: [
    "AEGIS_OLLAMA_URL": sharedRemoteURL,
    "AEGIS_OLLAMA_REMOTE_TIMEOUT_SECONDS": "300",
  ], client: client)
  do {
    _ = try await transport.chat(body: [:])
    Issue.record("Expected planner timeout")
  } catch let error as OllamaBackendError {
    if case .timeout = error {} else { Issue.record("Unexpected error: \(error)") }
  } catch { Issue.record("Unexpected error: \(error)") }
  #expect(await client.callCount == 1)
}

@Test func plannerAndVisionShareOneExpensiveInferenceSlot() async throws {
  let client = CoordinatedOllamaClient(delay: .milliseconds(40))
  let coordinator = OllamaInferenceCoordinator()
  let environment = ["AEGIS_OLLAMA_URL": sharedRemoteURL,
    "AEGIS_VISION_OLLAMA_URL": sharedRemoteURL, "AEGIS_VISION_MODEL": "vision-model"]
  let planner = OllamaTransport(environment: environment, client: client,
    coordinator: coordinator)
  let vision = VisionRoutingProvider(environment: environment, remoteClient: client,
    coordinator: coordinator)
  let snapshot = try temporarySnapshot()
  async let plannerResult = planner.chat(body: ["model": "planner-model"])
  async let visionResult = vision.analyze(snapshot: snapshot, trustedContext: nil)
  _ = try await (plannerResult, visionResult)
  #expect(await client.maximumConcurrentGenerationCount == 1)
}

@Test func queuedCallerTimesOutInsteadOfWaitingForeverOnAStuckHolder() async throws {
  let coordinator = OllamaInferenceCoordinator()
  let holder = Task<Int, Error> {
    try await coordinator.perform(waitTimeout: 10) { try await Task.sleep(for: .seconds(2)); return 1 }
  }
  try await Task.sleep(for: .milliseconds(20))
  do {
    _ = try await coordinator.perform(waitTimeout: 0.05) { 2 }
    Issue.record("Expected the queued caller to time out instead of waiting forever")
  } catch let error as OllamaBackendError {
    if case .timeout = error {} else { Issue.record("Unexpected error: \(error)") }
  } catch { Issue.record("Unexpected error: \(error)") }
  _ = try? await holder.value
}

@Test func backendStatusIntentIsDeterministic() {
  #expect(AIBackendIntentResolver.plan(for: "AI 백엔드 상태 보여줘")?.steps.first?.action
    == .getAIBackendStatus)
}

private func temporarySnapshot() throws -> ScreenSnapshot {
  let url = FileManager.default.temporaryDirectory.appending(path: "ollama-routing-\(UUID()).jpg")
  try Data("image".utf8).write(to: url)
  return ScreenSnapshot(displayCount: 1, activeApplication: "Code", activeWindowTitle: "Aegis",
    temporaryImageURL: url, width: 640, height: 480, captureSource: .activeWindow)
}

private actor TimeoutOllamaClient: ScreenAnalysisHTTPClient {
  private(set) var callCount = 0
  func data(for request: URLRequest) async throws -> ScreenAnalysisHTTPResult {
    callCount += 1
    throw URLError(.timedOut)
  }
}

private actor CoordinatedOllamaClient: ScreenAnalysisHTTPClient {
  private let delay: Duration
  private(set) var callCount = 0
  private var activeGenerations = 0
  private(set) var maximumConcurrentGenerationCount = 0

  init(delay: Duration = .zero) { self.delay = delay }

  func data(for request: URLRequest) async throws -> ScreenAnalysisHTTPResult {
    callCount += 1
    if request.url?.path == "/api/tags" {
      return response(request, ["models": [["name": "vision-model"]]])
    }
    activeGenerations += 1
    maximumConcurrentGenerationCount = max(maximumConcurrentGenerationCount, activeGenerations)
    defer { activeGenerations -= 1 }
    try await Task.sleep(for: delay)
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    let content = body.contains("images") ? #"{"summary":"visible"}"# : #"{"steps":[]}"#
    return response(request, ["message": ["content": content]])
  }

  private func response(_ request: URLRequest, _ object: Any) -> ScreenAnalysisHTTPResult {
    let data = try! JSONSerialization.data(withJSONObject: object)
    let http = HTTPURLResponse(url: request.url!, statusCode: 200,
      httpVersion: nil, headerFields: nil)!
    return ScreenAnalysisHTTPResult(data: data, response: http)
  }
}
