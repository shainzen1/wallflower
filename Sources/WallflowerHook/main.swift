import Darwin
import Foundation
import WallflowerHookCore

// wallflower-hook <tool> <event>: called by an agent's hook with the event's JSON on stdin. Writes
// the session's status into Wallflower's sessions folder (docs/agents.md). Prints nothing, on stdout
// or stderr (Gemini parses stderr when stdout is empty), and always exits 0, so it can never block,
// fail or steer the agent, whatever happens: a missing folder, garbage on stdin, a slow disk.

// A hard stop after two seconds, still with status 0.
signal(SIGALRM) { _ in _exit(0) }
alarm(2)
// A closed pipe on the far side must not kill the helper with a signal status.
signal(SIGPIPE, SIG_IGN)

/// Stdin up to `HookPayload.maxBytes` (a larger payload is dropped, the rest still read so the tool's
/// write never fails on a closed pipe); nothing when stdin is a terminal (the helper run by hand).
func readInput() -> Data {
    guard isatty(STDIN_FILENO) == 0 else { return Data() }
    var data = Data()
    var oversized = false
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count <= 0 { break }
        guard !oversized else { continue }
        data.append(contentsOf: buffer.prefix(count))
        if data.count > HookPayload.maxBytes {
            oversized = true
            data = Data()
        }
    }
    return data
}

let input = readInput()
// The path it was started by (not resolved: a symlinked `~/.local` still names the right home).
let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
let folder = HookRunner.sessionsFolder(environment: ProcessInfo.processInfo.environment, executablePath: executable)
HookRunner.run(
    arguments: Array(CommandLine.arguments.dropFirst()), stdin: input, sessionsFolder: folder, start: getppid(),
    inspector: SystemProcessInspector()
)
_exit(0)
