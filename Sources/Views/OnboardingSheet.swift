import SwiftUI

struct OnboardingSheet: View {
    @ObservedObject var model: AppModel
    let createStockroom: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to \(model.appDisplayName)")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                    Text("Use this setup guide to confirm the workspace name, database, stockrooms, and spreadsheet behavior before the team starts working in the app.")
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
                    title: "1. Review the workspace name",
                    body: "The app name and organization label appear throughout the UI and exports, so set them to match the team using this workspace."
                )
                onboardingCallout(
                    title: "2. Choose the database location",
                    body: "Create a fresh database for a new team, attach an existing database, or use the default local workspace location."
                )
                onboardingCallout(
                    title: "3. Create stockrooms",
                    body: "Stockrooms make inventory location filters and deployment context much more useful once items start arriving."
                )
                onboardingCallout(
                    title: "4. Decide how Excel should work",
                    body: "If the spreadsheet is still part of the workflow, connect it here. The app can read manual workbook changes on launch and also write updates back to Excel."
                )
            }

            HStack {
                Button {
                    model.selectedSection = .settings
                    close()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)

                Button {
                    model.selectedSection = .stockrooms
                    createStockroom()
                } label: {
                    Label("Create First Stockroom", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Skip for Now") {
                    close()
                }
            }
        }
        .padding(28)
        .frame(width: 760)
        .background(AppTheme.appBackground)
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
