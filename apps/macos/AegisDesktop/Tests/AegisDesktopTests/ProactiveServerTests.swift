import Testing
@testable import AegisDesktop

@Test func noEventBelowThresholdAndCrossingEmitsOnce() {
  let low = snapshot(server: server(memory: 50, disk: 79))
  let warning = snapshot(server: server(memory: 60, disk: 81))
  #expect(ProactiveDetector.detect(previous: low, current: low, thresholds: .init()).isEmpty)
  let events = ProactiveDetector.detect(previous: low, current: warning, thresholds: .init())
  #expect(events.map(\.type).contains(.diskHigh))
  #expect(ProactiveDetector.detect(previous: warning,
    current: snapshot(server: server(memory: 60, disk: 83)), thresholds: .init()).isEmpty)
}

@Test func criticalEscalationCreatesNewEvent() {
  let warning = snapshot(server: server(memory: 80, disk: 83))
  let critical = snapshot(server: server(memory: 80, disk: 92))
  let event = ProactiveDetector.detect(previous: warning, current: critical, thresholds: .init())
    .first { $0.type == .diskHigh }
  #expect(event?.severity == .critical)
}

@Test func serverUnreachableAndRecoveryAreExplicit() {
  let online = snapshot(server: server(memory: 20, disk: 30))
  let offline = snapshot(server: ServerContext(available: false, uptime: nil,
    memoryPercent: nil, diskPercent: nil, containers: [], error: "offline"))
  #expect(ProactiveDetector.detect(previous: online, current: offline,
    thresholds: .init()).map(\.type) == [.serverUnavailable])
  #expect(ProactiveDetector.detect(previous: offline, current: online,
    thresholds: .init()).map(\.type) == [.serverRecovered])
}

@Test func dockerRunningToStoppedSuggestsLogsOnly() {
  let running = DockerContext(name: "dksfhomepage", state: "Up 2 hours", isRunning: true)
  let stopped = DockerContext(name: "dksfhomepage", state: "Exited (1)", isRunning: false)
  let old = snapshot(server: server(containers: [running]))
  let new = snapshot(server: server(containers: [stopped]))
  let event = ProactiveDetector.detect(previous: old, current: new, thresholds: .init()).first
  #expect(event?.type == .containerStopped)
  #expect(event?.suggestedAction == .getDockerLogs)
  #expect(ProactivePolicy.mayAutoExecute(.restartDockerContainer) == false)
}

@Test func preferenceOverridesDefaultDiskThreshold() {
  let preference = MemoryRecord(type: .preference, key: "alert_disk_percent", value: "90")
  let thresholds = ContextThresholds().applying([preference])
  let old = snapshot(server: server(disk: 79))
  #expect(ProactiveDetector.detect(previous: old,
    current: snapshot(server: server(disk: 85)), thresholds: thresholds).isEmpty)
  #expect(ProactiveDetector.detect(previous: old,
    current: snapshot(server: server(disk: 91)), thresholds: thresholds).contains { $0.type == .diskHigh })
}

private func snapshot(server: ServerContext) -> ContextSnapshot { ContextSnapshot(server: server) }
private func server(memory: Double = 20, disk: Double = 30,
                    containers: [DockerContext] = []) -> ServerContext {
  ServerContext(available: true, uptime: "1 day", memoryPercent: memory,
    diskPercent: disk, containers: containers, error: nil)
}
