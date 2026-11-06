import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var currentEDRHeadroom: Double {
        Double(maximumExtendedDynamicRangeColorComponentValue)
    }

    var potentialEDRHeadroom: Double {
        Double(maximumPotentialExtendedDynamicRangeColorComponentValue)
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    static var builtIn: NSScreen? {
        screens.first { screen in
            guard let id = screen.displayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }
}
