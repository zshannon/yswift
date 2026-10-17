// swift-tools-version:6.0

import PackageDescription
import Foundation

// Unreleased source checkouts use the locally built framework. The release script
// sets these two values only when preparing a matching published binary.
let binaryURL: String? = "https://github.com/zshannon/yswift/releases/download/0.7.0/yniffiFFI.xcframework.zip"
let binaryChecksum = "1efcab2a9ede196c3332291d0b51847b6e1fd922ae758a21df21ceafc5b15eaa"
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
