import Foundation
import SQLite3

final class SkillRepository {
  private let url: URL
  private let dates = ISO8601DateFormatter()
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  init(databaseURL: URL = MemoryRepository.defaultDatabaseURL) { url = databaseURL }

  func bootstrap() throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try database { db in
    guard sqlite3_exec(db, SkillSchema.sql, nil, nil, nil) == SQLITE_OK else { throw failure(db) }
    }
  }

  func save(_ skill: LearnedSkill) throws -> LearnedSkill {
    try SkillValidator.validate(skill)
    let aliases = try json(skill.aliases), steps = try json(skill.steps)
    try statement("""
      INSERT INTO learned_skills VALUES(?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET name=excluded.name,aliases_json=excluded.aliases_json,
      description=excluded.description,steps_json=excluded.steps_json,
      confidence=excluded.confidence,usage_count=excluded.usage_count,updated_at=excluded.updated_at;
      """) { stmt in
      bind([skill.id.uuidString, skill.name, aliases, skill.description, steps,
        String(skill.confidence), String(skill.usageCount), dates.string(from: skill.createdAt),
        dates.string(from: skill.updatedAt)], stmt)
      guard sqlite3_step(stmt) == SQLITE_DONE else { throw SkillError.storage("write failed") }
    }
    return skill
  }

  func skills() throws -> [LearnedSkill] { try statement(
    "SELECT id,name,aliases_json,description,steps_json,confidence,usage_count,created_at,updated_at FROM learned_skills ORDER BY updated_at DESC") { stmt in
      var result: [LearnedSkill] = []
      while sqlite3_step(stmt) == SQLITE_ROW { if let skill = decode(stmt) { result.append(skill) } }
      return result
    }
  }

  func find(_ name: String) throws -> LearnedSkill? {
    let key = SkillMatcher.normalize(name)
    return try skills().first { ([ $0.name ] + $0.aliases).contains { SkillMatcher.normalize($0) == key } }
  }

  func delete(_ name: String) throws -> Bool {
    guard let skill = try find(name) else { return false }
    return try statement("DELETE FROM learned_skills WHERE id=?") { stmt in
      bind([skill.id.uuidString], stmt); sqlite3_step(stmt)
      return sqlite3_changes(sqlite3_db_handle(stmt)) > 0
    }
  }

  func recordUsage(skill: LearnedSkill, request: String, succeeded: Bool) throws {
    try statement("INSERT INTO skill_usage VALUES(?,?,?,?,?)") { stmt in
      bind([UUID().uuidString, skill.id.uuidString, request, succeeded ? "1" : "0", dates.string(from: .now)], stmt)
      guard sqlite3_step(stmt) == SQLITE_DONE else { throw SkillError.storage("usage write failed") }
    }
    var updated = skill; updated.usageCount += 1
    updated.confidence = min(1, max(0, updated.confidence + (succeeded ? 0.05 : -0.1)))
    updated.updatedAt = .now; _ = try save(updated)
  }

  func usages(skillID: UUID) throws -> [SkillUsage] { try statement(
    "SELECT skill_id,request,succeeded,created_at FROM skill_usage WHERE skill_id=? ORDER BY created_at") { stmt in
      bind([skillID.uuidString], stmt); var result: [SkillUsage] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        if let id = UUID(uuidString: text(stmt, 0)), let date = dates.date(from: text(stmt, 3)) {
          result.append(SkillUsage(skillID: id, request: text(stmt, 1),
            succeeded: sqlite3_column_int(stmt, 2) == 1, createdAt: date))
        }
      }; return result
    }
  }

  private func decode(_ stmt: OpaquePointer?) -> LearnedSkill? {
    guard let id = UUID(uuidString: text(stmt, 0)), let aliases: [String] = decodeJSON(text(stmt, 2)),
      let steps: [AgentStep] = decodeJSON(text(stmt, 4)), let created = dates.date(from: text(stmt, 7)),
      let updated = dates.date(from: text(stmt, 8)) else { return nil }
    let skill = LearnedSkill(id: id, name: text(stmt, 1), aliases: aliases, description: text(stmt, 3),
      steps: steps, confidence: sqlite3_column_double(stmt, 5), usageCount: Int(sqlite3_column_int(stmt, 6)),
      createdAt: created, updatedAt: updated)
    return SkillValidator.errors(in: skill).isEmpty ? skill : nil
  }

  private func json<T: Encodable>(_ value: T) throws -> String {
    guard let text = String(data: try JSONEncoder().encode(value), encoding: .utf8) else { throw SkillError.storage("encode failed") }; return text
  }
  private func decodeJSON<T: Decodable>(_ value: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(value.utf8)) }
  private func text(_ stmt: OpaquePointer?, _ index: Int32) -> String { sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? "" }
  private func bind(_ values: [String], _ stmt: OpaquePointer?) { for (i, value) in values.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), value, -1, transient) } }
  private func statement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T { try database { db in var stmt: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure(db) }; defer { sqlite3_finalize(stmt) }; return try body(stmt) } }
  private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T { var db: OpaquePointer?; guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw SkillError.storage("open failed") }; defer { sqlite3_close(db) }; return try body(db) }
  private func failure(_ db: OpaquePointer) -> Error { SkillError.storage(String(cString: sqlite3_errmsg(db))) }
}
