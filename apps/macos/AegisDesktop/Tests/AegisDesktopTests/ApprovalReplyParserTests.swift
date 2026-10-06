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
