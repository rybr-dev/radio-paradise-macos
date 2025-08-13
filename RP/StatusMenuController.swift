import Cocoa

private let MENU_ITEM_MAX_LENGTH: Int = 28
private let PLAY_TITLE = "Play"
private let PAUSE_TITLE = "Pause"

// Custom NSImageView that can handle mouse tracking
class HoverableImageView: NSImageView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func viewDidMoveToWindow() {
        window?.becomeKey()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        // Add new tracking area
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

class StatusMenuController: NSObject {
    static let shared = StatusMenuController()

    private let statusItem: NSStatusItem
    private var nowPlayingView: NSView?
    private var albumArtImageView: HoverableImageView?
    private var nowPlayingLabel: NSTextField?
    private var songInfoLabel: NSTextField?
    private var playPauseButton: NSButton?
    private var addToPlaylistMenuItem: NSMenuItem?
    private var shareSongMenuItem: NSMenuItem?
    private var viewOnRadioParadiseMenuItem: NSMenuItem?
    private var nowPlayingMenuItem: NSMenuItem?

    private var fullSongInfo: String = ""

    // Album art hover overlay properties
    private var hoverTimer: Timer?
    private var overlayWindow: OverlayWindow?

    // About window
    private var aboutWindow: AboutWindow?


    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Radio Paradise"

        super.init()
    }

    deinit {
        // Clean up timers and overlays
        hoverTimer?.invalidate()
        overlayWindow?.close()
        aboutWindow = nil
    }
    
