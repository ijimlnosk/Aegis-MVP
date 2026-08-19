import Foundation

struct ProactiveNotice {
  let event: ProactiveEvent
  let investigation: String?
}

final class ProactiveCoordinator {
  let contextStore: ContextStore
  var proactiveStore = ProactiveStore()
  private var deduplicator: EventDeduplicator
  private let sources: [AnyContextSource]
  private let memory: MemoryRepository
  var activeConditions: [String: ProactiveSeverity] { deduplicator.active }

  init(contextStore: ContextStore = ContextStore(), memory: MemoryRepository,
       sources: [AnyContextSource]? = nil,
       cooldown: TimeInterval = ContextObservationConfiguration.cooldown) {
    self.contextStore = contextStore; self.memory = memory
    self.sources = sources ?? [AnyContextSource(MacContextSource(
      includeClipboardMetadata: ContextObservationConfiguration.clipboardMetadataEnabled)),
      AnyContextSource(ProjectContextSource(repository: memory)), AnyContextSource(ServerContextSource())]
    deduplicator = EventDeduplicator(cooldown: cooldown)
  }

  func observe() async -> [ProactiveNotice] {
    let previous = try? contextStore.snapshots(limit: 1).first
    let current = await ContextCollector.collect(sources)
    try? contextStore.save(current)
    let preferences = (try? memory.records(type: .preference)) ?? []
    let thresholds = ContextThresholds().applying(preferences)
    return await ProactiveDetector.detect(previous: previous, current: current, thresholds: thresholds)
      .filter { deduplicator.accepts($0) && proactiveStore.shouldSurface($0) }
      .asyncMap { event in
        proactiveStore.lastEvent = event
        return ProactiveNotice(event: event, investigation: await investigate(event))
      }
  }

  func summary() -> String {
    guard let latest = try? contextStore.snapshots(limit: 1).first else { return "아직 수집된 context가 없습니다." }
    var warnings: [String] = []
    let preferences = (try? memory.records(type: .preference)) ?? []
    let thresholds = ContextThresholds().applying(preferences)
    if latest.server?.available == false { warnings.append("sol-server 연결 불가") }
    if let disk = latest.server?.diskPercent, disk >= thresholds.diskWarning { warnings.append("서버 디스크 \(Int(disk))%") }
    if let memory = latest.server?.memoryPercent, memory >= thresholds.memoryWarning { warnings.append("서버 메모리 \(Int(memory))%") }
    warnings += latest.projects.filter { $0.changedFileCount >= thresholds.projectThreshold($0.name) }
      .map { "\($0.name) 변경 파일 \($0.changedFileCount)개" }
    return warnings.isEmpty ? "현재 특별한 경고는 없습니다." : warnings.joined(separator: "\n")
  }

  private func investigate(_ event: ProactiveEvent) async -> String? {
    guard event.suggestedAction == .getDockerLogs,
      ProactivePolicy.permission(for: .getDockerLogs) == .autoInvestigateReadOnly else { return nil }
    let parts = event.deduplicationKey.split(separator: ":")
    guard parts.count > 1 else { return nil }
    let container = String(parts[1])
    guard container.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$", options: .regularExpression) != nil else { return nil }
    return try? await ServerAgentClient.call(.logs, arguments: ["container": container, "lines": 50])
  }
}

private extension Array {
  func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
    var result: [T] = []; for item in self { result.append(await transform(item)) }; return result
  }
}
