import Foundation

struct ProjectEntity: Equatable {
  let name: String
  let aliases: [String]
  let path: String?

  init(name: String, aliases: [String], path: String? = nil) {
    self.name = name; self.aliases = aliases; self.path = path
  }
}

enum ProjectEntityResolver {
  static func knownProjects(repository: MemoryRepository,
                            environment: [String: String]? = nil) -> [ProjectEntity] {
    let environment = environment ?? registeredEnvironment()
    let definitions = [("Aegis-MVP", "AEGIS_MVP_PROJECT_ROOT"),
      ("PTFriends", "PTFRIENDS_PROJECT_ROOT"),
      ("SoolSool", "SOOLSOOL_PROJECT_ROOT"), ("sol-server", "SOL_SERVER_PROJECT_ROOT")]
    let configured = definitions.compactMap { name, key in
      environment[key]?.isEmpty == false ? name : nil
    }
    let memories = (try? repository.records()) ?? []
    var names: [String: String] = [:]
    for name in configured { names[name.lowercased()] = name }
    for memory in memories where memory.type == .project {
      names[memory.key.lowercased()] = displayName(memory.key)
    }
    return names.values.map { rawName in
      let name = displayName(rawName)
      let aliases = memories.filter { $0.type == .alias && equal($0.value, name) }.map(\.key)
      let key = definitions.first { equal($0.0, name) }?.1
      let registryPath = key.flatMap { environment[$0] }
      let memoryPath = memories.first { $0.type == .project && equal($0.key, name) }?.value
      return ProjectEntity(name: name, aliases: aliases, path: registryPath ?? memoryPath)
    }
  }

  static func resolve(in request: String, repository: MemoryRepository,
                      environment: [String: String]? = nil) -> ProjectEntity? {
    knownProjects(repository: repository, environment: environment).first { project in
      ([project.name] + project.aliases).contains { contains(request, $0) }
    }
  }

  static func isKnownProject(_ value: String, repository: MemoryRepository) -> Bool {
    knownProjects(repository: repository).contains { project in
      ([project.name] + project.aliases).contains { equal($0, value) }
    }
  }

  static func resolve(name: String, repository: MemoryRepository,
                      environment: [String: String]? = nil) -> ProjectEntity? {
    knownProjects(repository: repository, environment: environment).first { project in
      ([project.name] + project.aliases).contains { equal($0, name) }
    }
  }

  private static func contains(_ text: String, _ value: String) -> Bool {
    text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
  }
  private static func equal(_ lhs: String, _ rhs: String) -> Bool {
    lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
  }
  private static func displayName(_ value: String) -> String {
    let names = ["aegis-mvp": "Aegis-MVP", "ptfriends": "PTFriends",
      "soolsool": "SoolSool", "sol-server": "sol-server"]
    return names[value.lowercased()] ?? value
  }

  private static func registeredEnvironment() -> [String: String] {
    var values = ProcessInfo.processInfo.environment
    let candidates = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".env.local"),
      Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".env.local")]
    for url in candidates {
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      let projectRoot = url.deletingLastPathComponent()
      if values["AEGIS_MVP_PROJECT_ROOT"] == nil,
        projectRoot.lastPathComponent.compare("Aegis-MVP", options: .caseInsensitive) == .orderedSame,
        FileManager.default.fileExists(atPath: projectRoot.appending(path: ".git").path) {
        values["AEGIS_MVP_PROJECT_ROOT"] = projectRoot.path
      }
      for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2, !parts[0].hasPrefix("#"), values[parts[0]] == nil { values[parts[0]] = parts[1] }
      }
    }
    return values
  }
}