    public func setupMenu() {
        let menu = NSMenu()

        // Combined album art and now playing item
        let nowPlayingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        nowPlayingItem.target = self
        createNowPlayingView(for: nowPlayingItem)
        menu.addItem(nowPlayingItem)
        
        menu.addItem(NSMenuItem.separator())

        // Channel selection submenu
        let channelMenuItem = NSMenuItem(title: "Channel", action: nil, keyEquivalent: "")
        let channelSubmenu = NSMenu()

        for (index, channel) in CHANNEL_DATA.enumerated() {
            let channelItem = NSMenuItem(title: channel.title, action: #selector(selectChannel(_:)), keyEquivalent: "")
            channelItem.target = self
            channelItem.tag = index
            channelItem.state = (index == getCurrentChannelIndex()) ? .on : .off
            channelSubmenu.addItem(channelItem)
        }

        channelMenuItem.submenu = channelSubmenu
        menu.addItem(channelMenuItem)

        // Separator
        menu.addItem(NSMenuItem.separator())

        // View on radioparadise.com item
        let viewOnRadioParadiseItem = NSMenuItem(title: "View on Radio Paradise", action: #selector(viewOnRadioParadise), keyEquivalent: "")
        // Initially disable the View on Radio Paradise item until we have a song
        viewOnRadioParadiseItem.isEnabled = false
        viewOnRadioParadiseItem.target = self
        menu.addItem(viewOnRadioParadiseItem)

        // Add to Apple Music playlist item
        let addToPlaylistItem = NSMenuItem(title: "Add to Apple Music Playlist", action: #selector(addToPlaylist), keyEquivalent: "")
        // Initially disable the Add to Playlist item until we have a song
        addToPlaylistItem.isEnabled = false
        addToPlaylistItem.target = self
        menu.addItem(addToPlaylistItem)

        // Share song item
        let shareSongItem = NSMenuItem(title: "Share...", action: #selector(shareSong), keyEquivalent: "")
        // Initially disable the Share Song item until we have a song
        shareSongItem.isEnabled = false
        shareSongItem.target = self
        menu.addItem(shareSongItem)

        menu.addItem(NSMenuItem.separator())

        // About item
        let aboutItem = NSMenuItem(title: "About Radio Paradise", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        // Store references to menu items
        self.nowPlayingMenuItem = nowPlayingItem
        self.addToPlaylistMenuItem = addToPlaylistItem
        self.shareSongMenuItem = shareSongItem
        self.viewOnRadioParadiseMenuItem = viewOnRadioParadiseItem
    }

    @objc private func togglePlayPause() {
        RadioPlayer.shared.togglePlayPause()
    }
    
    @objc private func addToPlaylist() {
        let songInfo = RadioPlayer.shared.currentSongInfo
        guard !songInfo.title.isEmpty && !songInfo.artist.isEmpty else {
            NotificationService.shared.showNotification(
                title: "Cannot Add Song",
                body: "No song information available"
            )
            return
        }

        Task {
            await MusicService.shared.addSongToPlaylist(title: songInfo.title, artist: songInfo.artist)
        }
    }

    @objc private func shareSong() {
        let songInfo = RadioPlayer.shared.currentSongInfo
        guard !songInfo.title.isEmpty && !songInfo.artist.isEmpty else {
            NotificationService.shared.showNotification(
                title: "Cannot Share Song",
                body: "No song information available"
            )
            return
        }

        Task {
//            let appleMusicSongUrl = MusicService.shared.getSongAppleMusicURL(title: songInfo.title, artist: songInfo.artist)
            let radioParadiseUrlString = "https://radioparadise.com/music/song/\(songInfo.songId)"
            if let url = URL(string: radioParadiseUrlString) {
                showShareSheet(for: url)
            }
        }
    }

    @objc private func viewOnRadioParadise() {
        let songId = RadioPlayer.shared.songId
        guard !songId.isEmpty else {
            NotificationService.shared.showNotification(
                title: "Cannot View Song",
                body: "No song information available"
            )
            return
        }

        let urlString = "https://radioparadise.com/music/song/\(songId)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func showShareSheet(for url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let items = ["I heard this on Radio Paradise:", url]
            // In case we want to specify certain services
            //let sharingService = NSSharingService(named: .composeMessage)
            //if let service = sharingService {
            //    service.perform(withItems: items)
            //}
            let picker = NSSharingServicePicker(items: items)

            // We need to show the picker relative to a view, but since we're in a menu bar app,
            // we'll use the status item's button as the reference
            if let button = self.statusItem.button {
                picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            } else {
                // Last resort: copy to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.absoluteString, forType: .string)

                NotificationService.shared.showNotification(
                    title: "Link Copied",
                    body: "Link copied to clipboard"
                )
            }
//            }
        }
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            aboutWindow = AboutWindow()
        }
        aboutWindow?.show()
    }

    @objc private func selectChannel(_ sender: NSMenuItem) {
        let selectedIndex = sender.tag

        // Update the selected channel
        setCurrentChannel(index: selectedIndex)

        // Update the menu checkmarks
        updateChannelMenuStates()

        // Switch to the new channel
        RadioPlayer.shared.switchChannel()

        // Show notification
        let channel = CHANNEL_DATA[selectedIndex]
        NotificationService.shared.showNotification(
            title: "Channel Changed",
            body: "Now playing \(channel.title)"
        )
    }

    private func updateChannelMenuStates() {
        guard let menu = statusItem.menu else { return }

        // Find the channel submenu
        for item in menu.items {
            if item.title == "Channel", let submenu = item.submenu {
                let currentIndex = getCurrentChannelIndex()
                for (index, subItem) in submenu.items.enumerated() {
                    subItem.state = (index == currentIndex) ? .on : .off
                }
                break
            }
        }
    }

    func updatePlayPauseButton(isPlaying: Bool) {
        // Update the button in the now playing view
        if let button = playPauseButton {
            updatePlayPauseButtonImage(button, isPlaying: isPlaying)
        }
    }

    private func updatePlayPauseButtonImage(_ button: NSButton, isPlaying: Bool) {
        let imageName = isPlaying ? "pause.fill" : "play.fill"
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil) {
            var config = NSImage.SymbolConfiguration(textStyle: .body,
                                                                 scale: .large)
                config = config.applying(.init(paletteColors: [.black]))
            button.image = image.withSymbolConfiguration(config)
        } else {
            // Fallback to text if system symbols aren't available
            button.title = isPlaying ? "⏸" : "▶"
        }
    }
    
    func updateNowPlaying(songInfo: String, isSong: Bool, isPaused: Bool) {
        fullSongInfo = songInfo

        // Update the custom view with song information
        let displayText = isPaused ? "\(fullSongInfo) (Paused)" : fullSongInfo
        songInfoLabel?.stringValue = displayText

        // Initially disable Apple Music features until preloading completes
        addToPlaylistMenuItem?.isEnabled = false
        shareSongMenuItem?.isEnabled = false
        viewOnRadioParadiseMenuItem?.isEnabled = false

        statusItem.button?.title = truncatedString(fullSongInfo)

        // Update album art
        updateAlbumArt()

        // Trigger preloading if this is a song
        if isSong {
            let songInfo = RadioPlayer.shared.currentSongInfo
            MusicService.shared.preloadSong(title: songInfo.title, artist: songInfo.artist)
        } else {
            updateSongPreloadStatus(isReady: false)
        }
    }

    func updateSongPreloadStatus(isReady: Bool) {
        addToPlaylistMenuItem?.isEnabled = isReady
        shareSongMenuItem?.isEnabled = isReady
        viewOnRadioParadiseMenuItem?.isEnabled = isReady
    }

    func updateAlbumArt() {
        let albumArt = RadioPlayer.shared.currentAlbumArt
        if let albumArt = albumArt {
            // Use the actual album art
            albumArtImageView?.image = albumArt
        } else {
            // Use the blank CD image as fallback
            if let blankCDImage = NSImage(named: "BlankCD") {
                albumArtImageView?.image = blankCDImage
            }
        }
    }
    
    private func truncatedString(_ string: String) -> String {
        return string.count > MENU_ITEM_MAX_LENGTH ?
        String(string.prefix(MENU_ITEM_MAX_LENGTH - 3)) + "..." :
        string;
    }

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        resizedImage.unlockFocus()
        return resizedImage
    }

    private func getMenuWidth() -> CGFloat {
        // Get the actual menu width by measuring the longest menu item
        guard let menu = statusItem.menu else { return 280.0 }

        var maxWidth: CGFloat = 280.0 // Default minimum width

        for item in menu.items {
            if let title = item.title.isEmpty ? item.attributedTitle?.string : item.title {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.menuFont(ofSize: 0)
                ]
                let size = title.size(withAttributes: attributes)
                maxWidth = max(maxWidth, size.width + 60) // Add padding for margins and icons
            }
        }

        // Cap the maximum width to something reasonable
        return min(maxWidth, 350.0)
    }

