import Foundation

enum DockerInventoryParser {
  static func parse(_ output: String) -> [DockerContext] {
    output.split(separator: "\n").compactMap { line in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard fields.count >= 2, isSafeName(fields[0]) else { return nil }
      let state = fields[1], lowered = state.lowercased()
      return DockerContext(name: fields[0], state: state,
        isRunning: lowered.hasPrefix("up") || lowered.contains("running"))
    }
  }

  static func isSafeName(_ value: String) -> Bool {
    value.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$", options: .regularExpression) != nil
  }
}
