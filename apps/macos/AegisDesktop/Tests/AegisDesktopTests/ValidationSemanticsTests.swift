import Foundation
import Testing
@testable import AegisDesktop

@Test func unsupportedAndSkippedChecksDoNotFailPlan() throws {
  let url = try DeveloperTestSupport.directory()
  try #"{"scripts":{}}"#.write(to: url.appending(path: "package.json"), atomically: true, encoding: .utf8)
  let unsupported = ProjectValidationRunner.run(.build, project: "PTFriends", at: url)
  #expect(unsupported.status == .unsupported)
  #expect(unsupported.succeedsPlan)
  #expect(unsupported.summary.contains("건너뜁니다"))
  let skipped = ProjectValidationRunner.run(.test, project: "PTFriends", at: url.appending(path: "missing"))
  #expect(skipped.status == .skipped)
  #expect(skipped.succeedsPlan)
}

@Test func plannerExcludesUnavailableBuildScript() throws {
  let project = try DeveloperTestSupport.gitProject()
  try #"{"scripts":{"typecheck":"echo ok","lint":"echo ok","test":"echo ok"}}"#
    .write(to: project.appending(path: "package.json"), atomically: true, encoding: .utf8)
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  let plan = DeveloperIntentResolver.plan(for: "PTFriends 전체 점검해봐", repository: memory)
  #expect(plan?.steps.map(\.action) == [.runProjectTypecheck, .runProjectLint,
    .runProjectTests, .assessProjectDeploymentReadiness])
}

@Test func lintWarningsAndErrorsRemainDistinct() throws {
  let warningURL = try package(script: #"node -e "console.log('0 errors and 15 warnings')""#, name: "lint")
  let warning = ProjectValidationRunner.run(.lint, project: "P", at: warningURL)
  #expect(warning.status == .warning)
  #expect(warning.warningCount == 15)
  let errorURL = try package(script: #"node -e "console.error('1 error');process.exit(1)""#, name: "lint")
  #expect(ProjectValidationRunner.run(.lint, project: "P", at: errorURL).status == .failed)
}

@Test func testAndTypecheckFailuresBlockReadiness() {
  let results = [ProjectValidationResult(check: .typecheck, status: .failed, summary: "typecheck failed"),
    ProjectValidationResult(check: .test, status: .failed, summary: "tests failed")]
  let profile = ProjectValidationProfile(requiredChecks: [.typecheck, .test], optionalChecks: [])
  let readiness = DeploymentReadiness.assess(health(clean: true, results: results), profile: profile)
  #expect(readiness.state == .blocked)
  #expect(readiness.blockers.count == 2)
}

@Test func cleanRequiredPassesAreReadyAndDirtyIsWarning() {
  let results = [ProjectValidationResult(check: .typecheck, status: .passed, summary: "typecheck passed"),
    ProjectValidationResult(check: .test, status: .passed, summary: "tests passed")]
  let profile = ProjectValidationProfile(requiredChecks: [.typecheck, .test], optionalChecks: [],
    unsupportedChecks: [.build])
  #expect(DeploymentReadiness.assess(health(clean: true, results: results), profile: profile).state == .ready)
  #expect(DeploymentReadiness.assess(health(clean: false, results: results), profile: profile).state == .warning)
}

@Test func missingRequiredWarnsAndInfrastructureFailureIsUnknown() {
  let missing = ProjectValidationProfile(requiredChecks: [.build], optionalChecks: [], unsupportedChecks: [.build])
  #expect(DeploymentReadiness.assess(health(clean: true, results: []), profile: missing).state == .warning)
  let skipped = ProjectValidationResult(check: .test, status: .skipped, summary: "tool unavailable")
  let required = ProjectValidationProfile(requiredChecks: [.test], optionalChecks: [])
  #expect(DeploymentReadiness.assess(health(clean: true, results: [skipped]), profile: required).state == .unknown)
}

@Test func readinessFormatterSeparatesEvidenceSections() {
  let readiness = DeploymentReadiness(state: .warning, passed: ["typecheck 통과"],
    warnings: ["ESLint 경고 15건"], unsupported: ["build 검사 제외"], blockers: [])
  let text = DeploymentReadinessFormatter.format(project: "PTFriends", readiness: readiness)
  #expect(text.contains("PTFriends 배포 준비 상태: WARNING"))
  #expect(text.contains("통과:")); #expect(text.contains("주의:")); #expect(text.contains("미지원:"))
}

@Test func explicitProjectValidationTeachingUsesProjectKey() {
  let intent = MemoryIntentParser.parse("PTFriends 배포 전에는 typecheck, lint, test를 확인해.")
  #expect(intent == .remember(type: .preference, key: "project_validation_profile:ptfriends",
    value: "typecheck,lint,test"))
}

private func package(script: String, name: String) throws -> URL {
  let url = try DeveloperTestSupport.directory()
  let data = try JSONSerialization.data(withJSONObject: ["scripts": [name: script]])
  try data.write(to: url.appending(path: "package.json")); return url
}

private func health(clean: Bool, results: [ProjectValidationResult]) -> ProjectHealthReport {
  ProjectHealthReport(project: "P", branch: "main", clean: clean,
    changedFileCount: clean ? 0 : 1, changedFiles: clean ? [] : ["M file"],
    recentCommits: "", validationResults: results, generatedAt: .now)
}
