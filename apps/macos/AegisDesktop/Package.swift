// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AegisDesktop",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "AegisWorkerProtocol"),
    .executableTarget(name: "AegisWorker", dependencies: ["AegisWorkerProtocol"]),
    .executableTarget(name: "AegisDesktop", dependencies: ["AegisWorkerProtocol"]),
    .testTarget(name: "AegisDesktopTests", dependencies: ["AegisDesktop", "AegisWorkerProtocol"]),
  ],
  swiftLanguageModes: [.v5]
)
