import AppKit

/// `--render-icon <folder>` writes the icon set and quits before any window or status item exists.
if let iconFolder = IconRenderer.requestedFolder(in: CommandLine.arguments) {
    exit(IconRenderer.run(folder: iconFolder))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
