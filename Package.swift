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
    targets: [
        .executableTarget(
            name: "AgentOverview",
            path: "Sources/AgentOverview",
            swiftSettings: [
                .swiftLanguageMode(.v6)
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
