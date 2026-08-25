import AegisWorkerProtocol
import Foundation

struct WorkerHealth: Encodable {
  let status = "ok"
  let service = "AegisWorker"
  let protocolVersion = WorkerJobContract.schemaVersion
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 1, arguments.first == "--health" else {
  FileHandle.standardError.write(Data("AegisWorker accepts only --health until queue handoff is enabled.\n".utf8))
  exit(2)
}
let data = try JSONEncoder().encode(WorkerHealth())
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
