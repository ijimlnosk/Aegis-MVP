import Foundation

struct DesktopBridgeCommand: Decodable { let sessionId: String; let commandId: String; let text: String }
struct DesktopBridgeApproval: Decodable { let sessionId: String; let commandId: String }

struct DesktopBridgeResult: Codable {
  let status: String
  let messages: [String]
  let pendingApproval: DesktopBridgeApprovalCard?
  let progress: DesktopBridgeProgress?
  // Bounded, stable failure category for status == "failed"/"cancelled" -- lets the
  // Remote app show why instead of a generic message. See DesktopFailureClassifier.
  let failureCode: String?

  init(status: String, messages: [String], pendingApproval: DesktopBridgeApprovalCard?,
       progress: DesktopBridgeProgress? = nil, failureCode: String? = nil) {
    self.status = status; self.messages = messages; self.pendingApproval = pendingApproval
    self.progress = progress; self.failureCode = failureCode
  }
}

struct DesktopBridgeProgress: Codable {
  let phase: String
  let message: String
  let currentStep: Int?
  let totalSteps: Int?
  let cancellable: Bool
  let startedAt: String
}

struct DesktopBridgeApprovalCard: Codable {
  let id: String
  let title: String
  let goal: String
  let risk: String
  let scope: String
}

struct DesktopBridgeHealth: Encodable {
  let status = "ok"; let service = "AegisDesktopBridge"
  var screenLocked = ScreenLockState.isLocked
}
