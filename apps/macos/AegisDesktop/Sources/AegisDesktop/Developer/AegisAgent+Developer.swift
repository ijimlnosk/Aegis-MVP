import Foundation

extension AegisAgent {
  func runDeveloperTool(_ step: AgentStep, request: String) {
    let project = step.project ?? ""
    busy = true
    Task.detached { [weak self] in
      guard let self else { return }
      if let check = self.validationCheck(for: step.action) {
        let repository = await MainActor.run { self.memoryStore.repository }
        do {
          let url = try ProjectCommandPolicy.projectURL(project, repository: repository)
          let result = ProjectValidationRunner.run(check, project: project, at: url)
          await MainActor.run { self.finishValidation(result, step: step, request: request, project: project) }
        } catch {
          let result = ProjectValidationResult(check: check, status: .skipped,
            summary: "\(check.rawValue) 검사 도구를 실행할 수 없습니다: \(error.localizedDescription)")
          await MainActor.run { self.finishValidation(result, step: step, request: request, project: project) }
        }
        return
      }
      do {
        if step.action == .getDevelopmentRecap {
          let typed = try await MainActor.run { try self.developmentSessions.recapResult(project: project) }
          let result = DevelopmentRecapFormatter.format(typed)
          await MainActor.run {
            self.busy = false
            self.finishReadTool(result, action: step.action.rawValue, request: request,
              target: project, succeeded: typed.executionStatus == .succeeded)
          }
          return
        }
        let result = try await self.developerResult(step, project: project)
        await MainActor.run {
          self.busy = false
          if !project.isEmpty { try? self.developmentSessions.record(project: project, action: step.action.rawValue) }
          self.finishReadTool(result, action: step.action.rawValue, request: request, target: project)
        }
      } catch {
        await MainActor.run {
          self.busy = false
          self.memoryStore.recordAction(request: request, action: step.action.rawValue,
            target: project, result: error.localizedDescription, succeeded: false)
          self.failCurrentStep(error.localizedDescription)
        }
      }
    }
  }

  nonisolated private func developerResult(_ step: AgentStep, project: String) async throws -> String {
    if step.action == .getTodayDevelopmentSummary {
      return try await MainActor.run { try developmentSessions.today() }
    }
    let repository = await MainActor.run { memoryStore.repository }
    let url = try ProjectCommandPolicy.projectURL(project, repository: repository)
    switch step.action {
    case .getProjectGitStatus: return try ProjectInspector.status(at: url)
    case .getProjectBranch: return try ProjectInspector.branch(at: url)
    case .getProjectDiffSummary: return try ProjectInspector.diffSummary(at: url)
    case .getProjectRecentCommits: return try ProjectInspector.recentCommits(at: url, count: step.lines ?? 5)
    case .getProjectChangedFiles: return try ProjectInspector.changedFiles(at: url).joined(separator: "\n")
    case .getProjectPackageScripts: return try PackageScriptTool.inspect(at: url).scripts.joined(separator: "\n")
    case .getProjectHealth: return try ProjectHealthService.format(ProjectHealthService.lightweight(project: project, repository: repository))
    case .assessProjectDeploymentReadiness:
      return try await MainActor.run { try deploymentReadiness(project: project) }
    case .startDevelopmentSession: return try await MainActor.run { try developmentSessions.start(project: project) }
    case .endDevelopmentSession: return try await MainActor.run { try developmentSessions.end(project: project) }
    case .getDevelopmentRecap: return try await MainActor.run { try developmentSessions.recap(project: project) }
    default: throw ProjectCommandError.commandFailed("지원하지 않는 개발 도구입니다.")
    }
  }

  nonisolated private func validationCheck(for action: AgentAction) -> ProjectValidationCheck? {
    [.runProjectTypecheck: .typecheck, .runProjectTests: .test,
     .runProjectLint: .lint, .runProjectBuild: .build][action]
  }

  private func finishValidation(_ result: ProjectValidationResult, step: AgentStep,
                                request: String, project: String) {
    busy = false; developerValidationResults[project, default: [:]][result.check] = result
    try? developmentSessions.record(project: project, action: step.action.rawValue)
    let succeeded = result.succeedsPlan
    memoryStore.recordAction(request: request, action: step.action.rawValue,
      target: project, result: result.summary, succeeded: succeeded)
    speak(result.summary, role: result.status == .failed ? .error : .assistant)
    completeCurrentStep(succeeded: succeeded)
  }

  private func deploymentReadiness(project: String) throws -> String {
    var report = try ProjectHealthService.lightweight(project: project, repository: memoryStore.repository)
    report.validationResults = developerValidationResults.removeValue(forKey: project)
      .map { Array($0.values) } ?? []
    let url = try ProjectCommandPolicy.projectURL(project, repository: memoryStore.repository)
    guard let package = try? PackageScriptTool.inspect(at: url) else {
      return DeploymentReadinessFormatter.format(project: project,
        readiness: DeploymentReadiness(state: .unknown, passed: [], warnings: [],
          unsupported: [], blockers: ["package.json 검증 구성을 평가하지 못했습니다."]))
    }
    let profile = ProjectValidationProfile.resolve(project: project, package: package,
      repository: memoryStore.repository)
    return DeploymentReadinessFormatter.format(project: project,
      readiness: DeploymentReadiness.assess(report, profile: profile))
  }
}
