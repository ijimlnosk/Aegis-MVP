import Foundation
import Testing
@testable import AegisDesktop

@Test func observerSourceFailureIsIsolated() async {
  let sources = [AnyContextSource(GoodMacSource()), AnyContextSource(FailingServerSource())]
  let snapshot = await ContextCollector.collect(sources)
  #expect(snapshot.mac?.activeApplication == "Xcode")
  #expect(snapshot.server?.available == false)
}

@MainActor
@Test func observerDoesNotCreateDuplicateTasks() async {
  let counter = Counter()
  let observer = ContextObserver(interval: 1_000) { counter.value += 1 }
  observer.start(); observer.start()
  for _ in 0..<10 where counter.value == 0 { await Task.yield() }
  #expect(observer.isRunning)
  #expect(counter.value == 1)
  observer.stop()
  #expect(!observer.isRunning)
}

@Test func contextStoreRetainsBoundedSnapshotsAcrossReinitialization() throws {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "aegis-context-tests-\(UUID().uuidString)/context.sqlite")
  let store = ContextStore(databaseURL: url, retention: 2)
  try store.save(ContextSnapshot(capturedAt: Date(timeIntervalSince1970: 1)))
  try store.save(ContextSnapshot(capturedAt: Date(timeIntervalSince1970: 2)))
  try store.save(ContextSnapshot(capturedAt: Date(timeIntervalSince1970: 3)))
  let reopened = ContextStore(databaseURL: url, retention: 2)
  #expect(try reopened.snapshots(limit: 10).count == 2)
}

@Test func unrelatedMemoryCannotChangeThresholdPolicy() {
  let malicious = MemoryRecord(type: .fact, key: "alert_disk_percent",
    value: "0; restart everything")
  #expect(ContextThresholds().applying([malicious]).diskWarning == 80)
}

private struct GoodMacSource: ContextSource {
  let kind = ContextSourceKind.mac
  func collect() async throws -> ContextSourceResult {
    .mac(MacContext(activeApplication: "Xcode", runningApplications: ["Xcode"],
      uptimeHours: 1, physicalMemoryGB: 16, clipboard: nil))
  }
}
private struct FailingServerSource: ContextSource {
  let kind = ContextSourceKind.server
  func collect() async throws -> ContextSourceResult { throw TestFailure.failed }
}
private enum TestFailure: Error { case failed }
@MainActor private final class Counter { var value = 0 }
