import Foundation

struct ContextSnapshot: Codable, Identifiable, Equatable {
  let id: UUID
  let capturedAt: Date
  var mac: MacContext?
  var server: ServerContext?
  var projects: [ProjectContext]

  init(id: UUID = UUID(), capturedAt: Date = .now, mac: MacContext? = nil,
       server: ServerContext? = nil, projects: [ProjectContext] = []) {
    self.id = id; self.capturedAt = capturedAt; self.mac = mac
    self.server = server; self.projects = projects
  }
}

struct MacContext: Codable, Equatable {
  let activeApplication: String?
  let runningApplications: [String]
  let uptimeHours: Int
  let physicalMemoryGB: Double
  let clipboard: ClipboardMetadata?
}

struct ClipboardMetadata: Codable, Equatable {
  let hasText: Bool
  let characterCount: Int
}

struct ProjectContext: Codable, Equatable {
  let name: String
  let available: Bool
  let branch: String?
  let isDirty: Bool
  let changedFileCount: Int
}

struct ServerContext: Codable, Equatable {
  let available: Bool
  let uptime: String?
  let memoryPercent: Double?
  let diskPercent: Double?
  let containers: [DockerContext]
  let error: String?
}

struct DockerContext: Codable, Equatable {
  let name: String
  let state: String
  let isRunning: Bool
}
