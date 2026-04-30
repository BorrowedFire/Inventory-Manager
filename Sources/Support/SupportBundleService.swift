import Foundation

struct SupportBundleContext: Encodable, Sendable {
    let generatedAt: String
    let appVersion: String
    let appBuild: String
    let bundleIdentifier: String
    let macOSVersion: String
    let databaseFileName: String
    let databaseDirectory: String
    let hasExcelWorkbook: Bool
    let excelWorkbookFileName: String?
    let currentUserRole: String
    let inventoryCount: Int
    let deploymentCount: Int
    let stockroomCount: Int
    let backupCount: Int
    let lastVisibleError: String?
    let lastImportSummary: String?
    let recentErrors: [String]
}

enum SupportBundleService {
    private static let maxLogBytes = 2_000_000

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    static func makeContext(
        databaseURL: URL,
        excelInventoryPath: String,
        currentUserRole: String,
        inventoryCount: Int,
        deploymentCount: Int,
        stockroomCount: Int,
        backupCount: Int,
        lastVisibleError: String?,
        lastImportSummary: String?,
        recentErrors: [String]
    ) -> SupportBundleContext {
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main
        let excelURL = excelInventoryPath.isEmpty ? nil : URL(fileURLWithPath: excelInventoryPath)

        return SupportBundleContext(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            macOSVersion: processInfo.operatingSystemVersionString,
            databaseFileName: databaseURL.lastPathComponent,
            databaseDirectory: databaseURL.deletingLastPathComponent().lastPathComponent,
            hasExcelWorkbook: excelURL != nil,
            excelWorkbookFileName: excelURL?.lastPathComponent,
            currentUserRole: currentUserRole,
            inventoryCount: inventoryCount,
            deploymentCount: deploymentCount,
            stockroomCount: stockroomCount,
            backupCount: backupCount,
            lastVisibleError: lastVisibleError,
            lastImportSummary: lastImportSummary,
            recentErrors: recentErrors
        )
    }

    static func createSupportBundle(context: SupportBundleContext) throws -> URL {
        let fileManager = FileManager.default
        let supportRoot = try supportBundlesDirectory()
        let bundleName = "InventoryManager-Support-\(timestampString())"
        let bundleDirectory = supportRoot.appendingPathComponent(bundleName, isDirectory: true)
        let zipURL = supportRoot.appendingPathComponent("\(bundleName).zip")

        if fileManager.fileExists(atPath: bundleDirectory.path) {
            try fileManager.removeItem(at: bundleDirectory)
        }
        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }

        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        try writeDiagnostics(context, to: bundleDirectory)
        try writeRecentErrors(context.recentErrors, to: bundleDirectory)
        try writeUnifiedLogs(to: bundleDirectory)
        try copyRecentCrashReports(to: bundleDirectory)
        try zipDirectory(bundleDirectory, to: zipURL)

        try? fileManager.removeItem(at: bundleDirectory)
        return zipURL
    }

    private static func supportBundlesDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = appSupport
            .appendingPathComponent("InventoryManager", isDirectory: true)
            .appendingPathComponent("Support Bundles", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeDiagnostics(_ context: SupportBundleContext, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(context)
        try data.write(to: directory.appendingPathComponent("diagnostics.json"), options: .atomic)
    }

    private static func writeRecentErrors(_ recentErrors: [String], to directory: URL) throws {
        let content = recentErrors.isEmpty ? "No recent in-app errors recorded.\n" : recentErrors.joined(separator: "\n")
        try content.write(to: directory.appendingPathComponent("recent-errors.log"), atomically: true, encoding: .utf8)
    }

    private static func writeUnifiedLogs(to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--style",
            "compact",
            "--last",
            "45m",
            "--predicate",
            #"process == "InventoryManager" OR process == "Inventory Manager" OR subsystem == "com.inventorymanager.app""#
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var logData = output
        if process.terminationStatus != 0, !errorOutput.isEmpty {
            logData = errorOutput
        }
        if logData.count > maxLogBytes {
            logData = Data(logData.suffix(maxLogBytes))
        }
        try logData.write(to: directory.appendingPathComponent("recent-unified.log"), options: .atomic)
    }

    private static func copyRecentCrashReports(to directory: URL) throws {
        let fileManager = FileManager.default
        let diagnosticsDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let reports = try? fileManager.contentsOfDirectory(
            at: diagnosticsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let crashDirectory = directory.appendingPathComponent("Crash Reports", isDirectory: true)
        let matchingReports = reports
            .filter { url in
                let name = url.lastPathComponent
                return (name.contains("InventoryManager") || name.contains("Inventory Manager")) &&
                    (name.hasSuffix(".crash") || name.hasSuffix(".ips"))
            }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(5)

        guard !matchingReports.isEmpty else { return }
        try fileManager.createDirectory(at: crashDirectory, withIntermediateDirectories: true)
        for report in matchingReports {
            try? fileManager.copyItem(at: report, to: crashDirectory.appendingPathComponent(report.lastPathComponent))
        }
    }

    private static func zipDirectory(_ directory: URL, to zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", directory.path, zipURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8) ?? "Failed to create support bundle zip."
            throw NSError(domain: "SupportBundleService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
