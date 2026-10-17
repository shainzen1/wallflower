import os

/// Loggers of the data layer, under the `AppInfo.bundleIdentifier` subsystem. Nothing session
/// specific (names, paths, ids) is logged above debug.
enum DataLog {
    static let registry = Logger(subsystem: AppInfo.bundleIdentifier, category: "registry")
    static let insight = Logger(subsystem: AppInfo.bundleIdentifier, category: "insight")
    /// Window placement (`--log-frame`): frames, screens and Space switches, geometry only.
    static let panel = Logger(subsystem: AppInfo.bundleIdentifier, category: "panel")
}
