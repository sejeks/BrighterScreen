import AppKit

/// Owns the extended brightness range: native 0–100% via DisplayServices,
/// and 100%…sliderMax via an EDR multiply overlay. Brightness keys continue
/// to work across both halves of the range when Extra Brightness is enabled.
@MainActor
final class BrightnessController {
    private(set) var isEnabled = false
    private(set) var logicalBrightness: Double = 50
    private(set) var maxBrightness: Double = 100
    private(set) var statusSummary = "Off"
    private(set) var needsAccessibility = false
    private(set) var hasEDRCapableDisplay = false

    var onStatusChange: (() -> Void)?

    private let overlay = EDROverlay()
    private let keyMonitor = BrightnessKeyMonitor()
    private var displayID: CGDirectDisplayID?
    private var headroomTimer: Timer?
    private var ignoringHardwareCallbacks = false
    private var notificationsRegistered = false

    private static let enabledDefaultsKey = "BrighterScreen.enabled"

    /// DisplayServices C callback has no retained context; route through here.
    private static weak var activeController: BrightnessController?

    func start() {
        Self.activeController = self
        refreshDisplay()
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        syncFromHardware()
        registerScreenNotifications()
        registerHardwareBrightnessObserver()
        keyMonitor.start { [weak self] up in
            self?.handleBrightnessKey(up: up) ?? false
        }
        needsAccessibility = !keyMonitor.isTrusted
        applyEnabledState()
        notify()
    }

    func stop() {
        headroomTimer?.invalidate()
        headroomTimer = nil
        keyMonitor.stop()
        overlay.remove()
        if let displayID {
            DisplayServicesBridge.unregisterForBrightnessChanges(displayID: displayID)
        }
        NotificationCenter.default.removeObserver(self)
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled {
            needsAccessibility = !keyMonitor.isTrusted
            if needsAccessibility {
                keyMonitor.requestAccessibilityPromptIfNeeded()
            }
        }
        applyEnabledState()
        notify()
    }

    func toggleEnabled() {
        setEnabled(!isEnabled)
    }

    func promptForAccessibility() {
        keyMonitor.requestAccessibilityPromptIfNeeded()
        needsAccessibility = !keyMonitor.isTrusted
        notify()
    }

    // MARK: - Display

    private func refreshDisplay() {
        guard let screen = NSScreen.builtIn, let id = screen.displayID else {
            displayID = nil
            hasEDRCapableDisplay = false
            maxBrightness = 100
            statusSummary = "No built-in display"
            return
        }
        displayID = id
        let potential = screen.potentialEDRHeadroom
        hasEDRCapableDisplay = potential > BrightnessMath.hdrReadyThreshold
        if isEnabled, hasEDRCapableDisplay {
            maxBrightness = BrightnessMath.sliderMax(potentialHeadroom: potential)
        } else {
            maxBrightness = 100
        }
    }

    private func syncFromHardware() {
        guard let displayID,
              let value = DisplayServicesBridge.readBrightness(displayID: displayID)
        else { return }
        let percent = value * 100.0
        if logicalBrightness <= 100.0 || !isEnabled {
            logicalBrightness = percent
        }
        updateStatus()
    }

