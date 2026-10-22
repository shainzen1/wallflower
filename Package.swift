// swift-tools-version: 6.2
import Foundation
import PackageDescription

/// With Command Line Tools only, the default (swiftbuild) build system does not hand the
/// swift-testing macro plugin to the compiler. Point at it explicitly, but only while the Command
/// Line Tools are the active developer directory: under Xcode (CI runners have both installed)
/// the plugin is found on its own, and the Command Line Tools' copy may not match Xcode's compiler.
let commandLineTools = "/Library/Developer/CommandLineTools"
let testingPluginPath = commandLineTools + "/usr/lib/swift/host/plugins/testing"
let activeDeveloperDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
let usesCommandLineTools = activeDeveloperDir.map { $0.hasPrefix(commandLineTools) }
    ?? !FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
let testingPluginFlags: [SwiftSetting] = usesCommandLineTools && FileManager.default.fileExists(atPath: testingPluginPath)
    ? [.unsafeFlags(["-plugin-path", testingPluginPath])]
    : []

let package = Package(
    name: "AgentOverview",
    platforms: [.macOS(.v26)],
    products: [
        /// The app's public name. The target and module keep the working name `AgentOverview`.
        .executable(name: "Wallflower", targets: ["AgentOverview"]),
    ],
    dependencies: [
        /// In-app updates. Pinned exactly: `scripts/release.sh` signs with this version's `sign_update`.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentOverview",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/AgentOverview",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            /// `scripts/bundle.sh` puts Sparkle.framework in Contents/Frameworks, next to Contents/MacOS. A
            /// debug build also finds the copy SwiftPM puts next to the bare binary (`swift run`).
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "AgentOverviewTests",
            dependencies: ["AgentOverview"],
            path: "Tests/AgentOverviewTests",
            resources: [.copy("../Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ] + testingPluginFlags
        ),
    ]
)
