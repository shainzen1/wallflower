import AVFoundation
import Foundation

/// Plays one sound file, decoded once: the player for the last file stays cached until another file
/// plays or `invalidate` drops it (a new custom file under the same name). Nothing runs between
/// plays.
@MainActor
final class SoundPlayer {
    private var player: AVAudioPlayer?
    private var loadedURL: URL?

    /// Plays `url` from its start at `volume` (0 to 1), cutting off a sound still playing. Returns
    /// whether playback started.
    @discardableResult
    func play(_ url: URL, volume: Double) -> Bool {
        if loadedURL != url || player == nil {
            player?.stop()
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            loadedURL = url
        }
        guard let player else { return false }
        player.stop()
        player.currentTime = 0
        player.volume = Float(min(max(volume, 0), 1))
        return player.play()
    }

    /// Drops the cached player, so the next play reads the file again.
    func invalidate() {
        player?.stop()
        player = nil
        loadedURL = nil
    }
}
