import Foundation
import AudioStreaming
import MediaPlayer
import Cocoa

let RP_STREAM_URL = URL(string: "http://stream.radioparadise.com/aac-320")!
let RP_API_URL = URL(string: "https://api.radioparadise.com/api/nowplaying_list_v2022?mode=wip-channel&chan=0")!

class RadioPlayer: NSObject, AudioPlayerDelegate {
    static let shared = RadioPlayer()

    private var player: AudioPlayer?
    private var timer: Timer?

    private var currentArtist: String = ""
    private var currentTitle: String = ""
    private var currentSongId: String = ""
    private var currentCoverArt: NSImage?

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
        player?.play(url: RP_STREAM_URL)
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        timer?.invalidate()
        player?.stop()
    }

    var isPlaying: Bool {
        return [.playing, .bufferring, .running].contains(player?.state)
    }

    var currentAlbumArt: NSImage? {
        return currentCoverArt
    }

    var currentSongInfo: (songId: String, artist: String, title: String) {
        return (currentSongId, currentArtist, currentTitle)
    }

    var songId: String {
        return currentSongId
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
        let task = URLSession.shared.dataTask(with: RP_API_URL) {
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
                    let songId = currentSong["song_id"] as? String ?? ""
                    let coverArtUrl = currentSong["cover"] as? String ?? ""

                    // Convert milliseconds to seconds
                    let playTime = playTimeMillis / 1000
                    let duration = (Double(durationMillis) ?? 0) / 1000

                    // Calculate when the next song should start
                    let nextSongTime = playTime + duration

                    // Calculate how many seconds from now until the next song
                    var onRadioBreak = false
                    let currentTime = Date().timeIntervalSince1970
                    var timeUntilNextSong = max(nextSongTime - currentTime + 5, 5)
                    print("∆: \(nextSongTime - currentTime)")
                    if (nextSongTime - currentTime < 0) {
                        // We're probably in a commercial break. Set the title and refresh a little later.
                        artist = "Radio Paradise"
                        title = "Break"
                        onRadioBreak = true
                        timeUntilNextSong = 10
                    }

                    if (onRadioBreak) {
                        DispatchQueue.main.async {
                            self.currentCoverArt = NSImage(named: "AppIcon")
                            self.updateSystemNowPlaying()
                            StatusMenuController.shared.updateAlbumArt()
                        }
                    } else if (coverArtUrl.isEmpty) {
                        self.currentCoverArt = nil
                        // Update the menu album art on main thread
                        DispatchQueue.main.async {
                            StatusMenuController.shared.updateAlbumArt()
                        }
                    } else {
                        let url = URL(string: "https://img.radioparadise.com/\(coverArtUrl)")!
                        let dataTask = URLSession.shared.dataTask(with: url) { [weak self] (data, _, _) in
                            if let data = data, let image = NSImage(data: data) {
                                self?.currentCoverArt = image
                                self?.updateSystemNowPlaying()

                                // Update the menu album art on main thread
                                DispatchQueue.main.async {
                                    StatusMenuController.shared.updateAlbumArt()
                                }
                            }
                        }
                        dataTask.resume()
                    }

                    DispatchQueue.main.async {
                        // Update stored song info
                        self.currentArtist = artist
                        self.currentTitle = title
                        self.currentSongId = songId

                        // Notify status menu controller
                        let fullSongInfo = "\(title) - \(artist)"
                        StatusMenuController.shared.updateNowPlaying(
                            songInfo: fullSongInfo,
                            isSong: !onRadioBreak,
                            isPaused: !self.isPlaying
                        )

                        // Update system Now Playing
                        if self.isPlaying {
                            self.updateSystemNowPlaying()
                        }

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
        nowPlayingInfo[MPMediaItemPropertyTitle] = self.currentTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = self.currentArtist
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: self.player?.rate ?? 0.0)
        if let coverArt = self.currentCoverArt {
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

    // MARK: - AudioPlayerDelegate

    func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        switch (newState) {
        case .ready:
            updateNowPlaying()
            fallthrough
        case .playing:
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.updateSystemNowPlaying()
            }
            fallthrough
        case .bufferring, .running:
            DispatchQueue.main.async {
                StatusMenuController.shared.updatePlayPauseButton(isPlaying: true)
            }
            break
        case .error:
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.setupPlayer()
                self.play()
            }
            fallthrough
        case .paused, .stopped:
            DispatchQueue.main.async {
                StatusMenuController.shared.updatePlayPauseButton(isPlaying: false)
                self.updateSystemNowPlaying()
            }
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
