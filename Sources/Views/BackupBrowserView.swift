import SwiftUI

struct BackupBrowserView: View {
    @ObservedObject var model: AppModel
    var limit: Int = 8
    @State private var backupToRestore: BackupRecord?
    @State private var confirmPrune = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Backups")
                    .font(.headline)
                Spacer()
                Button("Refresh") { model.refreshBackupRecords() }
                Button("Prune Old") { confirmPrune = true }
                    .disabled(model.backupRecords.count <= 20)
            }

            if model.backupRecords.isEmpty {
                Text("No backup files found next to this workspace yet.")
                    .foregroundStyle(AppTheme.muted)
            } else {
                ForEach(model.backupRecords.prefix(limit)) { backup in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.name)
                                .font(.subheadline.weight(.medium))
                            Text("\(backup.displayDate) · \(backup.displaySize)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            Text(backup.url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        Button("Reveal") { FileDialogs.revealInFinder(backup.url) }
                        Button("Restore") { backupToRestore = backup }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .confirmationDialog(
            "Restore backup?",
            isPresented: Binding(
                get: { backupToRestore != nil },
                set: { if !$0 { backupToRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Backup", role: .destructive) {
                guard let backup = backupToRestore else { return }
                Task {
                    await model.restoreBackup(backup)
                    backupToRestore = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(backupToRestore.map { "Replace the current database with \($0.name). The current database will be backed up first." } ?? "")
        }
        .confirmationDialog(
            "Prune old backups?",
            isPresented: $confirmPrune,
            titleVisibility: .visible
        ) {
            Button("Prune Old Backups", role: .destructive) {
                model.pruneOldBackups()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep the 20 newest backups and move older backup files to the Trash.")
        }
    }
}
