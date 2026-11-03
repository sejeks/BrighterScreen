import AppKit
import CoreGraphics
import Foundation

enum ArchitectureGuard {
    /// Apple Silicon only; requires a built-in display.
    static var isSupportedAppleSiliconMac: Bool {
        #if arch(arm64)
        return hasBuiltInDisplay
        #else
        return false
        #endif
    }

    private static var hasBuiltInDisplay: Bool {
        for screen in NSScreen.screens {
            if let id = screen.displayID, CGDisplayIsBuiltin(id) != 0 {
                return true
            }
        }
        return CGDisplayIsBuiltin(CGMainDisplayID()) != 0
    }
}
