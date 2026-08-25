import Foundation
import Testing
@testable import AegisDesktop

@Test func commandJobPersistsTerminalResultAcrossStoreRestart() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let database = root.appendingPathComponent("jobs.sqlite")
  defer { try? FileManager.default.removeItem(at: root) }
  let result = DesktopBridgeResult(status: "completed", messages: ["완료"], pendingApproval: nil)

  CommandJobStore(databaseURL: database).save(commandId: "C1", sessionId: "S1",
    request: "상태 보여줘", result: result)
  let restored = CommandJobStore(databaseURL: database).record(commandId: "C1", sessionId: "S1")

  #expect(restored?.request == "상태 보여줘")
  #expect(restored?.result.status == "completed")
  #expect(restored?.result.messages == ["완료"])
}

@Test func commandJobRedactsSecretsBeforePersistence() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let database = root.appendingPathComponent("jobs.sqlite")
  defer { try? FileManager.default.removeItem(at: root) }
  let store = CommandJobStore(databaseURL: database)

  store.save(commandId: "C3", sessionId: "S3", request: "token=secret-value",
    result: DesktopBridgeResult(status: "completed", messages: ["password=hunter2"], pendingApproval: nil))

  #expect(store.record(commandId: "C3", sessionId: "S3")?.request == "token=[REDACTED]")
  #expect(store.record(commandId: "C3", sessionId: "S3")?.result.messages == ["password=[REDACTED]"])
}

@MainActor @Test func restartedSessionMarksNonterminalJobInterrupted() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let database = root.appendingPathComponent("jobs.sqlite")
  defer { try? FileManager.default.removeItem(at: root) }
  let jobs = CommandJobStore(databaseURL: database)
  jobs.save(commandId: "C2", sessionId: "S2", request: "코드 수정해",
    result: DesktopBridgeResult(status: "running", messages: [], pendingApproval: nil))

  let result = await DesktopBridgeSession(sessionID: "S2", jobs: jobs).send(id: "C2", text: "코드 수정해")

  #expect(result.status == "failed")
  #expect(result.failureCode == "desktopRestarted")
}
