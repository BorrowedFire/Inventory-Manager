import Foundation

@main
struct FreshWorkspaceRunner {
    static func main() throws {
        let dbPath = "/tmp/inventory-manager-fresh-smoke/FreshWorkspace.db"
        let dbURL = URL(fileURLWithPath: dbPath)
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath + "-wal"))
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let service = DatabaseService(databaseURL: dbURL)
        try service.ensureSchema()

        let user = try service.currentUser()
        print("fresh.user.role=\(user.role)")

        let initialInventory = try service.inventoryItems()
        print("fresh.inventory.initial=\(initialInventory.count)")

        try service.createStockroom(name: "Main Closet", location: "HQ", department: "IT")
        let stockrooms = try service.stockrooms()
        print("fresh.stockrooms=\(stockrooms.count)")

        try service.saveAnnualBudgets([
            AnnualBudgetRecord(year: "2024", budgetType: "Capital", allocatedBudget: "10000", fundCode: "CAP-24", glCode: "1001"),
            AnnualBudgetRecord(year: "2024", budgetType: "OpEx", allocatedBudget: "2500", fundCode: "OPEX-24", glCode: "2001"),
            AnnualBudgetRecord(year: "2025", budgetType: "Capital", allocatedBudget: "12000", fundCode: "CAP-25", glCode: "1002")
        ])

        let parsed = ParsedImportItem(
            sourceFile: "fresh-smoke.pdf",
            itemType: "Laptop",
            description: "Fresh Workspace Test Device",
            manufacturer: "Dell",
            partNumber: "FRESH-SMOKE-001",
            purchaseDate: "04/07/2026",
            vendor: "Example Vendor",
            unitCost: 1499.00,
            quantity: 2,
            qtyReceived: 2,
            poNumber: "PO-FRESH-001",
            notes: "fresh workspace smoke",
            budgetType: "Capital"
        )

        let insert = try service.insertParsedItems([parsed])
        print("fresh.inserted=\(insert.insertedItems.count)")

        let inventory = try service.inventoryItems()
        print("fresh.inventory.afterInsert=\(inventory.count)")

        let dashboard = try service.dashboardSnapshot()
        print("fresh.dashboard.stats=\(dashboard.stats.count)")

        let budgetDashboard = try service.budgetDashboard()
        print("fresh.budget.years=\(budgetDashboard.annualSummaries.count)")

        if let item = inventory.first {
            let draft = DeploymentDraft(
                inventoryItemId: item.id,
                itemType: item.itemType,
                description: item.description,
                manufacturer: item.manufacturer,
                partNumber: item.partNumber,
                stockroomId: item.stockroomId,
                qtyDeployed: 1,
                deployedTo: "Fresh User",
                deployedBy: user.displayName,
                deployedDate: "04/07/2026",
                deployedLocation: "Office",
                notes: "fresh deployment"
            )
            try service.deploy(draft)
            let deployments = try service.deployments()
            print("fresh.deployments=\(deployments.count)")
        }

        print("fresh.done")
    }
}
