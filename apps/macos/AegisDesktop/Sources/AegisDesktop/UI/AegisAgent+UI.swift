import Foundation

extension AegisAgent {
  func runUITool(_ step: AgentStep, request: String) {
    screenAnalysisTask?.cancel(); busy = true
    Task {
      do {
        let result = try await uiCoordinator.perform(target: step.application ?? step.uiLabel) {
          try await self.executeUI(step)
        }
        busy = false
        finishReadTool(result, action: step.action.rawValue, request: request,
          target: step.application ?? step.uiLabel ?? "ui")
      } catch { busy = false; failCurrentStep(error.localizedDescription) }
    }
  }

  private func executeUI(_ step: AgentStep) async throws -> String {
    if step.action == .getUIControlStatus { return await uiDiagnostics() }
    if step.action == .activateApplication {
      return try accessibility.activate(try knownApplication(step.application))
    }
    let windows = (try? await visibleWindows.list()) ?? []
    let window = try resolveUIWindow(step, windows: windows)
    switch step.action {
    case .getVSCodeQuickOpenStatus:
      return try quickOpenDiagnostics(window: window)
    case .focusWindow:
      let result = try accessibility.focus(window: window)
      try rememberResolvedWindow(window)
      return result
    case .closeWindow:
      _ = try accessibility.focus(window: window)
      return try accessibility.close(window: window)
    case .listUIElements: return formatUIElements(try accessibility.listElements(window: window))
    case .inspectUIElement:
      let value = try resolveElement(step, window: window)
      return "\(value.role.rawValue) · \(value.displayName) · enabled \(value.enabled)"
    case .focusUIElement:
      return try accessibility.focus(resolveElement(step, window: window), window: window)
    case .pressUIElement, .selectMenuItem:
      return try accessibility.press(resolveElement(step, window: window), window: window)
    case .setUIText, .appendUIText:
      guard let text = step.content, !text.isEmpty else {
        throw UIInteractionError.targetNotFound("입력할 텍스트")
      }
      return try accessibility.setText(text, append: step.action == .appendUIText,
        descriptor: resolveElement(step, window: window), window: window)
    case .pressKeyboardShortcut:
      guard let shortcut = step.shortcut else { throw UIInteractionError.unsupportedAction }
      if shortcut == .quickOpen,
        window.bundleIdentifier == VSCodeAdapter.application.bundleIdentifiers.first {
        return try await openQuickOpen(window: window)
      }
      let result = try accessibility.shortcut(shortcut, window: window)
      if shortcut == .confirm, let expected = step.content {
        try await verifyOpenFile(expected, target: try currentResolvedTarget(window))
      }
      return result
    case .scrollUI:
      guard let direction = step.scrollDirection else { throw UIInteractionError.unsupportedAction }
      return try accessibility.scroll(direction, window: window)
    default: throw UIInteractionError.unsupportedAction
    }
  }

  private func resolveUIWindow(_ step: AgentStep,
                               windows: [WindowDescriptor]) throws -> WindowDescriptor {
    if let approved = planExecutor?.state.approvedUITarget {
      return try approved.resolve(in: windows)
    }
    return try UIWindowTargetResolver.resolve(step: step, windows: windows,
      workflow: planExecutor?.state.resolvedWindowTarget, recent: recentUIWindowTarget)
  }

  private func rememberResolvedWindow(_ window: WindowDescriptor) throws {
    let target = try ResolvedWindowTarget(window)
    recentUIWindowTarget = target
    planExecutor?.setResolvedWindowTarget(target)
  }

  private func currentResolvedTarget(_ window: WindowDescriptor) throws -> ResolvedWindowTarget {
    if let target = planExecutor?.state.resolvedWindowTarget { return target }
    return try ResolvedWindowTarget(window)
  }

  private func resolveElement(_ step: AgentStep,
                              window: WindowDescriptor) throws -> UIElementDescriptor {
    if step.uiLabel == "Quick Open", let descriptor = planExecutor?.state.resolvedUIElement {
      return descriptor
    }
    let elements = try accessibility.listElements(window: window)
    if step.uiLabel == "Quick Open" { return try VSCodeAdapter.quickOpenTarget(in: elements) }
    guard let label = step.uiLabel else { throw UIInteractionError.targetNotFound("UI 대상") }
    return try UIElementResolver.resolve(label: label, elements: elements)
  }

  private func openQuickOpen(window: WindowDescriptor) async throws -> String {
    #if DEBUG
    let before = try accessibility.elementTree(window: window)
    #endif
    _ = try accessibility.shortcut(.quickOpen, window: window)
    let input = try await VSCodeAdapter.waitForQuickOpen {
      try accessibility.elementTree(window: window, maximumDepth: 16,
        cancelled: { Task.isCancelled })
    }
    planExecutor?.setResolvedUIElement(input)
    #if DEBUG
    let after = try accessibility.elementTree(window: window)
    AccessibilityTreeInspector.logDifference(before: before, after: after)
    #endif
    return "VSCode Quick Open을 열었습니다."
  }

  private func quickOpenDiagnostics(window: WindowDescriptor) throws -> String {
    let trees = try accessibility.elementTree(window: window, maximumDepth: 16)
    let input = try? VSCodeAdapter.resolveQuickOpenInput(in: trees, maximumDepth: 16)
    return """
    VSCode Quick Open 상태
    - target window: \(window.windowTitle ?? "unknown")
    - detected: \(input == nil ? "no" : "yes")
    - input role: \(input?.role.rawValue ?? "none")
    - input title: \(input?.title ?? "none")
    - input identifier: \(input?.identifier ?? "none")
    - focused: \(input?.focused == true ? "yes" : "no")
    """
  }

  private func knownApplication(_ value: String?) throws -> KnownApplication {
    guard let value, let application = KnownApplicationRegistry.application(nameOrAlias: value)
    else { throw UIInteractionError.applicationNotRunning(value ?? "앱") }
    return application
  }

  private func verifyOpenFile(_ expected: String, target: ResolvedWindowTarget) async throws {
    for _ in 0..<20 {
      let windows = (try? await visibleWindows.list()) ?? []
      if let window = VSCodeAdapter.verifiedOpenFile(expected, target: target,
        windows: windows) {
        recentUIWindowTarget = try? ResolvedWindowTarget(window)
        return
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw UIInteractionError.verificationFailed
  }

  private func formatUIElements(_ elements: [UIElementDescriptor]) -> String {
    let rows = elements.filter { $0.role.actionable }.prefix(30)
      .map { "- \($0.role.rawValue): \($0.displayName)" }
    return (["현재 창에서 조작 가능한 UI"] + rows).joined(separator: "\n")
  }

  private func uiDiagnostics() async -> String {
    let windows = (try? await visibleWindows.list()) ?? []
    let active = windows.first(where: \.isActive)
    let state = await uiCoordinator.status()
    return """
    UI 제어 상태
    - Accessibility: \(accessibility.availability().rawValue)
    - active application: \(active?.canonicalApplication ?? "unknown")
    - active window: \(active?.windowTitle ?? "unknown")
    - interaction: \(state.active ? "active" : "idle")
    - current target: \(state.target ?? "none")
    - adapters: Visual Studio Code, Xcode
    """
  }
}
