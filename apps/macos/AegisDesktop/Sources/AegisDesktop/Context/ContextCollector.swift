import Foundation

enum ContextCollector {
  static func collect(_ sources: [AnyContextSource], at date: Date = .now) async -> ContextSnapshot {
    var snapshot = ContextSnapshot(capturedAt: date)
    for source in sources {
      do {
        switch try await source.collect() {
        case .mac(let value): snapshot.mac = value
        case .projects(let value): snapshot.projects = value
        case .server(let value): snapshot.server = value
        }
      } catch {
        if source.kind == .server {
          snapshot.server = ServerContext(available: false, uptime: nil, memoryPercent: nil,
            diskPercent: nil, containers: [], error: error.localizedDescription)
        }
      }
    }
    return snapshot
  }
}
