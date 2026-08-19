import Foundation

extension AegisAgent {
  func runScreenTool(_ step: AgentStep, request: String) {
    screenAnalysisTask?.cancel()
    busy = true
    screenAnalysisTask = Task { [weak self] in
      guard let self else { return }
      if step.action == .getScreenAwarenessStatus {
        let result = await screenInspector.diagnostics()
        finishScreen(result: ScreenInspectionResult(message: result,
          historySummary: "화면 인식 진단 조회", succeeded: true), step: step, request: request)
        return
      }
      if step.action == .listVisibleWindows {
        do {
          let windows = try await visibleWindows.list()
          finishScreen(result: windowListResult(windows), step: step, request: request)
        } catch {
          finishScreen(result: screenFailure(error), step: step, request: request)
        }
        return
      }
      let context = trustedProjectContext(step.project)
      var windowID: UInt32?
      if step.action == .inspectWindow {
        do {
          let target = step.application ?? ""
          if case .blocked(let reason) = ScreenPrivacyPolicy.decision(for: target) {
            throw ScreenCaptureError.sensitiveApplication(reason)
          }
          let windows = try await visibleWindows.list()
          windowID = try WindowResolver.resolve(target, displayIndex: step.displayIndex,
            windows: windows).id
        } catch {
          finishScreen(result: screenFailure(error), step: step, request: request)
          return
        }
      }
      let captureRequest = ScreenCaptureRequest(
        activeWindowOnly: !ScreenRequestPolicy.isExplicitFullScreen(request),
        displayIndex: step.displayIndex, windowID: windowID)
      let result = await screenInspector.inspect(captureRequest, trustedContext: context,
        requestedProfile: ScreenRequestPolicy.requestedProfile(request)) { state in
        await MainActor.run { [weak self] in self?.chat.append(.system, state.message) }
      }
      guard !Task.isCancelled else { return }
      finishScreen(result: result, step: step, request: request)
    }
  }

  func cancelCurrentOperation() {
    guard screenAnalysisTask != nil else { return }
    screenAnalysisTask?.cancel(); screenAnalysisTask = nil; busy = false
    speak("화면 분석이 취소되었습니다.", role: .system)
    completeCurrentStep(succeeded: false)
  }

  private func trustedProjectContext(_ project: String?) -> String? {
    guard let project else { return nil }
    do {
      return ProjectHealthService.format(try ProjectHealthService.lightweight(project: project,
        repository: memoryStore.repository))
    } catch { return "\(project) 프로젝트 상태를 확인하지 못했습니다: \(error.localizedDescription)" }
  }

  private func windowListResult(_ windows: [WindowDescriptor]) -> ScreenInspectionResult {
    let rows = windows.map { window in
      let title = window.windowTitle ?? "제목 없음"
      let display = window.displayIndex.map(String.init) ?? "확인 불가"
      return "- \(window.applicationName) · \(title) · 디스플레이 \(display)\(window.isActive ? " · 활성" : "")"
    }
    return ScreenInspectionResult(message: rows.isEmpty ? "현재 표시 가능한 창이 없습니다."
      : (["현재 열려 있는 창"] + rows).joined(separator: "\n"),
      historySummary: "표시 창 metadata 조회 · \(windows.count)개", succeeded: true)
  }

  private func screenFailure(_ error: Error) -> ScreenInspectionResult {
    ScreenInspectionResult(message: error.localizedDescription,
      historySummary: "창 조회 실패 · 콘텐츠 저장 안 함", succeeded: false)
  }

  private func finishScreen(result: ScreenInspectionResult, step: AgentStep, request: String) {
    screenAnalysisTask = nil
    busy = false
    memoryStore.recordAction(request: "명시적 화면 요청", action: step.action.rawValue,
      target: step.project ?? "screen", result: result.historySummary, succeeded: result.succeeded)
    speak(result.message, role: result.succeeded ? .assistant : .error)
    completeCurrentStep(succeeded: result.succeeded)
  }

}

private extension ScreenAnalysisProgress {
  var message: String {
    switch self {
    case .lowMemory: "메모리 사용량이 높아 저메모리 화면 분석으로 실행합니다."
    case .capturingWindow: "현재 창을 캡처하고 있습니다..."
    case .capturing: "현재 화면을 캡처하고 있습니다..."
    case .optimizing: "이미지를 화면 분석용으로 최적화하고 있습니다..."
    case .analyzing: "Vision 모델로 화면을 분석하고 있습니다..."
    }
  }
}
