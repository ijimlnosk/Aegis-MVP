import AegisWorkerProtocol
import Foundation

struct WorkerHealth: Encodable {
  let status = "ok"
  let service = "AegisWorker"
  let protocolVersion = WorkerJobContract.schemaVersion
}

struct WorkerLeaseResponse: Encodable { let acquired: Bool }

let arguments = Array(CommandLine.arguments.dropFirst())
let response: any Encodable
switch arguments.first {
case "--health" where arguments.count == 1:
  response = WorkerHealth()
case "--claim" where arguments.count == 5:
  let store = try WorkerLeaseStore(databaseURL: URL(fileURLWithPath: arguments[1]))
  response = WorkerLeaseResponse(acquired: try store.claim(commandId: arguments[2],
    sessionId: arguments[3], owner: arguments[4]))
case "--heartbeat" where arguments.count == 5:
  let store = try WorkerLeaseStore(databaseURL: URL(fileURLWithPath: arguments[1]))
  response = WorkerLeaseResponse(acquired: try store.heartbeat(commandId: arguments[2],
    sessionId: arguments[3], owner: arguments[4]))
case "--execute-read-only" where arguments.count == 3:
  try WorkerReadOnlyExecutor.run(requestURL: URL(fileURLWithPath: arguments[1]),
    resultURL: URL(fileURLWithPath: arguments[2]))
  response = WorkerLeaseResponse(acquired: true)
case "--execute-write" where arguments.count == 3:
  try WorkerWriteExecutor.run(requestURL: URL(fileURLWithPath: arguments[1]),
    resultURL: URL(fileURLWithPath: arguments[2]))
  response = WorkerLeaseResponse(acquired: true)
default:
  FileHandle.standardError.write(Data("Unsupported AegisWorker command.\n".utf8))
  exit(2)
}
let data = try JSONEncoder().encode(AnyEncodable(response))
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))

private struct AnyEncodable: Encodable {
  let value: any Encodable
  init(_ value: any Encodable) { self.value = value }
  func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