    private func resizeImageToSquare(_ image: NSImage, width: CGFloat) -> NSImage {
        let size = NSSize(width: width, height: width)
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()

        // Fill background with a subtle color
        NSColor.controlBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Draw the image to fill the square, maintaining aspect ratio and centering
        let imageSize = image.size
        let aspectRatio = imageSize.width / imageSize.height

        var drawRect: NSRect
        if aspectRatio > 1 {
            // Image is wider than tall - fit to height, center horizontally
            let drawHeight = width
            let drawWidth = drawHeight * aspectRatio
            let xOffset = (width - drawWidth) / 2
            drawRect = NSRect(x: xOffset, y: 0, width: drawWidth, height: drawHeight)
        } else {
            // Image is taller than wide or square - fit to width, center vertically
            let drawWidth = width
            let drawHeight = drawWidth / aspectRatio
            let yOffset = (width - drawHeight) / 2
            drawRect = NSRect(x: 0, y: yOffset, width: drawWidth, height: drawHeight)
        }

        image.draw(in: drawRect)
        resizedImage.unlockFocus()
        return resizedImage
    }

    private func setupWrappingMenuItem(_ menuItem: NSMenuItem?) {
        guard let menuItem = menuItem else { return }

        // Create an attributed string that allows wrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0), // Use system menu font
            .foregroundColor: NSColor.labelColor
        ]

