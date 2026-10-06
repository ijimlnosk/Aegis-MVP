import Foundation

@MainActor
final class ChatStore: ObservableObject {
  @Published private(set) var messages: [ChatMessage] = [
    ChatMessage(role: .system, content: "Aegis가 준비되었습니다. 텍스트로 요청해 주세요."),
  ]

  func append(_ role: ChatRole, _ content: String, id: UUID = UUID()) {
    messages.append(ChatMessage(id: id, role: role, content: content))
  }

  func appendApproval(id: UUID, content: String, kind: String? = nil) {
    messages.append(ChatMessage(id: id, role: .approval, content: content, approvalState: .pending,
      approvalKind: kind))
  }

  func resolveApproval(id: UUID, state: ApprovalState) {
    guard let index = messages.firstIndex(where: { $0.id == id && $0.role == .approval }) else { return }
    messages[index].approvalState = state
  }
}
