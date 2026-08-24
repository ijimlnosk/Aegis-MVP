import Foundation
import Testing
@testable import AegisDesktop

@Test func accessibilityAvailabilitySupportsGrantedDeniedAndRevokedStates() {
  #expect(AccessibilityService(permissionProvider: { .available }).availability() == .available)
  #expect(AccessibilityService(permissionProvider: { .permissionRequired }).availability()
    == .permissionRequired)
  let revoked = AccessibilityService(permissionProvider: { .permissionRequired })
  #expect(revoked.availability() == .permissionRequired)
  #expect(UIInteractionError.permissionRequired.localizedDescription.contains("손쉬운 사용"))
}

@Test func uiElementResolutionUsesIdentifierThenExactLabelAndRejectsAmbiguity() throws {
  let identifier = element(id: "search.action", label: "다른 이름")
  #expect(try UIElementResolver.resolve(label: "search.action",
    elements: [identifier]).id == identifier.id)
  let search = element(label: "Search")
  #expect(try UIElementResolver.resolve(label: "Search", elements: [search]).id == search.id)
  #expect(throws: UIInteractionError.self) {
    try UIElementResolver.resolve(label: "Search", elements: [search, element(label: "Search")])
  }
}

@Test func disabledAndUnsupportedElementsAreRejected() {
  #expect(throws: UIInteractionError.self) {
    try UIElementResolver.resolve(label: "Search", elements: [element(label: "Search", enabled: false)])
  }
  #expect(throws: UIInteractionError.self) {
    try UIElementResolver.resolve(label: "Info",
      elements: [element(role: .staticText, label: "Info")])
  }
}

@Test func secureTextFieldsAreBlockedWithoutReadingValues() {
  let secure = element(role: .textField, subrole: "AXSecureTextField", label: "Password")
  #expect(throws: UIInteractionError.self) { try UIInteractionPolicy.validateTextTarget(secure) }
}

@Test func dangerousButtonsRequireStrictRiskWhileNavigationIsAutomatic() {
  #expect(UIInteractionPolicy.risk(for: element(label: "Delete")) == .destructive)
  #expect(UIInteractionPolicy.risk(for: element(label: "삭제")) == .destructive)
  #expect(ApprovalPolicy.risk(for: .activateApplication) == .safeNavigation)
  #expect(!AgentAction.activateApplication.requiresApproval)
  #expect(AgentAction.pressUIElement.requiresApproval)
  #expect(AgentAction.closeWindow.requiresApproval)
  #expect(AgentAction.setUIText.requiresApproval)
}

@Test func semanticShortcutsAreClosedAllowlist() {
  #expect(Set(KeyboardShortcut.allCases.map(\.rawValue)) == ["quickOpen", "commandPalette",
    "find", "closeWindow", "escape", "confirm", "nextTab", "previousTab"])
}

private func element(role: UIElementRole = .button, subrole: String? = nil,
                     id: String? = nil, label: String, enabled: Bool = true) -> UIElementDescriptor {
  UIElementDescriptor(id: UUID(), role: role, subrole: subrole, identifier: id,
    title: nil, label: label, valueSummary: nil, enabled: enabled, focused: false,
    valueSettable: [.textField, .textArea, .searchField, .comboBox].contains(role),
    hasValueAttribute: [.textField, .textArea, .searchField, .comboBox].contains(role),
    applicationBundleIdentifier: "com.microsoft.VSCode", windowIdentifier: 1,
    windowTitle: "PTFriends", parentPath: [], supportedActions: ["AXPress"])
}
