import Foundation

extension AegisAgent {
  /// No command running and nothing waiting for approval.
  var isIdle: Bool { !busy && planExecutor == nil && pendingMacAction == nil }

  func handleSchedule(_ intent: ScheduleIntent) {
    let store = scheduleRunner.store
    var tasks = store.load()
    switch intent {
    case .list:
      speak(tasks.isEmpty ? "예약된 작업이 없습니다." : "예약된 작업:\n" + tasks.enumerated()
        .map { "\($0.offset + 1). \($0.element.timeText) · \($0.element.request)" }.joined(separator: "\n"))
    case .delete(let index):
      guard tasks.indices.contains(index - 1) else { speak("\(index)번 예약이 없습니다.", role: .error); return }
      let removed = tasks.remove(at: index - 1)
      saveSchedules(tasks, store: store, success: "\(removed.timeText) · \(removed.request) 예약을 삭제했습니다.")
    case .create(let request, let hour, let minute, let weekdaysOnly):
      guard tasks.count < ScheduledTaskStore.maximumTasks else {
        speak("예약은 최대 \(ScheduledTaskStore.maximumTasks)개까지 만들 수 있습니다.", role: .error); return
      }
      let task = ScheduledTask(id: UUID(), request: request, hour: hour, minute: minute,
        weekdaysOnly: weekdaysOnly, lastRunAt: .now)
      tasks.append(task)
      saveSchedules(tasks, store: store, success: "\(task.timeText)에 '\(request)'을 실행하고 결과를 폰으로 알려드릴게요."
        + " 승인이 필요한 작업은 예약 실행에서 하지 않습니다."
        + (pushNotifier.configuration == nil ? " (알림 서버가 설정되지 않아 결과는 Mac 창에만 표시됩니다.)" : ""))
    }
  }

  private func saveSchedules(_ tasks: [ScheduledTask], store: ScheduledTaskStore, success: String) {
    do { try store.save(tasks); speak(success) }
    catch { speak("예약을 저장하지 못했습니다: \(error.localizedDescription)", role: .error) }
  }
}
