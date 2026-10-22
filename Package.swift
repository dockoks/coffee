// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Coffee",
  platforms: [
    .macOS(.v14)
  ],
  targets: [
    .executableTarget(
      name: "Coffee",
      resources: [
        .process("Assets.xcassets")
      ],
      linkerSettings: [
        .linkedFramework("IOKit")
      ]
    ),
    .testTarget(
      name: "CoffeeTests",
      dependencies: ["Coffee"]
    ),
  ]
)
