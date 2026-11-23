import SwiftUI
import AppKit
import Combine

/// The default popover content — keyboard lock control. The settings
/// view replaces this within the same popover when the user opens
/// preferences.
struct MainView: View {
    @EnvironmentObject private var blocker: KeyboardBlocker
    @EnvironmentObject private var updates: UpdateChecker
    @Binding var showingSettings: Bool
    @State private var confirmLockdown: Bool
    /// The proof that Esc works, asked for before a long frozen-mouse lock.
    @StateObject private var escCheck = EscCheckModel()
    @Environment(\.locale) private var locale
    private let configurationOverride: LockConfiguration?

    /// `confirming` and `configuration` exist so the confirmation can be
    /// built in a test. The app uses the defaults: not confirming, and the
    /// stored settings.
    init(showingSettings: Binding<Bool>, confirming: Bool = false, configuration: LockConfiguration? = nil) {
        _showingSettings = showingSettings
        _confirmLockdown = State(initialValue: confirming)
        configurationOverride = configuration
    }

    private var lockConfiguration: LockConfiguration { configurationOverride ?? .current }

    // Secure input comes and goes with other apps, so re-check it every
    // second while the panel is open. During a lock the blocker does.
    private let secureInputPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            // Not while the keyboard is locked: that screen is for one thing.
            if !blocker.isActive {
                UpdateNoticeView(openSettings: { showingSettings = true })
            }

            content
                .padding(.vertical, 22)
                .padding(.horizontal, 18)
                .animation(.easeInOut(duration: 0.2), value: confirmLockdown)

            Divider()

