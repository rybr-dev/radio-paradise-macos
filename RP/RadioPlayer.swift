import Foundation
import AudioStreaming
import MediaPlayer
import Cocoa

struct SongInfo {
    var artist: String = ""
    var title: String = ""
    var songId: String = ""
    var coverArt: NSImage? = nil
}

class RadioPlayer: NSObject, AudioPlayerDelegate {
    static let shared = RadioPlayer()

    private var player: AudioPlayer?
    private var timer: Timer?
    private var pauseTimer: Timer?

    private var songInfo: SongInfo = SongInfo()
    private var originalSongInfo: SongInfo = SongInfo()
    private var isPausedLongEnough = false
    func currentSongInfo() -> SongInfo {
        return songInfo
    }
    
    private override init() {
        super.init()
        setupPlayer()
    }

    func togglePlayPause() {
        if ![.playing, .bufferring].contains(player?.state) {
            self.play()
        } else {
            self.pause()
        }
    }

    func play() {
        // Cancel pause timer and restore original song info if needed
        pauseTimer?.invalidate()
        pauseTimer = nil

        if isPausedLongEnough {
            isPausedLongEnough = false
            songInfo = originalSongInfo
        }

        player?.play(url: currentStreamURL)
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        startPauseTimer()
    }

    private func startPauseTimer() {
        // Cancel any existing pause timer
        pauseTimer?.invalidate()

        // Store the original song info before we potentially modify it
        originalSongInfo = songInfo
        isPausedLongEnough = false

        // Start a 15-second timer
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.handleLongPause()
        }
    }

    private func handleLongPause() {
        guard !isPlaying else { return }

        isPausedLongEnough = true

        // Stop the song update timer since we're no longer showing real song info
        timer?.invalidate()
        timer = nil

        // Get current channel name
        let currentChannelIndex = getCurrentChannelIndex()
        let channelName = CHANNEL_DATA[currentChannelIndex].title

        // Update song info to show Radio Paradise and channel name
        songInfo = SongInfo(
            artist: "Radio Paradise",
            title: channelName,
            songId: "",
            coverArt: NSImage(named: "AppIcon")
        )

        // Update the UI
        updateUI()
    }

    func stop() {
        timer?.invalidate()
        pauseTimer?.invalidate()
        pauseTimer = nil
        isPausedLongEnough = false
        player?.stop()
    }

    func switchChannel() {
        let wasPlaying = isPlaying

        // Stop current playback and cancel pause timer
        timer?.invalidate()
        pauseTimer?.invalidate()
        pauseTimer = nil
        isPausedLongEnough = false
        player?.stop()

        // Only restart if we were playing before
        if wasPlaying {
            // Wait a moment for the stop to complete, then start with new channel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.play()
            }
        }
    }

    var isPlaying: Bool {
        return [.playing, .bufferring, .running].contains(player?.state)
    }

    private func findCurrentlyPlayingSong(from songs: [[String: Any]]) -> [String: Any]? {
        let currentTime = Date().timeIntervalSince1970

        for song in songs {
            guard let playTimeMillis = song["play_time"] as? TimeInterval,
                  let durationString = song["duration"] as? String,
                  let durationMillis = Double(durationString) else {
                continue
            }

            // Convert milliseconds to seconds
            let playTime = playTimeMillis / 1000
            let duration = durationMillis / 1000
            let endTime = playTime + duration

            // Check if current time falls within this song's play window
            if currentTime >= playTime && currentTime < endTime {
                print("Found currently playing song: \(song["title"] as? String ?? "Unknown") - \(song["artist"] as? String ?? "Unknown")")
                print("Play time: \(playTime), Duration: \(duration), Current: \(currentTime)")
                return song
            }
        }

        // Fallback: if no song matches current time, return the first song
        // This handles edge cases like network delays or timing mismatches
        print("No song found for current time \(currentTime), falling back to first song")
        return songs.first
    }

    private func setupPlayer() {
        player = AudioPlayer()
        player?.delegate = self

        MPRemoteCommandCenter.shared().playCommand.addTarget { event in
            self.play()
            return .success
        }
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { event in
            self.pause()
            return .success
        }
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.addTarget { event in
            self.togglePlayPause()
            return .success
        }
    }

    func updateNowPlaying() {
        let task = URLSession.shared.dataTask(with: currentChannelInfoURL) {
            [weak self] data,
            response,
            error in
            guard let self = self,
                  let data = data,
                  error == nil else {
                print("Error fetching now playing info: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let songs = json["song"] as? [[String: Any]],
                   let currentSong = findCurrentlyPlayingSong(from: songs),
                   let playTimeMillis = currentSong["play_time"] as? TimeInterval,
                   let durationMillis = currentSong["duration"] as? String {

                    // Get artist, title, and song ID
                    var artist = currentSong["artist"] as? String ?? "Unknown Artist"
                    var title = currentSong["title"] as? String ?? "Unknown Song"
                    var songId = currentSong["song_id"] as? String ?? ""
                    let coverArtUrl = currentSong["cover"] as? String ?? ""

                    // Convert milliseconds to seconds
                    let playTime = playTimeMillis / 1000
                    let duration = (Double(durationMillis) ?? 0) / 1000

                    // Calculate when the next song should start
                    let nextSongTime = playTime + duration

                    // Calculate how many seconds from now until the next song
                    var onRadioBreak = false
                    let currentTime = Date().timeIntervalSince1970
                    let timeUntilNextSong = max(nextSongTime - currentTime + 5, 5)
                    print("∆: \(nextSongTime - currentTime)")
                    if (nextSongTime - currentTime < 0) {
                        // We're probably in a commercial break. Set the title and refresh a little later.
                        artist = "Radio Paradise"
                        title = "Break"
                        songId = ""
                        onRadioBreak = true
                    }

                    if (onRadioBreak) {
                        DispatchQueue.main.async {
                            self.songInfo.coverArt = NSImage(named: "AppIcon")
                            self.updateUI()
                        }
                    } else if (coverArtUrl.isEmpty) {
                        self.songInfo.coverArt = nil
                        self.updateUI()
                    } else {
                        let url = URL(string: "https://img.radioparadise.com/\(coverArtUrl)")!
                        let dataTask = URLSession.shared.dataTask(with: url) { [weak self] (data, _, _) in
                            if let data = data, let image = NSImage(data: data) {
                                self?.songInfo.coverArt = image
                                self?.updateUI()
                            }
                        }
                        dataTask.resume()
                    }

                    DispatchQueue.main.async {
                        // Update stored song info
                        if (songId != self.songInfo.songId) {
                            self.songInfo = SongInfo(
                                artist: artist,
                                title: title,
                                songId: songId,
                                coverArt: nil
                            )
                            MusicService.shared.preloadCurrentSong()
                        }

                        self.updateUI()

                        // Schedule the next update
                        self.scheduleNextUpdate(in: timeUntilNextSong)
                    }
                }
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")

                // If there's an error, try again in 30 seconds
                DispatchQueue.main.async {
                    self.scheduleNextUpdate(in: 30)
                }
            }
        }

        task.resume()
    }

    private func updateSystemNowPlaying() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = self.songInfo.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = self.songInfo.artist
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: self.player?.rate ?? 0.0)
        if let coverArt = self.songInfo.coverArt {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: coverArt.size) { (
                size: CGSize
            ) -> NSImage in
                return coverArt
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = self.isPlaying ? .playing : .paused
    }

    private func scheduleNextUpdate(in seconds: TimeInterval) {
        // Cancel any existing timer
        timer?.invalidate()

        // Schedule a new timer
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.updateNowPlaying()
        }

        print("Next song info update scheduled in \(Int(seconds)) seconds")
    }

    func updateUI() {
        let isPlaying = self.isPlaying
        DispatchQueue.main.async {
            StatusMenuController.shared.updatePlayPauseButton(isPlaying: isPlaying)
            StatusMenuController.shared.updateNowPlaying()
            StatusMenuController.shared.updateAlbumArt()
            self.updateSystemNowPlaying()
        }
    }

    // MARK: - AudioPlayerDelegate

    func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        switch (newState) {
        case .ready:
            updateNowPlaying()
            fallthrough
        case .error:
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.setupPlayer()
                self.play()
            }
            fallthrough
        case .playing, .bufferring, .running:
            // Cancel pause timer when playing
            pauseTimer?.invalidate()
            pauseTimer = nil
            if isPausedLongEnough {
                isPausedLongEnough = false
                songInfo = originalSongInfo
            }
            self.updateUI()
            break
        case .paused:
            startPauseTimer()
            self.updateUI()
            break
        case .stopped:
            pauseTimer?.invalidate()
            pauseTimer = nil
            isPausedLongEnough = false
            self.updateUI()
            break
        default:
            break
        }
    }

    func audioPlayerDidStartPlaying(player: AudioStreaming.AudioPlayer, with entryId: AudioStreaming.AudioEntryId) {}
    func audioPlayerDidFinishBuffering(player: AudioStreaming.AudioPlayer, with entryId: AudioStreaming.AudioEntryId) {}
    func audioPlayerDidFinishPlaying(player: AudioStreaming.AudioPlayer, entryId: AudioStreaming.AudioEntryId, stopReason: AudioStreaming.AudioPlayerStopReason, progress: Double, duration: Double) {}
    func audioPlayerUnexpectedError(player: AudioStreaming.AudioPlayer, error: AudioStreaming.AudioPlayerError) {}
    func audioPlayerDidCancel(player: AudioStreaming.AudioPlayer, queuedItems: [AudioStreaming.AudioEntryId]) {}
    func audioPlayerDidReadMetadata(player: AudioStreaming.AudioPlayer, metadata: [String : String]) {}
}
