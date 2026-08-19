enum ProjectChangeDetector {
  static func detect(_ old: [ProjectContext], _ new: [ProjectContext],
                     _ limits: ContextThresholds) -> [ProactiveEvent] {
    let before = Dictionary(uniqueKeysWithValues: old.map { ($0.name, $0) })
    return new.flatMap { current -> [ProactiveEvent] in
      guard let previous = before[current.name] else { return [] }
      let prefix = "project:\(current.name)"
      if previous.available, !current.available {
        return [make(.projectUnavailable, .warning, "\(current.name) 접근 불가",
          "\(current.name) 프로젝트 경로 또는 Git 상태를 확인할 수 없습니다.",
          "이전 관찰에서는 사용 가능", "\(prefix):availability")]
      }
      if !previous.available, current.available {
        return [make(.projectRecovered, .info, "\(current.name) 접근 복구",
          "\(current.name) 프로젝트를 다시 확인할 수 있습니다.",
          "현재 branch: \(current.branch ?? "알 수 없음")", "\(prefix):availability", true)]
      }
      guard current.available else { return [] }
      return stateEvents(previous, current, prefix, limits)
    }
  }

  private static func stateEvents(_ old: ProjectContext, _ new: ProjectContext,
                                  _ prefix: String, _ limits: ContextThresholds) -> [ProactiveEvent] {
    var events: [ProactiveEvent] = []
    if !old.isDirty, new.isDirty { events.append(make(.projectDirty, .info,
      "\(new.name) 변경 감지", "\(new.name)에 커밋되지 않은 변경이 생겼습니다.",
      "변경 파일 \(new.changedFileCount)개", "\(prefix):dirty")) }
    if old.isDirty, !new.isDirty { events.append(make(.projectClean, .info,
      "\(new.name) 정리 완료", "\(new.name)가 clean 상태로 돌아왔습니다.",
      "변경 파일 0개", "\(prefix):dirty", true)) }
    if old.branch != new.branch { events.append(make(.projectBranchChanged, .info,
      "\(new.name) 브랜치 변경", "\(new.name) 브랜치가 변경되었습니다.",
      "\(old.branch ?? "없음") → \(new.branch ?? "없음")", "\(prefix):branch")) }
    let noteworthy = limits.projectThreshold(new.name)
    if old.changedFileCount < noteworthy, new.changedFileCount >= noteworthy {
      let severity: ProactiveSeverity = new.changedFileCount >= limits.projectWarning ? .warning : .info
      events.append(make(.projectChangesHigh, severity, "\(new.name) 변경 파일 증가",
        "\(new.name)에 커밋되지 않은 변경 파일이 \(new.changedFileCount)개 있습니다.",
        "알림 기준 \(noteworthy)개", "\(prefix):changes"))
    }
    return events
  }

  private static func make(_ type: ProactiveEventType, _ severity: ProactiveSeverity,
    _ title: String, _ message: String, _ evidence: String, _ key: String,
    _ recovery: Bool = false) -> ProactiveEvent {
    ProactiveEvent(type: type, severity: severity, source: .projects, title: title,
      message: message, evidence: evidence, deduplicationKey: key, isRecovery: recovery)
  }
}
