// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TaskBuddy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TaskBuddyCore", targets: ["TaskBuddyCore"]),
        .executable(name: "TaskBuddy", targets: ["TaskBuddyApp"])
    ],
    targets: [
        .target(name: "TaskBuddyCore"),
        .executableTarget(
            name: "TaskBuddyApp",
            dependencies: ["TaskBuddyCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "TaskBuddyCoreTests", dependencies: ["TaskBuddyCore"])
    ],
    swiftLanguageVersions: [.v5]
)
