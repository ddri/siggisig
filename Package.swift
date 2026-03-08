// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SiggiSig",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SiggiSig",
            path: "SiggiSig",
            exclude: ["Info.plist", "SiggiSig.entitlements"]
        ),
        .testTarget(
            name: "SiggiSigTests",
            dependencies: ["SiggiSig"],
            path: "Tests"
        )
    ]
)
