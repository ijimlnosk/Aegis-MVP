import Foundation
import Testing
@testable import AegisDesktop

private func resolve(_ text: String) -> String? {
  text.contains("PTFriends") ? "PTFriends" : text.contains("SoolSool") ? "SoolSool" : nil
}

@Test func codeIntentParsesSearchAndFileRequests() {
  #expect(ProjectCodeIntentParser.parse("PTFriends에서 login 함수 찾아줘", project: resolve)
    == .search(project: "PTFriends", query: "login"))
  #expect(ProjectCodeIntentParser.parse("PTFriends에서 \"로그인 실패\" 문자열 검색해줘", project: resolve)
    == .search(project: "PTFriends", query: "로그인 실패"))
  #expect(ProjectCodeIntentParser.parse("SoolSool README 보여줘", project: resolve) == .read(project: "SoolSool", file: "README"))
  #expect(ProjectCodeIntentParser.parse("PTFriends src/app/page.tsx 보여줘", project: resolve)
    == .read(project: "PTFriends", file: "src/app/page.tsx"))
}

@Test func codeIntentLeavesOtherRequestsAlone() {
  #expect(ProjectCodeIntentParser.parse("PTFriends에서 개선할 부분 찾아줘", project: resolve) == nil)
  #expect(ProjectCodeIntentParser.parse("PTFriends 상태 보여줘", project: resolve) == nil)
  #expect(ProjectCodeIntentParser.parse("PTFriends 위치 찾아줘", project: resolve) == nil)
  #expect(ProjectCodeIntentParser.parse("Unknown에서 login 찾아줘", project: resolve) == nil)
}

@Test func fileMatchingPrefersExactPathsAndBlocksSecrets() {
  let tracked = ["README.md", "docs/README.md", "src/app/page.tsx", ".env.example", "config/app.key"]
  #expect(ProjectCodeReader.matches(for: "src/app/page.tsx", in: tracked) == ["src/app/page.tsx"])
  #expect(ProjectCodeReader.matches(for: "README", in: tracked) == ["README.md", "docs/README.md"])
  #expect(ProjectCodeReader.isSecretPath(".env.example"))
  #expect(ProjectCodeReader.isSecretPath("config/app.key"))
  #expect(!ProjectCodeReader.isSecretPath("src/app/page.tsx"))
}

@Test func searchAndReadStayInsideTrackedFiles() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  try "export function login() {}\nconst token = \"abc123secretvalue\"\n".write(to: root.appendingPathComponent("auth.ts"),
    atomically: true, encoding: .utf8)
  try "API_KEY=topsecret\n".write(to: root.appendingPathComponent(".env.local"), atomically: true, encoding: .utf8)
  try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
  try "nested".write(to: root.appendingPathComponent("docs/GUIDE.md"), atomically: true, encoding: .utf8)
  try "top".write(to: root.appendingPathComponent("GUIDE.md"), atomically: true, encoding: .utf8)
  _ = try ProjectCommandPolicy.run("/usr/bin/git", ["add", "auth.ts", "GUIDE.md", "docs/GUIDE.md"], at: root)
  #expect(try ProjectCodeReader.read("GUIDE", project: "P", root: root).hasSuffix("top"))
  let found = try ProjectCodeReader.search("login", project: "P", root: root)
  #expect(found.contains("auth.ts:1:"))
  #expect(try ProjectCodeReader.search("topsecret", project: "P", root: root).contains("찾지 못했습니다"))
  let shown = try ProjectCodeReader.read("auth.ts", project: "P", root: root)
  #expect(shown.contains("login") && !shown.contains("abc123secretvalue"))
  #expect(try ProjectCodeReader.read(".env.local", project: "P", root: root).contains("찾지 못했습니다"))
}
