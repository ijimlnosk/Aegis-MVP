import Foundation

/// Projects whose typecheck/lint/test/build scripts may run without approval.
/// Those scripts are the project's own package.json code, so any project not listed
/// here needs approval each time. Read once at launch; edit .env.local and restart.
enum AutoValidationProjects {
  static let environmentKey = "AEGIS_AUTO_VALIDATION_PROJECTS"
  static let current = names(from: RemoteEnvironment.load())

  static func names(from environment: [String: String]) -> Set<String> {
    Set((environment[environmentKey] ?? "").split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces).lowercased()
    }.filter { !$0.isEmpty })
  }

  /// Matches the planned project name exactly (case-insensitive); an unlisted alias needs approval.
  static func allows(_ project: String?, in names: Set<String>) -> Bool {
    guard let project = project?.trimmingCharacters(in: .whitespaces).lowercased(),
      !project.isEmpty else { return false }
    return names.contains(project)
  }
}
