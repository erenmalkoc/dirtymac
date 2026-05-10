import SwiftUI
import AppKit

/// The default popover content — keyboard lock control. The settings
/// view replaces this within the same popover when the user opens
/// preferences.
struct MainView: View {
    @EnvironmentObject private var blocker: KeyboardBlocker
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
                .padding(.vertical, 22)
                .padding(.horizontal, 18)

            Divider()

            footer
        }
        .onAppear { blocker.refreshPermission() }
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
        if blocker.hasPermission {
            mainControl
        } else {
            permissionPrompt
        }
    }

    private var mainControl: some View {
        VStack(spacing: 16) {
            GlassPowerButton(isActive: blocker.isActive) {
                blocker.toggle()
            }

            VStack(spacing: 3) {
                Text(blocker.isActive ? "Cleaning Mode Active" : "Click to Lock Keyboard")
                    .font(.headline)

                Text(blocker.isActive
                     ? "Click the button to release."
                     : "Mouse and trackpad stay enabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
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
                .buttonStyle(.glassProminent)

                Button("Open Settings") {
                    blocker.openAccessibilitySettings()
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 2)
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
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel("Settings")

            Text(versionString)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer()

            Button("Quit", role: .destructive) {
                blocker.stop()
                NSApp.terminate(nil)
            }
            .buttonStyle(.glass)
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
