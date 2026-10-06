import Foundation

enum WakeWordVerifier {
  static func score(for recording: URL?) async -> Double? {
    guard let recording, let url = URL(string: "http://127.0.0.1:4319/wake") else { return nil }
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
