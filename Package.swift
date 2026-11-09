// swift-tools-version: 6.4
import PackageDescription

/// Swift 6 language mode with Approachable Concurrency: `async` runs on the caller's actor,
/// `@concurrent` is the explicit way off it.
let approachable: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
/// The app and the CLI live on the main actor; the library stays nonisolated so callers decide.
let mainActorByDefault = approachable + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "pdf-namer",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "pdf-namer", targets: ["pdf-namer"]),
        .executable(name: "PDFNamerApp", targets: ["PDFNamerApp"]),
    ],
    targets: [
        .target(name: "PDFNamerCore", swiftSettings: approachable),
        .executableTarget(name: "pdf-namer", dependencies: ["PDFNamerCore"], swiftSettings: mainActorByDefault),
        .executableTarget(name: "PDFNamerApp", dependencies: ["PDFNamerCore"], swiftSettings: mainActorByDefault),
        .testTarget(name: "PDFNamerCoreTests", dependencies: ["PDFNamerCore"],
                    resources: [.copy("Fixtures")], swiftSettings: approachable),
    ]
)
