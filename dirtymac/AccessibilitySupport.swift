import AppKit
import Combine
import SwiftUI

// MARK: - Reduce Motion

/// What moves, and what stands still when "Reduce motion" is on in System
/// Settings → Accessibility → Display. Decisions live here so they are
/// tested; the views and the menu bar icon only ask.
nonisolated enum MotionPolicy {
    /// An animation, or none when motion is reduced.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// The menu bar icon's slow fade while locked.
    static func iconBreathes(isLocked: Bool, reduceMotion: Bool) -> Bool {
        isLocked && !reduceMotion
    }

    /// A slide between two screens becomes a plain fade.
    static func slide(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    /// Digits that roll to the next value become digits that just change.
    static func numberTransition(reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .identity : .numericText()
    }

    /// Reads the system setting.
    @MainActor
    static var systemReducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - VoiceOver

/// What VoiceOver is told about the lock. The panel and the menu bar are
/// visual: someone who cannot see them still needs to know the lock began,
/// how long Esc has still to be held, and that it ended.
enum StatusAnnouncement: Equatable {
    case waitingToLock(seconds: Int)
    case locked
    case unlocked
    case escHold(remaining: Int)
    case letGoOfEsc
    case autoUnlockIn(seconds: Int)
}

/// The values the announcements are worked out from.
struct StatusSnapshot: Equatable {
    var isActive = false
    var escHold: EscHoldState = .idle
    var lockCountdown: Int?
    /// Seconds to the auto-unlock, nil without a timer or without a lock.
    var autoUnlockRemaining: Int?
}

nonisolated enum StatusAnnouncements {
    /// Said once each, on the way down: a minute and ten seconds before
    /// the auto-unlock. Every second would be a stream of noise.
    static let autoUnlockMilestones = [60, 10]

    /// What changed between two snapshots worth saying, in order.
    static func changes(from old: StatusSnapshot, to new: StatusSnapshot) -> [StatusAnnouncement] {
        var said: [StatusAnnouncement] = []

        if let seconds = new.lockCountdown, seconds != old.lockCountdown {
            said.append(.waitingToLock(seconds: seconds))
        }
        if !old.isActive && new.isActive { said.append(.locked) }
        if old.isActive && !new.isActive { said.append(.unlocked) }

        switch new.escHold {
        case .holding(let remaining, _):
            if case .holding(let before, _) = old.escHold, before == remaining { break }
            said.append(.escHold(remaining: remaining))
        case .letGo:
            if old.escHold != .letGo { said.append(.letGoOfEsc) }
        case .idle:
            break
        }

        if new.isActive, let left = new.autoUnlockRemaining, left != old.autoUnlockRemaining,
           autoUnlockMilestones.contains(left) {
            said.append(.autoUnlockIn(seconds: left))
        }
        return said
    }
}

/// Where the words go.
protocol Announcing: AnyObject {
    func announce(_ text: String)
}

/// Speaks through VoiceOver.
final class VoiceOverAnnouncer: Announcing {
    func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

/// Watches the blocker and announces what changed, only while VoiceOver
/// (or whatever `isEnabled` stands for) is on.
@MainActor
final class StatusAnnouncer {
    private var last = StatusSnapshot()
    private var subscription: AnyCancellable?
    private let announcer: Announcing
    private let isEnabled: () -> Bool
    private let words: (StatusAnnouncement) -> String

    init(
        blocker: KeyboardBlocker,
        announcer: Announcing,
        isEnabled: @escaping () -> Bool,
        words: @escaping (StatusAnnouncement) -> String
    ) {
        self.announcer = announcer
        self.isEnabled = isEnabled
        self.words = words
        // Built from the values the publishers hand over: a @Published
        // property still holds its old value while its subscribers run.
        subscription = Publishers.CombineLatest(
            Publishers.CombineLatest4(
                blocker.$isActive, blocker.$escHold, blocker.$lockCountdown, blocker.$elapsed
            ),
            blocker.$autoUnlockTotal
        )
        .sink { [weak self] state, total in
            let (active, escHold, countdown, elapsed) = state
            self?.update(StatusSnapshot(
                isActive: active,
                escHold: escHold,
                lockCountdown: countdown,
                autoUnlockRemaining: active && total > 0 ? max(0, total - Int(elapsed)) : nil
            ))
        }
    }

    private func update(_ snapshot: StatusSnapshot) {
        defer { last = snapshot }
        guard isEnabled() else { return }
        for change in StatusAnnouncements.changes(from: last, to: snapshot) {
            announcer.announce(words(change))
        }
    }
}

extension StatusAnnouncement {
    /// The sentence, in the language of `bundle`.
    @MainActor
    func text(bundle: Bundle) -> String {
        switch self {
        case .waitingToLock(let seconds):
            return String(localized: "Locking in \(seconds)…", bundle: bundle)
        case .locked:
            return String(localized: "dirtymac — keyboard locked", bundle: bundle)
        case .unlocked:
            return String(localized: "Keyboard unlocked", bundle: bundle)
        case .escHold(let remaining):
            return String(localized: "Unlocking in \(remaining)…", bundle: bundle)
        case .letGoOfEsc:
            return String(localized: "Let go of Esc.", bundle: bundle)
        case .autoUnlockIn(let seconds):
            return String(localized: "Unlocks in \(LockStatusTitle.clock(seconds))", bundle: bundle)
        }
    }
}
