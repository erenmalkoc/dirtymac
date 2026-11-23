import AppKit
import CoreGraphics

// The rules of the lock, kept free of side effects so every one of them
// can be unit-tested without a real event tap (which needs an
// Accessibility permission that CI cannot grant).

// macOS routes media / brightness / volume / function-key controls
// through a separate event channel: `kCGEventSystemDefined` (raw 14)
// with the aux-buttons subtype (NX_SUBTYPE_AUX_CONTROL_BUTTONS = 8).
// They do NOT arrive as keyDown / keyUp, so a plain keyboard tap
// lets them through. We add the system-defined type to the mask and
// then filter by subtype. The power button (subtype 1) and the sleep
// event (11) are swallowed as well, so a short press during a lock does
// not put the Mac to sleep and end the lock. Whether macOS routes the
// press through this channel on a given Mac is not guaranteed, so this is
// best effort: the long press that shuts the Mac down is hardware and is
// never touched, and restart / shutdown requests (12, 13) pass too, so
// there is always a way out.
let kCGEventSystemDefined: UInt32 = 14
let kAuxControlButtonsSubtype: Int16 = 8
let kPowerKeySubtype: Int16 = 1
let kSleepEventSubtype: Int16 = 11

/// The system-defined subtypes a lock swallows.
let blockedSystemSubtypes: Set<Int16> = [kAuxControlButtonsSubtype, kPowerKeySubtype, kSleepEventSubtype]

// Escape key. Holding it force-unlocks — the universal emergency exit,
// available in every mode and essential when the mouse is part of the
// lockdown (the menu bar is unreachable then).
let kEscapeKeyCode: Int64 = 53

/// Which event types the tap intercepts for a lock configuration.
enum EventMask {
    static let pointerTypes: [CGEventType] = [
        .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .mouseMoved, .scrollWheel,
    ]

    /// Trackpad gestures (pinch, rotate, smart zoom, swipe) arrive as
    /// NSEvent type 29, which has no CGEventType case of its own.
    static let gestureBit = CGEventMask(NSEvent.EventTypeMask.gesture.rawValue)

    /// What the pointer guard intercepts: everything of `pointerTypes`
    /// except plain movement, so the cursor still moves and can reach the
    /// menu bar icon.
    static let guardedPointerTypes: [CGEventType] = pointerTypes.filter { $0 != .mouseMoved }

    /// Every pointer type but gestures, which only exist after the HID
    /// level and so are tapped at the session level alone.
    static let pointerMask: CGEventMask = pointerTypes.reduce(0) { $0 | bit($1) }

    /// Raw event type of trackpad gestures (NSEvent.EventType.gesture).
    static let gestureEventType: UInt32 = 29

    /// Whether the pointer guard decides this type.
    static func isGuarded(_ type: CGEventType) -> Bool {
        guardedPointerTypes.contains(type) || type.rawValue == gestureEventType
    }

    static func bit(_ type: CGEventType) -> CGEventMask {
        CGEventMask(1) << type.rawValue
    }

    /// keyDown and keyUp are always present; the rest follows the
    /// (already effective) configuration.
    static func build(for config: LockConfiguration) -> CGEventMask {
        var mask = bit(.keyDown) | bit(.keyUp)
        if config.blockModifierKeys {
            mask |= bit(.flagsChanged)
        }
        if config.blockMediaKeys {
            mask |= CGEventMask(1) << kCGEventSystemDefined
        }
        if config.blockMouseAndTrackpad {
            for type in pointerTypes { mask |= bit(type) }
            mask |= gestureBit
        } else if config.guardPointer {
            for type in guardedPointerTypes { mask |= bit(type) }
            mask |= gestureBit
        }
        return mask
    }
}

/// What the tap does with one intercepted event.
enum TapEventDecision: Equatable {
    /// Let it through.
    case pass
    /// Swallow it.
    case block
    /// Swallow it; Esc went down (or auto-repeated) — hold-Esc input.
    case escDown
    /// Swallow it; Esc came up — hold-Esc input.
    case escUp
    /// macOS disabled the tap (timeout or user input); turn it back on.
    case reEnable

