//
//  AboutWindow.swift
//  Radio Paradise
//

import Cocoa

class AboutWindow: NSObject, NSWindowDelegate {
    @IBOutlet var window: OverlayWindow!
    @IBOutlet var creditsTextView: LinkTrackingTextView!
    @IBOutlet var supportRadioParadiseButton: NSButton!

    func show() {
        // Load the XIB if not already loaded
        if window == nil {
            Bundle.main.loadNibNamed("AboutWindow", owner: self, topLevelObjects: nil)
        }

        // Don't show multiple about windows
        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Configure the window
        window.backgroundColor = NSColor.windowBackgroundColor
        window.isOpaque = true
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false

        // Center the window on screen
        window.center()

        // Configure the text view for links
        configureCreditsTextView()


        // Show the window
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Text View Configuration

    private func configureCreditsTextView() {
        // Configure text view for optimal link behavior
        creditsTextView.isEditable = false
        creditsTextView.isSelectable = false  // Disable text selection
        creditsTextView.drawsBackground = false
        creditsTextView.textContainer?.lineFragmentPadding = 0
        creditsTextView.textContainerInset = NSSize.zero

        // Enable automatic link detection (this gives you cursor changes and click handling)
        creditsTextView.isAutomaticLinkDetectionEnabled = true
        creditsTextView.checkTextInDocument(nil)

        // Remove focus ring
        creditsTextView.focusRingType = .none

        // Allow links to be clickable even when text is not selectable
        creditsTextView.isAutomaticTextReplacementEnabled = false
        creditsTextView.isAutomaticSpellingCorrectionEnabled = false
        creditsTextView.isAutomaticQuoteSubstitutionEnabled = false
        creditsTextView.isAutomaticDashSubstitutionEnabled = false

        creditsTextView.textStorage?.setAttributedString(creditsText())
    }

    private func creditsText() -> NSAttributedString {
        // Update version and credits label
        let _ = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        // Create paragraph style for center alignment
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        // Create attributed string with links
        let attributedString = NSMutableAttributedString()

        // Base attributes
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        // Link attributes
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.linkColor,
            .paragraphStyle: paragraphStyle,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        attributedString.append(NSAttributedString(string: "Built with ❤️ by the Radio Paradise fans at ", attributes: baseAttributes))

        // Add rybr.dev link
        let rybrLink = NSAttributedString(string: "rybr.dev", attributes: linkAttributes.merging([.link: "https://rybr.dev"], uniquingKeysWith: { _, new in new }))
        attributedString.append(rybrLink)

        attributedString.append(NSAttributedString(string: ". You can support development of this app by ", attributes: baseAttributes))

        // Add coffee link
        let coffeeLink = NSAttributedString(string: "buying us a coffee", attributes: linkAttributes.merging([.link: "https://buymeacoffee.com/rybr.dev"], uniquingKeysWith: { _, new in new }))
        attributedString.append(coffeeLink)

        attributedString.append(NSAttributedString(string: "!", attributes: baseAttributes))

        return attributedString
    }

    // MARK: - Button Actions

    @IBAction func supportRadioParadiseButtonClicked(_ sender: NSButton) {
        window?.close()
        if let url = URL(string: "https://radioparadise.com/support") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // The window will be hidden but not deallocated since we're using XIB
        // This allows for faster subsequent shows
    }
}

// Custom NSTextView that handles cursor changes for links even when not selectable
class LinkTrackingTextView: NSTextView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        // Add new tracking area for mouse movement
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
        let locationInTextView = convert(event.locationInWindow, from: nil)

        // Check if we're over a link
        if let textStorage = textStorage,
           let layoutManager = layoutManager,
           let textContainer = textContainer {

            let characterIndex = layoutManager.characterIndex(
                for: locationInTextView,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            if characterIndex < textStorage.length {
                let attributes = textStorage.attributes(at: characterIndex, effectiveRange: nil)
                if attributes[.link] != nil {
                    NSCursor.pointingHand.set()
                    return
                }
            }
        }

        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let locationInTextView = convert(event.locationInWindow, from: nil)

        // Check if we clicked on a link
        if let textStorage = textStorage,
           let layoutManager = layoutManager,
           let textContainer = textContainer {

            let characterIndex = layoutManager.characterIndex(
                for: locationInTextView,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            if characterIndex < textStorage.length {
                let attributes = textStorage.attributes(at: characterIndex, effectiveRange: nil)
                if let linkURL = attributes[.link] as? String,
                   let url = URL(string: linkURL) {
                    window?.close()
                    NSWorkspace.shared.open(url)
                    return
                }
            }
        }

        // If not a link, call super
        super.mouseDown(with: event)
    }
}
