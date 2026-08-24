import Foundation
import Testing
@testable import AegisDesktop

private let localURL = "http://127.0.0.1:11434"
private let remoteURL = "http://100.64.0.8:11434"
private let visionModel = "qwen2.5vl:3b"

@Test func plannerAndVisionURLsAreIndependentlyRequired() {
  let plannerOnly = ["AEGIS_OLLAMA_URL": remoteURL]
  #expect(ScreenAnalysisConfiguration.normalEndpoint(environment: plannerOnly) != nil)
  #expect(ScreenAnalysisConfiguration.visionEndpoint(environment: plannerOnly) == nil)
  #expect(ScreenAnalysisConfiguration.backend(environment: plannerOnly) == .unavailable)

  let visionOnly = ["AEGIS_VISION_OLLAMA_URL": remoteURL]
  #expect(ScreenAnalysisConfiguration.normalEndpoint(environment: visionOnly) == nil)
  #expect(ScreenAnalysisConfiguration.visionEndpoint(environment: visionOnly) != nil)
}

@Test func separateVisionURLSelectsRemoteWithoutChangingPlannerURL() {
  let environment = ["AEGIS_OLLAMA_URL": localURL,
    "AEGIS_VISION_OLLAMA_URL": remoteURL, "OLLAMA_MODEL": "qwen3:8b"]
  #expect(ScreenAnalysisConfiguration.backend(environment: environment) == .remote)
  #expect(ScreenAnalysisConfiguration.visionEndpoint(environment: environment)?.host == "100.64.0.8")
  #expect(Ollama.endpoint(environment: environment)?.host == "127.0.0.1")
  #expect(Ollama.model(environment: environment) == "qwen3:8b")
}

@Test func visionEndpointRejectsUnsafeOrMalformedURLs() {
  for value in ["file:///tmp/model", "ftp://server:11434", "http://user:pass@server:11434",
                "http://server:99999", "not a url", "http://server/path"] {
    #expect(ScreenAnalysisConfiguration.visionEndpoint(
      environment: ["AEGIS_VISION_OLLAMA_URL": value]) == nil)
  }
}

@Test func remoteVisionSuccessChecksModelBeforeSendingImage() async throws {
  let client = RoutingClient(replies: [.tags([visionModel]), .analysis])
  let provider = makeProvider(remote: client)
  let result = try await provider.analyze(snapshot: try routingSnapshot(), trustedContext: nil)
  #expect(result.summary == "remote success")
  #expect(await client.paths() == ["/api/tags", "/api/chat"])
}

@Test func remoteAvailabilityFailuresAreTyped() async throws {
  let unavailable = RoutingClient(replies: [.failure(URLError(.cannotConnectToHost))])
  await expectError(.connectionTimeout, from: makeProvider(remote: unavailable))
  let timeout = RoutingClient(replies: [.failure(URLError(.timedOut))])
  await expectError(.remoteInferenceTimeout(300), from: makeProvider(remote: timeout))
  let missing = RoutingClient(replies: [.tags(["other:latest"])])
  await expectError(.modelUnavailable(visionModel), from: makeProvider(remote: missing))
}

@Test func invalidVisionConfigurationNeverCallsNetwork() async throws {
  let client = RoutingClient(replies: [.analysis])
  let provider = VisionRoutingProvider(environment: [
    "AEGIS_OLLAMA_URL": localURL, "AEGIS_VISION_OLLAMA_URL": "file:///tmp/model",
  ], remoteClient: client)
  await expectError(.invalidConfiguration, from: provider)
  #expect(await client.callCount() == 0)
}

@Test func localFallbackDisabledDoesNotCallLocalOllama() async throws {
  let remote = RoutingClient(replies: [.failure(URLError(.cannotConnectToHost))])
  let local = RoutingClient(replies: [.analysis])
  await expectError(.connectionTimeout, from: makeProvider(remote: remote, local: local))
  #expect(await local.callCount() == 0)
}

