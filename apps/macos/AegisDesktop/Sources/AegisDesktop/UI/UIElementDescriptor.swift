import Foundation

enum UIElementRole: String, Codable, Sendable {
  case button, textField, textArea, searchField, menuItem, menu, tab, checkbox
  case radioButton, popUpButton, scrollArea, window, toolbar, outlineRow, staticText
  case comboBox, dialog, list
  case unknown

  var actionable: Bool {
    ![.toolbar, .staticText, .dialog, .list, .unknown].contains(self)
  }
}

struct UIElementDescriptor: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let role: UIElementRole
  let subrole: String?
  let identifier: String?
  let title: String?
  let label: String?
  let valueSummary: String?
  let enabled: Bool
  let focused: Bool
  let valueSettable: Bool
  let hasValueAttribute: Bool
  let applicationBundleIdentifier: String
  let windowIdentifier: UInt32?
  let windowTitle: String?
  let parentPath: [String]
  let supportedActions: [String]

  var displayName: String { label ?? title ?? identifier ?? role.rawValue }
}

enum KeyboardShortcut: String, Codable, CaseIterable, Sendable {
  case quickOpen, commandPalette, find, closeWindow, escape, confirm, nextTab, previousTab
}

enum UIScrollDirection: String, Codable, Sendable { case up, down, left, right }

enum UIInteractionError: LocalizedError, Equatable {
  case permissionRequired, applicationNotRunning(String), windowNotFound(String)
  case ambiguousTarget(String), targetNotFound(String), disabled, unsupportedRole
  case unsupportedAction, secureTextBlocked, staleElement, verificationFailed, timedOut
  case quickOpenUnverified

  var errorDescription: String? {
    switch self {
    case .permissionRequired:
      "UI 제어 권한이 필요합니다. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 AegisDesktop을 허용해 주세요."
    case .applicationNotRunning(let app): "실행 중인 \(app) 앱을 찾지 못했습니다."
    case .windowNotFound(let value): "현재 보이는 \(value) 창을 찾지 못했습니다."
    case .ambiguousTarget(let value): "\(value) UI 요소가 여러 개입니다. 더 정확히 지정해 주세요."
    case .targetNotFound(let value): "\(value) UI 요소를 찾지 못했습니다."
    case .disabled: "해당 UI 요소가 비활성화되어 있습니다."
    case .unsupportedRole, .unsupportedAction: "해당 UI 요소는 안전한 자동 조작을 지원하지 않습니다."
    case .secureTextBlocked: "암호나 보안 입력 필드에는 자동으로 텍스트를 입력할 수 없습니다."
    case .staleElement: "UI가 변경되어 대상 요소가 더 이상 유효하지 않습니다. 다시 확인해 주세요."
    case .verificationFailed: "UI 작업 후 상태를 확인하지 못했습니다."
    case .timedOut: "UI 작업 시간이 초과되었습니다."
    case .quickOpenUnverified: "VSCode Quick Open을 열었지만 입력창을 확인하지 못했습니다."
    }
  }
}
