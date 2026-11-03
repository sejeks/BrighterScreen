import Foundation

/// Maps the extended brightness scale onto an EDR multiply factor.
/// 0...100 is the native SDR / backlight range (factor 1.0).
/// 100...sliderMax maps exponentially onto 1.0...currentEDR headroom.
enum BrightnessMath {
    static let hdrReadyThreshold = 1.05
    /// Small nudge above 1.0 that prompts macOS to ramp EDR headroom.
    static let pendingHDRFactor = 1.12
    /// Native key step matches macOS (~1/16 of the 0–100 range).
    static let nativeKeyStep = 100.0 / 16.0

    /// Extended slider ceiling from potential EDR headroom, capped at 200%.
    static func sliderMax(potentialHeadroom: Double) -> Double {
        guard potentialHeadroom > hdrReadyThreshold else { return 100 }
        return (100 * min(potentialHeadroom, 2.0)).rounded()
    }

    /// Overlay multiplier for a brightness on the extended scale.
    static func overlayFactor(
        brightness: Double,
        sliderMax: Double,
        currentEDR: Double,
        potentialHeadroom: Double
    ) -> Double {
        guard brightness > 100, sliderMax > 100 else { return 1.0 }
        guard potentialHeadroom > hdrReadyThreshold else { return 1.0 }
        guard currentEDR > hdrReadyThreshold else { return pendingHDRFactor }
        let t = min(1.0, (brightness - 100) / (sliderMax - 100))
        return pow(currentEDR, t)
    }

    static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(upper, Swift.max(lower, value))
    }
}
