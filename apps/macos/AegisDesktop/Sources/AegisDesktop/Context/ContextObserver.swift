import Foundation

@MainActor
final class ContextObserver {
  let interval: TimeInterval
  private(set) var lastObservation: Date?
  private(set) var isRunning = false
  private var task: Task<Void, Never>?
  private let operation: () async -> Void

  init(interval: TimeInterval = ContextObservationConfiguration.interval,
       operation: @escaping () async -> Void) {
    self.interval = interval; self.operation = operation
  }

  func start() {
    guard !isRunning, ContextObservationConfiguration.enabled else { return }
    isRunning = true
    task = Task { [weak self] in
      while let self, !Task.isCancelled {
        await self.runOnce()
        let nanoseconds = UInt64(max(1, self.interval) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
      }
    }
  }

  func runOnce() async {
    lastObservation = .now
    await operation()
  }

  func stop() { task?.cancel(); task = nil; isRunning = false }
  deinit { task?.cancel() }
}

enum ContextObservationConfiguration {
  static var enabled: Bool {
    ProcessInfo.processInfo.environment["AEGIS_CONTEXT_OBSERVATION_ENABLED"]?.lowercased() != "false"
  }
  static var interval: TimeInterval {
    Double(ProcessInfo.processInfo.environment["AEGIS_OBSERVATION_INTERVAL_SECONDS"] ?? "") ?? 60
  }
  static var cooldown: TimeInterval {
    Double(ProcessInfo.processInfo.environment["AEGIS_PROACTIVE_COOLDOWN_SECONDS"] ?? "") ?? 900
  }
  static var clipboardMetadataEnabled: Bool {
    ProcessInfo.processInfo.environment["AEGIS_CLIPBOARD_METADATA_ENABLED"]?.lowercased() == "true"
  }
}
