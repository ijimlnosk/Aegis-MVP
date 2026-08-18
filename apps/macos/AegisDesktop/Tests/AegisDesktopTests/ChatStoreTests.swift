import Foundation
import Testing
@testable import AegisDesktop

@MainActor
@Test func keepsFiveRequestsAndResponsesInOrder() {
  let store = ChatStore()
  for index in 1...5 {
    store.append(.user, "요청 \(index)")
    store.append(.assistant, "응답 \(index)")
  }
  #expect(store.messages.count == 11)
  #expect(store.messages[1].content == "요청 1")
  #expect(store.messages[10].content == "응답 5")
}

@MainActor
@Test func approvalMessageRemainsAfterRejection() {
  let store = ChatStore()
  let id = UUID()
  store.appendApproval(id: id, content: "컨테이너 재시작")
  store.resolveApproval(id: id, state: .rejected)
  store.append(.system, "작업을 거절했습니다.")
  #expect(store.messages.contains { $0.id == id && $0.approvalState == .rejected })
  #expect(store.messages.last?.content == "작업을 거절했습니다.")
}

@MainActor
@Test func approvalRemainsBeforeExecutionResult() {
  let store = ChatStore()
  let id = UUID()
  store.appendApproval(id: id, content: "컨테이너 재시작")
  store.resolveApproval(id: id, state: .approved)
  store.append(.assistant, "컨테이너를 재시작했습니다.")
  #expect(store.messages.contains { $0.id == id && $0.approvalState == .approved })
  #expect(store.messages.last?.role == .assistant)
}

@MainActor
@Test func errorRemainsAfterLaterMessages() {
  let store = ChatStore()
  store.append(.error, "Server Agent가 응답하지 않습니다.")
  store.append(.user, "다시 확인해")
  #expect(store.messages.contains { $0.role == .error })
}
