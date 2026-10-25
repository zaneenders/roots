// swift-tools-version: 6.4
import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableExperimentalFeature("Lifetimes"),
  .treatAllWarnings(as: .error),
  .strictMemorySafety()
]

let package = Package(
  name: "RootsMandelbrotExample",
  platforms: [.macOS(.v27)],
  products: [.executable(name: "Mandelbrot", targets: ["Mandelbrot"])],
  dependencies: [.package(name: "roots", path: "../..")],
  targets: [
    .executableTarget(
      name: "Mandelbrot",
      dependencies: [
        .product(name: "Roots", package: "roots"),
        .product(name: "RootsDesktop", package: "roots")
      ],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "MandelbrotTests", dependencies: ["Mandelbrot"], swiftSettings: swiftSettings)
  ])
