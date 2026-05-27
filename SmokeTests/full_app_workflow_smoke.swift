import Foundation
import PDFKit

private enum SmokeFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SmokeFailure.failed(message)
    }
}

private func zipEntries(at url: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
    process.arguments = ["-1", url.path]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let message = String(data: errorOutput, encoding: .utf8) ?? "zipinfo failed"
        throw SmokeFailure.failed(message)
    }

    return String(data: output, encoding: .utf8) ?? ""
}

@main
struct FullAppWorkflowSmoke {
    @MainActor
    static func main() async throws {
        let defaults = UserDefaults.standard
        let keysToPreserve = [
            "appearance.preference",
            "workspace.appDisplayName",
            "workspace.organizationName",
            "workspace.databasePath",
            "workspace.excelInventoryPath",
            "workspace.excelLastSyncMarker",
            "workspace.onboardingDismissed",
            "workspace.brandingReviewed",
            "workspace.databaseReviewed",
            "workspace.spreadsheetReviewed",
            "workspace.lastImportUndoBackupPath",
            "workspace.lastImportUndoExcelBackupPath"
        ]
        let preservedDefaults = Dictionary(uniqueKeysWithValues: keysToPreserve.map { ($0, defaults.object(forKey: $0) as Any?) })

        defer {
            for key in keysToPreserve {
                if let value = preservedDefaults[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let workspace = URL(fileURLWithPath: "/tmp/inventory-manager-full-app-smoke", isDirectory: true)
        try? FileManager.default.removeItem(at: workspace)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let databaseURL = workspace.appendingPathComponent("InventoryData.sqlite")
        let model = AppModel()
        await model.createDatabase(at: databaseURL)
        try require(model.errorMessage == nil, "createDatabase produced an error")
        try require(model.inventory.isEmpty, "new workspace should start empty")

        await model.createStockroom(name: "Main Cage", location: "HQ", department: "IT")
        try require(model.stockrooms.count == 1, "stockroom was not created")
        let stockroomID = try requireStockroomID(model)

        var item = AppModel.blankInventoryItem(stockroomId: stockroomID)
        item.itemType = "Laptop"
        item.description = "Full App Smoke Laptop"
        item.manufacturer = "Example"
        item.partNumber = "FULL-SMOKE-001"
        item.purchaseDate = "2026-05-27"
        item.vendor = "Example Vendor"
        item.unitCost = 1200
        item.quantity = 3
        item.qtyReceived = 3
        item.poNumber = "PO-FULL-SMOKE"
        item.notes = "created by full app smoke"
        item.budgetType = "Capital"
        await model.createInventory(item)
        try require(model.inventory.count == 1, "inventory item was not created")
        try require(model.selectedInventory?.stockroomName == "Main Cage" || model.inventory.first?.stockroomName == "Main Cage", "created item did not attach to stockroom")

        var editedItem = try requireInventoryItem(model)
        editedItem.notes = "edited by full app smoke"
        editedItem.vendor = "Edited Vendor"
        await model.saveInventory(editedItem, originalItem: model.inventory.first)
        let savedItem = try requireInventoryItem(model)
        try require(savedItem.notes == "edited by full app smoke", "edited inventory notes did not persist")
        try require(savedItem.vendor == "Edited Vendor", "edited inventory vendor did not persist")

        await model.deploy(
            item: savedItem,
            qty: 1,
            deployedTo: "Smoke Recipient",
            deployedBy: model.currentUser.displayName,
            deployedDate: "2026-05-27",
            location: "HQ",
            notes: "deployment smoke"
        )
        try require(model.deployments.count == 1, "deployment was not created")
        try require(model.inventory.first?.availableQuantity == 2, "deployment did not reduce availability")

        if let deployment = model.deployments.first {
            await model.returnDeployment(id: deployment.id)
        }
        try require(model.deployments.first?.isReturned == true, "returned deployment was not preserved in history")
        try require(model.inventory.first?.availableQuantity == 3, "return did not restore availability")

        model.annualBudgetRecords = [
            AnnualBudgetRecord(year: "2026", budgetType: "Capital", allocatedBudget: "10000", fundCode: "CAP-26", glCode: "1001"),
            AnnualBudgetRecord(year: "2026", budgetType: "OpEx", allocatedBudget: "2500", fundCode: "OPEX-26", glCode: "2001")
        ]
        await model.saveAnnualBudgets()
        try require(model.budgetDashboard.annualSummaries.contains { $0.year == 2026 && $0.budgetType == "Capital" }, "budget dashboard did not include saved Capital target")

        let exportURL = workspace.appendingPathComponent("Inventory Export.csv")
        await model.exportInventoryCSV(to: exportURL)
        try require(FileManager.default.fileExists(atPath: exportURL.path), "inventory CSV export was not created")
        let exportText = try String(contentsOf: exportURL, encoding: .utf8)
        try require(exportText.contains("Full App Smoke Laptop"), "inventory CSV export did not include created item")

        let templateURL = workspace.appendingPathComponent("Inventory Template.csv")
        await model.exportBlankInventoryTemplateCSV(to: templateURL)
        let templateText = try String(contentsOf: templateURL, encoding: .utf8)
        try require(templateText.contains("Item Type,Description,Manufacturer"), "blank CSV template header is missing")

        let countBeforeImport = model.inventory.count
        let csvURL = workspace.appendingPathComponent("import.csv")
        let csv = [
            "Item Type,Description,Manufacturer,Part Number,Purchase Date,Vendor,Unit Cost,Quantity,Qty Received,PO Number,Budget Type,Stockroom,Notes",
            "Monitor,Imported Monitor,Example,MON-FULL-001,2026-05-27,CSV Vendor,300,2,2,PO-CSV-1,OpEx,Main Cage,import smoke"
        ].joined(separator: "\n")
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
        await model.importFromCSV(url: csvURL)
        try require(model.inventory.count == countBeforeImport + 1, "CSV import did not add a row")
        try require(model.lastImportUndoBackupURL != nil, "CSV import did not create an undo backup")
        await model.undoLastImport()
        try require(model.inventory.count == countBeforeImport, "undo last import did not restore pre-import inventory count")

        let fakePDFURL = workspace.appendingPathComponent("Smoke_Quote.pdf")
        try require(PDFDocument().write(to: fakePDFURL), "could not create smoke PDF fixture")
        await model.parsePDFs(urls: [fakePDFURL])
        try require(model.parsedImportItems.count == 1, "PDF fallback parser did not create a review row")
        model.parsedImportItems[0].description = "Parsed PDF Smoke Item"
        model.parsedImportItems[0].partNumber = "PDF-FULL-001"
        model.parsedImportItems[0].quantity = 1
        model.parsedImportItems[0].qtyReceived = 1
        model.parsedImportItems[0].stockroomId = model.stockrooms.first?.id
        await model.saveParsedItems()
        try require(model.parsedImportItems.isEmpty, "saving parsed PDF rows did not clear the review queue")
        try require(model.inventory.contains { $0.partNumber == "PDF-FULL-001" }, "saved parsed PDF row did not appear in inventory")

        let backupURL = workspace.appendingPathComponent("InventoryData-manual-backup-smoke.sqlite")
        await model.backupDatabase(to: backupURL)
        try require(FileManager.default.fileExists(atPath: backupURL.path), "manual database backup was not created")
        try require(model.backupRecords.contains { $0.url.lastPathComponent == backupURL.lastPathComponent }, "manual backup did not appear in backup records")

        let demoDatabaseURL = workspace.appendingPathComponent("DemoWorkspace.sqlite")
        await model.createDatabase(at: demoDatabaseURL)
        await model.loadDemoWorkspace()
        try require(model.inventory.count >= 3, "demo workspace did not create sample inventory")
        try require(model.deployments.count >= 1, "demo workspace did not create a sample deployment")
        try require(model.stockrooms.count >= 1, "demo workspace did not create a sample stockroom")
        try require(!model.dashboard.activity.isEmpty, "demo workspace did not create dashboard activity")

        let supportContext = SupportBundleService.makeContext(
            databaseURL: demoDatabaseURL,
            excelInventoryPath: "",
            currentUserRole: model.currentUser.role,
            inventoryCount: model.inventory.count,
            deploymentCount: model.deployments.count,
            stockroomCount: model.stockrooms.count,
            backupCount: model.backupRecords.count,
            lastVisibleError: model.errorMessage,
            lastImportSummary: model.lastImportSummary,
            recentErrors: []
        )
        let supportBundleURL = try SupportBundleService.createSupportBundle(context: supportContext)
        defer { try? FileManager.default.removeItem(at: supportBundleURL) }
        let entries = try zipEntries(at: supportBundleURL)
        try require(entries.contains("diagnostics.json"), "support bundle is missing diagnostics.json")
        try require(!entries.localizedCaseInsensitiveContains(".sqlite"), "support bundle unexpectedly contains a sqlite database")
        try require(!entries.localizedCaseInsensitiveContains(".xlsx"), "support bundle unexpectedly contains a workbook")

        print("full_app_workflow_smoke=ok")
    }

    @MainActor
    private static func requireStockroomID(_ model: AppModel) throws -> Int64 {
        guard let id = model.stockrooms.first?.id else {
            throw SmokeFailure.failed("missing stockroom id")
        }
        return id
    }

    @MainActor
    private static func requireInventoryItem(_ model: AppModel) throws -> InventoryItemRecord {
        guard let item = model.inventory.first else {
            throw SmokeFailure.failed("missing inventory item")
        }
        return item
    }
}
