// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Awake",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Awake", targets: ["Lidwake"])
    ],
    targets: [
        .executableTarget(
            name: "Lidwake",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "LidwakeTests",
            dependencies: ["Lidwake"]
        )
    ]
)
