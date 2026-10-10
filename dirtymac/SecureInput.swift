import AppKit
import Carbon.HIToolbox
import IOKit

// Secure Event Input: while any process holds it — a focused password
// field, Terminal's Secure Keyboard Entry — macOS delivers keystrokes
// past every event tap. dirtymac then cannot block keys, and hold-Esc
// cannot reach it either. Detecting it is the only way to be honest
// about that.

protocol SecureInputDetecting {
    var isEnabled: Bool { get }
    /// The app holding secure input, when macOS tells (best effort).
    func ownerName() -> String?
}

struct SystemSecureInput: SecureInputDetecting {
    var isEnabled: Bool { IsSecureEventInputEnabled() }

    func ownerName() -> String? {
        guard let pid = SecureInputOwner.pid(in: Self.consoleUsers(), userID: getuid()),
              let app = NSRunningApplication(processIdentifier: pid),
              // loginwindow and background helpers have no name worth showing.
              app.activationPolicy == .regular
        else { return nil }
        return app.localizedName
    }

    /// IOConsoleUsers lists the login sessions; its undocumented
    /// kCGSSessionSecureInputPID names the process holding secure input.
    static func consoleUsers() -> [[String: Any]] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(
            root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return [] }
        return value as? [[String: Any]] ?? []
    }
}

enum SecureInputOwner {
    /// The process holding secure input in the session of `userID`.
    static func pid(in consoleUsers: [[String: Any]], userID: uid_t) -> pid_t? {
        for session in consoleUsers {
            guard (session["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == userID else { continue }
            if let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 {
                return pid
            }
        }
        return nil
    }
}

/// What a lock does about secure input.
enum SecureInputPolicy {
    /// A field focused for a moment is no reason to act: secure input has
    /// to still be on at this many one-second checks in a row.
    static let readingsToAct = 2

    enum Action: Equatable {
        /// Nothing to do.
        case none
        /// Keys are getting through right now. Keep the lock — blocking
        /// resumes by itself once secure input clears — and say so.
        case warn
        /// End the lock: in full lockdown the mouse is frozen and hold-Esc
        /// cannot get through either, so only the timer would be left.
        case release
    }

    static func duringLock(readings: Int, mouseLocked: Bool) -> Action {
        guard readings >= readingsToAct else { return .none }
        return mouseLocked ? .release : .warn
    }

    /// Full lockdown does not start while secure input is on: its
    /// emergency exit would not work.
    static func canStart(secureInputOn: Bool, mouseLocked: Bool) -> Bool {
        !(secureInputOn && mouseLocked)
    }
}

/// Shown in the panel while another app holds secure input.
struct SecureInputStatus: Equatable {
    var ownerName: String?
}
