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

// UserDefaults key for storing selected channel index
let SELECTED_CHANNEL_KEY = "SelectedChannelIndex"

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
    // Rock Mix
    Channel(
        title: "Rock Mix",
        streamID: "rock-320",
        channelID: 2
    ),
    // Global Mix
    Channel(
        title: "Global Mix",
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

// Get the currently selected channel (defaults to Main Mix at index 0)
func getCurrentChannel() -> Channel {
    let selectedIndex = UserDefaults.standard.integer(forKey: SELECTED_CHANNEL_KEY)
    if selectedIndex >= 0 && selectedIndex < CHANNEL_DATA.count {
        return CHANNEL_DATA[selectedIndex]
    }
    return CHANNEL_DATA[0] // Default to Main Mix
}

// Set the currently selected channel
func setCurrentChannel(index: Int) {
    if index >= 0 && index < CHANNEL_DATA.count {
        UserDefaults.standard.set(index, forKey: SELECTED_CHANNEL_KEY)
    }
}

// Get the index of the currently selected channel
func getCurrentChannelIndex() -> Int {
    let selectedIndex = UserDefaults.standard.integer(forKey: SELECTED_CHANNEL_KEY)
    if selectedIndex >= 0 && selectedIndex < CHANNEL_DATA.count {
        return selectedIndex
    }
    return 0 // Default to Main Mix
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

