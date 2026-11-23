# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **A guard for the trackpad while the keyboard is locked.** A palm resting on the trackpad could still scroll and click things in the apps behind the lock. Now, in every mode, scrolling, trackpad gestures and clicks go nowhere while the keyboard is locked. The cursor still moves, and a click on the dirtymac menu bar icon, its panel and its menus still works, so the lock can always be ended with a click. A press that was let through is followed to its release, and a blocked one is blocked to its release, so no app sees half a click. Settings → While locked → **Ignore scrolling and clicks**, on by default, switches it off. With the mouse frozen (Advanced) everything is blocked as before. Which window is under the cursor comes from the window server and needs no extra permission.
- **The power (Touch ID) button is caught during a lock.** A short press used to put the Mac to sleep or lock the screen and so end the lock. dirtymac now swallows the power and sleep events of the keyboard lock (the same channel as the media keys, so it follows the **Block media & brightness keys** setting and is always on in Basic mode). This is best effort: whether macOS delivers a press of the button to an event tap depends on the Mac, so check it on yours. Holding the button to shut the Mac down is hardware and is never touched, and restart and shutdown requests still get through.

### Fixed
- The README and the code comment named subtype 1 as the power button that is let through on purpose. It is the power button, and it is now blocked during a lock. The long press stays the hardware way out.

## [1.4.0] - 2026-11-23

### Added
- **Update checks, off by default.** Nobody noticed when a new version came out, because dirtymac had no way to say so. Settings → Updates → Check for updates lets the app ask GitHub once a day for the number of the latest release. That one request is the only network use in the app: no identifier, cookie or usage data is sent, and the setting says plainly what leaves the Mac. When a newer version is found, the panel shows a notice with its release notes and, depending on how dirtymac was installed, the Homebrew command to copy or a download link. The menu bar icon gets a small dot and the right-click menu an entry for it.
- **Reminders for people who leave update checks off.** Every 60 days after a version was installed (60, 120, 180 …) the panel suggests looking for a new version, with a link to the releases page and a shortcut to the setting. **Later** hides it until the next step. This needs no connection: it only counts days.
- **A one-time offer in What's New** to turn update checks on. The box starts unticked.
- **Longer auto-unlock timers.** Advanced mode now offers 10 min, 15 min, 30 min and 1 hour next to the old choices. With the mouse and trackpad frozen the longest lock is 15 minutes, because hold-Esc and the timer are the only ways out and the time someone could be stuck behind a key that does not work should stay short. With the mouse free, up to an hour: clicking the menu bar icon still ends the lock. Switching the mouse freeze on pulls a longer timer down to 15 minutes.
- **An Esc check before long frozen-mouse locks.** The confirmation now says how long the keyboard will stay locked. A frozen-mouse lock longer than 5 minutes also asks you to hold Esc for 3 seconds first, and the Lock button stays off until you did. That finds a keyboard whose Esc does not reach the app while everything still works. The lock itself refuses to start without the check, so no other way of starting one can skip it.
- Settings explain the 15-minute limit and the check under the Auto-unlock timer while the mouse freeze is on.
- **A countdown for the hold-Esc exit.** Holding Esc to unlock gave no sign of how long was left, only a tick sound each second. The locked panel now fills a bar and says "Unlocking in 3…", 2, 1, then "Let go of Esc." The panel keeps its height through all three states.
- **Lock for a chosen time from the menu bar.** The right-click menu has a new **Lock for** entry: 1 min, 5 min, 15 min, 30 min or 1 hour, each a keyboard-only lock that ends by itself, with the key choices you set in Settings (Basic mode uses its own set). It is left out while a lock runs, and while your settings freeze the mouse: that lock goes through the panel's confirmation, and above 5 minutes through the Esc check. Without the Accessibility permission the click opens the panel for the usual prompt.
- **Five more languages.** Polish, Dutch, Ukrainian, Indonesian and Vietnamese join the twelve already there, 17 in all. Every string is translated, the language picker lists them by their own names, and the tests check that none is missing, that no number placeholder was damaged and that the longer texts still fit the panel.
- **VoiceOver hears the lock.** While VoiceOver runs, dirtymac speaks what the panel and the menu bar only show: the start delay counting down, "keyboard locked", the hold-Esc countdown 3, 2, 1 and "Let go of Esc", "Unlocks in 01:00" a minute and ten seconds before an auto-unlock, and "Keyboard unlocked". Each is said once, never every second.
- **Reduce motion is respected.** With it on, the locked menu bar icon stops fading, the panel fades between screens instead of sliding, and numbers change without rolling. It follows the setting while the app runs.
- **A delay before the lock starts.** Settings → Before locking → Start delay: off, 3, 5 or 10 seconds (off by default). After the click on Lock the panel and the menu bar count "Locking in 5…" with a Cancel button and a tick each second, and nothing is blocked until it reaches zero, so you can take your hands off the keyboard first. It applies to the panel, the menu bar's Lock for entry and the Shortcuts action alike. A lock that would be refused (no permission, secure input, a long frozen-mouse lock without its Esc check) is refused at the click, not after the countdown. Sleep, a locked screen or a quit during the wait cancel it.
- **A length for the Shortcuts action.** *Lock Keyboard for Cleaning* takes an optional **Minutes** value (1 to 60, anything else is pulled into that range), so a Shortcut can lock for exactly as long as it needs. Left empty it behaves as before and uses the timer from Settings. A length changes nothing about when the action locks at all: without the Accessibility permission, with secure input on, or with the mouse frozen it still opens the panel instead.
- **The screen stays awake while the keyboard is locked.** A lock lasts minutes now, and with nobody touching the Mac the screen saver or the display sleep would start, and a locked screen or a sleeping Mac ends the lock. dirtymac now asks macOS to keep the display on for the length of the lock (Settings → While locked → Keep the screen awake, on by default). It is released the moment the lock ends, and macOS drops it by itself if the app ever dies.
- **A counter in the menu bar while locked.** With the mouse frozen the panel cannot be opened, and the menu bar is the one thing still in view. Beside the icon it now shows the time left until the auto-unlock, or how long the keyboard has been locked when there is no timer. While Esc is held it counts "Esc 3", "Esc 2", "Esc 1", "Esc 0". The digits are of one width so the item does not jitter. The auto-unlock countdown in the panel is larger too.

