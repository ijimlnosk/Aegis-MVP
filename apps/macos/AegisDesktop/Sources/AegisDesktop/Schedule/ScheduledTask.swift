import Foundation

struct ScheduledTask: Codable, Equatable, Identifiable {
  let id: UUID
  let request: String
  let hour: Int
  let minute: Int
  let weekdaysOnly: Bool
  var lastRunAt: Date?

  /// Runs missed by more than this (Mac asleep, Aegis busy) are skipped rather than run late.
  static let lateness: TimeInterval = 60 * 60

  var timeText: String {
    "\(weekdaysOnly ? "평일" : "매일") \(String(format: "%02d:%02d", hour, minute))"
  }

  /// Today's slot when it is due now and has not run yet, otherwise nil.
  func dueSlot(now: Date, calendar: Calendar = .current) -> Date? {
    guard let slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
    if weekdaysOnly, calendar.isDateInWeekend(slot) { return nil }
    guard now >= slot, now.timeIntervalSince(slot) <= Self.lateness else { return nil }
    if let lastRunAt, lastRunAt >= slot { return nil }
    return slot
  }
}

/// Schedules live in a small JSON file next to the memory database.
final class ScheduledTaskStore {
  static let maximumTasks = 20
  private let url: URL

  init(url: URL = MemoryRepository.defaultDatabaseURL.deletingLastPathComponent()
    .appending(path: "schedules.json")) {
    self.url = url
  }

  func load() -> [ScheduledTask] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([ScheduledTask].self, from: data)) ?? []
  }

  func save(_ tasks: [ScheduledTask]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(tasks).write(to: url, options: .atomic)
  }
}
