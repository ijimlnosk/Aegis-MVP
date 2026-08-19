import Foundation

@MainActor
extension AegisAgent {
  func restoreProactivePreferences() {
    let records = (try? memoryStore.repository.records(type: .preference)) ?? []
    for record in records where record.key.hasPrefix("proactive_suppress_") && record.value == "true" {
      let raw = String(record.key.dropFirst("proactive_suppress_".count))
      if let type = ProactiveEventType(rawValue: raw) {
        proactiveCoordinator.proactiveStore.suppressedTypes.insert(type)
      }
    }
  }

  func handleProactiveIntent(_ intent: ProactiveIntent) -> String {
    switch intent {
    case .status: return proactiveCoordinator.summary()
    case .diagnostics:
      let latest = try? proactiveCoordinator.contextStore.snapshots(limit: 1).first
      let time = contextObserver.lastObservation?.formatted() ?? "없음"
      let source = latest.map { "mac=\($0.mac != nil), server=\($0.server?.available == true), projects=\($0.projects.count)" } ?? "snapshot 없음"
      let active = proactiveCoordinator.activeConditions.keys.sorted().joined(separator: ", ")
      return "관찰 간격: \(Int(contextObserver.interval))초\n마지막 관찰: \(time)\n\(source)\n활성 조건: \(active.isEmpty ? "없음" : active)"
    case .quiet(let duration, let scope):
      proactiveCoordinator.proactiveStore.quietMode = QuietMode(scope: scope, until: .now.addingTimeInterval(duration))
      return scope == .server ? "오늘 서버 알림을 조용히 하겠습니다." : "요청한 시간 동안 알림을 조용히 하겠습니다."
    case .resume:
      proactiveCoordinator.proactiveStore.quietMode = nil
      return "Proactive 알림을 다시 표시합니다."
    case .threshold(let key, let value):
      _ = try? memoryStore.repository.save(MemoryRecord(type: .preference, key: key,
        value: String(value), source: "user"))
      return "알림 기준을 저장했습니다: \(key) = \(Int(value))"
    case .suppressLast:
      guard let event = proactiveCoordinator.proactiveStore.lastEvent else { return "숨길 최근 알림이 없습니다." }
      proactiveCoordinator.proactiveStore.suppressedTypes.insert(event.type)
      _ = try? memoryStore.repository.save(MemoryRecord(type: .preference,
        key: "proactive_suppress_\(event.type.rawValue)", value: "true", source: "user"))
      return "앞으로 같은 종류의 알림은 표시하지 않겠습니다."
    }
  }

  func surface(_ notices: [ProactiveNotice]) {
    for notice in notices {
      let event = notice.event
      chat.append(event.severity == .critical ? .error : .assistant,
        "\(event.message)\n근거: \(event.evidence)")
      if let investigation = notice.investigation {
        chat.append(.assistant, "읽기 전용 자동 조사 결과:\n\(String(investigation.prefix(2_000)))")
      } else if event.suggestedAction != nil {
        chat.append(.system, "제안: 최근 Docker 로그를 확인할 수 있습니다.")
      }
    }
  }
}
