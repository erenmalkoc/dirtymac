import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @EnvironmentObject private var blocker: KeyboardBlocker

    var body: some View {
        VStack(spacing: 16) {
            header

            if blocker.hasPermission {
                mainControl
            } else {
                permissionPrompt
            }

            footer
        }
        .padding(18)
        .frame(width: 290)
        .onAppear { blocker.refreshPermission() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Label("dirtymac", systemImage: "sparkles")
                .font(.headline)
                .labelStyle(.titleAndIcon)

            Spacer()

            StatusPill(isActive: blocker.isActive, elapsed: blocker.elapsedDisplay)
        }
    }

    // MARK: Main control

    private var mainControl: some View {
        VStack(spacing: 12) {
            GlassPowerButton(isActive: blocker.isActive) {
                blocker.toggle()
            }
            .padding(.top, 14)

            VStack(spacing: 2) {
                Text(blocker.isActive ? "Cleaning Mode" : "Tap to Lock Keyboard")
                    .font(.headline)

                Text(blocker.isActive
                     ? "Wipe away — your trackpad still works."
                     : "Mouse and trackpad stay enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Permission prompt

    private var permissionPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
                .padding(.top, 10)

            Text("Accessibility Required")
                .font(.headline)

            Text("dirtymac needs Accessibility access to intercept keyboard events.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            HStack(spacing: 8) {
                Button("Grant Access", systemImage: "checkmark.shield") {
                    blocker.requestPermission()
                }
                .buttonStyle(.glassProminent)

                Button("Open Settings", systemImage: "gear") {
                    blocker.openAccessibilitySettings()
                }
                .buttonStyle(.glass)
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise") {
                blocker.refreshPermission()
            }
            .buttonStyle(.glass)

            Spacer()

            Button("Quit", systemImage: "power", role: .destructive) {
                blocker.stop()
                NSApp.terminate(nil)
            }
            .buttonStyle(.glass)
        }
    }
}

#Preview {
    MenuBarPopoverView()
        .environmentObject(KeyboardBlocker())
}