            footer
        }
        // Defer the AX check so it doesn't block the popover's first
        // frame. The cached value from init renders immediately; if it
        // turns out stale, the view updates a tick later.
        .onAppear {
            // The app may have run for weeks: a reminder can have come due.
            updates.refreshReminder()
            DispatchQueue.main.async {
                blocker.refreshPermission()
                if !blocker.isActive { blocker.refreshSecureInput() }
            }
            syncEscCheck()
        }
        .onChange(of: confirmLockdown) { _, _ in syncEscCheck() }
        // Closing the panel ends a confirmation that was left open: it must
        // not wait there, with a stale pass, for the next click.
        .onReceive(NotificationCenter.default.publisher(for: .panelDidClose)) { _ in
            confirmLockdown = false
            escCheck.stop()
            escCheck.reset()
        }
        .onDisappear { escCheck.stop() }
        .onReceive(secureInputPoll) { _ in
            if !blocker.isActive { blocker.refreshSecureInput() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("dirtymac")
                    .font(.headline)
                    .lineLimit(1)
                Text("Keyboard utility")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            StatusPill(isActive: blocker.isActive, elapsed: blocker.elapsedDisplay)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if Self.showsLockControl(isActive: blocker.isActive, hasPermission: blocker.hasPermission) {
            mainControl
        } else {
            permissionPrompt
        }
    }

    /// A running lock always keeps its stop control, even if the
    /// permission was revoked meanwhile: stopping needs no permission.
    static func showsLockControl(isActive: Bool, hasPermission: Bool) -> Bool {
        isActive || hasPermission
    }

    @ViewBuilder
    private var mainControl: some View {
        if confirmLockdown {
            lockdownConfirm
        } else {
            lockControl
        }
    }

    private var lockControl: some View {
        VStack(spacing: 16) {
            GlassPowerButton(isActive: blocker.isActive) {
                handlePowerTap()
            }

            VStack(spacing: 5) {
                Text(blocker.isActive ? "Cleaning Mode Active" : "Click to Lock Keyboard")
                    .font(.headline)

                if blocker.isActive {
                    if blocker.hasAutoUnlock {
                        Label("Unlocks in \(blocker.autoUnlockRemainingDisplay)",
                              systemImage: "timer")
                            .font(.title3.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    if blocker.secureInput != nil {
                        // Esc can't reach the tap either; don't promise it.
                        secureInputWarning
                    } else {
                        escHoldHint
                    }
                } else {
                    Text(idleCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    secureInputWarning
                        .padding(.top, 4)

                    if let explanation = blocker.lastUnlockReason?.explanation {
                        Label(explanation, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The way out, and while Esc is held how long is left. The space is
    /// the same in every state, so the panel does not jump as the hold runs.
    private var escHoldHint: some View {
        VStack(spacing: 6) {
            ProgressView(value: escHoldProgress)
                .progressViewStyle(.linear)
                .opacity(escHoldIsRunning ? 1 : 0)
                .accessibilityHidden(!escHoldIsRunning)
            Group {
                switch blocker.escHold {
                case .idle:
                    Text("Hold Esc for 3 seconds to unlock.")
                case .holding(let remaining, _):
                    Text("Unlocking in \(remaining)…")
                        .monospacedDigit()
                case .letGo:
                    Text("Let go of Esc.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 32, alignment: .top)
        }
        .padding(.horizontal, 24)
    }

    private var escHoldIsRunning: Bool {
        if case .idle = blocker.escHold { return false }
        return true
    }

    private var escHoldProgress: Double {
        switch blocker.escHold {
        case .idle: return 0
        case .holding(_, let progress): return progress
        case .letGo: return 1
        }
    }

    // Inline confirmation. A system .confirmationDialog can't be used
    // here: presenting it makes the MenuBarExtra popover resign key and
    // close, tearing the dialog down before its action runs. Keeping the
    // confirmation inside the popover avoids the focus loss entirely.
    private var lockdownConfirm: some View {
        let effective = lockConfiguration.effective
        return VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("Full Lockdown")
                    .font(.headline)
                Text("Your mouse and trackpad will be frozen too. To unlock: hold Esc for 3 seconds, or wait for the auto-unlock timer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // How long, spelled out, so nobody locks for an hour by accident.
                Text("The keyboard stays locked for \(LockConfiguration.unlockChoiceTitle(effective.autoUnlockSeconds, locale: locale)) unless you unlock it sooner.")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if effective.requiresEscCheck {
                escCheckRow
            }

            // Full lockdown can't start while secure input is on: hold-Esc
            // would not get through, leaving only the timer as a way out.
            secureInputWarning

            HStack(spacing: 8) {
                Button("Cancel") { confirmLockdown = false }
                    .buttonStyle(.bordered)

                Button("Lock Keyboard", role: .destructive) {
                    confirmLockdown = false
                    // Passed along, not assumed: the blocker refuses a long
                    // frozen-mouse lock that was not checked.
                    blocker.start(escVerified: escCheck.passed)
                }
                .buttonStyle(.borderedProminent)
                .disabled(Self.lockButtonDisabled(
                    secureInputOn: blocker.secureInput != nil,
                    requiresEscCheck: effective.requiresEscCheck,
                    escPassed: escCheck.passed
                ))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    /// The bar fills while Esc is held, then says it works.
    @ViewBuilder
    private var escCheckRow: some View {
        VStack(spacing: 6) {
            if escCheck.passed {
                Label("Esc works. You can lock now.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                ProgressView(value: escCheck.progress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Hold Esc for 3 seconds to check that your way out works.")
                Text("Hold Esc for 3 seconds to check that your way out works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
    }

    /// Keys get past the tap while another app holds secure input.
    @ViewBuilder
    private var secureInputWarning: some View {
        if let status = blocker.secureInput {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    if let name = status.ownerName {
                        Text("\(name) is using secure input, so macOS won't let dirtymac block keys.")
                    } else {
                        Text("Another app is using secure input, so macOS won't let dirtymac block keys.")
                    }
                    Text("Quit that app, or lock and unlock your screen, to clear it.")
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var idleCaption: LocalizedStringKey {
        lockConfiguration.blockMouseAndTrackpad
            ? "Mouse and trackpad will be frozen too."
            : "Mouse and trackpad stay enabled."
    }

    /// The check listens while, and only while, a long lock is being confirmed.
    private func syncEscCheck() {
        if Self.escCheckShouldListen(confirming: confirmLockdown, configuration: lockConfiguration) {
            if !escCheck.isListening { escCheck.start() }
        } else {
            escCheck.stop()
            escCheck.reset()
        }
    }

    static func escCheckShouldListen(confirming: Bool, configuration: LockConfiguration) -> Bool {
        confirming && configuration.effective.requiresEscCheck
    }

    /// The Lock button waits for the secure-input warning to clear and, for
    /// a long frozen-mouse lock, for the Esc check.
    static func lockButtonDisabled(secureInputOn: Bool, requiresEscCheck: Bool, escPassed: Bool) -> Bool {
        secureInputOn || (requiresEscCheck && !escPassed)
    }

    private func handlePowerTap() {
        if blocker.isActive {
            blocker.stop(reason: .clicked)
        } else if lockConfiguration.blockMouseAndTrackpad {
            confirmLockdown = true
        } else {
            blocker.start()
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Accessibility Access Required")
                    .font(.headline)

                Text("dirtymac needs permission to intercept keyboard events while you clean.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Grant Access") {
                    blocker.requestPermission()
                }
                .buttonStyle(.borderedProminent)

                Button("Open Settings") {
                    blocker.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 2)

            Text("Already switched on in System Settings? Grant Access removes the old entry so you can switch it on again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Settings")

            Text(versionString)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer()

            Button("Quit", role: .destructive) {
                blocker.stop(reason: .quit)
                NSApp.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(short)"
    }
}

extension UnlockReason {
    /// Locks the system ended, rather than the user, are explained in
    /// the panel until the next lock.
    var explanation: LocalizedStringKey? {
        switch self {
        case .systemSleep:
            return "The keyboard unlocked when your Mac went to sleep."
        case .screenLocked, .userSwitched:
            return "The keyboard unlocked when your screen was locked."
        case .systemSettings:
            return "The keyboard unlocked because System Settings opened."
        case .permissionRevoked:
            return "The keyboard unlocked because Accessibility access was turned off."
        case .secureInput:
            return "The keyboard unlocked because another app turned on secure input."
        case .clicked, .escHeld, .autoUnlock, .quit:
            return nil
        }
    }
}
