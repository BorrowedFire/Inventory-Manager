import Foundation

struct ImportedInventoryItem: Decodable {
    let itemType: String
    let description: String
    let manufacturer: String
    let partNumber: String
    let purchaseDate: String
    let vendor: String
    let unitCost: Double
    let quantity: Int
    let qtyReceived: Int
    let poNumber: String
    let notes: String
    let budgetType: String
}

struct ImportedDeployment: Decodable {
    let itemType: String
    let description: String
    let manufacturer: String
    let partNumber: String
    let qtyDeployed: Int
    let deployedTo: String
    let deployedBy: String
    let deployedDate: String
    let deployedLocation: String
    let notes: String
}

struct ImportSummary: Sendable {
    let inventoryImported: Int
    let inventoryUpdated: Int
    let inventorySkipped: Int
    let deploymentsImported: Int
    let deploymentsUpdated: Int
    let deploymentsSkipped: Int
}

struct ParsedImportSaveResult: Sendable {
    let insertedItems: [ParsedImportItem]
    let skippedCount: Int
}

struct DeploymentDraft {
    let inventoryItemId: Int64
    let itemType: String
    let description: String
    let manufacturer: String
    let partNumber: String
    let stockroomId: Int64?
    let qtyDeployed: Int
    let deployedTo: String
    let deployedBy: String
    let deployedDate: String
    let deployedLocation: String
    let notes: String
}

struct RemainingInventoryUpdate: Sendable {
    let partNumber: String
    let poNumber: String
    let budgetType: String
    let remaining: Int
}

final class ExcelSyncService: @unchecked Sendable {
    private let fileManager = FileManager.default

    func readWorkbook(at excelPath: String) throws -> ([ImportedInventoryItem], [ImportedDeployment]) {
        let inventory = try run(command: "read-inventory", excelPath: excelPath, payload: [:], decode: WorkbookInventoryResponse.self)
        try validateSuccess(inventory)
        let deployments = try run(command: "read-deployed", excelPath: excelPath, payload: [:], decode: WorkbookDeploymentResponse.self)
        try validateSuccess(deployments)
        return (inventory.items, deployments.deployments)
    }

    func appendInventory(_ items: [InventoryItemRecord], to excelPath: String) throws {
        let payloadItems = items.map { item in
            [
                "itemType": item.itemType,
                "description": item.description,
                "manufacturer": item.manufacturer,
                "partNumber": item.partNumber,
                "purchaseDate": item.purchaseDate,
                "vendor": item.vendor,
                "unitCost": item.unitCost,
                "quantity": item.quantity,
                "qtyReceived": item.qtyReceived,
                "poNumber": item.poNumber,
                "notes": item.notes,
                "remainingInventory": item.availableQuantity
            ] as [String: Any]
        }

        let sheet = items.first?.budgetType == "OpEx" ? "OpEx" : "Inventory"
        try validateSuccess(try run(command: "append-inventory", excelPath: excelPath, payload: ["sheet": sheet, "items": payloadItems], decode: SuccessResponse.self))
    }

    func appendInventory(_ items: [ParsedImportItem], to excelPath: String) throws {
        let groupedItems = Dictionary(grouping: items) { item in
            item.budgetType == "OpEx" ? "OpEx" : "Inventory"
        }

        for (sheet, sheetItems) in groupedItems {
            let payloadItems = sheetItems.map { item in
                [
                    "itemType": item.itemType,
                    "description": item.description,
                    "manufacturer": item.manufacturer,
                    "partNumber": item.partNumber,
                    "purchaseDate": item.purchaseDate,
                    "vendor": item.vendor,
                    "unitCost": item.unitCost,
                    "quantity": item.quantity,
                    "qtyReceived": item.qtyReceived,
                    "poNumber": item.poNumber,
                    "notes": item.notes,
                    "remainingInventory": item.quantity
                ] as [String: Any]
            }
            try validateSuccess(try run(command: "append-inventory", excelPath: excelPath, payload: ["sheet": sheet, "items": payloadItems], decode: SuccessResponse.self))
        }
    }

    func appendDeployment(_ deployment: DeploymentDraft, to excelPath: String) throws {
        let payload: [String: Any] = [
            "deployments": [[
                "itemType": deployment.itemType,
                "description": deployment.description,
                "manufacturer": deployment.manufacturer,
                "partNumber": deployment.partNumber,
                "qtyDeployed": deployment.qtyDeployed,
                "deployedTo": deployment.deployedTo,
                "deployedBy": deployment.deployedBy,
                "deployedDate": deployment.deployedDate,
                "deployedLocation": deployment.deployedLocation,
                "notes": deployment.notes
            ]]
        ]

        try validateSuccess(try run(command: "append-deployed", excelPath: excelPath, payload: payload, decode: SuccessResponse.self))
    }

