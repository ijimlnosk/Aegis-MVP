struct ScreenDiagnostics: Equatable {
  let availability: ScreenCaptureAvailability
  let activeApplication: String?
  let activeWindowAvailable: Bool
  let activeWindowTitle: String?
  let displayCount: Int

  func format(provider: String, cacheAvailable: Bool) -> String {
    """
    화면 인식 상태
    - 화면 기록 권한: \(availability.rawValue)
    - 활성 앱: \(activeApplication ?? "확인 불가")
    - 활성 창: \(activeWindowAvailable ? "사용 가능" : "확인 불가")
    - 모니터: \(displayCount)개
    - 분석 provider: \(provider)
    - 임시 분석 캐시: \(cacheAvailable ? "있음" : "없음")
    """
  }
}
