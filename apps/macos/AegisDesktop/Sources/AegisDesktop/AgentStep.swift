import Foundation

enum StepDependency: String, Codable {
  case independent
  case requiresPreviousSuccess = "requires_previous_success"
}

struct AgentStep: Codable, Identifiable {
  let id: UUID
  let action: AgentAction
  let dependency: StepDependency
  let recipient: String?
  let body: String?
  let application: String?
  let browser: String?
  let site: String?
  let query: String?
  let content: String?
  let project: String?
  let container: String?
  let lines: Int?

  init(id: UUID = UUID(), action: AgentAction, dependency: StepDependency = .independent,
       recipient: String? = nil, body: String? = nil, application: String? = nil,
       browser: String? = nil, site: String? = nil, query: String? = nil,
       content: String? = nil, project: String? = nil, container: String? = nil,
       lines: Int? = nil) {
    self.id = id; self.action = action; self.dependency = dependency
    self.recipient = recipient; self.body = body; self.application = application
    self.browser = browser; self.site = site; self.query = query; self.content = content
    self.project = project; self.container = container; self.lines = lines
  }

  private enum CodingKeys: String, CodingKey {
    case action, dependency, recipient, body, application, browser, site, query, content, project, container, lines
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(action: try values.decode(AgentAction.self, forKey: .action),
      dependency: try values.decodeIfPresent(StepDependency.self, forKey: .dependency) ?? .independent,
      recipient: try values.decodeIfPresent(String.self, forKey: .recipient),
      body: try values.decodeIfPresent(String.self, forKey: .body),
      application: try values.decodeIfPresent(String.self, forKey: .application),
      browser: try values.decodeIfPresent(String.self, forKey: .browser), site: try values.decodeIfPresent(String.self, forKey: .site),
      query: try values.decodeIfPresent(String.self, forKey: .query), content: try values.decodeIfPresent(String.self, forKey: .content),
      project: try values.decodeIfPresent(String.self, forKey: .project), container: try values.decodeIfPresent(String.self, forKey: .container),
      lines: try values.decodeIfPresent(Int.self, forKey: .lines))
  }
}
