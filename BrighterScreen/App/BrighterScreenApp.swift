import AppKit

@main
enum BrighterScreenMain {
    static func main() {
        #if !arch(arm64)
        fputs("BrighterScreen requires Apple Silicon (arm64).\n", stderr)
        exit(1)
        #else
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Keep a strong reference for the lifetime of the run loop.
        AppDelegate.shared = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private var statusItemController: StatusItemController?
    private var brightnessController: BrightnessController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if arch(arm64)
        guard ArchitectureGuard.isSupportedAppleSiliconMac else {
            presentUnsupportedHardwareAlert()
            NSApp.terminate(nil)
            return
        }

        let controller = BrightnessController()
        brightnessController = controller
        statusItemController = StatusItemController(brightnessController: controller)
        controller.start()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        brightnessController?.stop()
    }

    private func presentUnsupportedHardwareAlert() {
        let alert = NSAlert()
        alert.messageText = "Unsupported Mac"
        alert.informativeText =
            "BrighterScreen only runs on Apple Silicon MacBooks with an EDR-capable built-in display."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }
}
