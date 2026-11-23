import AppKit

/// What the menu bar shows beside the icon while the keyboard is locked.
///
/// With the mouse frozen the panel cannot be opened, and the menu bar is
/// the one place that stays in view. It shows, most urgent first:
/// - the hold-Esc countdown while Esc is held (Esc 3, Esc 2, Esc 1, then Esc 0),
/// - otherwise the time left until the auto-unlock,
/// - otherwise, with no timer, how long the keyboard has been locked.
nonisolated enum LockStatusTitle {
    /// The key's own name: printed on the key in every language, so it needs no translation.
    static let escLabel = "Esc"

    static func text(
        isActive: Bool,
        escHold: EscHoldState,
        autoUnlockTotal: Int,
        elapsed: TimeInterval,
        pendingLockText: String? = nil
    ) -> String? {
        // The start delay is counting down: nothing is locked yet, and
        // this is the moment the user looks at the menu bar to see it.
        guard isActive else { return pendingLockText }
        switch escHold {
        case .holding(let remaining, _):
            return "\(escLabel) \(remaining)"
        case .letGo:
            return "\(escLabel) 0"
        case .idle:
            let seconds = autoUnlockTotal > 0
                ? max(0, autoUnlockTotal - Int(elapsed))
                : Int(elapsed)
            return clock(seconds)
        }
    }

    /// 05:07. Past an hour the minutes keep counting (75:10) so the width
    /// only ever grows by a digit.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Digits of one width, so the item does not jitter as they change.
    static func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ])
    }

    /// Puts `text` beside the icon, or takes it away again.
    @MainActor
    static func apply(_ text: String?, to button: NSButton) {
        if let text {
            button.attributedTitle = attributed(" " + text)
            button.imagePosition = .imageLeft
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        }
    }
}
