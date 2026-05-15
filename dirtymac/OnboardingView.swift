import SwiftUI

/// First-launch guided setup. Three steps: welcome, Accessibility
/// permission (with live status), and a short how-to. Hosted in an
/// AppKit-managed window by AppDelegate.
struct OnboardingView: View {
    @EnvironmentObject private var blocker: KeyboardBlocker

    /// Called when the user finishes or skips. AppDelegate persists the
    /// "hasOnboarded" flag and closes the window.
    var onFinish: () -> Void

    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, permission, ready
    }

    // Re-check permission once a second while the permission step is
    // shown — the user grants it outside the app (system prompt or
    // System Settings), so we poll to reflect it live.
    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 36)
                .padding(.top, 44)

            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
        }
        .frame(width: 460, height: 560)
        .background(.background)
        .onReceive(pollTimer) { _ in
            if step == .permission { blocker.refreshPermission() }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:     welcomeStep
        case .permission:  permissionStep
        case .ready:       readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            AppIconView(size: 84)

            VStack(spacing: 8) {
                Text("Welcome to dirtymac")
                    .font(.title).fontWeight(.semibold)

                Text("A menu bar utility that locks your keyboard so you can clean it — without typing nonsense or launching apps.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("dirtymac lives in your menu bar, up here.", systemImage: "arrow.up.forward")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(in: .capsule)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Grant Accessibility Access")
                    .font(.title2).fontWeight(.semibold)

                Text("dirtymac needs Accessibility access to intercept keyboard events while you clean. Nothing is recorded, logged, or sent anywhere.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            statusRow
                .padding(.top, 2)

            HStack(spacing: 10) {
                Button("Grant Access") { blocker.requestPermission() }
                    .buttonStyle(.glassProminent)

                Button("Open Settings") { blocker.openAccessibilitySettings() }
                    .buttonStyle(.glass)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: blocker.hasPermission ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(blocker.hasPermission ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))

            Text(blocker.hasPermission
                 ? "Accessibility access granted"
                 : "Accessibility access not granted yet")
                .font(.callout)
                .foregroundStyle(blocker.hasPermission ? .primary : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(in: .capsule)
        .animation(.easeInOut(duration: 0.25), value: blocker.hasPermission)
    }

    private var readyStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            Text("You're all set")
                .font(.title2).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                tip("1", "menubar.rectangle", "Click the dirtymac icon in your menu bar.")
                tip("2", "power", "Press the power button to lock the keyboard.")
                tip("3", "cursorarrow.rays", "Mouse and trackpad keep working — click the icon again to unlock.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 16))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func tip(_ number: String, _ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 24, alignment: .center)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = Step(rawValue: step.rawValue - 1) ?? .welcome
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            Spacer()

            ProgressDots(count: Step.allCases.count, index: step.rawValue)

            Spacer()

            Button(primaryTitle) { advance() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case .welcome:    "Get Started"
        case .permission: blocker.hasPermission ? "Continue" : "Skip for Now"
        case .ready:      "Done"
        }
    }

    private func advance() {
        switch step {
        case .welcome:
            withAnimation(.easeInOut(duration: 0.2)) { step = .permission }
        case .permission:
            withAnimation(.easeInOut(duration: 0.2)) { step = .ready }
        case .ready:
            onFinish()
        }
    }
}

// MARK: - Progress Dots

private struct ProgressDots: View {
    var count: Int
    var index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: index)
            }
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environmentObject(KeyboardBlocker())
}
