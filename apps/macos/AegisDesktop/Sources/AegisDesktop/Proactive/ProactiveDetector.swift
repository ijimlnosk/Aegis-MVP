import Foundation

enum ProactiveDetector {
  static func detect(previous: ContextSnapshot?, current: ContextSnapshot,
                     thresholds: ContextThresholds) -> [ProactiveEvent] {
    guard let previous else { return [] }
    return serverEvents(previous.server, current.server, thresholds)
      + dockerEvents(previous.server?.containers ?? [], current.server?.containers ?? [])
      + ProjectChangeDetector.detect(previous.projects, current.projects, thresholds)
  }

  private static func serverEvents(_ old: ServerContext?, _ new: ServerContext?,
                                   _ limits: ContextThresholds) -> [ProactiveEvent] {
    guard let old, let new else { return [] }
    if old.available, !new.available {
      return [event(.serverUnavailable, .critical, "sol-server 연결 끊김",
        "sol-server에 연결할 수 없습니다.", new.error ?? "응답 없음", "server:availability")]
    }
    if !old.available, new.available {
      return [event(.serverRecovered, .info, "sol-server 연결 복구",
        "sol-server 연결이 복구됐습니다.", new.uptime ?? "응답 정상", "server:availability", true)]
    }
    guard new.available else { return [] }
    return metricEvents(name: "메모리", old: old.memoryPercent, new: new.memoryPercent,
      warning: limits.memoryWarning, critical: limits.memoryCritical,
      type: .memoryHigh, recovery: .memoryRecovered, key: "server:memory")
      + metricEvents(name: "디스크", old: old.diskPercent, new: new.diskPercent,
        warning: limits.diskWarning, critical: limits.diskCritical,
        type: .diskHigh, recovery: .diskRecovered, key: "server:disk")
  }

  private static func metricEvents(name: String, old: Double?, new: Double?, warning: Double,
                                   critical: Double, type: ProactiveEventType,
                                   recovery: ProactiveEventType, key: String) -> [ProactiveEvent] {
    guard let old, let new else { return [] }
    let oldSeverity = severity(old, warning, critical), newSeverity = severity(new, warning, critical)
    if let newSeverity, oldSeverity == nil || oldSeverity! < newSeverity {
      let threshold = newSeverity == .critical ? critical : warning
      return [event(type, newSeverity, "sol-server \(name) 사용률 상승",
        "sol-server \(name) 사용률이 \(format(new))%로 \(format(threshold))% 기준을 넘었습니다.",
        "이전 \(format(old))% → 현재 \(format(new))%", key)]
    }
    if oldSeverity != nil, newSeverity == nil {
      return [event(recovery, .info, "sol-server \(name) 사용률 정상화",
        "sol-server \(name) 사용률이 \(format(new))%로 정상 범위로 돌아왔습니다.",
        "경고 기준 \(format(warning))%", key, true)]
    }
    return []
  }

  private static func dockerEvents(_ old: [DockerContext], _ new: [DockerContext]) -> [ProactiveEvent] {
    let before = Dictionary(uniqueKeysWithValues: old.map { ($0.name, $0) })
    let after = Dictionary(uniqueKeysWithValues: new.map { ($0.name, $0) })
    return Set(before.keys).union(after.keys).compactMap { name in
      guard let oldValue = before[name] else { return nil }
      let current = after[name], key = "docker:\(name):running"
      if oldValue.isRunning, current?.isRunning != true {
        return event(.containerStopped, .warning, "Docker 컨테이너 중지",
          "\(name) 컨테이너가 중지되었습니다. 최근 로그를 확인할까요?",
          "이전: \(oldValue.state), 현재: \(current?.state ?? "목록에서 없음")", key,
          suggestion: .getDockerLogs)
      }
      if !oldValue.isRunning, current?.isRunning == true {
        return event(.containerRecovered, .info, "Docker 컨테이너 복구",
          "\(name) 컨테이너가 다시 실행 중입니다.", current?.state ?? "running", key, true)
      }
      return nil
    }
  }

  private static func severity(_ value: Double, _ warning: Double, _ critical: Double) -> ProactiveSeverity? {
    value >= critical ? .critical : value >= warning ? .warning : nil
  }
  private static func format(_ value: Double) -> String { String(format: "%.0f", value) }
  private static func event(_ type: ProactiveEventType, _ severity: ProactiveSeverity,
    _ title: String, _ message: String, _ evidence: String, _ key: String,
    _ recovery: Bool = false, suggestion: AgentAction? = nil) -> ProactiveEvent {
    ProactiveEvent(type: type, severity: severity, source: key.hasPrefix("project") ? .projects : .server,
      title: title, message: message, evidence: evidence, deduplicationKey: key,
      isRecovery: recovery, suggestedAction: suggestion)
  }
}
