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

  /// What the user taught, grouped by kind. Tool history is internal bookkeeping, so it is
  /// counted rather than dumped as JSON.
  func format(_ records: [MemoryRecord]) -> String {
    let history = records.filter { $0.type == .actionHistory }.count
    let taught = records.filter { $0.type != .actionHistory }
    guard !taught.isEmpty else {
      return history > 0 ? "직접 알려주신 기억은 아직 없습니다. (작업 기록 \(history)건은 따로 보관 중)" : "저장된 기억이 없습니다."
    }
    let order: [MemoryType] = [.project, .alias, .preference, .fact]
    let sections = order.compactMap { type -> String? in
      let items = taught.filter { $0.type == type }.prefix(15)
      guard !items.isEmpty else { return nil }
      return ([display(type)] + items.map { "  \(label(for: $0)): \($0.value)" }).joined(separator: "\n")
    }
    let footer = history > 0 ? "\n\n작업 기록 \(history)건은 목록에서 뺐습니다." : ""
    return sections.joined(separator: "\n\n") + footer
  }

  private func label(for record: MemoryRecord) -> String {
    guard record.type == .preference else { return record.key }
    return ["default_browser": "기본 브라우저", "default_code_editor": "기본 코드 에디터",
      "preferred_project_health_checks": "기본 검증", "recent_commit_count": "최근 커밋 표시 개수"][record.key] ?? record.key
  }

  private func display(_ type: MemoryType) -> String {
    [MemoryType.fact: "사실", .preference: "선호", .alias: "별칭", .project: "프로젝트",
     .actionHistory: "작업 기록"][type] ?? type.rawValue
  }
}
