import AppKit

/// Short system sounds that carry the lock's state when nobody looks at
/// the screen — while cleaning, eyes are on the keys. Sparse on purpose:
/// never one per keystroke.
enum SoundCue: CaseIterable {
    /// The lock started.
    case locked
    /// A second of the Esc hold passed, or the auto-unlock is near.
    case tick
    /// The keyboard is free, or will be as soon as Esc comes up.
    case unlocked
    /// Keys are getting past the lock (another app holds secure input).
    case warning

    /// System sound names, preferred first.
    var soundNames: [String] {
        switch self {
        case .locked: ["Pop", "Bottle"]
        case .tick: ["Tink", "Morse"]
        case .unlocked: ["Glass", "Hero"]
        case .warning: ["Funk", "Basso"]
        }
    }
}

/// When the lock plays which cue.
enum SoundSchedule {
    /// Seconds into an Esc hold that tick, so the user hears it counting.
    static func escHoldTicks(holdDuration: TimeInterval) -> [TimeInterval] {
        Array(stride(from: 1, to: holdDuration, by: 1))
    }

    /// The last three seconds before an auto-unlock tick, so a cloth
    /// resting on the keys is lifted in time. Short timers stay quiet.
    static func countdownTicks(remaining: Int, total: Int) -> Bool {
        total >= 10 && (1...3).contains(remaining)
    }

    /// The cue for a lock that ended, if any. A click or quit needs none
    /// (the user is looking at the panel), the hold-Esc exit already
    /// chimed when the hold completed, and nobody is at a Mac that slept.
    static func cue(for reason: UnlockReason) -> SoundCue? {
        switch reason {
        case .autoUnlock:
            return .unlocked
        case .secureInput:
            return .warning
        case .clicked, .escHeld, .quit, .systemSleep, .screenLocked, .userSwitched,
             .systemSettings, .permissionRevoked:
            return nil
        }
    }
}

protocol SoundPlaying {
    func play(_ cue: SoundCue)
}

/// Plays cues with NSSound, following the "Play sounds" setting and the
/// system output volume.
final class SystemSounds: SoundPlaying {
    static let enabledKey = "playSounds"

    private let defaults: UserDefaults
    private var cache: [SoundCue: NSSound] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On unless the user turned it off.
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    func play(_ cue: SoundCue) {
        guard Self.isEnabled(in: defaults), let sound = sound(for: cue) else { return }
        sound.stop()   // restart rather than overlap
        sound.play()
    }

    func sound(for cue: SoundCue) -> NSSound? {
        if let cached = cache[cue] { return cached }
        let sound = cue.soundNames.lazy.compactMap { NSSound(named: NSSound.Name($0)) }.first
        cache[cue] = sound
        return sound
    }
}
