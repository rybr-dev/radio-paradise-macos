import Foundation

// URL format constants
let bundleIdentifier = Bundle.main.bundleIdentifier ?? "dev.rybr.radioparadise"
let RP_NOW_PLAYING_URL_FORMAT = "https://api.radioparadise.com/api/now_playing?chan=%ld&player_id=\(bundleIdentifier)"
let RP_NOW_PLAYING_DETAILS_URL_FORMAT = "https://api.radioparadise.com/api/nowplaying_list_v2022?chan=%ld&list_num=1&player_id=\(bundleIdentifier)"
let RP_STREAM_URL_FORMAT = "http://stream.radioparadise.com/%@"

// Channel structure
struct Channel {
    var title: String
    var streamID: String
    var channelID: Int

    var streamURL: URL {
        return URL(string: String(format: RP_STREAM_URL_FORMAT, streamID))!
    }

    var nowPlayingAPIURL: URL {
        return URL(string: String(format: RP_NOW_PLAYING_URL_FORMAT, channelID))!
    }

    var nowPlayingDetailsAPIURL: URL {
        return URL(string: String(format: RP_NOW_PLAYING_DETAILS_URL_FORMAT, channelID))!
    }
}

// Stores the selected channel's stable Radio Paradise channel ID, so the menu
// order can change without disturbing a saved selection. Older builds stored
// the array index instead; that value is migrated once (see below).
let SELECTED_CHANNEL_ID_KEY = "SelectedChannelID"
private let LEGACY_SELECTED_CHANNEL_INDEX_KEY = "SelectedChannelIndex"

// Legacy stored index -> channel ID, using the v1.0.x release order (the only
// menu ordering that shipped with index-based persistence).
private let LEGACY_INDEX_TO_CHANNEL_ID: [Int] = [
    0,    // 0: Main Mix
    1,    // 1: Mellow Mix
    2,    // 2: Rock Mix   (now RockIt!)
    3,    // 3: Global Mix (now The Globe)
    5,    // 4: Beyond...
    42,   // 5: Serenity
    2050, // 6: Radio 2050
]

//
// The order in this array determines the order they will appear in the menu
//
let CHANNEL_DATA: [Channel] = [
    // Main Mix
    Channel(
        title: "Main Mix",
        streamID: "aac-320",
        channelID: 0
    ),
    // Mellow Mix
    Channel(
        title: "Mellow Mix",
        streamID: "mellow-320",
        channelID: 1
    ),
    // RockIt!
    Channel(
        title: "RockIt!",
        streamID: "rock-320",
        channelID: 2
    ),
    // The Globe
    Channel(
        title: "The Globe",
        streamID: "global-320",
        channelID: 3
    ),
    // Beyond...
    Channel(
        title: "Beyond...",
        streamID: "beyond-320",
        channelID: 5
    ),
    // Serenity
    Channel(
        title: "Serenity",
        streamID: "serenity",
        channelID: 42
    ),
    // KFAT
    Channel(
        title: "KFAT",
        streamID: "kfat-320",
        channelID: 945
    ),
    // Radio 2050
    Channel(
        title: "Radio 2050",
        streamID: "radio2050-320",
        channelID: 2050
    )
]

//
// Current channel management
//

private var defaultChannel: Channel { CHANNEL_DATA[0] }

func channel(forID channelID: Int) -> Channel? {
    return CHANNEL_DATA.first { $0.channelID == channelID }
}

// Resolves the stored selection to a channel ID, migrating a legacy index-based
// value the first time it is seen. Returns nil when nothing has been stored.
private func migratedSelectedChannelID() -> Int? {
    let defaults = UserDefaults.standard

    if defaults.object(forKey: SELECTED_CHANNEL_ID_KEY) != nil {
        return defaults.integer(forKey: SELECTED_CHANNEL_ID_KEY)
    }

    // Migrate a legacy index-based selection, if present.
    if defaults.object(forKey: LEGACY_SELECTED_CHANNEL_INDEX_KEY) != nil {
        let legacyIndex = defaults.integer(forKey: LEGACY_SELECTED_CHANNEL_INDEX_KEY)
        let migratedID = LEGACY_INDEX_TO_CHANNEL_ID.indices.contains(legacyIndex)
            ? LEGACY_INDEX_TO_CHANNEL_ID[legacyIndex]
            : defaultChannel.channelID
        defaults.set(migratedID, forKey: SELECTED_CHANNEL_ID_KEY)
        defaults.removeObject(forKey: LEGACY_SELECTED_CHANNEL_INDEX_KEY)
        return migratedID
    }

    return nil
}

// Currently selected channel ID, defaulting to Main Mix.
func getCurrentChannelID() -> Int {
    if let storedID = migratedSelectedChannelID(), channel(forID: storedID) != nil {
        return storedID
    }
    return defaultChannel.channelID
}

func getCurrentChannel() -> Channel {
    return channel(forID: getCurrentChannelID()) ?? defaultChannel
}

func setCurrentChannel(channelID: Int) {
    guard channel(forID: channelID) != nil else { return }
    UserDefaults.standard.set(channelID, forKey: SELECTED_CHANNEL_ID_KEY)
}

// Current API URLs and Stream URL based on selected channel
var currentChannelNowPlayingURL: URL {
    return getCurrentChannel().nowPlayingAPIURL
}

var currentChannelNowPlayingDetailsURL: URL {
    return getCurrentChannel().nowPlayingDetailsAPIURL
}

var currentStreamURL: URL {
    return getCurrentChannel().streamURL
}

