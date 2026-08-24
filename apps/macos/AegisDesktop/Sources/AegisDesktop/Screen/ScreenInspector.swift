import Foundation

actor ScreenInspector {
  private let capture: ScreenCaptureProviding
  private let provider: ScreenAnalysisProviding
  private let redactor: ScreenRedacting
  private let coordinator: VisionAnalysisCoordinator
  private var cache: CachedScreenAnalysis?
  private let cacheLifetime: TimeInterval

  init(capture: ScreenCaptureProviding = ScreenCaptureService(),
       provider: ScreenAnalysisProviding = VisionRoutingProvider(),
       redactor: ScreenRedacting = PassthroughScreenRedactor(),
       coordinator: VisionAnalysisCoordinator = VisionAnalysisCoordinator(),
       cacheLifetime: TimeInterval = 8) {
    self.capture = capture; self.provider = provider; self.redactor = redactor
    self.coordinator = coordinator; self.cacheLifetime = cacheLifetime
  }

  func inspect(_ request: ScreenCaptureRequest, trustedContext: String?,
               requestedProfile: VisionResourceProfile? = nil,
               progress: (@Sendable (ScreenAnalysisProgress) async -> Void)? = nil) async -> ScreenInspectionResult {
    let started = ContinuousClock.now
    let diagnostics = await capture.diagnostics()
    if let cache, Date.now.timeIntervalSince(cache.createdAt) <= cacheLifetime,
      cache.application == diagnostics.activeApplication,
      cache.windowTitle == diagnostics.activeWindowTitle, cache.request == request,
      request.displayIndex == nil, requestedProfile == nil {
      return cache.result
    }
    let lease: VisionAnalysisLease
    do { lease = try await coordinator.begin(requested: requestedProfile) }
    catch { return failure(error) }
    if lease.pressure == .warning { await progress?(.lowMemory) }
    let effectiveRequest = ScreenCaptureRequest(activeWindowOnly: request.activeWindowOnly,
      displayIndex: request.displayIndex, resourceProfile: lease.profile,
      windowID: request.windowID)
    do {
      await progress?(effectiveRequest.activeWindowOnly ? .capturingWindow : .capturing)
      let snapshot = try await capture.capture(effectiveRequest)
      defer { try? FileManager.default.removeItem(at: snapshot.temporaryImageURL) }
      try Task.checkCancellation()
      await progress?(.optimizing)
      let redacted = try await redactor.redact(snapshot)
      let backend: VisionBackend
      if let routed = provider as? VisionBackendStatusProviding {
        backend = await routed.backendStatus(refresh: false).configured
      } else { backend = .local }
      await progress?(.analyzing(backend))
      let inferenceStarted = ContinuousClock.now
      let analysis = try await provider.analyze(snapshot: redacted, trustedContext: trustedContext)
      ScreenAnalysisDiagnostics.modelIdentity(analysis)
      let inferenceDuration = inferenceStarted.duration(to: .now)
      try Task.checkCancellation()
      let result = ScreenInspectionResult.format(snapshot: redacted, analysis: analysis,
        projectContext: trustedContext)
      cache = CachedScreenAnalysis(createdAt: .now, application: snapshot.activeApplication,
        windowTitle: snapshot.activeWindowTitle, request: request, result: result)
      let bytes = (try? snapshot.temporaryImageURL.resourceValues(
        forKeys: [.fileSizeKey]).fileSize) ?? 0
      await coordinator.finish(lease, metrics: VisionAnalysisMetrics(
        dimensions: (snapshot.width, snapshot.height), pixels: snapshot.width * snapshot.height,
        encodedBytes: bytes, inferenceDuration: inferenceDuration))
      ScreenAnalysisDiagnostics.timing("total_analysis", since: started,
        dimensions: (snapshot.width, snapshot.height))
      return result
    } catch {
      await coordinator.finish(lease)
      return failure(error)
    }
  }

  func diagnostics() async -> String {
    let value = await capture.diagnostics()
    let state = await coordinator.status()
    let backend = await (provider as? VisionBackendStatusProviding)?.backendStatus(refresh: true)
    let loaded = await (provider as? VisionModelStatusProviding)?.isModelLoaded()
    let profile = ScreenAnalysisConfiguration.resourceProfile()
    var lines = [value.format(provider: provider.availabilityDescription,
      cacheAvailable: cache != nil), "리소스 프로필: \(profile.rawValue)",
      "최대 이미지: \(ScreenAnalysisConfiguration.maximumLongEdge(for: profile))px / \(ScreenAnalysisConfiguration.maximumPixels()) pixels",
      "메모리 압력: \(state.pressure.rawValue)", "활성 Vision 요청: \(state.active ? "yes" : "no")",
      "모델 로드됨: \(loaded.map { $0 ? "yes" : "no" } ?? "unknown")"]
    if let backend {
      lines += ["Vision backend: \(backend.configured.rawValue)",
        "Vision endpoint: \(backend.endpoint.map { "\($0.host):\($0.port)" } ?? "invalid")",
        "Vision model: \(backend.model)",
        "Remote status: \(backend.availability.rawValue)",
        "Local fallback: \(backend.fallbackEnabled ? "enabled" : "disabled")",
        "Last backend: \(backend.lastBackend?.rawValue ?? "none")",
        "Last failure: \(backend.lastFailure?.rawValue ?? "none")"]
    }
    if let metrics = state.metrics {
      lines += ["마지막 이미지: \(metrics.dimensions.0)x\(metrics.dimensions.1)",
        "마지막 추론: \(metrics.inferenceDuration)",
        "예상 분석 크기: \(metrics.pixels) pixels / \(metrics.encodedBytes) bytes"]
    }
    return lines.joined(separator: "\n")
  }

  func visionBackendStatus(refresh: Bool) async -> VisionBackendStatus? {
    await (provider as? VisionBackendStatusProviding)?.backendStatus(refresh: refresh)
  }

  private func failure(_ error: Error) -> ScreenInspectionResult {
    ScreenInspectionResult(message: error.localizedDescription,
      historySummary: "화면 분석 실패 · 콘텐츠 저장 안 함", succeeded: false)
  }
}

private struct CachedScreenAnalysis {
  let createdAt: Date
  let application: String?
  let windowTitle: String?
  let request: ScreenCaptureRequest
  let result: ScreenInspectionResult
}

enum ScreenAnalysisProgress: Sendable {
  case lowMemory, capturingWindow, capturing, optimizing, analyzing(VisionBackend)
}
