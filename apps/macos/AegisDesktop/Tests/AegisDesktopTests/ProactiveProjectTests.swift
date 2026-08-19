import Testing
@testable import AegisDesktop

@Test func projectCleanToDirtyAndChangedThreshold() {
  let old = context(project("PTFriends", branch: "main", dirty: false, count: 2))
  let new = context(project("PTFriends", branch: "main", dirty: true, count: 17))
  let types = ProactiveDetector.detect(previous: old, current: new, thresholds: .init()).map(\.type)
  #expect(types.contains(.projectDirty))
  #expect(types.contains(.projectChangesHigh))
}

@Test func projectBranchChangeIsDetected() {
  let old = context(project("PTFriends", branch: "main", dirty: false, count: 0))
  let new = context(project("PTFriends", branch: "feature", dirty: false, count: 0))
  #expect(ProactiveDetector.detect(previous: old, current: new,
    thresholds: .init()).contains { $0.type == .projectBranchChanged })
}

@Test func projectAvailabilityFailureAndRecoveryAreDetected() {
  let available = context(project("PTFriends", branch: "main", dirty: false, count: 0))
  let unavailable = context(ProjectContext(name: "PTFriends", available: false,
    branch: nil, isDirty: false, changedFileCount: 0))
  #expect(ProactiveDetector.detect(previous: available, current: unavailable,
    thresholds: .init()).contains { $0.type == .projectUnavailable })
  #expect(ProactiveDetector.detect(previous: unavailable, current: available,
    thresholds: .init()).contains { $0.type == .projectRecovered })
}

@Test func projectSpecificPreferenceOverridesDefault() {
  let preference = MemoryRecord(type: .preference,
    key: "alert_project_ptfriends_files", value: "20")
  let limits = ContextThresholds().applying([preference])
  let old = context(project("PTFriends", branch: "main", dirty: true, count: 2))
  let below = context(project("PTFriends", branch: "main", dirty: true, count: 17))
  let above = context(project("PTFriends", branch: "main", dirty: true, count: 21))
  #expect(!ProactiveDetector.detect(previous: old, current: below,
    thresholds: limits).contains { $0.type == .projectChangesHigh })
  #expect(ProactiveDetector.detect(previous: old, current: above,
    thresholds: limits).contains { $0.type == .projectChangesHigh })
}

private func project(_ name: String, branch: String, dirty: Bool, count: Int) -> ProjectContext {
  ProjectContext(name: name, available: true, branch: branch, isDirty: dirty, changedFileCount: count)
}
private func context(_ project: ProjectContext) -> ContextSnapshot {
  ContextSnapshot(projects: [project])
}
