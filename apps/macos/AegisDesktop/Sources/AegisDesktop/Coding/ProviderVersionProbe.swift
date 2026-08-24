import Foundation

enum ProviderVersionProbe {
  static func read(executable: URL) -> String? {
    guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
    let process = Process(), output = Pipe()
    process.executableURL = executable; process.arguments = ["--version"]
    process.standardOutput = output; process.standardError = output
    do { try process.run(); process.waitUntilExit() } catch { return nil }
    guard process.terminationStatus == 0 else { return nil }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines).prefix(120).description
  }
}
