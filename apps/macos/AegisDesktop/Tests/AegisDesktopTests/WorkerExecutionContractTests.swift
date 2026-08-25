import AegisWorkerProtocol
import Foundation
import Testing

@Test func workerExecutionContractAllowsOnlyFixedReadOnlyCodex() throws {
  let root = FileManager.default.temporaryDirectory
  let safe = WorkerExecutionRequest(executable: "/opt/homebrew/bin/codex", projectRoot: root.path,
    arguments: ["exec", "--sandbox", "read-only", "inspect"], timeout: 60)
  let write = WorkerExecutionRequest(executable: "/opt/homebrew/bin/codex", projectRoot: root.path,
    arguments: ["exec", "--sandbox", "workspace-write", "edit"], timeout: 60)
  let shell = WorkerExecutionRequest(executable: "/bin/zsh", projectRoot: root.path,
    arguments: ["-c", "anything"], timeout: 60)
  #expect(safe.isSafeReadOnlyCodex)
  #expect(!write.isSafeReadOnlyCodex)
  #expect(!shell.isSafeReadOnlyCodex)
}
