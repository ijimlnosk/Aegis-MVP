import SwiftUI

struct ChatInput: View {
  @State private var text = ""
  let disabled: Bool
  let submit: (String) -> Void
  let cancel: () -> Void

  var body: some View {
    HStack(alignment: .bottom) {
      TextField("Aegis에게 메시지 보내기", text: $text, axis: .vertical)
        .lineLimit(1...5)
        .textFieldStyle(.roundedBorder)
        .onSubmit(send)
      if disabled { Button("취소", action: cancel).buttonStyle(.bordered) }
      else {
        Button("전송", action: send).buttonStyle(.borderedProminent)
          .disabled(trimmed.isEmpty)
      }
    }
  }

  private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func send() {
    let message = trimmed
    guard !disabled, !message.isEmpty else { return }
    text = ""
    submit(message)
  }
}
