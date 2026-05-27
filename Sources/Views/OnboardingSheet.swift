import SwiftUI

struct OnboardingSheet: View {
    @ObservedObject var model: AppModel
    let createStockroom: () -> Void
    let addManualItem: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set Up \(model.appDisplayName)")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                    Text("Create the workspace, name it, add the first stockroom, then import existing Excel or CSV inventory when you are ready.")
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button("Close") {
                    close()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.setupChecklist) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(item.isComplete ? AppTheme.teal : AppTheme.muted)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                }
            }
            .frostedPanel()

            VStack(alignment: .leading, spacing: 12) {
                onboardingCallout(
                    title: "1. Create the workspace",
                    body: "Use the default local database, choose a location, or attach an existing Inventory Manager database before importing data."
                )
                onboardingCallout(
                    title: "2. Name the workspace",
                    body: "Set the workspace name and organization label so reports, exports, and support bundles identify the right team."
                )
                onboardingCallout(
                    title: "3. Create the first stockroom",
                    body: "Choose the room or cage where imported inventory should land first. Additional stockrooms can be added later."
                )
                onboardingCallout(
                    title: "4. Import existing inventory",
                    body: "Bring in an Excel workbook or CSV once the workspace and first stockroom exist, or start blank and import later."
                )
            }

            adaptiveOnboardingActions {
                Button {
                    Task { await model.createDatabaseAtDefaultLocation() }
                } label: {
                    Label("Create Workspace", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)

                Button {
                    model.selectedSection = .settings
                    close()
                } label: {
                    Label("Name Workspace", systemImage: "textformat")
                }
                .buttonStyle(.bordered)

                Button {
                    model.selectedSection = .stockrooms
                    createStockroom()
                } label: {
                    Label("Create First Stockroom", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    addManualItem()
                } label: {
                    Label("Add Items Manually", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)

                Button {
                    chooseExcelWorkbook()
                } label: {
                    Label(model.excelInventoryPath.isEmpty ? "Choose Excel" : "Preview Excel", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)

                Button {
                    importCSVFile()
                } label: {
                    Label("Import CSV", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Button {
                    model.acknowledgeSpreadsheetSetup()
                    close()
                } label: {
                    Label("Start Blank", systemImage: "forward")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(width: 760)
        .background(AppTheme.appBackground)
    }

    private func adaptiveOnboardingActions<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10, content: content)
            VStack(alignment: .leading, spacing: 10, content: content)
        }
    }

    private func chooseExcelWorkbook() {
        if let url = FileDialogs.chooseExcelFile() {
            model.setExcelInventoryPath(url.path)
            Task { await model.previewExcelImport() }
        }
    }

    private func importCSVFile() {
        if let url = FileDialogs.chooseCSVFile() {
            Task { await model.importFromCSV(url: url) }
        }
    }

    private func onboardingCallout(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.row, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
}
