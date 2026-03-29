import CoreGraphics
import AppKit

final class CursorTracker: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onMove: ((NSPoint) -> Void)?

    func start() -> Bool {
        guard checkAccessibility() else { return false }

        let mask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tracker = Unmanaged<CursorTracker>.fromOpaque(userInfo).takeUnretainedValue()
                let location = event.location
                // Flip Y coordinate: CGEvent uses top-left origin, NSWindow uses bottom-left
                if let screen = NSScreen.main {
                    let flippedY = screen.frame.maxY - location.y
                    tracker.onMove?(NSPoint(x: location.x, y: flippedY))
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            print("Sandevistan: failed to create event tap — check Accessibility permissions")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Sandevistan: cursor tracking started")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func checkAccessibility() -> Bool {
        // Use the raw CFString key directly to avoid touching the C global
        // kAXTrustedCheckOptionPrompt, which Swift 6 flags as shared mutable state.
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let trusted = AXIsProcessTrustedWithOptions(
            [promptKey: true] as CFDictionary
        )
        if !trusted {
            print("Sandevistan: Accessibility permission required — opening System Settings")
        }
        return trusted
    }
}
