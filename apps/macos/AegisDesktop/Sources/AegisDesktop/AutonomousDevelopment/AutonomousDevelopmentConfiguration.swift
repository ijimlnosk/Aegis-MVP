import Foundation

struct AutonomousDevelopmentConfiguration: Equatable, Sendable {
  let maximumChangedFiles: Int
  let maximumTasks: Int
  let repairAttempts: Int

  static func load(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
    let files = Int(environment["AEGIS_AUTONOMOUS_MAX_CHANGED_FILES"] ?? "") ?? 5
    let tasks = Int(environment["AEGIS_AUTONOMOUS_MAX_TASKS_PER_REQUEST"] ?? "") ?? 1
    let repairs = Int(environment["AEGIS_AUTONOMOUS_REPAIR_ATTEMPTS"] ?? "") ?? 1
    return .init(maximumChangedFiles: min(max(files, 1), 20),
      maximumTasks: min(max(tasks, 1), 1), repairAttempts: min(max(repairs, 0), 1))
  }
}
