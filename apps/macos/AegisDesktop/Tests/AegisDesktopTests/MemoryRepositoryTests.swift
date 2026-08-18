import Foundation
import Testing
@testable import AegisDesktop

@Test func savesAndUpdatesPreference() throws {
  let repository = try repository()
  try repository.save(MemoryRecord(type: .preference, key: "default_browser", value: "Chrome"))
  try repository.save(MemoryRecord(type: .preference, key: "default_browser", value: "Firefox"))
  let records = try repository.records(type: .preference)
  #expect(records.count == 1)
  #expect(records.first?.value == "Firefox")
}

@Test func forgetsMemory() throws {
  let repository = try repository()
  try repository.save(MemoryRecord(type: .alias, key: "솔 서버", value: "sol-server"))
  #expect(try repository.forget(type: .alias, key: "솔 서버"))
  #expect(try repository.find(type: .alias, key: "솔 서버") == nil)
}

@Test func persistsAcrossRepositoryReinitialization() throws {
  let url = temporaryDatabaseURL()
  let first = MemoryRepository(databaseURL: url)
  try first.bootstrap()
  try first.save(MemoryRecord(type: .fact, key: "owner", value: "Jinsol"))
  let second = MemoryRepository(databaseURL: url)
  try second.bootstrap()
  #expect(try second.find(type: .fact, key: "owner")?.value == "Jinsol")
}

@Test func persistsActionHistory() throws {
  let repository = try repository()
  let store = MemoryStore(repository: repository)
  store.recordAction(request: "상태 확인", action: "status", target: "sol-server",
    result: "정상", succeeded: true)
  let records = try repository.records(type: .actionHistory)
  let value = try JSONDecoder().decode(ActionHistoryValue.self, from: Data(records[0].value.utf8))
  #expect(value.target == "sol-server")
  #expect(value.succeeded)
}

private func repository() throws -> MemoryRepository {
  let repository = MemoryRepository(databaseURL: temporaryDatabaseURL())
  try repository.bootstrap()
  return repository
}

private func temporaryDatabaseURL() -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "aegis-memory-tests-\(UUID().uuidString)/memory.sqlite")
}
