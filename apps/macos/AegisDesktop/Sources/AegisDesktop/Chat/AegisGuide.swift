import Foundation

/// The single usage guide behind "/help" and "뭐 할 수 있어?". Every quoted line is a sentence
/// the user can send as-is; `examples` is also what the routing tests replay.
enum AegisGuide {
  struct Example { let text: String; let approval: Bool }

  static let sections: [(title: String, examples: [Example])] = [
    ("프로젝트", [.init(text: "PTFriends 상태 보여줘", approval: false),
      .init(text: "PTFriends lint 검사해줘", approval: false),
      .init(text: "PTFriends에서 login 찾아줘", approval: false),
      .init(text: "PTFriends README 보여줘", approval: false)]),
    ("코딩 (Codex)", [.init(text: "PTFriends 개선할 부분 찾아줘", approval: false),
      .init(text: "PTFriends lint 오류 고쳐줘", approval: true)]),
    ("Git", [.init(text: "PTFriends CI 상태 보여줘", approval: false),
      .init(text: "PTFriends 커밋 계획 세워줘", approval: false)]),
    ("서버", [.init(text: "sol-server 상태 보여줘", approval: false),
      .init(text: "ntfy 컨테이너 재시작해줘", approval: true)]),
    ("예약 · 폰 알림", [.init(text: "매일 아침 9시에 PTFriends 상태 알려줘", approval: false),
      .init(text: "예약 목록 보여줘", approval: false)]),
    ("감시 · 폰 알림", [.init(text: "PTFriends CI 끝나면 알려줘", approval: false),
      .init(text: "sol-server 복구되면 알려줘", approval: false),
      .init(text: "감시 목록 보여줘", approval: false)]),
    ("Mac", [.init(text: "현재 창 설명해줘", approval: false),
      .init(text: "VS Code 열어줘", approval: true)]),
    ("기억", [.init(text: "뭘 기억하고 있어?", approval: false)]),
  ]

  static func text(commands: [SlashCommand] = SlashCommand.allCases) -> String {
    let body = sections.map { section in
      ([section.title] + section.examples.map { "  \"\($0.text)\"" + ($0.approval ? " [승인]" : "") })
        .joined(separator: "\n")
    }.joined(separator: "\n\n")
    let slash = commands.map { "  \($0.usage)  \($0.summary)" }.joined(separator: "\n")
    return "Aegis에게 아래처럼 말하면 됩니다. [승인]은 실행 전에 확인을 받습니다.\n"
      + "검증(lint·test 등)은 허용 목록 프로젝트만 바로 실행하고 나머지는 승인을 받습니다.\n\n"
      + body + "\n\n명령어\n" + slash
  }
}