    private func registerScreenNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        refreshDisplay()
        overlay.realignIfNeeded()
        syncOverlay()
        updateStatus()
        notify()
    }

    @objc private func screensDidWake() {
        refreshDisplay()
        syncFromHardware()
        syncOverlay()
        notify()
    }

    // MARK: - Hardware observer

    private func registerHardwareBrightnessObserver() {
        guard let displayID, !notificationsRegistered else { return }
        let ok = DisplayServicesBridge.registerForBrightnessChanges(
            displayID: displayID,
            callback: { _, did, _, _, _ in
                DispatchQueue.main.async {
                    BrightnessController.activeController?.hardwareBrightnessChanged(displayID: did)
                }
            }
        )
        notificationsRegistered = ok
    }

    private func hardwareBrightnessChanged(displayID: CGDirectDisplayID) {
        guard displayID == self.displayID, !ignoringHardwareCallbacks else { return }
        guard let value = DisplayServicesBridge.readBrightness(displayID: displayID) else { return }
        let percent = value * 100.0

        if isEnabled, logicalBrightness > 100 {
            // System slider / auto-brightness moved off the SDR ceiling.
            if percent < 99.0 {
                logicalBrightness = percent
                syncOverlay()
            }
            updateStatus()
            notify()
            return
        }

        logicalBrightness = percent
        syncOverlay()
        updateStatus()
        notify()
    }

    // MARK: - Keys

    /// Returns true when the event should be consumed (not delivered to macOS).
    private func handleBrightnessKey(up: Bool) -> Bool {
        needsAccessibility = false
        guard isEnabled, hasEDRCapableDisplay else { return false }

        let step = BrightnessMath.nativeKeyStep

        if up {
            if logicalBrightness < 100 - 0.01 {
                // Still in native range — let macOS handle the key.
                return false
            }
            let next = BrightnessMath.clamp(
                logicalBrightness + step,
                min: 0,
                max: maxBrightness
            )
            applyLogicalBrightness(next, pinHardwareAtMax: true)
            return true
        }

        if logicalBrightness > 100 {
            let next = BrightnessMath.clamp(
                logicalBrightness - step,
                min: 0,
                max: maxBrightness
            )
            applyLogicalBrightness(max(next, 100), pinHardwareAtMax: true)
            if next < 100 {
                // Next down press can fall through to native once we're parked at 100.
            }
            return true
        }

        if abs(logicalBrightness - 100) < 0.5 {
            let next = BrightnessMath.clamp(100 - step, min: 0, max: maxBrightness)
            applyLogicalBrightness(next, pinHardwareAtMax: false)
            return true
        }

        return false
    }

    private func applyLogicalBrightness(_ value: Double, pinHardwareAtMax: Bool) {
        logicalBrightness = value
        guard let displayID else {
            updateStatus()
            notify()
            return
        }

        ignoringHardwareCallbacks = true
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.ignoringHardwareCallbacks = false
            }
        }

        if value <= 100 {
            DisplayServicesBridge.writeBrightness(displayID: displayID, value: value / 100.0)
        } else if pinHardwareAtMax {
            DisplayServicesBridge.writeBrightness(displayID: displayID, value: 1.0)
        }
        syncOverlay()
        updateStatus()
        notify()
    }

    // MARK: - Overlay

    private func applyEnabledState() {
        refreshDisplay()
        if isEnabled, hasEDRCapableDisplay {
            maxBrightness = BrightnessMath.sliderMax(
                potentialHeadroom: NSScreen.builtIn?.potentialEDRHeadroom ?? 1
            )
            startHeadroomPolling()
            syncOverlay()
        } else {
            maxBrightness = 100
            if logicalBrightness > 100 {
                applyLogicalBrightness(100, pinHardwareAtMax: true)
            }
            overlay.remove()
            headroomTimer?.invalidate()
            headroomTimer = nil
        }
        updateStatus()
    }

    private func startHeadroomPolling() {
        headroomTimer?.invalidate()
        headroomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncOverlay()
            }
        }
    }

    private func syncOverlay() {
        guard isEnabled, hasEDRCapableDisplay, let displayID,
              let screen = NSScreen.screen(for: displayID)
        else {
            overlay.remove()
            return
        }

        let factor = BrightnessMath.overlayFactor(
            brightness: logicalBrightness,
            sliderMax: maxBrightness,
            currentEDR: screen.currentEDRHeadroom,
            potentialHeadroom: screen.potentialEDRHeadroom
        )
        if factor <= 1.001 {
            overlay.remove()
        } else {
            _ = overlay.setFactor(factor, for: displayID)
        }
    }

    private func updateStatus() {
        if !hasEDRCapableDisplay {
            statusSummary = "No EDR display"
            return
        }
        if !isEnabled {
            statusSummary = String(format: "Off · %.0f%%", logicalBrightness.rounded())
            return
        }
        if logicalBrightness > 100 {
            statusSummary = String(format: "EDR · %.0f%%", logicalBrightness.rounded())
        } else {
            statusSummary = String(format: "On · %.0f%%", logicalBrightness.rounded())
        }
    }

    private func notify() {
        onStatusChange?()
    }
}
