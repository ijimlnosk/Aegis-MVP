import Foundation
import Testing
@testable import AegisDesktop

@Test func pushNotifierStaysOffWithoutServerAndUnguessableTopic() {
  #expect(PushNotifierConfiguration.load([:]) == nil)
  #expect(PushNotifierConfiguration.load(["AEGIS_NOTIFY_SERVER": "http://sol-server:8080",
    "AEGIS_NOTIFY_TOPIC": "aegis"]) == nil)
  #expect(PushNotifierConfiguration.load(["AEGIS_NOTIFY_SERVER": "file:///tmp",
    "AEGIS_NOTIFY_TOPIC": "aegis-7f3k9q2m1x8z"]) == nil)
  let configured = PushNotifierConfiguration.load(["AEGIS_NOTIFY_SERVER": "http://sol-server:8080",
    "AEGIS_NOTIFY_TOPIC": "aegis-7f3k9q2m1x8z", "AEGIS_NOTIFY_TOKEN": "tk_x"])
  #expect(configured?.minimumSeconds == 20)
  #expect(configured?.token == "tk_x")
}

@Test func pushRequestPublishesJSONToTheTopicWithToken() throws {
  let configuration = try #require(PushNotifierConfiguration.load(["AEGIS_NOTIFY_SERVER": "https://ntfy.example",
    "AEGIS_NOTIFY_TOPIC": "aegis-7f3k9q2m1x8z", "AEGIS_NOTIFY_TOKEN": "tk_x"]))
  let request = try #require(PushNotifier.request(for: PushMessages.approval(kind: "kakao_message", scope: "Mac"),
    configuration: configuration))
  #expect(request.httpMethod == "POST")
  #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tk_x")
  let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
  #expect(body["topic"] as? String == "aegis-7f3k9q2m1x8z")
  #expect(body["priority"] as? Int == 4)
  #expect((body["message"] as? String)?.contains("카카오톡") == true)
}

@Test func finishedPushNamesActionsAndSkipsQuickCommands() {
  let push = PushMessages.finished(succeeded: false, actions: [.runProjectLint], project: "PTFriends")
  #expect(push.title == "Aegis 작업 실패")
  #expect(push.message == "PTFriends: lint 실행")
  let now = Date()
  #expect(!PushMessages.shouldNotifyFinish(startedAt: now.addingTimeInterval(-5), now: now, minimumSeconds: 20))
  #expect(PushMessages.shouldNotifyFinish(startedAt: now.addingTimeInterval(-30), now: now, minimumSeconds: 20))
  #expect(!PushMessages.shouldNotifyFinish(startedAt: nil, now: now, minimumSeconds: 0))
}
