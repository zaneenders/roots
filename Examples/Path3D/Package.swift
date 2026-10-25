// swift-tools-version: 6.4
import PackageDescription

let settings: [SwiftSetting] = [
  .enableExperimentalFeature("Lifetimes"), .treatAllWarnings(as: .error), .strictMemorySafety()
]
#if os(Linux)
let nativeTests: [Target.Dependency] = [.product(name: "WaylandBridge", package: "roots")]
#else
let nativeTests: [Target.Dependency] = []
#endif
let package = Package(
  name: "RootsPath3D", platforms: [.macOS(.v27)],
  products: [.executable(name: "Path3D", targets: ["Path3D"])],
  dependencies: [.package(name: "roots", path: "../..")],
  targets: [
    .executableTarget(
      name: "Path3D",
      dependencies: [
        .product(name: "Roots", package: "roots"), .product(name: "RootsDesktop", package: "roots")
      ], swiftSettings: settings),
    .testTarget(
      name: "Path3DTests", dependencies: ["Path3D", .product(name: "RootsCPU", package: "roots")] + nativeTests,
      swiftSettings: settings)
  ])
