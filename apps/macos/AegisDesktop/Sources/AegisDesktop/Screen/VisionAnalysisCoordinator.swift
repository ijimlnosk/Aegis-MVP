import Foundation

struct VisionAnalysisLease: Sendable {
  let id: UUID
  let profile: VisionResourceProfile
  let pressure: VisionMemoryPressure
}

struct VisionAnalysisMetrics: Sendable {
  let dimensions: (Int, Int)
  let pixels: Int
  let encodedBytes: Int
  let inferenceDuration: Duration
}

actor VisionAnalysisCoordinator {
  private let memory: any VisionMemoryPressureProviding
  private var activeID: UUID?
  private(set) var lastMetrics: VisionAnalysisMetrics?
  private(set) var lastPressure: VisionMemoryPressure = .normal

  init(memory: any VisionMemoryPressureProviding = SystemMemoryPressure()) {
    self.memory = memory
  }

  func begin(requested: VisionResourceProfile?) throws -> VisionAnalysisLease {
    guard activeID == nil else { throw ScreenAnalysisError.concurrentRequest }
    let pressure = memory.current(); lastPressure = pressure
    guard pressure != .critical else { throw ScreenAnalysisError.memoryPressureCritical }
    let configured = requested ?? ScreenAnalysisConfiguration.resourceProfile()
    let profile: VisionResourceProfile = pressure == .warning ? .lowMemory : configured
    let id = UUID(); activeID = id
    return VisionAnalysisLease(id: id, profile: profile, pressure: pressure)
  }

  func finish(_ lease: VisionAnalysisLease, metrics: VisionAnalysisMetrics? = nil) {
    guard activeID == lease.id else { return }
    if let metrics { lastMetrics = metrics }
    activeID = nil
  }

  func status() -> (active: Bool, pressure: VisionMemoryPressure,
                    metrics: VisionAnalysisMetrics?) {
    (activeID != nil, memory.current(), lastMetrics)
  }
}
