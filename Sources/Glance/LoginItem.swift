import Foundation
import ServiceManagement

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Returns a user-facing message on failure.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if enabled && needsApproval {
                return "macOS needs your approval: turn on Glance in System Settings › General › Login Items & Extensions."
            }
            return nil
        } catch {
            let ns = error as NSError
            if ns.code == kSMErrorLaunchDeniedByUser {
                return "Glance was turned off in System Settings › General › Login Items & Extensions. Turn it on there."
            }
            return "Couldn’t \(enabled ? "turn on" : "turn off") Open at Login: \(error.localizedDescription)"
        }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
