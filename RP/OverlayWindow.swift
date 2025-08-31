//
//  OverlayWindow.swift
//  Radio Paradise
//

import Cocoa

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }

    static func create(withRect overlayRect: NSRect) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: overlayRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        return window
    }
}
