import SwiftUI

struct BackupBrowserView: View {
    @ObservedObject var model: AppModel
    var limit: Int = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Backups")
                    .font(.headline)
                Spacer()
                Button("Refresh") { model.refreshBackupRecords() }
                Button("Prune Old") { model.pruneOldBackups() }
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
                        Button("Restore") { Task { await model.restoreBackup(backup) } }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}
