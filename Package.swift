// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Winch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WinchDomain", targets: ["WinchDomain"]),
        .executable(name: "winch", targets: ["Winch"]),
    ],
    targets: [
        .target(
            name: "WinchDomain",
            path: "Sources/WinchDomain"
        ),
        .executableTarget(
            name: "Winch",
            dependencies: ["WinchDomain"],
            path: "Sources/Winch"
        ),
        .testTarget(
            name: "WinchDomainTests",
            dependencies: ["WinchDomain"],
            path: "Tests/WinchDomainTests"
        ),
    ]
)
