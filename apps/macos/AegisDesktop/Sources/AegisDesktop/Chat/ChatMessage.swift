import Foundation

enum ChatRole {
  case user
  case assistant
  case system
  case approval
  case error
}

enum ApprovalState {
  case pending
  case approved
  case rejected
}

struct ChatMessage: Identifiable {
  let id: UUID
  let role: ChatRole
  let content: String
  let createdAt: Date
  var approvalState: ApprovalState?

  init(id: UUID = UUID(), role: ChatRole, content: String,
       createdAt: Date = .now, approvalState: ApprovalState? = nil) {
    self.id = id
    self.role = role
    self.content = content
    self.createdAt = createdAt
    self.approvalState = approvalState
  }
}
