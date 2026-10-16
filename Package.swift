// swift-tools-version:6.0

import PackageDescription
import Foundation

// Unreleased source checkouts use the locally built framework. The release script
// sets these two values only when preparing a matching published binary.
let binaryURL: String? = "https://github.com/zshannon/yswift/releases/download/0.6.0/yniffiFFI.xcframework.zip"
let binaryChecksum = "968195a90558a5ad7638ea6545c99aa5c16a23a05272a45e1beb0ba462c5f434"
let FFIbinaryTarget: PackageDescription.Target
if let binaryURL, ProcessInfo.processInfo.environment["YSWIFT_LOCAL"] == nil {
    FFIbinaryTarget = .binaryTarget(name: "yniffiFFI", url: binaryURL, checksum: binaryChecksum)
} else {
    FFIbinaryTarget = .binaryTarget(name: "yniffiFFI", path: "./lib/yniffiFFI.xcframework")
}

let package = Package(
    name: "YSwift",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "YSwift", type: .dynamic, targets: ["YSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.1.0"),
        .package(url: "https://github.com/mattmassicotte/Queue", from: "0.2.1"),
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
                .product(name: "Queue", package: "Queue"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "YSwiftTests",
            dependencies: ["YSwift"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ],
    swiftLanguageModes: [.v5]
)
