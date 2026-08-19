import Foundation

enum ScreenAnalysisDiagnostics {
  static var enabled: Bool { ProcessInfo.processInfo.environment["AEGIS_SCREEN_DEBUG"] == "1" }

  static func response(_ data: Data, _ response: HTTPURLResponse) {
    guard enabled else { return }
    let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let message = root?["message"] as? [String: Any]
    let text = root?["response"] as? String ?? message?["content"] as? String ?? ""
    print("[ScreenAnalysis] status=\(response.statusCode) contentType=\(response.value(forHTTPHeaderField: "Content-Type") ?? "nil") bytes=\(data.count)")
    print("[ScreenAnalysis] keys=\((root?.keys.sorted() ?? []).joined(separator: ",")) response=\(root?["response"] is String) message.content=\(message?["content"] is String)")
    print("[ScreenAnalysis] modelText=\(sanitize(text, limit: 500))")
  }

  static func decoderFailure(_ error: Error) {
    guard enabled else { return }
    print("[ScreenAnalysis] JSONDecoder error: \(error)")
  }

  static func timing(_ name: String, since start: ContinuousClock.Instant,
                     dimensions: (Int, Int)? = nil) {
    guard enabled else { return }
    let duration = start.duration(to: .now)
    let size = dimensions.map { " dimensions=\($0.0)x\($0.1)" } ?? ""
    print("[ScreenAnalysis] \(name)=\(duration)\(size)")
  }

  private static func sanitize(_ value: String, limit: Int) -> String {
    let scalars = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }
    return String(String.UnicodeScalarView(scalars).prefix(limit))
  }
}
