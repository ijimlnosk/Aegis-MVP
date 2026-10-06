import Foundation

enum SpeakerVerifier {
  private static let workspace = "/Users/kimjinsol/Aegis-MVP"
  private static var service: Process?

  static func start() {
    guard service == nil else { return }
    let root = URL(fileURLWithPath: workspace)
    let process = Process()
    process.executableURL = root.appending(path: ".aegis/f5-tts/bin/python")
    process.arguments = [root.appending(path: "scripts/speaker_server.py").path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      service = process
    } catch { }
  }

  static func score(for recording: URL?) async -> Double? {
    guard let recording else { return nil }
    start()
    for _ in 0..<60 {
      if let score = await requestScore(for: recording) { return score }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return nil
  }

  private static func requestScore(for recording: URL) async -> Double? {
    guard let url = URL(string: "http://127.0.0.1:4319/verify") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 2
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["audio": recording.path])
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      return (try JSONSerialization.jsonObject(with: data) as? [String: Double])?["score"]
    } catch { return nil }
  }
}
