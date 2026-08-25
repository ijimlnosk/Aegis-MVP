import Foundation
import SQLite3

public final class WorkerLeaseStore {
  private let url: URL
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  public init(databaseURL: URL) throws {
    url = databaseURL
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try database { db in
      let sql = """
      CREATE TABLE IF NOT EXISTS worker_jobs(
        command_id TEXT NOT NULL, session_id TEXT NOT NULL, contract_json TEXT NOT NULL,
        lease_owner TEXT, lease_expires REAL, updated_at REAL NOT NULL,
        PRIMARY KEY(command_id,session_id));
      """
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.write }
    }
  }

  public func upsert(_ contract: WorkerJobContract) throws {
    let data = try JSONEncoder().encode(contract)
    guard let json = String(data: data, encoding: .utf8) else { throw StoreError.write }
    try statement("""
      INSERT INTO worker_jobs(command_id,session_id,contract_json,updated_at) VALUES(?,?,?,?)
      ON CONFLICT(command_id,session_id) DO UPDATE SET
      contract_json=excluded.contract_json,updated_at=excluded.updated_at;
      """) { query in
      bind([contract.commandId, contract.sessionId, json], query)
      sqlite3_bind_double(query, 4, Date().timeIntervalSince1970)
      guard sqlite3_step(query) == SQLITE_DONE else { throw StoreError.write }
    }
  }

  public func claim(commandId: String, sessionId: String, owner: String,
                    now: Date = .now, duration: TimeInterval = 30) throws -> Bool {
    try statement("""
      UPDATE worker_jobs SET lease_owner=?,lease_expires=?,updated_at=?
      WHERE command_id=? AND session_id=? AND (lease_expires IS NULL OR lease_expires<=?);
      """) { query in
      sqlite3_bind_text(query, 1, owner, -1, transient)
      sqlite3_bind_double(query, 2, now.addingTimeInterval(duration).timeIntervalSince1970)
      sqlite3_bind_double(query, 3, now.timeIntervalSince1970)
      bind([commandId, sessionId], query, offset: 3)
      sqlite3_bind_double(query, 6, now.timeIntervalSince1970)
      guard sqlite3_step(query) == SQLITE_DONE else { throw StoreError.write }
      return sqlite3_changes(sqlite3_db_handle(query)) == 1
    }
  }

  public func heartbeat(commandId: String, sessionId: String, owner: String,
                        now: Date = .now, duration: TimeInterval = 30) throws -> Bool {
    try statement("""
      UPDATE worker_jobs SET lease_expires=?,updated_at=?
      WHERE command_id=? AND session_id=? AND lease_owner=? AND lease_expires>?;
      """) { query in
      sqlite3_bind_double(query, 1, now.addingTimeInterval(duration).timeIntervalSince1970)
      sqlite3_bind_double(query, 2, now.timeIntervalSince1970)
      bind([commandId, sessionId, owner], query, offset: 2)
      sqlite3_bind_double(query, 6, now.timeIntervalSince1970)
      guard sqlite3_step(query) == SQLITE_DONE else { throw StoreError.write }
      return sqlite3_changes(sqlite3_db_handle(query)) == 1
    }
  }

  private func bind(_ values: [String], _ query: OpaquePointer?, offset: Int = 0) {
    for (index, value) in values.enumerated() {
      sqlite3_bind_text(query, Int32(index + offset + 1), value, -1, transient)
    }
  }
  private func statement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
    try database { db in var query: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK else { throw StoreError.write }; defer { sqlite3_finalize(query) }; return try body(query) }
  }
  private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    var db: OpaquePointer?; guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw StoreError.open }; defer { sqlite3_close(db) }; return try body(db)
  }
  private enum StoreError: Error { case open, write }
}
