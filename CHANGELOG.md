# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.6] - 2026-11-24

### Added
- **Auto-unlock up to 24 hours, with a length or a time of your own.** The timer stopped at one hour. The list now goes 30 seconds, 1, 2, 5, 10, 15, 30 minutes, 1, 2, 4, 8, 12 and 24 hours, and **Custom…** opens a box with two choices: **For** (any number of hours and minutes, up to a day) and **Until** (a time of day, such as 23:30, which means the next 23:30). A line under it says when the lock will end ("Unlocks at 23:30", with the weekday when it is not today). It is the same setting in the panel and in Settings, Basic mode included. With the mouse frozen nothing changes: only 30 seconds to 15 minutes are offered, there is no box, and a length or time entered earlier is brought to the closest of them.
- **A confirmation before a lock longer than an hour.** It says how long the keyboard stays locked and the time it ends, how to unlock sooner (the menu bar icon or Esc held for 3 seconds), and warns that the lock ends early if the Mac goes to sleep or the screen locks, and that the screen stays on the whole time (and uses power) while Keep the screen awake is on. A Shortcut that locks without a length asks the same by opening the panel when the stored timer is over an hour. A length chosen from the **Lock for** menu or passed to Shortcuts is already the person's choice and starts at once.
- **The Lock for menu goes up to 8 hours** (2, 4 and 8 hours added), and the Shortcuts **Minutes** value up to 1440, a day.
- **Hours on the counters.** From an hour on the clock reads 1:15:10 instead of 75:10, in the panel, the status pill and beside the menu bar icon, whose reserved width follows.
- 11 new texts in all 17 languages.

### Changed
- **More trackpad gestures are switched off during a lock,** after users reported the screen still moving with some gestures: pinch, rotate, smart zoom (two-finger double tap), look up (three-finger tap) and swipe between pages (the app-wide setting), next to the swipes and pinches of 1.4.5. They are put back the same way, exactly as they were. Which gesture moved the screen was not reported, so this covers the ones left that can: if one still gets through, please say which.

## [1.4.5] - 2026-11-24

### Added
- **Three and four finger swipes are turned off while the keyboard is locked.** Mission Control, Spaces and App Exposé gestures are handled by macOS out of reach of every event tap (the event log shows them never arriving as events an app can stop), so a palm on the trackpad could still switch screens. The one lever an app has is the settings that turn them off. During a lock dirtymac switches off the trackpad gesture settings (for the built-in and a Bluetooth trackpad) and the Dock's gesture switches, and puts every value back exactly as it was when the lock ends, whichever way it ends. The values are written down before anything is changed, so if the app is killed or crashes mid-lock, the next launch puts them back. A setting that was not set before is removed again, not left at zero. The Dock restarts briefly at each end. Settings → While locked → **Turn off trackpad gestures**, on by default.
- **The Auto-unlock choice is in Settings in Basic mode too.** It sat under Advanced only, so Basic mode's own Settings had nowhere to say when the lock ends, although the panel already offered it. Switching to Advanced with the mouse freeze on pulls a length the freeze does not allow down to what it does.

### Changed
- The README and the changelog said the power (Touch ID) button is caught during a lock. The event log of a lock on macOS 27 shows that a press of it never reaches an app as an event: only other system events were counted, never the power button (type 1) or the sleep event (type 11). It is handled below anything an app can stop, so it cannot be blocked. The code still swallows those two event types if a Mac does deliver them.

## [1.4.4] - 2026-11-24

### Added
- **A nearly invisible shield over the screens while the keyboard is locked.** On macOS 27 the event log showed trackpad scrolling reaching apps without passing any event tap (neither the session tap nor the HID tap saw a single scroll event), so no tap could stop it. A scroll goes to the window under the cursor, so during a lock dirtymac now puts a window of its own over every screen, below the menu bar and above the Dock and all apps. Scrolling and clicks land on it and it does nothing with them. The menu bar icon and the panel sit above it and stay usable, Esc still unlocks, and the shield goes away with the lock, on every way a lock can end, and with the app if it ever dies. It follows screens that are plugged in or removed during a lock. It is used whenever **Ignore scrolling and clicks** is on, and with the mouse frozen. It cannot stop the three and four finger swipes that switch Spaces or open Mission Control, which macOS handles out of reach of any app. Not tried on a real scroll yet.
- The optional event log (`tapDiagnostics`) now names the kind of system-defined event it counted, such as `system-1` for the power button, so a press that gets through can be traced.

## [1.4.3] - 2026-11-24

### Added
- **Choose how long the lock lasts right on the panel.** Before locking, the panel shows an **Auto-unlock** menu (off, 30 seconds up to 1 hour) under the power button. Until now the timer lived in Settings and only in Advanced mode, so most people never found it and Basic mode could not lock for a set time at all. It is the same setting as in Settings. Basic mode now keeps the timer you chose (it is safe there because the mouse is free and a click on the icon always ends the lock). While the mouse is frozen the menu offers only what the lock will really use, 30 seconds to 15 minutes.

### Fixed
- **The panel's arrow points at the menu bar icon.** The panel centred its arrow on the whole menu bar button, which is wider than the icon whenever text sits beside it, so the arrow could land beside the icon and look like a bump on the panel's corner. It now points at the icon's own span.

## [1.4.2] - 2026-11-24

### Added
- **The pointer is also caught at the HID level.** On at least one Mac (macOS 27) scrolling and clicks still reached apps during a lock although the session event tap listed every pointer event, so the session tap alone was not enough. Pointer events are now tapped a second time at the HID level, before the session in the input path, with the same guard (clicks on dirtymac's own windows still go through). If macOS refuses that second tap the lock carries on with the session tap alone.
- **An optional event log for finding such problems.** `defaults write tech.erenium.dirtymac tapDiagnostics -bool true` makes a lock write, once a second, how many events of each kind each tap saw and whether they were blocked or passed (for example `scroll blocked 12`). Counts only: nothing that was typed or where anything was clicked. Off unless asked for. Read it with `/usr/bin/log show --last 5m --predicate 'subsystem == "tech.erenium.dirtymac"'`.

### Fixed
- **The panel no longer slides sideways while the keyboard is locked.** The menu bar item changed its width with the text beside the icon (the start delay, the clock, the hold-Esc countdown), and the open panel, which hangs from the item, followed it. The item now keeps one width for as long as the lock or its start delay runs, wide enough for the longest text in every language, and the icon stays at its left edge. The width goes back to the icon's own once the lock is over, and not while the panel is open.

## [1.4.1] - 2026-11-23

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

[Unreleased]: https://github.com/erenmalkoc/dirtymac/compare/v1.4.6...HEAD
[1.4.6]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.4.6
[1.4.5]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.4.5
[1.4.4]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.4.4
[1.4.3]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.4.3
[1.4.2]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.4.2
[1.4.1]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.4.1
[1.4.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.4.0
[1.3.2]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.3.2
[1.3.1]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.3.1
[1.3.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.3.0
[1.2.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.2.0
[1.1.2]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.2
[1.1.1]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.1
[1.1.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.1.0
[1.0.0]: https://github.com/erenmalkoc/dirtymac/releases/tag/v1.0.0
