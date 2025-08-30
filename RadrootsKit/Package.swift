// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RadrootsKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "RadrootsKit",
            targets: ["RadrootsKit"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "RadrootsFFI",
            path: "Artifacts/RadrootsFFI.xcframework"
        ),
        .target(
            name: "RadrootsKit",
            dependencies: ["RadrootsFFI"],
            path: "Sources/RadrootsKit"
        )
    ]
)
