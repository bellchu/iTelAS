// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "iTelAS",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "iTelASCore", targets: ["iTelASCore"]),
        .executable(name: "iTelAS", targets: ["iTelAS"])
    ],
    targets: [
        .target(
            name: "iTelASCore",
            path: "Sources/iTelASCore",
            linkerSettings: [
                .linkedLibrary("iconv")
            ]
        ),
        .executableTarget(
            name: "iTelAS",
            dependencies: ["iTelASCore"],
            path: "Sources/iTelAS",
            resources: [
                .copy("Resources/iTelASIcon.png")
            ]
        ),
        .testTarget(
            name: "iTelASCoreTests",
            dependencies: ["iTelASCore"],
            path: "Tests/iTelASCoreTests"
        ),
        .testTarget(
            name: "iTelASAppTests",
            dependencies: ["iTelAS"],
            path: "Tests/iTelASAppTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
