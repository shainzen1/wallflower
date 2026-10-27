import Foundation
import Testing
@testable import AgentOverview

@Suite("Welcome: page order and sound")
@MainActor
struct WelcomeTourTests {
    @Test func thePagesRunInOrder() {
        #expect(WelcomeModel.Page.allCases == [.hello, .status, .look, .sound, .gestures, .actions, .agents, .setUp])
        #expect(WelcomeModel.Page.allCases.map(\.rawValue) == Array(1...WelcomeModel.pageCount))
        #expect(WelcomeModel.pageCount == 8)
        #expect(WelcomeModel.soundPage == WelcomeModel.lookPage + 1, "the sound follows the look")
        #expect(WelcomeModel.Page.actions.rawValue == WelcomeModel.Page.gestures.rawValue + 1, "actions follow hover, click, drag")
        #expect(WelcomeModel.Page.setUp.rawValue == WelcomeModel.pageCount, "Set up is last, so Start is there")
    }

    @Test func soundChangesAreWrittenAsTheyChange() {
        let start = WelcomeModel.SoundChoices(sound: .wallflowerPing, volume: 0.7, onDone: true, onNeedsInput: true)
        let model = WelcomeModel(page: WelcomeModel.soundPage, sessionSource: .desktop, sound: start, systemSounds: ["Glass", "Tink"])
        var writes: [WelcomeModel.SoundChoices] = []
        var plays = 0
        model.onSoundChange = { writes.append($0) }
        model.onPlaySound = { plays += 1 }
        model.sound.volume = 0.4
        model.sound.onDone = false
        model.sound.onNeedsInput = false
        model.sound.onNeedsInput = false
        #expect(writes.map(\.volume) == [0.4, 0.4, 0.4])
        #expect(writes.map(\.onDone) == [true, false, false])
        #expect(writes.last?.onNeedsInput == false && writes.count == 3, "an unchanged value writes nothing")
        #expect(plays == 0, "volume and switches write without playing")
    }

    @Test func pickingASoundPlaysItOnce() {
        let model = WelcomeModel(sessionSource: .desktop, systemSounds: ["Glass"])
        var writes: [SoundChoice] = []
        var plays = 0
        model.onSoundChange = { writes.append($0.sound) }
        model.onPlaySound = { plays += 1 }
        model.pickSound(.wallflowerPing)
        #expect(writes.isEmpty && plays == 0, "the sound in force: nothing written, nothing played")
        model.pickSound(.system("Glass"))
        #expect(writes == [.system("Glass")] && plays == 1)
        model.pickSound(.none)
        #expect(writes == [.system("Glass"), .none] && plays == 1, "None is silent")
        model.previewSound()
        #expect(plays == 1, "no preview of None")
        model.pickSound(.wallflowerPing)
        model.previewSound()
        #expect(plays == 3)
        model.sound.volume = 0
        model.previewSound()
        #expect(plays == 3, "muted: no preview")
    }

    @Test func nothingPlaysOnItsOwn() {
        let model = WelcomeModel(sessionSource: .desktop)
        var plays = 0
        var writes = 0
        model.onPlaySound = { plays += 1 }
        model.onSoundChange = { _ in writes += 1 }
        for _ in 1...WelcomeModel.pageCount { model.primary() }
        model.go(to: WelcomeModel.soundPage)
        #expect(plays == 0 && writes == 0)
    }

    @Test func thePickerShowsWhatPlays() {
        let missing = WelcomeModel(sessionSource: .desktop, sound: .init(sound: .system("Gone"), volume: 1, onDone: true, onNeedsInput: true), systemSounds: ["Glass"])
        #expect(missing.shownSound == .wallflowerPing, "a sound this macOS lacks plays the ping")
        let custom = WelcomeModel(sessionSource: .desktop, sound: .init(sound: .custom, volume: 1, onDone: true, onNeedsInput: true), customSoundName: "bell.wav")
        #expect(custom.shownSound == .custom)
        #expect(WelcomeModel(sessionSource: .desktop).sound == .standard)
    }
}
