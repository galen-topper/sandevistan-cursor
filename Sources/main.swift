import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Load config
let configLoader = ConfigLoader()
print("Sandevistan: config loaded — ghostCount=\(configLoader.config.ghostCount), hotkey=\(configLoader.config.hotkey)")

// Set up ghost manager
let ghostManager = GhostManager(config: configLoader.config)
ghostManager.startDisplayLink()

// Set up cursor tracker
// onMove fires from the CGEvent tap, which runs on the main run loop thread.
// Swift 6 can't verify this, so we use MainActor.assumeIsolated.
let cursorTracker = CursorTracker()
cursorTracker.onMove = { position in
    MainActor.assumeIsolated {
        ghostManager.addSample(position: position)
    }
}

// Set up hotkey listener
// onToggle fires from NSEvent's global monitor, which dispatches on the main thread.
let hotkeyListener = HotkeyListener(hotkey: configLoader.config.hotkey)
hotkeyListener.onToggle = {
    MainActor.assumeIsolated {
        ghostManager.isActive.toggle()
        print("Sandevistan: \(ghostManager.isActive ? "ACTIVATED" : "deactivated")")
    }
}

// Config hot-reload
// onChange fires on DispatchQueue.main, so MainActor.assumeIsolated is safe here.
configLoader.onChange = { newConfig in
    MainActor.assumeIsolated {
        ghostManager.updateConfig(newConfig)
        hotkeyListener.updateHotkey(newConfig.hotkey)
    }
}

// Start tracking and listening
if cursorTracker.start() {
    hotkeyListener.start()
    print("Sandevistan: ready — press \(configLoader.config.hotkey) to activate")
} else {
    print("Sandevistan: failed to start — grant Accessibility permission and restart")
}

app.run()
