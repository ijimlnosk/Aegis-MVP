import Foundation

actor CodingTaskCoordinator {
  struct Active: Sendable, Equatable {
    let taskID: UUID; let project: String; let mode: CodingTaskMode; let startedAt: Date
    var lifecycle: CodingExecutionLifecycle
  }

  private(set) var activeByProject: [String: Active] = [:]
  private(set) var lastResult: CodingTaskResult?
  private var records: [String: CodingTaskRecord] = [:]

  func run(_ task: CodingTask, provider: any CodingAgentProvider,
           configuration: CodingConfiguration,
           repository: MemoryRepository) async throws -> CodingTaskResult {
    let key = task.projectRoot.standardizedFileURL.path
    guard activeByProject[key] == nil else { throw CodingTaskError.alreadyRunning(task.project) }
    activeByProject[key] = Active(taskID: task.id, project: task.project,
      mode: task.mode, startedAt: task.startedAt, lifecycle: .planned)
    defer { activeByProject[key] = nil }
    let before = try CodingGitInspector.snapshot(at: task.projectRoot)
    transition(key, to: .validated)
    let policy = CodingExecutionPolicy.policy(for: task.mode)
    transition(key, to: .started)
    transition(key, to: .providerRunning)
    let execution = await provider.execute(task, policy: policy, timeout: configuration.timeout)
    transition(key, to: .providerFinished)
    let after = try CodingGitInspector.snapshot(at: task.projectRoot)
    let diff = try CodingGitInspector.diff(before: before, after: after, at: task.projectRoot)
    transition(key, to: .verified)
    let validation = task.mode == .workspaceWrite
      ? validate(project: task.project, root: task.projectRoot, repository: repository) : []
    let status = status(execution, task: task, before: before, after: after,
      diff: diff, validation: validation, limit: configuration.maximumChangedFiles)
    let summary = task.mode == .readOnlyAnalysis && status == .succeeded
      ? execution.userResult
      : CodingTaskFormatter.summary(status: status, execution: execution)
    let changedFiles = task.mode == .readOnlyAnalysis
      ? Array(Set(diff.attributableFiles + diff.overlappingFiles)).sorted()
      : diff.attributableFiles
    transition(key, to: .completed)
    let result = CodingTaskResult(taskID: task.id, project: task.project,
      status: status, summary: summary,
      changedFiles: changedFiles, verification: validation, provider: provider.name,
      duration: Date().timeIntervalSince(task.startedAt), hadPreexistingChanges: before.isDirty,
      mode: task.mode, workingTreeDelta: diff.workingTreeDelta,
      preexistingFiles: diff.preexistingFiles, lifecycle: .completed,
      providerDiagnostics: execution.diagnostics, providerEvents: execution.providerEvents,
      sourceFindingId: task.sourceFindingId, sourceFindingTitle: task.sourceFindingTitle)
    lastResult = result
    if task.mode == .workspaceWrite {
      records[key] = CodingTaskRecord(taskID: task.id, before: before, after: after,
        diff: diff, root: task.projectRoot)
    }
    return result
  }

  private func transition(_ key: String, to lifecycle: CodingExecutionLifecycle) {
    activeByProject[key]?.lifecycle = lifecycle
  }

  func rollbackLast(projectRoot: URL) throws -> [String] {
    let key = projectRoot.standardizedFileURL.path
    guard let record = records[key] else { throw CodingTaskError.taskNotFound }
    let current = try CodingGitInspector.snapshot(at: projectRoot)
    guard current == record.after else { throw CodingTaskError.unsafeRollback }
    let files = try CodingRollbackService.rollback(diff: record.diff, at: projectRoot)
    records[key] = nil
    return files
  }

  func status(provider: any CodingAgentProvider) -> CodingAgentStatus {
    .init(provider: provider.name, available: provider.isAvailable(),
      active: activeByProject.values.first, lastResult: lastResult,
      version: provider.version(), executable: provider.executablePath)
  }

  func lastAttributedFiles(project: String) -> [String]? {
    guard let result = lastResult,
      result.project.caseInsensitiveCompare(project) == .orderedSame,
      result.mode == .workspaceWrite else { return nil }
    return result.changedFiles
  }

  func verify(project: String, root: URL,
              repository: MemoryRepository) -> [ProjectValidationResult] {
    validate(project: project, root: root, repository: repository)
  }

  private func validate(project: String, root: URL,
                        repository: MemoryRepository) -> [ProjectValidationResult] {
    ProjectValidationService.run(project: project, root: root,
      repository: repository).checks
  }

  private func status(_ execution: CodingAgentExecution, task: CodingTask,
                      before: CodingTaskSnapshot, after: CodingTaskSnapshot,
                      diff: CodingTaskDiff, validation: [ProjectValidationResult],
                      limit: Int) -> CodingTaskStatus {
    if execution.cancelled { return .cancelled }
    if execution.timedOut { return .timedOut }
    if !execution.completed { return .agentFailed }
    if task.mode == .readOnlyAnalysis {
      if diff.workingTreeDelta.hasChanges { return .needsReview }
      return execution.userResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? .agentFailed : .succeeded
    }
    if diff.attributableFiles.count > limit || !diff.overlappingFiles.isEmpty { return .needsReview }
    if validation.contains(where: { $0.status == .failed }) { return .failedValidation }
    if diff.attributableFiles.isEmpty { return .needsReview }
    if validation.contains(where: { [.warning, .skipped].contains($0.status) }) {
      return .succeededWithWarnings
    }
    return .succeeded
  }
}

private struct CodingTaskRecord: Sendable {
  let taskID: UUID
  let before: CodingTaskSnapshot
  let after: CodingTaskSnapshot
  let diff: CodingTaskDiff
  let root: URL
}

enum CodingTaskError: LocalizedError {
  case alreadyRunning(String), notGitRepository, unsafeRollback, taskNotFound
  var errorDescription: String? {
    switch self {
    case .alreadyRunning(let project): "\(project)에서 이미 코딩 작업이 실행 중입니다."
    case .notGitRepository: "신뢰된 프로젝트가 Git 저장소가 아닙니다."
    case .unsafeRollback: "기존 사용자 변경과 분리할 수 없어 자동 롤백하지 않았습니다."
    case .taskNotFound: "롤백할 코딩 작업을 찾지 못했습니다."
    }
  }
}
