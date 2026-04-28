import Foundation

@main
struct MigrationSmokeRunner {
    static func main() throws {
        let dbPath = "/tmp/inventory-manager-migration-smoke/LegacyInventory.sqlite"
        let dbURL = URL(fileURLWithPath: dbPath)
        let service = DatabaseService(databaseURL: dbURL)
        try service.ensureSchema()

        let inventory = try service.inventoryItems()
        let deployments = try service.deployments()
        let stockrooms = try service.stockrooms()
        let user = try service.currentUser()

        precondition(inventory.count == 1, "expected one migrated inventory row")
        precondition(deployments.count == 1, "expected one migrated deployment row")
        precondition(stockrooms.count == 1, "expected one migrated stockroom")
        precondition(!user.username.isEmpty, "expected current user/bootstrap user")
        precondition(inventory[0].partNumber == "LEGACY-001", "legacy inventory row changed unexpectedly")
        precondition(deployments[0].partNumber == "LEGACY-001", "legacy deployment row changed unexpectedly")
        precondition(deployments[0].inventoryItemId == inventory[0].id, "deployment should reconcile to inventory item")

        let migrations = try service.schemaMigrationNames()
        precondition(migrations.contains("initial_public_schema"), "missing initial schema migration")
        precondition(migrations.contains("native_mac_product_polish"), "missing native polish migration")
        precondition(migrations.contains("release_safety_backups_and_import_preview"), "missing release safety migration")

        print("migration_smoke=ok")
    }
}
