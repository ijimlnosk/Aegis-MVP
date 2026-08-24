import Foundation

actor UIInteractionCoordinator {
  private var active = false
  private(set) var currentTarget: String?

  func perform<T: Sendable>(target: String?,
    _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    guard !active else { throw UIInteractionError.timedOut }
    active = true; currentTarget = target
    defer { active = false; currentTarget = nil }
    return try await operation()
  }

  func status() -> (active: Bool, target: String?) { (active, currentTarget) }
}
