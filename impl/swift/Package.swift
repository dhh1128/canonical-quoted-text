// swift-tools-version:5.9
import PackageDescription

// The port keeps the name it has always had rather than becoming
// Sources/Cqt/Cqt.swift, so the target points at it directly.
let package = Package(
    name: "Cqt",
    products: [
        .library(name: "Cqt", targets: ["Cqt"])
    ],
    targets: [
        .target(
            name: "Cqt",
            path: ".",
            exclude: ["Tests"],
            sources: ["Cqt.swift"]
        ),
        .testTarget(
            name: "CqtTests",
            dependencies: ["Cqt"],
            path: "Tests/CqtTests"
        )
    ]
)
