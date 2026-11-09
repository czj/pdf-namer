// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pdf-namer",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "pdf-namer", targets: ["pdf-namer"]),
        .executable(name: "PDFNamerApp", targets: ["PDFNamerApp"]),
    ],
    targets: [
        .target(name: "PDFNamerCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "pdf-namer", dependencies: ["PDFNamerCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "PDFNamerApp", dependencies: ["PDFNamerCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "PDFNamerCoreTests", dependencies: ["PDFNamerCore"],
                    resources: [.copy("Fixtures")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
