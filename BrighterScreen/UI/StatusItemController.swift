import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let brightnessController: BrightnessController

    init(brightnessController: BrightnessController) {
        self.brightnessController = brightnessController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sun.max.fill",
                accessibilityDescription: "BrighterScreen"
            )
            button.toolTip = "BrighterScreen"
        }
        brightnessController.onStatusChange = { [weak self] in
            self?.rebuildMenu()
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: "BrighterScreen", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let status = NSMenuItem(
            title: brightnessController.statusSummary,
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: brightnessController.isEnabled
                ? "Disable Extra Brightness"
                : "Enable Extra Brightness",
            action: #selector(toggleExtraBrightness),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = brightnessController.hasEDRCapableDisplay
        menu.addItem(toggle)

        if brightnessController.needsAccessibility {
            let access = NSMenuItem(
                title: "Grant Accessibility for Brightness Keys…",
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            access.target = self
            menu.addItem(access)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit BrighterScreen",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.appearsDisabled = !brightnessController.isEnabled
    }

    @objc private func toggleExtraBrightness() {
        brightnessController.toggleEnabled()
    }

    @objc private func requestAccessibility() {
        brightnessController.promptForAccessibility()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
