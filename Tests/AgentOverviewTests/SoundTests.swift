import Foundation
import Testing
@testable import AgentOverview

/// A fresh `UserDefaults` suite per test, removed afterwards.
private final class SoundScratchDefaults {
    let name = "WallflowerSoundTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

/// A 16-bit mono PCM WAV of silence, `seconds` long, at 8 kHz (small files for long durations).
private func writeSilentWAV(to url: URL, seconds: Double, sampleRate: Int = 8_000) throws {
    let frames = Int(Double(sampleRate) * seconds)
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + frames * 2))
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2))
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    append(UInt32(frames * 2))
    data.append(Data(count: frames * 2))
    try data.write(to: url)
}

// MARK: Transitions and collapse

struct SoundTriggerTests {
    @Test func doneIsWorkingToIdleOnly() {
        #expect(SoundEvent.event(from: .working, to: .idle) == .done)
        #expect(SoundEvent.event(from: .needsInput(kind: .question), to: .idle) == nil, "a dismissed prompt is not a finished turn")
        #expect(SoundEvent.event(from: .idle, to: .working) == nil)
        #expect(SoundEvent.event(from: .idle, to: .idle) == nil)
    }

    @Test func needsInputIsEnteringIt() {
        #expect(SoundEvent.event(from: .working, to: .needsInput(kind: .permission)) == .needsInput)
        #expect(SoundEvent.event(from: .idle, to: .needsInput(kind: .question)) == .needsInput)
        #expect(
            SoundEvent.event(from: .needsInput(kind: .question), to: .needsInput(kind: .permission)) == nil,
            "a change within needs input is the same state"
        )
        #expect(SoundEvent.event(from: .needsInput(kind: .other), to: .working) == nil)
    }

    @Test func severalTransitionsWithinTheWindowPlayOneSound() {
        var announcer = SoundAnnouncer(window: 1)
        let start = Date(timeIntervalSince1970: 1_000)
        let options = SoundAnnouncer.Options()
        #expect(announcer.announce([.init(event: .done)], options: options, at: start) == .done)
        #expect(announcer.announce([.init(event: .done)], options: options, at: start.addingTimeInterval(0.4)) == nil)
        #expect(announcer.announce([.init(event: .needsInput)], options: options, at: start.addingTimeInterval(0.9)) == nil)
        #expect(announcer.announce([.init(event: .done)], options: options, at: start.addingTimeInterval(1.0)) == .done, "the window is over")
        #expect(announcer.lastPlayed == start.addingTimeInterval(1.0))
    }

    @Test func needsInputWinsInABatch() {
        var announcer = SoundAnnouncer()
        let event = announcer.announce([.init(event: .done), .init(event: .needsInput), .init(event: .done)], options: .init(), at: Date())
        #expect(event == .needsInput)
    }

    @Test func quietChangesDoNotOpenTheWindow() {
        var announcer = SoundAnnouncer(window: 1)
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(announcer.announce([.init(event: .done, isHidden: true)], options: .init(), at: start) == nil)
        #expect(announcer.lastPlayed == nil)
        #expect(announcer.announce([.init(event: .done)], options: .init(), at: start.addingTimeInterval(0.2)) == .done)
    }

    @Test func switchesHiddenAndFrontmost() {
        var options = SoundAnnouncer.Options()
        #expect(SoundAnnouncer.passes(.init(event: .done), options: options))
        #expect(!SoundAnnouncer.passes(.init(event: .done, isHidden: true), options: options))
        #expect(!SoundAnnouncer.passes(.init(event: .needsInput, hostIsFrontmost: true), options: options))
        #expect(SoundAnnouncer.passes(.init(event: .needsInput, hostIsFrontmost: false), options: options))
        #expect(SoundAnnouncer.passes(.init(event: .needsInput, hostIsFrontmost: nil), options: options), "unknown app: no guess, it plays")
        options.skipsFrontmost = false
        #expect(SoundAnnouncer.passes(.init(event: .needsInput, hostIsFrontmost: true), options: options))
        options.onDone = false
        #expect(!SoundAnnouncer.passes(.init(event: .done), options: options))
        #expect(SoundAnnouncer.passes(.init(event: .needsInput), options: options))
        options.onNeedsInput = false
        #expect(!SoundAnnouncer.passes(.init(event: .needsInput), options: options))
    }

    @Test func aBatchWhoseWinnerIsFilteredFallsBackToTheRest() {
        var announcer = SoundAnnouncer()
        var options = SoundAnnouncer.Options()
        options.onNeedsInput = false
        #expect(announcer.announce([.init(event: .needsInput), .init(event: .done)], options: options, at: Date()) == .done)
    }

    @Test func hostFollowsTheClickRoute() {
        #expect(SoundHost(route: .claudeApp) == .bundle(SessionOpener.claudeBundleIdentifier))
        #expect(SoundHost(route: .claudeDeepLink(URL(string: "claude://code/continue?session=x")!)) == .bundle(SessionOpener.claudeBundleIdentifier))
        #expect(SoundHost(route: .hostApp(pid: 42, fallsBackToClaude: true)) == .process(42))
        #expect(SoundHost(route: .app(bundleID: "com.example.editor")) == .bundle("com.example.editor"))
        #expect(SoundHost(route: .url(URL(string: "https://example.com")!)) == .unknown)
        #expect(SoundHost(route: .command(script: "", fileName: "x.command")) == .unknown)
        #expect(SoundHost(route: .nothing) == .unknown)
    }
}

