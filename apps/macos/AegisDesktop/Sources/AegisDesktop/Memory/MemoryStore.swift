import Foundation

final class MemoryStore {
  let repository: MemoryRepository

  init(repository: MemoryRepository = MemoryRepository()) {
    self.repository = repository
    try? repository.bootstrap()
  }

  func handle(_ intent: MemoryIntent) -> String {
    do {
      switch intent {
      case .remember(let type, let key, let value):
        _ = try repository.save(MemoryRecord(type: type, key: key, value: value))
        return "기억했습니다: \(display(type)) · \(key) = \(value)"
      case .forget(let type, let key):
        return try repository.forget(type: type, key: key)
          ? "기억을 지웠습니다: \(key)" : "해당 기억을 찾지 못했습니다: \(key)"
      case .list(let type):
        return format(try repository.records(type: type))
      case .lookup(let type, let key):
        guard let record = try repository.find(type: type, key: key) else {
          return "해당 기억이 없습니다: \(key)"
        }
        return "\(display(type)) · \(record.key) = \(record.value)"
      }
    } catch { return "메모리 저장소 오류: \(error.localizedDescription)" }
  }

  func recordAction(request: String, action: String, target: String,
                    result: String, succeeded: Bool) {
    let value = ActionHistoryValue(request: request, action: action, target: target,
      result: String(result.prefix(500)), succeeded: succeeded, timestamp: .now)
    guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return }
    _ = try? repository.save(MemoryRecord(type: .actionHistory, key: UUID().uuidString,
      value: json, source: "tool", confidence: 1))
  }

  private func format(_ records: [MemoryRecord]) -> String {
    guard !records.isEmpty else { return "저장된 기억이 없습니다." }
    return records.prefix(30).map { "• \(display($0.type)) · \($0.key) = \($0.value)" }
      .joined(separator: "\n")
  }

  private func display(_ type: MemoryType) -> String {
    [MemoryType.fact: "사실", .preference: "선호", .alias: "별칭", .project: "프로젝트",
     .actionHistory: "작업 기록"][type] ?? type.rawValue
  }
}
