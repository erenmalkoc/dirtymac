# dirtymac

A native macOS menu bar utility that temporarily locks your keyboard so you can clean it without triggering keys. Mouse and trackpad stay fully responsive — they're your escape hatch.

Built with SwiftUI and the native Liquid Glass APIs introduced in macOS 26.

## Why

Wiping crumbs out of a MacBook keyboard usually means dragging a Finder window full of garbage characters and accidentally launching apps. dirtymac suppresses every keystroke at the system event-tap level until you click stop. Your trackpad keeps working the entire time.

## Features

- One-click keyboard lock and unlock from the menu bar
- Mouse and trackpad never blocked — click the menu bar icon to release
- Live elapsed-time display while locked
- Auto re-enables the event tap if macOS times it out
- Native macOS 26 Liquid Glass UI — no custom material stacks
- No Dock icon (`LSUIElement`)
- No network access, no analytics, no background daemons

## Requirements

- macOS 26 or later
- Xcode 26 or later (to build from source)

## Build & Run

```bash
git clone https://github.com/<your-handle>/dirtymac.git
cd dirtymac
open dirtymac.xcodeproj
```

Build and run the `dirtymac` scheme (`⌘R`) targeting *My Mac*.

## Permissions

dirtymac needs **Accessibility** access to intercept keyboard events. On first launch:

1. Click the menu bar icon, then **Grant Access** in the popover.
2. macOS will prompt you to enable dirtymac in **System Settings → Privacy & Security → Accessibility**.
3. Toggle dirtymac on and reopen the popover (or click **Refresh**).

The accessibility tap only swallows events; nothing is recorded, logged, or forwarded.

## How it works

dirtymac creates a `CGEventTap` at the session level (`.cgSessionEventTap`) listening for `keyDown`, `keyUp`, and `flagsChanged`. The callback returns `nil` for those event types, which removes them from the system input queue. Mouse, trackpad, and other input devices are never in the event mask, so they continue to function — including the click that opens the menu and disables the lock.

If macOS disables the tap (timeout or excessive callback latency), dirtymac re-enables it automatically.

## Project layout

```
dirtymac/
├── dirtymacApp.swift          # @main, MenuBarExtra
├── KeyboardBlocker.swift      # CGEventTap + AX permission
├── MenuBarPopoverView.swift   # popover layout
└── GlassComponents.swift      # GlassPowerButton, StatusPill
```

## Privacy

dirtymac runs entirely on your Mac:

- No network connections
- No telemetry, analytics, or crash reporting
- No background processes — quitting the app fully releases the keyboard

The hardened runtime is enabled. The app is unsandboxed because the system event tap requires it.

## Contributing

Issues and pull requests welcome. Please keep changes scoped — the goal is to stay a small, focused utility.

## License

[MIT](LICENSE) © 2026 Eren Malkoç
