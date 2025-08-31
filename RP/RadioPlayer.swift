import Foundation
import AudioStreaming
import MediaPlayer
import Cocoa
import LRUCache

struct SongInfo {
    var artist: String = ""
    var title: String = ""
    var songId: String? = nil
    var coverArtUrl: String? = nil
}

class RadioPlayer: NSObject, AudioPlayerDelegate {
    static let shared = RadioPlayer()

    private var player: AudioPlayer?
    var isPlaying: Bool {
        return [.playing, .bufferring, .running].contains(player?.state)
    }
    
    private var updateTimer: Timer?
    private var pauseTimer: Timer?
    
    private(set) var currentSongInfo: SongInfo? = nil
    private(set) var isSwitchingChannels = false
    
    let albumArtCache = LRUCache<String, NSImage>(countLimit: 3)
    var visibleSongInfo: (SongInfo, NSImage) {
        get {
            let defaultImage = NSImage(named: "AppIcon")!
            if let songInfo = currentSongInfo {
                var coverArtImage = defaultImage
                if let coverArtUrl = songInfo.coverArtUrl, let cachedCoverArtImage = self.albumArtCache.value(forKey: coverArtUrl) {
                    coverArtImage = cachedCoverArtImage
                }
                return (songInfo, coverArtImage)
            }
            let currentChannelIndex = getCurrentChannelIndex()
            let channelName = CHANNEL_DATA[currentChannelIndex].title
            return (SongInfo(artist: "Radio Paradise", title: channelName), defaultImage)
        }
    }

    //
    // MARK: - Initialization
    //
    
    private override init() {
        super.init()
        setupPlayer()
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        // Remove wake notification observer
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
    
    //
    // MARK: - System wake handler
    //

    @objc private func systemDidWake() {
        print("System woke from sleep - refreshing song data")

        // If we're currently playing, refresh the song data immediately
        if isPlaying {
            updateNowPlaying()
        }
    }
    
    //
    // MARK: - Player play/pause/stop
    //
    
    func play() {
        // Cancel pause timer
        stopPauseTimer()
        
        player?.play(url: currentStreamURL)
        updateNowPlaying()
    }
    
    func pause() {
        player?.pause()
        startPauseTimer()
    }
    
    func stop() {
        stopUpdateTimer()
        stopPauseTimer()
        player?.stop()
    }
    
    func togglePlayPause() {
        if ![.playing, .bufferring].contains(player?.state) {
            self.play()
        } else {
            self.pause()
        }
    }
    
    private func startPauseTimer() {
        // Don't start pause timer if we're switching channels
        guard !isSwitchingChannels else { return }
        
        DispatchQueue.main.async {
            // Stop previous timers
            self.stopPauseTimer()
            
            // Start a 15-second timer
            self.pauseTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
                self?.handleLongPause()
            }
        }
    }
    
    private func stopPauseTimer() {
        DispatchQueue.main.async {
            self.pauseTimer?.invalidate()
            self.pauseTimer = nil
        }
    }

    private func handleLongPause() {
        guard !isPlaying else { return }
                
        // Stop the song update timer since we're no longer showing real song info
        stopUpdateTimer()
        
        // Wipe the current song
        currentSongInfo = nil
        
        // Update the UI
        updateUI()
    }
    
    //
    // MARK: - Channel switching
    //
    
