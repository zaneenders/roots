// swift-tools-version: 6.4
import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableExperimentalFeature("Lifetimes"),
  .treatAllWarnings(as: .error),
  .strictMemorySafety(),
]
var dependencies: [Package.Dependency] = []
var windowsBridgeDependencies: [Target.Dependency] = ["Roots", "RootsCPU"]
#if os(Windows)
  windowsBridgeDependencies.append("CWindowsHost")
#endif
var products: [Product] = [
  .library(name: "Roots", targets: ["Roots"]),
  .library(name: "RootsCPU", targets: ["RootsCPU"]),
]
var targets: [Target] = [
  .target(
    name: "CPNG", path: "Vendor/FreeType/png",
    sources: [
      "libpng/png.c", "libpng/pngerror.c", "libpng/pngget.c", "libpng/pngmem.c",
      "libpng/pngpread.c", "libpng/pngread.c", "libpng/pngrio.c", "libpng/pngrtran.c",
      "libpng/pngrutil.c", "libpng/pngset.c", "libpng/pngtrans.c", "libpng/pngwio.c",
      "libpng/pngwrite.c", "libpng/pngwtran.c", "libpng/pngwutil.c",
      "libpng/arm/arm_init.c", "libpng/arm/filter_neon_intrinsics.c",
      "libpng/arm/palette_neon_intrinsics.c",
    ],
    publicHeadersPath: "include",
    linkerSettings: [
      .linkedLibrary("z", .when(platforms: [.macOS, .linux])),
      .linkedLibrary("m", .when(platforms: [.linux])),
      .linkedLibrary("zlib", .when(platforms: [.windows])),
    ]),
  .target(
    name: "CFreeType",
    dependencies: ["CPNG"], path: "Vendor/FreeType",
    exclude: ["png"],
    sources: [
      "freetype/src/autofit/autofit.c", "freetype/src/base/ftbase.c",
      "freetype/src/base/ftbbox.c", "freetype/src/base/ftbitmap.c",
      "freetype/src/base/ftdebug.c", "freetype/src/base/ftglyph.c",
      "freetype/src/base/ftinit.c", "freetype/src/base/ftmm.c",
      "freetype/src/base/ftsystem.c",
      "freetype/src/bdf/bdf.c", "freetype/src/cff/cff.c",
      "freetype/src/cid/type1cid.c", "freetype/src/gzip/ftgzip.c",
      "freetype/src/hvf/hvf.c", "freetype/src/lzw/ftlzw.c",
      "freetype/src/pcf/pcf.c",
      "freetype/src/pfr/pfr.c", "freetype/src/psaux/psaux.c",
      "freetype/src/pshinter/pshinter.c", "freetype/src/psnames/psnames.c",
      "freetype/src/raster/raster.c", "freetype/src/sdf/sdf.c",
      "freetype/src/sfnt/sfnt.c", "freetype/src/smooth/smooth.c",
      "freetype/src/svg/svg.c", "freetype/src/truetype/truetype.c",
      "freetype/src/type1/type1.c", "freetype/src/type42/type42.c",
      "freetype/src/winfonts/winfnt.c",
    ],
    publicHeadersPath: "include",
    cSettings: [
      .define("FT2_BUILD_LIBRARY"),
      .define("FT_CONFIG_OPTION_USE_PNG"),
      .headerSearchPath("freetype/include"),
    ]),
  .target(
    name: "Roots", resources: [.copy("Resources")], swiftSettings: swiftSettings,
    plugins: [.plugin(name: "FontAtlasPlugin")]),
  .executableTarget(
    name: "FontAtlasGenerator", dependencies: ["CFreeType"],
    swiftSettings: swiftSettings),
  .executableTarget(
    name: "EmojiAtlasGenerator", dependencies: ["CFreeType"],
    swiftSettings: swiftSettings),
  .plugin(
    name: "FontAtlasPlugin", capability: .buildTool(),
    dependencies: ["FontAtlasGenerator", "EmojiAtlasGenerator"]),
  .target(name: "RootsCPU", dependencies: ["Roots"], swiftSettings: swiftSettings),
  .testTarget(name: "RootsTests", dependencies: ["Roots"], swiftSettings: swiftSettings),
  .testTarget(
    name: "RootsCPUTests", dependencies: ["Roots", "RootsCPU"], swiftSettings: swiftSettings),
  // Keep input translation and CPU frames testable without a Windows SDK.
  .target(
    name: "WindowsBridge", dependencies: windowsBridgeDependencies, swiftSettings: swiftSettings),
  .testTarget(
    name: "WindowsBridgeTests", dependencies: ["WindowsBridge", "Roots", "RootsCPU"],
    swiftSettings: swiftSettings),
]
#if os(Linux)
  dependencies += [
    .package(
      url: "https://github.com/zaneenders/swift-nio.git", branch: "shape-tree/unix-fd-messages"),
    .package(url: "https://github.com/apple/swift-system.git", from: "1.8.1"),
  ]
  products += [
    .library(name: "SwiftWayland", targets: ["SwiftWayland"]),
    .library(name: "WaylandBridge", targets: ["WaylandBridge"]),
  ]
  targets += [
    .target(
      name: "SwiftWayland",
      dependencies: [
        "CXKBCommon", .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "SystemPackage", package: "swift-system"),
      ], swiftSettings: swiftSettings),
    .systemLibrary(name: "CXKBCommon", pkgConfig: "xkbcommon"),
    .target(
      name: "CWaylandTestSupport", path: "Tests/CWaylandTestSupport", publicHeadersPath: "include"),
    .testTarget(
      name: "SwiftWaylandTests",
      dependencies: [
        "SwiftWayland", "CWaylandTestSupport",
        .product(name: "SystemPackage", package: "swift-system"),
      ],
      resources: [.copy("Protocols")], swiftSettings: swiftSettings),
    .target(
      name: "WaylandBridge",
      dependencies: ["CEGLGLES", "Roots", "SwiftWayland"],
      exclude: ["Shaders"],
      swiftSettings: swiftSettings, plugins: [.plugin(name: "ShaderSourcePlugin")]),
    .executableTarget(name: "ShaderSourceGenerator", swiftSettings: swiftSettings),
    .plugin(
      name: "ShaderSourcePlugin", capability: .buildTool(), dependencies: ["ShaderSourceGenerator"]),
    .testTarget(
      name: "ShaderSourceGeneratorTests", dependencies: ["ShaderSourceGenerator"],
      swiftSettings: swiftSettings),
    .target(
      name: "DesktopTestSupport",
      dependencies: [
        "CEGLGLES", .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
      ],
      path: "Tests/DesktopTestSupport", swiftSettings: swiftSettings),
    .testTarget(
      name: "WaylandBridgeTests",
      dependencies: [
        "WaylandBridge", "RootsCPU", "CEGLGLES", "SwiftWayland", "DesktopTestSupport",
      ],
      swiftSettings: swiftSettings),
    .systemLibrary(name: "CEGLGLES"),
  ]
