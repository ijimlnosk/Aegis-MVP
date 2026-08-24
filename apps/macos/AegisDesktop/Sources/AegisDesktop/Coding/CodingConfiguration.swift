import Foundation

struct CodingConfiguration: Equatable {
  let timeout: TimeInterval
  let maximumChangedFiles: Int

  static func load(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
    let seconds = Double(environment["AEGIS_CODING_TASK_TIMEOUT_SECONDS"] ?? "") ?? 900
    let files = Int(environment["AEGIS_CODING_MAX_CHANGED_FILES"] ?? "") ?? 20
    return Self(timeout: min(max(seconds, 30), 3_600),
      maximumChangedFiles: min(max(files, 1), 100))
  }
}
