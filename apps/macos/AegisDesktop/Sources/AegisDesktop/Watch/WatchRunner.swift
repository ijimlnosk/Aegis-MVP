import Foundation

/// Re-checks every watch once a minute and pushes when its condition is met, the check
/// breaks, or the 6-hour lifetime runs out. Checks are read-only and never touch the plan executor.
@MainActor
final class WatchRunner {
  let store: WatchTaskStore
  private weak var agent: AegisAgent?
  private var timer: Timer?
  private var checking = false

  init(store: WatchTaskStore = WatchTaskStore()) { self.store = store }

  func start(agent: AegisAgent) {
    self.agent = agent
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.tick() }
    }
  }

  func stop() { timer?.invalidate(); timer = nil }

  func tick(now: Date = .now) async {
    guard !checking, let agent else { return }
    let tasks = store.load()
    guard !tasks.isEmpty else { return }
    checking = true; defer { checking = false }
    var remaining: [WatchTask] = []
    for task in tasks {
      if now >= task.expiresAt {
        finish(task, message: "\(task.kind.label) 감시를 6시간 만에 종료했습니다. 조건이 아직 충족되지 않았습니다.",
          succeeded: false, agent: agent)
        continue
      }
      switch await WatchEvaluator.evaluate(task.kind, repository: agent.memoryStore.repository) {
      case .waiting: remaining.append(task)
      case .met(let message): finish(task, message: message, succeeded: true, agent: agent)
      case .broken(let reason): finish(task, message: reason, succeeded: false, agent: agent)
      }
    }
    // Watches added while checking must survive, so only finished ids are removed.
    let finished = Set(tasks.map(\.id)).subtracting(remaining.map(\.id))
    try? store.save(store.load().filter { !finished.contains($0.id) })
  }

  private func finish(_ task: WatchTask, message: String, succeeded: Bool, agent: AegisAgent) {
    agent.chat.append(succeeded ? .assistant : .error, "감시 알림: \(message)")
    agent.pushNotifier.send(PushMessages.watch(label: task.kind.label, message: message, succeeded: succeeded))
  }
}
