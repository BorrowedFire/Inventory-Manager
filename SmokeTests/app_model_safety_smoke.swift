import Foundation

@main
struct Runner {
    @MainActor
    static func main() async throws {
        let defaults = UserDefaults.standard
        [
            "workspace.databasePath",
            "workspace.excelInventoryPath",
            "workspace.excelLastSyncMarker",
            "workspace.lastImportUndoBackupPath",
            "workspace.lastImportUndoExcelBackupPath"
        ].forEach { defaults.removeObject(forKey: $0) }

        let workspace = URL(fileURLWithPath: "/tmp/inventory-manager-app-model-smoke", isDirectory: true)
        try? FileManager.default.removeItem(at: workspace)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let databaseURL = workspace.appendingPathComponent("InventoryData.sqlite")
        let model = AppModel()
        await model.createDatabase(at: databaseURL)

        await model.backupDatabase(to: databaseURL)
        let activeDatabaseStillExists = FileManager.default.fileExists(atPath: databaseURL.path)
        let backupSelfBlocked = model.errorMessage?.localizedCaseInsensitiveContains("different from the active workspace database") == true
        print("backupRejectsActiveDatabase=\(activeDatabaseStillExists && backupSelfBlocked ? "ok" : "fail")")

        let unmanagedWorkspace = workspace.appendingPathComponent("OtherWorkspace.sqlite")
        let managedBackup = workspace.appendingPathComponent("InventoryData-before-smoke-import-20260430.sqlite")
        FileManager.default.createFile(atPath: unmanagedWorkspace.path, contents: Data("not a managed backup".utf8))
        FileManager.default.createFile(atPath: managedBackup.path, contents: Data("managed backup marker".utf8))

        model.refreshBackupRecords()
        let unmanagedPath = unmanagedWorkspace.standardizedFileURL.resolvingSymlinksInPath().path
        let managedPath = managedBackup.standardizedFileURL.resolvingSymlinksInPath().path
        let includesUnmanaged = model.backupRecords.contains { $0.url.standardizedFileURL.resolvingSymlinksInPath().path == unmanagedPath }
        let includesManaged = model.backupRecords.contains { $0.url.standardizedFileURL.resolvingSymlinksInPath().path == managedPath }
        print("backupFilterIgnoresWorkspaceDatabases=\(!includesUnmanaged && includesManaged ? "ok" : "fail")")
    }
}
