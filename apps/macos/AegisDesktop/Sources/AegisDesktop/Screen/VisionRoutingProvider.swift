import Foundation

actor VisionRoutingState {
  private(set) var availability: VisionBackendAvailability = .serverUnavailable
  private(set) var lastBackend: VisionBackend?
  private(set) var lastFailure: VisionFailureCategory?

  func record(availability value: VisionBackendAvailability) { availability = value }
  func success(_ backend: VisionBackend) { lastBackend = backend; lastFailure = nil }
  func failure(_ value: VisionFailureCategory) { lastFailure = value }
}

struct VisionRoutingProvider: ScreenAnalysisProviding, VisionBackendStatusProviding {
  let backend: VisionBackend
  let endpoint: VisionEndpoint?
  let model: String
  let fallbackEnabled: Bool
  private let remote: OllamaScreenAnalysisProvider?
  private let local: OllamaScreenAnalysisProvider?
  private let memory: any VisionMemoryPressureProviding
  private let state = VisionRoutingState()

  init(environment: [String: String]? = nil,
       remoteClient: (any ScreenAnalysisHTTPClient)? = nil,
       localClient: (any ScreenAnalysisHTTPClient)? = nil,
       memory: any VisionMemoryPressureProviding = SystemMemoryPressure(),
       coordinator: OllamaInferenceCoordinator = .shared) {
    let configuredBackend = environment.map(ScreenAnalysisConfiguration.backend)
      ?? ScreenAnalysisConfiguration.backend()
    let configuredEndpoint = environment.flatMap(ScreenAnalysisConfiguration.visionEndpoint)
      ?? (environment == nil ? ScreenAnalysisConfiguration.visionEndpoint() : nil)
    let configuredModel = environment.map(ScreenAnalysisConfiguration.model)
      ?? ScreenAnalysisConfiguration.model()
    let configuredFallback = environment.map(ScreenAnalysisConfiguration.localFallback)
      ?? ScreenAnalysisConfiguration.localFallback()
    backend = configuredBackend; endpoint = configuredEndpoint; model = configuredModel
    fallbackEnabled = configuredFallback
    self.memory = memory
    if let configuredEndpoint {
      let timeout: TimeInterval
      if let environment {
        timeout = configuredBackend == .remote
          ? ScreenAnalysisConfiguration.remoteTimeout(environment: environment)
          : ScreenAnalysisConfiguration.timeout(environment: environment)
      } else {
        timeout = configuredBackend == .remote ? ScreenAnalysisConfiguration.remoteTimeout()
          : ScreenAnalysisConfiguration.timeout()
      }
      remote = OllamaScreenAnalysisProvider(model: model, timeout: timeout,
        endpoint: configuredEndpoint, backend: configuredBackend, client: remoteClient,
        coordinator: coordinator)
    } else { remote = nil }
    let localEndpoint = environment.flatMap(ScreenAnalysisConfiguration.normalEndpoint)
      ?? (environment == nil ? ScreenAnalysisConfiguration.normalEndpoint() : nil)
    if configuredBackend == .remote, configuredFallback, let localEndpoint,
      localEndpoint.isLoopback {
      let localTimeout = environment.map(ScreenAnalysisConfiguration.timeout)
        ?? ScreenAnalysisConfiguration.timeout()
      local = OllamaScreenAnalysisProvider(model: model,
        timeout: localTimeout,
        endpoint: localEndpoint, backend: .local, client: localClient,
        coordinator: coordinator)
    } else { local = nil }
  }

  var availabilityDescription: String { "Ollama · \(backend.rawValue) · \(model)" }

  func analyze(snapshot: ScreenSnapshot, trustedContext: String?) async throws -> ScreenAnalysis {
    guard let remote, backend != .unavailable else {
      await state.record(availability: .invalidConfiguration)
      throw ScreenAnalysisError.invalidConfiguration
    }
    if backend == .remote {
      let availability = await remote.availability()
      await state.record(availability: availability)
      guard availability == .available else {
        return try await fallbackIfAllowed(for: availability, snapshot: snapshot,
          trustedContext: trustedContext)
      }
    }
    do {
      let result = try await remote.analyze(snapshot: snapshot, trustedContext: trustedContext)
      await state.success(backend)
      return result
    } catch {
      guard backend == .remote, fallbackCategory(error) != nil else {
        await state.failure(failureCategory(error)); throw error
      }
      return try await fallbackIfAllowed(for: fallbackCategory(error)!, snapshot: snapshot,
        trustedContext: trustedContext)
    }
  }

  func backendStatus(refresh: Bool) async -> VisionBackendStatus {
    var availability = await state.availability
    if refresh, let remote {
      availability = await remote.availability()
      await state.record(availability: availability)
    } else if backend == .unavailable { availability = .invalidConfiguration }
    return await VisionBackendStatus(configured: backend, endpoint: endpoint, model: model,
      availability: availability, fallbackEnabled: fallbackEnabled,
      lastBackend: state.lastBackend, lastFailure: state.lastFailure)
  }

  private func fallbackIfAllowed(for failure: VisionBackendAvailability,
                                 snapshot: ScreenSnapshot,
                                 trustedContext: String?) async throws -> ScreenAnalysis {
    await state.failure(failureCategory(failure))
    guard fallbackEnabled, let local else { throw error(for: failure) }
    guard memory.current() != .critical else {
      throw ScreenAnalysisError.remoteFallbackMemoryCritical
    }
    let result = try await local.analyze(snapshot: snapshot, trustedContext: trustedContext)
    await state.success(.fallback)
    return result
  }

  private func fallbackCategory(_ error: Error) -> VisionBackendAvailability? {
    guard let error = error as? ScreenAnalysisError else { return nil }
    switch error {
    case .connectionTimeout: return .serverUnavailable
    case .remoteInferenceTimeout: return .timeout
    default: return nil
    }
  }

  private func failureCategory(_ availability: VisionBackendAvailability) -> VisionFailureCategory {
    switch availability {
    case .available: return .httpFailure
    case .serverUnavailable: return .serverUnavailable
    case .modelUnavailable: return .modelUnavailable
    case .timeout: return .timeout
    case .invalidConfiguration: return .invalidConfiguration
    }
  }

  private func failureCategory(_ error: Error) -> VisionFailureCategory {
    guard let error = error as? ScreenAnalysisError else { return .httpFailure }
    switch error {
    case .connectionTimeout: return .serverUnavailable
    case .inferenceTimeout, .remoteInferenceTimeout: return .timeout
    case .modelUnavailable: return .modelUnavailable
    case .invalidConfiguration: return .invalidConfiguration
    case .malformedResponse: return .malformedResponse
    case .cancelled: return .cancelled
    case .memoryPressureCritical, .remoteFallbackMemoryCritical: return .memoryPressure
    default: return .httpFailure
    }
  }

  private func error(for availability: VisionBackendAvailability) -> ScreenAnalysisError {
    switch availability {
    case .available: return .httpFailure(0)
    case .serverUnavailable: return .connectionTimeout
    case .modelUnavailable: return .modelUnavailable(model)
    case .timeout: return .remoteInferenceTimeout(
      ScreenAnalysisConfiguration.remoteTimeout())
    case .invalidConfiguration: return .invalidConfiguration
    }
  }
}