@Test func localFallbackRunsExactlyOnceAfterRemoteConnectionFailure() async throws {
  let shared = RoutingClient(replies: [.failure(URLError(.cannotConnectToHost)), .analysis])
  let provider = makeProvider(fallback: true, remote: shared, local: shared)
  let result = try await provider.analyze(snapshot: try routingSnapshot(), trustedContext: nil)
  #expect(result.summary == "remote success")
  #expect(await shared.callCount() == 2)
  #expect(await shared.maximumConcurrentCalls() == 1)
  #expect(await provider.backendStatus(refresh: false).lastBackend == .fallback)
}

@Test func fallbackIsBlockedDuringCriticalMacMemoryPressure() async throws {
  let remote = RoutingClient(replies: [.failure(URLError(.timedOut))])
  let local = RoutingClient(replies: [.analysis])
  let provider = makeProvider(fallback: true, remote: remote, local: local,
    memory: RoutingPressure(.critical))
  await expectError(.remoteFallbackMemoryCritical, from: provider)
  #expect(await local.callCount() == 0)
}

@Test func unstructuredRemoteOutputNeverFallsBackLocally() async throws {
  let remote = RoutingClient(replies: [.tags([visionModel]), .malformed])
  let local = RoutingClient(replies: [.analysis])
  let provider = makeProvider(fallback: true, remote: remote, local: local)
  let result = try await provider.analyze(snapshot: routingSnapshot(), trustedContext: nil)
  #expect(result.summary == "not-json")
  #expect(await local.callCount() == 0)
}

@Test func sensitiveCaptureIsBlockedBeforeRemoteNetworkRequest() async {
  let client = RoutingClient(replies: [.tags([visionModel]), .analysis])
  let inspector = ScreenInspector(capture: SensitiveRoutingCapture(),
    provider: makeProvider(remote: client), cacheLifetime: 0)
  let result = await inspector.inspect(.init(activeWindowOnly: true, displayIndex: nil),
    trustedContext: nil)
  #expect(!result.succeeded)
  #expect(await client.callCount() == 0)
}

@Test func remoteRequestUsesTemporaryOptimizedImageAndDoesNotPersistIt() async throws {
  let client = RoutingClient(replies: [.tags([visionModel]), .analysis])
  let url = FileManager.default.temporaryDirectory
    .appending(path: "aegis-routing-\(UUID().uuidString).jpg")
  try Data("optimized-image".utf8).write(to: url)
  let capture = OptimizedRoutingCapture(url: url)
  let inspector = ScreenInspector(capture: capture, provider: makeProvider(remote: client),
    cacheLifetime: 0)
  let result = await inspector.inspect(.init(activeWindowOnly: true, displayIndex: nil),
    trustedContext: nil)
  #expect(result.succeeded)
  #expect(!FileManager.default.fileExists(atPath: url.path))
  #expect(await client.lastChatBody()?.contains(Data("optimized-image".utf8).base64EncodedString()) == true)
}

@Test func remoteVisionFailureDoesNotBreakNormalProjectPlanning() async throws {
  let remote = RoutingClient(replies: [.failure(URLError(.cannotConnectToHost))])
  await expectError(.connectionTimeout, from: makeProvider(remote: remote))
  let database = FileManager.default.temporaryDirectory
    .appending(path: "aegis-routing-memory-\(UUID().uuidString)/memory.sqlite")
  let repository = MemoryRepository(databaseURL: database)
  try repository.bootstrap()
  try repository.save(MemoryRecord(type: .project, key: "ptfriends", value: "/tmp/ptfriends"))
  let context = MemoryRetriever.relevant(to: "PTFriends 상태 보여줘", repository: repository)
  let plan = try await AgentPlanner.plan(for: "PTFriends 상태 보여줘", memory: context)
  #expect(plan.steps.first?.action == .getRememberedProjectStatus)
}

private func makeProvider(fallback: Bool = false, remote: RoutingClient,
                          local: RoutingClient? = nil,
                          memory: RoutingPressure = .init(.normal)) -> VisionRoutingProvider {
  VisionRoutingProvider(environment: ["AEGIS_OLLAMA_URL": localURL,
    "AEGIS_VISION_OLLAMA_URL": remoteURL, "AEGIS_VISION_MODEL": visionModel,
    "AEGIS_VISION_LOCAL_FALLBACK": fallback ? "true" : "false"],
    remoteClient: remote, localClient: local, memory: memory)
}

