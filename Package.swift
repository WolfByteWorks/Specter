// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Specter",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Specter",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Specter",
            // Sparkle.framework is bundled in Specter.app/Contents/Frameworks by build.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
