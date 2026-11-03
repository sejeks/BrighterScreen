import AppKit
import Metal
import QuartzCore

/// Full-screen click-through EDR multiply overlay that lifts desktop luminance
/// into HDR headroom (Vivid / BrightIntosh / Crisp style).
@MainActor
final class EDROverlay {
    private struct OverlayState {
        let window: NSWindow
        let layer: CAMetalLayer
        var factor: Double
        var timer: Timer?
        var revealed = false
    }

    private var overlay: OverlayState?
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = device?.makeCommandQueue()
    private(set) var displayID: CGDirectDisplayID?

    var isActive: Bool { overlay != nil }

    @discardableResult
    func setFactor(_ factor: Double, for displayID: CGDirectDisplayID) -> Bool {
        let clamped = max(1.0, factor)
        if overlay == nil {
            guard clamped > 1.001 else { return true }
            guard createOverlay(for: displayID) else { return false }
        }
        guard var state = overlay else { return false }
        self.displayID = displayID
        guard abs(state.factor - clamped) > 0.004 else { return true }
        state.factor = clamped
        overlay = state
        render()
        return true
    }

    func remove() {
        overlay?.timer?.invalidate()
        overlay?.window.close()
        overlay = nil
        displayID = nil
    }

    func realignIfNeeded() {
        guard let displayID, let screen = NSScreen.screen(for: displayID), let state = overlay else {
            if let displayID, NSScreen.screen(for: displayID) == nil {
                remove()
            }
            return
        }
        if state.window.frame != screen.frame {
            state.window.setFrame(screen.frame, display: true)
            state.layer.frame = CGRect(origin: .zero, size: screen.frame.size)
        }
        render()
    }

    private func createOverlay(for displayID: CGDirectDisplayID) -> Bool {
        guard let screen = NSScreen.screen(for: displayID), let device else { return false }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.ignoresMouseEvents = true
        window.collectionBehavior = [
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        window.hasShadow = false
        window.alphaValue = 0

        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.isOpaque = false
        metalLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
        metalLayer.drawableSize = CGSize(width: 1, height: 1)
        metalLayer.compositingFilter = "multiply"

        let host = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        host.layer = metalLayer
        window.contentView = host
        window.orderFrontRegardless()

        self.displayID = displayID
        overlay = OverlayState(window: window, layer: metalLayer, factor: 1.0, timer: nil)

        // Keep presenting so WindowServer does not promote the window to
        // direct scanout and drop the multiply filter.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.render()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        overlay?.timer = timer

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.reveal()
        }
        return true
    }

    private func render() {
        guard let state = overlay, let commandQueue else { return }
        if let displayID, let screen = NSScreen.screen(for: displayID),
           state.window.frame != screen.frame {
            state.window.setFrame(screen.frame, display: true)
            state.layer.frame = CGRect(origin: .zero, size: screen.frame.size)
        }
        guard let drawable = state.layer.nextDrawable() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let f = state.factor
        pass.colorAttachments[0].clearColor = MTLClearColor(red: f, green: f, blue: f, alpha: 1)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        if !state.revealed {
            commandBuffer.addCompletedHandler { [weak self] _ in
                DispatchQueue.main.async { self?.reveal() }
            }
        }
        commandBuffer.commit()
    }

    private func reveal() {
        guard var state = overlay, !state.revealed else { return }
        state.revealed = true
        overlay = state
        state.window.alphaValue = 1
    }
}
