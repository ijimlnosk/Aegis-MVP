import Foundation
import AppKit
import SQLite3

enum LearningStore {
  private static let databaseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "Aegis/learning.sqlite")

  static func bootstrap() {
    try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    execute("CREATE TABLE IF NOT EXISTS wake_samples (path TEXT PRIMARY KEY, label TEXT NOT NULL, source TEXT NOT NULL, created_at TEXT NOT NULL);")
    execute("CREATE TABLE IF NOT EXISTS agent_traces (id INTEGER PRIMARY KEY, request TEXT, action TEXT, result TEXT, created_at TEXT);")
    execute("CREATE TABLE IF NOT EXISTS application_aliases (alias TEXT PRIMARY KEY, bundle_id TEXT NOT NULL, display_name TEXT NOT NULL, learned_at TEXT NOT NULL);")
    execute("CREATE TABLE IF NOT EXISTS wake_checks (id INTEGER PRIMARY KEY, score REAL, detected INTEGER, created_at TEXT);")
    let root = "/Users/kimjinsol/Aegis-MVP/src/assets/voices/"
    register(path: root + "aegis.mp3", label: "wake", source: "owner")
    register(path: root + "my-voice.mp3", label: "non_wake", source: "owner")
    register(path: root + "voice.mp3", label: "non_wake", source: "reference")
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.kakao.KakaoTalkMac") {
      rememberApplication(alias: "카카오톡", bundleID: "com.kakao.KakaoTalkMac", displayName: url.deletingPathExtension().lastPathComponent)
    }
  }

  static func record(request: String, action: String, result: String) {
    execute("INSERT INTO agent_traces (request, action, result, created_at) VALUES ('\(escaped(request))', '\(escaped(action))', '\(escaped(result))', '\(Date.now.ISO8601Format())');")
  }

  static func addWakeSample(path: String, label: String) {
    register(path: path, label: label, source: "recorded")
  }

  static func recordWakeCheck(score: Double?, detected: Bool) {
    let value = score.map { String($0) } ?? "NULL"
    execute("INSERT INTO wake_checks (score, detected, created_at) VALUES (\(value), \(detected ? 1 : 0), '\(Date.now.ISO8601Format())');")
  }

  static func rememberApplication(alias: String, bundleID: String, displayName: String) {
    execute("INSERT OR REPLACE INTO application_aliases (alias, bundle_id, display_name, learned_at) VALUES ('\(escaped(normalized(alias)))', '\(escaped(bundleID))', '\(escaped(displayName))', '\(Date.now.ISO8601Format())');")
  }

  static func applicationBundleID(for alias: String) -> String? {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else { return nil }
    defer { sqlite3_close(database) }
    let query = "SELECT bundle_id FROM application_aliases WHERE alias = '\(escaped(normalized(alias)))' LIMIT 1;"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
    return String(cString: value)
  }

  private static func register(path: String, label: String, source: String) {
    execute("INSERT OR IGNORE INTO wake_samples (path, label, source, created_at) VALUES ('\(escaped(path))', '\(escaped(label))', '\(escaped(source))', '\(Date.now.ISO8601Format())');")
  }

  private static func execute(_ statement: String) {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else { return }
    defer { sqlite3_close(database) }
    sqlite3_exec(database, statement, nil, nil, nil)
  }

  private static func escaped(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "''")
  }

  private static func normalized(_ value: String) -> String {
    value.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
  }
}
