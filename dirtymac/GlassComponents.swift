import SwiftUI
import AppKit

/// Renders the app's bundle icon at an arbitrary size. Used in the
/// popover header as the brand mark.
struct AppIconView: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// Large circular power control. Uses the native interactive Liquid
/// Glass effect — tint shifts to red while the keyboard is locked.
struct GlassPowerButton: View {
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(width: 132, height: 132)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular
                .tint(isActive ? .red : nil)
                .interactive(),
            in: .circle
        )
        .animation(.easeInOut(duration: 0.25), value: isActive)
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
        .glassEffect(in: .capsule)
        // Lock to intrinsic size so the pill never compresses when the
        // adjacent header text expands (e.g. "Locked" → "Locked 00:12").
        .fixedSize()
    }
}
