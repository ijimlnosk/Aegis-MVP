import Foundation
import SQLite3

final class MemoryRepository {
  private let databaseURL: URL
  private let dateFormatter = ISO8601DateFormatter()
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  init(databaseURL: URL = MemoryRepository.defaultDatabaseURL) {
    self.databaseURL = databaseURL
  }
  func bootstrap() throws {
    try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try withDatabase { database in
      let sql = """
      CREATE TABLE IF NOT EXISTS memories (
        id TEXT PRIMARY KEY, type TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL,
        source TEXT NOT NULL, confidence REAL NOT NULL, created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL, UNIQUE(type, key)
      );
      CREATE INDEX IF NOT EXISTS memories_type_updated ON memories(type, updated_at DESC);
      """
      guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw error(database) }
    }
  }
  @discardableResult
  func save(_ record: MemoryRecord) throws -> MemoryRecord {
    let existing = try find(type: record.type, key: record.key)
    let saved = MemoryRecord(id: existing?.id ?? record.id, type: record.type, key: normalized(record.key),
      value: record.value, source: record.source, confidence: record.confidence,
      createdAt: existing?.createdAt ?? record.createdAt, updatedAt: .now)
    try withStatement("""
      INSERT INTO memories(id,type,key,value,source,confidence,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)
      ON CONFLICT(type,key) DO UPDATE SET value=excluded.value,source=excluded.source,
      confidence=excluded.confidence,updated_at=excluded.updated_at;
      """) { statement in
      bind([saved.id.uuidString, saved.type.rawValue, saved.key, saved.value, saved.source,
            String(saved.confidence), dateFormatter.string(from: saved.createdAt),
            dateFormatter.string(from: saved.updatedAt)], to: statement)
      guard sqlite3_step(statement) == SQLITE_DONE else { throw RepositoryError.writeFailed }
    }
    return saved
  }
  func records(type: MemoryType? = nil) throws -> [MemoryRecord] {
    let sql = "SELECT id,type,key,value,source,confidence,created_at,updated_at FROM memories"
      + (type == nil ? "" : " WHERE type=?") + " ORDER BY updated_at DESC;"
    return try withStatement(sql) { statement in
      if let type { sqlite3_bind_text(statement, 1, type.rawValue, -1, transient) }
      var values: [MemoryRecord] = []
      while sqlite3_step(statement) == SQLITE_ROW { if let value = decode(statement) { values.append(value) } }
      return values
    }
  }
  func find(type: MemoryType, key: String) throws -> MemoryRecord? {
    try records(type: type).first { $0.key == normalized(key) }
  }

  @discardableResult
  func forget(type: MemoryType, key: String) throws -> Bool {
    try withStatement("DELETE FROM memories WHERE type=? AND key=?;") { statement in
      bind([type.rawValue, normalized(key)], to: statement)
      guard sqlite3_step(statement) == SQLITE_DONE else { throw RepositoryError.writeFailed }
      return sqlite3_changes(sqlite3_db_handle(statement)) > 0
    }
  }

  private func decode(_ statement: OpaquePointer?) -> MemoryRecord? {
    func text(_ index: Int32) -> String { sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
    guard let id = UUID(uuidString: text(0)), let type = MemoryType(rawValue: text(1)),
          let created = dateFormatter.date(from: text(6)), let updated = dateFormatter.date(from: text(7)) else { return nil }
    return MemoryRecord(id: id, type: type, key: text(2), value: text(3), source: text(4),
      confidence: sqlite3_column_double(statement, 5), createdAt: created, updatedAt: updated)
  }

  private func bind(_ values: [String], to statement: OpaquePointer?) {
    for (index, value) in values.enumerated() { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
  }

  private func withStatement<T>(_ sql: String, body: (OpaquePointer?) throws -> T) throws -> T {
    try withDatabase { database in
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw error(database) }
      defer { sqlite3_finalize(statement) }
      return try body(statement)
    }
  }

  private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else { throw RepositoryError.openFailed }
    defer { sqlite3_close(database) }
    return try body(database)
  }

  private func error(_ database: OpaquePointer) -> Error { RepositoryError.sqlite(String(cString: sqlite3_errmsg(database))) }
  private func normalized(_ key: String) -> String { key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
  static var defaultDatabaseURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Aegis/memory.sqlite") }
}

enum RepositoryError: Error { case openFailed, writeFailed, sqlite(String) }
