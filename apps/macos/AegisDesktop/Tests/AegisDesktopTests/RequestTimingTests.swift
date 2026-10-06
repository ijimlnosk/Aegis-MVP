import Foundation
import Testing
@testable import AegisDesktop

private func timing(_ total: Int, planner: [Int] = [], backend: String = "codex",
                    request: String = "요청") -> RequestTimingRecord {
  RequestTimingRecord(createdAt: .now, source: "desktop", request: request,
    plannerCalls: planner.map { PlannerCallTiming(backend: backend, milliseconds: $0,
      promptCharacters: 1_000, scope: [.project], succeeded: true) },
    totalMilliseconds: total, actions: [], outcome: "completed")
}

@MainActor @Test func trackerRedactsSecretsAndMeasuresElapsedTime() {
  let tracker = RequestTimingTracker(source: "remote", request: "token=abc123 PTFriends 상태")
  tracker.planner.record(PlannerCallTiming(backend: "ollama", milliseconds: 40,
    promptCharacters: 10, scope: [.project], succeeded: false))
  tracker.setPlan(["get_project_git_status"])
  let record = tracker.finish(outcome: "completed", now: tracker.startedAt + .milliseconds(250))
  #expect(record.totalMilliseconds == 250)
  #expect(record.planningMilliseconds == 40)
  #expect(record.route == "planner")
  #expect(!record.request.contains("abc123"))
  #expect(record.actions == ["get_project_git_status"])
}

@Test func timingStoreKeepsOnlyTheNewestRecords() throws {
  let url = FileManager.default.temporaryDirectory.appending(path: "timings-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: url) }
  let store = RequestTimingStore(url: url)
  for index in 0..<(RequestTimingStore.limit + 3) { store.append(timing(index)) }
  let values = store.recent()
  #expect(values.count == RequestTimingStore.limit)
  #expect(values.first?.totalMilliseconds == 3)
}

@Test func timingSummarySeparatesRuleAndPlannerRequests() {
  let text = RequestTimingSummary.format([timing(200), timing(400),
    timing(9_000, planner: [8_000], request: "느린 요청"), timing(3_000, planner: [2_500], backend: "ollama")])
  #expect(text.contains("최근 요청 성능 (4건)"))
  #expect(text.contains("규칙 처리: 2건"))
  #expect(text.contains("AI planner: 2건"))
  #expect(text.contains("codex: 1회 (실패 0)"))
  #expect(text.contains("ollama: 1회"))
  #expect(text.contains("\"느린 요청\" 9.0초"))
}

@Test func timingSummaryHandlesEmptyHistory() {
  #expect(RequestTimingSummary.format([]).contains("없습니다"))
  #expect(RequestTimingSummary.percentile([], 0.9) == 0)
  #expect(RequestTimingSummary.percentile([1, 2, 3, 4, 5], 0.5) == 3)
}

@Test func perfSlashCommandReadsTimingsOnlyWhenRequested() {
  var reads = 0
  _ = SlashCommandResolver.resolve("/help", projects: [], timings: { reads += 1; return [] })
  #expect(reads == 0)
  guard case .message(let text) = SlashCommandResolver.resolve("/perf", projects: [],
    timings: { reads += 1; return [timing(100)] }) else { Issue.record("perf must be a message"); return }
  #expect(reads == 1)
  #expect(text.contains("최근 요청 성능 (1건)"))
}
