import SwiftUI

struct AegisView: View {
  @ObservedObject var agent: AegisAgent

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading) {
          Text("AEGIS").font(.title.bold())
          Text("TEXT CHAT · LOCAL MAC INTELLIGENCE").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Label(statusText, systemImage: "circle.fill").foregroundStyle(statusColor)
        Button("백그라운드") { NSApplication.shared.keyWindow?.close() }
          .help("창만 닫고 원격 작업과 Aegis Bridge는 계속 실행합니다.")
      }
      .padding()
      Divider()
      ChatView(store: agent.chat, busy: agent.busy, submit: agent.sendFromDesktop,
        cancel: agent.cancelCurrentOperation,
        approve: agent.approveChatAction, reject: agent.rejectChatAction)
    }
  }

  private var statusText: String {
    if agent.pendingMacAction != nil { return "승인 대기" }
    return agent.busy ? "처리 중" : "준비됨"
  }

  private var statusColor: Color {
    if agent.pendingMacAction != nil { return .orange }
    return agent.busy ? .blue : .green
  }
}
