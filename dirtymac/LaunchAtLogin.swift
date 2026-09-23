import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` — registers dirtymac as a
/// login item so it is already in the menu bar (and the global shortcut
/// already listening) the moment the user decides to clean.
///
/// The system is the source of truth: the user can remove the item from
/// System Settings → General → Login Items at any time, so the state is
/// always read back from `SMAppService` rather than cached in defaults.
enum LaunchAtLogin {
    /// Set once the user has been offered launch-at-login (onboarding for
    /// new users, the What's New window for existing ones), so the offer
    /// is never repeated and a later "off" choice is never overridden.
    static let offeredKey = "launchAtLoginOffered"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registered, but the user (or an MDM profile) has switched the item
    /// off in System Settings. macOS will not launch it until approved.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static var wasOffered: Bool {
        UserDefaults.standard.bool(forKey: offeredKey)
    }

    static func markOffered() {
        UserDefaults.standard.set(true, forKey: offeredKey)
    }

    /// Registers or unregisters the login item. Errors are swallowed on
    /// purpose: the callers re-read `isEnabled` afterwards and show the
    /// real state, which is more useful to the user than an error code.
    static func set(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("dirtymac: launch-at-login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
