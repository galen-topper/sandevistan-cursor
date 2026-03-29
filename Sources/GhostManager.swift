import AppKit
import CoreVideo

struct CursorSample {
    let position: NSPoint
    let timestamp: CFTimeInterval
}

@MainActor
final class GhostManager {
    private var windows: [NSWindow] = []
    private var imageViews: [NSImageView] = []
    private var ringBuffer: [CursorSample] = []
    private var bufferIndex: Int = 0
    private var displayLink: CVDisplayLink?
    private let renderer = CursorRenderer()

    var config: SandevistanConfig
    var isActive: Bool = false {
        didSet {
            if !isActive { hideAll() }
        }
    }
    private var lastSampleTime: CFTimeInterval = 0

    init(config: SandevistanConfig) {
        self.config = config
        rebuildWindowPool()
    }

    func rebuildWindowPool() {
        // Remove old windows
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        imageViews.removeAll()

        // Resize ring buffer
        ringBuffer = Array(repeating: CursorSample(position: .zero, timestamp: 0), count: config.ghostCount)
        bufferIndex = 0

        // Create new windows
        for _ in 0..<config.ghostCount {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hasShadow = false

            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            window.contentView = imageView

            windows.append(window)
            imageViews.append(imageView)
        }

        renderer.clearCache()
    }

    func addSample(position: NSPoint) {
        guard isActive else { return }
        let now = CACurrentMediaTime()
        let minInterval = Double(config.samplingIntervalMs) / 1000.0
        guard now - lastSampleTime >= minInterval else { return }
        lastSampleTime = now

        ringBuffer[bufferIndex] = CursorSample(position: position, timestamp: now)
        bufferIndex = (bufferIndex + 1) % config.ghostCount
    }

    func startDisplayLink() {
        guard displayLink == nil else { return }
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let dl else { return }

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkSetOutputCallback(dl, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let mgr = Unmanaged<GhostManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { mgr.updateGhosts() }
            return kCVReturnSuccess
        }, selfPtr)

        CVDisplayLinkStart(dl)
        displayLink = dl
    }

    func stopDisplayLink() {
        if let dl = displayLink {
            CVDisplayLinkStop(dl)
            displayLink = nil
        }
    }

    private func updateGhosts() {
        guard isActive else { return }
        let now = CACurrentMediaTime()
        let lifespanSec = Double(config.lifespanMs) / 1000.0
        let colors = config.colors

        for i in 0..<config.ghostCount {
            let sample = ringBuffer[i]
            let age = (now - sample.timestamp) / lifespanSec

            guard sample.timestamp > 0, age >= 0, age < 1.0 else {
                windows[i].orderOut(nil)
                continue
            }

            // Map age to color palette
            let colorPosition = age * Double(colors.count - 1)
            let colorIndex = min(Int(colorPosition), colors.count - 2)
            let colorFraction = colorPosition - Double(colorIndex)
            let hexColor = interpolateHex(colors[colorIndex], colors[colorIndex + 1], t: colorFraction)

            // Opacity: 0.7 at age 0, 0.0 at age 1
            let opacity = 0.7 * (1.0 - age)

            if let image = renderer.tintedCursor(hexColor: hexColor, opacity: CGFloat(opacity)) {
                let size = image.size
                imageViews[i].image = image
                windows[i].setFrame(
                    NSRect(x: sample.position.x, y: sample.position.y - size.height, width: size.width, height: size.height),
                    display: false
                )
                windows[i].alphaValue = CGFloat(opacity)
                windows[i].orderFrontRegardless()
            }
        }
    }

    private func hideAll() {
        for w in windows { w.orderOut(nil) }
        ringBuffer = Array(repeating: CursorSample(position: .zero, timestamp: 0), count: config.ghostCount)
        bufferIndex = 0
    }

    func updateConfig(_ newConfig: SandevistanConfig) {
        let needsRebuild = newConfig.ghostCount != config.ghostCount
        config = newConfig
        renderer.clearCache()
        if needsRebuild { rebuildWindowPool() }
    }

    private func interpolateHex(_ a: String, _ b: String, t: Double) -> String {
        func parse(_ hex: String) -> (r: Double, g: Double, b: Double) {
            var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            if h.hasPrefix("#") { h.removeFirst() }
            guard let val = UInt64(h, radix: 16) else { return (0, 1, 0) }
            return (
                Double((val >> 16) & 0xFF) / 255.0,
                Double((val >> 8) & 0xFF) / 255.0,
                Double(val & 0xFF) / 255.0
            )
        }
        let ca = parse(a), cb = parse(b)
        let r = Int((ca.r + (cb.r - ca.r) * t) * 255)
        let g = Int((ca.g + (cb.g - ca.g) * t) * 255)
        let b = Int((ca.b + (cb.b - ca.b) * t) * 255)
        return String(format: "#%02x%02x%02x", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}
