import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Workspace") {
                TextField("App Name", text: $model.appDisplayName)
                TextField("Organization", text: $model.organizationName)
                Button("Save Workspace Details") {
                    model.saveWorkspaceBranding()
                }
            }

            Section("Database") {
                LabeledContent("Current Database") {
                    Text(model.databaseURL.path)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Choose…") {
                        if let url = FileDialogs.chooseDatabaseFile() {
                            Task { await model.useDatabase(at: url) }
                        }
                    }
                    Button("New…") {
                        if let url = FileDialogs.chooseDatabaseSaveURL(defaultName: "InventoryData.sqlite") {
                            Task { await model.createDatabase(at: url) }
                        }
                    }
                    Button("Backup…") {
                        if let url = FileDialogs.chooseDatabaseSaveURL(defaultName: "InventoryData Backup.sqlite") {
                            Task { await model.backupDatabase(to: url) }
                        }
                    }
                    Button("Restore…") {
                        if let url = FileDialogs.chooseDatabaseFile() {
                            Task { await model.restoreDatabase(from: url) }
                        }
                    }
                    Button("Reveal") {
                        FileDialogs.revealInFinder(model.databaseURL)
                    }
                    Button("Load Demo") {
                        Task { await model.loadDemoWorkspace() }
                    }
                    .disabled(!model.isWorkspaceEmpty)
                    Button("Refresh Backups") {
                        model.refreshBackupRecords()
                    }
                }
            }

            Section("Backups") {
                if model.backupRecords.isEmpty {
                    Text("No backup files found next to this workspace yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.backupRecords.prefix(8)) { backup in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(backup.name)
                                Text("\(backup.displayDate) · \(backup.displaySize)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Reveal") {
                                FileDialogs.revealInFinder(backup.url)
                            }
                            Button("Restore") {
                                Task { await model.restoreBackup(backup) }
                            }
                        }
                    }
                }
            }

            Section("Spreadsheet Sync") {
                LabeledContent("Excel File") {
                    Text(model.excelInventoryPath.isEmpty ? "None" : model.excelInventoryPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Choose Excel File…") {
                        if let url = FileDialogs.chooseExcelFile() {
                            model.setExcelInventoryPath(url.path)
                        }
                    }
                    Button("Import Now") {
                        Task { await model.importFromExcel() }
                    }
                    .disabled(model.excelInventoryPath.isEmpty)
                    Button("Preview") {
                        Task { await model.previewExcelImport() }
                    }
                    .disabled(model.excelInventoryPath.isEmpty)
                    Button("Clear") {
                        model.clearExcelInventoryPath()
                    }
                    .disabled(model.excelInventoryPath.isEmpty)
                }
            }

            if let preview = model.importPreview {
                Section("Import Preview") {
                    Text(preview.summary)
                    if preview.hasConflicts {
                        ForEach((preview.inventoryConflicts + preview.deploymentConflicts), id: \.self) { conflict in
                            Text(conflict)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if let message = model.lastImportSummary {
                Section("Status") {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
    }
}
