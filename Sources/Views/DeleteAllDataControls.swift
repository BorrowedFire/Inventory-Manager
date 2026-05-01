import Foundation
import SwiftUI

struct DeleteAllDataControl: View {
    @ObservedObject var model: AppModel
    var afterReset: () -> Void = {}

    @State private var showInitialConfirmation = false
    @State private var showPhraseConfirmation = false
    @State private var showFinalConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.rose)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.rose.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Danger Zone")
                        .font(.headline)
                    Text("Start over by deleting the current app-managed workspace data and resetting saved preferences.")
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                dangerDetail("Current database", value: model.databaseURL.path)
                dangerDetail("Application Support", value: AppModel.applicationSupportDirectoryURL().appendingPathComponent("InventoryManager", isDirectory: true).path)
                if !model.excelInventoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dangerDetail("Excel workbook", value: "Disconnected only. The workbook file is not deleted.")
                }
            }

            Button(role: .destructive) {
                showInitialConfirmation = true
            } label: {
                Label("Delete All App Data", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.rose)
        }
        .confirmationDialog(
            "Start fresh and delete all app data?",
            isPresented: $showInitialConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                showPhraseConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is the first confirmation. The next step requires typing \(AppModel.deleteAllDataConfirmationPhrase).")
        }
        .sheet(isPresented: $showPhraseConfirmation) {
            DeleteAllDataConfirmationSheet(
                databasePath: model.databaseURL.path,
                appSupportPath: AppModel.applicationSupportDirectoryURL().appendingPathComponent("InventoryManager", isDirectory: true).path,
                excelWorkbookPath: model.excelInventoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model.excelInventoryPath,
                confirmationPhrase: AppModel.deleteAllDataConfirmationPhrase,
                continueAction: {
                    showPhraseConfirmation = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showFinalConfirmation = true
                    }
                },
                cancelAction: {
                    showPhraseConfirmation = false
                }
            )
        }
        .confirmationDialog(
            "Final confirmation",
            isPresented: $showFinalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Data and Start Fresh", role: .destructive) {
                Task {
                    await model.deleteAllAppDataAndStartFresh()
                    afterReset()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves app-managed data to the Trash where macOS allows it, resets preferences, and creates a fresh default workspace.")
        }
    }

    private func dangerDetail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .tracking(1.1)
            Text(value)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct DeleteAllDataConfirmationSheet: View {
    let databasePath: String
    let appSupportPath: String
    let excelWorkbookPath: String?
    let confirmationPhrase: String
    let continueAction: () -> Void
    let cancelAction: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typedPhrase = ""

    private var phraseMatches: Bool {
        typedPhrase.trimmingCharacters(in: .whitespacesAndNewlines) == confirmationPhrase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trash.slash.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.rose)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.rose.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Type to Confirm")
                        .font(.title2.bold())
                    Text("This action starts the app over with a blank default workspace.")
                        .foregroundStyle(AppTheme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                deletionLine("Deletes current database", detail: databasePath)
                deletionLine("Deletes app support data", detail: appSupportPath)
                deletionLine("Resets saved preferences", detail: "Workspace name, database path, Excel connection, onboarding, and theme preference.")
                if let excelWorkbookPath {
                    deletionLine("Does not delete Excel workbook", detail: excelWorkbookPath)
                }
            }
            .padding(12)
            .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Type \(confirmationPhrase) to continue.")
                    .font(.caption.weight(.semibold))
                TextField(confirmationPhrase, text: $typedPhrase)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    cancelAction()
                    dismiss()
                }

                Spacer()

                Button(role: .destructive) {
                    continueAction()
                    dismiss()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.rose)
                .disabled(!phraseMatches)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(AppTheme.appBackground)
    }

    private func deletionLine(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.rose)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}
