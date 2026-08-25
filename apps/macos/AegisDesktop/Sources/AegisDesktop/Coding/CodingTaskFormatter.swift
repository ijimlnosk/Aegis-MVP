import Foundation

struct CodingAgentStatus: Sendable, Equatable {
  let provider: String
  let available: Bool
  let active: CodingTaskCoordinator.Active?
  let lastResult: CodingTaskResult?
  let version: String?
  let executable: String?

  init(provider: String, available: Bool, active: CodingTaskCoordinator.Active?,
       lastResult: CodingTaskResult?, version: String? = nil, executable: String? = nil) {
    self.provider = provider; self.available = available; self.active = active
    self.lastResult = lastResult; self.version = version; self.executable = executable
  }
}

enum CodingTaskFormatter {
  static func summary(status: CodingTaskStatus, execution: CodingAgentExecution) -> String {
    switch status {
    case .succeeded: "코딩 작업과 필수 검증이 완료되었습니다."
    case .succeededWithWarnings: "코딩 작업은 완료됐지만 검증 경고가 있습니다."
    case .failedValidation: "코드 수정은 수행했지만 검증이 실패해 완료로 판단하지 않았습니다."
    case .agentFailed: "코딩 에이전트 실행에 실패했습니다. 부분 변경 여부를 확인했습니다."
    case .cancelled: "코딩 작업이 취소되었습니다. 부분 변경은 보존했습니다."
    case .timedOut: "코딩 작업 시간이 초과되었습니다. 부분 변경은 보존했습니다."
    case .needsReview: "변경 범위나 귀속을 확정할 수 없어 검토가 필요합니다."
    }
  }

  static func format(_ result: CodingTaskResult, project: String, workStatus: Bool = false) -> String {
    if result.mode == .readOnlyAnalysis {
      if result.status == .succeeded {
        let heading = workStatus ? "\(project) 현재 작업 분석" : "\(project)에서 개선할 부분 1개를 찾았습니다."
        var text = "\(heading)\n\n\(result.summary)\n\n코드는 수정하지 않았습니다."
        if !result.preexistingFiles.isEmpty {
          text += "\n\n참고:\n분석 전부터 미커밋 변경 \(result.preexistingFiles.count)건이 존재합니다."
        }
        return text
      }
      guard result.workingTreeDelta.hasChanges else {
        return result.summary
      }
      var lines = ["읽기 전용 분석 중 예상하지 않은 변경이 발생했습니다.", "", "새 변경:"]
      lines += result.changedFiles.isEmpty ? ["- Git HEAD 또는 branch가 변경되었습니다."]
        : result.changedFiles.map { "- \($0)" }
      if !result.preexistingFiles.isEmpty {
        lines += ["", "기존 변경:"] + result.preexistingFiles.map { "- \($0)" }
        lines += ["", "기존 변경은 분석 전부터 존재했으며 이번 작업의 변경으로 계산하지 않았습니다."]
      }
      lines += ["", "자동 복구는 수행하지 않았습니다."]
      return lines.joined(separator: "\n")
    }
    var lines = ["\(project) 코딩 작업", "", reviewSummary(result)]
    if [.succeeded, .succeededWithWarnings].contains(result.status),
      let title = result.sourceFindingTitle {
      lines.insert("방금 찾은 \(title)을(를) 수정했습니다.", at: 2)
    }
    if !result.changedFiles.isEmpty {
      lines += ["", "변경:"] + result.changedFiles.prefix(20).map { "- \($0)" }
    }
    if !result.verification.isEmpty {
      lines += ["", "검증:"] + result.verification.map {
        "- \($0.check.rawValue): \($0.status.rawValue) · \($0.summary)"
      }
    }
    if result.hadPreexistingChanges {
      lines += ["", "주의:", "- 기존 미커밋 변경은 작업 변경으로 귀속하거나 자동 롤백하지 않습니다."]
    }
    return lines.joined(separator: "\n")
  }

