// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CleanR",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CleanR", targets: ["CleanR"]),
        .executable(name: "CleanRMenu", targets: ["CleanRMenu"]),
        .library(name: "CleanRKit", targets: ["CleanRKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CleanR",
            dependencies: [
                "CleanRKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/CleanR"
        ),
        .executableTarget(
            name: "CleanRMenu",
            dependencies: ["CleanRKit"],
            path: "Sources/CleanRMenu"
        ),
        .target(
            name: "CleanRKit",
            dependencies: [],
            path: "Sources/CleanRKit"
        ),
        .testTarget(
            name: "CleanRTestSupport",
            dependencies: ["CleanRKit"],
            path: "Tests/CleanRTestSupport"
        ),
        .testTarget(
            name: "CleanRTests",
            dependencies: ["CleanR", "CleanRKit", "CleanRTestSupport"],
            path: "Tests/CleanRTests"
        ),
        .testTarget(
            name: "CleanRKitTests",
            dependencies: ["CleanRKit", "CleanRTestSupport"],
            path: "Tests/CleanRKitTests"
        ),
    ]
)
