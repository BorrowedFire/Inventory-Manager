import SwiftUI

struct ImportPreviewPanel: View {
    let preview: ImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import Preview")
                        .font(.headline)
                    Text(preview.summary)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if preview.hasConflicts {
                    Label("Review conflicts before importing", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Table(preview.rows.prefix(200).map { $0 }) {
                TableColumn("Type") { row in Text(row.kind) }
                    .width(min: 90, ideal: 110)
                TableColumn("Action") { row in
                    Text(row.action)
                        .foregroundStyle(row.isConflict ? .orange : .primary)
                }
                .width(min: 110, ideal: 140)
                TableColumn("Identity") { row in Text(row.identity) }
                    .width(min: 130, ideal: 180)
                TableColumn("Details") { row in Text(row.detail) }
            }
            .frame(minHeight: 180, idealHeight: 260)

            if preview.rows.count > 200 {
                Text("Showing first 200 of \(preview.rows.count) preview rows.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(12)
        .background(AppTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
