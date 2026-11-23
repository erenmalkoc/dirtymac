import AppKit

/// Where the panel's arrow points. The panel centres its arrow on the
/// rectangle it is shown from, and the whole menu bar button is wider than
/// the icon whenever text sits beside it (or the width is reserved for it),
/// so pointing at the button put the arrow beside the icon. This is the
/// icon's own span, at the full height of the button.
nonisolated enum StatusItemAnchor {
    /// `imageRect` is where the button draws its image. Without a usable
    /// one (empty, or outside the button) the whole button is the target.
    static func rect(buttonBounds bounds: NSRect, imageRect: NSRect) -> NSRect {
        guard !imageRect.isEmpty, imageRect.width.isFinite,
              imageRect.minX >= bounds.minX - 0.5, imageRect.maxX <= bounds.maxX + 0.5
        else { return bounds }
        return NSRect(x: imageRect.minX, y: bounds.minY, width: imageRect.width, height: bounds.height)
    }

    @MainActor
    static func rect(for button: NSButton) -> NSRect {
        rect(buttonBounds: button.bounds, imageRect: button.cell?.imageRect(forBounds: button.bounds) ?? .zero)
    }
}

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

    /// The longest things the title can say while a lock runs: the start
    /// delay's wording with its widest number, the clock (one digit more
    /// without a timer, which counts up) and the hold-Esc countdown. The
    /// menu bar item is made this wide and kept so, because an item that
    /// changes width moves the panel that hangs from it.
    static func widestTexts(autoUnlockTotal: Int, pendingText: (Int) -> String) -> [String] {
        [
            pendingText(10),
            autoUnlockTotal > 0 ? "88:88" : "888:88",
            "\(escLabel) 3",
        ]
    }

    /// The width a button needs for the widest of `texts` beside its icon.
    /// Leaves the button showing the last of them: apply the real title after.
    @MainActor
    static func reservedWidth(for button: NSButton, texts: [String]) -> CGFloat {
        var widest: CGFloat = 0
        for text in texts {
            apply(text, to: button)
            widest = max(widest, button.fittingSize.width)
        }
        return widest.rounded(.up)
    }

    /// Puts `text` beside the icon, or takes it away again.
    @MainActor
    static func apply(_ text: String?, to button: NSButton) {
        if let text {
            button.attributedTitle = attributed(" " + text)
            button.imagePosition = .imageLeft
            // Packed to the left so the icon stays where it is however
            // wide the text is.
            button.alignment = .left
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        }
    }
}
