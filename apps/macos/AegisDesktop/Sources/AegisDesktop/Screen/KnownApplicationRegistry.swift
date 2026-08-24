import Foundation

struct KnownApplication: Equatable, Sendable {
  let canonicalName: String
  let aliases: [String]
  let bundleIdentifiers: [String]

  func matches(bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    return bundleIdentifiers.contains { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
  }

  func matches(alias: String) -> Bool {
    aliases.contains { $0.caseInsensitiveCompare(alias) == .orderedSame }
  }
}

enum KnownApplicationRegistry {
  static let applications = [
    KnownApplication(canonicalName: "Visual Studio Code",
      aliases: ["VSCode", "VS Code", "Visual Studio Code", "Code", "비주얼 스튜디오 코드"],
      bundleIdentifiers: ["com.microsoft.VSCode"]),
    KnownApplication(canonicalName: "Xcode", aliases: ["Xcode", "엑스코드"],
      bundleIdentifiers: ["com.apple.dt.Xcode"]),
    KnownApplication(canonicalName: "Firefox", aliases: ["Firefox"],
      bundleIdentifiers: ["org.mozilla.firefox"]),
    KnownApplication(canonicalName: "Google Chrome", aliases: ["Chrome", "Google Chrome"],
      bundleIdentifiers: ["com.google.Chrome"]),
    KnownApplication(canonicalName: "Safari", aliases: ["Safari"],
      bundleIdentifiers: ["com.apple.Safari"]),
    KnownApplication(canonicalName: "Cursor", aliases: ["Cursor", "커서"],
      bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]),
    KnownApplication(canonicalName: "KakaoTalk", aliases: ["KakaoTalk", "카카오톡"],
      bundleIdentifiers: ["com.kakao.KakaoTalkMac"]),
  ]

  static func application(bundleIdentifier: String?) -> KnownApplication? {
    applications.first { $0.matches(bundleIdentifier: bundleIdentifier) }
  }

  static func application(nameOrAlias: String) -> KnownApplication? {
    applications.first {
      $0.canonicalName.caseInsensitiveCompare(nameOrAlias) == .orderedSame
        || $0.matches(alias: nameOrAlias)
    }
  }

  static func canonicalName(applicationName: String,
                            bundleIdentifier: String?) -> String {
    application(bundleIdentifier: bundleIdentifier)?.canonicalName
      ?? application(nameOrAlias: applicationName)?.canonicalName
      ?? applicationName
  }
}
