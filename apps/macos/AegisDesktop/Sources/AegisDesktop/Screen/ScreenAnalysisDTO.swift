import Foundation

struct ScreenAnalysisDTO: Decodable {
  let summary: String
  let detectedApplication: String?
  let detectedWindow: String?
  let visibleErrors: [String]
  let visibleWarnings: [String]
  let visibleCodeContext: String?
  let visibleUIState: String?
  let confidence: Double?
  let limitations: [String]

  var analysis: ScreenAnalysis {
    ScreenAnalysis(summary: summary, detectedApplication: detectedApplication,
      detectedWindow: detectedWindow, visibleErrors: visibleErrors,
      visibleWarnings: visibleWarnings, visibleCodeContext: visibleCodeContext,
      visibleUIState: visibleUIState, confidence: confidence, limitations: limitations)
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: Keys.self)
    summary = try values.decode(String.self, forKey: .summary)
    detectedApplication = try values.decodeOptionalString(.detectedApplication, .detectedApplicationAlias)
    detectedWindow = try values.decodeOptionalString(.detectedWindow, .detectedWindowAlias)
    visibleErrors = try values.decodeOptionalArray(.visibleErrors, .visibleErrorsAlias)
    visibleWarnings = try values.decodeOptionalArray(.visibleWarnings, .visibleWarningsAlias)
    visibleCodeContext = try values.decodeOptionalString(.visibleCodeContext, .visibleCodeContextAlias)
    visibleUIState = try values.decodeOptionalString(.visibleUIState, .visibleUIStateAlias)
    confidence = try values.decodeIfPresent(Double.self, forKey: .confidence)
    limitations = try values.decodeIfPresent([String].self, forKey: .limitations) ?? []
  }
}

private enum Keys: String, CodingKey {
  case summary, detectedApplication, detectedWindow, visibleErrors, visibleWarnings
  case visibleCodeContext, visibleUIState, confidence, limitations
  case detectedApplicationAlias = "detected_application"
  case detectedWindowAlias = "detected_window"
  case visibleErrorsAlias = "visible_errors"
  case visibleWarningsAlias = "visible_warnings"
  case visibleCodeContextAlias = "visible_code_context"
  case visibleUIStateAlias = "visible_ui_state"
}

private extension KeyedDecodingContainer where Key == Keys {
  func decodeOptionalString(_ primary: Key, _ alias: Key) throws -> String? {
    try decodeIfPresent(String.self, forKey: primary) ?? decodeIfPresent(String.self, forKey: alias)
  }
  func decodeOptionalArray(_ primary: Key, _ alias: Key) throws -> [String] {
    try decodeIfPresent([String].self, forKey: primary)
      ?? decodeIfPresent([String].self, forKey: alias) ?? []
  }
}
