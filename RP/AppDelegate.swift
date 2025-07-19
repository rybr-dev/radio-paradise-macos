
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Setup the menu bar extra
        StatusMenuController.shared.setupMenu()

        // Setup notifications
        NotificationService.shared.setupNotifications()

        // Start the radio player
        RadioPlayer.shared.play()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        RadioPlayer.shared.stop()
    }
}