    /// `keyCode` is only read for key events and `systemSubtype` only
    /// for system-defined ones, so callers may pass anything otherwise.
    static func decide(type: CGEventType, keyCode: Int64, systemSubtype: Int16?) -> TapEventDecision {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .reEnable
        case .keyDown where keyCode == kEscapeKeyCode:
            return .escDown
        case .keyUp where keyCode == kEscapeKeyCode:
            return .escUp
        default:
            // System-defined events: swallow the aux-button subtype
            // (brightness, volume, media, F-key controls) and the power
            // and sleep presses. Everything else still reaches the system.
            if type.rawValue == kCGEventSystemDefined {
                guard let systemSubtype else { return .pass }
                return blockedSystemSubtypes.contains(systemSubtype) ? .block : .pass
            }
            // Everything else in the mask is meant to be blocked.
            return .block
        }
    }

    /// Reads the fields `decide` needs from a real event.
    static func decide(type: CGEventType, event: CGEvent) -> TapEventDecision {
        let isKey = type == .keyDown || type == .keyUp
        let keyCode = isKey ? event.getIntegerValueField(.keyboardEventKeycode) : -1
        let subtype = type.rawValue == kCGEventSystemDefined
            ? NSEvent(cgEvent: event)?.subtype.rawValue
            : nil
        return decide(type: type, keyCode: keyCode, systemSubtype: subtype)
    }
}

/// The guard that keeps stray touches off a locked Mac: while the
/// keyboard is locked, scrolling, gestures and clicks go nowhere, except
/// clicks on dirtymac's own windows (its menu bar icon, its panel and
/// menus), which stay usable so the lock can always be ended. Moving the
/// cursor stays free.
///
/// A press that was let through is followed through to its release and
/// the drags in between, and a blocked press is blocked to its release, so
/// no app ever sees half a click.
struct PointerGuard: Equatable {
    /// The mouse buttons whose current press was let through.
    private var passing: Set<Button> = []

    enum Button: Hashable {
        case left, right, other
    }

    private static func button(of type: CGEventType) -> Button? {
        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: return .other
        default: return nil
        }
    }

    /// `overOwnWindow` is only asked for when a button goes down.
    mutating func decide(type: CGEventType, overOwnWindow: () -> Bool) -> TapEventDecision {
        guard let button = Self.button(of: type) else {
            // Scrolling, gestures and anything else of the guarded set.
            return .block
        }
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if overOwnWindow() {
                passing.insert(button)
                return .pass
            }
            passing.remove(button)
            return .block
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return passing.remove(button) != nil ? .pass : .block
        default:
            return passing.contains(button) ? .pass : .block
        }
    }

    /// Forgets every press, for a tap that was switched off and on again.
    mutating func reset() {
        passing.removeAll()
    }
}

/// A count of what a tap saw, for the diagnostics log: how many events of
/// each kind were swallowed and how many passed. Nothing about the events
/// themselves is kept.
struct TapTally: Equatable {
    /// `defaults write tech.erenium.dirtymac tapDiagnostics -bool true`
    /// switches the log on. Off unless asked for.
    static let defaultsKey = "tapDiagnostics"

    private var counts: [String: Int] = [:]

    var isEmpty: Bool { counts.isEmpty }

    mutating func record(_ kind: String, swallowed: Bool) {
        counts["\(kind) \(swallowed ? "blocked" : "passed")", default: 0] += 1
    }

    /// "scroll blocked 12, down passed 1", sorted, or nil when nothing was
    /// seen. Starts a new count.
    mutating func flush() -> String? {
        guard !counts.isEmpty else { return nil }
        let text = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        counts.removeAll()
        return text
    }

    static func kind(of type: CGEventType) -> String {
        switch type {
        case .scrollWheel: return "scroll"
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: return "down"
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: return "up"
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: return "drag"
        case .mouseMoved: return "moved"
        case .keyDown, .keyUp: return "key"
        case .flagsChanged: return "modifier"
        case .tapDisabledByTimeout, .tapDisabledByUserInput: return "tap-disabled"
        default:
            switch type.rawValue {
            case EventMask.gestureEventType: return "gesture"
            case kCGEventSystemDefined: return "system"
            default: return "other-\(type.rawValue)"
            }
        }
    }
}
