import SwiftUI

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

/// Compact status indicator placed inline in the header. Uses native
/// glass; the dot color is the only signal of state.
struct StatusPill: View {
    var isActive: Bool
    var elapsed: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.red : Color.green)
                .frame(width: 7, height: 7)

            Text(isActive ? "Locked" : "Active")
                .font(.callout)
                .foregroundStyle(.primary)

            if isActive {
                Text(elapsed)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(in: .capsule)
    }
}
