import Foundation
import Testing
@testable import AegisDesktop

private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Seoul")!; return value }
private func at(_ hour: Int, _ minute: Int, day: Int = 7) -> Date {
  calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Test func relativeRemindersCarryANoteOrARequest() {
  let now = at(14, 0)
  #expect(ReminderIntentParser.parse("30분 뒤에 배포 확인하라고 알려줘", now: now, calendar: calendar)
    == .create(.note("배포 확인"), fireAt: at(14, 30)))
  #expect(ReminderIntentParser.parse("1시간 후에 알려줘", now: now, calendar: calendar) == .create(.note(""), fireAt: at(15, 0)))
  #expect(ReminderIntentParser.parse("10분 뒤에 곧 도착이라고 알려줘", now: now, calendar: calendar)
    == .create(.note("곧 도착"), fireAt: at(14, 10)))
}

@Test func absoluteRemindersRollToTomorrowWhenPast() {
  let now = at(14, 0)
  #expect(ReminderIntentParser.parse("오후 3시에 PTFriends 상태 알려줘", now: now, calendar: calendar)
    == .create(.request("PTFriends 상태 알려줘"), fireAt: at(15, 0)))
  #expect(ReminderIntentParser.parse("오전 9시 반에 회의 준비하라고 알려줘", now: now, calendar: calendar)
    == .create(.note("회의 준비"), fireAt: at(9, 30, day: 8)))
  #expect(ReminderIntentParser.parse("내일 18:00에 알려줘", now: now, calendar: calendar) == .create(.note(""), fireAt: at(18, 0, day: 8)))
}

@Test func reminderParserLeavesSchedulesWatchesAndListsToOthers() {
  #expect(ReminderIntentParser.parse("매일 아침 9시에 PTFriends 상태 알려줘") == nil)
  #expect(ReminderIntentParser.parse("PTFriends CI 끝나면 알려줘") == nil)
  #expect(ReminderIntentParser.parse("sol-server 복구되면 알려줘") == nil)
  #expect(ReminderIntentParser.parse("PTFriends 상태 알려줘") == nil)
  #expect(ReminderIntentParser.parse("리마인더 목록 보여줘") == .list)
  #expect(ReminderIntentParser.parse("리마인더 2번 취소") == .cancel(index: 2))
}

@MainActor @Test func dueNoteRemindersAreDeliveredAndRemoved() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let reminders = ReminderStore(url: directory.appendingPathComponent("reminders.json"))
  let runner = ScheduledTaskRunner(store: ScheduledTaskStore(url: directory.appendingPathComponent("s.json")), reminders: reminders)
  let agent = AegisAgent()
  try reminders.save([Reminder(id: UUID(), content: .note("배포 확인"), fireAt: .now.addingTimeInterval(-5)),
    Reminder(id: UUID(), content: .note("나중"), fireAt: .now.addingTimeInterval(600))])
  runner.start(agent: agent); runner.stop()
  runner.tick()
  #expect(agent.chat.messages.contains { $0.content == "리마인더: 배포 확인" })
  #expect(reminders.load().map(\.summary) == ["나중"])
}

@MainActor @Test func reminderTimesUseTwentyFourHourClock() {
  let evening = Calendar.current.date(bySettingHour: 17, minute: 48, second: 0, of: .now.addingTimeInterval(86_400))!
  #expect(AegisAgent.when(evening) == "내일 17:48")
}
