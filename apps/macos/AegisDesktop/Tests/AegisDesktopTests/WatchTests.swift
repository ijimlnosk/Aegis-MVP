import Foundation
import Testing
@testable import AegisDesktop

private func resolve(_ text: String) -> String? { text.contains("PTFriends") ? "PTFriends" : nil }

@Test func watchParserRecognizesCIAndServerConditions() {
  #expect(WatchIntentParser.parse("PTFriends CI 끝나면 알려줘", project: resolve) == .create(.ciFinished(project: "PTFriends")))
  #expect(WatchIntentParser.parse("sol-server 복구되면 알려줘", project: resolve) == .create(.serverReachable))
  #expect(WatchIntentParser.parse("서버 다시 켜지면 알려줘", project: resolve) == .create(.serverReachable))
  #expect(WatchIntentParser.parse("감시 목록 보여줘", project: resolve) == .list)
  #expect(WatchIntentParser.parse("감시 2번 취소", project: resolve) == .cancel(index: 2))
  #expect(WatchIntentParser.parse("PTFriends CI 상태 보여줘", project: resolve) == nil)
  #expect(WatchIntentParser.parse("CI 끝나면 알려줘", project: resolve) == nil)
}

@Test func ciWatchWaitsUntilTheRunCompletes() {
  #expect(WatchEvaluator.ciOutcome(status: "in_progress", conclusion: nil, name: "ci", project: "P") == .waiting)
  #expect(WatchEvaluator.ciOutcome(status: "queued", conclusion: nil, name: "ci", project: "P") == .waiting)
  #expect(WatchEvaluator.ciOutcome(status: "completed", conclusion: "success", name: "ci", project: "P")
    == .met("P CI 'ci'이 끝났습니다: 성공"))
  #expect(WatchEvaluator.ciOutcome(status: "completed", conclusion: "failure", name: "ci", project: "P")
    == .met("P CI 'ci'이 끝났습니다: 실패 (failure)"))
}

@Test func watchStoreRoundTrips() throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    .appendingPathComponent("watches.json")
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = WatchTaskStore(url: url)
  let task = WatchTask(id: UUID(), kind: .ciFinished(project: "PTFriends"), expiresAt: .now)
  try store.save([task])
  #expect(store.load() == [task])
}
