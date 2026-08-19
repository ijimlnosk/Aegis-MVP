import AppKit
import Foundation

struct MacContextSource: ContextSource {
  let kind = ContextSourceKind.mac
  let includeClipboardMetadata: Bool
  init(includeClipboardMetadata: Bool = false) { self.includeClipboardMetadata = includeClipboardMetadata }

  @MainActor func collect() async throws -> ContextSourceResult {
    let info = ProcessInfo.processInfo
    let applications = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }.compactMap(\.localizedName).sorted()
    let clipboard: ClipboardMetadata? = includeClipboardMetadata ? {
      let text = NSPasteboard.general.string(forType: .string) ?? ""
      return ClipboardMetadata(hasText: !text.isEmpty, characterCount: text.count)
    }() : nil
    return .mac(MacContext(activeApplication: NSWorkspace.shared.frontmostApplication?.localizedName,
      runningApplications: applications, uptimeHours: Int(info.systemUptime / 3600),
      physicalMemoryGB: Double(info.physicalMemory) / 1_073_741_824, clipboard: clipboard))
  }
}
