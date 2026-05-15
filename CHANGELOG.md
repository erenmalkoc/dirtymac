# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-05-15

### Added
- First-launch guided onboarding: a 3-step welcome window (intro → Accessibility permission with live status → how-to), re-openable from Settings → Help.
- Basic / Advanced lock modes. Advanced lets you toggle modifier keys, media/brightness keys, and full mouse & trackpad lockdown, plus an auto-unlock timer.
- Universal hold-Esc emergency exit (3 seconds) — works in every mode, essential when the mouse is part of the lockdown.
- Auto-unlock countdown in the popover; mandatory minimum timer when mouse lockdown is enabled; confirmation before full lockdown.
- Status item interactions: single-click opens the popover, double-click quits, right-click shows an Open / Quit menu.

### Changed
- Menu bar icon redesigned for consistency: same `keyboard` glyph in both states (filled + red while locked) instead of swapping to an unrelated lock symbol. Calmer `.breathe` animation replaces the pulsing throb.
- `KeyboardBlocker` event mask is now built from the active configuration instead of being hardcoded.
- Replaced SwiftUI `MenuBarExtra` with a hand-managed `NSStatusItem` + `NSPopover` to enable the click interactions above.

### Fixed
- Full-lockdown confirmation no longer silently fails. It used a system `.confirmationDialog`, which made the menu bar popover resign key and close before the action ran; the confirmation is now inline within the popover.
- Onboarding window now honours the in-app Language and Appearance settings instead of falling back to the system locale.

## [1.0.0] - 2026-05-11

Initial release.

### Added
- Menu bar utility that locks the keyboard for cleaning while keeping mouse and trackpad active.
- Native Liquid Glass UI built on macOS 26 SwiftUI APIs (`.glassEffect`, `.buttonStyle(.glass)`).
- One-click power orb with live elapsed-time display.
- Settings page with system / light / dark appearance override and 12-language picker (English, Türkçe, Deutsch, Español, Français, Italiano, Português (Brasil), 日本語, 한국어, Русский, 简体中文, 繁體中文).
- Runtime language switching via String Catalog — no app restart required.
- System-defined event blocking covering brightness, volume, media, and F-key controls (subtype 8) in addition to standard key events.
- Automatic event-tap re-enable when macOS times out the tap.
- Accessibility permission flow with deep-link to System Settings.
- Menu bar icon swaps `keyboard.fill` ↔ `lock.fill` with a pulsing red tint while locked.

[Unreleased]: https://github.com/erenmalkoc/dirtymac/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.0
[1.0.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.0.0
