import Foundation
import SQLite3

struct CommandJobRecord {
  let commandId: String
  let sessionId: String
  let request: String
  let result: DesktopBridgeResult
}

final class CommandJobStore {
  private let url: URL
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(databaseURL: URL = MemoryRepository.defaultDatabaseURL) {
    url = databaseURL
    try? bootstrap()
  }

  func save(commandId: String, sessionId: String, request: String,
            result: DesktopBridgeResult) {
    let now = ISO8601DateFormatter().string(from: .now)
    let encoded = (try? JSONEncoder().encode(sanitized(result)))
      .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    try? statement("""
      INSERT INTO command_jobs(command_id,session_id,request,result_json,created_at,updated_at)
      VALUES(?,?,?,?,?,?) ON CONFLICT(command_id,session_id) DO UPDATE SET
      result_json=excluded.result_json,updated_at=excluded.updated_at;
      """) { query in
      bind([scrub(commandId), scrub(sessionId), scrub(request), encoded, now, now], query)
      guard sqlite3_step(query) == SQLITE_DONE else { throw RepositoryError.writeFailed }
    }
  }

  func record(commandId: String, sessionId: String) -> CommandJobRecord? {
    try? statement("""
      SELECT command_id,session_id,request,result_json FROM command_jobs
      WHERE command_id=? AND session_id=?;
      """) { query in
      bind([scrub(commandId), scrub(sessionId)], query)
      guard sqlite3_step(query) == SQLITE_ROW else { return nil }
      func text(_ index: Int32) -> String {
        sqlite3_column_text(query, index).map(String.init(cString:)) ?? ""
      }
      guard let data = text(3).data(using: .utf8),
        let result = try? JSONDecoder().decode(DesktopBridgeResult.self, from: data) else { return nil }
      return .init(commandId: text(0), sessionId: text(1), request: text(2), result: result)
    }
  }

  private func bootstrap() throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try database { db in
      let sql = """
      CREATE TABLE IF NOT EXISTS command_jobs(
        command_id TEXT NOT NULL, session_id TEXT NOT NULL, request TEXT NOT NULL,
        result_json TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        PRIMARY KEY(command_id,session_id));
      CREATE INDEX IF NOT EXISTS command_jobs_updated ON command_jobs(updated_at DESC);
      """
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw RepositoryError.writeFailed
      }
    }
  }

  private func scrub(_ value: String) -> String {
    String(redact(value).prefix(4_000))
  }

  private func sanitized(_ result: DesktopBridgeResult) -> DesktopBridgeResult {
    let approval = result.pendingApproval.map {
      DesktopBridgeApprovalCard(id: scrub($0.id), title: scrub($0.title), goal: scrub($0.goal),
        risk: scrub($0.risk), scope: scrub($0.scope))
    }
    let progress = result.progress.map {
      DesktopBridgeProgress(phase: scrub($0.phase), message: scrub($0.message),
        currentStep: $0.currentStep, totalSteps: $0.totalSteps, cancellable: $0.cancellable,
        startedAt: scrub($0.startedAt))
    }
    return DesktopBridgeResult(status: scrub(result.status), messages: result.messages.map(scrub),
      pendingApproval: approval, progress: progress, failureCode: result.failureCode.map(scrub))
  }

  private func redact(_ value: String) -> String {
    let patterns = [#"(?i)(bearer\s+)[A-Za-z0-9._~+/-]+"#,
      #"(?i)((?:api[_-]?key|token|password|secret)\s*[:=]\s*)[^\s,;]+"#,
      #"\b(?:sk|ghp|github_pat)_[A-Za-z0-9_\-]{12,}\b"#]
    return patterns.reduce(value) { text, pattern in
      text.replacingOccurrences(of: pattern, with: "$1[REDACTED]", options: .regularExpression)
    }
  }

  private func bind(_ values: [String], _ query: OpaquePointer?) {
    for (index, value) in values.enumerated() {
      sqlite3_bind_text(query, Int32(index + 1), value, -1, transient)
    }
  }

  private func statement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
    try database { db in
      var query: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK else {
        throw RepositoryError.writeFailed
      }
      defer { sqlite3_finalize(query) }
      return try body(query)
    }
  }

  private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw RepositoryError.openFailed }
    defer { sqlite3_close(db) }
    return try body(db)
  }
}
