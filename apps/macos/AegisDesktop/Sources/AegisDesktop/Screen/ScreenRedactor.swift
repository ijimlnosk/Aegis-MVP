protocol ScreenRedacting {
  func redact(_ snapshot: ScreenSnapshot) async throws -> ScreenSnapshot
}

struct PassthroughScreenRedactor: ScreenRedacting {
  func redact(_ snapshot: ScreenSnapshot) async throws -> ScreenSnapshot { snapshot }
}
