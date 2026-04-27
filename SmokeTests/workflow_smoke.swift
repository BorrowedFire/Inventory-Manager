import Foundation

@main
struct Runner {
    static func main() throws {
        let service = DatabaseService(databaseURL: URL(fileURLWithPath: "/tmp/universal-inventory-workflow-smoke-db/InventoryData.sqlite"))
        try service.ensureSchema()
        let smokeSuffix = String(Int(Date().timeIntervalSince1970))

        let seed = ParsedImportItem(
            sourceFile: "seed.pdf",
            itemType: "Laptop",
            description: "Smoke Seed Laptop",
            manufacturer: "Apple",
            partNumber: "SMOKE-SEED-\(smokeSuffix)",
            purchaseDate: "04/06/2026",
            vendor: "SmokeVendor",
            unitCost: 1000,
            quantity: 3,
            qtyReceived: 3,
            poNumber: "PO-SEED-\(smokeSuffix)",
            notes: "seed item",
            budgetType: "Capital"
        )
        _ = try service.insertParsedItems([seed])

        let dashboard = try service.dashboardSnapshot()
        print("dashboard.stats=\(dashboard.stats.count)")

        let inventory = try service.inventoryItems()
        print("inventory.count=\(inventory.count)")

        let deployments = try service.deployments()
        print("deployments.count=\(deployments.count)")

        let stockrooms = try service.stockrooms()
        print("stockrooms.count=\(stockrooms.count)")

        let user = try service.currentUser()
        print("user=\(user.username):\(user.role)")

        let users = try service.users()
        print("users.count=\(users.count)")

        guard var firstItem = inventory.first else {
            fatalError("no inventory items")
        }

        let originalNotes = firstItem.notes
        firstItem.notes = "smoke-test-note"
        try service.updateInventoryItem(firstItem)
        let updated = try service.inventoryItems().first(where: { $0.id == firstItem.id })
        print("updateInventoryItem=\(updated?.notes == "smoke-test-note" ? "ok" : "fail")")

        let draft = DeploymentDraft(
            inventoryItemId: firstItem.id,
            itemType: firstItem.itemType,
            description: firstItem.description,
            manufacturer: firstItem.manufacturer,
            partNumber: firstItem.partNumber,
            stockroomId: firstItem.stockroomId,
            qtyDeployed: 1,
            deployedTo: "Smoke Test User",
            deployedBy: user.displayName,
            deployedDate: "04/06/2026",
            deployedLocation: "Office",
            notes: "smoke deploy"
        )

        try service.deploy(draft)
        let newDeployment = try service.deployments().first(where: {
            $0.deployedTo == "Smoke Test User" && $0.partNumber == firstItem.partNumber
        })
        print("deploy=\(newDeployment != nil ? "ok" : "fail")")

        if let newDeployment {
            try service.returnDeployment(id: newDeployment.id)
        }

        let returnedDeployment = try service.deployments().first(where: {
            $0.deployedTo == "Smoke Test User" && $0.partNumber == firstItem.partNumber
        })
        print("returnDeployment=\(returnedDeployment == nil ? "ok" : "fail")")

        let parsed = ParsedImportItem(
            sourceFile: "smoke.pdf",
            itemType: "Accessory",
            description: "Smoke Test Accessory",
            manufacturer: "Example Manufacturer",
            partNumber: "SMOKE-PART-\(smokeSuffix)",
            purchaseDate: "04/06/2026",
            vendor: "SmokeVendor",
            unitCost: 12.34,
            quantity: 2,
            qtyReceived: 2,
            poNumber: "PO-SMOKE-\(smokeSuffix)",
            notes: "smoke parsed item",
            budgetType: "Capital"
        )

        let parsedResult = try service.insertParsedItems([parsed])
        print("insertParsedItems.inserted=\(parsedResult.insertedItems.count)")

        let duplicateResult = try service.insertParsedItems([parsed])
        print("insertParsedItems.duplicateSkipped=\(duplicateResult.skippedCount)")

        let remaining = try service.remainingInventorySnapshots()
        print("remainingSnapshots.count=\(remaining.count)")

        let csv = try service.inventoryCSV()
        print("inventoryCSV.nonEmpty=\(!csv.isEmpty)")

        try service.createStockroom(name: "Smoke Stockroom", location: "Lab", department: "Operations")
        let createdStockroom = try service.stockrooms().first(where: { $0.name == "Smoke Stockroom" })
        print("createStockroom=\(createdStockroom != nil ? "ok" : "fail")")

        if let createdStockroom {
            try service.updateStockroom(id: createdStockroom.id, name: "Smoke Stockroom Updated", location: "HQ", department: "Operations")
            let updatedStockroom = try service.stockrooms().first(where: { $0.id == createdStockroom.id })
            print("updateStockroom=\(updatedStockroom?.name == "Smoke Stockroom Updated" ? "ok" : "fail")")
            try service.deleteStockroom(id: createdStockroom.id)
            let deletedStockroom = try service.stockrooms().first(where: { $0.id == createdStockroom.id })
            print("deleteStockroom=\(deletedStockroom == nil ? "ok" : "fail")")
        }

        if let nonCurrentUser = users.first(where: { $0.id != user.id }), let userID = nonCurrentUser.id {
            let originalRole = nonCurrentUser.role
            let replacementRole = originalRole == "viewer" ? "manager" : "viewer"
            try service.updateUserRole(userID: userID, role: replacementRole)
            let updatedUsers = try service.users()
            let changedUser = updatedUsers.first(where: { $0.id == userID })
            print("updateUserRole=\(changedUser?.role == replacementRole ? "ok" : "fail")")
            try service.updateUserRole(userID: userID, role: originalRole)
        }

        var restored = firstItem
        restored.notes = originalNotes
        try service.updateInventoryItem(restored)

        print("done")
    }
}
