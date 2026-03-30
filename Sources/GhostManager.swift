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
            if isActive {
                cursorCatcherWindow?.orderFrontRegardless()
            } else {
                hideAll()
            }
        }
    }
    private var lastSampleTime: CFTimeInterval = 0
    private var currentPosition: NSPoint = .zero
    private var cursorWindow: NSWindow?
    private var cursorImageView: NSImageView?
    private var cursorCatcherWindow: NSWindow?
    private var colorCycleStart: CFTimeInterval = 0
    private static let blankCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        return NSCursor(image: image, hotSpot: .zero)
    }()

    init(config: SandevistanConfig) {
        self.config = config
        rebuildWindowPool()
    }

    private func makeOverlayWindow() -> NSWindow {
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
        return window
    }

    func rebuildWindowPool() {
        // Remove old windows
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        imageViews.removeAll()

        // Resize ring buffer
        ringBuffer = Array(repeating: CursorSample(position: .zero, timestamp: 0), count: config.ghostCount)
        bufferIndex = 0

        // Create ghost windows
        for _ in 0..<config.ghostCount {
            let window = makeOverlayWindow()
            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            window.contentView = imageView
            windows.append(window)
            imageViews.append(imageView)
        }

        // Create cursor overlay window (above ghosts)
        cursorWindow?.orderOut(nil)
        let cw = makeOverlayWindow()
        cw.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        let civ = NSImageView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        civ.imageScaling = .scaleProportionallyUpOrDown
        cw.contentView = civ
        cursorWindow = cw
        cursorImageView = civ
        colorCycleStart = CACurrentMediaTime()

        // Create cursor catcher window — hides system cursor by placing a blank cursor
        // This window does NOT ignore mouse events so macOS shows our custom cursor
        cursorCatcherWindow?.orderOut(nil)
        let catcherSize: CGFloat = 2
        let catcher = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: catcherSize, height: catcherSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        catcher.isOpaque = false
        catcher.backgroundColor = .clear
        catcher.ignoresMouseEvents = false  // must accept mouse to control cursor
        catcher.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)) + 2)
        catcher.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        catcher.hasShadow = false
        // Set blank cursor on the catcher's content view
        let catcherView = NSView(frame: NSRect(x: 0, y: 0, width: catcherSize, height: catcherSize))
        catcherView.addCursorRect(catcherView.bounds, cursor: GhostManager.blankCursor)
        catcher.contentView = catcherView
        cursorCatcherWindow = catcher

        renderer.clearCache()
    }

    func addSample(position: NSPoint) {
        currentPosition = position
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
        // Move the cursor catcher to follow the mouse — keeps system cursor blank
        if let catcher = cursorCatcherWindow {
            catcher.setFrameOrigin(NSPoint(x: currentPosition.x - 1, y: currentPosition.y - 1))
            catcher.orderFrontRegardless()
        }
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
                // Offset by cursor hotspot so the ghost's tip aligns with the recorded position
                let hotSpot = NSCursor.currentSystem?.hotSpot ?? NSPoint(x: 0, y: 0)
                imageViews[i].image = image
                windows[i].setFrame(
                    NSRect(x: sample.position.x - hotSpot.x, y: sample.position.y - (size.height - hotSpot.y), width: size.width, height: size.height),
                    display: false
                )
                windows[i].alphaValue = CGFloat(opacity)
                windows[i].orderFrontRegardless()
            }
        }

        // Update color-cycling cursor overlay
        updateCursorOverlay(now: now, colors: colors)
    }

    private func updateCursorOverlay(now: CFTimeInterval, colors: [String]) {
        guard let cw = cursorWindow, let civ = cursorImageView, colors.count >= 2 else { return }

        // Cycle through palette every 2 seconds
        let cycleDuration = 2.0
        let t = (now - colorCycleStart).truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        let colorPosition = t * Double(colors.count - 1)
        let colorIndex = min(Int(colorPosition), colors.count - 2)
        let colorFraction = colorPosition - Double(colorIndex)
        let hexColor = interpolateHex(colors[colorIndex], colors[colorIndex + 1], t: colorFraction)

        if let image = renderer.tintedCursor(hexColor: hexColor, opacity: 1.0) {
            let size = image.size
            let hotSpot = NSCursor.currentSystem?.hotSpot ?? NSPoint(x: 0, y: 0)
            civ.image = image
            cw.setFrame(
                NSRect(x: currentPosition.x - hotSpot.x, y: currentPosition.y - (size.height - hotSpot.y), width: size.width, height: size.height),
                display: false
            )
            cw.alphaValue = 1.0
            cw.orderFrontRegardless()
        }
    }

    private func hideAll() {
        for w in windows { w.orderOut(nil) }
        cursorWindow?.orderOut(nil)
        cursorCatcherWindow?.orderOut(nil)
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