// MARK: Store and controller

@MainActor
struct SoundStoreTests {
    private func record(_ fixture: String, pid: pid_t, status: RegistryStatus, waitingFor: String? = nil) throws -> SessionRecord {
        var record = try TestSupport.fixtureRecord(fixture)
        record.pid = pid
        record.status = status
        record.waitingFor = waitingFor
        return record
    }

    @Test func statesFoundByAScanAreNoChanges() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        var batches: [[SessionStateChange]] = []
        store.onStateChanges = { batches.append($0) }
        let waiting = try record("busy-desktop", pid: TestSupport.livePid, status: .waiting, waitingFor: "input needed")
        store.reconcile(RegistryScanResult(records: [waiting], presentPids: [waiting.pid]))
        #expect(batches.isEmpty, "a session waiting at launch plays nothing")

        // The same state again, and a session that appears later already idle: still nothing.
        let idle = try record("idle-desktop", pid: TestSupport.otherLivePid, status: .idle)
        store.reconcile(RegistryScanResult(records: [waiting, idle], presentPids: [waiting.pid, idle.pid]))
        #expect(batches.isEmpty)

        // A real transition.
        let working = try record("idle-desktop", pid: TestSupport.otherLivePid, status: .busy)
        store.reconcile(RegistryScanResult(records: [waiting, working], presentPids: [waiting.pid, working.pid]))
        #expect(batches.count == 1)
        #expect(batches.first?.first?.from == .idle)
        #expect(batches.first?.first?.to == .working)
    }

    @Test func controllerPlaysForTransitionsButNotForHiddenSessions() throws {
        let scratch = SoundScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        settings.sound = .none  // decide, never actually play in a test
        settings.soundSkipsFrontmost = false
        var clock = Date(timeIntervalSince1970: 5_000)
        let controller = SoundController(settings: settings, folder: URL(filePath: "/nonexistent"), now: { clock })
        let hidden = HiddenSessions(defaults: scratch.defaults)
        controller.hiddenSessions = hidden
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        var events: [SoundEvent?] = []
        store.onStateChanges = { events.append(controller.handle($0)) }

        let a = try record("busy-desktop", pid: TestSupport.livePid, status: .busy)
        let b = try record("idle-desktop", pid: TestSupport.otherLivePid, status: .busy)
        store.reconcile(RegistryScanResult(records: [a, b], presentPids: [a.pid, b.pid]))
        #expect(events.isEmpty)

        // Both change in one scan: one sound, needs input.
        let aDone = try record("busy-desktop", pid: a.pid, status: .idle)
        let bWaits = try record("idle-desktop", pid: b.pid, status: .waiting, waitingFor: "permission prompt")
        store.reconcile(RegistryScanResult(records: [aDone, bWaits], presentPids: [a.pid, b.pid]))
        #expect(events == [.needsInput])

        // Hidden: its change stays quiet even after the window.
        clock = clock.addingTimeInterval(5)
        let bKey = try #require(store.sessions.first { $0.pid == b.pid })
        hidden.hide(bKey)
        let bWorks = try record("idle-desktop", pid: b.pid, status: .busy)
        store.reconcile(RegistryScanResult(records: [aDone, bWorks], presentPids: [a.pid, b.pid]))
        let bDone = try record("idle-desktop", pid: b.pid, status: .idle)
        store.reconcile(RegistryScanResult(records: [aDone, bDone], presentPids: [a.pid, b.pid]))
        #expect(events == [.needsInput, nil, nil], "two changes of the hidden session, both quiet")

        // The switch off: no done.
        settings.soundOnDone = false
        let aWorks = try record("busy-desktop", pid: a.pid, status: .busy)
        store.reconcile(RegistryScanResult(records: [aWorks, bDone], presentPids: [a.pid, b.pid]))
        store.reconcile(RegistryScanResult(records: [aDone, bDone], presentPids: [a.pid, b.pid]))
        #expect(events.compactMap { $0 } == [.needsInput], "working, then done with the done switch off: quiet")
        #expect(events.count == 5)
    }
}

