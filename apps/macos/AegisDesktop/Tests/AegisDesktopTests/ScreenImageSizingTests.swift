import Testing
@testable import AegisDesktop

@Test func imageResizePreservesAspectRatioAndNeverUpscales() {
  let landscape = ScreenImageSizing.bounded(width: 2_560, height: 1_440, maximum: 1_600)
  #expect(landscape.width == 1_600)
  #expect(landscape.height == 900)
  let portrait = ScreenImageSizing.bounded(width: 1_200, height: 2_400, maximum: 1_600)
  #expect(portrait.width == 800)
  #expect(portrait.height == 1_600)
  let small = ScreenImageSizing.bounded(width: 800, height: 600, maximum: 1_600)
  #expect(small.width == 800); #expect(small.height == 600)
}

@Test func activeWindowUsesConfiguredBoundedDimensions() {
  let result = ScreenImageSizing.bounded(width: 3_200, height: 1_800,
    maximum: ScreenAnalysisConfiguration.maximumLongEdge(for: .balanced),
    maximumPixels: ScreenAnalysisConfiguration.maximumPixels())
  #expect(max(result.width, result.height) == 1_280)
  #expect(Double(result.width) / Double(result.height) == 16.0 / 9.0)
}

@Test func fiveKCaptureObeysEdgeAndPixelBudgets() {
  let result = ScreenImageSizing.bounded(width: 5_120, height: 2_880,
    maximum: 1_920, maximumPixels: 1_500_000)
  #expect(result.width * result.height <= 1_500_000)
  #expect(result.width <= 1_920)
  #expect(abs(Double(result.width) / Double(result.height) - 16.0 / 9.0) < 0.01)
}

@Test func longEdgeConfigurationDefaultsToBalanced() {
  #expect(ScreenAnalysisConfiguration.parsedLongEdge(environment: [:]) == 1_280)
  #expect(ScreenAnalysisConfiguration.parsedLongEdge(
    environment: ["AEGIS_VISION_MAX_LONG_EDGE": "1024"]) == 1_024)
}
