<img width="128" height="128" alt="icon_128x128" src="https://github.com/user-attachments/assets/85f958aa-34be-408d-a122-d92ff0354588" />

# Radio Paradise for macOS

![Radio Paradise Menu Bar App](https://img.shields.io/badge/macOS-14.0+-blue) ![Swift](https://img.shields.io/badge/Swift-5.0-orange) ![License](https://img.shields.io/badge/License-GPTv3-green)

A native macOS menu bar app for streaming [Radio Paradise](https://radioparadise.com), commercial-free listener-supported Internet radio curated by real human beings.

Supported on macOS 10.14 (Mojave) and higher.

This app is not affiliated with or endorsed by Radio Paradise, and is created with love and respect by the Radio Paradise fans at [rybr.dev](https://rybr.dev). Please support Radio Paradise at [https://radioparadise.com/support](https://radioparadise.com/support).

## Download

[Download the latest release](https://github.com/rybr-dev/radio-paradise-macos/releases/download/1.0/RP-1.0.zip). Open the `.zip` file and drag the revealed **Radio Paradise** app to your Applications folder, then launch it and enjoy the music!

## Pretty picture

<img width="1000" height="622" alt="2" src="https://github.com/user-attachments/assets/8fa2556b-a199-4226-bda9-a67f56d37538" />

## Features

- **Streaming music**: Stream the 320kbps AAC stream of Radio Paradise's Main Mix
- **Menu bar interface**: An unobtrusive menu bar player with now playing info and other helpful utilities
- **Album artwork**: Shows the album art of the currently playing song. Hover to view the high-res version.
- **Apple Music integration**: Add songs to a special Apple Music playlist
- **Song sharing**: Share songs you love with friends via links to Radio Paradise
- **macOS media controls**: Supports play/pause from keyboard media keys and the Now Playing view

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later (for building)

## Contribute

Contributions to the project are welcome. Make changes on a fork and submit a PR to this repo.

### Building from Source

1. Clone this repository

2. Open in Xcode
   ```bash
   open RP.xcodeproj
   ```

3. **Configure signing:**
   - Select the "RP" target in Xcode
   - Go to "Signing & Capabilities"
   - Select your Apple Developer Team
   - Update the Bundle Identifier to use your own domain

4. **Build and run:**
   - Press `Cmd+R` or click the Run button in Xcode

## Architecture

Written fully in Swift. Core classes:

- **`RadioPlayer`**: Handles audio streaming and now playing data
- **`StatusMenuController`**: Manages the menu bar interface
- **`MusicService`**: Apple Music API integration and song/playlist management
- **`NotificationService`**: System notifications

## Dependencies
with special thanks to their owners and contributors.

- [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) - Audio streaming engine
- [MusadoraKit](https://github.com/rryam/MusadoraKit) - Apple Music API wrapper
- [LRUCache](https://github.com/nicklockwood/LRUCache) - Song data caching

## TODO
Things that would be cool to add:

- **Station selector**: Stream other stations on Radio Paradise. This means researching and managing the other song feeds as well.
- **Limited bandwidth fallback**: The 320kbps stream is buttery but in case of slow connections, it might be helpful to downshift to lower-bandwidth streams.
  
## License

This project is licensed under the GPLv3 License - see the [LICENSE](LICENSE) file for details.

## Special Thanks

This app is an ode to [Radio Paradise](https://radioparadise.com). Thank you for decades of incredible music.

## Support

Please support independent radio and the ongoing work of Radio Paradise at [https://radioparadise.com/support](https://radioparadise.com/support).

If you encounter any issues or have feature requests with this app, please [open an issue](../../issues) on GitHub. 

If you'd like to donate to the ongoing development of this app, you can [buy us a coffee](https://buymeacoffee.com/rybr.dev) or [sponsor us via GitHub](https://github.com/sponsors/rybr-dev). You're also welcome to submit contributions via PR.