    func updateRemaining(_ remaining: [RemainingInventoryUpdate], at excelPath: String) throws {
        let payload = [
            "updates": remaining.map { ["partNumber": $0.partNumber, "poNumber": $0.poNumber, "budgetType": $0.budgetType, "remaining": $0.remaining] }
        ]
        try validateSuccess(try run(command: "update-remaining", excelPath: excelPath, payload: payload, decode: SuccessResponse.self))
    }

    func updateInventory(original: InventoryItemRecord, updated: InventoryItemRecord, at excelPath: String) throws {
        let payload: [String: Any] = [
            "original": inventoryPayload(for: original),
            "updated": inventoryPayload(for: updated)
        ]
        try validateSuccess(try run(command: "update-inventory", excelPath: excelPath, payload: payload, decode: SuccessResponse.self))
    }

    func resolvedScriptPath() -> String? {
        let candidates: [String?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("Resources")
                .appendingPathComponent("Scripts")
                .appendingPathComponent("excel_sync.py")
                .path,
            Bundle.main.resourceURL?
                .appendingPathComponent("Scripts")
                .appendingPathComponent("excel_sync.py")
                .path,
            fileManager.currentDirectoryPath + "/Resources/Scripts/excel_sync.py",
            fileManager.currentDirectoryPath + "/Inventory Manager.app/Contents/Resources/Resources/Scripts/excel_sync.py",
            fileManager.currentDirectoryPath + "/../Inventory Manager.app/Contents/Resources/Resources/Scripts/excel_sync.py",
            fileManager.currentDirectoryPath + "/Sources/Scripts/excel_sync.py"
        ]

        return candidates.compactMap { $0 }.first(where: { fileManager.fileExists(atPath: $0) })
    }

    func resolvedPythonPath() -> String? {
        let candidates: [String?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("Resources")
                .appendingPathComponent("python")
                .path,
            Bundle.main.resourceURL?
                .appendingPathComponent("python")
                .path,
            fileManager.currentDirectoryPath + "/Resources/python",
            fileManager.currentDirectoryPath + "/Vendor/python"
        ]

        return candidates.compactMap { $0 }.first(where: { fileManager.fileExists(atPath: $0) })
    }

    private func run<T: Decodable>(command: String, excelPath: String, payload: [String: Any], decode: T.Type) throws -> T {
        guard let scriptPath = resolvedScriptPath() else {
            throw NSError(domain: "ExcelSyncService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate excel_sync.py"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath, command, excelPath]
        var environment = ProcessInfo.processInfo.environment
        if let pythonPath = resolvedPythonPath() {
            let existing = environment["PYTHONPATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            environment["PYTHONPATH"] = [pythonPath, existing].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }.joined(separator: ":")
        }
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let body = try JSONSerialization.data(withJSONObject: payload)
        inputPipe.fileHandleForWriting.write(body)
        try? inputPipe.fileHandleForWriting.close()

        let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrText = String(data: stderr, encoding: .utf8) ?? "Unknown Python error"
            throw NSError(domain: "ExcelSyncService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderrText])
        }

        return try JSONDecoder().decode(T.self, from: stdout)
    }

    private func validateSuccess(_ response: ExcelSyncResponse) throws {
        guard response.success else {
            throw NSError(domain: "ExcelSyncService", code: 2, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Excel sync failed."])
        }
    }

    private func inventoryPayload(for item: InventoryItemRecord) -> [String: Any] {
        [
            "itemType": item.itemType,
            "description": item.description,
            "manufacturer": item.manufacturer,
            "partNumber": item.partNumber,
            "purchaseDate": item.purchaseDate,
            "vendor": item.vendor,
            "unitCost": item.unitCost,
            "quantity": item.quantity,
            "qtyReceived": item.qtyReceived,
            "poNumber": item.poNumber,
            "notes": item.notes,
            "budgetType": item.budgetType,
            "remainingInventory": item.availableQuantity
        ]
    }
}

private protocol ExcelSyncResponse {
    var success: Bool { get }
    var error: String? { get }
}

private struct WorkbookInventoryResponse: Decodable, ExcelSyncResponse {
    let success: Bool
    let error: String?
    let items: [ImportedInventoryItem]
}

private struct WorkbookDeploymentResponse: Decodable, ExcelSyncResponse {
    let success: Bool
    let error: String?
    let deployments: [ImportedDeployment]
}

private struct SuccessResponse: Decodable, ExcelSyncResponse {
    let success: Bool
    let error: String?
}
