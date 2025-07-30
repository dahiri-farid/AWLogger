// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AWLogger",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AWLogger",
            targets: ["AWLogger"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", from: "2.1.1")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AWLogger",
            dependencies: [
                .product(name: "SwiftyBeaver", package: "SwiftyBeaver")
            ],
            swiftSettings: [
                .define("AWLOGGER_EXPORTS_SWIFTYBEAVER")
            ]
        ),

    ]
)
