import Foundation
import SQLite3

public final class WorkerAuthorizationStore {
  private let url: URL
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  public init(databaseURL: URL) throws {
    url = databaseURL
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try database { db in
      let sql = """
      CREATE TABLE IF NOT EXISTS worker_authorizations(
        command_id TEXT NOT NULL,session_id TEXT NOT NULL,authorization_json TEXT NOT NULL,
        consumed_at REAL,PRIMARY KEY(command_id,session_id));
      """
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.write }
    }
  }

  public func issue(_ authorization: WorkerWriteAuthorization) throws {
    let data = try JSONEncoder().encode(authorization)
    guard let json = String(data: data, encoding: .utf8) else { throw StoreError.write }
    try statement("""
      INSERT INTO worker_authorizations(command_id,session_id,authorization_json,consumed_at)
      VALUES(?,?,?,NULL) ON CONFLICT(command_id,session_id) DO UPDATE SET
      authorization_json=excluded.authorization_json,consumed_at=NULL;
      """) { query in
      bind([authorization.commandId, authorization.sessionId, json], query)
      guard sqlite3_step(query) == SQLITE_DONE else { throw StoreError.write }
    }
  }

  public func consume(commandId: String, sessionId: String, request: String,
                      projectRoot: String, now: Date = .now) throws -> WorkerWriteAuthorization? {
    try database { db in
      guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw StoreError.write }
      defer { sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) }
      var query: OpaquePointer?
      guard sqlite3_prepare_v2(db, "SELECT authorization_json FROM worker_authorizations WHERE command_id=? AND session_id=? AND consumed_at IS NULL;", -1, &query, nil) == SQLITE_OK else { throw StoreError.write }
      defer { sqlite3_finalize(query) }; bind([commandId, sessionId], query)
      guard sqlite3_step(query) == SQLITE_ROW,
        let raw = sqlite3_column_text(query, 0).map({ String(cString: $0) }),
        let data = raw.data(using: .utf8),
        let value = try? JSONDecoder().decode(WorkerWriteAuthorization.self, from: data),
        value.authorizes(commandId: commandId, sessionId: sessionId, request: request,
          projectRoot: projectRoot, now: now) else { return nil }
      var update: OpaquePointer?
      guard sqlite3_prepare_v2(db, "UPDATE worker_authorizations SET consumed_at=? WHERE command_id=? AND session_id=? AND consumed_at IS NULL;", -1, &update, nil) == SQLITE_OK else { throw StoreError.write }
      defer { sqlite3_finalize(update) }; sqlite3_bind_double(update, 1, now.timeIntervalSince1970)
      bind([commandId, sessionId], update, offset: 1)
      guard sqlite3_step(update) == SQLITE_DONE, sqlite3_changes(db) == 1,
        sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else { throw StoreError.write }
      return value
    }
  }

  private func bind(_ values: [String], _ query: OpaquePointer?, offset: Int = 0) { for (index,value) in values.enumerated() { sqlite3_bind_text(query,Int32(index+offset+1),value,-1,transient) } }
  private func statement<T>(_ sql: String,_ body:(OpaquePointer?) throws->T)throws->T{try database{db in var query:OpaquePointer?;guard sqlite3_prepare_v2(db,sql,-1,&query,nil)==SQLITE_OK else{throw StoreError.write};defer{sqlite3_finalize(query)};return try body(query)}}
  private func database<T>(_ body:(OpaquePointer)throws->T)throws->T{var db:OpaquePointer?;guard sqlite3_open(url.path,&db)==SQLITE_OK,let db else{throw StoreError.open};defer{sqlite3_close(db)};return try body(db)}
  private enum StoreError: Error { case open, write }
}
