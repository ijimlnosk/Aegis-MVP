import Foundation
import Testing
@testable import AegisDesktop

@Test func scheduleParserReadsDailyWeekdayAndAfternoonTimes() {
  #expect(ScheduleIntentParser.parse("매일 아침 9시에 PTFriends 상태 알려줘")
    == .create(request: "PTFriends 상태 알려줘", hour: 9, minute: 0, weekdaysOnly: false))
  #expect(ScheduleIntentParser.parse("평일 오후 6시 반에 sol-server 상태 보여줘")
    == .create(request: "sol-server 상태 보여줘", hour: 18, minute: 30, weekdaysOnly: true))
  #expect(ScheduleIntentParser.parse("매일 07:45에 /status")
    == .create(request: "/status", hour: 7, minute: 45, weekdaysOnly: false))
  #expect(ScheduleIntentParser.parse("예약 목록 보여줘") == .list)
  #expect(ScheduleIntentParser.parse("예약 2번 삭제해줘") == .delete(index: 2))
  #expect(ScheduleIntentParser.parse("PTFriends 상태 알려줘") == nil)
  #expect(ScheduleIntentParser.parse("매일 25시에 상태 알려줘") == nil)
}

@Test func scheduledTaskIsDueOnceWithinTheLatenessWindow() throws {
  var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
  let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 10)))
  var task = ScheduledTask(id: UUID(), request: "x", hour: 9, minute: 0, weekdaysOnly: true, lastRunAt: nil)
  #expect(task.dueSlot(now: monday, calendar: calendar) != nil)
  task.lastRunAt = monday
  #expect(task.dueSlot(now: monday.addingTimeInterval(60), calendar: calendar) == nil)
  task.lastRunAt = nil
  #expect(task.dueSlot(now: monday.addingTimeInterval(2 * 3600), calendar: calendar) == nil)
  let saturday = monday.addingTimeInterval(5 * 86_400)
  #expect(task.dueSlot(now: saturday, calendar: calendar) == nil)
  let early = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8, minute: 59)))
  #expect(task.dueSlot(now: early, calendar: calendar) == nil)
}

@Test func scheduleStoreRoundTrips() throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    .appendingPathComponent("schedules.json")
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = ScheduledTaskStore(url: url)
  #expect(store.load().isEmpty)
  let task = ScheduledTask(id: UUID(), request: "PTFriends 상태 알려줘", hour: 9, minute: 0, weekdaysOnly: false)
  try store.save([task])
  #expect(store.load() == [task])
}

@MainActor @Test func scheduledRunRefusesStepsThatNeedApproval() {
  let agent = AegisAgent()
  agent.scheduledRun = ScheduledTask(id: UUID(), request: "x", hour: 9, minute: 0, weekdaysOnly: false)
  agent.execute(AgentPlan(step: AgentStep(action: .createCommit, project: "PTFriends")), request: "PTFriends 커밋해줘")
  #expect(agent.pendingMacAction == nil)
  #expect(agent.chat.messages.contains { $0.content == AegisAgent.scheduledApprovalRefusal })
}

@Test func scheduledPushCarriesARedactedBoundedResult() {
  let push = PushMessages.scheduled(request: "PTFriends 상태 알려줘",
    result: "Branch: dev token=abc123secret " + String(repeating: "가", count: 600), succeeded: true)
  #expect(push.title == "Aegis 예약: PTFriends 상태 알려줘")
  #expect(!push.message.contains("abc123secret"))
  #expect(push.message.count <= 400)
}
