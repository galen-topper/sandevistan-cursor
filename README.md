# Sandevistan

A macOS cursor trail inspired by David Martinez's Sandevistan from *Cyberpunk: Edgerunners*. Ghost afterimages of your cursor fade behind it, shifting through a neon color palette.

## Usage

```bash
swift build
swift run Sandevistan
```

Grant Accessibility permission when prompted (System Settings > Privacy & Security > Accessibility).

Press **Ctrl+Shift+S** to toggle the trail on/off.

## Configuration

Edit `~/.config/sandevistan/config.json` (created on first run). Changes hot-reload automatically.

```json
{
  "ghostCount": 6,
  "lifespanMs": 500,
  "colors": ["#4bff21", "#00f0ff", "#772289", "#ff3333", "#f8e602"],
  "samplingIntervalMs": 30,
  "hotkey": "ctrl+shift+s"
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `ghostCount` | 6 | Number of ghost afterimages (1-30) |
| `lifespanMs` | 500 | Ghost fade duration in ms (100-3000) |
| `colors` | green > cyan > purple > red > yellow | Hex color palette |
| `samplingIntervalMs` | 30 | Position sampling interval (10-200) |
| `hotkey` | `ctrl+shift+s` | Toggle hotkey |

## Requirements

- macOS 13+
- Swift 6.0+
