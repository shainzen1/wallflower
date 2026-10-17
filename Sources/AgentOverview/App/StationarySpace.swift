import AppKit
import Darwin

/// A window-server Space of the panel's own, so a Space switch never moves the panel.
///
/// Why: with `.canJoinAllSpaces` + `.fullScreenAuxiliary` (+ `.stationary`) the window server still
/// treats the panel as part of the regular desktop while a full-screen Space slides in or out. The
/// panel rides along with the slide and then snaps back to the edge (measured with
/// `CGWindowListCopyWindowInfo` while switching between a desktop and a full-screen Space: its x went
/// from the screen edge to the far left and back over the ~1 s transition, while `NSWindow.frame`
/// never changed and no screen-parameter notification arrived). Window level (status bar, pop-up
/// menu, screen saver), dropping `.stationary`, `.transient`, `.canJoinAllApplications` and
/// re-ordering the window on `activeSpaceDidChangeNotification` all left the slide unchanged.
/// A window in a Space of its own with an absolute level above the user Spaces is composited above
/// them and takes no part in their transitions: the same measurement then shows no movement at all.
///
/// The calls (`CGSSpaceCreate` and friends) are exported by CoreGraphics but declared in no public
/// header. They are looked up at runtime with `dlsym`; when one is missing, `init` returns nil and
/// the panel keeps the plain collection behaviour (and the slide). The Space dies with the process.
@MainActor
final class StationarySpace {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias CreateFn = @convention(c) (Int32, Int, CFDictionary?) -> UInt64
    private typealias LevelFn = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias SpacesFn = @convention(c) (Int32, CFArray) -> Void
    private typealias WindowsFn = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias ActiveSpaceFn = @convention(c) (Int32) -> UInt64

    private let connection: Int32
    private let space: UInt64
    private let addWindows: WindowsFn

    /// Creates and shows the Space at `level` (a Space level, not a window level: user Spaces sit at 0).
    init?(level: Int32) {
        guard
            let connectionFn: ConnectionFn = Self.symbol("_CGSDefaultConnection"),
            let create: CreateFn = Self.symbol("CGSSpaceCreate"),
            let setLevel: LevelFn = Self.symbol("CGSSpaceSetAbsoluteLevel"),
            let show: SpacesFn = Self.symbol("CGSShowSpaces"),
            let add: WindowsFn = Self.symbol("CGSAddWindowsToSpaces")
        else { return nil }
        connection = connectionFn()
        // Flag 1: a plain Space (other values make Finder draw desktop icons into it).
        space = create(connection, 1, nil)
        guard space != 0 else { return nil }
        addWindows = add
        setLevel(connection, space, level)
        show(connection, [NSNumber(value: space)] as CFArray)
    }

    /// Moves a window into the Space. Call after every order-in (an ordered-out window leaves it).
    func add(_ window: NSWindow) {
        let number = window.windowNumber
        guard number > 0 else { return }
        addWindows(connection, [NSNumber(value: number)] as CFArray, [NSNumber(value: space)] as CFArray)
    }

    /// The window server's id of the active user Space, 0 when the call is missing (`--log-frame` only).
    static func activeSpaceID() -> UInt64 {
        guard let connection: ConnectionFn = symbol("_CGSDefaultConnection"), let active: ActiveSpaceFn = symbol("CGSGetActiveSpace") else { return 0 }
        return active(connection())
    }

    private static func symbol<T>(_ name: String) -> T? {
        // RTLD_DEFAULT: search every image loaded into the process (CoreGraphics re-exports these).
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
