import SwiftUI

struct DeploymentSheetModel: Identifiable {
    let id = UUID()
    let item: InventoryItemRecord
}

struct InventoryEditSheet: View {
    let item: InventoryItemRecord
    let stockrooms: [StockroomRecord]
    let itemTypeOptions: [String]
    let onSave: (InventoryItemRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: InventoryItemRecord

    init(item: InventoryItemRecord, stockrooms: [StockroomRecord], itemTypeOptions: [String], onSave: @escaping (InventoryItemRecord) -> Void) {
        self.item = item
        self.stockrooms = stockrooms
        self.itemTypeOptions = itemTypeOptions
        self.onSave = onSave
        _draft = State(initialValue: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.id == 0 ? "New Inventory Item" : "Edit Inventory Item")
                        .font(.title2.bold())
                    Text(draft.description.isEmpty ? "Create a manually-entered inventory row." : draft.description)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if draft.availableQuantity > 0 {
                    ItemTypeIconView(itemType: draft.itemType, size: 18)
                }
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            }

            InventoryEditor(item: $draft, stockrooms: stockrooms, itemTypeOptions: itemTypeOptions) {
                onSave(draft)
                dismiss()
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(AppTheme.appBackground)
    }
}

struct InventoryEditor: View {
    @Binding var item: InventoryItemRecord
    let stockrooms: [StockroomRecord]
    let itemTypeOptions: [String]
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Item Type")
                        .font(.caption.weight(.semibold))
                    Picker("Item Type", selection: $item.itemType) {
                        ForEach(itemTypeOptions, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                labeledField("Description", text: $item.description)
                labeledField("Manufacturer", text: $item.manufacturer)
                labeledField("Part Number", text: $item.partNumber)
                labeledField("Purchase Date", text: $item.purchaseDate, prompt: "YYYY-MM-DD or MM/DD/YYYY")
                labeledField("Vendor", text: $item.vendor)
                labeledField("PO Number", text: $item.poNumber)
            }

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unit Cost")
                        .font(.caption.weight(.semibold))
                    TextField("0", value: $item.unitCost, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quantity")
                        .font(.caption.weight(.semibold))
                    TextField("0", value: $item.quantity, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Received")
                        .font(.caption.weight(.semibold))
                    TextField("0", value: $item.qtyReceived, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Picker("Budget", selection: $item.budgetType) {
                Text("Capital").tag("Capital")
                Text("OpEx").tag("OpEx")
            }

            Picker("Stockroom", selection: Binding(
                get: { item.stockroomId ?? -1 },
                set: { item.stockroomId = $0 == -1 ? nil : $0 }
            )) {
                Text("Unassigned").tag(Int64(-1))
                ForEach(stockrooms) { stockroom in
                    Text(stockroom.name).tag(stockroom.id)
                }
            }

            Text("Notes")
                .font(.caption.weight(.semibold))
            TextEditor(text: $item.notes)
                .frame(height: 120)
                .padding(8)
                .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                        .stroke(AppTheme.stroke, lineWidth: 1)
                )

            Button(action: onSave) {
                Label(item.id == 0 ? "Create Item" : "Save Changes", systemImage: item.id == 0 ? "plus" : "checkmark.circle")
            }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
                .disabled(item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
            TextField(prompt ?? label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct DeploySheet: View {
    let item: InventoryItemRecord
    let currentUser: String
    let onDeploy: (Int, String, String, String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var qty = 1
    @State private var deployedTo = ""
    @State private var deployedBy = ""
    @State private var deployedDate = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
    @State private var location = "Office"
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deploy \(item.description)")
                        .font(.title2.bold())
                    Text("\(item.partNumber) • \(item.availableQuantity) available")
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            }

            Stepper("Quantity: \(qty)", value: $qty, in: 1...max(1, item.availableQuantity))
            labeled("Deployed To", text: $deployedTo)
            labeled("Deployed By", text: $deployedBy)
            labeled("Deployment Date", text: $deployedDate, prompt: "YYYY-MM-DD or MM/DD/YYYY")
            labeled("Location", text: $location)

            Text("Notes")
                .font(.caption.weight(.semibold))
            TextEditor(text: $notes)
                .frame(height: 100)
                .padding(8)
                .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                        .stroke(AppTheme.stroke, lineWidth: 1)
                )

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button {
                    onDeploy(qty, deployedTo, deployedBy.isEmpty ? currentUser : deployedBy, deployedDate, location, notes)
                } label: {
                    Label("Deploy", systemImage: "arrowshape.turn.up.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.teal)
                .disabled(deployedTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(AppTheme.appBackground)
        .onAppear {
            deployedBy = currentUser
        }
    }

    private func labeled(_ label: String, text: Binding<String>, prompt: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
            TextField(prompt ?? label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct ParsedImportEditor: View {
    @Binding var item: ParsedImportItem
    let stockrooms: [StockroomRecord]
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.sourceFile)
                    .font(.headline)
                Text(item.description.isEmpty ? "Review before saving" : item.description)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Label("Remove Row", systemImage: "trash")
                }
                Picker("Budget", selection: $item.budgetType) {
                    Text("Capital").tag("Capital")
                    Text("OpEx").tag("OpEx")
                }
                .frame(width: 140)
                Picker("Stockroom", selection: Binding(
                    get: { item.stockroomId ?? -1 },
                    set: { item.stockroomId = $0 == -1 ? nil : $0 }
                )) {
                    Text("Unassigned").tag(Int64(-1))
                    ForEach(stockrooms) { stockroom in
                        Text(stockroom.name).tag(stockroom.id)
                    }
                }
                .frame(width: 170)
            }

            HStack {
                editorField("Item Type", text: $item.itemType)
                editorField("Manufacturer", text: $item.manufacturer)
                editorField("Part Number", text: $item.partNumber)
            }

            editorField("Description", text: $item.description)

            HStack {
                editorField("Vendor", text: $item.vendor)
                editorField("PO Number", text: $item.poNumber)
                editorField("Purchase Date", text: $item.purchaseDate, prompt: "YYYY-MM-DD or MM/DD/YYYY")
            }

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unit Cost")
                        .font(.caption.weight(.semibold))
                    TextField("0", value: $item.unitCost, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quantity")
                        .font(.caption.weight(.semibold))
                    TextField("0", value: $item.quantity, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Received")
                        .font(.caption.weight(.semibold))
                    TextField("0", value: $item.qtyReceived, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Notes")
                .font(.caption.weight(.semibold))
            TextEditor(text: $item.notes)
                .frame(height: 76)
                .padding(8)
                .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                        .stroke(AppTheme.stroke, lineWidth: 1)
                )
        }
        .frostedPanel()
    }

    private func editorField(_ label: String, text: Binding<String>, prompt: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
            TextField(prompt ?? label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct StockroomEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StockroomDraft
    let onSave: (StockroomDraft) -> Void

    init(draft: StockroomDraft, onSave: @escaping (StockroomDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text(draft.id == nil ? "New Stockroom" : "Edit Stockroom")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            }

            field("Name", text: $draft.name)
            field("Location", text: $draft.location)
            field("Department", text: $draft.department)

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button {
                    onSave(draft)
                } label: {
                    Label(draft.id == nil ? "Create" : "Save", systemImage: draft.id == nil ? "plus" : "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(AppTheme.appBackground)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
