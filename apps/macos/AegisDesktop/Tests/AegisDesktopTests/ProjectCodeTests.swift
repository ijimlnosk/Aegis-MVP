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
  #expect(found.contains("auth.ts\n    1  export function login()"))
  #expect(try ProjectCodeReader.search("topsecret", project: "P", root: root).contains("찾지 못했습니다"))
  let shown = try ProjectCodeReader.read("auth.ts", project: "P", root: root)
  #expect(shown.contains("login") && !shown.contains("abc123secretvalue"))
  #expect(try ProjectCodeReader.read(".env.local", project: "P", root: root).contains("찾지 못했습니다"))
}

@Test func searchResultsGroupByFileInsideACodeBlock() {
  let output = "src/a.ts:3:login()\nsrc/a.ts:10:  const x = login\nsrc/b.ts:1:import { login }"
  let text = ProjectCodeReader.formatSearch(output, query: "login", project: "P")
  #expect(text.hasPrefix("P에서 'login' · 3곳 (파일 2개)"))
  #expect(text.contains("```\nsrc/a.ts\n    3  login()\n   10  const x = login\n\nsrc/b.ts\n    1  import { login }\n```"))
}

@Test func fileViewNumbersCodeButLeavesProseAsText() {
  let code = ProjectCodeReader.formatFile("a\nb", path: "src/x.ts", project: "P")
  #expect(code == "P/src/x.ts · 2줄\n```\n1  a\n2  b\n```")
  let prose = ProjectCodeReader.formatFile("# Title", path: "README.md", project: "P")
  #expect(prose == "P/README.md · 1줄\n\n# Title")
}

@Test func messageSegmentsSplitFencesAndTolerateTruncation() {
  #expect(MessageSegments.split("결과\n```\nline 1\n  line 2\n```\n끝")
    == [.text("결과"), .code("line 1\n  line 2"), .text("끝")])
  #expect(MessageSegments.split("머리\n```\ncut off") == [.text("머리"), .code("cut off")])
  #expect(MessageSegments.split("plain") == [.text("plain")])
}

@Test func textTableRealignsDockerAndFreeOutput() {
  #expect(TextTable.columns("web\tUp 3 hours\t127.0.0.1:3201\nntfy\tUp 22 hours\t100.74.88.48:8080")
    == "web   Up 3 hours   127.0.0.1:3201\nntfy  Up 22 hours  100.74.88.48:8080")
  let free = "total        used\nMem:           7.6Gi       3.5Gi"
  #expect(TextTable.rightAlignHeader(free) == "               total        used\nMem:           7.6Gi       3.5Gi")
  #expect(TextTable.columns("no tabs here") == "no tabs here")
}

@Test func serverStatusRawLayoutStaysParseableWhileChatViewIsFormatted() {
  let raw = "sol-server\nUptime: up 2 days\nMemory:\ntotal  used\nMem:   7.6Gi  3.5Gi\nDisk:\n/dev/a  98G  52G  42G  56% /\nDocker:\nntfy\tUp 22 hours"
  #expect(DockerInventoryParser.parse("ntfy\tUp 22 hours").first?.name == "ntfy")
  let view = ServerResultFormatter.display(.status, raw: raw)
  #expect(view.hasPrefix("sol-server · up 2 days"))
  #expect(view.contains("```\nntfy  Up 22 hours\n```"))
  #expect(ServerResultFormatter.display(.containers, raw: "ntfy\tUp\nweb\tUp 3 hours") == "```\nntfy  Up\nweb   Up 3 hours\n```")
}
