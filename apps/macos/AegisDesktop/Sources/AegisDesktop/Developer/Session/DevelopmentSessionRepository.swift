import Foundation
import SQLite3

final class DevelopmentSessionRepository {
  let databaseURL: URL
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  init(databaseURL: URL = MemoryRepository.defaultDatabaseURL) { self.databaseURL = databaseURL }

  func bootstrap() throws { try database { db in
    let sql = "CREATE TABLE IF NOT EXISTS development_sessions (id TEXT PRIMARY KEY, project TEXT NOT NULL, started_at REAL NOT NULL, ended_at REAL, payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS sessions_project_started ON development_sessions(project, started_at DESC);"
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw RepositoryError.writeFailed }
  } }

  func save(_ session: DevelopmentSession) throws {
    let data = try JSONEncoder().encode(session)
    try statement("INSERT OR REPLACE INTO development_sessions(id,project,started_at,ended_at,payload) VALUES(?,?,?,?,?);") { query in
      sqlite3_bind_text(query, 1, session.id.uuidString, -1, transient)
      sqlite3_bind_text(query, 2, session.project, -1, transient)
      sqlite3_bind_double(query, 3, session.startedAt.timeIntervalSince1970)
      if let ended = session.endedAt { sqlite3_bind_double(query, 4, ended.timeIntervalSince1970) }
      else { sqlite3_bind_null(query, 4) }
      _ = data.withUnsafeBytes { sqlite3_bind_blob(query, 5, $0.baseAddress, Int32(data.count), transient) }
      guard sqlite3_step(query) == SQLITE_DONE else { throw RepositoryError.writeFailed }
    }
  }

  func sessions(project: String? = nil, since: Date? = nil) throws -> [DevelopmentSession] {
    try statement("SELECT payload FROM development_sessions ORDER BY started_at DESC;") { query in
      var result: [DevelopmentSession] = []
      while sqlite3_step(query) == SQLITE_ROW, let bytes = sqlite3_column_blob(query, 0) {
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))
        if let value = try? JSONDecoder().decode(DevelopmentSession.self, from: data),
          project.map({ value.project.caseInsensitiveCompare($0) == .orderedSame }) ?? true,
          since.map({ value.startedAt >= $0 }) ?? true { result.append(value) }
      }
      return result
    }
  }

  private func statement<T>(_ sql: String, body: (OpaquePointer?) throws -> T) throws -> T { try database { db in
    var query: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK else { throw RepositoryError.writeFailed }
    defer { sqlite3_finalize(query) }; return try body(query)
  } }
  private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var db: OpaquePointer?; guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else { throw RepositoryError.openFailed }
    defer { sqlite3_close(db) }; return try body(db)
  }
}