  private static func reviewSummary(_ result: CodingTaskResult) -> String {
    guard result.status == .needsReview else { return result.summary }
    if !result.workingTreeDelta.hasChanges {
      return "코딩 에이전트 실행 후 이번 작업에 귀속할 새 변경을 확인하지 못했습니다."
    }
    let overlap = Set(result.preexistingFiles).intersection(result.changedFiles).sorted()
    if !overlap.isEmpty {
      return "이번 작업이 기존 미커밋 변경과 같은 파일을 수정해 자동 귀속하지 않았습니다: "
        + overlap.joined(separator: ", ")
    }
    return "변경 파일 수나 변경 범위가 안전 한도를 넘어 자동 완료하지 않았습니다."
  }

  static func diagnostics(_ status: CodingAgentStatus) -> String {
    var lines = ["코딩 에이전트", "- provider: \(status.provider)",
      "- available: \(status.available ? "yes" : "no")"]
    if let version = status.version { lines.append("- version: \(version)") }
    if let executable = status.executable { lines.append("- executable: \(executable)") }
    if let active = status.active {
      lines += ["- active task: \(active.taskID.uuidString)", "- project: \(active.project)",
        "- mode: \(active.mode.rawValue)",
        "- lifecycle: \(active.lifecycle.rawValue)",
        "- elapsed: \(Int(Date().timeIntervalSince(active.startedAt)))초"]
    } else { lines.append("- active task: none") }
    if let last = status.lastResult { lines.append("- last result: \(last.status.rawValue)") }
    return lines.joined(separator: "\n")
  }

  static func diagnostics(primary: CodingAgentStatus, fallback: CodingAgentStatus?) -> String {
    var lines = ["Coding Agent:", "- provider: \(primary.provider)",
      "- status: \(primary.available ? "available" : "unavailable")"]
    if let version = primary.version { lines.append("- version: \(version)") }
    lines.append("- fallback: none")
    if let active = primary.active ?? fallback?.active {
      lines += ["", "Active task:", "- project: \(active.project)", "- mode: \(active.mode.rawValue)"]
    } else { lines += ["", "Active task: none"] }
    return lines.joined(separator: "\n")
  }

  static func recentDiagnostics(_ status: CodingAgentStatus) -> String {
    guard let result = status.lastResult else { return "최근 코딩 에이전트 실행이 없습니다." }
    let diagnostics = result.providerDiagnostics
    return ["코딩 에이전트 최근 실행 진단",
      "- provider: \(result.provider)", "- mode: \(result.mode.rawValue)",
      "- project: \(result.project)",
      "- exit status: \(diagnostics.exitStatus.map(String.init) ?? "unavailable")",
      "- duration: \(Int(result.duration))초", "- sandbox: \(diagnostics.sandboxMode)",
      "- provider events: \(diagnostics.eventCount)"].joined(separator: "\n")
  }

  static func validationExplanation(_ result: CodingTaskResult) -> String {
    guard !result.verification.isEmpty else {
      return "최근 \(result.project) 코딩 작업에는 실행된 검증 항목이 없습니다."
    }
    var lines = ["\(result.project) 최근 코드 수정 검증 결과"]
    lines += result.verification.map {
      "- \($0.check.rawValue): \($0.status.rawValue) · \($0.summary)"
    }
    let warnings = result.verification.filter { [.warning, .skipped].contains($0.status) }
    if warnings.isEmpty {
      lines += ["", "별도의 검증 경고는 없습니다."]
    } else {
      lines += ["", "경고는 코드 수정을 되돌릴 실패는 아니지만 확인이 필요한 항목입니다."]
    }
    return lines.joined(separator: "\n")
  }

  static func validationExplanation(project: String, checks: [ProjectValidationResult]) -> String {
    guard !checks.isEmpty else { return "\(project)에서 확인할 검증 항목을 찾지 못했습니다." }
    var lines = ["\(project) 검증 원인 확인"]
    lines += checks.map { "- \($0.check.rawValue): \($0.status.rawValue) · \($0.summary)" }
    let unsupported = checks.filter { $0.status == .unsupported }.map(\.check.rawValue)
    if !unsupported.isEmpty {
      lines += ["", "unsupported는 코드 오류가 아니라 package.json에 해당 스크립트가 없어서 실행하지 못했다는 뜻입니다: \(unsupported.joined(separator: ", "))"]
    }
    return lines.joined(separator: "\n")
  }
}
