import Foundation
import Testing
@testable import AegisDesktop

@Test func normalScreenAnalysisUsesKoreanPresentationSections() {
  let output = format(analysis(summary: "회원 관리 기능을 작업 중인 것으로 보입니다.",
    errors: ["TypeScript 오류 2건"], warnings: ["ESLint 경고"],
    code: "회원 관리 TypeScript 파일이 열려 있습니다.", ui: "편집기 하단에 터미널이 표시되어 있습니다."))
  #expect(output.contains("현재 화면\n- 앱: Visual Studio Code\n- 창: PTFriends"))
  #expect(output.contains("확인된 내용\n- 회원 관리 TypeScript 파일"))
  #expect(output.contains("오류\n- TypeScript 오류 2건"))
  #expect(output.contains("경고\n- ESLint 경고"))
  #expect(output.contains("해석\n- 회원 관리 기능을 작업 중"))
  #expect(!output.contains("confidence"))
}

@Test func emptyErrorAndWarningSectionsAreOmitted() {
  let output = format(analysis(summary: "코드 편집 화면으로 보입니다."))
  #expect(!output.contains("\n오류\n"))
  #expect(!output.contains("\n경고\n"))
}

@Test func repetitiveVisibleStringsAreDeduplicatedAndBounded() {
  let labels = (["Aegis에게 메시지 보내기", "취소", "취소"]
    + (1...9).map { "UI 항목 \($0)" }).joined(separator: "\n")
  let output = format(analysis(summary: "Aegis 화면입니다.", ui: labels))
  #expect(output.components(separatedBy: "- 취소").count - 1 == 1)
  #expect(output.contains("외 3건"))
  #expect(!output.contains("UI 항목 9"))
}

@Test func inferenceIsSeparateFromDirectlyVisibleFacts() {
  let output = format(analysis(summary: "배포를 준비 중인 것으로 보입니다.",
    code: "Package.swift가 열려 있습니다."))
  let facts = output.range(of: "확인된 내용")!
  let inference = output.range(of: "해석")!
  #expect(facts.lowerBound < inference.lowerBound)
  #expect(output[inference.lowerBound...].contains("준비 중인 것으로"))
}

@Test func rawJSONIsNeverPresentedAsNormalChat() {
  let raw = #"{"summary":"내부 값","confidence":0.9}"#
  let output = format(analysis(summary: raw))
  #expect(!output.contains(raw))
  #expect(!output.contains("\"confidence\""))
  #expect(output.contains("자연어로 정리하지 못했습니다"))
}

@Test func unstructuredFallbackAnalysisFormatsSafely() throws {
  let envelope = #"{"message":{"content":"코드 편집기와 터미널이 보입니다."}}"#
  let parsed = try OllamaScreenAnalysisParser.parse(Data(envelope.utf8))
  let output = format(parsed)
  #expect(output.contains("해석\n- 코드 편집기와 터미널이 보입니다."))
  #expect(!output.contains("provider wrapper"))
}

@Test func trustedVSCodeIdentityOverridesConflictingVisionGuesses() {
  let snapshot = ScreenSnapshot(displayCount: 1, activeApplication: "Code",
    bundleIdentifier: "com.microsoft.VSCode", activeWindowTitle: "build.gradle — ptfriendsapp",
    windowID: 42, displayIndex: 1, temporaryImageURL: URL(fileURLWithPath: "/tmp/not-used"),
    width: 1, height: 1, captureSource: .activeWindow)
  let untrusted = ScreenAnalysis(summary: "Android Studio의 git gui로 보입니다.",
    detectedApplication: "PTFriends 개발 환경", detectedWindow: "git gui",
    visibleErrors: [], visibleWarnings: [], visibleCodeContext: "build.gradle 파일 내용",
    visibleUIState: nil, confidence: 0.9, limitations: [])
  let output = ScreenAnalysisFormatter.format(snapshot: snapshot, analysis: untrusted,
    projectContext: "PTFriends 프로젝트 상태")
  #expect(output.contains("현재 화면\n- 앱: Visual Studio Code"))
  #expect(output.contains("- 창: build.gradle — ptfriendsapp"))
  #expect(output.contains("확인된 내용\n- build.gradle 파일 내용"))
  #expect(!output.contains("Android Studio"))
  #expect(!output.contains("git gui"))
  #expect(!output.contains("앱: PTFriends 개발 환경"))
}

private func format(_ value: ScreenAnalysis) -> String {
  ScreenAnalysisFormatter.format(snapshot: ScreenSnapshot(displayCount: 1,
    activeApplication: "Visual Studio Code", activeWindowTitle: "PTFriends",
    temporaryImageURL: URL(fileURLWithPath: "/tmp/not-used"), width: 1, height: 1,
    captureSource: .activeWindow), analysis: value, projectContext: nil)
}

private func analysis(summary: String, errors: [String] = [], warnings: [String] = [],
                      code: String? = nil, ui: String? = nil) -> ScreenAnalysis {
  ScreenAnalysis(summary: summary, detectedApplication: "Visual Studio Code",
    detectedWindow: "PTFriends", visibleErrors: errors, visibleWarnings: warnings,
    visibleCodeContext: code, visibleUIState: ui, confidence: 0.9, limitations: [])
}
