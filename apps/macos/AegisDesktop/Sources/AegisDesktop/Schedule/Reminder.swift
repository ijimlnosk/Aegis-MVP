import Foundation

struct Reminder: Codable, Equatable, Identifiable {
  enum Content: Codable, Equatable {
    /// "배포 확인하라고 알려줘": push this note.
    case note(String)
    /// "PTFriends 상태 알려줘": run the request once and push the result.
    case request(String)
  }

  let id: UUID
  let content: Content
  let fireAt: Date

  var summary: String {
    switch content {
    case .note(let text): text.isEmpty ? "알림" : text
    case .request(let text): text
    }
  }
}

/// One-shot reminders, kept beside the daily schedules.
final class ReminderStore {
  static let maximum = 30
  private let url: URL

  init(url: URL = MemoryRepository.defaultDatabaseURL.deletingLastPathComponent().appending(path: "reminders.json")) {
    self.url = url
  }

  func load() -> [Reminder] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return ((try? JSONDecoder().decode([Reminder].self, from: data)) ?? []).sorted { $0.fireAt < $1.fireAt }
  }

  func save(_ reminders: [Reminder]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(reminders).write(to: url, options: .atomic)
  }
}
