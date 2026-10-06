import SwiftUI

struct ChatMessageRow: View {
  let message: ChatMessage
  let approve: (UUID) -> Void
  let reject: (UUID) -> Void

  var body: some View {
    HStack {
      if message.role == .user { Spacer(minLength: 60) }
      VStack(alignment: .leading, spacing: 8) {
        Text(label).font(.caption.bold()).foregroundStyle(labelColor)
        Text(message.content).textSelection(.enabled)
          .font(message.role == .system ? .caption : .body)
        if message.role == .approval { approvalControls }
      }
      .padding(12)
      .background(background)
      .clipShape(.rect(cornerRadius: 12))
      if message.role != .user { Spacer(minLength: 60) }
    }
  }

  @ViewBuilder private var approvalControls: some View {
    switch message.approvalState {
    case .pending:
      let presentation = ApprovalPresentation.present(kind: message.approvalKind)
      Text("승인하면: \(presentation.effect)").font(.callout.weight(presentation.irreversible ? .semibold : .regular))
        .foregroundStyle(presentation.irreversible ? .red : .primary)
      HStack {
        Button(presentation.confirmLabel) { approve(message.id) }.buttonStyle(.borderedProminent)
          .tint(presentation.irreversible ? .red : .accentColor)
        Button("거절") { reject(message.id) }
      }
    case .approved: Label("승인됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    case .rejected: Label("거절됨", systemImage: "xmark.circle.fill").foregroundStyle(.secondary)
    case nil: EmptyView()
    }
  }

  private var label: String {
    switch message.role {
    case .user: "나"
    case .assistant: "Aegis"
    case .system: "상태"
    case .approval: "승인 요청"
    case .error: "오류"
    }
  }

  private var labelColor: Color { message.role == .error ? .red : .secondary }
  private var background: Color {
    switch message.role {
    case .user: .accentColor.opacity(0.16)
    case .approval: .orange.opacity(0.16)
    case .error: .red.opacity(0.12)
    case .system: .secondary.opacity(0.10)
    case .assistant: .secondary.opacity(0.08)
    }
  }
}
