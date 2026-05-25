import SwiftUI
import AppKit

/// Renders the app's bundle icon at an arbitrary size. Used in the
/// popover header as the brand mark.
struct AppIconView: View {
    var size: CGFloat

    // Launch Services lookup is synchronous and traverses the bundle.
    // Cache once so every popover open doesn't pay that cost.
    static let bundleIcon: NSImage = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    var body: some View {
        Image(nsImage: Self.bundleIcon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// Large circular power control. Tinted red while the keyboard is
/// locked, with a subtle press-down scale for tactile feedback.
struct GlassPowerButton: View {
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(PowerButtonStyle(isActive: isActive))
        .animation(.easeInOut(duration: 0.25), value: isActive)
    }
}

private struct PowerButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 132, height: 132)
            .background {
                if isActive {
                    Circle().fill(Color.red.gradient)
                } else {
                    Circle().fill(.regularMaterial)
                }
            }
            .overlay(
                Circle().strokeBorder(
                    isActive ? Color.red.opacity(0.6) : Color.primary.opacity(0.08),
                    lineWidth: 0.5
                )
            )
            .shadow(
                color: isActive ? Color.red.opacity(0.35) : .black.opacity(0.06),
                radius: isActive ? 14 : 6,
                y: isActive ? 4 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(.circle)
    }
}

/// Compact status indicator placed inline in the header. The dot color
/// is the only signal of state; the elapsed timer is shown only when
/// the keyboard is locked.
struct StatusPill: View {
    var isActive: Bool
    var elapsed: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.red : Color.green)
                .frame(width: 7, height: 7)

            Text(isActive ? "Locked" : "Ready")
                .font(.caption)
                .foregroundStyle(.primary)

            if isActive {
                Text(elapsed)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
        // Lock to intrinsic size so the pill never compresses when the
        // adjacent header text expands (e.g. "Locked" → "Locked 00:12").
        .fixedSize()
    }
}
