import AppKit
import Foundation

enum BrowserTools {
  static func search(browser: String, site: String, query: String) async -> String {
    await Task.detached {
      let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
      let target: String
      if site.lowercased().contains("youtube") {
        target = query.isEmpty ? "https://www.youtube.com" : "https://www.youtube.com/results?search_query=\(encoded)"
      } else {
        target = "https://www.google.com/search?q=\(encoded)"
      }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-a", browser, target]
      do {
        try process.run()
        process.waitUntilExit()
        let result = query.isEmpty ? "\(browser)에서 \(site)를 열었습니다." : "\(browser)에서 \(site)로 \(query)을 검색했습니다."
        return process.terminationStatus == 0 ? result : "\(browser)을 열지 못했습니다."
      } catch { return "\(browser) 검색을 실행하지 못했습니다." }
    }.value
  }
}
