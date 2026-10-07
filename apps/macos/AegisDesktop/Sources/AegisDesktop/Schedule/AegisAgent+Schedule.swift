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
      saveSchedules(tasks, store: store, success: "\(task.timeText)에 '\(request)' 요청을 실행하고 결과를 폰으로 알려드릴게요."
        + " 승인이 필요한 작업은 예약 실행에서 하지 않습니다."
        + (pushNotifier.configuration == nil ? " (알림 서버가 설정되지 않아 결과는 Mac 창에만 표시됩니다.)" : ""))
    }
  }

  private func saveSchedules(_ tasks: [ScheduledTask], store: ScheduledTaskStore, success: String) {
    do { try store.save(tasks); speak(success) }
    catch { speak("예약을 저장하지 못했습니다: \(error.localizedDescription)", role: .error) }
  }
}

extension AegisAgent {
  func handleReminder(_ intent: ReminderIntent) {
    let store = scheduleRunner.reminders
    var reminders = store.load()
    switch intent {
    case .list:
      speak(reminders.isEmpty ? "예정된 리마인더가 없습니다." : "리마인더:\n" + reminders.enumerated().map {
        "\($0.offset + 1). \(Self.when($0.element.fireAt)) · \($0.element.summary)"
      }.joined(separator: "\n"))
    case .cancel(let index):
      guard reminders.indices.contains(index - 1) else { speak("\(index)번 리마인더가 없습니다.", role: .error); return }
      let removed = reminders.remove(at: index - 1)
      saveReminders(reminders, store: store, success: "\(Self.when(removed.fireAt)) 리마인더를 취소했습니다.")
    case .create(let content, let fireAt):
      guard reminders.count < ReminderStore.maximum else {
        speak("리마인더는 최대 \(ReminderStore.maximum)개까지 만들 수 있습니다.", role: .error); return
      }
      let reminder = Reminder(id: UUID(), content: content, fireAt: fireAt)
      reminders.append(reminder)
      let what: String = switch content {
      case .note(let text): text.isEmpty ? "알려드릴게요." : "'\(text)'라고 알려드릴게요."
      case .request(let request): "'\(request)' 요청을 실행하고 결과를 알려드릴게요. 승인이 필요한 작업은 하지 않습니다."
      }
      saveReminders(reminders, store: store, success: "\(Self.when(fireAt))에 \(what)"
        + (pushNotifier.configuration == nil ? " (알림 서버가 설정되지 않아 Mac 창에만 표시됩니다.)" : ""))
    }
  }

  static func when(_ date: Date) -> String {
    let calendar = Calendar.current
    let day = calendar.isDateInToday(date) ? "오늘" : calendar.isDateInTomorrow(date) ? "내일"
      : date.formatted(.dateTime.month().day())
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return "\(day) " + String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
  }

  private func saveReminders(_ reminders: [Reminder], store: ReminderStore, success: String) {
    do { try store.save(reminders); speak(success) }
    catch { speak("리마인더를 저장하지 못했습니다: \(error.localizedDescription)", role: .error) }
  }
}