### Changed
- Settings scroll when they would be taller than the screen leaves room for. With the update section and the new note they could otherwise run off the bottom of a small display.
- Closing the panel ends a lockdown confirmation that was left open, instead of leaving it waiting for the next click.

### Development
- Tests cover the rules (daily limit, 60-day steps, version parsing that refuses anything but a plain number), the request against a stand-in server (what is sent, what a bad reply does), races such as switching the setting off while a request is out, and a guard that fails when any source file other than `UpdateCheck.swift` touches the network.

## [1.3.2] - 2026-10-11

### Fixed
- People who updated straight from 1.1.x got no What's New window on 1.3.1, and with it missed the one-time offer to open dirtymac at login. The window looked for notes of exactly the running version, and a patch release has none. It now shows the newest notes up to the running version.

### Documentation
- README troubleshooting explains why `brew upgrade` can report the latest version as installed for up to a day after a release, and which command checks right away.

## [1.3.1] - 2026-10-11

### Fixed
- After an update dirtymac could ask for Accessibility again even though System Settings showed it switched on. Two causes are handled:
  - A copy left running while an update replaced it on disk (Homebrew did not quit dirtymac before upgrading until the 1.3.0 cask) can no longer pass macOS's signature checks. It now notices and restarts itself into the new version as soon as it is opened or its menu bar icon is clicked.
  - An Accessibility entry macOS no longer honours (left by another build) still shows as switched on but does nothing, and blocks the system prompt. Grant Access now removes it first, so the prompt and a working switch come back. The permission screens say so.

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

[Unreleased]: https://github.com/erenmalkoc/dirtymac/compare/v1.3.2...HEAD
[1.3.2]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.3.2
[1.3.1]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.3.1
[1.3.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.3.0
[1.2.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.2.0
[1.1.2]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.2
[1.1.1]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.1
[1.1.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.0
[1.0.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.0.0
