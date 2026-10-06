import Foundation

/// Local-only JSON log of recent request timings; never synced or sent to a model.
struct RequestTimingStore {
  static let limit = 500
  let url: URL

  static let standard = RequestTimingStore(url: FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "Aegis/request-timings.json"))

  func recent(limit: Int = RequestTimingStore.limit) -> [RequestTimingRecord] {
    guard let data = try? Data(contentsOf: url),
      let values = try? decoder.decode([RequestTimingRecord].self, from: data) else { return [] }
    return Array(values.suffix(limit))
  }

  func append(_ record: RequestTimingRecord) {
    let values = Array((recent() + [record]).suffix(Self.limit))
    guard let data = try? encoder.encode(values) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  private var encoder: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
  private var decoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
