import Foundation

// Serializes all Ollama calls app-wide (planning, screen analysis, kakao decisions, ...)
// through a single-slot queue. A waiter's wait is itself bounded: if whatever is
// currently holding the slot never releases it (e.g. a network call that hangs instead
// of failing fast), queued callers time out instead of blocking forever -- previously
// a single stuck holder wedged every subsequent Ollama-backed command indefinitely.
actor OllamaInferenceCoordinator {
  static let shared = OllamaInferenceCoordinator()

  private var active = false
  private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

  func perform<T: Sendable>(
    waitTimeout: TimeInterval = 60,
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    guard await acquire(waitTimeout: waitTimeout) else { throw OllamaBackendError.timeout }
    do {
      try Task.checkCancellation()
      let result = try await operation()
      release()
      return result
    } catch {
      release()
      throw error
    }
  }

  func status() -> (active: Bool, queued: Int) { (active, waiters.count) }

  private func acquire(waitTimeout: TimeInterval) async -> Bool {
    guard active else { active = true; return true }
    let id = UUID()
    return await withCheckedContinuation { continuation in
      waiters.append((id, continuation))
      Task { try? await Task.sleep(for: .seconds(waitTimeout)); await self.expire(id) }
    }
  }

  private func expire(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(returning: false)
  }

  private func release() {
    guard !waiters.isEmpty else { active = false; return }
    waiters.removeFirst().continuation.resume(returning: true)
  }
}
