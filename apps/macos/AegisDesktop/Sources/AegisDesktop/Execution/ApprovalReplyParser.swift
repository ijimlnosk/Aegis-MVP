import Foundation

enum ApprovalReply: Equatable { case approve, cancel }

/// Reads a typed or spoken reply to a pending approval.
/// Approval needs the whole reply to be an approval word; substring matching let
/// unrelated messages such as "그래프 보여줘" or "응답이 느려" approve the action.
enum ApprovalReplyParser {
  static let approvals: Set<String> = ["실행", "진행", "승인", "응", "좋아", "그래", "네", "예",
    "실행해", "진행해", "승인해", "실행해줘", "진행해줘", "좋아요", "네좋아요", "응진행해"]
  static let cancels = ["취소", "그만", "하지마", "거절"]

  static func decision(_ text: String) -> ApprovalReply? {
    let compact = text.filter { !$0.isWhitespace && !".,!?~".contains($0) }
    // A false cancel only stops the action, so cancel words still match anywhere.
    if cancels.contains(where: compact.contains) { return .cancel }
    return approvals.contains(compact) ? .approve : nil
  }
}
