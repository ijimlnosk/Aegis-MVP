enum ScreenDisplayPolicy {
  static func validate(index: Int?, displayCount: Int) throws {
    guard let index else { return }
    guard index > 0, index <= displayCount else { throw ScreenCaptureError.invalidDisplay(index) }
  }
}
