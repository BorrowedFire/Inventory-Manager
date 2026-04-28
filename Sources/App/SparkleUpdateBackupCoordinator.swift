import Foundation
import Sparkle

@MainActor
final class SparkleUpdateBackupCoordinator: NSObject, SPUUpdaterDelegate {
    private let model: AppModel
    private var backupInProgress = false

    init(model: AppModel) {
        self.model = model
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvoking installHandler: @escaping () -> Void
    ) -> Bool {
        guard !backupInProgress else { return false }
        backupInProgress = true

        Task { @MainActor in
            defer { backupInProgress = false }
            do {
                _ = try await model.createPreUpdateBackup(reason: "Sparkle relaunch")
                installHandler()
            } catch {
                model.errorMessage = "Update paused because the pre-update backup failed: \(error.localizedDescription)"
            }
        }

        return true
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        guard !backupInProgress else { return false }
        backupInProgress = true

        Task { @MainActor in
            defer { backupInProgress = false }
            do {
                _ = try await model.createPreUpdateBackup(reason: "Sparkle install on quit")
                immediateInstallHandler()
            } catch {
                model.errorMessage = "Update paused because the pre-update backup failed: \(error.localizedDescription)"
            }
        }

        return true
    }
}
