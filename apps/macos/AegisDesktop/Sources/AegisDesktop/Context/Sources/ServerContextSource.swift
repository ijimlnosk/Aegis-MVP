import Foundation

struct ServerContextSource: ContextSource {
  let kind = ContextSourceKind.server

  func collect() async throws -> ContextSourceResult {
    do {
      let status = try await ServerAgentClient.call(.status)
      let containers = (try? await ServerAgentClient.call(.containers)) ?? ""
      return .server(ServerContext(available: true, uptime: section("Uptime:", in: status),
        memoryPercent: memoryPercent(status), diskPercent: percent(after: "Disk:", in: status),
        containers: DockerInventoryParser.parse(containers), error: nil))
    } catch {
      return .server(ServerContext(available: false, uptime: nil, memoryPercent: nil,
        diskPercent: nil, containers: [], error: error.localizedDescription))
    }
  }

  private func section(_ marker: String, in text: String) -> String? {
    guard let range = text.range(of: marker) else { return nil }
    return text[range.upperBound...].split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
  }

  private func percent(after marker: String, in text: String) -> Double? {
    guard let range = text.range(of: marker),
      let match = text[range.upperBound...].range(of: #"\d+(?:\.\d+)?%"#, options: .regularExpression) else { return nil }
    return Double(text[match].dropLast())
  }

  private func memoryPercent(_ text: String) -> Double? {
    guard let range = text.range(of: "Memory:") else { return nil }
    let lines = text[range.upperBound...].split(separator: "\n")
    guard let line = lines.first(where: { $0.lowercased().contains("mem:") }) else { return percent(after: "Memory:", in: text) }
    let values = line.split(whereSeparator: { $0.isWhitespace }).dropFirst().compactMap(parseSize)
    guard values.count >= 2, values[0] > 0 else { return nil }
    return values[1] / values[0] * 100
  }

  private func parseSize(_ value: Substring) -> Double? {
    let text = value.lowercased(), number = Double(text.filter { $0.isNumber || $0 == "." })
    guard let number else { return nil }
    if text.contains("ti") { return number * 1024 }
    if text.contains("gi") { return number }
    if text.contains("mi") { return number / 1024 }
    return number
  }

}
