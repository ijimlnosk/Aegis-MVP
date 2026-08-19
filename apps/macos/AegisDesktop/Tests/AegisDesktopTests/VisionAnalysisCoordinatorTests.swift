import Foundation
import Testing
@testable import AegisDesktop

@Test func warningPressureForcesLowMemoryProfile() async throws {
  let coordinator = VisionAnalysisCoordinator(memory: FixedPressure(.warning))
  let lease = try await coordinator.begin(requested: .highQuality)
  #expect(lease.profile == .lowMemory)
  await coordinator.finish(lease)
}

@Test func criticalPressureBlocksInference() async {
  let coordinator = VisionAnalysisCoordinator(memory: FixedPressure(.critical))
  do { _ = try await coordinator.begin(requested: .lowMemory); Issue.record("Expected block") }
  catch let error as ScreenAnalysisError {
    guard case .memoryPressureCritical = error else { Issue.record("Wrong error"); return }
  } catch { Issue.record("Unexpected error") }
}

@Test func coordinatorAllowsOnlyOneVisionInference() async throws {
  let coordinator = VisionAnalysisCoordinator(memory: FixedPressure(.normal))
  let first = try await coordinator.begin(requested: .balanced)
  do { _ = try await coordinator.begin(requested: .balanced); Issue.record("Expected rejection") }
  catch let error as ScreenAnalysisError {
    guard case .concurrentRequest = error else { Issue.record("Wrong error"); return }
  }
  await coordinator.finish(first)
  let retry = try await coordinator.begin(requested: .lowMemory)
  #expect(retry.profile == .lowMemory)
  await coordinator.finish(retry)
}

private struct FixedPressure: VisionMemoryPressureProviding {
  let value: VisionMemoryPressure
  init(_ value: VisionMemoryPressure) { self.value = value }
  func current() -> VisionMemoryPressure { value }
}
