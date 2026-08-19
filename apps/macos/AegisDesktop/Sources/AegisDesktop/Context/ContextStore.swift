import Foundation
import SQLite3

final class ContextStore {
  private let url: URL
  private let retention: Int
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  init(databaseURL: URL = MemoryRepository.defaultDatabaseURL, retention: Int = 20) {
    url = databaseURL; self.retention = max(2, retention); try? bootstrap()
  }

  func save(_ snapshot: ContextSnapshot) throws {
    let data = try JSONEncoder().encode(snapshot)
    guard let json = String(data: data, encoding: .utf8) else { throw ContextStoreError.encoding }
    try statement("INSERT INTO context_snapshots(id,captured_at,snapshot_json) VALUES(?,?,?)") { stmt in
      bind([snapshot.id.uuidString, ISO8601DateFormatter().string(from: snapshot.capturedAt), json], stmt)
      guard sqlite3_step(stmt) == SQLITE_DONE else { throw ContextStoreError.write }
    }
    try database { db in
      let sql = "DELETE FROM context_snapshots WHERE id NOT IN (SELECT id FROM context_snapshots ORDER BY captured_at DESC LIMIT \(retention))"
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ContextStoreError.write }
    }
  }

  func snapshots(limit: Int = 2) throws -> [ContextSnapshot] {
    try statement("SELECT snapshot_json FROM context_snapshots ORDER BY captured_at DESC LIMIT \(max(1, limit))") { stmt in
      var result: [ContextSnapshot] = []
      while sqlite3_step(stmt) == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0),
        let value = try? JSONDecoder().decode(ContextSnapshot.self, from: Data(String(cString: raw).utf8)) {
        result.append(value)
      }
      return result
    }
  }

  private func bootstrap() throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try database { db in
      let sql = "CREATE TABLE IF NOT EXISTS context_snapshots(id TEXT PRIMARY KEY,captured_at TEXT NOT NULL,snapshot_json TEXT NOT NULL); CREATE INDEX IF NOT EXISTS context_time ON context_snapshots(captured_at DESC);"
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ContextStoreError.write }
    }
  }
  private func bind(_ values: [String], _ stmt: OpaquePointer?) { for (i, value) in values.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), value, -1, transient) } }
  private func statement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T { try database { db in var stmt: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw ContextStoreError.write }; defer { sqlite3_finalize(stmt) }; return try body(stmt) } }
  private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T { var db: OpaquePointer?; guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw ContextStoreError.open }; defer { sqlite3_close(db) }; return try body(db) }
}

enum ContextStoreError: Error { case open, write, encoding }
