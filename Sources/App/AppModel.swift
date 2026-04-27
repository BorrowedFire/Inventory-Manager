import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    private static let standardItemTypes = [
        "AV",
        "Accessory",
        "Cables",
        "Desktop",
        "Laptop",
        "Monitor",
        "Peripheral",
        "Phone",
        "Printer",
        "Services",
        "Tablet",
        "Tools",
        "Warranty"
    ]

    private enum DefaultsKey {
        static let appDisplayName = "workspace.appDisplayName"
        static let organizationName = "workspace.organizationName"
        static let databasePath = "workspace.databasePath"
        static let excelInventoryPath = "workspace.excelInventoryPath"
        static let excelLastSyncMarker = "workspace.excelLastSyncMarker"
        static let onboardingDismissed = "workspace.onboardingDismissed"
        static let brandingReviewed = "workspace.brandingReviewed"
        static let databaseReviewed = "workspace.databaseReviewed"
        static let spreadsheetReviewed = "workspace.spreadsheetReviewed"
    }

    @Published var selectedSection: AppSection = .dashboard
    @Published var dashboard = DashboardSnapshot(stats: [], budgets: [], vendors: [], activity: [])
    @Published var budgetDashboard = BudgetDashboardSnapshot(annualSummaries: [], combinedSummaries: [], categorySummaries: [], annualBudgets: [])
    @Published var inventory: [InventoryItemRecord] = []
    @Published var deployments: [DeploymentRecord] = []
    @Published var stockrooms: [StockroomRecord] = []
    @Published var currentUser = AppUserRecord(id: nil, username: NSUserName(), role: "viewer", displayName: NSUserName())
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var appDisplayName: String
    @Published var organizationName: String
    @Published var databaseURL: URL
    @Published var inventorySearch = ""
    @Published var inventoryAvailability: InventoryAvailability = .all
    @Published var inventoryReceiptStatus: InventoryReceiptStatus = .all
    @Published var inventorySort: InventorySortOption = .updatedNewest
    @Published var inventoryTypeFilter = "All Types"
    @Published var inventoryManufacturerFilter = "All Manufacturers"
    @Published var inventoryVendorFilter = "All Vendors"
    @Published var inventoryBudgetFilter = "All Budgets"
    @Published var inventoryStockroomFilter = "All Stockrooms"
    @Published var inventoryPartNumberSearch = ""
    @Published var inventoryPOSearch = ""
    @Published var deploymentSearch = ""
    @Published var deploymentSort: DeploymentSortOption = .dateNewest
    @Published var deploymentTypeFilter = "All Types"
    @Published var deploymentLocationFilter = "All Locations"
    @Published var deploymentByFilter = "All Team Members"
    @Published var selectedInventoryID: Int64?
    @Published var selectedStockroomID: Int64?
    @Published var excelInventoryPath: String
    @Published var lastImportSummary: String?
    @Published var parsedImportItems: [ParsedImportItem] = []
    @Published var users: [AppUserRecord] = []
    @Published var annualBudgetRecords: [AnnualBudgetRecord] = []

    private var databaseService: DatabaseService
    private let excelSyncService = ExcelSyncService()
    private let pdfImportService = PDFImportService()
    private let lockRetryNanoseconds: UInt64 = 300_000_000
    private let defaults = UserDefaults.standard

    init() {
        let databaseURL = Self.initialDatabaseURL()
        let defaults = UserDefaults.standard
        self.appDisplayName = defaults.string(forKey: DefaultsKey.appDisplayName) ?? "Inventory Manager"
        self.organizationName = defaults.string(forKey: DefaultsKey.organizationName) ?? "Standalone Workspace"
        self.databaseURL = databaseURL
        self.excelInventoryPath = defaults.string(forKey: DefaultsKey.excelInventoryPath) ?? ""
        self.databaseService = DatabaseService(databaseURL: databaseURL)
    }

    var filteredInventory: [InventoryItemRecord] {
        inventory.filter { item in
            let matchesSearch = inventorySearch.isEmpty || [item.itemType, item.description, item.manufacturer, item.partNumber, item.vendor, item.poNumber, item.stockroomName]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(inventorySearch)

            let matchesAvailability: Bool = switch inventoryAvailability {
            case .all: true
            case .inStock: item.availableQuantity > 2
            case .low: item.availableQuantity > 0 && item.availableQuantity <= 2
            case .depleted: item.availableQuantity == 0
            }

            let matchesReceipt: Bool = switch inventoryReceiptStatus {
            case .all:
                true
            case .fullyReceived:
                item.quantity > 0 && item.qtyReceived >= item.quantity
            case .partiallyReceived:
                item.qtyReceived > 0 && item.qtyReceived < item.quantity
            case .notReceived:
                item.qtyReceived == 0
            }

            let matchesType = inventoryTypeFilter == "All Types" || item.itemType == inventoryTypeFilter
            let matchesManufacturer = inventoryManufacturerFilter == "All Manufacturers" || item.manufacturer == inventoryManufacturerFilter
            let matchesVendor = inventoryVendorFilter == "All Vendors" || item.vendor == inventoryVendorFilter
            let matchesBudget = inventoryBudgetFilter == "All Budgets" || item.budgetType == inventoryBudgetFilter
            let matchesStockroom = inventoryStockroomFilter == "All Stockrooms" || item.stockroomName == inventoryStockroomFilter
            let matchesPartNumber = inventoryPartNumberSearch.isEmpty || item.partNumber.localizedCaseInsensitiveContains(inventoryPartNumberSearch)
            let matchesPO = inventoryPOSearch.isEmpty || item.poNumber.localizedCaseInsensitiveContains(inventoryPOSearch)

            return matchesSearch && matchesAvailability && matchesReceipt && matchesType && matchesManufacturer && matchesVendor && matchesBudget && matchesStockroom && matchesPartNumber && matchesPO
        }
        .sorted(by: inventorySortComparator)
    }

    var filteredDeployments: [DeploymentRecord] {
        deployments.filter { deployment in
            let matchesSearch = deploymentSearch.isEmpty || [
                deployment.itemType,
                deployment.manufacturer,
                deployment.partNumber,
                deployment.description,
                deployment.deployedTo,
                deployment.deployedBy,
                deployment.deployedLocation,
                deployment.stockroomName,
                deployment.notes
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(deploymentSearch)

            let matchesType = deploymentTypeFilter == "All Types" || deployment.itemType == deploymentTypeFilter
            let matchesLocation = deploymentLocationFilter == "All Locations" || deployment.deployedLocation == deploymentLocationFilter
            let matchesDeployedBy = deploymentByFilter == "All Team Members" || deployment.deployedBy == deploymentByFilter

            return matchesSearch && matchesType && matchesLocation && matchesDeployedBy
        }
        .sorted(by: deploymentSortComparator)
    }

    var selectedInventory: InventoryItemRecord? {
        get { inventory.first(where: { $0.id == selectedInventoryID }) }
        set { selectedInventoryID = newValue?.id }
    }

    var selectedStockroomItems: [InventoryItemRecord] {
        guard let selectedStockroomID else { return [] }
        return inventory
            .filter { $0.stockroomId == selectedStockroomID }
            .sorted { lhs, rhs in
                let descriptionOrder = lhs.description.localizedCaseInsensitiveCompare(rhs.description)
                if descriptionOrder == .orderedSame {
                    return lhs.partNumber.localizedCaseInsensitiveCompare(rhs.partNumber) == .orderedAscending
                }
                return descriptionOrder == .orderedAscending
            }
    }

    var inventoryTypeOptions: [String] {
        ["All Types"] + uniqueInventoryValues(\.itemType)
    }

    var editableItemTypeOptions: [String] {
        let existingTypes = Set(
            inventory
                .map(\.itemType)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let orderedExisting = Self.standardItemTypes.filter { existingTypes.contains($0) }
        let remaining = existingTypes
            .subtracting(Self.standardItemTypes)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return orderedExisting + remaining
    }

    var inventoryManufacturerOptions: [String] {
        ["All Manufacturers"] + uniqueInventoryValues(\.manufacturer)
    }

    var inventoryVendorOptions: [String] {
        ["All Vendors"] + uniqueInventoryValues(\.vendor)
    }

    var inventoryBudgetOptions: [String] {
        ["All Budgets"] + uniqueInventoryValues(\.budgetType)
    }

    var inventoryStockroomOptions: [String] {
        ["All Stockrooms"] + uniqueInventoryValues(\.stockroomName)
    }

    var deploymentTypeOptions: [String] {
        ["All Types"] + uniqueDeploymentValues(\.itemType)
    }

    var deploymentLocationOptions: [String] {
        ["All Locations"] + uniqueDeploymentValues(\.deployedLocation)
    }

    var deploymentByOptions: [String] {
        ["All Team Members"] + uniqueDeploymentValues(\.deployedBy)
    }

    var filteredInventoryTotalUnits: Int {
        filteredInventory.reduce(0) { $0 + $1.quantity }
    }

    var filteredInventoryAvailableUnits: Int {
        filteredInventory.reduce(0) { $0 + $1.availableQuantity }
    }

    var filteredInventoryTotalValue: Double {
        filteredInventory.reduce(0) { $0 + $1.totalCost }
    }

    var isWorkspaceEmpty: Bool {
        inventory.isEmpty && deployments.isEmpty && stockrooms.isEmpty
    }

    var needsSpreadsheetSetup: Bool {
        excelInventoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var setupChecklist: [WorkspaceChecklistItem] {
        [
            WorkspaceChecklistItem(
                title: "Review workspace name",
                detail: "\(appDisplayName) for \(organizationName)",
                isComplete: defaults.bool(forKey: DefaultsKey.brandingReviewed)
            ),
            WorkspaceChecklistItem(
                title: "Choose the workspace database",
                detail: databaseURL.path,
                isComplete: defaults.bool(forKey: DefaultsKey.databaseReviewed) &&
                    FileManager.default.fileExists(atPath: databaseURL.path)
            ),
            WorkspaceChecklistItem(
                title: "Create a stockroom",
                detail: stockrooms.isEmpty ? "No stockrooms yet" : "\(stockrooms.count) configured",
                isComplete: !stockrooms.isEmpty
            ),
            WorkspaceChecklistItem(
                title: "Review spreadsheet workflow",
                detail: excelInventoryPath.isEmpty ? "Excel sync optional. No workbook selected." : excelInventoryPath,
                isComplete: defaults.bool(forKey: DefaultsKey.spreadsheetReviewed)
            )
        ]
    }

    var shouldPresentOnboarding: Bool {
        let allComplete = setupChecklist.allSatisfy(\.isComplete)
        return !allComplete && !defaults.bool(forKey: DefaultsKey.onboardingDismissed)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall { try databaseService.ensureSchema() }
            try await autoSyncExcelIfNeeded()
            dashboard = try await retryingDatabaseCall { try databaseService.dashboardSnapshot() }
            budgetDashboard = try await retryingDatabaseCall { try databaseService.budgetDashboard() }
            inventory = try await retryingDatabaseCall { try databaseService.inventoryItems() }
            deployments = try await retryingDatabaseCall { try databaseService.deployments() }
            stockrooms = try await retryingDatabaseCall { try databaseService.stockrooms() }
            currentUser = try await retryingDatabaseCall { try databaseService.currentUser() }
            users = try await retryingDatabaseCall { try databaseService.users() }
            annualBudgetRecords = budgetRecords(from: budgetDashboard)

            if selectedInventoryID == nil {
                selectedInventoryID = inventory.first?.id
            }
            if selectedStockroomID == nil {
                selectedStockroomID = stockrooms.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveInventory(_ item: InventoryItemRecord, originalItem: InventoryItemRecord? = nil) async {
        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall { try databaseService.updateInventoryItem(item) }
            let refreshedItem = try await retryingDatabaseCall {
                try databaseService.inventoryItem(id: item.id)
            }
            if
                !excelInventoryPath.isEmpty,
                let originalItem,
                let refreshedItem
            {
                try excelSyncService.updateInventory(original: originalItem, updated: refreshedItem, at: excelInventoryPath)
                try await syncRemainingInventoryIfNeeded()
                persistExcelSyncMarker()
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func returnDeployment(id: Int64) async {
        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall { try databaseService.returnDeployment(id: id) }
            try await syncRemainingInventoryIfNeeded()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deploy(item: InventoryItemRecord, qty: Int, deployedTo: String, deployedBy: String, deployedDate: String, location: String, notes: String) async {
        let draft = DeploymentDraft(
            inventoryItemId: item.id,
            itemType: item.itemType,
            description: item.description,
            manufacturer: item.manufacturer,
            partNumber: item.partNumber,
            stockroomId: item.stockroomId,
            qtyDeployed: qty,
            deployedTo: deployedTo,
            deployedBy: deployedBy,
            deployedDate: deployedDate,
            deployedLocation: location,
            notes: notes
        )

        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall { try databaseService.deploy(draft) }
            if !excelInventoryPath.isEmpty {
                try excelSyncService.appendDeployment(draft, to: excelInventoryPath)
                try await syncRemainingInventoryIfNeeded()
                persistExcelSyncMarker()
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setExcelInventoryPath(_ path: String) {
        excelInventoryPath = path
        defaults.set(path, forKey: DefaultsKey.excelInventoryPath)
        defaults.set(true, forKey: DefaultsKey.spreadsheetReviewed)
    }

    func clearExcelInventoryPath() {
        excelInventoryPath = ""
        defaults.removeObject(forKey: DefaultsKey.excelInventoryPath)
        defaults.removeObject(forKey: DefaultsKey.excelLastSyncMarker)
    }

    func saveWorkspaceBranding() {
        let trimmedAppName = appDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrganization = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        appDisplayName = trimmedAppName.isEmpty ? "Inventory Manager" : trimmedAppName
        organizationName = trimmedOrganization.isEmpty ? "Standalone Workspace" : trimmedOrganization
        defaults.set(appDisplayName, forKey: DefaultsKey.appDisplayName)
        defaults.set(organizationName, forKey: DefaultsKey.organizationName)
        defaults.set(true, forKey: DefaultsKey.brandingReviewed)
    }

    func dismissOnboarding() {
        defaults.set(true, forKey: DefaultsKey.onboardingDismissed)
    }

    func resetOnboarding() {
        defaults.removeObject(forKey: DefaultsKey.onboardingDismissed)
    }

    func useDatabase(at url: URL) async {
        do {
            let normalizedURL = url.standardizedFileURL
            let newService = DatabaseService(databaseURL: normalizedURL)
            try await retryingDatabaseCall { try newService.ensureSchema() }
            databaseURL = normalizedURL
            databaseService = newService
            defaults.set(normalizedURL.path, forKey: DefaultsKey.databasePath)
            defaults.set(true, forKey: DefaultsKey.databaseReviewed)
            selectedInventoryID = nil
            selectedStockroomID = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createDatabase(at url: URL) async {
        await useDatabase(at: url)
    }

    func createDatabaseAtDefaultLocation() async {
        await createDatabase(at: Self.defaultWorkspaceDatabaseURL())
    }

    func acknowledgeSpreadsheetSetup() {
        defaults.set(true, forKey: DefaultsKey.spreadsheetReviewed)
    }

    func importFromExcel() async {
        guard !excelInventoryPath.isEmpty else {
            errorMessage = "Choose an Excel inventory file first."
            return
        }

        do {
            let summary = try await syncExcel(force: true)
            lastImportSummary = "\(summary.inventoryImported) inventory imported, \(summary.inventoryUpdated) updated, \(summary.inventorySkipped) unchanged; \(summary.deploymentsImported) deployments imported, \(summary.deploymentsUpdated) updated, \(summary.deploymentsSkipped) unchanged."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeDuplicateInventoryItems() async {
        do {
            let databaseService = self.databaseService
            let removed = try await retryingDatabaseCall { try databaseService.removeDuplicateInventoryItems() }
            lastImportSummary = removed == 0 ? "No duplicate inventory rows found." : "Removed \(removed) duplicate inventory rows."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncRemainingInventoryIfNeeded() async throws {
        guard !excelInventoryPath.isEmpty else { return }
        let databaseService = self.databaseService
        let remaining = try await retryingDatabaseCall { try databaseService.remainingInventorySnapshots() }
        try excelSyncService.updateRemaining(remaining, at: excelInventoryPath)
    }

    func exportInventoryCSV(to url: URL) async {
        do {
            let databaseService = self.databaseService
            let csv = try await retryingDatabaseCall { try databaseService.inventoryCSV() }
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func backupDatabase(to destinationURL: URL) async {
        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall { try databaseService.checkpointForBackup() }
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: databaseURL, to: destinationURL)
            lastImportSummary = "Database backup saved to \(destinationURL.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreDatabase(from sourceURL: URL) async {
        do {
            let fileManager = FileManager.default
            let targetURL = databaseURL
            let backupURL = targetURL.deletingLastPathComponent().appendingPathComponent("InventoryData-before-restore-\(Int(Date().timeIntervalSince1970)).sqlite")
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.copyItem(at: targetURL, to: backupURL)
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            databaseService = DatabaseService(databaseURL: targetURL)
            selectedInventoryID = nil
            selectedStockroomID = nil
            lastImportSummary = "Database restored. Previous database backed up as \(backupURL.lastPathComponent)."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportBlankInventoryTemplateCSV(to url: URL) async {
        let csv = [
            "Item Type,Description,Manufacturer,Part Number,Purchase Date,Vendor,Unit Cost,Quantity,Qty Received,PO Number,Budget Type,Stockroom,Notes",
            "Laptop,Example Laptop,Example Manufacturer,ABC123,2026-01-01,Example Vendor,1999,5,5,PO-1001,Capital,Main Stockroom,Starter example row"
        ].joined(separator: "\n")

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func parsePDFs(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let parser = pdfImportService
            parsedImportItems = try await Task.detached(priority: .userInitiated) {
                parser.parse(urls: urls)
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveParsedItems() async {
        guard !parsedImportItems.isEmpty else { return }

        do {
            let itemsToSave = parsedImportItems
            let databaseService = self.databaseService
            let result = try await retryingDatabaseCall { try databaseService.insertParsedItems(itemsToSave) }

            if !excelInventoryPath.isEmpty {
                if !result.insertedItems.isEmpty {
                    try excelSyncService.appendInventory(result.insertedItems, to: excelInventoryPath)
                    try await syncRemainingInventoryIfNeeded()
                    persistExcelSyncMarker()
                }
            }

            let insertedCount = result.insertedItems.count
            if result.skippedCount > 0 {
                lastImportSummary = "Saved \(insertedCount) parsed PDF item(s) and skipped \(result.skippedCount) duplicate row(s)."
            } else {
                lastImportSummary = "Saved \(insertedCount) parsed PDF item(s) into inventory."
            }
            parsedImportItems = []
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createStockroom(name: String, location: String, department: String) async {
        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall {
                try databaseService.createStockroom(name: name, location: location, department: department)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetInventoryFilters() {
        inventorySearch = ""
        inventoryAvailability = .all
        inventoryReceiptStatus = .all
        inventorySort = .updatedNewest
        inventoryTypeFilter = "All Types"
        inventoryManufacturerFilter = "All Manufacturers"
        inventoryVendorFilter = "All Vendors"
        inventoryBudgetFilter = "All Budgets"
        inventoryStockroomFilter = "All Stockrooms"
        inventoryPartNumberSearch = ""
        inventoryPOSearch = ""
    }

    func openInventoryDrilldown(
        availability: InventoryAvailability = .all,
        receiptStatus: InventoryReceiptStatus = .all,
        sort: InventorySortOption = .updatedNewest,
        type: String? = nil,
        manufacturer: String? = nil,
        vendor: String? = nil,
        budget: String? = nil,
        stockroom: String? = nil,
        partNumber: String? = nil,
        poNumber: String? = nil,
        search: String? = nil
    ) {
        resetInventoryFilters()
        selectedSection = .inventory
        inventoryAvailability = availability
        inventoryReceiptStatus = receiptStatus
        inventorySort = sort
        inventoryTypeFilter = type ?? "All Types"
        inventoryManufacturerFilter = manufacturer ?? "All Manufacturers"
        inventoryVendorFilter = vendor ?? "All Vendors"
        inventoryBudgetFilter = budget ?? "All Budgets"
        inventoryStockroomFilter = stockroom ?? "All Stockrooms"
        inventoryPartNumberSearch = partNumber ?? ""
        inventoryPOSearch = poNumber ?? ""
        inventorySearch = search ?? ""
    }

    func openDeploymentsDrilldown(search: String? = nil) {
        deploymentSort = .dateNewest
        deploymentTypeFilter = "All Types"
        deploymentLocationFilter = "All Locations"
        deploymentByFilter = "All Team Members"
        selectedSection = .deployments
        deploymentSearch = search ?? ""
    }

    func openStockroomsDrilldown() {
        selectedSection = .stockrooms
    }

    func openSettingsDrilldown() {
        selectedSection = .settings
    }

    func updateStockroom(_ draft: StockroomDraft) async {
        guard let id = draft.id else { return }
        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall {
                try databaseService.updateStockroom(id: id, name: draft.name, location: draft.location, department: draft.department)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteStockroom(id: Int64) async {
        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall { try databaseService.deleteStockroom(id: id) }
            if selectedStockroomID == id {
                selectedStockroomID = nil
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateUserRole(userID: Int64, role: String) async {
        do {
            let databaseService = self.databaseService
            try await retryingDatabaseCall { try databaseService.updateUserRole(userID: userID, role: role) }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAnnualBudgets() async {
        do {
            let databaseService = self.databaseService
            let records = annualBudgetRecords
            try await retryingDatabaseCall { try databaseService.saveAnnualBudgets(records) }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addBudgetYear(_ year: String) {
        let trimmedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedYear.isEmpty else { return }

        let existingTypes = Set(
            annualBudgetRecords
                .filter { $0.year.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedYear }
                .map(\.budgetType)
        )

        if !existingTypes.contains("Capital") {
            annualBudgetRecords.append(AnnualBudgetRecord(year: trimmedYear, budgetType: "Capital", allocatedBudget: "", fundCode: "", glCode: ""))
        }
        if !existingTypes.contains("OpEx") {
            annualBudgetRecords.append(AnnualBudgetRecord(year: trimmedYear, budgetType: "OpEx", allocatedBudget: "", fundCode: "", glCode: ""))
        }

        annualBudgetRecords.sort {
            let lhsYear = Int($0.year.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let rhsYear = Int($1.year.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if lhsYear == rhsYear {
                return $0.budgetType.localizedCaseInsensitiveCompare($1.budgetType) == .orderedAscending
            }
            return lhsYear < rhsYear
        }
    }

    func removeAnnualBudgetRecord(id: UUID) {
        annualBudgetRecords.removeAll { $0.id == id }
    }

    private func retryingDatabaseCall<T: Sendable>(attempts: Int = 4, operation: @escaping @Sendable () throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 0..<attempts {
            do {
                return try await Task.detached(priority: .userInitiated, operation: operation).value
            } catch {
                lastError = error
                guard isLockError(error), attempt < attempts - 1 else {
                    throw error
                }
                try await Task.sleep(nanoseconds: lockRetryNanoseconds)
            }
        }

        throw lastError ?? DatabaseError.stepFailed("Unknown database error")
    }

    private func isLockError(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("database is locked")
    }

    private func autoSyncExcelIfNeeded() async throws {
        guard !excelInventoryPath.isEmpty else { return }
        _ = try await syncExcel(force: false)
    }

    @discardableResult
    private func syncExcel(force: Bool) async throws -> ImportSummary {
        guard !excelInventoryPath.isEmpty else {
            return ImportSummary(
                inventoryImported: 0,
                inventoryUpdated: 0,
                inventorySkipped: 0,
                deploymentsImported: 0,
                deploymentsUpdated: 0,
                deploymentsSkipped: 0
            )
        }

        let excelURL = URL(fileURLWithPath: excelInventoryPath)
        let marker = excelSyncMarker(for: excelURL)
        let savedMarker = defaults.string(forKey: DefaultsKey.excelLastSyncMarker)
        guard force || marker != savedMarker else {
            return ImportSummary(
                inventoryImported: 0,
                inventoryUpdated: 0,
                inventorySkipped: 0,
                deploymentsImported: 0,
                deploymentsUpdated: 0,
                deploymentsSkipped: 0
            )
        }

        let excelService = excelSyncService
        let excelPath = excelInventoryPath
        let workbook = try await Task.detached(priority: .userInitiated) {
            try excelService.readWorkbook(at: excelPath)
        }.value
        let databaseService = self.databaseService
        let summary = try await retryingDatabaseCall {
            try databaseService.importFromExcel(inventoryItems: workbook.0, deployments: workbook.1)
        }
        defaults.set(marker, forKey: DefaultsKey.excelLastSyncMarker)
        return summary
    }

    private func excelSyncMarker(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let timestamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(url.path)|\(timestamp)|\(size)"
    }

    private func persistExcelSyncMarker() {
        guard !excelInventoryPath.isEmpty else { return }
        let marker = excelSyncMarker(for: URL(fileURLWithPath: excelInventoryPath))
        defaults.set(marker, forKey: DefaultsKey.excelLastSyncMarker)
    }

    private func uniqueInventoryValues(_ keyPath: KeyPath<InventoryItemRecord, String>) -> [String] {
        Array(
            Set(
                inventory
                    .map { $0[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func uniqueDeploymentValues(_ keyPath: KeyPath<DeploymentRecord, String>) -> [String] {
        Array(
            Set(
                deployments
                    .map { $0[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func inventorySortComparator(lhs: InventoryItemRecord, rhs: InventoryItemRecord) -> Bool {
        switch inventorySort {
        case .updatedNewest:
            return lhs.updatedAt > rhs.updatedAt
        case .itemType:
            return lhs.itemType.localizedCaseInsensitiveCompare(rhs.itemType) == .orderedAscending
        case .description:
            return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
        case .manufacturer:
            return lhs.manufacturer.localizedCaseInsensitiveCompare(rhs.manufacturer) == .orderedAscending
        case .vendor:
            return lhs.vendor.localizedCaseInsensitiveCompare(rhs.vendor) == .orderedAscending
        case .partNumber:
            return lhs.partNumber.localizedCaseInsensitiveCompare(rhs.partNumber) == .orderedAscending
        case .unitCostHigh:
            return lhs.unitCost == rhs.unitCost ? lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending : lhs.unitCost > rhs.unitCost
        case .quantityHigh:
            return lhs.quantity == rhs.quantity ? lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending : lhs.quantity > rhs.quantity
        case .availableHigh:
            return lhs.availableQuantity == rhs.availableQuantity ? lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending : lhs.availableQuantity > rhs.availableQuantity
        case .purchaseDateNewest:
            return lhs.purchaseDate > rhs.purchaseDate
        }
    }

    private func deploymentSortComparator(lhs: DeploymentRecord, rhs: DeploymentRecord) -> Bool {
        switch deploymentSort {
        case .dateNewest:
            return lhs.deployedDate == rhs.deployedDate
                ? lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
                : lhs.deployedDate > rhs.deployedDate
        case .itemType:
            return lhs.itemType.localizedCaseInsensitiveCompare(rhs.itemType) == .orderedAscending
        case .description:
            return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
        case .deployedTo:
            return lhs.deployedTo.localizedCaseInsensitiveCompare(rhs.deployedTo) == .orderedAscending
        case .deployedBy:
            return lhs.deployedBy.localizedCaseInsensitiveCompare(rhs.deployedBy) == .orderedAscending
        case .location:
            return lhs.deployedLocation.localizedCaseInsensitiveCompare(rhs.deployedLocation) == .orderedAscending
        case .quantityHigh:
            return lhs.qtyDeployed == rhs.qtyDeployed
                ? lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
                : lhs.qtyDeployed > rhs.qtyDeployed
        }
    }

    private func budgetRecords(from snapshot: BudgetDashboardSnapshot) -> [AnnualBudgetRecord] {
        if !snapshot.annualBudgets.isEmpty {
            return snapshot.annualBudgets
        }

        let years = Set(snapshot.annualSummaries.map(\.year))
        let normalizedYears = years.isEmpty ? [Calendar.current.component(.year, from: Date())] : Array(years).sorted()
        var records: [AnnualBudgetRecord] = []
        for year in normalizedYears {
            let yearString = String(year)
            records.append(AnnualBudgetRecord(year: yearString, budgetType: "Capital", allocatedBudget: "", fundCode: "", glCode: ""))
            records.append(AnnualBudgetRecord(year: yearString, budgetType: "OpEx", allocatedBudget: "", fundCode: "", glCode: ""))
        }
        return records
    }

    private static func initialDatabaseURL() -> URL {
        let defaults = UserDefaults.standard
        if let savedPath = defaults.string(forKey: DefaultsKey.databasePath), !savedPath.isEmpty {
            return URL(fileURLWithPath: savedPath)
        }

        let fileManager = FileManager.default
        let cwdDatabase = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("InventoryData.sqlite")
        if fileManager.fileExists(atPath: cwdDatabase.path) {
            return cwdDatabase
        }

        return defaultWorkspaceDatabaseURL()
    }

    static func defaultWorkspaceDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("InventoryManager", isDirectory: true)
            .appendingPathComponent("InventoryData.sqlite")
    }
}
