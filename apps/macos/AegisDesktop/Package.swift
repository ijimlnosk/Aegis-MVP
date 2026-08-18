// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AegisDesktop",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "AegisDesktop"),
    .testTarget(name: "AegisDesktopTests", dependencies: ["AegisDesktop"]),
  ],
  swiftLanguageModes: [.v5]
)
