import Foundation
import SQLite3

struct ConversationActionEvent: Codable, Equatable {
  let action: String
  let succeeded: Bool
  let result: String?
}

struct ConversationTurnRecord: Equatable {
  let id: UUID
  let sessionId: String
  let request: String
  let plan: [String]
  let actions: [ConversationActionEvent]
  let responses: [String]
  let status: String
}

final class ConversationEventStore {
  private let url: URL
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(databaseURL: URL = MemoryRepository.defaultDatabaseURL) {
    url = databaseURL
    try? bootstrap()
  }

  func begin(sessionId: String, request: String) -> UUID {
    let id = UUID(), now = ISO8601DateFormatter().string(from: .now)
    try? statement("INSERT INTO conversation_turns VALUES(?,?,?,?,?,?,?,?,?);") { query in
      bind([id.uuidString, scrub(sessionId), scrub(request), "[]", "[]", "[]", "received", now, now], query)
      guard sqlite3_step(query) == SQLITE_DONE else { throw RepositoryError.writeFailed }
    }
    prune()
    return id
  }

  func setPlan(_ actions: [String], turnId: UUID) {
    update(column: "plan_json", value: json(actions.map(scrub)), turnId: turnId)
  }

  func appendAction(_ event: ConversationActionEvent, turnId: UUID) {
    guard var values = record(id: turnId)?.actions else { return }
    values.append(.init(action: scrub(event.action), succeeded: event.succeeded,
      result: event.result.map { scrub(String($0.prefix(2_000))) }))
    update(column: "actions_json", value: json(values), turnId: turnId)
  }

  func appendResponse(_ response: String, turnId: UUID) {
    guard var values = record(id: turnId)?.responses else { return }
    values.append(scrub(String(response.prefix(4_000))))
    update(column: "responses_json", value: json(Array(values.suffix(20))), turnId: turnId)
  }

  func setStatus(_ status: String, turnId: UUID) {
    update(column: "status", value: status, turnId: turnId)
  }

  func record(id: UUID) -> ConversationTurnRecord? {
    try? statement("SELECT id,session_id,request,plan_json,actions_json,responses_json,status FROM conversation_turns WHERE id=?;") { query in
      bind([id.uuidString], query)
      guard sqlite3_step(query) == SQLITE_ROW else { return nil }
      func text(_ index: Int32) -> String { sqlite3_column_text(query, index).map(String.init(cString:)) ?? "" }
      guard let id = UUID(uuidString: text(0)) else { return nil }
      return .init(id: id, sessionId: text(1), request: text(2),
        plan: decode([String].self, text(3)) ?? [],
        actions: decode([ConversationActionEvent].self, text(4)) ?? [],
        responses: decode([String].self, text(5)) ?? [], status: text(6))
    }
  }

  func latestValidationResponse(sessionId: String, excluding id: UUID? = nil) -> String? {
    let sql = "SELECT id,responses_json FROM conversation_turns WHERE session_id=? ORDER BY created_at DESC LIMIT 20;"
    return try? statement(sql) { query in
      bind([scrub(sessionId)], query)
      while sqlite3_step(query) == SQLITE_ROW {
        let rowId = sqlite3_column_text(query, 0).map { String(cString: $0) } ?? ""
        if rowId == id?.uuidString { continue }
        let raw = sqlite3_column_text(query, 1).map { String(cString: $0) } ?? "[]"
        let responses = decode([String].self, raw) ?? []
        if let match = responses.reversed().first(where: {
          $0.localizedCaseInsensitiveContains("검증") || $0.localizedCaseInsensitiveContains("validation")
        }) { return match }
      }
      return nil
    }
  }

  private func bootstrap() throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try database { db in
      let sql = """
      CREATE TABLE IF NOT EXISTS conversation_turns(
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL, request TEXT NOT NULL,
        plan_json TEXT NOT NULL, actions_json TEXT NOT NULL, responses_json TEXT NOT NULL,
        status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS conversation_turns_session ON conversation_turns(session_id, created_at DESC);
      """
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw RepositoryError.writeFailed }
    }
  }

  private func update(column: String, value: String, turnId: UUID) {
    let allowed = ["plan_json", "actions_json", "responses_json", "status"]
    guard allowed.contains(column) else { return }
    try? statement("UPDATE conversation_turns SET \(column)=?, updated_at=? WHERE id=?;") { query in
      bind([value, ISO8601DateFormatter().string(from: .now), turnId.uuidString], query)
      guard sqlite3_step(query) == SQLITE_DONE else { throw RepositoryError.writeFailed }
    }
  }

  private func prune() {
    _ = try? database { db in
      sqlite3_exec(db, "DELETE FROM conversation_turns WHERE id NOT IN (SELECT id FROM conversation_turns ORDER BY created_at DESC LIMIT 1000);", nil, nil, nil)
    }
  }

  private func scrub(_ value: String) -> String { SecretRedactor.redact(value) }

  private func json<T: Encodable>(_ value: T) -> String {
    (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
  }
  private func decode<T: Decodable>(_ type: T.Type, _ value: String) -> T? {
    try? JSONDecoder().decode(type, from: Data(value.utf8))
  }
  private func bind(_ values: [String], _ query: OpaquePointer?) {
    for (index, value) in values.enumerated() { sqlite3_bind_text(query, Int32(index + 1), value, -1, transient) }
  }
  private func statement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
    try database { db in var query: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK else { throw RepositoryError.writeFailed }; defer { sqlite3_finalize(query) }; return try body(query) }
  }
  private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    var db: OpaquePointer?; guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw RepositoryError.openFailed }; defer { sqlite3_close(db) }; return try body(db)
  }
}
