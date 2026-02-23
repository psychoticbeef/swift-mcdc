// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCDCAnalyzer",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MCDCAnalyzer", targets: ["MCDCAnalyzer"]),
        .executable(name: "mcdc-tool", targets: ["mcdc-tool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "600.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MCDCAnalyzer",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "mcdc-tool",
            dependencies: [
                "MCDCAnalyzer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "MCDCAnalyzerTests",
            dependencies: ["MCDCAnalyzer"]
        ),
    ]
)
