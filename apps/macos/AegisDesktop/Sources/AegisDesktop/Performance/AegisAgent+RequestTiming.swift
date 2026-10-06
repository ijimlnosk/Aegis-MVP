import Foundation

extension AegisAgent {
  /// Deferred one turn because routing often flips `busy` off right before `execute` turns it back on.
  func scheduleTimingFinish() {
    guard requestTiming != nil else { return }
    Task { @MainActor [weak self] in self?.finishRequestTimingIfSettled() }
  }

  /// Approval waits end the measurement so human response time is never counted as Aegis latency.
  func finishRequestTimingIfSettled() {
    guard let timing = requestTiming else { return }
    let outcome: String
    if pendingMacAction != nil || pendingKakaoMessage != nil { outcome = "awaitingApproval" }
    else if busy || planExecutor != nil { return }
    else { outcome = chat.messages.last?.role == .error ? "failed" : "completed" }
    requestTiming = nil
    timingStore.append(timing.finish(outcome: outcome))
  }
}
