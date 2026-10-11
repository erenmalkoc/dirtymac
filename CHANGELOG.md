# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-10-11

A "safe exits" release: the lock tells the truth about what it blocks, always lets you out, and every way out is now covered by tests.

### Added
- **Secure Input warning.** While another app holds Secure Event Input (a focused password field, Terminal's Secure Keyboard Entry), macOS sends keystrokes past every event tap, so no app can block them. The panel now says so and names the app when macOS tells which one; dirtymac comes forward so apps that only hold secure input while frontmost let go of it. Full lockdown does not start while secure input is on and ends if it turns on mid-lock, because hold-Esc could not get through either. Spotlight and Shortcuts open the panel instead of locking blind in that case.
- **The lock ends with the session.** Sleep, a locked screen, a user switch, System Settings coming forward or a revoked Accessibility permission now end the lock, and the panel explains why. Switching Accessibility off under a live tap can hang all input on macOS 15 and 26.
- **Sound cues.** A short system sound when the keyboard locks, a tick each second while Esc is held, ticks in the last three seconds before an auto-unlock, and a chime on unlock. On by default; Settings → Sound turns them off.
- **New app icon and menu bar glyph.** A keycap with one clean stripe across a dusty top; the menu bar glyph turns red while locked.
- VoiceOver label and state on the power button.

### Changed
- Hold-Esc now finishes the unlock when Esc comes up (at most 1.5 s later), so the rest of the press no longer auto-repeats into the frontmost app.
- Full lockdown also blocks trackpad gestures (pinch, rotate, smart zoom).
- The right-click menu, the menu bar tooltip and the Auto-unlock labels follow the in-app language instead of the system language.

### Fixed
- The panel opened at every login for people with open at login on: the login-item check ran before macOS made the launch event available.
- The locked menu bar icon was drawn black, not red (`contentTintColor` does not tint a non-template image).
- Hold-Esc and auto-unlock stalled while a dirtymac menu was open; lock timers now run in every run-loop mode.
- Every unlock left a disabled event tap alive until the app quit; the tap is now invalidated.
- After the Mac slept the countdown could sit at 00:00 while the lock kept running; lock time is measured on one monotonic clock that counts sleep.
- The Auto-unlock picker was blank for people who upgraded from 1.1.x with mouse lockdown and the timer off.
- The stop control stays in the panel while a lock runs, even if the Accessibility permission was revoked meanwhile.

### Development
- The test target picks up new files by itself, and CI fails when fewer tests run than are declared, when a string is missing from the catalog or untranslated, or when the Release configuration does not build. The lock core runs against a fake event tap and clock, so every exit is tested on each build without an Accessibility permission.
- Releases run the test suite first, check that the tag matches the app version and the CHANGELOG, refuse to rebuild a published release, and keep the signing keychain away from third-party actions.

## [1.2.0] - 2026-09-23

### Added
- **Global shortcut** (⌃⌥⌘K by default) opens the menu bar panel from any app. Settings → Quick Access offers two other combinations or Off, and warns when another app already owns the chosen one. Uses Carbon's `RegisterEventHotKey`, so it needs no extra permission.
- **Spotlight and Shortcuts actions** — *Lock Keyboard for Cleaning* and *Open dirtymac* are App Intents, so they work even when dirtymac isn't running: macOS launches the app and runs the action. A Shortcut built from them can be given its own keyboard shortcut in the Shortcuts app. Full lockdown (mouse included) and a missing Accessibility permission still go through the panel's confirmation instead of locking blind.
- **Open at login** via `SMAppService`. New users get the choice (on by default) on the last onboarding step; existing users are offered it once in the What's New window; it can be changed any time in Settings → Quick Access, with a link to System Settings when macOS is holding the login item for approval.
- **What's New window**, shown once after an update that has release notes. It collects every release the user skipped, is not shown to brand-new users (onboarding already covers it), and can be reopened from Settings → Help.
- Launching dirtymac by hand (Spotlight, Finder, Launchpad) now opens the panel right away — both on a cold start and when it is already running. Login-item launches stay silent.
- Unit test target (What's New version logic, global shortcut registration and conflicts, lock rules), run by CI on every push.

### Fixed
- The Auto-unlock picker no longer offers "Off" (or anything below 30 seconds) while **Block mouse & trackpad** is on. `LockConfiguration.effective` already forced a 30-second minimum in that mode, so the picker could display a setting the lock would not actually use — Settings said "Off" while the session was really running a 30-second timer.
- Quitting from the status item's right-click menu now releases the keyboard first, like the popover's Quit button does. The event tap was torn down by the process exit either way, so nothing was ever left locked, but the two quit paths now do the same thing.

## [1.1.2] - 2026-07-24

Packaging fix only — no changes to the app itself.

### Fixed
- Gatekeeper no longer refuses the app after `brew install --cask`. Only the DMG was stapled, and Homebrew copies `dirtymac.app` out of the DMG into `/Applications` — leaving the ticket behind. The app then had to be verified against Apple over the network on first launch, so anyone offline or behind a proxy that blocks Apple's notary endpoints was told it couldn't be checked for malware. The release script now notarizes and staples the `.app` itself before the DMG is built, so the installed copy validates with no network.
- The DMG is now signed with the Developer ID certificate as well, so a direct download from the Releases page has a signature for Gatekeeper to evaluate.
- Release builds now fail loudly when Apple rejects a notarization. `notarytool submit --wait` exits 0 for a completed-but-rejected submission, so the final status is read back explicitly and the notary log is printed on failure.

## [1.1.1] - 2026-05-25

### Changed
- Minimum macOS is now **macOS 14 (Sonoma)**, down from macOS 26. The UI moved from Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)` / `.glassProminent`) to standard SwiftUI `Material` surfaces with `.bordered` / `.borderedProminent` buttons. The locked-state power orb keeps its red-tinted, pressable feel via a custom `ButtonStyle`. Same app, much wider audience.

### Fixed
- Menu bar popover now opens instantly. The double-click-to-quit shortcut imposed a ~250–500 ms `NSEvent.doubleClickInterval` wait on every single click; quit moved to the right-click menu so the single-click path has zero delay.
- Onboarding window now opens centered on first launch. `NSHostingController` was missing `sizingOptions = .preferredContentSize`, so `window.center()` ran against a default-sized window and the content's later 460×560 layout pushed the frame off-center.
- Bundle icon is cached at app launch and reused across popover opens, instead of being looked up via `NSWorkspace` on every open.
- The Accessibility permission re-check no longer blocks the popover's first frame; it's deferred by one run-loop tick.

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

[Unreleased]: https://github.com/erenmalkoc/dirtymac/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.3.0
[1.2.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.2.0
[1.1.2]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.2
[1.1.1]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.1
[1.1.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.0
[1.0.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.0.0
