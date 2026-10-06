import AppKit
import SwiftUI

@main
struct AegisDesktopApp: App {
  @NSApplicationDelegateAdaptor(AegisApplicationDelegate.self) private var applicationDelegate
  @StateObject private var agent = AegisAgent()

  var body: some Scene {
    WindowGroup("Aegis") {
      AegisView(agent: agent).frame(minWidth: 520, minHeight: 560)
        .onAppear { applicationDelegate.agent = agent; agent.start() }
    }
    MenuBarExtra("Aegis", systemImage: "waveform") {
      AegisView(agent: agent).frame(width: 380, height: 440)
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class AegisApplicationDelegate: NSObject, NSApplicationDelegate {
  weak var agent: AegisAgent?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard agent?.hasActiveBackgroundWork == true else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "진행 중인 Aegis 작업이 있습니다."
    alert.informativeText = "종료하면 현재 작업은 중단됩니다. 창만 닫으려면 취소를 누르세요."
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "작업 중단 후 종료")
    return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
  }
}
