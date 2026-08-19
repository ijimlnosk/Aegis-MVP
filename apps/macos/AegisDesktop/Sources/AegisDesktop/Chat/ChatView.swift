import SwiftUI

struct ChatView: View {
  @ObservedObject var store: ChatStore
  let busy: Bool
  let submit: (String) -> Void
  let cancel: () -> Void
  let approve: (UUID) -> Void
  let reject: (UUID) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(store.messages) { message in
              ChatMessageRow(message: message, approve: approve, reject: reject)
                .id(message.id)
            }
            if busy {
              HStack { ProgressView(); Text("Aegis가 처리 중입니다…"); Spacer() }
                .foregroundStyle(.secondary).id("busy")
            }
          }.padding()
        }
        .onChange(of: store.messages.count) {
          guard let id = store.messages.last?.id else { return }
          withAnimation { proxy.scrollTo(id, anchor: .bottom) }
        }
      }
      Divider()
      ChatInput(disabled: busy, submit: submit, cancel: cancel).padding()
    }
  }
}
