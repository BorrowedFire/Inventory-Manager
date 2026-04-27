import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case budgets = "Budgets"
    case inventory = "Inventory"
    case deployments = "Deployments"
    case importPDFs = "Import PDFs"
    case stockrooms = "Stockrooms"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .budgets: "chart.bar.doc.horizontal"
        case .inventory: "shippingbox"
        case .deployments: "arrowshape.turn.up.right"
        case .importPDFs: "doc.viewfinder"
        case .stockrooms: "building.2"
        case .settings: "gearshape"
        }
    }

    var eyebrow: String {
        switch self {
        case .dashboard: "Overview"
        case .budgets: "Budget Intelligence"
        case .inventory: "Inventory Ledger"
        case .deployments: "Deployment History"
        case .importPDFs: "Import Workflow"
        case .stockrooms: "Room Access"
        case .settings: "Configuration"
        }
    }
}

enum InventoryAvailability: String, CaseIterable, Identifiable {
    case all = "All"
    case inStock = "In Stock"
    case low = "Low Stock"
    case depleted = "Out of Stock"

    var id: String { rawValue }
}

enum InventorySortOption: String, CaseIterable, Identifiable, Sendable {
    case updatedNewest = "Updated"
    case itemType = "Type"
    case description = "Description"
    case manufacturer = "Manufacturer"
    case vendor = "Vendor"
    case partNumber = "Part Number"
    case unitCostHigh = "Cost"
    case quantityHigh = "Quantity"
    case availableHigh = "Available"
    case purchaseDateNewest = "Purchase Date"

    var id: String { rawValue }
}

enum InventoryReceiptStatus: String, CaseIterable, Identifiable, Sendable {
    case all = "All Receipts"
    case fullyReceived = "Fully Received"
    case partiallyReceived = "Partially Received"
    case notReceived = "Not Received"

    var id: String { rawValue }
}

enum DeploymentSortOption: String, CaseIterable, Identifiable, Sendable {
    case dateNewest = "Date"
    case itemType = "Type"
    case description = "Item"
    case deployedTo = "Deployed To"
    case deployedBy = "Deployed By"
    case location = "Location"
    case quantityHigh = "Qty"

    var id: String { rawValue }
}

struct DashboardStat: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let value: String
    let note: String
    let accent: String
}

struct BudgetDashboardSnapshot: Sendable {
    let annualSummaries: [BudgetYearSummary]
    let combinedSummaries: [BudgetCombinedSummary]
    let categorySummaries: [BudgetCategorySummary]
    let annualBudgets: [AnnualBudgetRecord]
}

struct BudgetSummary: Identifiable, Hashable, Sendable {
    let id = UUID()
    let budgetType: String
    let itemCount: Int
    let totalValue: Double
}

struct BudgetYearSummary: Identifiable, Hashable, Sendable {
    var id: String { "\(budgetType)-\(year)" }
    let year: Int
    let budgetType: String
    let allocatedBudget: Double?
    let actualSpend: Double
    let remainingBudget: Double?
    let percentUsed: Double?
    let status: String
    let fundCode: String
    let glCode: String
    let itemCount: Int
}

struct BudgetCombinedSummary: Identifiable, Hashable, Sendable {
    var id: String { yearLabel }
    let yearLabel: String
    let totalBudget: Double?
    let totalSpend: Double
    let totalRemaining: Double?
}

struct BudgetCategorySummary: Identifiable, Hashable, Sendable {
    var id: String { "\(budgetType)-\(year)-\(category)" }
    let year: Int
    let budgetType: String
    let category: String
    let totalSpend: Double
    let itemCount: Int
    let averageCost: Double
    let percentOfYear: Double
}

struct AnnualBudgetRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    var year: String
    var budgetType: String
    var allocatedBudget: String
    var fundCode: String
    var glCode: String

    init(
        id: UUID = UUID(),
        year: String,
        budgetType: String,
        allocatedBudget: String,
        fundCode: String,
        glCode: String
    ) {
        self.id = id
        self.year = year
        self.budgetType = budgetType
        self.allocatedBudget = allocatedBudget
        self.fundCode = fundCode
        self.glCode = glCode
    }
}

struct VendorSpend: Identifiable, Hashable, Sendable {
    var id: String { vendor }
    let vendor: String
    let totalValue: Double
}

struct ActivityEntry: Identifiable, Hashable, Sendable {
    let id: Int64
    let action: String
    let entityType: String
    let details: String
    let detailNote: String
    let performedBy: String
    let createdAt: String
}

struct InventoryItemRecord: Identifiable, Hashable, Sendable {
    let id: Int64
    var itemType: String
    var description: String
    var manufacturer: String
    var partNumber: String
    var purchaseDate: String
    var vendor: String
    var unitCost: Double
    var quantity: Int
    var qtyReceived: Int
    var poNumber: String
    var notes: String
    var budgetType: String
    var stockroomId: Int64?
    var stockroomName: String
    var availableQuantity: Int
    var updatedAt: String

    var totalCost: Double { unitCost * Double(quantity) }
}

struct DeploymentRecord: Identifiable, Hashable, Sendable {
    let id: Int64
    let inventoryItemId: Int64?
    let itemType: String
    let manufacturer: String
    let partNumber: String
    let description: String
    let deployedTo: String
    let deployedBy: String
    let deployedDate: String
    let deployedLocation: String
    let qtyDeployed: Int
    let stockroomName: String
    let notes: String
}

struct StockroomRecord: Identifiable, Hashable, Sendable {
    let id: Int64
    var name: String
    var location: String
    var department: String
    let itemCount: Int
    let totalQuantity: Int
    let totalValue: Double
}

struct AppUserRecord: Hashable, Sendable {
    let id: Int64?
    let username: String
    let role: String
    let displayName: String
}

struct StockroomDraft: Identifiable, Hashable, Sendable {
    let id: Int64?
    var name: String
    var location: String
    var department: String

    init(id: Int64? = nil, name: String = "", location: String = "", department: String = "") {
        self.id = id
        self.name = name
        self.location = location
        self.department = department
    }
}

struct ParsedImportItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    var sourceFile: String
    var itemType: String
    var description: String
    var manufacturer: String
    var partNumber: String
    var purchaseDate: String
    var vendor: String
    var unitCost: Double
    var quantity: Int
    var qtyReceived: Int
    var poNumber: String
    var notes: String
    var budgetType: String
}

struct WorkspaceChecklistItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
    let isComplete: Bool
}
