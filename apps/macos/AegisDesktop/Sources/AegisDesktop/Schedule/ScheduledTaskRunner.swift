import Foundation

/// Checks schedules every 30 seconds and runs a due one on the shared agent when it is idle.
/// A scheduled run never asks for approval (see `AegisAgent.scheduledRun`), so nothing
/// changes while the user is away; the result goes to the phone as a push.
@MainActor
final class ScheduledTaskRunner {
  let store: ScheduledTaskStore
  private weak var agent: AegisAgent?
  private var timer: Timer?
  private var running = false

  init(store: ScheduledTaskStore = ScheduledTaskStore()) { self.store = store }

  func start(agent: AegisAgent) {
    self.agent = agent
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  func stop() { timer?.invalidate(); timer = nil }

  func tick(now: Date = .now) {
    guard !running, let agent, agent.isIdle else { return }
    var tasks = store.load()
    guard let index = tasks.firstIndex(where: { $0.dueSlot(now: now) != nil }) else { return }
    tasks[index].lastRunAt = now
    try? store.save(tasks)
    run(tasks[index], on: agent)
  }

  private func run(_ task: ScheduledTask, on agent: AegisAgent) {
    running = true
    agent.scheduledRun = task
    agent.chat.append(.system, "예약 작업 실행 (\(task.timeText)): \(task.request)")
    let start = agent.chat.messages.count
    agent.sendFromDesktop(task.request)
    Task { @MainActor [weak self, weak agent] in
      // Bounded wait so a stuck command cannot block later schedules forever.
      for _ in 0..<1_800 where !(agent?.isIdle ?? true) { try? await Task.sleep(for: .seconds(1)) }
      guard let agent else { self?.running = false; return }
      let replies = agent.chat.messages.dropFirst(start).filter { [.assistant, .error].contains($0.role) }
      let failed = replies.contains { $0.role == .error } || !agent.isIdle
      agent.pushNotifier.send(PushMessages.scheduled(request: task.request,
        result: replies.map(\.content).joined(separator: "\n"), succeeded: !failed))
      agent.scheduledRun = nil
      self?.running = false
    }
  }
}
