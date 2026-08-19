protocol ContextSource {
  var kind: ContextSourceKind { get }
  func collect() async throws -> ContextSourceResult
}

enum ContextSourceKind: String, Codable { case mac, projects, server }

enum ContextSourceResult {
  case mac(MacContext)
  case projects([ProjectContext])
  case server(ServerContext)
}

struct AnyContextSource: ContextSource {
  let kind: ContextSourceKind
  private let operation: () async throws -> ContextSourceResult
  init<S: ContextSource>(_ source: S) { kind = source.kind; operation = source.collect }
  func collect() async throws -> ContextSourceResult { try await operation() }
}