// MARK: Custom files

struct CustomSoundTests {
    @Test func rulesInOrder() {
        #expect(CustomSound.check(name: "a.ogg", fileExtension: "ogg", byteCount: 10, duration: 1) == .unsupportedType(name: "a.ogg"))
        #expect(CustomSound.check(name: "a.WAV", fileExtension: "WAV", byteCount: 10, duration: 1) == nil, "any case")
        for ext in ["aiff", "aif", "wav", "mp3", "m4a", "caf"] {
            #expect(CustomSound.check(name: "a.\(ext)", fileExtension: ext, byteCount: 10, duration: 1) == nil)
        }
        let big = CustomSound.maxBytes + 1
        #expect(CustomSound.check(name: "a.wav", fileExtension: "wav", byteCount: big, duration: 1) == .tooLarge(name: "a.wav", bytes: big))
        #expect(CustomSound.check(name: "a.wav", fileExtension: "wav", byteCount: CustomSound.maxBytes, duration: 5) == nil, "the limits themselves pass")
        #expect(CustomSound.check(name: "a.wav", fileExtension: "wav", byteCount: 10, duration: 5.2) == .tooLong(name: "a.wav", seconds: 5.2))
        #expect(CustomSound.check(name: "a.wav", fileExtension: "wav", byteCount: 10, duration: nil) == .unreadable(name: "a.wav"))
    }

    @Test func messagesSayWhatToDo() {
        #expect(CustomSound.Problem.tooLong(name: "x.wav", seconds: 7.25).message.contains("5 seconds or less"))
        #expect(CustomSound.Problem.tooLarge(name: "x.wav", bytes: 7_000_000).message.contains("5 MB or less"))
        #expect(CustomSound.Problem.unsupportedType(name: "x.ogg").message.contains("AIFF, WAV, MP3, M4A or CAF"))
    }

    @Test func validatesRealFiles() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let short = folder.appending(path: "short.wav")
        try writeSilentWAV(to: short, seconds: 1)
        #expect(CustomSound.validate(short) == nil)
        #expect(abs((CustomSound.duration(of: short) ?? 0) - 1) < 0.01)

        let long = folder.appending(path: "long.wav")
        try writeSilentWAV(to: long, seconds: 6)
        guard case .tooLong(_, let seconds)? = CustomSound.validate(long) else {
            Issue.record("a 6 s file must be refused as too long")
            return
        }
        #expect(abs(seconds - 6) < 0.01)

        let junk = folder.appending(path: "junk.wav")
        try Data("not a sound".utf8).write(to: junk)
        #expect(CustomSound.validate(junk) == .unreadable(name: "junk.wav"))

        // Over 5 MB: refused by size before it is ever opened (sparse, so nothing is really written).
        let huge = folder.appending(path: "huge.wav")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(CustomSound.maxBytes + 1))
        try handle.close()
        #expect(CustomSound.validate(huge) == .tooLarge(name: "huge.wav", bytes: CustomSound.maxBytes + 1))

        let text = folder.appending(path: "notes.txt")
        try Data("x".utf8).write(to: text)
        #expect(CustomSound.validate(text) == .unsupportedType(name: "notes.txt"))
    }

    @Test func installKeepsOneCopyThatOutlivesTheOriginal() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sounds = folder.appending(path: "Sounds", directoryHint: .isDirectory)
        let first = folder.appending(path: "first.wav")
        try writeSilentWAV(to: first, seconds: 0.5)
        #expect(try CustomSound.install(first, into: sounds) == "first.wav")
        try FileManager.default.removeItem(at: first)
        #expect(CustomSound.installedURL(named: "first.wav", in: sounds) != nil, "the copy survives the original")

        let second = folder.appending(path: "second.wav")
        try writeSilentWAV(to: second, seconds: 0.5)
        #expect(try CustomSound.install(second, into: sounds) == "second.wav")
        #expect(try FileManager.default.contentsOfDirectory(atPath: sounds.path) == ["second.wav"], "a new copy replaces the old one")

        // A refused file leaves the current copy alone.
        let long = folder.appending(path: "long.wav")
        try writeSilentWAV(to: long, seconds: 6)
        #expect(throws: CustomSound.Problem.self) { try CustomSound.install(long, into: sounds) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: sounds.path) == ["second.wav"])

        // Choosing the copy itself again keeps it.
        #expect(try CustomSound.install(sounds.appending(path: "second.wav"), into: sounds) == "second.wav")
        #expect(CustomSound.installedURL(named: "second.wav", in: sounds) != nil)
    }

    @Test func missingFilesFallBackToThePing() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let ping = try #require(SoundLibrary.pingURL)
        #expect(SoundLibrary.url(for: .custom, customName: "gone.wav", folder: folder) == ping)
        #expect(SoundLibrary.url(for: .custom, customName: nil, folder: folder) == ping)
        #expect(SoundLibrary.url(for: .system("No Such Sound"), customName: nil, folder: folder) == ping)
        #expect(SoundLibrary.url(for: .none, customName: nil, folder: folder) == nil)
        #expect(SoundLibrary.systemSoundURL(named: "../etc/passwd") == nil)
    }

    @Test func bundledPingDecodes() throws {
        let ping = try #require(SoundLibrary.pingURL)
        let duration = try #require(CustomSound.duration(of: ping))
        #expect(duration > 0.2 && duration < 2)
    }
}

