// swift-tools-version: 6.4
import PackageDescription

let settings: [SwiftSetting] = [
  .enableExperimentalFeature("Lifetimes"), .treatAllWarnings(as: .error), .strictMemorySafety(),
]
let package = Package(
  name: "RootsVideoExample", platforms: [.macOS(.v27)],
  products: [.executable(name: "VideoPlayer", targets: ["VideoPlayer"])],
  dependencies: [.package(name: "roots", path: "../..")],
  targets: [
    .systemLibrary(name: "CFFmpeg", pkgConfig: "libavformat"),
    .target(
      name: "CVideoDecoder", dependencies: ["CFFmpeg"],
      linkerSettings: [
        .linkedLibrary("avcodec"), .linkedLibrary("avutil"), .linkedLibrary("swscale"),
      ]),
    .executableTarget(
      name: "VideoPlayer",
      dependencies: [
        "CVideoDecoder", .product(name: "Roots", package: "roots"),
        .product(name: "RootsDesktop", package: "roots"),
      ], swiftSettings: settings),
    .testTarget(
      name: "VideoPlayerTests",
      dependencies: [
        "VideoPlayer",
        .product(name: "RootsCPU", package: "roots"),
      ], swiftSettings: settings),
  ])
