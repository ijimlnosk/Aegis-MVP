import Testing
@testable import AegisDesktop

@Test func onlyWholeApprovalRepliesApprove() {
  for reply in ["승인", "응", "네 좋아요", "진행해!", " 실행 "] {
    #expect(ApprovalReplyParser.decision(reply) == .approve)
  }
  for reply in ["그래프 보여줘", "응답이 왜 느려?", "실행 결과 알려줘", "PTFriends 진행 상황"] {
    #expect(ApprovalReplyParser.decision(reply) == nil)
  }
}

@Test func cancelWordsWinAnywhere() {
  #expect(ApprovalReplyParser.decision("취소") == .cancel)
  #expect(ApprovalReplyParser.decision("진행하지마") == .cancel)
  #expect(ApprovalReplyParser.decision("그건 거절할게") == .cancel)
}

@Test func approvalPresentationNamesTheActionAndFlagsIrreversibleOnes() {
  let kakao = ApprovalPresentation.present(kind: "kakao_message")
  #expect(kakao.confirmLabel == "보내기" && kakao.irreversible)
  #expect(!ApprovalPresentation.present(kind: "create_commit").irreversible)
  #expect(ApprovalPresentation.present(kind: "run_project_lint").confirmLabel == "실행")
  #expect(ApprovalPresentation.present(kind: "set_ui_text").confirmLabel == "진행")
  #expect(ApprovalPresentation.present(kind: nil).confirmLabel == "승인")
}

@Test func everyActionHasAKoreanDisplayName() {
  for action in AgentAction.allCases {
    #expect(!action.displayName.isEmpty)
    #expect(!action.displayName.contains("_"))
  }
}
