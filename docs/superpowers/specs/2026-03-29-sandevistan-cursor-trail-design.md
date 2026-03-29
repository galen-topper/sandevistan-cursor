# Sandevistan Cursor Trail — Design Spec

A macOS system-wide cursor trail effect inspired by David Martinez's Sandevistan from Cyberpunk: Edgerunners. Ghost afterimages of the cursor fade behind it, shifting through a configurable color palette.

## Platform & Delivery

- **macOS background daemon** (no dock icon, no menu bar)
- **Swift**, using AppKit and Core Graphics
- Launches at login, runs invisibly
- Configured via JSON file at `~/.config/sandevistan/config.json`

## Architecture

### Approach: NSWindow Overlay

One transparent, click-through NSWindow per ghost cursor. Each window holds an NSImageView rendering the current system cursor image, tinted to the appropriate color and opacity. Windows are repositioned and recycled as the cursor moves.

Why this over a single CALayer overlay: simpler, works reliably across Spaces and fullscreen apps, negligible overhead for a small number of windows.

### Cursor Tracking

- **CGEvent tap** (requires Accessibility permission) listens for `mouseMoved`, `leftMouseDragged`, `rightMouseDragged`, and `otherMouseDragged` events
- On each event, records `(position, timestamp)` into a ring buffer
- Sampling is throttled by `samplingIntervalMs` (default 30ms) — events arriving faster than the interval are dropped to avoid over-saturating the buffer

### Components

1. **CursorTracker**
   - Sets up the CGEvent tap
   - Captures mouse position on every qualifying move event
   - Pushes `(position, timestamp)` into the ring buffer
   - Requests Accessibility permission on first launch if not granted

2. **GhostManager**
   - Owns the ring buffer and the pool of NSWindows
   - On each display link tick (~60fps):
     - Iterates the buffer, skips entries older than `lifespanMs`
     - For each live entry, calculates `age` (0.0 = just spawned, 1.0 = about to expire)
     - Maps `age` to a color from the palette (interpolated) and an opacity (linear fade)
     - Positions the corresponding NSWindow and applies the tint + opacity
     - Hides windows for expired entries, recycles them back to the pool
   - When config changes: resizes the window pool (creating or destroying windows), updates palette and lifespan

3. **CursorRenderer**
   - Captures the current system cursor image via `NSCursor.currentSystemCursor`
   - Applies a color tint using `CIColorMatrix` or simple Core Graphics blend
   - Caches tinted images per color to avoid re-rendering every frame
   - Invalidates cache when palette changes or cursor style changes

4. **ConfigLoader**
   - Reads and validates `~/.config/sandevistan/config.json`
   - Watches the file for changes using `DispatchSource.makeFileSystemObjectSource`
   - Notifies GhostManager on change to hot-reload settings
   - Writes a default config file if none exists on first launch

5. **HotkeyListener**
   - Registers a global hotkey using `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`
   - On hotkey press, toggles the `active` state on GhostManager
   - When deactivated: hides all ghost windows, stops populating the ring buffer
   - When activated: resumes tracking and rendering from the current cursor position
   - Re-registers when hotkey changes via config reload

6. **main.swift**
   - Entry point
   - Sets up NSApplication as `.accessory` (no dock icon)
   - Wires components together
   - Starts the run loop

## Ghost Window Properties

- `NSWindow.Level`: `.screenSaver + 1` (above all normal content)
- `ignoresMouseEvents = true` (fully click-through)
- `isOpaque = false`, `backgroundColor = .clear`
- `styleMask = .borderless`
- `collectionBehavior`: `.canJoinAllSpaces, .fullScreenAuxiliary` (visible across all Spaces and in fullscreen)

## Color Mapping & Fade

- The palette array maps linearly across each ghost's lifespan
- Age 0.0 (just spawned, nearest to cursor) → first color in palette
- Age 1.0 (about to expire, farthest from cursor) → last color in palette
- Colors are linearly interpolated in RGB space between palette stops
- Opacity fades linearly: 0.7 at age 0.0 → 0.0 at age 1.0

### Default Sandevistan Palette

The color progression matches the anime's echo shift:

| Age | Color | Hex |
|-----|-------|-----|
| 0.0 | Neon green | `#4bff21` |
| 0.25 | Cyan | `#00f0ff` |
| 0.5 | Deep purple | `#772289` |
| 0.75 | Red | `#ff3333` |
| 1.0 | Yellow | `#f8e602` |

## Activation

The trail is **off by default**. The user activates it with a global hotkey — like activating the Sandevistan itself.

- **Toggle hotkey** (default: `Ctrl+Shift+S`): toggles the trail on/off
- When off, the CGEvent tap is still active but ghost windows are hidden and the ring buffer is not populated
- When toggled on, the trail activates immediately from the current cursor position
- Hotkey is registered via `CGEvent.tapCreate` listening for key events, or via `NSEvent.addGlobalMonitorForEvents`
- Hotkey is configurable in the config file

## Configuration

File: `~/.config/sandevistan/config.json`

```json
{
  "ghostCount": 6,
  "lifespanMs": 500,
  "colors": ["#4bff21", "#00f0ff", "#772289", "#ff3333", "#f8e602"],
  "samplingIntervalMs": 30,
  "hotkey": "ctrl+shift+s"
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ghostCount` | int | 6 | Number of ghost afterimages (1-30) |
| `lifespanMs` | int | 500 | How long each ghost lives before fully fading (100-3000) |
| `colors` | string[] | see above | Hex color palette, any length >= 1 |
| `samplingIntervalMs` | int | 30 | Min interval between position samples (10-200) |
| `hotkey` | string | `"ctrl+shift+s"` | Global hotkey to toggle trail on/off |

- Config is hot-reloaded on file change (no restart needed)
- Invalid JSON or out-of-range values are ignored (previous valid config is kept)
- Missing file on launch triggers creation of default config

## Permissions

- **Accessibility** (required): CGEvent tap needs Accessibility access in System Settings > Privacy & Security > Accessibility
- On first launch, if not granted, the app logs a message and opens the relevant System Settings pane

## Project Structure

```
Sandevistan/
├── Package.swift
├── Sources/
│   ├── main.swift
│   ├── CursorTracker.swift
│   ├── GhostManager.swift
│   ├── CursorRenderer.swift
│   ├── ConfigLoader.swift
│   └── HotkeyListener.swift
└── README.md
```

Built as a Swift Package Manager executable.

## Out of Scope

- Menu bar UI or preferences window
- Launch agent / auto-start setup (user can configure manually via launchd)
- Multiple cursor support
- Per-application enable/disable rules
- Custom cursor shapes (uses system cursor only)
