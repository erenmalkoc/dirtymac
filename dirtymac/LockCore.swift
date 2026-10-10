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
// then filter by subtype so other system events (e.g. power button,
// subtype 1) keep working — leaving the user a hardware emergency exit
// if anything goes wrong.
let kCGEventSystemDefined: UInt32 = 14
let kAuxControlButtonsSubtype: Int16 = 8

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
            // System-defined events: only swallow the aux-button subtype
            // (brightness, volume, media, F-key controls). Everything
            // else, like the power button, still reaches the system.
            if type.rawValue == kCGEventSystemDefined {
                return systemSubtype == kAuxControlButtonsSubtype ? .block : .pass
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
