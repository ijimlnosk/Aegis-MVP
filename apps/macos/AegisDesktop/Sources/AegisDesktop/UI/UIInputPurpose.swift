import Foundation

enum UIInputPurpose: String, Codable, Sendable {
  case navigationSearch, commandSearch, find, filter
  case editorContent, messageContent, formContent, terminalInput, secureInput, unknown

  var risk: ActionRisk {
    switch self {
    case .navigationSearch, .commandSearch, .find, .filter: .safeNavigation
    case .editorContent, .formContent, .terminalInput, .unknown: .localMutation
    case .messageContent, .secureInput: .sensitiveInteraction
    }
  }

  func isTrustedSemanticLabel(_ label: String?) -> Bool {
    let value = label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    switch self {
    case .navigationSearch:
      return ["quick open", "검색", "search", "application search"].contains(value)
    case .commandSearch: return ["command palette", "명령 팔레트"].contains(value)
    case .find: return ["find", "찾기"].contains(value)
    case .filter: return ["filter", "필터"].contains(value)
    default: return true
    }
  }
}
