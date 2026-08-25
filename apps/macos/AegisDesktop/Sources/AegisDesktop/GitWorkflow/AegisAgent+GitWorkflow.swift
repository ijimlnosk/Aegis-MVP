import Foundation

extension AegisAgent {
  func runGitWorkflowTool(_ step: AgentStep, request: String) {
    guard let project = step.project else { failCurrentStep("프로젝트가 필요합니다."); return }
    busy = true
    Task {
      do {
        let root = try ProjectCommandPolicy.projectURL(project, repository: memoryStore.repository)
        let result = try await executeGitAction(step.action, project: project, root: root,
          request: request, stepContent: step.content)
        busy = false
        speak(result)
        completeCurrentStep(succeeded: true, result: result)
      } catch {
        busy = false
        if step.action == .createCommit {
          switch error as? GitWorkflowError {
          case .stalePlan: gitWorkflowContext.state = .invalidated
          case .expiredCommitPlan: gitWorkflowContext.state = .expired
          case .validationFailed: gitWorkflowContext.state = .failed
          default: gitWorkflowContext.state = .failed
          }
        }
        failCurrentStep(error.localizedDescription)
      }
    }
  }

  private func executeGitAction(_ action: AgentAction, project: String, root: URL,
                                request: String, stepContent: String?) async throws -> String {
    switch action {
    case .inspectGitDiff:
      let snapshot = try CodingGitInspector.snapshot(at: root)
      return "\(project) Git 변경\n- branch: \(snapshot.branch)\n- files: \(snapshot.changedFiles.count)\n"
        + snapshot.changedFiles.prefix(50).map { "- \($0)" }.joined(separator: "\n")
    case .proposeCommitPlan:
      if let existing = gitWorkflowContext.plan,
        !isCommitReplanRequest(request, stepContent: stepContent) {
        let current = try CodingGitInspector.snapshot(at: root)
        guard current.branch == existing.branch, current.entries == existing.baseSnapshot.entries else {
          gitWorkflowContext.state = .invalidated
          throw GitWorkflowError.stalePlan
        }
        let selection = ["첫 번째", "두 번째", "세 번째", "1번", "2번", "3번", "빼", "제외"]
          .contains(where: request.contains)
        let retained = selection ? try GitCommitPlanEditor.update(existing, request: request) : existing
        gitWorkflowContext.retain(retained)
        return selection ? GitWorkflowFormatter.plan(retained)
          : "기존 \(project) 커밋 계획을 확인했습니다. 승인 후 정확한 계획을 실행합니다."
      }
      let snapshot = try CodingGitInspector.snapshot(at: root)
      let recentOnly = request.contains("방금") && request.contains("작업")
      var attributed = recentOnly ? await codingCoordinator.lastAttributedFiles(project: project) : nil
      if recentOnly, attributed?.isEmpty != false {
        attributed = await autonomousDevelopment.lastAttributedFiles(project: project)
      }
      if recentOnly, attributed?.isEmpty != false { throw GitWorkflowError.noAttributedFiles }
      let plan = try GitCommitPlanner.create(project: project, root: root,
        snapshot: snapshot, request: request, allowedFiles: attributed.map(Set.init))
      gitWorkflowContext = GitWorkflowContext(sessionId: conversationSessionID)
      gitWorkflowContext.retain(plan)
      return GitWorkflowFormatter.plan(plan)
    case .createCommit:
      guard let plan = gitWorkflowContext.plan, plan.projectId == project else {
        throw GitWorkflowError.invalidPlan
      }
      gitWorkflowContext.state = .committing
      let result = try GitCommitExecutor.execute(plan, root: root) {
        let report = self.validateForCommit(project: project, root: root, plan: plan)
        self.gitWorkflowContext.lastValidationReport = report
        return report
      }
      gitWorkflowContext.createdCommits += result.commits
      gitWorkflowContext.state = result.succeeded ? .committed : .failed
      let report = GitWorkflowFormatter.execution(result, total: plan.groups.count)
      if !result.succeeded { throw GitWorkflowError.partialCommit(report) }
      try? developmentSessions.record(project: project,
        action: "Git 커밋 \(result.commits.count)개 생성 · push 안 함")
      return report
    case .getRemoteStatus:
      return GitWorkflowFormatter.push(try GitPushPolicy.status(project: project, root: root))
    case .proposePush:
      let proposal = try GitPushPolicy.proposal(project: project, root: root)
      gitWorkflowContext.pushProposal = proposal
      gitWorkflowContext.state = .awaitingPushApproval
      return GitWorkflowFormatter.push(proposal)
    case .pushCurrentBranch:
      guard let proposal = gitWorkflowContext.pushProposal, proposal.project == project else {
        throw GitWorkflowError.stalePlan
      }
      let report = try GitPushExecutor.push(proposal, root: root)
      gitWorkflowContext.state = .complete
      try? developmentSessions.record(project: project, action: "Git push 완료 · \(proposal.upstream)")
      return report
    case .getCIStatus:
      return try GitHubStatusReader.ci(project: project, root: root)
    case .getPullRequestStatus:
      return try GitHubStatusReader.pullRequest(project: project, root: root)
    case .getGitWorkflowStatus:
      return GitWorkflowFormatter.status(project: project, snapshot: try CodingGitInspector.snapshot(at: root),
        context: gitWorkflowContext)
    default: throw GitWorkflowError.invalidPlan
    }
  }

  private func validateForCommit(project: String, root: URL,
                                 plan: GitCommitPlan) -> ProjectValidationReport {
    let files = plan.groups.flatMap(\.files)
    let report = files.allSatisfy({ $0.hasSuffix(".md") || $0.hasPrefix("docs/") })
      ? ProjectValidationReport.documentationOnly(project: project)
      : ProjectValidationService.run(project: project, root: root, repository: memoryStore.repository)
    developerValidationResults[project.lowercased()] = Dictionary(
      uniqueKeysWithValues: report.checks.map { ($0.check, $0) })
    return report
  }

  private func isCommitReplanRequest(_ request: String, stepContent: String?) -> Bool {
    let text = ([request, stepContent ?? ""].joined(separator: " "))
      .lowercased().replacingOccurrences(of: " ", with: "")
    return ["새계획", "다시계획", "새로만들", "다시만들"].contains(where: text.contains)
  }
}
