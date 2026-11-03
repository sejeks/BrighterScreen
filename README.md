# BrighterScreen

Native Swift menu-bar utility for **Apple Silicon MacBooks** that extends brightness past the SDR ceiling into EDR/HDR headroom — Lunar / Vivid class, MVP scope only.

When Extra Brightness is enabled, the built-in brightness keys and system brightness behavior continue to work across an **enlarged range**: 0–100% stays native backlight control; past 100% an EDR multiply overlay lifts the desktop into available HDR headroom.

## Requirements

- Apple Silicon Mac (arm64 only)
- Built-in Liquid Retina XDR / EDR-capable display (typical MacBook Pro 14"/16")
- macOS 13 Ventura or later
- Xcode 15+ (for building)
- **Accessibility** permission so brightness keys can be intercepted once you cross 100%

## Build & run (Xcode)

1. Clone this repository and open `BrighterScreen.xcodeproj` in Xcode on an Apple Silicon Mac.
2. Select the **BrighterScreen** scheme and the **My Mac** run destination.
3. Build and run (`⌘R`). The app is an agent (`LSUIElement`): it appears in the menu bar (sun icon), not in the Dock.
4. From the menu bar item, choose **Enable Extra Brightness**.
5. If prompted, grant **Accessibility** under  
   System Settings → Privacy & Security → Accessibility → BrighterScreen.
6. Raise brightness with the keyboard keys until you pass 100%. Further presses increase EDR boost (menu status shows `EDR · N%`). Lowering brightness walks back through EDR into the normal SDR range.

### Command-line build

```bash
xcodebuild -scheme BrighterScreen -configuration Debug -arch arm64 build
```

The `.app` lands under DerivedData; open it from Xcode’s Products group, or:

```bash
open ~/Library/Developer/Xcode/DerivedData/BrighterScreen-*/Build/Products/Debug/BrighterScreen.app
```

## How it works (MVP)

| Range | Mechanism |
| --- | --- |
| 0–100% | `DisplayServices` get/set brightness (native keys / slider) |
| >100% | Full-screen click-through `CAMetalLayer` with `wantsExtendedDynamicRangeContent` + multiply compositing filter (Vivid-style EDR overlay) |
| Keys past 100% | `CGEvent` tap on brightness media keys (needs Accessibility) |

No schedules, per-app profiles, external DDC, or custom brightness UI beyond the menu-bar toggle.

## Notes

- Sandboxing is **off** — private `DisplayServices` symbols and a session event tap are required for MVP behavior.
- macOS still owns thermal / ABL limits; BrighterScreen cannot force nits above what the panel will deliver.
- Intel Macs are intentionally unsupported (`ARCHS = arm64`, runtime guard).

## License

See repository license when present; otherwise all rights reserved by the repository owner.