private func expectError(_ expected: ScreenAnalysisError,
                         from provider: VisionRoutingProvider) async {
  do {
    _ = try await provider.analyze(snapshot: try routingSnapshot(), trustedContext: nil)
    Issue.record("Expected Vision error")
  } catch let error as ScreenAnalysisError {
    #expect(error.localizedDescription == expected.localizedDescription)
  } catch { Issue.record("Unexpected error: \(error)") }
}

private func routingSnapshot() throws -> ScreenSnapshot {
  let url = FileManager.default.temporaryDirectory.appending(path: "routing-\(UUID()).jpg")
  try Data("optimized-image".utf8).write(to: url)
  return ScreenSnapshot(displayCount: 1, activeApplication: "Code", activeWindowTitle: "Aegis",
    temporaryImageURL: url, width: 1_024, height: 640, captureSource: .activeWindow)
}

private enum RoutingReply: @unchecked Sendable {
  case tags([String]), analysis, malformed, failure(Error)
}

private actor RoutingClient: ScreenAnalysisHTTPClient {
  private var replies: [RoutingReply]
  private var requestedPaths: [String] = []
  private var chatBody: String?
  private var active = 0
  private var maximumActive = 0

  init(replies: [RoutingReply]) { self.replies = replies }

  func data(for request: URLRequest) async throws -> ScreenAnalysisHTTPResult {
    active += 1; maximumActive = max(maximumActive, active)
    defer { active -= 1 }
    requestedPaths.append(request.url?.path ?? "")
    if request.url?.path == "/api/chat" {
      chatBody = request.httpBody.map { String(decoding: $0, as: UTF8.self) }
    }
    let reply = replies.removeFirst()
    switch reply {
    case .failure(let error): throw error
    case .tags(let names):
      let models = names.map { ["name": $0] }
      return result(request, object: ["models": models])
    case .analysis:
      return result(request, object: ["message": ["role": "assistant",
        "content": #"{"summary":"remote success"}"#], "done": true])
    case .malformed: return result(request, object: ["message": ["content": "not-json"]])
    }
  }

  func paths() -> [String] { requestedPaths }
  func callCount() -> Int { requestedPaths.count }
  func maximumConcurrentCalls() -> Int { maximumActive }
  func lastChatBody() -> String? { chatBody }

  private func result(_ request: URLRequest, object: Any) -> ScreenAnalysisHTTPResult {
    let data = try! JSONSerialization.data(withJSONObject: object)
    let response = HTTPURLResponse(url: request.url!, statusCode: 200,
      httpVersion: nil, headerFields: nil)!
    return ScreenAnalysisHTTPResult(data: data, response: response)
  }
}

private struct RoutingPressure: VisionMemoryPressureProviding {
  let value: VisionMemoryPressure
  init(_ value: VisionMemoryPressure) { self.value = value }
  func current() -> VisionMemoryPressure { value }
}

private struct SensitiveRoutingCapture: ScreenCaptureProviding {
  func availability() -> ScreenCaptureAvailability { .available }
  func capture(_ request: ScreenCaptureRequest) async throws -> ScreenSnapshot {
    throw ScreenCaptureError.sensitiveApplication("민감한 창")
  }
  func diagnostics() async -> ScreenDiagnostics {
    .init(availability: .available, activeApplication: "1Password",
      activeWindowAvailable: true, activeWindowTitle: "Login", displayCount: 1)
  }
}

private struct OptimizedRoutingCapture: ScreenCaptureProviding {
  let url: URL
  func availability() -> ScreenCaptureAvailability { .available }
  func capture(_ request: ScreenCaptureRequest) async throws -> ScreenSnapshot {
    ScreenSnapshot(displayCount: 1, activeApplication: "Code", activeWindowTitle: "Aegis",
      temporaryImageURL: url, width: 1_024, height: 640, captureSource: .activeWindow)
  }
  func diagnostics() async -> ScreenDiagnostics {
    .init(availability: .available, activeApplication: "Code", activeWindowAvailable: true,
      activeWindowTitle: "Aegis", displayCount: 1)
  }
}