        let attributedTitle = NSAttributedString(string: menuItem.title, attributes: attributes)
        menuItem.attributedTitle = attributedTitle
    }

    private func updateWrappingMenuItemText(_ menuItem: NSMenuItem?, text: String) {
        guard let menuItem = menuItem else { return }

        let menuWidth = getMenuWidth()
        let maxWidth = menuWidth - 40 // Leave some padding

        // Create attributed string with wrapping
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.maximumLineHeight = 18

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        let attributedTitle = NSAttributedString(string: text, attributes: attributes)
        menuItem.attributedTitle = attributedTitle

        // Calculate the height needed for the text
        let textRect = attributedTitle.boundingRect(
            with: NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        // If text is too long, we might need to create a custom view
        if textRect.height > 20 { // Standard menu item height
            createCustomMenuItemView(menuItem, text: text, maxWidth: maxWidth)
        }
    }

    private func createCustomMenuItemView(_ menuItem: NSMenuItem, text: String, maxWidth: CGFloat) {
        let textField = NSTextField()
        textField.stringValue = text
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.font = NSFont.menuFont(ofSize: 0)
        textField.textColor = NSColor.labelColor
        textField.maximumNumberOfLines = 3 // Limit to 3 lines
        textField.lineBreakMode = .byWordWrapping
        textField.preferredMaxLayoutWidth = maxWidth

        // Size the text field to fit the content
        textField.sizeToFit()
        let size = textField.fittingSize
        textField.frame = NSRect(x: 0, y: 0, width: min(size.width, maxWidth), height: min(size.height, 60))

        menuItem.view = textField
    }

    private func createNowPlayingView(for menuItem: NSMenuItem) {
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Set a more compact frame for the container
        let containerWidth: CGFloat = 320
        let containerHeight: CGFloat = 80
        containerView.frame = NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight)

        // Album art image view with hover capability
        let imageView = HoverableImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(x: 16, y: 8, width: 64, height: 64)

        // Setup hover callbacks
        imageView.onMouseEntered = { [weak self] in
            self?.albumArtMouseEntered()
        }
        imageView.onMouseExited = { [weak self] in
            self?.albumArtMouseExited()
        }

        // Set initial blank CD image
        if let blankCDImage = NSImage(named: "BlankCD") {
            imageView.image = blankCDImage
        } else {
            // Fallback: create a simple placeholder
            let placeholderImage = NSImage(size: NSSize(width: 64, height: 64))
            placeholderImage.lockFocus()
            NSColor.lightGray.setFill()
            NSRect(origin: .zero, size: NSSize(width: 64, height: 64)).fill()
            placeholderImage.unlockFocus()
            imageView.image = placeholderImage
        }

        // "Now Playing" label (bold, small text)
        let nowPlayingLabel = NSTextField()
        nowPlayingLabel.stringValue = "Now Playing"
        nowPlayingLabel.isEditable = false
        nowPlayingLabel.isSelectable = false
        nowPlayingLabel.isBezeled = false
        nowPlayingLabel.drawsBackground = false
        nowPlayingLabel.font = NSFont.boldSystemFont(ofSize: 11)
        nowPlayingLabel.textColor = NSColor.labelColor
        nowPlayingLabel.frame = NSRect(x: 92, y: 50, width: 220, height: 16)

        // Song info label (normal text) - reduced width to make room for button
        let songInfoLabel = NSTextField()
        songInfoLabel.stringValue = "Loading..."
        songInfoLabel.isEditable = false
        songInfoLabel.isSelectable = false
        songInfoLabel.isBezeled = false
        songInfoLabel.drawsBackground = false
        songInfoLabel.font = NSFont.systemFont(ofSize: 13)
        songInfoLabel.textColor = NSColor.labelColor
        songInfoLabel.lineBreakMode = .byWordWrapping
        songInfoLabel.maximumNumberOfLines = 0  // Allow unlimited lines
        songInfoLabel.frame = NSRect(x: 92, y: 6, width: 182, height: 40)

        // Play/pause button (32 x 32, positioned on the right side)
        let playPauseButton = NSButton()
        playPauseButton.frame = NSRect(x: 278, y: 21, width: 32, height: 32)
        playPauseButton.isBordered = false
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)

        // Set initial button image based on current playing state
        updatePlayPauseButtonImage(playPauseButton, isPlaying: RadioPlayer.shared.isPlaying)

        // Add subviews
        containerView.addSubview(imageView)
        containerView.addSubview(nowPlayingLabel)
        containerView.addSubview(songInfoLabel)
        containerView.addSubview(playPauseButton)

        // Store references
        self.nowPlayingView = containerView
        self.albumArtImageView = imageView
        self.nowPlayingLabel = nowPlayingLabel
        self.songInfoLabel = songInfoLabel
        self.playPauseButton = playPauseButton

        // Set the view on the menu item
        menuItem.view = containerView
    }

    // MARK: - Album Art Hover Functionality

    private func albumArtMouseEntered() {
        // Cancel any existing timer
        hoverTimer?.invalidate()

        // Start a timer to show the overlay after 1 second
        let timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.showAlbumArtOverlay()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.hoverTimer = timer
    }

    private func albumArtMouseExited() {
        // Cancel the hover timer if mouse exits before 1 second
        hoverTimer?.invalidate()
        hoverTimer = nil

        // Hide the overlay if it's showing
        hideAlbumArtOverlay()
    }

    private func showAlbumArtOverlay() {
        guard let albumArtImageView = albumArtImageView,
              let image = albumArtImageView.image else { return }

        // Don't show overlay if it's already showing
        guard overlayWindow == nil else { return }

        // Get the current mouse location
        let mouseLocation = NSEvent.mouseLocation

        // Calculate overlay size (larger version of the album art)
        let overlaySize: CGFloat = 300
        // Position to bottom-left of mouse to avoid covering menu bar
        let overlayRect = NSRect(
            x: mouseLocation.x + 2, // 20px offset to the left
            y: mouseLocation.y - overlaySize - 2, // 20px offset below
            width: overlaySize,
            height: overlaySize
        )

        // Create the overlay window
        overlayWindow = OverlayWindow.create(withRect: overlayRect)

        guard let window = overlayWindow else { return }

        // Create the content view with black background
        let contentView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: overlaySize, height: overlaySize)))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        contentView.layer?.cornerRadius = 8

        // Create the image view for the overlay
        let overlayImageView = NSImageView(frame: contentView.bounds)
        overlayImageView.imageScaling = .scaleProportionallyUpOrDown
        overlayImageView.image = image

        contentView.addSubview(overlayImageView)
        window.contentView = contentView

        // Show the window with fade-in animation
        window.alphaValue = 0.0
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window.animator().alphaValue = 1.0
        }
    }

    private func hideAlbumArtOverlay() {
        guard let window = overlayWindow else { return }

        // Clear the reference immediately to prevent double-cleanup
        overlayWindow = nil

        // Fade out and close the overlay window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak window] in
            window?.close()
        })
    }
}
