// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QBittorrentKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "QBittorrentKit",
            targets: ["QBittorrentKit"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "QBittorrentKit"
        ),
        .testTarget(
            name: "QBittorrentKitTests",
            dependencies: ["QBittorrentKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
