import CoreGraphics
import Darwin
import Foundation

/// Thin dlsym bridge to private DisplayServices brightness APIs used on
/// Apple Silicon (CoreDisplay user-brightness setters are ineffective there).
enum DisplayServicesBridge {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen(frameworkPath, RTLD_LAZY)
    }()

    typealias BrightnessChangeHandler = @convention(c) (
        UnsafeMutableRawPointer?,
        CGDirectDisplayID,
        UnsafeMutableRawPointer?,
        UnsafeRawPointer?,
        UnsafeRawPointer?
    ) -> Void

    private typealias GetBrightnessFn =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn =
        @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias RegisterBrightnessChangeFn =
        @convention(c) (CGDirectDisplayID, UInt32, BrightnessChangeHandler) -> Int32
    private typealias UnregisterBrightnessChangeFn =
        @convention(c) (CGDirectDisplayID, UInt32) -> Int32

    private static let getBrightness: GetBrightnessFn? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetBrightnessFn.self)
    }()

    private static let setBrightness: SetBrightnessFn? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetBrightnessFn.self)
    }()

    private static let registerBrightnessChange: RegisterBrightnessChangeFn? = {
        guard let handle,
              let sym = dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications")
        else { return nil }
        return unsafeBitCast(sym, to: RegisterBrightnessChangeFn.self)
    }()

    private static let unregisterBrightnessChange: UnregisterBrightnessChangeFn? = {
        guard let handle,
              let sym = dlsym(handle, "DisplayServicesUnregisterForBrightnessChangeNotifications")
        else { return nil }
        return unsafeBitCast(sym, to: UnregisterBrightnessChangeFn.self)
    }()

    static var isAvailable: Bool {
        getBrightness != nil && setBrightness != nil
    }

    /// Hardware brightness in 0...1.
    static func readBrightness(displayID: CGDirectDisplayID) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(displayID, &value) == 0 else { return nil }
        return Double(value)
    }

    /// Hardware brightness in 0...1.
    @discardableResult
    static func writeBrightness(displayID: CGDirectDisplayID, value: Double) -> Bool {
        guard let setBrightness else { return false }
        let clamped = Float(BrightnessMath.clamp(value, min: 0, max: 1))
        return setBrightness(displayID, clamped) == 0
    }

    /// Register for built-in brightness changes (keys, slider, auto-brightness).
    /// The callback does not receive the new value; read it back with `readBrightness`.
    @discardableResult
    static func registerForBrightnessChanges(
        displayID: CGDirectDisplayID,
        callback: BrightnessChangeHandler
    ) -> Bool {
        guard let registerBrightnessChange else { return false }
        return registerBrightnessChange(displayID, displayID, callback) == 0
    }

    @discardableResult
    static func unregisterForBrightnessChanges(displayID: CGDirectDisplayID) -> Bool {
        guard let unregisterBrightnessChange else { return false }
        return unregisterBrightnessChange(displayID, displayID) == 0
    }
}
