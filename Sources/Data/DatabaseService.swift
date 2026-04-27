import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message):
            message
        }
    }
}

struct DashboardSnapshot: Sendable {
    let stats: [DashboardStat]
    let budgets: [BudgetSummary]
    let vendors: [VendorSpend]
    let activity: [ActivityEntry]
}

final class DatabaseService: @unchecked Sendable {
    private let databaseURL: URL
    private let busyTimeoutMilliseconds: Int32 = 5_000
    private let accessQueue = DispatchQueue(label: "com.inventorymanager.database")
    private let purchaseYearSQL = """
    CASE
      WHEN trim(COALESCE(purchaseDate, '')) GLOB '[0-1][0-9]/[0-3][0-9]/[1-2][0-9][0-9][0-9]' THEN CAST(substr(trim(purchaseDate), 7, 4) AS INTEGER)
      WHEN trim(COALESCE(purchaseDate, '')) GLOB '[0-1][0-9]/[0-3][0-9]/[0-9][0-9]' THEN 2000 + CAST(substr(trim(purchaseDate), 7, 2) AS INTEGER)
      WHEN trim(COALESCE(purchaseDate, '')) GLOB '[1-2][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]*' THEN CAST(substr(trim(purchaseDate), 1, 4) AS INTEGER)
      ELSE CAST(strftime('%Y', createdAt) AS INTEGER)
    END
    """

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func ensureSchema() throws {
        try accessQueue.sync {
            let directoryURL = databaseURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

            var db: OpaquePointer?
            guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                throw DatabaseError.openFailed(lastMessage(from: db))
            }
            defer { sqlite3_close(db) }
            configureConnection(db)

            let schemaSQL = """
            PRAGMA journal_mode = WAL;
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS inventory_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              itemType TEXT DEFAULT '',
              description TEXT DEFAULT '',
              manufacturer TEXT DEFAULT '',
              partNumber TEXT DEFAULT '',
              purchaseDate TEXT,
              vendor TEXT,
              unitCost DOUBLE DEFAULT 0,
              quantity INTEGER DEFAULT 0,
              qtyReceived INTEGER DEFAULT 0,
              poNumber TEXT,
              notes TEXT,
              sourcePDF TEXT,
              budgetType TEXT DEFAULT 'Capital',
              stockroomId INTEGER,
              createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
              updatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS index_inventory_items_on_partNumber ON inventory_items(partNumber);
            CREATE INDEX IF NOT EXISTS index_inventory_items_on_poNumber ON inventory_items(poNumber);
            CREATE INDEX IF NOT EXISTS index_inventory_items_on_vendor ON inventory_items(vendor);
            CREATE INDEX IF NOT EXISTS index_inventory_items_on_stockroomId ON inventory_items(stockroomId);

            CREATE TABLE IF NOT EXISTS deployments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              inventoryItemId INTEGER,
              itemType TEXT DEFAULT '',
              description TEXT DEFAULT '',
              manufacturer TEXT DEFAULT '',
              partNumber TEXT DEFAULT '',
              qtyDeployed INTEGER DEFAULT 1,
              deployedTo TEXT DEFAULT '',
              deployedBy TEXT DEFAULT '',
              deployedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
              deployedLocation TEXT DEFAULT '',
              notes TEXT,
              createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
              stockroomId INTEGER
            );
            CREATE INDEX IF NOT EXISTS index_deployments_on_partNumber ON deployments(partNumber);
            CREATE INDEX IF NOT EXISTS index_deployments_on_inventoryItemId ON deployments(inventoryItemId);
            CREATE INDEX IF NOT EXISTS index_deployments_on_stockroomId ON deployments(stockroomId);

            CREATE TABLE IF NOT EXISTS stockrooms (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              location TEXT,
              department TEXT,
              createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
              createdBy INTEGER
            );

            CREATE TABLE IF NOT EXISTS users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              displayName TEXT,
              role TEXT DEFAULT 'viewer',
              createdAt DATETIME DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS audit_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              action TEXT NOT NULL,
              entityType TEXT NOT NULL,
              entityId INTEGER,
              details TEXT NOT NULL,
              performedBy TEXT NOT NULL,
              createdAt DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS index_audit_log_on_createdAt ON audit_log(createdAt);
            CREATE INDEX IF NOT EXISTS index_audit_log_on_action ON audit_log(action);

            CREATE TABLE IF NOT EXISTS annual_budgets (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              year INTEGER NOT NULL,
              budgetType TEXT NOT NULL,
              allocatedBudget DOUBLE,
              fundCode TEXT,
              glCode TEXT,
              createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
              updatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
              UNIQUE(year, budgetType)
            );
            CREATE INDEX IF NOT EXISTS index_annual_budgets_on_year_type ON annual_budgets(year, budgetType);

            CREATE TRIGGER IF NOT EXISTS validate_inventory_items_insert
            BEFORE INSERT ON inventory_items
            BEGIN
              SELECT RAISE(ABORT, 'Quantity cannot be negative.') WHERE NEW.quantity < 0;
              SELECT RAISE(ABORT, 'Quantity received cannot be negative.') WHERE NEW.qtyReceived < 0;
              SELECT RAISE(ABORT, 'Quantity received cannot exceed quantity.') WHERE NEW.qtyReceived > NEW.quantity;
              SELECT RAISE(ABORT, 'Unit cost cannot be negative.') WHERE NEW.unitCost < 0;
            END;

            CREATE TRIGGER IF NOT EXISTS validate_inventory_items_update
            BEFORE UPDATE ON inventory_items
            BEGIN
              SELECT RAISE(ABORT, 'Quantity cannot be negative.') WHERE NEW.quantity < 0;
              SELECT RAISE(ABORT, 'Quantity received cannot be negative.') WHERE NEW.qtyReceived < 0;
              SELECT RAISE(ABORT, 'Quantity received cannot exceed quantity.') WHERE NEW.qtyReceived > NEW.quantity;
              SELECT RAISE(ABORT, 'Unit cost cannot be negative.') WHERE NEW.unitCost < 0;
            END;

            CREATE TRIGGER IF NOT EXISTS validate_deployments_insert
            BEFORE INSERT ON deployments
            WHEN NEW.inventoryItemId IS NOT NULL
            BEGIN
              SELECT RAISE(ABORT, 'Deployment quantity must be greater than zero.') WHERE NEW.qtyDeployed <= 0;
              SELECT RAISE(ABORT, 'Deployment exceeds available inventory.')
              WHERE (
                SELECT COALESCE(SUM(qtyDeployed), 0)
                FROM deployments
                WHERE inventoryItemId = NEW.inventoryItemId
              ) + NEW.qtyDeployed > (
                SELECT quantity FROM inventory_items WHERE id = NEW.inventoryItemId
              );
            END;

            CREATE TRIGGER IF NOT EXISTS validate_deployments_update
            BEFORE UPDATE ON deployments
            WHEN NEW.inventoryItemId IS NOT NULL
            BEGIN
              SELECT RAISE(ABORT, 'Deployment quantity must be greater than zero.') WHERE NEW.qtyDeployed <= 0;
              SELECT RAISE(ABORT, 'Deployment exceeds available inventory.')
              WHERE (
                SELECT COALESCE(SUM(qtyDeployed), 0)
                FROM deployments
                WHERE inventoryItemId = NEW.inventoryItemId AND id <> OLD.id
              ) + NEW.qtyDeployed > (
                SELECT quantity FROM inventory_items WHERE id = NEW.inventoryItemId
              );
            END;
            """

            guard sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK else {
                throw DatabaseError.stepFailed(lastMessage(from: db))
            }

            let reconcileSQL = """
            UPDATE deployments AS d
            SET inventoryItemId = (
              SELECT i.id
              FROM inventory_items i
              WHERE lower(trim(COALESCE(i.partNumber, ''))) = lower(trim(COALESCE(d.partNumber, '')))
              ORDER BY i.id ASC
              LIMIT 1
            )
            WHERE d.inventoryItemId IS NULL
              AND trim(COALESCE(d.partNumber, '')) <> '';
            """
            guard sqlite3_exec(db, reconcileSQL, nil, nil, nil) == SQLITE_OK else {
                throw DatabaseError.stepFailed(lastMessage(from: db))
            }
        }
    }

    func dashboardSnapshot() throws -> DashboardSnapshot {
        let totals = try singleRow(
            """
            SELECT
              COUNT(*) AS itemCount,
              COALESCE(SUM(quantity), 0) AS totalQuantity,
              COALESCE(SUM(unitCost * quantity), 0) AS totalValue,
              (SELECT COALESCE(SUM(qtyDeployed), 0) FROM deployments) AS totalDeployed,
              (SELECT COUNT(*) FROM stockrooms) AS stockroomCount,
              (SELECT COUNT(*)
               FROM (
                 SELECT i.id
                 FROM inventory_items i
                 LEFT JOIN (
                    SELECT inventoryItemId, SUM(qtyDeployed) AS deployedQty
                    FROM deployments
                    GROUP BY inventoryItemId
                 ) d ON d.inventoryItemId = i.id
                 WHERE MAX(i.quantity - COALESCE(d.deployedQty, 0), 0) BETWEEN 1 AND 2
               )) AS lowStockCount
            FROM inventory_items
            """
        )

        let deploymentsThisMonth = try singleInt(
            """
            SELECT COUNT(*)
            FROM deployments
            WHERE strftime('%Y-%m', deployedDate) = strftime('%Y-%m', 'now', 'localtime')
            """
        )

        let stats = [
            DashboardStat(title: "Cataloged Items", value: formatInteger(totals.int(named: "itemCount")), note: "\(formatInteger(totals.int(named: "totalQuantity"))) units tracked", accent: "amber"),
            DashboardStat(title: "Inventory Value", value: formatCurrency(totals.double(named: "totalValue")), note: "purchase-value footprint", accent: "blue"),
            DashboardStat(title: "Total Deployed", value: formatInteger(totals.int(named: "totalDeployed")), note: "\(deploymentsThisMonth) this month", accent: "teal"),
            DashboardStat(title: "Low Stock Alerts", value: formatInteger(totals.int(named: "lowStockCount")), note: "items with 1-2 left", accent: "rose"),
            DashboardStat(title: "Stockrooms", value: formatInteger(totals.int(named: "stockroomCount")), note: "active room locations", accent: "indigo"),
            DashboardStat(title: "Database", value: "Live", note: databaseURL.lastPathComponent, accent: "mint")
        ]

        let budgets = try query(
            """
            SELECT budgetType, COUNT(*) AS itemCount, COALESCE(SUM(unitCost * quantity), 0) AS totalValue
            FROM inventory_items
            GROUP BY budgetType
            ORDER BY totalValue DESC
            """
        ).map { row in
            BudgetSummary(
                budgetType: row.string(named: "budgetType"),
                itemCount: row.int(named: "itemCount"),
                totalValue: row.double(named: "totalValue")
            )
        }

        let vendors = try query(
            """
            SELECT COALESCE(NULLIF(TRIM(vendor), ''), 'Unknown Vendor') AS vendor,
                   COALESCE(SUM(unitCost * quantity), 0) AS totalValue
            FROM inventory_items
            GROUP BY vendor
            ORDER BY totalValue DESC
            LIMIT 8
            """
        ).map { row in
            VendorSpend(vendor: row.string(named: "vendor"), totalValue: row.double(named: "totalValue"))
        }

        let activity = try query(
            """
            SELECT
              id,
              action,
              entityType,
              details,
              CASE
                WHEN action = 'import' AND details LIKE 'PDF import:%' THEN
                  substr(details, instr(details, ' | ') + 3)
                WHEN action = 'import' AND details LIKE 'Excel import:%' THEN
                  substr(details, instr(details, ' | ') + 3)
                ELSE ''
              END AS detailNote,
              performedBy,
              datetime(createdAt, 'localtime') AS createdAt
            FROM audit_log
            WHERE NOT (action = 'import' AND details LIKE '%: 0 inserted%')
            ORDER BY createdAt DESC
            LIMIT 20
            """
        ).map { row in
            ActivityEntry(
                id: row.int64(named: "id"),
                action: row.string(named: "action"),
                entityType: row.string(named: "entityType"),
                details: row.string(named: "details"),
                detailNote: row.string(named: "detailNote"),
                performedBy: row.string(named: "performedBy"),
                createdAt: row.string(named: "createdAt")
            )
        }

        return DashboardSnapshot(stats: stats, budgets: budgets, vendors: vendors, activity: activity)
    }

    func checkpointForBackup() throws {
        try accessQueue.sync {
            let db = try openDatabase(readOnly: false)
            defer { sqlite3_close(db) }
            guard sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil) == SQLITE_OK else {
                throw DatabaseError.stepFailed(lastMessage(from: db))
            }
        }
    }

    func inventoryItems() throws -> [InventoryItemRecord] {
        try query(
            """
            SELECT
              i.id,
              i.itemType,
              i.description,
              i.manufacturer,
              i.partNumber,
              COALESCE(i.purchaseDate, '') AS purchaseDate,
              COALESCE(i.vendor, '') AS vendor,
              i.unitCost,
              i.quantity,
              i.qtyReceived,
              COALESCE(i.poNumber, '') AS poNumber,
              COALESCE(i.notes, '') AS notes,
              i.budgetType,
              i.stockroomId,
              COALESCE(s.name, 'Unassigned') AS stockroomName,
              MAX(i.quantity - COALESCE(d.totalDeployed, 0), 0) AS availableQuantity,
              datetime(i.updatedAt, 'localtime') AS updatedAt
            FROM inventory_items i
            LEFT JOIN stockrooms s ON s.id = i.stockroomId
            LEFT JOIN (
              SELECT inventoryItemId, SUM(qtyDeployed) AS totalDeployed
              FROM deployments
              GROUP BY inventoryItemId
            ) d ON d.inventoryItemId = i.id
            ORDER BY i.updatedAt DESC, i.id DESC
            """
        ).map { row in
            InventoryItemRecord(
                id: row.int64(named: "id"),
                itemType: row.string(named: "itemType"),
                description: row.string(named: "description"),
                manufacturer: row.string(named: "manufacturer"),
                partNumber: row.string(named: "partNumber"),
                purchaseDate: row.string(named: "purchaseDate"),
                vendor: row.string(named: "vendor"),
                unitCost: row.double(named: "unitCost"),
                quantity: row.int(named: "quantity"),
                qtyReceived: row.int(named: "qtyReceived"),
                poNumber: row.string(named: "poNumber"),
                notes: row.string(named: "notes"),
                budgetType: row.string(named: "budgetType"),
                stockroomId: row.optionalInt64(named: "stockroomId"),
                stockroomName: row.string(named: "stockroomName"),
                availableQuantity: row.int(named: "availableQuantity"),
                updatedAt: row.string(named: "updatedAt")
            )
        }
    }

    func deployments() throws -> [DeploymentRecord] {
        try query(
            """
            SELECT
              d.id,
              d.inventoryItemId,
              d.itemType,
              d.manufacturer,
              d.partNumber,
              d.description,
              d.deployedTo,
              d.deployedBy,
              datetime(d.deployedDate, 'localtime') AS deployedDate,
              d.deployedLocation,
              d.qtyDeployed,
              COALESCE(s.name, 'Unassigned') AS stockroomName,
              COALESCE(d.notes, '') AS notes
            FROM deployments d
            LEFT JOIN stockrooms s ON s.id = d.stockroomId
            ORDER BY d.deployedDate DESC, d.id DESC
            """
        ).map { row in
            DeploymentRecord(
                id: row.int64(named: "id"),
                inventoryItemId: row.optionalInt64(named: "inventoryItemId"),
                itemType: row.string(named: "itemType"),
                manufacturer: row.string(named: "manufacturer"),
                partNumber: row.string(named: "partNumber"),
                description: row.string(named: "description"),
                deployedTo: row.string(named: "deployedTo"),
                deployedBy: row.string(named: "deployedBy"),
                deployedDate: row.string(named: "deployedDate"),
                deployedLocation: row.string(named: "deployedLocation"),
                qtyDeployed: row.int(named: "qtyDeployed"),
                stockroomName: row.string(named: "stockroomName"),
                notes: row.string(named: "notes")
            )
        }
    }

    func budgetDashboard() throws -> BudgetDashboardSnapshot {
        let annualSummaries = try query(
            """
            WITH actuals AS (
              SELECT
                \(purchaseYearSQL) AS year,
                CASE
                  WHEN lower(trim(COALESCE(budgetType, ''))) IN ('opex', 'operational', 'operational expense', 'operational expenses') THEN 'OpEx'
                  ELSE 'Capital'
                END AS budgetType,
                COALESCE(SUM(unitCost * quantity), 0) AS actualSpend,
                COUNT(*) AS itemCount
              FROM inventory_items
              GROUP BY 1, 2
            ),
            keys AS (
              SELECT year, budgetType FROM actuals
              UNION
              SELECT year, budgetType FROM annual_budgets
            )
            SELECT
              keys.year,
              keys.budgetType,
              annual_budgets.allocatedBudget,
              COALESCE(actuals.actualSpend, 0) AS actualSpend,
              CASE
                WHEN annual_budgets.allocatedBudget IS NULL THEN NULL
                ELSE annual_budgets.allocatedBudget - COALESCE(actuals.actualSpend, 0)
              END AS remainingBudget,
              CASE
                WHEN annual_budgets.allocatedBudget IS NULL OR annual_budgets.allocatedBudget = 0 THEN NULL
                ELSE COALESCE(actuals.actualSpend, 0) / annual_budgets.allocatedBudget
              END AS percentUsed,
              CASE
                WHEN annual_budgets.allocatedBudget IS NULL THEN 'Unconfigured'
                WHEN COALESCE(actuals.actualSpend, 0) > annual_budgets.allocatedBudget THEN 'Over Budget'
                WHEN COALESCE(actuals.actualSpend, 0) >= annual_budgets.allocatedBudget THEN 'At Budget'
                WHEN annual_budgets.allocatedBudget > 0 AND COALESCE(actuals.actualSpend, 0) / annual_budgets.allocatedBudget >= 0.85 THEN 'Watch'
                ELSE 'On Track'
              END AS status,
              COALESCE(annual_budgets.fundCode, '') AS fundCode,
              COALESCE(annual_budgets.glCode, '') AS glCode,
              COALESCE(actuals.itemCount, 0) AS itemCount
            FROM keys
            LEFT JOIN actuals ON actuals.year = keys.year AND actuals.budgetType = keys.budgetType
            LEFT JOIN annual_budgets ON annual_budgets.year = keys.year AND annual_budgets.budgetType = keys.budgetType
            WHERE keys.year IS NOT NULL
            ORDER BY keys.year, CASE keys.budgetType WHEN 'Capital' THEN 0 ELSE 1 END
            """
        ).map { row in
            BudgetYearSummary(
                year: row.int(named: "year"),
                budgetType: row.string(named: "budgetType"),
                allocatedBudget: row.optionalDouble(named: "allocatedBudget"),
                actualSpend: row.double(named: "actualSpend"),
                remainingBudget: row.optionalDouble(named: "remainingBudget"),
                percentUsed: row.optionalDouble(named: "percentUsed"),
                status: row.string(named: "status"),
                fundCode: row.string(named: "fundCode"),
                glCode: row.string(named: "glCode"),
                itemCount: row.int(named: "itemCount")
            )
        }

        let combinedSummaries = try query(
            """
            WITH actuals AS (
              SELECT
                \(purchaseYearSQL) AS year,
                COALESCE(SUM(unitCost * quantity), 0) AS totalSpend
              FROM inventory_items
              GROUP BY 1
            ),
            budgets AS (
              SELECT year, COALESCE(SUM(allocatedBudget), 0) AS totalBudget
              FROM annual_budgets
              GROUP BY 1
            ),
            years AS (
              SELECT year FROM actuals
              UNION
              SELECT year FROM budgets
            )
            SELECT
              years.year,
              budgets.totalBudget,
              COALESCE(actuals.totalSpend, 0) AS totalSpend,
              CASE
                WHEN budgets.totalBudget IS NULL THEN NULL
                ELSE budgets.totalBudget - COALESCE(actuals.totalSpend, 0)
              END AS totalRemaining
            FROM years
            LEFT JOIN actuals ON actuals.year = years.year
            LEFT JOIN budgets ON budgets.year = years.year
            WHERE years.year IS NOT NULL
            ORDER BY years.year
            """
        ).map { row in
            BudgetCombinedSummary(
                yearLabel: String(row.int(named: "year")),
                totalBudget: row.optionalDouble(named: "totalBudget"),
                totalSpend: row.double(named: "totalSpend"),
                totalRemaining: row.optionalDouble(named: "totalRemaining")
            )
        }

        let categorySummaries = try query(
            """
            WITH base AS (
              SELECT
                \(purchaseYearSQL) AS year,
                CASE
                  WHEN lower(trim(COALESCE(budgetType, ''))) IN ('opex', 'operational', 'operational expense', 'operational expenses') THEN 'OpEx'
                  ELSE 'Capital'
                END AS budgetType,
                COALESCE(NULLIF(TRIM(itemType), ''), 'Uncategorized') AS category,
                (unitCost * quantity) AS spend
              FROM inventory_items
            ),
            totals AS (
              SELECT year, budgetType, COALESCE(SUM(spend), 0) AS yearTotal
              FROM base
              GROUP BY 1, 2
            )
            SELECT
              base.year,
              base.budgetType,
              base.category,
              COALESCE(SUM(base.spend), 0) AS totalSpend,
              COUNT(*) AS itemCount,
              COALESCE(AVG(base.spend), 0) AS averageCost,
              CASE
                WHEN totals.yearTotal = 0 THEN 0
                ELSE COALESCE(SUM(base.spend), 0) / totals.yearTotal
              END AS percentOfYear
            FROM base
            LEFT JOIN totals ON totals.year = base.year AND totals.budgetType = base.budgetType
            WHERE base.year IS NOT NULL
            GROUP BY base.year, base.budgetType, base.category, totals.yearTotal
            ORDER BY base.year, CASE base.budgetType WHEN 'Capital' THEN 0 ELSE 1 END, totalSpend DESC, base.category
            """
        ).map { row in
            BudgetCategorySummary(
                year: row.int(named: "year"),
                budgetType: row.string(named: "budgetType"),
                category: row.string(named: "category"),
                totalSpend: row.double(named: "totalSpend"),
                itemCount: row.int(named: "itemCount"),
                averageCost: row.double(named: "averageCost"),
                percentOfYear: row.double(named: "percentOfYear")
            )
        }

        let annualBudgets = try query(
            """
            SELECT
              year,
              budgetType,
              COALESCE(printf('%.2f', allocatedBudget), '') AS allocatedBudget,
              COALESCE(fundCode, '') AS fundCode,
              COALESCE(glCode, '') AS glCode
            FROM annual_budgets
            ORDER BY year, CASE budgetType WHEN 'Capital' THEN 0 ELSE 1 END
            """
        ).map { row in
            AnnualBudgetRecord(
                year: String(row.int(named: "year")),
                budgetType: row.string(named: "budgetType"),
                allocatedBudget: row.string(named: "allocatedBudget"),
                fundCode: row.string(named: "fundCode"),
                glCode: row.string(named: "glCode")
            )
        }

        return BudgetDashboardSnapshot(
            annualSummaries: annualSummaries,
            combinedSummaries: combinedSummaries,
            categorySummaries: categorySummaries,
            annualBudgets: annualBudgets
        )
    }

    func saveAnnualBudgets(_ records: [AnnualBudgetRecord]) throws {
        var uniqueRecords: [String: AnnualBudgetRecord] = [:]
        for record in records {
            let trimmedYear = record.year.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedType = record.budgetType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedYear.isEmpty, !trimmedType.isEmpty else { continue }
            uniqueRecords["\(trimmedYear)|\(trimmedType.lowercased())"] = record
        }

        try withTransaction { db in
            try execute("DELETE FROM annual_budgets", bindings: [], db: db)

            for record in uniqueRecords.values.sorted(by: {
                let lhsYear = Int($0.year.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let rhsYear = Int($1.year.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                if lhsYear == rhsYear {
                    return $0.budgetType.localizedCaseInsensitiveCompare($1.budgetType) == .orderedAscending
                }
                return lhsYear < rhsYear
            }) {
                let trimmedYear = record.year.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let year = Int(trimmedYear) else { continue }
                let trimmedBudget = record.allocatedBudget.trimmingCharacters(in: .whitespacesAndNewlines)
                let amount = Double(trimmedBudget.replacingOccurrences(of: ",", with: ""))
                try execute(
                    """
                    INSERT INTO annual_budgets (year, budgetType, allocatedBudget, fundCode, glCode, updatedAt)
                    VALUES (?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), CURRENT_TIMESTAMP)
                    """,
                    bindings: [
                        .int(year),
                        .text(record.budgetType),
                        amount.map(SQLiteBinding.double) ?? .null,
                        .text(record.fundCode),
                        .text(record.glCode)
                    ],
                    db: db
                )
            }

            try insertAudit(
                action: "edit",
                entityType: "budget",
                entityId: 0,
                details: "Budget configuration updated for \(uniqueRecords.count) annual rows",
                performedBy: NSUserName(),
                db: db
            )
        }
    }

    func stockrooms() throws -> [StockroomRecord] {
        try query(
            """
            SELECT
              s.id,
              s.name,
              COALESCE(s.location, '') AS location,
              COALESCE(s.department, '') AS department,
              COUNT(i.id) AS itemCount,
              COALESCE(SUM(i.quantity), 0) AS totalQuantity,
              COALESCE(SUM(i.unitCost * i.quantity), 0) AS totalValue
            FROM stockrooms s
            LEFT JOIN inventory_items i ON i.stockroomId = s.id
            GROUP BY s.id, s.name, s.location, s.department
            ORDER BY s.name
            """
        ).map { row in
            StockroomRecord(
                id: row.int64(named: "id"),
                name: row.string(named: "name"),
                location: row.string(named: "location"),
                department: row.string(named: "department"),
                itemCount: row.int(named: "itemCount"),
                totalQuantity: row.int(named: "totalQuantity"),
                totalValue: row.double(named: "totalValue")
            )
        }
    }

    func currentUser() throws -> AppUserRecord {
        let username = NSUserName()
        let rows = try query(
            """
            SELECT id, username, COALESCE(role, 'viewer') AS role, COALESCE(displayName, username) AS displayName
            FROM users
            WHERE lower(username) = lower(?)
            LIMIT 1
            """,
            bindings: [.text(username)]
        )

        if let row = rows.first {
            return AppUserRecord(id: row.int64(named: "id"), username: row.string(named: "username"), role: row.string(named: "role"), displayName: row.string(named: "displayName"))
        }

        let userCount = try singleInt("SELECT COUNT(*) FROM users")
        let role = userCount == 0 ? "admin" : "viewer"
        try execute(
            """
            INSERT INTO users (username, displayName, role)
            VALUES (?, ?, ?)
            """,
            bindings: [.text(username), .text(username), .text(role)]
        )

        let inserted = try query(
            """
            SELECT id, username, COALESCE(role, 'viewer') AS role, COALESCE(displayName, username) AS displayName
            FROM users
            WHERE lower(username) = lower(?)
            LIMIT 1
            """,
            bindings: [.text(username)]
        )

        guard let row = inserted.first else {
            return AppUserRecord(id: nil, username: username, role: role, displayName: username)
        }

        return AppUserRecord(id: row.int64(named: "id"), username: row.string(named: "username"), role: row.string(named: "role"), displayName: row.string(named: "displayName"))
    }

    func users() throws -> [AppUserRecord] {
        try query(
            """
            SELECT id, username, COALESCE(role, 'viewer') AS role, COALESCE(displayName, username) AS displayName
            FROM users
            ORDER BY lower(COALESCE(displayName, username)), lower(username)
            """
        ).map { row in
            AppUserRecord(
                id: row.int64(named: "id"),
                username: row.string(named: "username"),
                role: row.string(named: "role"),
                displayName: row.string(named: "displayName")
            )
        }
    }

    func updateUserRole(userID: Int64, role: String) throws {
        let allowedRoles = Set(["admin", "manager", "viewer"])
        guard allowedRoles.contains(role) else {
            throw DatabaseError.stepFailed("Unsupported user role: \(role).")
        }

        try withTransaction { db in
            let current = try query(
                """
                SELECT COALESCE(role, 'viewer') AS role
                FROM users
                WHERE lower(username) = lower(?)
                LIMIT 1
                """,
                bindings: [.text(NSUserName())],
                db: db
            ).first?.string(named: "role") ?? "viewer"
            guard current == "admin" else {
                throw DatabaseError.stepFailed("Only admins can change user roles.")
            }

            try execute(
                """
                UPDATE users
                SET role = ?
                WHERE id = ?
                """,
                bindings: [.text(role), .int64(userID)],
                db: db
            )

            try insertAudit(
                action: "edit",
                entityType: "user",
                entityId: userID,
                details: "Updated user role to \(role)",
                performedBy: NSUserName(),
                db: db
            )
        }
    }

    func createStockroom(name: String, location: String, department: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DatabaseError.stepFailed("Stockroom name is required.")
        }

        let currentUser = try currentUser()
        try execute(
            """
            INSERT INTO stockrooms (name, location, department, createdBy)
            VALUES (?, NULLIF(?, ''), NULLIF(?, ''), ?)
            """,
            bindings: [
                .text(trimmedName),
                .text(location),
                .text(department),
                currentUser.id.map(SQLiteBinding.int64) ?? .null
            ]
        )

        try insertAudit(
            action: "create",
            entityType: "stockroom",
            entityId: 0,
            details: "Created stockroom \(trimmedName)",
            performedBy: currentUser.displayName
        )
    }

    func updateStockroom(id: Int64, name: String, location: String, department: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DatabaseError.stepFailed("Stockroom name is required.")
        }

        try execute(
            """
            UPDATE stockrooms
            SET name = ?, location = NULLIF(?, ''), department = NULLIF(?, '')
            WHERE id = ?
            """,
            bindings: [.text(trimmedName), .text(location), .text(department), .int64(id)]
        )

        try insertAudit(
            action: "edit",
            entityType: "stockroom",
            entityId: id,
            details: "Updated stockroom \(trimmedName)",
            performedBy: NSUserName()
        )
    }

    func deleteStockroom(id: Int64) throws {
        let existing = try query(
            """
            SELECT name
            FROM stockrooms
            WHERE id = ?
            LIMIT 1
            """,
            bindings: [.int64(id)]
        )

        guard let row = existing.first else { return }
        let name = row.string(named: "name")

        try execute(
            """
            UPDATE inventory_items
            SET stockroomId = NULL, updatedAt = CURRENT_TIMESTAMP
            WHERE stockroomId = ?
            """,
            bindings: [.int64(id)]
        )

        try execute("DELETE FROM stockrooms WHERE id = ?", bindings: [.int64(id)])

        try insertAudit(
            action: "delete",
            entityType: "stockroom",
            entityId: id,
            details: "Deleted stockroom \(name)",
            performedBy: NSUserName()
        )
    }

    func updateInventoryItem(_ item: InventoryItemRecord) throws {
        try validateInventoryValues(quantity: item.quantity, qtyReceived: item.qtyReceived, unitCost: item.unitCost)
        try execute(
            """
            UPDATE inventory_items
            SET itemType = ?, description = ?, manufacturer = ?, partNumber = ?, purchaseDate = NULLIF(?, ''),
                vendor = NULLIF(?, ''), unitCost = ?, quantity = ?, qtyReceived = ?, poNumber = NULLIF(?, ''),
                notes = NULLIF(?, ''), budgetType = ?, stockroomId = ?, updatedAt = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            bindings: [
                .text(item.itemType),
                .text(item.description),
                .text(item.manufacturer),
                .text(item.partNumber),
                .text(item.purchaseDate),
                .text(item.vendor),
                .double(item.unitCost),
                .int(item.quantity),
                .int(item.qtyReceived),
                .text(item.poNumber),
                .text(item.notes),
                .text(item.budgetType),
                .optionalInt64(item.stockroomId),
                .int64(item.id)
            ]
        )

        try insertAudit(action: "edit", entityType: "item", entityId: item.id, details: "Updated \(item.partNumber) \(item.description)", performedBy: NSUserName())
    }

    func inventoryItem(id: Int64) throws -> InventoryItemRecord? {
        try query(
            """
            SELECT
              i.id,
              i.itemType,
              i.description,
              i.manufacturer,
              i.partNumber,
              COALESCE(i.purchaseDate, '') AS purchaseDate,
              COALESCE(i.vendor, '') AS vendor,
              i.unitCost,
              i.quantity,
              i.qtyReceived,
              COALESCE(i.poNumber, '') AS poNumber,
              COALESCE(i.notes, '') AS notes,
              i.budgetType,
              i.stockroomId,
              COALESCE(s.name, 'Unassigned') AS stockroomName,
              MAX(i.quantity - COALESCE(d.totalDeployed, 0), 0) AS availableQuantity,
              datetime(i.updatedAt, 'localtime') AS updatedAt
            FROM inventory_items i
            LEFT JOIN stockrooms s ON s.id = i.stockroomId
            LEFT JOIN (
              SELECT inventoryItemId, SUM(qtyDeployed) AS totalDeployed
              FROM deployments
              GROUP BY inventoryItemId
            ) d ON d.inventoryItemId = i.id
            WHERE i.id = ?
            GROUP BY i.id, i.itemType, i.description, i.manufacturer, i.partNumber, i.purchaseDate, i.vendor,
                     i.unitCost, i.quantity, i.qtyReceived, i.poNumber, i.notes, i.budgetType, i.stockroomId,
                     s.name, i.updatedAt
            LIMIT 1
            """,
            bindings: [.int64(id)]
        ).map { row in
            InventoryItemRecord(
                id: row.int64(named: "id"),
                itemType: row.string(named: "itemType"),
                description: row.string(named: "description"),
                manufacturer: row.string(named: "manufacturer"),
                partNumber: row.string(named: "partNumber"),
                purchaseDate: row.string(named: "purchaseDate"),
                vendor: row.string(named: "vendor"),
                unitCost: row.double(named: "unitCost"),
                quantity: row.int(named: "quantity"),
                qtyReceived: row.int(named: "qtyReceived"),
                poNumber: row.string(named: "poNumber"),
                notes: row.string(named: "notes"),
                budgetType: row.string(named: "budgetType"),
                stockroomId: row.optionalInt64(named: "stockroomId"),
                stockroomName: row.string(named: "stockroomName"),
                availableQuantity: row.int(named: "availableQuantity"),
                updatedAt: row.string(named: "updatedAt")
            )
        }.first
    }

    func returnDeployment(id: Int64) throws {
        try withTransaction { db in
            let rows = try query(
                """
                SELECT id, partNumber, COALESCE(description, '') AS description, COALESCE(deployedTo, '') AS deployedTo
                FROM deployments
                WHERE id = ?
                LIMIT 1
                """,
                bindings: [.int64(id)],
                db: db
            )

            guard let existing = rows.first else { return }

            try execute("DELETE FROM deployments WHERE id = ?", bindings: [.int64(id)], db: db)
            try insertAudit(
                action: "return",
                entityType: "deployment",
                entityId: id,
                details: "Returned \(existing.string(named: "partNumber")) from \(existing.string(named: "deployedTo"))",
                performedBy: NSUserName(),
                db: db
            )
        }
    }

    func importFromExcel(inventoryItems: [ImportedInventoryItem], deployments: [ImportedDeployment]) throws -> ImportSummary {
        try withTransaction { db in
            let existingInventory = try query(
                """
                SELECT
                  id,
                  lower(trim(COALESCE(partNumber, ''))) AS partNumber,
                  lower(trim(COALESCE(poNumber, ''))) AS poNumber,
                  lower(trim(COALESCE(vendor, ''))) AS vendor,
                  lower(trim(COALESCE(description, ''))) AS description,
                  lower(trim(COALESCE(itemType, ''))) AS itemType,
                  lower(trim(COALESCE(manufacturer, ''))) AS manufacturer,
                  COALESCE(purchaseDate, '') AS purchaseDate,
                  quantity,
                  qtyReceived,
                  printf('%.2f', unitCost) AS unitCost,
                  COALESCE(notes, '') AS notes,
                  COALESCE(budgetType, 'Capital') AS budgetType
                FROM inventory_items
                """,
                db: db
            )

            var inventoryByKey: [String: SQLiteRow] = [:]
            for row in existingInventory.sorted(by: { $0.int64(named: "id") < $1.int64(named: "id") }) {
                let key = inventorySyncKey(
                    partNumber: row.string(named: "partNumber"),
                    poNumber: row.string(named: "poNumber"),
                    vendor: row.string(named: "vendor"),
                    description: row.string(named: "description")
                )
                inventoryByKey[key] = row
            }

            var inventoryImported = 0
            var inventoryUpdated = 0
            var inventorySkipped = 0

            for item in inventoryItems {
                try validateInventoryValues(quantity: item.quantity, qtyReceived: item.qtyReceived, unitCost: item.unitCost)
                let key = inventorySyncKey(
                    partNumber: item.partNumber,
                    poNumber: item.poNumber,
                    vendor: item.vendor,
                    description: item.description
                )

                if let existingRow = inventoryByKey[key] {
                    let normalizedBudgetType = item.budgetType.isEmpty ? "Capital" : item.budgetType
                    let hasChanges =
                        existingRow.string(named: "itemType") != normalized(item.itemType) ||
                        existingRow.string(named: "description") != normalized(item.description) ||
                        existingRow.string(named: "manufacturer") != normalized(item.manufacturer) ||
                        existingRow.string(named: "partNumber") != normalized(item.partNumber) ||
                        normalized(existingRow.string(named: "purchaseDate")) != normalized(item.purchaseDate) ||
                        existingRow.string(named: "vendor") != normalized(item.vendor) ||
                        existingRow.string(named: "unitCost") != String(format: "%.2f", item.unitCost) ||
                        existingRow.int(named: "quantity") != item.quantity ||
                        existingRow.int(named: "qtyReceived") != item.qtyReceived ||
                        existingRow.string(named: "poNumber") != normalized(item.poNumber) ||
                        normalized(existingRow.string(named: "notes")) != normalized(item.notes) ||
                        normalized(existingRow.string(named: "budgetType")) != normalized(normalizedBudgetType)

                    if hasChanges {
                        try execute(
                            """
                            UPDATE inventory_items
                            SET itemType = ?, description = ?, manufacturer = ?, partNumber = ?, purchaseDate = NULLIF(?, ''),
                                vendor = NULLIF(?, ''), unitCost = ?, quantity = ?, qtyReceived = ?, poNumber = NULLIF(?, ''),
                                notes = NULLIF(?, ''), budgetType = ?, updatedAt = CURRENT_TIMESTAMP
                            WHERE id = ?
                            """,
                            bindings: [
                                .text(item.itemType), .text(item.description), .text(item.manufacturer), .text(item.partNumber),
                                .text(item.purchaseDate), .text(item.vendor), .double(item.unitCost), .int(item.quantity),
                                .int(item.qtyReceived), .text(item.poNumber), .text(item.notes), .text(normalizedBudgetType),
                                .int64(existingRow.int64(named: "id"))
                            ],
                            db: db
                        )
                        inventoryUpdated += 1
                    } else {
                        inventorySkipped += 1
                    }
                    continue
                }

                try execute(
                    """
                    INSERT INTO inventory_items
                    (itemType, description, manufacturer, partNumber, purchaseDate, vendor, unitCost, quantity, qtyReceived, poNumber, notes, budgetType)
                    VALUES (?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?)
                    """,
                    bindings: [
                        .text(item.itemType), .text(item.description), .text(item.manufacturer), .text(item.partNumber),
                        .text(item.purchaseDate), .text(item.vendor), .double(item.unitCost), .int(item.quantity),
                        .int(item.qtyReceived), .text(item.poNumber), .text(item.notes), .text(item.budgetType.isEmpty ? "Capital" : item.budgetType)
                    ],
                    db: db
                )

                let insertedID = Int64(sqlite3_last_insert_rowid(db))
                if let insertedRow = try query(
                    """
                    SELECT
                      id,
                      lower(trim(COALESCE(partNumber, ''))) AS partNumber,
                      lower(trim(COALESCE(poNumber, ''))) AS poNumber,
                      lower(trim(COALESCE(vendor, ''))) AS vendor,
                      lower(trim(COALESCE(description, ''))) AS description,
                      lower(trim(COALESCE(itemType, ''))) AS itemType,
                      lower(trim(COALESCE(manufacturer, ''))) AS manufacturer,
                      COALESCE(purchaseDate, '') AS purchaseDate,
                      quantity,
                      qtyReceived,
                      printf('%.2f', unitCost) AS unitCost,
                      COALESCE(notes, '') AS notes,
                      COALESCE(budgetType, 'Capital') AS budgetType
                    FROM inventory_items
                    WHERE id = ?
                    LIMIT 1
                    """,
                    bindings: [.int64(insertedID)],
                    db: db
                ).first {
                    inventoryByKey[key] = insertedRow
                }
                inventoryImported += 1
            }

            let existingDeployments = try query(
                """
                SELECT
                  id,
                  inventoryItemId,
                  lower(trim(COALESCE(partNumber, ''))) AS partNumber,
                  lower(trim(COALESCE(description, ''))) AS description,
                  qtyDeployed,
                  lower(trim(COALESCE(deployedTo, ''))) AS deployedTo,
                  lower(trim(COALESCE(deployedBy, ''))) AS deployedBy,
                  date(deployedDate) AS deployedDate,
                  lower(trim(COALESCE(deployedLocation, ''))) AS deployedLocation,
                  lower(trim(COALESCE(itemType, ''))) AS itemType,
                  lower(trim(COALESCE(manufacturer, ''))) AS manufacturer,
                  COALESCE(notes, '') AS notes
                FROM deployments
                """,
                db: db
            )

            var deploymentsByKey: [String: SQLiteRow] = [:]
            for row in existingDeployments.sorted(by: { $0.int64(named: "id") < $1.int64(named: "id") }) {
                let key = deploymentSyncKey(
                    partNumber: row.string(named: "partNumber"),
                    description: row.string(named: "description"),
                    deployedTo: row.string(named: "deployedTo"),
                    deployedDate: row.string(named: "deployedDate")
                )
                deploymentsByKey[key] = row
            }

            var deploymentsImported = 0
            var deploymentsUpdated = 0
            var deploymentsSkipped = 0

            for deployment in deployments {
                let key = deploymentSyncKey(
                    partNumber: deployment.partNumber,
                    description: deployment.description,
                    deployedTo: deployment.deployedTo,
                    deployedDate: deployment.deployedDate
                )
                let matchedInventoryID = try matchingInventoryItemID(partNumber: deployment.partNumber, description: deployment.description, db: db)

                if let existingRow = deploymentsByKey[key] {
                    let hasChanges =
                        existingRow.optionalInt64(named: "inventoryItemId") != matchedInventoryID ||
                        existingRow.string(named: "itemType") != normalized(deployment.itemType) ||
                        existingRow.string(named: "description") != normalized(deployment.description) ||
                        existingRow.string(named: "manufacturer") != normalized(deployment.manufacturer) ||
                        existingRow.string(named: "partNumber") != normalized(deployment.partNumber) ||
                        existingRow.int(named: "qtyDeployed") != deployment.qtyDeployed ||
                        existingRow.string(named: "deployedTo") != normalized(deployment.deployedTo) ||
                        existingRow.string(named: "deployedBy") != normalized(deployment.deployedBy) ||
                        normalized(existingRow.string(named: "deployedDate")) != normalized(deployment.deployedDate) ||
                        existingRow.string(named: "deployedLocation") != normalized(deployment.deployedLocation) ||
                        normalized(existingRow.string(named: "notes")) != normalized(deployment.notes)

                    if hasChanges {
                        try execute(
                            """
                            UPDATE deployments
                            SET inventoryItemId = ?, itemType = ?, description = ?, manufacturer = ?, partNumber = ?, qtyDeployed = ?,
                                deployedTo = ?, deployedBy = ?, deployedDate = NULLIF(?, ''), deployedLocation = NULLIF(?, ''), notes = NULLIF(?, '')
                            WHERE id = ?
                            """,
                            bindings: [
                                .optionalInt64(matchedInventoryID), .text(deployment.itemType), .text(deployment.description), .text(deployment.manufacturer),
                                .text(deployment.partNumber), .int(deployment.qtyDeployed), .text(deployment.deployedTo), .text(deployment.deployedBy),
                                .text(deployment.deployedDate), .text(deployment.deployedLocation), .text(deployment.notes),
                                .int64(existingRow.int64(named: "id"))
                            ],
                            db: db
                        )
                        deploymentsUpdated += 1
                    } else {
                        deploymentsSkipped += 1
                    }
                    continue
                }

                try execute(
                    """
                    INSERT INTO deployments
                    (inventoryItemId, itemType, description, manufacturer, partNumber, qtyDeployed, deployedTo, deployedBy, deployedDate, deployedLocation, notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''))
                    """,
                    bindings: [
                        .optionalInt64(matchedInventoryID), .text(deployment.itemType), .text(deployment.description), .text(deployment.manufacturer),
                        .text(deployment.partNumber), .int(deployment.qtyDeployed), .text(deployment.deployedTo), .text(deployment.deployedBy),
                        .text(deployment.deployedDate), .text(deployment.deployedLocation), .text(deployment.notes)
                    ],
                    db: db
                )

                let insertedID = Int64(sqlite3_last_insert_rowid(db))
                if let insertedRow = try query(
                    """
                    SELECT
                      id,
                      inventoryItemId,
                      lower(trim(COALESCE(partNumber, ''))) AS partNumber,
                      lower(trim(COALESCE(description, ''))) AS description,
                      qtyDeployed,
                      lower(trim(COALESCE(deployedTo, ''))) AS deployedTo,
                      lower(trim(COALESCE(deployedBy, ''))) AS deployedBy,
                      date(deployedDate) AS deployedDate,
                      lower(trim(COALESCE(deployedLocation, ''))) AS deployedLocation,
                      lower(trim(COALESCE(itemType, ''))) AS itemType,
                      lower(trim(COALESCE(manufacturer, ''))) AS manufacturer,
                      COALESCE(notes, '') AS notes
                    FROM deployments
                    WHERE id = ?
                    LIMIT 1
                    """,
                    bindings: [.int64(insertedID)],
                    db: db
                ).first {
                    deploymentsByKey[key] = insertedRow
                }
                deploymentsImported += 1
            }

            if inventoryImported > 0 || inventoryUpdated > 0 || deploymentsImported > 0 || deploymentsUpdated > 0 || inventorySkipped > 0 || deploymentsSkipped > 0 {
                try insertAudit(
                    action: "import",
                    entityType: "item",
                    entityId: 0,
                    details: "Excel sync: \(inventoryImported) inventory inserted, \(inventoryUpdated) inventory updated, \(inventorySkipped) inventory unchanged | \(deploymentsImported) deployments inserted, \(deploymentsUpdated) deployments updated, \(deploymentsSkipped) deployments unchanged",
                    performedBy: NSUserName(),
                    db: db
                )
            }

            return ImportSummary(
                inventoryImported: inventoryImported,
                inventoryUpdated: inventoryUpdated,
                inventorySkipped: inventorySkipped,
                deploymentsImported: deploymentsImported,
                deploymentsUpdated: deploymentsUpdated,
                deploymentsSkipped: deploymentsSkipped
            )
        }
    }

    func deploy(_ draft: DeploymentDraft) throws {
        guard draft.qtyDeployed > 0 else {
            throw DatabaseError.stepFailed("Deployment quantity must be greater than zero.")
        }

        try withTransaction { db in
            let available = try availableQuantity(for: draft.inventoryItemId, db: db)
            guard available >= draft.qtyDeployed else {
                throw DatabaseError.stepFailed("Only \(available) item(s) are available for \(draft.partNumber). Refresh inventory and try again.")
            }

            try execute(
                """
                INSERT INTO deployments
                (inventoryItemId, stockroomId, itemType, description, manufacturer, partNumber, qtyDeployed, deployedTo, deployedBy, deployedDate, deployedLocation, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''))
                """,
                bindings: [
                    .int64(draft.inventoryItemId),
                    .optionalInt64(draft.stockroomId),
                    .text(draft.itemType),
                    .text(draft.description),
                    .text(draft.manufacturer),
                    .text(draft.partNumber),
                    .int(draft.qtyDeployed),
                    .text(draft.deployedTo),
                    .text(draft.deployedBy),
                    .text(draft.deployedDate),
                    .text(draft.deployedLocation),
                    .text(draft.notes)
                ],
                db: db
            )

            try insertAudit(
                action: "deploy",
                entityType: "deployment",
                entityId: draft.inventoryItemId,
                details: "Deployed \(draft.qtyDeployed)x \(draft.partNumber) to \(draft.deployedTo)",
                performedBy: draft.deployedBy,
                db: db
            )
        }
    }

    func removeDuplicateInventoryItems() throws -> Int {
        let duplicates = try query(
            """
            SELECT id
            FROM (
                SELECT
                  id,
                  ROW_NUMBER() OVER (
                    PARTITION BY
                      CASE WHEN trim(COALESCE(poNumber, '')) <> '' THEN lower(trim(poNumber)) || '|' || lower(trim(partNumber))
                           ELSE lower(trim(partNumber)) || '|' || quantity || '|' || printf('%.2f', unitCost)
                      END
                    ORDER BY createdAt ASC, id ASC
                  ) AS rowNumber
                FROM inventory_items
            )
            WHERE rowNumber > 1
            """
        )

        let ids = duplicates.map { $0.int64(named: "id") }
        for id in ids {
            try execute("DELETE FROM inventory_items WHERE id = ?", bindings: [.int64(id)])
        }

        if !ids.isEmpty {
            try insertAudit(action: "delete", entityType: "item", entityId: 0, details: "Removed \(ids.count) duplicate inventory rows", performedBy: NSUserName())
        }

        return ids.count
    }

    func remainingInventorySnapshots() throws -> [RemainingInventoryUpdate] {
        try query(
            """
            SELECT
              TRIM(i.partNumber) AS partNumber,
              COALESCE(TRIM(i.poNumber), '') AS poNumber,
              COALESCE(i.budgetType, 'Capital') AS budgetType,
              CASE
                WHEN i.quantity - COALESCE(d.totalDeployed, 0) > 0 THEN i.quantity - COALESCE(d.totalDeployed, 0)
                ELSE 0
              END AS remaining
            FROM inventory_items i
            LEFT JOIN (
              SELECT inventoryItemId, SUM(qtyDeployed) AS totalDeployed
              FROM deployments
              GROUP BY inventoryItemId
            ) d ON d.inventoryItemId = i.id
            WHERE TRIM(COALESCE(i.partNumber, '')) <> ''
            ORDER BY lower(TRIM(i.partNumber)), lower(COALESCE(TRIM(i.poNumber), '')), i.id
            """
        ).map { row in
            RemainingInventoryUpdate(
                partNumber: row.string(named: "partNumber"),
                poNumber: row.string(named: "poNumber"),
                budgetType: row.string(named: "budgetType"),
                remaining: row.int(named: "remaining")
            )
        }
    }

    func inventoryCSV() throws -> String {
        let header = "Item Type,Description,Manufacturer,Part Number,Purchase Date,Vendor,Unit Cost,Quantity,Qty Received,Available,PO Number,Budget Type,Stockroom,Notes"
        let lines = try inventoryItems().map { item in
            [
                item.itemType,
                item.description,
                item.manufacturer,
                item.partNumber,
                item.purchaseDate,
                item.vendor,
                String(format: "%.2f", item.unitCost),
                "\(item.quantity)",
                "\(item.qtyReceived)",
                "\(item.availableQuantity)",
                item.poNumber,
                item.budgetType,
                item.stockroomName,
                item.notes
            ].map(csvEscape).joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\n")
    }

    func insertParsedItems(_ items: [ParsedImportItem]) throws -> ParsedImportSaveResult {
        let existingInventory = try query(
            """
            SELECT
              lower(trim(COALESCE(partNumber, ''))) AS partNumber,
              lower(trim(COALESCE(poNumber, ''))) AS poNumber,
              quantity,
              printf('%.2f', unitCost) AS unitCost
            FROM inventory_items
            """
        )

        var inventoryFingerprints = Set(existingInventory.map { row in
            inventoryFingerprint(
                partNumber: row.string(named: "partNumber"),
                poNumber: row.string(named: "poNumber"),
                quantity: row.int(named: "quantity"),
                unitCostString: row.string(named: "unitCost")
            )
        })

        var insertedItems: [ParsedImportItem] = []
        var skippedCount = 0
        for item in items {
            try validateInventoryValues(quantity: item.quantity, qtyReceived: item.qtyReceived, unitCost: item.unitCost)
            let fingerprint = inventoryFingerprint(
                partNumber: item.partNumber,
                poNumber: item.poNumber,
                quantity: item.quantity,
                unitCostString: String(format: "%.2f", item.unitCost)
            )

            if inventoryFingerprints.contains(fingerprint) {
                skippedCount += 1
                continue
            }

            try execute(
                """
                INSERT INTO inventory_items
                (itemType, description, manufacturer, partNumber, purchaseDate, vendor, unitCost, quantity, qtyReceived, poNumber, notes, sourcePDF, budgetType)
                VALUES (?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?)
                """,
                bindings: [
                    .text(item.itemType),
                    .text(item.description),
                    .text(item.manufacturer),
                    .text(item.partNumber),
                    .text(item.purchaseDate),
                    .text(item.vendor),
                    .double(item.unitCost),
                    .int(item.quantity),
                    .int(item.qtyReceived),
                    .text(item.poNumber),
                    .text(item.notes),
                    .text(item.sourceFile),
                    .text(item.budgetType)
                ]
            )
            inventoryFingerprints.insert(fingerprint)
            insertedItems.append(item)
        }

        if !insertedItems.isEmpty || skippedCount > 0 {
            let firstPO = items.first?.poNumber.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let firstSource = items.first?.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sourceLabel = !firstPO.isEmpty ? "PO \(firstPO)" : (!firstSource.isEmpty ? firstSource : "PDF batch")
            try insertAudit(
                action: "import",
                entityType: "item",
                entityId: 0,
                details: "PDF import: \(insertedItems.count) inserted, \(skippedCount) skipped | Source: \(sourceLabel)",
                performedBy: NSUserName()
            )
        }

        return ParsedImportSaveResult(insertedItems: insertedItems, skippedCount: skippedCount)
    }

    private func insertAudit(action: String, entityType: String, entityId: Int64, details: String, performedBy: String) throws {
        try execute(
            """
            INSERT INTO audit_log (action, entityType, entityId, details, performedBy)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [.text(action), .text(entityType), .int64(entityId), .text(details), .text(performedBy)]
        )
    }

    private func insertAudit(action: String, entityType: String, entityId: Int64, details: String, performedBy: String, db: OpaquePointer?) throws {
        try execute(
            """
            INSERT INTO audit_log (action, entityType, entityId, details, performedBy)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [.text(action), .text(entityType), .int64(entityId), .text(details), .text(performedBy)],
            db: db
        )
    }

    private func singleInt(_ sql: String) throws -> Int {
        try singleRow(sql).int(at: 0)
    }

    private func validateInventoryValues(quantity: Int, qtyReceived: Int, unitCost: Double) throws {
        guard quantity >= 0 else {
            throw DatabaseError.stepFailed("Quantity cannot be negative.")
        }
        guard qtyReceived >= 0 else {
            throw DatabaseError.stepFailed("Quantity received cannot be negative.")
        }
        guard qtyReceived <= quantity else {
            throw DatabaseError.stepFailed("Quantity received cannot exceed quantity.")
        }
        guard unitCost >= 0 else {
            throw DatabaseError.stepFailed("Unit cost cannot be negative.")
        }
    }

    private func matchingInventoryItemID(partNumber: String, description: String, db: OpaquePointer?) throws -> Int64? {
        let rows = try query(
            """
            SELECT id
            FROM inventory_items
            WHERE lower(trim(COALESCE(partNumber, ''))) = lower(trim(?))
            ORDER BY
              CASE WHEN lower(trim(COALESCE(description, ''))) = lower(trim(?)) THEN 0 ELSE 1 END,
              id ASC
            LIMIT 1
            """,
            bindings: [.text(partNumber), .text(description)],
            db: db
        )
        return rows.first?.int64(named: "id")
    }

    private func availableQuantity(for inventoryItemId: Int64) throws -> Int {
        try singleRow(
            """
            SELECT
              MAX(i.quantity - COALESCE(d.totalDeployed, 0), 0) AS availableQuantity
            FROM inventory_items i
            LEFT JOIN (
              SELECT inventoryItemId, SUM(qtyDeployed) AS totalDeployed
              FROM deployments
              GROUP BY inventoryItemId
            ) d ON d.inventoryItemId = i.id
            WHERE i.id = ?
            """,
            bindings: [.int64(inventoryItemId)]
        ).int(named: "availableQuantity")
    }

    private func availableQuantity(for inventoryItemId: Int64, db: OpaquePointer?) throws -> Int {
        try query(
            """
            SELECT
              MAX(i.quantity - COALESCE(d.totalDeployed, 0), 0) AS availableQuantity
            FROM inventory_items i
            LEFT JOIN (
              SELECT inventoryItemId, SUM(qtyDeployed) AS totalDeployed
              FROM deployments
              GROUP BY inventoryItemId
            ) d ON d.inventoryItemId = i.id
            WHERE i.id = ?
            """,
            bindings: [.int64(inventoryItemId)],
            db: db
        ).first?.int(named: "availableQuantity") ?? 0
    }

    private func singleRow(_ sql: String, bindings: [SQLiteBinding] = []) throws -> SQLiteRow {
        guard let row = try query(sql, bindings: bindings).first else {
            throw DatabaseError.stepFailed("No rows returned for query.")
        }
        return row
    }

    private func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [SQLiteRow] {
        try accessQueue.sync {
            let db = try openDatabase(readOnly: true)
            defer { sqlite3_close(db) }
            return try query(sql, bindings: bindings, db: db)
        }
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding]) throws {
        try accessQueue.sync {
            let db = try openDatabase(readOnly: false)
            defer { sqlite3_close(db) }
            try execute(sql, bindings: bindings, db: db)
        }
    }

    private func withTransaction<T>(_ work: (OpaquePointer?) throws -> T) throws -> T {
        try accessQueue.sync {
            let db = try openDatabase(readOnly: false)
            defer { sqlite3_close(db) }
            guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
                throw DatabaseError.stepFailed(lastMessage(from: db))
            }
            do {
                let value = try work(db)
                guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                    throw DatabaseError.stepFailed(lastMessage(from: db))
                }
                return value
            } catch {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw error
            }
        }
    }

    private func openDatabase(readOnly: Bool) throws -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
            throw DatabaseError.openFailed(lastMessage(from: db))
        }
        configureConnection(db)
        return db
    }

    private func query(_ sql: String, bindings: [SQLiteBinding] = [], db: OpaquePointer?) throws -> [SQLiteRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(SQLiteRow(statement: statement))
                continue
            }
            if result == SQLITE_DONE {
                return rows
            }
            throw DatabaseError.stepFailed(lastMessage(from: db))
        }
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding], db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastMessage(from: db))
        }
    }

    private func configureConnection(_ db: OpaquePointer?) {
        sqlite3_busy_timeout(db, busyTimeoutMilliseconds)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer?) throws {
        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            case .int(let value):
                sqlite3_bind_int(statement, position, Int32(value))
            case .int64(let value):
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case .double(let value):
                sqlite3_bind_double(statement, position, value)
            case .null:
                sqlite3_bind_null(statement, position)
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func formatInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func lastMessage(from db: OpaquePointer?) -> String {
        if let cString = sqlite3_errmsg(db) {
            String(cString: cString)
        } else {
            "Unknown SQLite error"
        }
    }

    private func inventoryFingerprint(partNumber: String, poNumber: String, quantity: Int, unitCostString: String) -> String {
        let normalizedPart = normalized(partNumber)
        let normalizedPO = normalized(poNumber)
        if !normalizedPO.isEmpty {
            return "po|\(normalizedPO)|\(normalizedPart)"
        }
        return "quote|\(normalizedPart)|\(quantity)|\(unitCostString)"
    }

    private func inventorySyncKey(partNumber: String, poNumber: String, vendor: String, description: String) -> String {
        let normalizedPart = normalized(partNumber)
        let normalizedPO = normalized(poNumber)
        if !normalizedPO.isEmpty {
            return "po|\(normalizedPO)|\(normalizedPart)"
        }
        return [
            "inventory",
            normalizedPart,
            normalized(vendor),
            normalized(description)
        ].joined(separator: "|")
    }

    private func deploymentFingerprint(partNumber: String, qty: Int, deployedTo: String, deployedBy: String, deployedDate: String, deployedLocation: String) -> String {
        [
            normalized(partNumber),
            "\(qty)",
            normalized(deployedTo),
            normalized(deployedBy),
            normalized(deployedDate),
            normalized(deployedLocation)
        ].joined(separator: "|")
    }

    private func deploymentSyncKey(partNumber: String, description: String, deployedTo: String, deployedDate: String) -> String {
        [
            normalized(partNumber),
            normalized(description),
            normalized(deployedTo),
            normalized(deployedDate)
        ].joined(separator: "|")
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteBinding {
    case text(String)
    case int(Int)
    case int64(Int64)
    case double(Double)
    case null

    static func optionalInt64(_ value: Int64?) -> SQLiteBinding {
        if let value { .int64(value) } else { .null }
    }
}

struct SQLiteRow {
    private let names: [String: Int32]
    private let values: [Int32: SQLiteValue]

    init(statement: OpaquePointer?) {
        let columnCount = sqlite3_column_count(statement)
        var names: [String: Int32] = [:]
        var values: [Int32: SQLiteValue] = [:]

        for index in 0..<columnCount {
            let name = String(cString: sqlite3_column_name(statement, index))
            names[name] = index
            values[index] = SQLiteValue(statement: statement, index: index)
        }

        self.names = names
        self.values = values
    }

    func string(named name: String) -> String {
        guard let index = names[name], let value = values[index] else { return "" }
        return value.stringValue
    }

    func int(named name: String) -> Int {
        guard let index = names[name], let value = values[index] else { return 0 }
        return value.intValue
    }

    func int64(named name: String) -> Int64 {
        guard let index = names[name], let value = values[index] else { return 0 }
        return value.int64Value
    }

    func optionalInt64(named name: String) -> Int64? {
        guard let index = names[name], let value = values[index], !value.isNull else { return nil }
        return value.int64Value
    }

    func double(named name: String) -> Double {
        guard let index = names[name], let value = values[index] else { return 0 }
        return value.doubleValue
    }

    func optionalDouble(named name: String) -> Double? {
        guard let index = names[name], let value = values[index], !value.isNull else { return nil }
        return value.doubleValue
    }

    func int(at index: Int32) -> Int {
        values[index]?.intValue ?? 0
    }
}

struct SQLiteValue {
    let rawString: String?
    let int64Value: Int64
    let doubleValue: Double
    let isNull: Bool

    init(statement: OpaquePointer?, index: Int32) {
        isNull = sqlite3_column_type(statement, index) == SQLITE_NULL
        if let cString = sqlite3_column_text(statement, index) {
            rawString = String(cString: cString)
        } else {
            rawString = nil
        }
        int64Value = sqlite3_column_int64(statement, index)
        doubleValue = sqlite3_column_double(statement, index)
    }

    var stringValue: String { rawString ?? "" }
    var intValue: Int { Int(int64Value) }
}
