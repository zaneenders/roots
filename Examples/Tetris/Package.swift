// swift-tools-version: 6.4
import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableExperimentalFeature("Lifetimes"),
  .treatAllWarnings(as: .error),
  .strictMemorySafety()
]

let package = Package(
  name: "RootsTetris",
  platforms: [
    .macOS(.v27)
  ],
  products: [
    .executable(
      name: "Tetris",
      targets: ["Tetris"]
    )
  ],
  dependencies: [
    .package(
      name: "roots",
      path: "../.."
    )
  ],
  targets: [
    .target(
      name: "TetrisCore",
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "Tetris",
      dependencies: [
        "TetrisCore",
        .product(name: "Roots", package: "roots"),
        .product(name: "RootsDesktop", package: "roots")
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "TetrisCoreTests",
      dependencies: ["TetrisCore"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "TetrisTests",
      dependencies: ["Tetris", .product(name: "RootsCPU", package: "roots")],
      swiftSettings: swiftSettings
    )
  ]
)