// MARK: Settings and launch arguments

@MainActor
struct SoundSettingsTests {
    @Test func defaults() {
        let scratch = SoundScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.sound == .wallflowerPing)
        #expect(settings.customSoundName == nil)
        #expect(settings.soundVolume == 0.7)
        #expect(settings.soundOnDone)
        #expect(settings.soundOnNeedsInput)
        #expect(settings.soundSkipsFrontmost)
        #expect(settings.soundOptions == SoundAnnouncer.Options())
    }

    @Test func storedValuesRoundTrip() {
        let scratch = SoundScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        settings.sound = .system("Glass")
        settings.customSoundName = "mine.wav"
        settings.soundVolume = 0.25
        settings.soundOnDone = false
        settings.soundSkipsFrontmost = false
        let reread = AppSettings(defaults: scratch.defaults)
        #expect(reread.sound == .system("Glass"))
        #expect(reread.customSoundName == "mine.wav")
        #expect(reread.soundVolume == 0.25)
        #expect(!reread.soundOnDone)
        #expect(reread.soundOnNeedsInput)
        #expect(!reread.soundSkipsFrontmost)
    }

    @Test func launchArgumentBeatsStoredSoundAndIsNotWritten() {
        let scratch = SoundScratchDefaults()
        scratch.defaults.set("custom", forKey: AppSettings.Key.sound)
        let settings = AppSettings(defaults: scratch.defaults, overrides: AppSettings.Overrides(sound: SoundChoice.none))
        #expect(settings.sound == .none)
        #expect(scratch.defaults.string(forKey: AppSettings.Key.sound) == "custom")
    }

    @Test func setValueTakesSoundKeys() {
        let scratch = SoundScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.setValue("Tink", forKey: AppSettings.Key.sound))
        #expect(settings.sound == .system("Tink"))
        #expect(settings.setValue("0.4", forKey: AppSettings.Key.soundVolume))
        #expect(settings.soundVolume == 0.4)
        #expect(!settings.setValue("1.5", forKey: AppSettings.Key.soundVolume))
        #expect(settings.setValue("off", forKey: AppSettings.Key.soundOnNeedsInput))
        #expect(!settings.soundOnNeedsInput)
    }

    @Test func choiceNames() {
        let choices: [SoundChoice] = [.wallflowerPing, .system("Glass"), .custom, .none]
        for choice in choices {
            #expect(SoundChoice(storedName: choice.storedName) == choice)
        }
        #expect(SoundChoice(storedName: "off") == SoundChoice.none)
        #expect(SoundChoice(storedName: "Glass") == .system("Glass"))
        #expect(SoundChoice(storedName: "") == nil)
        #expect(SoundChoice(storedName: "system:") == nil)
    }

    @Test func pickerShowsWhatPlays() {
        #expect(SoundSettingsView.shownChoice(.custom, customName: nil, systemSounds: []) == .wallflowerPing)
        #expect(SoundSettingsView.shownChoice(.custom, customName: "a.wav", systemSounds: []) == .custom)
        #expect(SoundSettingsView.shownChoice(.system("Gone"), customName: nil, systemSounds: ["Glass"]) == .wallflowerPing)
        #expect(SoundSettingsView.shownChoice(.system("Glass"), customName: nil, systemSounds: ["Glass"]) == .system("Glass"))
    }

    @Test func launchArguments() {
        let arguments = LaunchArguments(["app", "--sounds-folder", "/tmp/s", "--sound", "off", "--play-sound", "--sound-file", "/tmp/a.wav"])
        #expect(arguments.soundsFolder?.path == "/tmp/s")
        #expect(arguments.sound == SoundChoice.none)
        #expect(arguments.settingsOverrides.sound == SoundChoice.none)
        #expect(arguments.playSound)
        #expect(arguments.soundFile?.path == "/tmp/a.wav")
        #expect(LaunchArguments(["app"]).sound == nil)
        #expect(LaunchArguments(["app", "--sound", "Glass"]).sound == .system("Glass"))
        #expect(LaunchArguments(["app", "--show-settings", "sound"]).showSettings == .sound)
    }
}
