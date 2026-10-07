import Foundation

/// Checks schedules every 30 seconds and runs a due one on the shared agent when it is idle.
/// A scheduled run never asks for approval (see `AegisAgent.scheduledRun`), so nothing
/// changes while the user is away; the result goes to the phone as a push.
@MainActor
final class ScheduledTaskRunner {
  let store: ScheduledTaskStore
  let reminders: ReminderStore
  private weak var agent: AegisAgent?
  private var timer: Timer?
  private var running = false

  init(store: ScheduledTaskStore = ScheduledTaskStore(), reminders: ReminderStore = ReminderStore()) {
    self.store = store; self.reminders = reminders
  }

  func start(agent: AegisAgent) {
    self.agent = agent
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  func stop() { timer?.invalidate(); timer = nil }

  func tick(now: Date = .now) {
    guard let agent else { return }
    deliverNotes(now: now, agent: agent)
    guard !running, agent.isIdle else { return }
    if runDueRequestReminder(now: now, agent: agent) { return }
    var tasks = store.load()
    guard let index = tasks.firstIndex(where: { $0.dueSlot(now: now) != nil }) else { return }
    tasks[index].lastRunAt = now
    try? store.save(tasks)
    run(tasks[index], label: tasks[index].timeText, on: agent)
  }

  /// Notes do not touch the agent, so they go out even while a command is running, late if need be.
  private func deliverNotes(now: Date, agent: AegisAgent) {
    let all = reminders.load()
    let due = all.filter { $0.fireAt <= now && { if case .note = $0.content { true } else { false } }($0) }
    guard !due.isEmpty else { return }
    for reminder in due {
      let late = now.timeIntervalSince(reminder.fireAt) > 120
        ? " (\(Int(now.timeIntervalSince(reminder.fireAt) / 60))분 늦게 전달)" : ""
      agent.chat.append(.assistant, "리마인더: \(reminder.summary)\(late)")
      agent.pushNotifier.send(PushMessages.reminder(reminder.summary + late))
    }
    try? reminders.save(all.filter { reminder in !due.contains { $0.id == reminder.id } })
  }

  private func runDueRequestReminder(now: Date, agent: AegisAgent) -> Bool {
    var all = reminders.load()
    guard let index = all.firstIndex(where: { $0.fireAt <= now && { if case .request = $0.content { true } else { false } }($0) }),
      case .request(let request) = all[index].content else { return false }
    let reminder = all.remove(at: index)
    try? reminders.save(all)
    let calendar = Calendar.current
    let task = ScheduledTask(id: reminder.id, request: request, hour: calendar.component(.hour, from: reminder.fireAt),
      minute: calendar.component(.minute, from: reminder.fireAt), weekdaysOnly: false)
    run(task, label: "한 번", on: agent)
    return true
  }

  private func run(_ task: ScheduledTask, label: String, on agent: AegisAgent) {
    running = true
    agent.scheduledRun = task
    agent.chat.append(.system, "예약 작업 실행 (\(label)): \(task.request)")
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
