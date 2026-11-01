// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LabforgeMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LabforgeCore",
            targets: ["LabforgeCore"]
        ),
        .executable(
            name: "LabforgeMenuBarApp",
            targets: ["LabforgeMenuBarApp"]
        ),
        .executable(
            name: "LabforgeVerify",
            targets: ["LabforgeVerify"]
        ),
        .executable(
            name: "LabforgeLiveCheck",
            targets: ["LabforgeLiveCheck"]
        )
    ],
    targets: [
        .target(
            name: "LabforgeCore",
            exclude: ["DefaultLabforgeCredentials.swift", "DefaultLabforgeCredentials.swift.example"]
        ),
        .executableTarget(
            name: "LabforgeMenuBarApp",
            dependencies: ["LabforgeCore"]
        ),
        .executableTarget(
            name: "LabforgeVerify",
            dependencies: ["LabforgeCore"]
        ),
        .executableTarget(
            name: "LabforgeLiveCheck",
            dependencies: ["LabforgeCore"]
        )
    ]
)
