// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AuthCompanion",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "authcompanion", targets: ["AuthCompanionCLI"]),
    .library(name: "AuthCompanionCore", targets: ["AuthCompanionCore"]),
  ],
  targets: [
    .target(name: "AuthCompanionCore"),
    .executableTarget(
      name: "AuthCompanionCLI",
      dependencies: ["AuthCompanionCore"]
    ),
    .testTarget(
      name: "AuthCompanionTests",
      dependencies: ["AuthCompanionCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
