import Carbon.HIToolbox
import SwiftUI

/// The system-wide shortcut that opens dirtymac from anywhere. A fixed
/// set of presets instead of a free-form recorder: every preset uses
/// three modifiers so it never steals a shortcut another app relies on,
/// and the Carbon hot-key API needs no Accessibility permission.
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case off
    case ctrlOptCmdK
    case ctrlOptCmdD
    case optShiftCmdK

    static let defaultsKey = "globalHotKey"
    static let defaultValue: HotKeyPreset = .ctrlOptCmdK

    var id: Self { self }

    /// Virtual key code + Carbon modifier mask, nil when off.
    var binding: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .off:          nil
        case .ctrlOptCmdK:  (UInt32(kVK_ANSI_K), UInt32(controlKey | optionKey | cmdKey))
        case .ctrlOptCmdD:  (UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey))
        case .optShiftCmdK: (UInt32(kVK_ANSI_K), UInt32(optionKey | shiftKey | cmdKey))
        }
    }

    /// Glyphs in the order macOS menus print them (⌃ ⌥ ⇧ ⌘).
    var symbols: String {
        switch self {
        case .off:          ""
        case .ctrlOptCmdK:  "⌃⌥⌘K"
        case .ctrlOptCmdD:  "⌃⌥⌘D"
        case .optShiftCmdK: "⌥⇧⌘K"
        }
    }

    @ViewBuilder
    var label: some View {
        if self == .off {
            Text("Off")
        } else {
            Text(verbatim: symbols)
        }
    }

    static var current: HotKeyPreset {
        HotKeyPreset(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "")
            ?? defaultValue
    }
}

/// Registers a single global hot key through Carbon's
/// `RegisterEventHotKey`. The handler is invoked on the main thread.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    private static let signature: OSType = 0x4452_544D // 'DRTM'

    init(action: @escaping () -> Void) {
        self.action = action
        installHandler()
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Replaces any current registration with `preset`. Returns false
    /// when macOS refused it — usually because another app already owns
    /// the same combination.
    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        unregister()
        guard let binding = preset.binding else { return true }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("dirtymac: could not register \(preset.symbols) (OSStatus \(status))")
            hotKeyRef = nil
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard status == noErr, id.signature == GlobalHotKey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1,
            &spec,
            context,
            &handlerRef
        )
    }
}
