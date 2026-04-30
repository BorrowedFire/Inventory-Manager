import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.inventorymanager.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let database = Logger(subsystem: subsystem, category: "Database")
    static let excelSync = Logger(subsystem: subsystem, category: "ExcelSync")
    static let importFlow = Logger(subsystem: subsystem, category: "Import")
    static let updates = Logger(subsystem: subsystem, category: "Updates")
    static let support = Logger(subsystem: subsystem, category: "Support")
}
