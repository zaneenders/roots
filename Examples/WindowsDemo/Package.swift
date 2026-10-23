// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "WindowsDemo",
  platforms: [.macOS("27.0")],
  dependencies: [.package(name: "roots", path: "../..")],
  targets: [
    .executableTarget(
      name: "WindowsDemo",
      dependencies: [
        .product(name: "Roots", package: "roots"),
        .product(name: "RootsDesktop", package: "roots"),
      ], swiftSettings: [.enableExperimentalFeature("Lifetimes")])
  ])
