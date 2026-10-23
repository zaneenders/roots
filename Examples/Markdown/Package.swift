// swift-tools-version: 6.4
import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableExperimentalFeature("Lifetimes"),
  .treatAllWarnings(as: .error),
  .strictMemorySafety()
]

let package = Package(
  name: "RootsMarkdownExample",
  platforms: [.macOS(.v27)],
  products: [.executable(name: "MarkdownDemo", targets: ["MarkdownDemo"])],
  dependencies: [.package(name: "roots", path: "../..")],
  targets: [
    .executableTarget(
      name: "MarkdownDemo",
      dependencies: [
        .product(name: "Roots", package: "roots"),
        .product(name: "RootsDesktop", package: "roots")
      ],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "MarkdownDemoTests", dependencies: ["MarkdownDemo"], swiftSettings: swiftSettings)
  ])
