import ProjectDescription

let packages: [Package] = [
    .package(path: .relativeToCurrentFile("../..")),
]
let dependencies = Dependencies(
    swiftPackageManager: SwiftPackageManagerDependencies(
        packages
    ),
    platforms: [.iOS]
)
