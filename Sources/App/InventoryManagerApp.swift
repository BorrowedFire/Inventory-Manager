import SwiftUI
import AppKit

@main
struct InventoryManagerApp: App {
    @StateObject private var model = AppModel()

    init() {
        Self.applyBundledAppIcon()
    }

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .frame(minWidth: 1450, minHeight: 920)
        }
        .defaultSize(width: 1500, height: 960)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Workspace") {
                    Task { await model.load() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Import from Excel…") {
                    Task { await model.importFromExcel() }
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.excelInventoryPath.isEmpty)

                Button("Sync Remaining Inventory") {
                    Task {
                        do {
                            try await model.syncRemainingInventoryIfNeeded()
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(model.excelInventoryPath.isEmpty)
            }

            CommandMenu("Inventory") {
                Button("Show Dashboard") { model.selectedSection = .dashboard }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Show Inventory") { model.selectedSection = .inventory }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Show Deployments") { model.selectedSection = .deployments }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Show Stockrooms") { model.selectedSection = .stockrooms }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Show Settings") { model.selectedSection = .settings }
                    .keyboardShortcut(",", modifiers: [.command])

                Divider()

                Button("Remove Duplicate Inventory Rows") {
                    Task { await model.removeDuplicateInventoryItems() }
                }
            }
        }

        Settings {
            AppSettingsView(model: model)
        }
    }

    private static func applyBundledAppIcon() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"),
            Bundle.main.resourceURL?.appendingPathComponent("Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"),
            Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns")
        ]

        for url in candidates.compactMap({ $0 }) {
            guard let image = NSImage(contentsOf: url) else { continue }
            NSApplication.shared.applicationIconImage = image
            break
        }
    }
}
