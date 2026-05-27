import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var databaseToRestore: URL?
    @AppStorage(AppAppearancePreference.storageKey) private var appearancePreference = AppAppearancePreference.dark.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearancePreference) {
                    ForEach(AppAppearancePreference.allCases) { preference in
                        Text(preference.title).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Workspace") {
                TextField("App Name", text: $model.appDisplayName)
                TextField("Organization", text: $model.organizationName)
                Button("Save Details") {
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

                settingsActionGrid {
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
                        if let url = FileDialogs.chooseDatabaseSaveURL(defaultName: "InventoryData-manual-backup.sqlite") {
                            Task { await model.backupDatabase(to: url) }
                        }
                    }
                    Button("Restore…") {
                        if let url = FileDialogs.chooseDatabaseFile() {
                            databaseToRestore = url
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
                BackupBrowserView(model: model)
            }

            Section("Spreadsheet and CSV Imports") {
                LabeledContent("Excel File") {
                    Text(model.excelInventoryPath.isEmpty ? "None" : model.excelInventoryPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                settingsActionGrid {
                    Button("Choose Excel Workbook…") {
                        if let url = FileDialogs.chooseExcelFile() {
                            model.setExcelInventoryPath(url.path)
                        }
                    }
                    Button("Import Excel") {
                        Task { await model.importFromExcel() }
                    }
                    .disabled(model.excelInventoryPath.isEmpty)
                    Button("Import CSV") {
                        if let url = FileDialogs.chooseCSVFile() {
                            Task { await model.importFromCSV(url: url) }
                        }
                    }
                    Button("Undo Last Import") {
                        Task { await model.undoLastImport() }
                    }
                    .disabled(model.lastImportUndoBackupURL == nil)
                    Button("Preview Excel Import") {
                        Task { await model.previewExcelImport() }
                    }
                    .disabled(model.excelInventoryPath.isEmpty)
                    Button("Clear Excel Path") {
                        model.clearExcelInventoryPath()
                    }
                    .disabled(model.excelInventoryPath.isEmpty)
                    Button("Skip Import for Now") {
                        model.acknowledgeSpreadsheetSetup()
                    }
                }
            }

            Section("Danger Zone") {
                DeleteAllDataControl(model: model)
            }

            if let preview = model.importPreview {
                Section("Import Preview") {
                    ImportPreviewPanel(preview: preview)
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
        .scrollContentBackground(.hidden)
        .padding(20)
        .background(AppTheme.appBackground)
        .tint(AppTheme.blue)
        .frame(minWidth: 620, minHeight: 460)
        .preferredColorScheme((AppAppearancePreference(rawValue: appearancePreference) ?? .dark).colorScheme)
        .onAppear(perform: sanitizeAppearancePreference)
        .confirmationDialog(
            "Restore database?",
            isPresented: Binding(
                get: { databaseToRestore != nil },
                set: { if !$0 { databaseToRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Database", role: .destructive) {
                guard let url = databaseToRestore else { return }
                Task {
                    await model.restoreDatabase(from: url)
                    databaseToRestore = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(databaseToRestore.map { "Replace the current database with \($0.lastPathComponent). The current database will be backed up first." } ?? "")
        }
    }

    private func sanitizeAppearancePreference() {
        if AppAppearancePreference(rawValue: appearancePreference) == nil {
            appearancePreference = AppAppearancePreference.dark.rawValue
        }
    }

    private func settingsActionGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)],
            alignment: .leading,
            spacing: 8
        ) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
