// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StarPlayrRadioKit",
    platforms: [
           .macOS(.v10_15),
           .iOS(.v13)
       ],
    products: [
        .library(
            name: "StarPlayrRadioKit",
            targets: ["StarPlayrRadioKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/StarPlayrX/StarPlayrXServe", branch: "viper")
    ],
    targets: [
        .target(
            name: "StarPlayrRadioKit",
            dependencies: [.product(name: "StarPlayrXServe", package: "StarPlayrXServe")]
        ),
    ]
)