#elseif os(macOS)
  products += [.library(name: "MacOSBridge", targets: ["MacOSBridge"])]
  targets += [
    .target(
      name: "MacOSBridge", dependencies: ["Roots"],
      resources: [.copy("Shaders")], swiftSettings: swiftSettings),
    .target(
      name: "DesktopTestSupport", path: "Tests/DesktopTestSupport", swiftSettings: swiftSettings),
    .testTarget(
      name: "MacOSBridgeTests", dependencies: ["MacOSBridge", "RootsCPU", "DesktopTestSupport"],
      swiftSettings: swiftSettings),
  ]
#elseif os(Windows)
  products += [.library(name: "WindowsBridge", targets: ["WindowsBridge"])]
  targets += [
    .target(
      name: "CWindowsHost", publicHeadersPath: "include",
      linkerSettings: [.linkedLibrary("user32"), .linkedLibrary("gdi32")]),
    .target(
      name: "DesktopTestSupport", path: "Tests/DesktopTestSupport", swiftSettings: swiftSettings),
  ]
#endif
#if os(macOS) || os(Linux) || os(Windows)
  products += [.library(name: "RootsDesktop", targets: ["RootsDesktop"])]
  #if os(macOS)
    let desktopBackend: Target.Dependency = "MacOSBridge"
  #elseif os(Windows)
    let desktopBackend: Target.Dependency = "WindowsBridge"
  #else
    let desktopBackend: Target.Dependency = "WaylandBridge"
  #endif
  targets += [
    .target(
      name: "RootsDesktop", dependencies: ["Roots", desktopBackend], swiftSettings: swiftSettings),
    .testTarget(
      name: "RootsDesktopTests", dependencies: ["RootsDesktop", "RootsCPU", "DesktopTestSupport"],
      swiftSettings: swiftSettings),
  ]
#endif
let package = Package(
  name: "roots", platforms: [.macOS("27.0")], products: products,
  dependencies: dependencies, targets: targets)
