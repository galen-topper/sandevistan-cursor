import AppKit

final class HotkeyListener: @unchecked Sendable {
    private var monitor: Any?
    var hotkey: String
    var onToggle: (() -> Void)?

    init(hotkey: String) {
        self.hotkey = hotkey
    }

    func start() {
        let parsed = parseHotkey(hotkey)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let parsed = self.parseHotkey(self.hotkey) else { return }
            let modifiersMatch = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == parsed.modifiers
            let keyMatch = event.keyCode == parsed.keyCode
            if modifiersMatch && keyMatch {
                self.onToggle?()
            }
        }
        if parsed != nil {
            print("Sandevistan: hotkey registered — \(hotkey)")
        } else {
            print("Sandevistan: warning — could not parse hotkey '\(hotkey)'")
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func updateHotkey(_ newHotkey: String) {
        stop()
        hotkey = newHotkey
        start()
    }

    private func parseHotkey(_ str: String) -> (modifiers: NSEvent.ModifierFlags, keyCode: UInt16)? {
        let parts = str.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            case "alt", "option", "opt": modifiers.insert(.option)
            case "cmd", "command", "meta": modifiers.insert(.command)
            default: break
            }
        }

        guard let lastPart = parts.last, lastPart.count == 1,
              let keyCode = keyCodeForCharacter(lastPart) else { return nil }

        return (modifiers, keyCode)
    }

    private func keyCodeForCharacter(_ char: String) -> UInt16? {
        // Common key codes for US keyboard layout
        let map: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
            "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        ]
        return map[char]
    }
}
