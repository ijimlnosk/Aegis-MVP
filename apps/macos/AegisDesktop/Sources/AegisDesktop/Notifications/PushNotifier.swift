import Foundation

struct PushNotification: Equatable {
  let title: String
  let message: String
  /// ntfy priority, 1 (min) to 5 (urgent).
  let priority: Int
  let tags: [String]
}

struct PushNotifierConfiguration: Equatable {
  let server: URL
  let topic: String
  let token: String?
  /// Phone commands that finish faster than this are not pushed; the open app already shows them.
  let minimumSeconds: TimeInterval

  /// Disabled unless both a server and an unguessable topic are configured.
  static func load(_ environment: [String: String] = RemoteEnvironment.load()) -> Self? {
    guard let raw = environment["AEGIS_NOTIFY_SERVER"]?.trimmingCharacters(in: .whitespacesAndNewlines), let server = URL(string: raw),
      ["http", "https"].contains(server.scheme ?? ""), server.host != nil,
      let topic = environment["AEGIS_NOTIFY_TOPIC"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      topic.range(of: "^[A-Za-z0-9_-]{16,64}$", options: .regularExpression) != nil else { return nil }
    let token = environment["AEGIS_NOTIFY_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let seconds = Double(environment["AEGIS_NOTIFY_MIN_SECONDS"] ?? "") ?? 20
    return Self(server: server, topic: topic, token: token?.isEmpty == false ? token : nil,
      minimumSeconds: max(0, seconds))
  }
}

/// Publishes short status pushes to a self-hosted ntfy topic so the phone hears about
/// approvals, long results, and Aegis warnings without the app open.
final class PushNotifier {
  let configuration: PushNotifierConfiguration?

  init(configuration: PushNotifierConfiguration? = .load()) { self.configuration = configuration }

  func send(_ notification: PushNotification) {
    guard let configuration, let request = Self.request(for: notification, configuration: configuration) else { return }
    // Fire and forget: a missing notification server must never slow down or fail a command.
    Task.detached { _ = try? await URLSession.shared.data(for: request) }
  }

  static func request(for notification: PushNotification,
                      configuration: PushNotifierConfiguration) -> URLRequest? {
    let body: [String: Any] = ["topic": configuration.topic, "title": notification.title,
      "message": notification.message, "priority": notification.priority, "tags": notification.tags]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
    var request = URLRequest(url: configuration.server, timeoutInterval: 5)
    request.httpMethod = "POST"
    request.httpBody = data
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = configuration.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return request
  }
}
