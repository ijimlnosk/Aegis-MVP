import SwiftUI

struct ChatInput: View {
  @State private var text = ""
  let disabled: Bool
  let submit: (String) -> Void
  let cancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      let suggestions = disabled ? [] : SlashCommand.suggestions(for: text)
      if !suggestions.isEmpty { SlashCommandSuggestions(commands: suggestions) { send($0) } }
      HStack(alignment: .bottom) {
        TextField("Aegis에게 메시지 보내기 (/ 로 명령어)", text: $text, axis: .vertical)
          .lineLimit(1...5)
          .textFieldStyle(.roundedBorder)
          .onSubmit { send() }
        if disabled { Button("취소", action: cancel).buttonStyle(.bordered) }
        else {
          Button("전송") { send() }.buttonStyle(.borderedProminent)
            .disabled(trimmed.isEmpty)
        }
      }
    }
  }

  private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func send(_ command: SlashCommand? = nil) {
    let message = command?.usage ?? trimmed
    guard !disabled, !message.isEmpty else { return }
    text = ""
    submit(message)
  }
}

private struct SlashCommandSuggestions: View {
  let commands: [SlashCommand]
  let choose: (SlashCommand) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(commands, id: \.self) { command in
        Button { choose(command) } label: {
          HStack {
            Text(command.usage).font(.body.monospaced()).fontWeight(.semibold)
            Text(command.summary).foregroundStyle(.secondary)
            Spacer()
          }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4).padding(.horizontal, 8)
        .accessibilityLabel("\(command.usage), \(command.summary)")
      }
    }
    .padding(4)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }
}
