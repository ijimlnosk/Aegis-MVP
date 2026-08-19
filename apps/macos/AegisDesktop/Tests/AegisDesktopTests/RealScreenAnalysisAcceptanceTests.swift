import Foundation
import Testing
@testable import AegisDesktop

@Test func realScreenAnalysisAcceptance() async throws {
  guard ProcessInfo.processInfo.environment["AEGIS_REAL_SCREEN_TEST"] == "1" else { return }
  let displayInspector = ScreenInspector(cacheLifetime: 0)
  let display = await displayInspector.inspect(
    .init(activeWindowOnly: false, displayIndex: nil), trustedContext: nil)
  #expect(display.succeeded)
  #expect(!display.message.contains("Vision 모델의 응답을 해석하지 못했습니다"))

  let windowInspector = ScreenInspector(cacheLifetime: 0)
  let window = await windowInspector.inspect(
    .init(activeWindowOnly: true, displayIndex: nil), trustedContext: nil)
  #expect(window.succeeded)
  #expect(!window.message.contains("Vision 모델의 응답을 해석하지 못했습니다"))
}
