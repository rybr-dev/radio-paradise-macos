import Foundation
import MusadoraKit
import Cocoa
import LRUCache

let APPLE_MUSIC_PLAYLIST_NAME = "Radio Paradise Favorites"

class MusicService {
    static let shared = MusicService()

    private var songCache = LRUCache<String, Song>(countLimit: 100)
    
    private var currentPreloadTask: Task<Void, Never>?

    func authorization() -> MusicAuthorization.Status {
        return MusicAuthorization.currentStatus
    }
    
    func hasAuthorization() -> Bool {
        return self.authorization() == .authorized;
    }
    
    func requestAuthorization() async -> Bool {
        let authStatus = await MusicAuthorization.request()
        switch authStatus {
        case .authorized:
            print("Music authorization granted")
            return true
        default:
            print("Music authorization not granted: \(authStatus)")
            return false
        }
    }
    
    // MARK: - Private Helper Methods

    private func cacheKey(title: String, artist: String) -> String {
        return "\(artist.lowercased())|\(title.lowercased())"
    }

    private func searchForSong(title: String, artist: String) async throws -> Song? {
        let key = cacheKey(title: title, artist: artist)

        // Check if this is the currently cached song
        if let cachedSong = songCache.value(forKey: key) {
            print("Using cached current song: \(cachedSong.title) - \(cachedSong.artistName)")
            return cachedSong
        }

        // Search Apple Music
        let searchTerm = "\(title) \(artist)"
        let searchResponse = try await MCatalog.search(for: searchTerm, types: [.songs], limit: 10)

        if let song = searchResponse.songs.first {
            // Cache as the current song
            songCache.setValue(song, forKey: key)
            print("Cached current song: \(song.title) - \(song.artistName)")
        }

        return searchResponse.songs.first
    }

    func addSongToPlaylist(title: String, artist: String) async {
        func showDeniedNotification() {
            NotificationService.shared.showNotification(
                title: "Not Authorized",
                body: "Go to the Settings app to authorize Radio Paradise to access Apple Music."
            )
            return
        }
        if self.authorization() == .denied {
            showDeniedNotification()
            return
        }
        // Function to search for the song and add it to the RP playlist
        func addSong() async throws {
            // First request permission to access Apple Music. It will:
            // - already be approved
            // - be approved in this request
            // - be denied in the request
            let authorization = await MusicAuthorization.request()
            if authorization == .denied {
                showDeniedNotification()
                return
            }

            // Now we have access to Apple Music, search for the song
            guard let firstSong = try await searchForSong(title: title, artist: artist) else {
                NotificationService.shared.showNotification(
                    title: "Song Not Found",
                    body: "Could not find \"\(title)\" by \(artist) in Apple Music"
                )
                return
            }

            // Find or create the playlist
            let playlistId = try await findOrCreatePlaylistId(named: APPLE_MUSIC_PLAYLIST_NAME)

            // Add the song to the playlist
            let success = try await MLibrary.add(songIDs: [firstSong.id], to: MusicItemID(playlistId))

            if success {
                print("Added song: \(firstSong.title) - \(firstSong.artistName) - \(firstSong.id)")
                NotificationService.shared.showNotification(
                    title: "Song Added",
                    body: "Added \"\(title)\" to \"\(APPLE_MUSIC_PLAYLIST_NAME)\" playlist"
                )
            } else {
                print("Couldn't add song to playlist!")
                NotificationService.shared.showNotification(
                    title: "Error",
                    body: "Couldn't add song to the playlist. Please try again later."
                )
            }
        }

        // Now try to add the song.
        do {
            try await addSong();
        } catch {
            print("Error adding song to playlist: \(error)")
            NotificationService.shared.showNotification(
                title: "Error",
                body: "Could not add song to playlist: \(error.localizedDescription)"
            )
        }
    }
    
