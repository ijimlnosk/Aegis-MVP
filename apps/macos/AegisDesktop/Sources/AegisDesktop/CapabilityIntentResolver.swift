import Foundation

enum CapabilityIntentResolver {
  static func plan(for request: String) -> AgentPlan? {
    let normalized = request.lowercased().filter { $0.isLetter || $0.isNumber }
    let capabilityQuestion = [
      "뭘할수있", "뭐할수있", "무엇을할수있", "할수있는기능", "어떤기능",
      "할수있는게뭐", "할수있는건뭐", "할수있는것이뭐", "기능이뭐", "기능뭐",
      "도움말", "사용법", "whatcanyoudo", "capabilities",
    ].contains { normalized.contains($0) }
    guard capabilityQuestion else { return nil }
    return AgentPlan(steps: [], finalAnswer: answer)
  }

  private static let answer = """
  지금은 다음 기능을 사용할 수 있습니다.

  • 현재 창·전체 화면·지정한 앱 창을 읽고 설명하기
  • 열린 창, 실행 중인 앱, Mac 상태와 클립보드 확인하기
  • 등록된 프로젝트의 Git 상태, 변경 파일, 커밋과 개발 상태 확인하기
  • 프로젝트 테스트, 타입 검사, 린트와 빌드 실행하기
  • sol-server와 Docker 컨테이너 상태 및 로그 확인하기
  • 앱·프로젝트·웹사이트 열기와 웹 검색하기
  • 메모리, 프로젝트 별칭과 기본 브라우저 기억하기

  읽기 작업은 바로 수행할 수 있습니다. 앱 종료, 클립보드 변경, 메시지 전송,
  Docker 변경처럼 상태를 바꾸는 작업은 실행 전에 확인을 요청합니다.
  "현재 창 설명해줘" 또는 "PTFriends 상태 보여줘"처럼 말해 보세요.
  """
}
