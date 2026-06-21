// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "macvision",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macvision", targets: ["macvision"])
    ],
    targets: [
        .executableTarget(
            name: "macvision",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(name: "macvisionTests", dependencies: ["macvision"]),
    ]
)
