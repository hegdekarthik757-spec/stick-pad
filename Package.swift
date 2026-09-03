// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StickPad",
    platforms: [.macOS(.v14)],
    targets: [
        // All of the app: models, encrypted store and UI.
        .target(
            name: "StickPadKit",
            path: "Sources/StickPadKit"
        ),
        // The app bundle's executable.
        .executableTarget(
            name: "StickPad",
            dependencies: ["StickPadKit"],
            path: "Sources/StickPad"
        ),
        // A standalone test runner. XCTest ships with Xcode, and Stick Pad
        // builds with the Command Line Tools alone, so the suite runs as a
        // plain executable: `swift run StickPadTests`.
        .executableTarget(
            name: "StickPadTests",
            dependencies: ["StickPadKit"],
            path: "Sources/StickPadTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