    func switchChannel() {
        // Set flag to prevent pause animations during channel switch
        isSwitchingChannels = true
        
        // Stop current playback and cancel pause timer
        stopUpdateTimer()
        stopPauseTimer()
    
        player?.stop()
        
        // Always start playing after switching channels
        // Wait a moment for the stop to complete, then start with new channel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.play()
            // Clear the flag after starting to play
            self.isSwitchingChannels = false
        }
    }
    
    //
    // MARK: - Now Playing updates
    //
    // General flow:
    // updateNowPlaying()
    //    -> fetchNowPlayingInfo()
    //       -> are we playing a song?
    //          YES -> updateNowPlayingDetails()
    //                 -> fetchNowPlayingDetails()
    //    -> scheduleNextUpdate()
    //
    
    func updateNowPlaying() {
        print("Updating now playing data")
        //
        // This is an admittedly weird flow.
        //   - It first calls /api/now_playing, which gives us an accurate picture of "what's streaming right now" --
        //     it returns the *real-time* number of seconds until the next update, and *real-time* song info, which
        //     will be empty if there is a radio break or conversation happening (this is particularly relevant on
        //     Radio 2050). We update our artist, title, and album cover information from this.
        //   - If there is a song currently playing, we call /api/nowplaying_v2022, which gives us the song ID (which
        //     we need in order to generate the share link).
        //   - tl;dr if the song ID was in /api/now_playing, it'd be a perfect endpoint :)
        //
        fetchNowPlayingInfo { result in
            switch result {
            case .success(let (songInfo, nextUpdateTime)):
                self.updateCurrentSong(songInfo)
                self.scheduleNextUpdate(in: nextUpdateTime)
                if songInfo != nil {
                    // If there is song info, we'll update with the additional details.
                    // (Otherwise, we're likely on a radio break or there's other narration going on.)
                    self.updateNowPlayingDetails()
                    if #available(macOS 14.0, *) {
                        MusicService.shared.preloadCurrentSong()
                    }
                }
            case .failure:
                DispatchQueue.main.async {
                    self.scheduleNextUpdate(in: 30)
                }
            }
        }
    }

    private func fetchNowPlayingInfo(completion: @escaping (Result<(songInfo: SongInfo?, nextUpdateTime: TimeInterval), Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: currentChannelNowPlayingURL) { data, _, error in
            guard let data = data, error == nil else {
                print("Error fetching now playing info: \(error?.localizedDescription ?? "Unknown error")")
                completion(.failure(error ?? NSError(domain: "RadioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
                return
            }

            do {
                guard
                    let currentSong = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let nextUpdateTime = currentSong["time"] as? TimeInterval
                else {
                    completion(.failure(NSError(domain: "RadioPlayer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"])))
                    return
                }

                var songInfo: SongInfo? = nil
                if let artist = currentSong["artist"] as? String, !artist.isEmpty, let title = currentSong["title"] as? String, !title.isEmpty {
                    print("current: \(artist) - \(title)")
                    // In this call, "cover" is a full URL
                    let coverArtUrl = currentSong["cover"] as? String
                    songInfo = SongInfo(artist: artist, title: title, coverArtUrl: coverArtUrl)
                }
                print("∆: \(nextUpdateTime)")
                completion(.success((songInfo: songInfo, nextUpdateTime: nextUpdateTime)))

            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    private func updateNowPlayingDetails() {
        print("Updating now playing detailed data")
        fetchNowPlayingDetails { result in
            switch result {
            case .success(let (songInfo)):
                self.updateCurrentSong(songInfo)
            case .failure:
                DispatchQueue.main.async {
                    self.scheduleNextUpdate(in: 30)
                }
            }
        }
    }

    private func fetchNowPlayingDetails(completion: @escaping (Result<SongInfo, Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: currentChannelNowPlayingDetailsURL) { data, _, error in
            guard let data = data, error == nil else {
                print("Error fetching now playing details: \(error?.localizedDescription ?? "Unknown error")")
                completion(.failure(error ?? NSError(domain: "RadioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
                return
            }

            do {
                guard
                    let currentSongDetails = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let songs = currentSongDetails["song"] as? [[String: Any]],
                    let currentSong = songs.count == 1 ? songs.first : nil,
                    let songId = currentSong["song_id"] as? String,
                    let artist = currentSong["artist"] as? String,
                    let title  = currentSong["title"] as? String,
                    let cover  = currentSong["cover"] as? String
                else {
                    completion(.failure(NSError(domain: "RadioPlayer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"])))
                    return
                }

                // In this call, "cover" is a full URL
                let coverArtUrl = "https://img.radioparadise.com/\(cover)";
                let songInfo = SongInfo(artist: artist, title: title, songId: songId, coverArtUrl: coverArtUrl)
                completion(.success(songInfo))
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    private func scheduleNextUpdate(in seconds: TimeInterval) {
        // Cancel any existing timer
        stopUpdateTimer()

        // Schedule a new timer on the main queue to ensure it has an active run loop
        // We add a 7.5sec fudge factor to account for crossfade/transitions. This is a total
        // vibe check and will probably be off sometimes :)
        DispatchQueue.main.async {
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: seconds + 7.5, repeats: false) { timer in
                self.updateNowPlaying()
            }
        }

        print("Next song info update scheduled in \(Int(seconds)) seconds")
    }
    
    private func stopUpdateTimer() {
        DispatchQueue.main.async {
            self.updateTimer?.invalidate()
            self.updateTimer = nil
        }
    }
    
    
    //
    // MARK: - UI Updates
    //
    
    private func updateCurrentSong(_ songInfo: SongInfo?) {
        currentSongInfo = songInfo
        fetchCurrentCoverArt()
        updateUI()
    }

    private func updateCurrentSong(artist: String, title: String, songId: String?, coverArtUrl: String?) {
        let songInfo = SongInfo(
            artist: artist,
            title: title,
            songId: songId,
            coverArtUrl: coverArtUrl
        )
        updateCurrentSong(songInfo)
    }
    
    private func updateSystemNowPlaying() {
        let (songInfo, coverImage) = visibleSongInfo
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = songInfo.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = songInfo.artist
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: self.player?.rate ?? 0.0)
        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: coverImage.size) { (
            size: CGSize
        ) -> NSImage in
            return coverImage
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = self.isPlaying ? .playing : .paused
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
    
    //
    // MARK: Album art fetch
    //
    
    private func fetchCurrentCoverArt() {
        guard
            let urlString = currentSongInfo?.coverArtUrl,
            let url = URL(string: urlString)
        else { return }
        
        if self.albumArtCache.value(forKey: urlString) != nil {
            // We have a cached image, don't run the task
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = NSImage(data: data) else { return }
            self.albumArtCache.setValue(image, forKey: urlString)
            DispatchQueue.main.async {
                self.updateUI()
            }
        }
        task.resume()
    }

    //
    // MARK: - AudioPlayerDelegate
    //
    
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
            stopPauseTimer()
            updateUI()
            break
        case .paused:
            if !isSwitchingChannels {
                startPauseTimer()
            }
            self.updateUI()
            break
        case .stopped:
            stopPauseTimer()
            updateUI()
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
