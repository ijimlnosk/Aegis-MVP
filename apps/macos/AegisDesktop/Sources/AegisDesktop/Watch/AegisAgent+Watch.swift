import Foundation

extension AegisAgent {
  func handleWatch(_ intent: WatchIntent) {
    let store = watchRunner.store
    var tasks = store.load()
    switch intent {
    case .list:
      speak(tasks.isEmpty ? "감시 중인 조건이 없습니다." : "감시 중:\n" + tasks.enumerated().map {
        "\($0.offset + 1). \($0.element.kind.label) · \($0.element.expiresAt.formatted(date: .omitted, time: .shortened))까지"
      }.joined(separator: "\n"))
    case .cancel(let index):
      guard tasks.indices.contains(index - 1) else { speak("\(index)번 감시가 없습니다.", role: .error); return }
      let removed = tasks.remove(at: index - 1)
      saveWatches(tasks, store: store, success: "\(removed.kind.label) 감시를 취소했습니다.")
    case .create(let kind):
      guard tasks.count < WatchTaskStore.maximumTasks else {
        speak("감시는 최대 \(WatchTaskStore.maximumTasks)개까지 할 수 있습니다.", role: .error); return
      }
      guard !tasks.contains(where: { $0.kind == kind }) else { speak("이미 \(kind.label) 여부를 감시하고 있습니다."); return }
      startWatch(kind, store: store)
    }
  }

  /// Checks once before saving so an already-met or broken condition is answered right away.
  private func startWatch(_ kind: WatchKind, store: WatchTaskStore) {
    busy = true
    Task {
      let outcome = await WatchEvaluator.evaluate(kind, repository: memoryStore.repository)
      busy = false
      switch outcome {
      case .met(let message): speak("이미 조건이 충족돼 있습니다. \(message)")
      case .broken(let reason): speak(reason, role: .error)
      case .waiting:
        var tasks = store.load()
        tasks.append(WatchTask(id: UUID(), kind: kind, expiresAt: .now.addingTimeInterval(WatchTask.lifetime)))
        saveWatches(tasks, store: store, success: "\(kind.label) 여부를 1분마다 확인하다가 충족되면 폰으로 알려드릴게요. 최대 6시간 동안 감시합니다."
          + (pushNotifier.configuration == nil ? " (알림 서버가 설정되지 않아 Mac 창에만 표시됩니다.)" : ""))
      }
    }
  }

  private func saveWatches(_ tasks: [WatchTask], store: WatchTaskStore, success: String) {
    do { try store.save(tasks); speak(success) }
    catch { speak("감시를 저장하지 못했습니다: \(error.localizedDescription)", role: .error) }
  }
}
