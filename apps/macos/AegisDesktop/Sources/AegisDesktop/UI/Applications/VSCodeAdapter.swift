import Foundation

enum VSCodeAdapter {
  static let application = KnownApplicationRegistry.application(nameOrAlias: "Visual Studio Code")!
  private static let quickOpenIdentifiers = ["quickinputbox", "quick-input-box"]
  private static let quickOpenLabels = ["quick open", "go to file", "파일로 이동",
    "type the name of a file to open", "search files by name"]
  private static let quickOpenPickerLabels = ["search files by name"]

  static func quickOpenPlan(project: String?, filename: String) -> AgentPlan {
    AgentPlan(steps: [
      AgentStep(action: .focusWindow, application: application.canonicalName, project: project),
      AgentStep(action: .pressKeyboardShortcut, dependency: .requiresPreviousSuccess,
        application: application.canonicalName, shortcut: .quickOpen),
      AgentStep(action: .setUIText, dependency: .requiresPreviousSuccess,
        application: application.canonicalName, content: filename, project: project,
        uiLabel: "Quick Open", inputPurpose: .navigationSearch),
      AgentStep(action: .pressKeyboardShortcut, dependency: .requiresPreviousSuccess,
        application: application.canonicalName, content: filename, project: project,
        shortcut: .confirm),
    ], finalAnswer: "\(filename)을 열었습니다.")
  }

  static func quickOpenTarget(in elements: [UIElementDescriptor]) throws -> UIElementDescriptor {
    let nodes = elements.map { AccessibilityTreeNode(descriptor: $0, childCount: 0, children: []) }
    return try resolveQuickOpenInput(in: nodes)
  }

  static func resolveQuickOpenInput(in roots: [AccessibilityTreeNode], maximumDepth: Int = 8) throws
    -> UIElementDescriptor {
    let nodes = AccessibilityTreeSearch.flattened(roots, maximumDepth: maximumDepth)
    let enabled = nodes.map(\.descriptor).filter(\.enabled)
    if let identified = enabled.first(where: {
      $0.identifier.map(normalize).map(quickOpenIdentifiers.contains) == true
        && isEditable($0)
    }) { return identified }
    let pickers = nodes.filter { node in
      node.accessibilityRole == "AXList"
        && [node.descriptor.title, node.descriptor.label].compactMap { $0 }.map(normalize)
          .contains { value in quickOpenPickerLabels.contains { value.contains($0) } }
    }
    if pickers.count == 1,
      let input = AccessibilityTreeSearch.first(in: pickers[0].children,
        maximumDepth: 4, maximumElements: 40, where: {
          $0.enabled && isEditable($0)
        }) {
      return input
    }
    let editable = enabled.filter(isEditable)
    let labelled = editable.filter { item in
      let metadata = [item.title, item.label, item.identifier].compactMap { $0 }.map(normalize)
      return metadata.contains { value in quickOpenLabels.contains { value.contains($0) } }
    }
    if labelled.count == 1 { return labelled[0] }
    if labelled.count > 1 { throw UIInteractionError.ambiguousTarget("VSCode Quick Open") }
    let focused = editable.filter(\.focused)
    if focused.count == 1 { return focused[0] }
    if focused.count > 1 { throw UIInteractionError.ambiguousTarget("VSCode Quick Open") }
    throw UIInteractionError.targetNotFound("VSCode Quick Open")
  }

  static func waitForQuickOpen(attempts: Int = 16, maximumDepth: Int = 16,
    inspect: () async throws -> [AccessibilityTreeNode],
    wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(150)) })
    async throws -> UIElementDescriptor {
    for attempt in 0..<max(1, attempts) {
      if let input = try? resolveQuickOpenInput(in: try await inspect(),
        maximumDepth: maximumDepth) { return input }
      if attempt + 1 < attempts { try await wait() }
    }
    throw UIInteractionError.quickOpenUnverified
  }

  static func verifiedOpenFile(_ filename: String, target: ResolvedWindowTarget,
                               windows: [WindowDescriptor]) -> WindowDescriptor? {
    guard let window = try? target.resolve(in: windows),
      window.windowTitle?.range(of: filename, options: .caseInsensitive) != nil
    else { return nil }
    return window
  }

  static func textValueMatches(_ expected: String, descriptor: UIElementDescriptor) -> Bool {
    descriptor.valueSummary == expected
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func isEditable(_ descriptor: UIElementDescriptor) -> Bool {
    [.textField, .textArea, .searchField, .comboBox].contains(descriptor.role)
      || (descriptor.role == .unknown && descriptor.valueSettable)
  }
}
