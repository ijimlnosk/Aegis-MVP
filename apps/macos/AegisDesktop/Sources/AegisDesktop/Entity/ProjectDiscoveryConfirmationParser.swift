// Matches a short "register it" follow-up after a project location was just found
// (see ProjectDiscovery / DeveloperIntentResolver.locateProjectPlan). Kept separate
// from MemoryIntentParser because it only makes sense in the context of a pending
// discovery -- callers must still check that pending state before acting on it.
enum ProjectDiscoveryConfirmationParser {
  private static let confirmations = ["등록해", "등록해줘", "등록할게", "등록하자", "등록시켜"]

  static func isConfirmation(_ request: String) -> Bool {
    let compact = request.replacingOccurrences(of: " ", with: "")
    return confirmations.contains { compact.contains($0) }
  }
}
