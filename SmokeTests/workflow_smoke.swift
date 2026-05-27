import Foundation

@main
struct Runner {
    static func main() throws {
        let service = DatabaseService(databaseURL: URL(fileURLWithPath: "/tmp/inventory-manager-workflow-smoke-db/InventoryData.sqlite"))
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

        var invalidReducedQuantity = firstItem
        invalidReducedQuantity.quantity = 0
        let reductionBlocked: Bool
        do {
            try service.updateInventoryItem(invalidReducedQuantity)
            reductionBlocked = false
        } catch {
            reductionBlocked = true
        }
        print("blockQuantityBelowActiveDeployments=\(reductionBlocked ? "ok" : "fail")")

        let overDeployImportBlocked: Bool
        do {
            _ = try service.importFromExcel(
                inventoryItems: [
                    ImportedInventoryItem(
                        itemType: firstItem.itemType,
                        description: firstItem.description,
                        manufacturer: firstItem.manufacturer,
                        partNumber: firstItem.partNumber,
                        purchaseDate: firstItem.purchaseDate,
                        vendor: firstItem.vendor,
                        unitCost: firstItem.unitCost,
                        quantity: 0,
                        qtyReceived: 0,
                        poNumber: firstItem.poNumber,
                        notes: firstItem.notes,
                        budgetType: firstItem.budgetType
                    )
                ],
                deployments: []
            )
            overDeployImportBlocked = false
        } catch {
            overDeployImportBlocked = true
        }
        print("blockExcelImportBelowActiveDeployments=\(overDeployImportBlocked ? "ok" : "fail")")

        let zeroQuantityDeploymentSummary = try service.importFromExcel(
            inventoryItems: [],
            deployments: [
                ImportedDeployment(
                    itemType: firstItem.itemType,
                    description: firstItem.description,
                    manufacturer: firstItem.manufacturer,
                    partNumber: firstItem.partNumber,
                    qtyDeployed: 0,
                    deployedTo: "Zero Quantity Import",
                    deployedBy: "Smoke Test",
                    deployedDate: "2026-04-07",
                    deployedLocation: "HQ",
                    notes: "should be skipped"
                )
            ]
        )
        let zeroQuantityDeploymentExists = try service.deployments().contains {
            $0.deployedTo == "Zero Quantity Import" && $0.partNumber == firstItem.partNumber
        }
        print("skipZeroQuantityDeploymentImport=\(zeroQuantityDeploymentSummary.deploymentsSkipped == 1 && !zeroQuantityDeploymentExists ? "ok" : "fail")")

        var deploymentToDelete: DeploymentRecord?
        if let newDeployment {
            try service.deploy(draft)
            deploymentToDelete = try service.deployments().first(where: {
                $0.deployedTo == "Smoke Test User" && $0.partNumber == firstItem.partNumber && $0.id != newDeployment.id
            })
            if let deploymentToDelete {
                try service.deleteDeployment(id: deploymentToDelete.id)
            }
        }
        let deletedDeployment = deploymentToDelete.flatMap { deleted in
            try? service.deployments().first(where: { $0.id == deleted.id })
        }
        print("deleteDeployment=\(deletedDeployment == nil ? "ok" : "fail")")

        if let newDeployment {
            try service.returnDeployment(id: newDeployment.id)
        }

        let returnedDeployment = try service.deployments().first(where: {
            $0.deployedTo == "Smoke Test User" && $0.partNumber == firstItem.partNumber
        })
        print("returnDeploymentPreservesHistory=\(returnedDeployment?.isReturned == true ? "ok" : "fail")")

        let afterReturnItem = try service.inventoryItems().first(where: { $0.id == firstItem.id })
        print("returnDeploymentRestoresAvailability=\(afterReturnItem?.availableQuantity == firstItem.quantity ? "ok" : "fail")")

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

        if let parsedItem = try service.inventoryItems().first(where: { $0.partNumber == parsed.partNumber }) {
            try service.deleteInventoryItem(id: parsedItem.id)
            let deletedItem = try service.inventoryItems().first(where: { $0.id == parsedItem.id })
            print("deleteInventoryItem=\(deletedItem == nil ? "ok" : "fail")")
        }

        let duplicatePart = "DUP-SMOKE-\(smokeSuffix)"
        let retainedID = try service.createInventoryItem(
            InventoryItemRecord(
                id: 0,
                itemType: "Accessory",
                description: "Duplicate Retained",
                manufacturer: "SmokeCo",
                partNumber: duplicatePart,
                purchaseDate: "04/06/2026",
                vendor: "SmokeVendor",
                unitCost: 50,
                quantity: 2,
                qtyReceived: 2,
                poNumber: "",
                notes: "retained duplicate",
                budgetType: "Capital",
                stockroomId: nil,
                stockroomName: "Unassigned",
                availableQuantity: 2,
                updatedAt: ""
            )
        )
        let duplicateID = try service.createInventoryItem(
            InventoryItemRecord(
                id: 0,
                itemType: "Accessory",
                description: "Duplicate Removed",
                manufacturer: "SmokeCo",
                partNumber: duplicatePart,
                purchaseDate: "04/06/2026",
                vendor: "SmokeVendor",
                unitCost: 50,
                quantity: 2,
                qtyReceived: 2,
                poNumber: "",
                notes: "removed duplicate",
                budgetType: "Capital",
                stockroomId: nil,
                stockroomName: "Unassigned",
                availableQuantity: 2,
                updatedAt: ""
            )
        )
        try service.deploy(
            DeploymentDraft(
                inventoryItemId: duplicateID,
                itemType: "Accessory",
                description: "Duplicate Removed",
                manufacturer: "SmokeCo",
                partNumber: duplicatePart,
                stockroomId: nil,
                qtyDeployed: 1,
                deployedTo: "Duplicate Smoke User",
                deployedBy: user.displayName,
                deployedDate: "04/06/2026",
                deployedLocation: "Office",
                notes: "duplicate cleanup smoke"
            )
        )
        let duplicateRemovedCount = try service.removeDuplicateInventoryItems()
        let movedDeployment = try service.deployments().first(where: { $0.deployedTo == "Duplicate Smoke User" })
        let duplicateStillExists = try service.inventoryItems().contains(where: { $0.id == duplicateID })
        print("removeDuplicates.migratesDeployments=\(duplicateRemovedCount == 1 && movedDeployment?.inventoryItemId == retainedID && !duplicateStillExists ? "ok" : "fail")")

        try service.saveAnnualBudgets([
            AnnualBudgetRecord(year: "2026", budgetType: "Capital", allocatedBudget: "1000", fundCode: "FUND", glCode: "GL")
        ])
        try service.deleteAnnualBudget(year: "2026", budgetType: "Capital")
        let deletedBudget = try service.budgetDashboard().annualBudgets.first(where: { $0.year == "2026" && $0.budgetType == "Capital" })
        print("deleteAnnualBudget=\(deletedBudget == nil ? "ok" : "fail")")

        let remaining = try service.remainingInventorySnapshots()
        print("remainingSnapshots.count=\(remaining.count)")

        let csv = try service.inventoryCSV()
        print("inventoryCSV.nonEmpty=\(!csv.isEmpty)")

        try service.createStockroom(name: "Smoke Stockroom", location: "Lab", department: "Operations")
        let createdStockroom = try service.stockrooms().first(where: { $0.name == "Smoke Stockroom" })
        print("createStockroom=\(createdStockroom != nil ? "ok" : "fail")")

        if let createdStockroom {
            let manual = InventoryItemRecord(
                id: 0,
                itemType: "Tablet",
                description: "Manual Smoke Item",
                manufacturer: "SmokeCo",
                partNumber: "MANUAL-SMOKE-\(smokeSuffix)",
                purchaseDate: "04/06/2026",
                vendor: "SmokeVendor",
                unitCost: 25,
                quantity: 1,
                qtyReceived: 1,
                poNumber: "PO-MANUAL-\(smokeSuffix)",
                notes: "manual create smoke",
                budgetType: "OpEx",
                stockroomId: createdStockroom.id,
                stockroomName: createdStockroom.name,
                availableQuantity: 1,
                updatedAt: ""
            )
            let manualID = try service.createInventoryItem(manual)
            let manualItem = try service.inventoryItems().first(where: { $0.id == manualID })
            print("createInventoryItem=\(manualItem?.stockroomId == createdStockroom.id ? "ok" : "fail")")

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
