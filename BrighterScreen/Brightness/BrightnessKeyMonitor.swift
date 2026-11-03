import AppKit
import ApplicationServices

/// Intercepts brightness media keys so presses past SDR max can drive the
/// extended EDR range. Requires Accessibility permission for the session event tap.
@MainActor
final class BrightnessKeyMonitor {
    typealias Handler = (_ brightnessUp: Bool) -> Bool

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: Handler?
    private var retryTimer: Timer?
    private var selfRetention: Unmanaged<BrightnessKeyMonitor>?

    private static let systemDefinedEventType: UInt32 = 14
    private static let auxControlButtonsSubtype: Int16 = 8
    private static let brightnessUpKeyType = 2
    private static let brightnessDownKeyType = 3

    func start(handler: @escaping Handler) {
        self.handler = handler
        armTap()
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        tearDownTap()
        handler = nil
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPromptIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func armTap() {
        tearDownTap()

        let mask =
            CGEventMask(1 << Self.systemDefinedEventType) |
            CGEventMask(1 << CGEventType.keyDown.rawValue)

        let retained = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<BrightnessKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: retained.toOpaque()
        ) else {
            retained.release()
            scheduleRetry()
            return
        }

        selfRetention = retained
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func tearDownTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        selfRetention?.release()
        selfRetention = nil
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.armTap()
            }
        }
    }

    private nonisolated func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                if let tap = self?.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Event taps can fire off the main thread; hop synchronously so we
        // can decide whether to consume before returning.
        var shouldConsume = false
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                shouldConsume = interpret(type: type, event: event)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    shouldConsume = interpret(type: type, event: event)
                }
            }
        }
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func interpret(type: CGEventType, event: CGEvent) -> Bool {
        guard let handler else { return false }

        if type == .keyDown {
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case 144: return handler(true)
            case 145: return handler(false)
            default: return false
            }
        }

        guard type.rawValue == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlButtonsSubtype
        else { return false }

        let data1 = nsEvent.data1
        let keyCode = (data1 >> 16) & 0xFF
        let keyDown = ((data1 & 0x0100) == 0)
        guard keyDown else { return false }

        switch keyCode {
        case Self.brightnessUpKeyType:
            return handler(true)
        case Self.brightnessDownKeyType:
            return handler(false)
        default:
            return false
        }
    }
}
