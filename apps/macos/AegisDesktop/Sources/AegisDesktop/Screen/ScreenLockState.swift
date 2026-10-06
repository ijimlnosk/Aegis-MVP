import CoreGraphics
import Foundation

/// Screen capture, Accessibility control, and KakaoTalk automation cannot work behind the lock screen,
/// so those steps stop early with a clear reason instead of failing midway.
enum ScreenLockState {
  static let lockedMessage = "Mac 화면이 잠겨 있어 화면·UI·카카오톡 작업을 실행할 수 없습니다. Mac 잠금을 해제한 뒤 다시 요청해 주세요."

  static var isLocked: Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
  }

  static func blockingMessage(for action: AgentAction, locked: Bool = isLocked) -> String? {
    action.needsUnlockedScreen && locked ? lockedMessage : nil
  }
}

extension AgentAction {
  var needsUnlockedScreen: Bool {
    if [.getUIControlStatus, .getVSCodeQuickOpenStatus].contains(self) { return false }
    return isUIAction || [.kakaoMessage, .captureScreen, .inspectScreen, .inspectActiveWindow,
      .inspectScreenWithProjectContext, .listVisibleWindows, .inspectWindow].contains(self)
  }
}
