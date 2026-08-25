import Foundation
import Testing
@testable import AegisDesktop

@Test func conversationTurnPersistsRequestPlanActionsAndResponses() {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "aegis-conversation-\(UUID())/memory.sqlite")
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = ConversationEventStore(databaseURL: url)
  let id = store.begin(sessionId: "mobile-1", request: "PTFriends N+1 조사해")
  store.setPlan(["analyze_project_with_coding_agent"], turnId: id)
  store.appendAction(.init(action: "analyze_project_with_coding_agent", succeeded: true,
    result: "users.ts:42"), turnId: id)
  store.appendResponse("N+1 가능성이 있습니다.", turnId: id)
  store.setStatus("succeeded", turnId: id)
  let saved = store.record(id: id)
  #expect(saved?.request == "PTFriends N+1 조사해")
  #expect(saved?.plan == ["analyze_project_with_coding_agent"])
  #expect(saved?.actions.first?.result == "users.ts:42")
  #expect(saved?.responses == ["N+1 가능성이 있습니다."])
  #expect(saved?.status == "succeeded")
}

@Test func conversationTurnRedactsCommonSecretsBeforeWriting() {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "aegis-conversation-secret-\(UUID())/memory.sqlite")
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = ConversationEventStore(databaseURL: url)
  let id = store.begin(sessionId: "mobile", request: "token=super-secret Bearer abc.def.ghi")
  store.appendResponse("api_key: sk_test_abcdefghijklmnop", turnId: id)
  let saved = store.record(id: id)
  #expect(saved?.request.contains("super-secret") == false)
  #expect(saved?.request.contains("abc.def.ghi") == false)
  #expect(saved?.responses.first?.contains("abcdefghijklmnop") == false)
  #expect(saved?.request.contains("[REDACTED]") == true)
}

@Test func latestValidationResponseSurvivesAStoreRestart() {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "aegis-conversation-recovery-\(UUID())/memory.sqlite")
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let first = ConversationEventStore(databaseURL: url)
  let id = first.begin(sessionId: "mobile-1", request: "수정해")
  first.appendResponse("검증:\n- lint: warning · 경고 2건", turnId: id)
  let second = ConversationEventStore(databaseURL: url)
  #expect(second.latestValidationResponse(sessionId: "mobile-1")?.contains("경고 2건") == true)
}
