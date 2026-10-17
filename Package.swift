// swift-tools-version:6.0

import PackageDescription
import Foundation

// Unreleased source checkouts use the locally built framework. The release script
// sets these two values only when preparing a matching published binary.
let binaryURL: String? = "https://github.com/zshannon/yswift/releases/download/0.7.1/yniffiFFI.xcframework.zip"
let binaryChecksum = "d2cb4742667f71e3405119eacf1a668a3b1389396b7f0f9cd64c7d52a262ee35"
let FFIbinaryTarget: PackageDescription.Target
if let binaryURL, ProcessInfo.processInfo.environment["YSWIFT_LOCAL"] == nil {
    FFIbinaryTarget = .binaryTarget(name: "yniffiFFI", url: binaryURL, checksum: binaryChecksum)
} else {
    FFIbinaryTarget = .binaryTarget(name: "yniffiFFI", path: "./lib/yniffiFFI.xcframework")
}

let package = Package(
    name: "YSwift",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "YSwift", type: .dynamic, targets: ["YSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.1.0"),
        .package(url: "https://github.com/guykogus/SwifterJSON", from: "5.0.1"),
    ],
    targets: [
        FFIbinaryTarget,
        .target(
            name: "Yniffi",
            dependencies: ["yniffiFFI"],
            path: "lib/swift/scaffold"
        ),
        .target(
            name: "YSwift",
            dependencies: [
                "Yniffi",
                .product(name: "SwifterJSON", package: "SwifterJSON"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "YSwiftTests",
            dependencies: ["YSwift"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
