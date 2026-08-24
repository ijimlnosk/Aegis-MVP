import Foundation

enum XcodeAdapter {
  static let application = KnownApplicationRegistry.application(nameOrAlias: "Xcode")!
  static let availableCapabilities = ["activate", "focusWindow", "find"]
}
