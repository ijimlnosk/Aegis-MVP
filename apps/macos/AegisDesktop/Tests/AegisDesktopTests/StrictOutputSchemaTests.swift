import Foundation
import Testing
@testable import AegisDesktop

private func object(_ value: Any?) throws -> [String: Any] { try #require(value as? [String: Any]) }

@Test func strictSchemaRequiresEveryPropertyAndForbidsExtras() throws {
  let strict = StrictOutputSchema.make(AgentPlanner.schema)
  #expect(strict["additionalProperties"] as? Bool == false)
  #expect(strict["required"] as? [String] == ["finalAnswer", "steps"])
  let steps = try object(try object(strict["properties"])["steps"])
  let step = try object(steps["items"])
  let properties = try object(step["properties"])
  #expect(step["additionalProperties"] as? Bool == false)
  #expect(Set(step["required"] as? [String] ?? []) == Set(properties.keys))
}

@Test func strictSchemaKeepsRequiredFieldsAndMakesOptionalOnesNullable() throws {
  let strict = StrictOutputSchema.make(AgentPlanner.schema)
  let step = try object(try object(try object(strict["properties"])["steps"])["items"])
  let properties = try object(step["properties"])
  #expect(try object(properties["action"])["type"] as? String == "string")
  #expect(try object(properties["query"])["type"] as? [String] == ["string", "null"])
  let shortcut = try #require(try object(properties["shortcut"])["enum"] as? [Any])
  #expect(shortcut.contains { $0 is NSNull })
  #expect(try object(properties["lines"])["maximum"] as? Int == 1000)
}

@Test func codexStrictOutputWithNullFieldsDecodesToPlan() throws {
  let json = """
  {"finalAnswer":null,"steps":[{"action":"get_system_status","dependency":"independent","project":null,
  "shortcut":null,"lines":null,"query":"","codingMode":null,"inputPurpose":null,"scrollDirection":null}]}
  """
  let plan = try JSONDecoder().decode(AgentPlan.self, from: Data(json.utf8))
  #expect(plan.steps.map(\.action) == [.getSystemStatus])
  #expect(plan.steps.first?.shortcut == nil)
  #expect(plan.finalAnswer == nil)
}
