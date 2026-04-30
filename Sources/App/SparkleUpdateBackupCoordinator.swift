import Foundation
import AppKit
import Sparkle

@MainActor
final class SparkleUpdateBackupCoordinator: NSObject, SPUUpdaterDelegate {
    private enum DefaultsKey {
        static let appManagementNoticeSuppressed = "updates.appManagementNoticeSuppressed"
    }

    private let model: AppModel
    private let defaults: UserDefaults
    private var installPreparationInProgress = false

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        prepareForUpdateInstall(reason: "Sparkle relaunch", installHandler: installHandler)
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        prepareForUpdateInstall(reason: "Sparkle install on quit", installHandler: immediateInstallHandler)
    }

    private func prepareForUpdateInstall(reason: String, installHandler: @escaping () -> Void) -> Bool {
        guard !installPreparationInProgress else { return false }
        installPreparationInProgress = true

        Task { @MainActor in
            defer { installPreparationInProgress = false }

            guard showAppManagementNoticeIfNeeded() else {
                model.errorMessage = "Update paused. Choose Check for Updates when you are ready to continue."
                return
            }

            do {
                _ = try await model.createPreUpdateBackup(reason: reason)
                installHandler()
            } catch {
                model.errorMessage = "Update paused because the pre-update backup failed: \(error.localizedDescription)"
            }
        }

        return true
    }

    private func showAppManagementNoticeIfNeeded() -> Bool {
        if defaults.bool(forKey: DefaultsKey.appManagementNoticeSuppressed) {
            return true
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "macOS May Ask for App Management"
        alert.informativeText = """
        Inventory Manager uses this permission only to replace its own app during updates. It does not manage other apps, read your inventory database, or access your Excel workbook because of this permission.

        If macOS asks, allow Inventory Manager in System Settings > Privacy & Security > App Management so the update can finish.
        """
        alert.addButton(withTitle: "Continue Update")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't remind me again"

        let accepted = alert.runModal() == .alertFirstButtonReturn
        if accepted, alert.suppressionButton?.state == .on {
            defaults.set(true, forKey: DefaultsKey.appManagementNoticeSuppressed)
        }
        return accepted
    }
}