    // TODO
    // There is some inconsistent behavior with playlists in MusicKit. In particular:
    // - if a user deletes our playlist, MusicKit [inconsistently] still lets you add songs to it. By all
    //   indications, the song gets added successfully -- but the user won't be able to access it!
    // - IDs come back inconsistently. It feels very sus that we have to get the ID of the
    //   playlist from the playParams, but it's the only field it comes back consistently in.
    // Ideally, this method would cache the playlist ID and avoid running the search every time. But this
    // is the most consistent approach for now.
    private func findOrCreatePlaylistId(named name: String) async throws -> String {
        var playlistId: String?
            
        do {
            // Search for existing playlist
            let playlists = try await MLibrary.playlists(limit: 0)
            for playlist in playlists {
                if playlist.attributes.name == APPLE_MUSIC_PLAYLIST_NAME {
                    playlistId = playlist.attributes.playParams.id.rawValue
                    break
                }
            }
        } catch {
            print("Error searching for playlist:", error)
        }
            
        if (playlistId == nil) {
            // If we didn't find our playlist, we'll create one
            do {
                let playlist = try await MLibrary.createPlaylist(with: name)
                playlistId = playlist.id.rawValue
                print("Created playlist id: \(playlistId!)")
            } catch {
                print("Error creating playlist:", error)
            }
        }
            
        if (playlistId == nil) {
            throw NSError(
                domain: Bundle.main.bundleIdentifier ?? "app",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey : "Failed to find or create playlist"]
            )
        }
            
        return playlistId!
    }

    func getSongAppleMusicURL(title: String, artist: String) async -> URL? {
        do {
            guard let song = try await searchForSong(title: title, artist: artist) else {
                NotificationService.shared.showNotification(
                    title: "Song Not Found",
                    body: "Could not find \"\(title)\" by \(artist) in Apple Music"
                )
                return nil
            }

            print("Found song for sharing: \(song.title) - \(song.artistName)")

            // Get the Apple Music URL for the song
            if let url = song.url {
                return url
            } else {
                NotificationService.shared.showNotification(
                    title: "No Song Link",
                    body: "Could not get Apple Music link for \"\(title)\" by \(artist)"
                )
                return nil
            }
        } catch {
            print("Error searching for song: \(error)")
            NotificationService.shared.showNotification(
                title: "Error",
                body: "Could not search for song: \(error.localizedDescription)"
            )
            return nil
        }
    }

    // MARK: - Preloading

    func preloadCurrentSong() {
        // Cancel any existing preload task
        currentPreloadTask?.cancel()

        let currentSong = RadioPlayer.shared.currentSongInfo()
        if (currentSong.songId.isEmpty) {
            return;
        }

        let artist = currentSong.artist
        let title = currentSong.title

        if !self.hasAuthorization() {
            // No need to preload
            print("Not authorized to Apple Music yet")
            DispatchQueue.main.async {
                // We set this true because we want the user to be able to select it and start authorization
                StatusMenuController.shared.updateSongPreloadStatus(isReady: true)
            }
            return;
        }
        
        let key = cacheKey(title: title, artist: artist)

        // Skip if this song is already cached
        if songCache.value(forKey: key) != nil {
            print("Song already cached: \(currentSong.title) - \(currentSong.artist)")
            // Notify that the song is ready
            DispatchQueue.main.async {
                StatusMenuController.shared.updateSongPreloadStatus(isReady: true)
            }
            return
        }

        // Start preloading task
        currentPreloadTask = Task {
            do {
                // Check authorization first
                guard !Task.isCancelled else { return }

                if self.hasAuthorization() {
                    // Preload the song (this will cache it)
                    let song = try await searchForSong(title: title, artist: artist)

                    guard !Task.isCancelled else { return }

                    // Notify based on whether we found and cached the song
                    let isReady = song != nil
                    DispatchQueue.main.async {
                        StatusMenuController.shared.updateSongPreloadStatus(isReady: isReady)
                    }

                    if isReady {
                        print("Preloaded song: \(title) - \(artist)")
                    } else {
                        print("Song not found in Apple Music: \(title) - \(artist)")
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }

                print("Failed to preload song: \(error)")
                // On error, disable menu items
                DispatchQueue.main.async {
                    StatusMenuController.shared.updateSongPreloadStatus(isReady: false)
                }
            }
        }
    }
}
