import AppKit

final class CursorRenderer {
    private var cache: [String: NSImage] = [:]
    private var baseCursorHash: Int = 0

    func tintedCursor(hexColor: String, opacity: CGFloat) -> NSImage? {
        let cacheKey = "\(hexColor)_\(Int(opacity * 100))"
        if let cached = cache[cacheKey] { return cached }

        guard let cursor = NSCursor.currentSystem else { return nil }
        let cursorImage = cursor.image

        // Invalidate cache if cursor changed
        let currentHash = cursorImage.tiffRepresentation.hashValue
        if currentHash != baseCursorHash {
            cache.removeAll()
            baseCursorHash = currentHash
        }

        let size = cursorImage.size
        let image = NSImage(size: size)
        image.lockFocus()

        // Draw original cursor
        cursorImage.draw(in: NSRect(origin: .zero, size: size))

        // Overlay tint color using source-atop compositing
        let color = NSColor(hex: hexColor) ?? .green
        color.withAlphaComponent(opacity * 0.8).set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)

        image.unlockFocus()
        cache[cacheKey] = image
        return image
    }

    func clearCache() {
        cache.removeAll()
        baseCursorHash = 0
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >> 8) & 0xFF) / 255.0,
            blue: CGFloat(val & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
