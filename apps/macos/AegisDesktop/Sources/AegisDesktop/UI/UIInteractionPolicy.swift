import Foundation

enum UIInteractionPolicy {
  static let dangerousLabels = ["delete", "remove", "erase", "format", "factory reset",
    "purchase", "buy", "pay", "send", "submit", "install", "uninstall", "allow",
    "grant access", "삭제", "제거", "지우기", "초기화", "구매", "결제", "보내기",
    "전송", "설치", "제거", "허용", "접근 권한"]

  static func risk(for descriptor: UIElementDescriptor) -> ActionRisk {
    let text = [descriptor.label, descriptor.title].compactMap { $0 }.joined(separator: " ").lowercased()
    return dangerousLabels.contains(where: text.contains) ? .destructive : .localInteraction
  }

  static func validateTextTarget(_ descriptor: UIElementDescriptor) throws {
    let subrole = descriptor.subrole?.lowercased() ?? ""
    guard !subrole.contains("secure"), !subrole.contains("password") else {
      throw UIInteractionError.secureTextBlocked
    }
    let standardEditable = [.textField, .textArea, .searchField, .comboBox]
      .contains(descriptor.role)
    guard standardEditable || (descriptor.role == .unknown && descriptor.valueSettable) else {
      throw UIInteractionError.unsupportedRole
    }
  }
}
