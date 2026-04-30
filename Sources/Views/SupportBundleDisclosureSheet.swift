import SwiftUI

struct SupportBundleDisclosureSheet: View {
    let createBundle: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Create Support Bundle")
                        .font(.title2.weight(.semibold))
                    Text("Inventory Manager will create a zip file you can review before sending.")
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button(action: cancel) {
                    Label("Cancel", systemImage: "xmark")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                disclosureRow(systemImage: "checkmark.circle.fill", title: "Included", body: "App version, macOS version, item counts, recent in-app errors, recent Inventory Manager logs, and matching crash reports.")
                disclosureRow(systemImage: "xmark.circle.fill", title: "Not included", body: "The SQLite database, Excel workbook contents, PDF imports, CSV exports, and inventory attachments are not copied into the bundle.")
                disclosureRow(systemImage: "folder", title: "Reviewable", body: "The zip is revealed in Finder after it is created, so you can inspect it before sharing.")
            }
            .frostedPanel()

            HStack {
                Spacer()
                Button(action: createBundle) {
                    Label("Create Bundle", systemImage: "shippingbox.and.arrow.backward")
                }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.blue)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(AppTheme.appBackground)
    }

    private func disclosureRow(systemImage: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(systemImage == "xmark.circle.fill" ? AppTheme.rose : AppTheme.teal)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }
}
