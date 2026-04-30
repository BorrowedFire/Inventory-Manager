import SwiftUI
import AppKit
import UniformTypeIdentifiers

private final class PDFDropCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var inventoryEditorItem: InventoryItemRecord?
    @State private var inventoryToDelete: InventoryItemRecord?
    @State private var deploymentToReturn: DeploymentRecord?
    @State private var deploymentToDelete: DeploymentRecord?
    @State private var deploymentDraft: DeploymentSheetModel?
    @State private var stockroomDraft: StockroomDraft?
    @State private var stockroomToDelete: StockroomRecord?
    @State private var budgetToDelete: AnnualBudgetRecord?
    @State private var databaseToRestore: URL?
    @State private var showOnboarding = false
    @State private var showInstallGuide = false
    @State private var budgetCategoryTypeSelection = "Capital"
    @State private var budgetYearDraft = ""
    @State private var confirmClearParsedPDFs = false
    @State private var showSupportBundleDisclosure = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Database Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh workspace")

                Button {
                    FileDialogs.revealInFinder(model.databaseURL)
                } label: {
                    Label("Reveal Database", systemImage: "folder")
                }
                .help("Reveal the current SQLite database in Finder")

                Button {
                    model.selectedSection = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open workspace settings")
            }
        }
        .task {
            await model.load()
            showInstallGuide = InstallHelper.shouldPromptForApplicationsInstall
            showOnboarding = model.shouldPresentOnboarding && !showInstallGuide
        }
        .onChange(of: model.commandRequestID) { _, _ in
            switch model.commandRequest {
            case .newInventoryItem:
                inventoryEditorItem = AppModel.blankInventoryItem(stockroomId: model.selectedStockroomID)
                model.selectedSection = .inventory
            case .createStockroom:
                stockroomDraft = StockroomDraft()
                model.selectedSection = .stockrooms
            case .reportProblem:
                showSupportBundleDisclosure = true
            case .none:
                break
            }
        }
        .sheet(isPresented: $showInstallGuide, onDismiss: {
            showOnboarding = model.shouldPresentOnboarding
        }) {
            InstallGuideSheet(
                moveToApplications: {
                    do {
                        let targetURL = try InstallHelper.moveToApplications()
                        InstallHelper.relaunchApplication(at: targetURL)
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                },
                continueHere: {
                    showInstallGuide = false
                }
            )
        }
        .sheet(isPresented: $showSupportBundleDisclosure) {
            SupportBundleDisclosureSheet(
                createBundle: {
                    showSupportBundleDisclosure = false
                    Task { await model.createSupportBundle() }
                },
                cancel: {
                    showSupportBundleDisclosure = false
                }
            )
        }
        .sheet(item: $inventoryEditorItem) { item in
            InventoryEditSheet(
                item: item,
                stockrooms: model.stockrooms,
                itemTypeOptions: model.editableItemTypeOptions
            ) { updatedItem in
                Task {
                    if item.id == 0 {
                        await model.createInventory(updatedItem)
                    } else {
                        await model.saveInventory(updatedItem, originalItem: item)
                    }
                    inventoryEditorItem = nil
                }
            }
        }
        .sheet(item: $deploymentDraft) { draft in
            DeploySheet(
                item: draft.item,
                currentUser: model.currentUser.displayName,
                onDeploy: { qty, deployedTo, deployedBy, deployedDate, location, notes in
                    Task {
                        await model.deploy(
                            item: draft.item,
                            qty: qty,
                            deployedTo: deployedTo,
                            deployedBy: deployedBy,
                            deployedDate: deployedDate,
                            location: location,
                            notes: notes
                        )
                        deploymentDraft = nil
                    }
                }
            )
        }
        .sheet(item: $stockroomDraft) { draft in
            StockroomEditorSheet(draft: draft) { updatedDraft in
                Task {
                    if updatedDraft.id == nil {
                        await model.createStockroom(name: updatedDraft.name, location: updatedDraft.location, department: updatedDraft.department)
                    } else {
                        await model.updateStockroom(updatedDraft)
                    }
                    stockroomDraft = nil
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet(
                model: model,
                createStockroom: {
                    stockroomDraft = StockroomDraft()
                    showOnboarding = false
                },
                close: {
                    model.dismissOnboarding()
                    showOnboarding = false
                }
            )
        }
        .confirmationDialog(
            "Delete inventory item?",
            isPresented: Binding(
                get: { inventoryToDelete != nil },
                set: { if !$0 { inventoryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Inventory Item", role: .destructive) {
                guard let item = inventoryToDelete else { return }
                Task {
                    await model.deleteInventoryItem(id: item.id)
                    inventoryToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the inventory row and any deployment rows linked to it.")
        }
        .confirmationDialog(
            "Delete stockroom?",
            isPresented: Binding(
                get: { stockroomToDelete != nil },
                set: { if !$0 { stockroomToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Stockroom", role: .destructive) {
                guard let stockroom = stockroomToDelete else { return }
                Task {
                    await model.deleteStockroom(id: stockroom.id)
                    stockroomToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items in this stockroom will become unassigned.")
        }
        .confirmationDialog(
            "Delete saved budget?",
            isPresented: Binding(
                get: { budgetToDelete != nil },
                set: { if !$0 { budgetToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Budget", role: .destructive) {
                guard let budget = budgetToDelete else { return }
                Task {
                    await model.deleteAnnualBudget(record: budget)
                    budgetToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(budgetToDelete.map { "Remove the saved \($0.year) \($0.budgetType) budget target." } ?? "")
        }
        .confirmationDialog(
            "Restore database?",
            isPresented: Binding(
                get: { databaseToRestore != nil },
                set: { if !$0 { databaseToRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Database", role: .destructive) {
                guard let url = databaseToRestore else { return }
                Task {
                    await model.restoreDatabase(from: url)
                    databaseToRestore = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(databaseToRestore.map { "Replace the current database with \($0.lastPathComponent). The current database will be backed up first." } ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedSection) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.appDisplayName)
                        .font(.headline)
                        .textCase(nil)
                    Text(model.organizationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .padding(.vertical, 6)
            }

            Section("Workspace") {
                LabeledContent("User", value: model.currentUser.displayName)
                LabeledContent("Role", value: model.currentUser.role.replacingOccurrences(of: "_", with: " ").capitalized)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(model.appDisplayName)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .dashboard:
            dashboardView
        case .budgets:
            budgetsView
        case .inventory:
            inventoryView
        case .deployments:
            deploymentsView
        case .importPDFs:
            importPlaceholder
        case .stockrooms:
            stockroomsView
        case .settings:
            settingsView
        }
    }

    private var dashboardView: some View {
        SectionShell(
            title: "Inventory at a glance",
            eyebrow: AppSection.dashboard.eyebrow,
            subtitle: nil
        ) {
            if model.isWorkspaceEmpty {
                workspaceSetupPanel
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                ForEach(model.dashboard.stats) { stat in
                    Button {
                        openDashboardStat(stat)
                    } label: {
                        StatCardView(stat: stat)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    panelHeading(
                        title: "Budget Status",
                        subtitle: "Annual budget vs. actual spend."
                    )
                    ForEach(model.budgetDashboard.annualSummaries.prefix(4)) { budget in
                        Button {
                            model.selectedSection = .budgets
                        } label: {
                            dashboardYearBudgetRow(budget)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frostedPanel()

                VStack(alignment: .leading, spacing: 14) {
                    panelHeading(
                        title: "Top Vendors",
                        subtitle: "Spend by supplier."
                    )
                    ForEach(Array(model.dashboard.vendors.enumerated()), id: \.element.id) { index, vendor in
                        Button {
                            model.openInventoryDrilldown(sort: .unitCostHigh, vendor: vendor.vendor)
                        } label: {
                            dashboardVendorRow(vendor, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frostedPanel()
            }

            VStack(alignment: .leading, spacing: 12) {
                panelHeading(
                    title: "Recent Activity",
                    subtitle: "Recent imports, edits, returns, and deletes."
                )
                ForEach(model.dashboard.activity) { entry in
                    Button {
                        openActivityEntry(entry)
                    } label: {
                        activityRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frostedPanel()
        }
    }

    private var budgetsView: some View {
        SectionShell(
            title: "Budget intelligence",
            eyebrow: AppSection.budgets.eyebrow,
            subtitle: "Budget targets, actual spend, and category mix by year."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                panelHeading(
                    title: "Budget Dashboard",
                    subtitle: "Capital and OpEx by year with remaining balance and status."
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        budgetSummaryHeader
                        ForEach(model.budgetDashboard.annualSummaries) { summary in
                            budgetSummaryRow(summary)
                            Divider()
                        }
                    }
                }
                .frostedPanel()

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        panelHeading(
                            title: "Combined Summary",
                            subtitle: "Total budget, spend, and remaining by year."
                        )
                        ForEach(model.budgetDashboard.combinedSummaries) { summary in
                            combinedBudgetRow(summary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frostedPanel()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            panelHeading(
                                title: "Budget by Category",
                                subtitle: "Category analysis based on inventory purchases."
                            )
                            Spacer()
                            Picker("Budget Type", selection: $budgetCategoryTypeSelection) {
                                Text("Capital").tag("Capital")
                                Text("OpEx").tag("OpEx")
                            }
                            .frame(width: 140)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(groupedBudgetCategories, id: \.year) { group in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(group.year) \(group.typeLabel) SPENDING")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(AppTheme.blue)
                                        budgetCategoryHeader
                                        ForEach(group.rows) { row in
                                            budgetCategoryRow(row)
                                        }
                                    }
                                    .padding(.bottom, 12)
                                }
                            }
                        }
                        if groupedBudgetCategories.isEmpty {
                            Text("No \(budgetCategoryTypeSelection) purchases are mapped yet. Add inventory rows with purchase dates, item types, quantities, and costs to populate this view.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frostedPanel()
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        panelHeading(
                            title: "Budget Configuration",
                            subtitle: "Add budget years, then edit targets, fund codes, and GL codes for this workspace."
                        )
                        Spacer()
                        HStack(spacing: 8) {
                            TextField("Year", text: $budgetYearDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 84)
                            Button("Add Year") {
                                model.addBudgetYear(budgetYearDraft)
                                budgetYearDraft = ""
                            }
                        }
                        Button("Save Budget Targets") {
                            Task { await model.saveAnnualBudgets() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.blue)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            budgetConfigHeader
                            ForEach($model.annualBudgetRecords) { $record in
                                budgetConfigRow($record)
                            }
                        }
                    }
                }
                .frostedPanel()
            }
        }
    }

    private var inventoryView: some View {
        SectionShell(
            title: "Inventory workspace",
            eyebrow: AppSection.inventory.eyebrow,
            subtitle: "Create, search, filter, edit, deploy, and export inventory."
        ) {
            HStack(spacing: 16) {
                TextField("Search inventory", text: $model.inventorySearch)
                    .textFieldStyle(.roundedBorder)
                Text("\(model.filteredInventory.count) rows")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Button("New Item") {
                    inventoryEditorItem = AppModel.blankInventoryItem(stockroomId: model.selectedStockroomID)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
                Button("Deployments") {
                    model.openDeploymentsDrilldown()
                }
                Button("Refresh") {
                    Task { await model.load() }
                }
                Button("Export CSV") {
                    if let url = FileDialogs.chooseCSVSaveURL(defaultName: "Inventory Export.csv") {
                        Task { await model.exportInventoryCSV(to: url) }
                    }
                }
                Button("Reset") {
                    model.resetInventoryFilters()
                }
            }

            if !activeInventoryFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeInventoryFilters, id: \.self) { filter in
                            Text(filter)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.blue.opacity(0.10), in: Capsule())
                                .foregroundStyle(AppTheme.blue)
                        }
                    }
                }
            }

            inventoryTable
                .frame(minHeight: 460)
                .frostedPanel()
        }
    }

    private var deploymentsView: some View {
        SectionShell(
            title: "Deployment ledger",
            eyebrow: AppSection.deployments.eyebrow,
            subtitle: "Deployment ledger with active and returned history."
        ) {
            HStack(spacing: 16) {
                TextField("Search deployments", text: $model.deploymentSearch)
                    .textFieldStyle(.roundedBorder)
                Text("\(model.filteredDeployments.count) ledger rows")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Button("Refresh") {
                    Task { await model.load() }
                }
            }

            if !activeDeploymentFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeDeploymentFilters, id: \.self) { filter in
                            Text(filter)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.blue.opacity(0.10), in: Capsule())
                                .foregroundStyle(AppTheme.blue)
                        }
                    }
                }
            }

            deploymentTable
                .frame(minHeight: 460)
                .frostedPanel()
        }
        .confirmationDialog(
            "Return deployment?",
            isPresented: Binding(
                get: { deploymentToReturn != nil },
                set: { if !$0 { deploymentToReturn = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mark Returned") {
                guard let deploymentToReturn else { return }
                Task {
                    await model.returnDeployment(id: deploymentToReturn.id)
                    self.deploymentToReturn = nil
                }
            }
            .disabled(deploymentToReturn?.isReturned == true)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deploymentToReturn.map { "Mark \($0.description) as returned while keeping it in deployment history." } ?? "")
        }
        .confirmationDialog(
            "Delete deployment?",
            isPresented: Binding(
                get: { deploymentToDelete != nil },
                set: { if !$0 { deploymentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Deployment", role: .destructive) {
                guard let deployment = deploymentToDelete else { return }
                Task {
                    await model.deleteDeployment(id: deployment.id)
                    deploymentToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the deployment row. Use Mark Returned if you want to keep deployment history.")
        }
    }

    private var inventoryTable: some View {
        Table(model.filteredInventory) {
            TableColumn("Type") { item in
                HStack(spacing: 8) {
                    ItemTypeIconView(itemType: item.itemType, size: 14)
                    Text(item.itemType)
                }
            }
            .width(min: 110, ideal: 130)

            TableColumn("Item") { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.description)
                        .lineLimit(1)
                    Text(item.partNumber.isEmpty ? "No part number" : item.partNumber)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
            }
            .width(min: 260, ideal: 340)

            TableColumn("Vendor", value: \.vendor)
                .width(min: 110, ideal: 140)
            TableColumn("PO", value: \.poNumber)
                .width(min: 90, ideal: 120)
            TableColumn("Received") { item in
                Text("\(item.qtyReceived)/\(item.quantity)")
                    .monospacedDigit()
            }
            .width(80)
            TableColumn("Available") { item in
                Text("\(item.availableQuantity)")
                    .monospacedDigit()
                    .foregroundStyle(item.availableQuantity == 0 ? AppTheme.rose : AppTheme.teal)
            }
            .width(82)
            TableColumn("Unit Cost") { item in
                Text(currency(item.unitCost))
                    .monospacedDigit()
            }
            .width(100)
            TableColumn("Stockroom", value: \.stockroomName)
                .width(min: 120, ideal: 160)
            TableColumn("Actions") { item in
                HStack(spacing: 8) {
                    Button("Edit") {
                        inventoryEditorItem = item
                    }
                    Button("Deploy") {
                        deploymentDraft = DeploymentSheetModel(item: item)
                    }
                    .disabled(item.availableQuantity <= 0)
                    Button("Delete", role: .destructive) {
                        inventoryToDelete = item
                    }
                }
                .buttonStyle(.borderless)
            }
            .width(190)
        }
    }

    private var deploymentTable: some View {
        Table(model.filteredDeployments) {
            TableColumn("Type") { deployment in
                HStack(spacing: 8) {
                    ItemTypeIconView(itemType: deployment.itemType, size: 14)
                    Text(deployment.itemType)
                }
            }
            .width(min: 110, ideal: 130)

            TableColumn("Item") { deployment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(deployment.description)
                        .lineLimit(1)
                    Text(deployment.partNumber.isEmpty ? "No part number" : deployment.partNumber)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
            }
            .width(min: 260, ideal: 340)

            TableColumn("Qty") { deployment in
                Text("\(deployment.qtyDeployed)")
                    .monospacedDigit()
            }
            .width(56)
            TableColumn("Deployed To", value: \.deployedTo)
                .width(min: 140, ideal: 180)
            TableColumn("Deployed By", value: \.deployedBy)
                .width(min: 120, ideal: 160)
            TableColumn("Date", value: \.deployedDate)
                .width(min: 110, ideal: 130)
            TableColumn("Location", value: \.deployedLocation)
                .width(min: 120, ideal: 160)
            TableColumn("Status") { deployment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(deployment.statusLabel)
                        .foregroundStyle(deployment.isReturned ? AppTheme.muted : AppTheme.teal)
                    if deployment.isReturned {
                        Text(deployment.returnedAt)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
            .width(min: 110, ideal: 150)
            TableColumn("Actions") { deployment in
                HStack(spacing: 8) {
                    Button("Mark Returned") {
                        deploymentToReturn = deployment
                    }
                    .disabled(deployment.isReturned)
                    Button("Delete", role: .destructive) {
                        deploymentToDelete = deployment
                    }
                }
                .buttonStyle(.borderless)
            }
            .width(140)
        }
    }

    private var stockroomsView: some View {
        SectionShell(
            title: "Stockroom map",
            eyebrow: AppSection.stockrooms.eyebrow,
            subtitle: "Room-by-room inventory, quantity, and value."
        ) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Stockrooms")
                            .font(.title3.bold())
                        Spacer()
                        Button("New Stockroom") {
                            stockroomDraft = StockroomDraft()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.blue)
                    }
                    ForEach(model.stockrooms) { stockroom in
                        Button {
                            model.selectedStockroomID = stockroom.id
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(stockroom.name)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.text)
                                Text("\(stockroom.location) • \(stockroom.department)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                                HStack {
                                    Text("\(stockroom.itemCount) records")
                                    Spacer()
                                    Text(currency(stockroom.totalValue))
                                        .monospacedDigit()
                                }
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            }
                            .padding(16)
                            .background(stockroom.id == model.selectedStockroomID ? AppTheme.gold.opacity(0.16) : Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 300, alignment: .topLeading)
                .frostedPanel()

                VStack(alignment: .leading, spacing: 14) {
                    if let stockroom = model.stockrooms.first(where: { $0.id == model.selectedStockroomID }) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(stockroom.name)
                                    .font(.title2.bold())
                                Text("\(stockroom.location.isEmpty ? "No location" : stockroom.location) • \(stockroom.department.isEmpty ? "No department" : stockroom.department)")
                                    .foregroundStyle(AppTheme.muted)
                                Text("\(stockroom.totalQuantity) total units • \(currency(stockroom.totalValue))")
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            HStack {
                                Button("Edit") {
                                    stockroomDraft = StockroomDraft(id: stockroom.id, name: stockroom.name, location: stockroom.location, department: stockroom.department)
                                }
                                Button("Delete", role: .destructive) {
                                    stockroomToDelete = stockroom
                                }
                            }
                        }
                        HStack {
                            Text("\(model.selectedStockroomItems.count) records in this stockroom")
                                .font(.headline)
                            Spacer()
                            Button("Open in Inventory") {
                                model.openInventoryDrilldown(stockroom: stockroom.name)
                            }
                            Button("New Item Here") {
                                inventoryEditorItem = AppModel.blankInventoryItem(stockroomId: stockroom.id)
                            }
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(model.selectedStockroomItems, id: \.id) { item in
                                    HStack {
                                        HStack(alignment: .top, spacing: 12) {
                                            ItemTypeIconView(itemType: item.itemType, size: 16)
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 8) {
                                                    Text(item.description)
                                                        .font(.headline)
                                                    Text(item.itemType)
                                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                        .foregroundStyle(ItemTypeIconCatalog.tint(for: item.itemType))
                                                }
                                                Text(item.partNumber)
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.muted)
                                            }
                                        }
                                        Spacer()
                                        Text("\(item.availableQuantity) avail")
                                            .monospacedDigit()
                                            .foregroundStyle(item.availableQuantity == 0 ? AppTheme.rose : AppTheme.teal)
                                    }
                                    .padding(.vertical, 10)
                                    Divider()
                                }
                            }
                        }
                    } else {
                        Text("Select a stockroom to inspect its live inventory.")
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frostedPanel()
            }
        }
    }

    private var importPlaceholder: some View {
        SectionShell(
            title: "PDF intake and review",
            eyebrow: AppSection.importPDFs.eyebrow,
            subtitle: "Review parsed quote and purchase-order rows before saving them into inventory."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button("Choose PDFs") {
                        let urls = FileDialogs.choosePDFs()
                        Task { await model.parsePDFs(urls: urls) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.blue)

                    if !model.parsedImportItems.isEmpty {
                        Text("\(model.parsedImportItems.count) parsed row\(model.parsedImportItems.count == 1 ? "" : "s") ready for review")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.muted)
                        Button("Clear Parsed Rows", role: .destructive) {
                            confirmClearParsedPDFs = true
                        }
                        Button("Save Reviewed Rows") {
                            Task { await model.saveParsedItems() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                    }
                }

                if model.parsedImportItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Drop quote or purchase-order PDFs here", systemImage: "square.and.arrow.down.on.square")
                            .font(.headline)
                        Text("Or choose PDFs with the button above. Parsed rows stay editable until you save them.")
                            .foregroundStyle(AppTheme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                    .frostedPanel()
                    .onDrop(of: [UTType.pdf.identifier], isTargeted: nil, perform: handlePDFDrop)
                } else {
                    ForEach($model.parsedImportItems) { $item in
                        ParsedImportEditor(item: $item, stockrooms: model.stockrooms) {
                            model.removeParsedImportItem(id: item.id)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear parsed PDF rows?",
            isPresented: $confirmClearParsedPDFs,
            titleVisibility: .visible
        ) {
            Button("Clear Parsed Rows", role: .destructive) {
                model.clearParsedImportItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This discards the current parsed rows. No inventory changes will be saved.")
        }
    }

    private func handlePDFDrop(_ providers: [NSItemProvider]) -> Bool {
        let pdfProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
        guard !pdfProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let collector = PDFDropCollector()

        for provider in pdfProviders {
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    collector.append(destination)
                } catch {
                    DispatchQueue.main.async {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
        }

        group.notify(queue: .main) {
            Task { await model.parsePDFs(urls: collector.snapshot()) }
        }
        return true
    }

    private var settingsView: some View {
        SectionShell(
            title: "Workspace settings",
            eyebrow: AppSection.settings.eyebrow,
            subtitle: "Workspace identity, database location, imports, backups, and spreadsheet sync."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                workspaceSetupPanel

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Workspace Details")
                        .font(.headline)
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("App Name")
                                .font(.caption.weight(.semibold))
                            TextField("Inventory Manager", text: $model.appDisplayName)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Organization")
                                .font(.caption.weight(.semibold))
                            TextField("Standalone Workspace", text: $model.organizationName)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button("Save Details") {
                            model.saveWorkspaceBranding()
                        }
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workspace Database")
                            .font(.headline)
                        Text(model.databaseURL.path)
                            .textSelection(.enabled)
                            .foregroundStyle(AppTheme.muted)
                        Text("This SQLite database can be backed up, restored, or swapped for another workspace.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Text("\(model.inventory.count) inventory items")
                        .font(.headline.monospacedDigit())
                }

                HStack {
                    Button("Choose Existing Database") {
                        if let url = FileDialogs.chooseDatabaseFile() {
                            Task { await model.useDatabase(at: url) }
                        }
                    }
                    Button("Create New Database") {
                        if let url = FileDialogs.chooseDatabaseSaveURL(defaultName: "InventoryData.sqlite") {
                            Task { await model.createDatabase(at: url) }
                        }
                    }
                    Button("Use Default Workspace Location") {
                        Task { await model.createDatabaseAtDefaultLocation() }
                    }
                    Button("Back Up Database") {
                        if let url = FileDialogs.chooseDatabaseSaveURL(defaultName: "InventoryData-manual-backup.sqlite") {
                            Task { await model.backupDatabase(to: url) }
                        }
                    }
                    Button("Restore Database") {
                        if let url = FileDialogs.chooseDatabaseFile() {
                            databaseToRestore = url
                        }
                    }
                    Button("Reveal in Finder") {
                        FileDialogs.revealInFinder(model.databaseURL)
                    }
                    Button("Load Demo Data") {
                        Task { await model.loadDemoWorkspace() }
                    }
                    .disabled(!model.isWorkspaceEmpty)
                    Button("Refresh Backups") {
                        model.refreshBackupRecords()
                    }
                }

                BackupBrowserView(model: model, limit: 5)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Spreadsheet and CSV Imports")
                        .font(.headline)
                    Text(model.excelInventoryPath.isEmpty ? "No Excel workbook selected. CSV import is still available." : model.excelInventoryPath)
                        .textSelection(.enabled)
                        .foregroundStyle(AppTheme.muted)

                    HStack {
                        Button("Choose Excel File") {
                            if let url = FileDialogs.chooseExcelFile() {
                                model.setExcelInventoryPath(url.path)
                            }
                        }
                        Button("Import Excel") {
                            Task { await model.importFromExcel() }
                        }
                        .disabled(model.excelInventoryPath.isEmpty)
                        Button("Import CSV") {
                            if let url = FileDialogs.chooseCSVFile() {
                                Task { await model.importFromCSV(url: url) }
                            }
                        }
                        Button("Preview Import") {
                            Task { await model.previewExcelImport() }
                        }
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
                        Button("Clear Path") {
                            model.clearExcelInventoryPath()
                        }
                        .disabled(model.excelInventoryPath.isEmpty)
                        Button("Skip Spreadsheet Sync") {
                            model.acknowledgeSpreadsheetSetup()
                        }
                        Button("Export CSV Template") {
                            if let url = FileDialogs.chooseCSVSaveURL(defaultName: "Inventory Template.csv") {
                                Task { await model.exportBlankInventoryTemplateCSV(to: url) }
                            }
                        }
                    }
                }

                if let preview = model.importPreview {
                    ImportPreviewPanel(preview: preview)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Maintenance")
                            .font(.headline)
                        Text("Clean up duplicate inventory rows or undo the last import in this workspace.")
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Button("Remove Duplicates") {
                        Task { await model.removeDuplicateInventoryItems() }
                    }
                    Button("Undo Last Import") {
                        Task { await model.undoLastImport() }
                    }
                    .disabled(model.lastImportUndoBackupURL == nil)
                }

                if let lastImportSummary = model.lastImportSummary {
                    Text(lastImportSummary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.teal)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("User Management")
                                .font(.headline)
                            Text("Roles from the live users table.")
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        Text("\(model.users.count) users")
                            .font(.headline.monospacedDigit())
                    }

                    ForEach(model.users, id: \.username) { user in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text(user.username)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            if model.currentUser.role == "admin", let userID = user.id {
                                Picker("Role", selection: Binding(
                                    get: { user.role },
                                    set: { newRole in
                                        Task { await model.updateUserRole(userID: userID, role: newRole) }
                                    }
                                )) {
                                    ForEach(Self.userRoles, id: \.self) { role in
                                        Text(role.replacingOccurrences(of: "_", with: " ").capitalized).tag(role)
                                    }
                                }
                                .frame(width: 180)
                            } else {
                                Text(user.role.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frostedPanel()

                Divider()

                HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workspace Profile")
                        .font(.headline)
                    Text("This workspace stores its branding, database path, and spreadsheet connection for the team using it.")
                        .foregroundStyle(AppTheme.muted)
                }
                    Spacer()
                    Text(model.currentUser.role.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                }
            }
            .frostedPanel()
        }
    }

    private func vendorRatio(_ value: Double) -> Double {
        guard let maximum = model.dashboard.vendors.map(\.totalValue).max(), maximum > 0 else { return 0 }
        return Swift.max(0.08, value / maximum)
    }

    private var workspaceSetupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick Start")
                        .font(.title3.bold())
                    Text("Confirm the workspace name, database, stockrooms, and optional spreadsheet sync before daily use.")
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if model.isWorkspaceEmpty {
                    HStack(spacing: 8) {
                        Text("Empty Workspace")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.blue.opacity(0.10), in: Capsule())
                        Button("Load Demo") {
                            Task { await model.loadDemoWorkspace() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.blue)
                    }
                }
            }

            ForEach(model.setupChecklist) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(item.isComplete ? AppTheme.teal : AppTheme.muted)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(2)
                    }
                }
            }

            HStack {
                Button("Create First Stockroom") {
                    stockroomDraft = StockroomDraft()
                }
                .disabled(!model.stockrooms.isEmpty)

                Button("New Inventory Item") {
                    inventoryEditorItem = AppModel.blankInventoryItem(stockroomId: model.selectedStockroomID)
                }

                Button("Open Workspace Settings") {
                    model.selectedSection = .settings
                }

                Button("Export Inventory CSV") {
                    if let url = FileDialogs.chooseCSVSaveURL(defaultName: "\(model.appDisplayName) Export.csv") {
                        Task { await model.exportInventoryCSV(to: url) }
                    }
                }
                .disabled(model.inventory.isEmpty)

                Button("Show Welcome Guide") {
                    model.resetOnboarding()
                    showOnboarding = true
                }
            }
        }
        .frostedPanel()
    }

    private func panelHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.muted)
        }
    }

    private func dashboardBudgetRow(_ budget: BudgetSummary) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.gold.opacity(0.14))
                Text(String(budget.budgetType.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.gold)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(budget.budgetType)
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                Text("\(budget.itemCount) cataloged records")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Text(currency(budget.totalValue))
                .font(.headline.monospacedDigit())
                .foregroundStyle(AppTheme.text)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dashboardYearBudgetRow(_ budget: BudgetYearSummary) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(statusTint(budget.status).opacity(0.14))
                Text(String(budget.year))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(statusTint(budget.status))
            }
            .frame(width: 48, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(budget.budgetType) • \(budget.status)")
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                Text("\(budget.itemCount) item records • \(budgetPercentLabel(budget.percentUsed))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(currency(budget.actualSpend))
                    .font(.headline.monospacedDigit())
                Text(budget.remainingBudget.map(currency) ?? "No target")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dashboardVendorRow(_ vendor: VendorSpend, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Text("#\(rank)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.blue.opacity(0.10), in: Capsule())
                    Text(vendor.vendor)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                }
                Spacer()
                Text(currency(vendor.totalValue))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.text)
            }
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 999)
                    .fill(AppTheme.blue.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 999)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.blue, AppTheme.teal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * vendorRatio(vendor.totalValue))
                    }
            }
            .frame(height: 10)
        }
        .padding(.vertical, 8)
    }

    private func activityRow(_ entry: ActivityEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(actionColor(entry.action).opacity(0.14))
                Circle()
                    .fill(actionColor(entry.action))
                    .frame(width: 10, height: 10)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(activityTitle(entry))
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                    Text(displayTimestamp(entry.createdAt))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Text(activityBody(entry))
                    .foregroundStyle(AppTheme.text)
                if !entry.detailNote.isEmpty {
                    Text(entry.detailNote)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Text("by \(entry.performedBy)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func inventoryLedgerRow(_ item: InventoryItemRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(spacing: 10) {
                ItemTypeIconView(itemType: item.itemType, size: 16)
                Text(item.itemType)
            }
            .frame(width: 116, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.description)
                    .font(.headline)
                Text("\(item.manufacturer) • \(item.partNumber)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(width: 310, alignment: .leading)

            Text(item.vendor.isEmpty ? "No vendor" : item.vendor)
                .frame(width: 110, alignment: .leading)
            Text(item.poNumber.isEmpty ? "-" : item.poNumber)
                .frame(width: 100, alignment: .leading)
            Text(displayCompactDate(item.purchaseDate))
                .frame(width: 104, alignment: .leading)
            Text("\(item.qtyReceived)/\(item.quantity)")
                .frame(width: 72, alignment: .center)
            Text("\(item.availableQuantity)")
                .frame(width: 68, alignment: .center)
            Text(currency(item.unitCost))
                .frame(width: 92, alignment: .trailing)
            Text(item.stockroomName)
                .frame(width: 120, alignment: .leading)
            Text(item.budgetType)
                .frame(width: 80, alignment: .leading)
            HStack(spacing: 8) {
                Button("Edit") {
                    inventoryEditorItem = item
                }
                .buttonStyle(.bordered)

                Button("Deploy") {
                    deploymentDraft = DeploymentSheetModel(item: item)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.teal)
                .disabled(item.availableQuantity <= 0)
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(AppTheme.text)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func deploymentRow(_ deployment: DeploymentRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(deployment.itemType)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(deployment.description)
                    .font(.headline)
                Text("\(deployment.manufacturer) • \(deployment.partNumber)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(deployment.qtyDeployed)")
                .frame(width: 42, alignment: .center)
            Text(deployment.deployedTo)
                .frame(width: 150, alignment: .leading)
            Text(deployment.deployedBy)
                .frame(width: 130, alignment: .leading)
            Text(displayCompactDate(deployment.deployedDate))
                .frame(width: 110, alignment: .leading)
            Text(deployment.deployedLocation.isEmpty ? "No location" : deployment.deployedLocation)
                .frame(width: 110, alignment: .leading)
            Text(deployment.statusLabel)
                .foregroundStyle(deployment.isReturned ? AppTheme.muted : AppTheme.teal)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(deployment.notes.isEmpty ? "No notes" : deployment.notes)
                    .lineLimit(3)
                Text(deployment.stockroomName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(width: 240, alignment: .leading)
            Button("Mark Returned") {
                deploymentToReturn = deployment
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.rose)
            .disabled(deployment.isReturned)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(AppTheme.text)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var deploymentHeader: some View {
        HStack(spacing: 12) {
            deploymentHeaderMenu("Type", width: 84) {
                Button("Sort by Type") { model.deploymentSort = .itemType }
                Divider()
                deploymentFilterButtons(options: model.deploymentTypeOptions, selection: $model.deploymentTypeFilter)
            }
            deploymentHeaderMenu("Item", width: nil) {
                Button("Sort by Item") { model.deploymentSort = .description }
            }
            deploymentHeaderMenu("Qty", width: 42) {
                Button("Sort by Quantity") { model.deploymentSort = .quantityHigh }
            }
            deploymentHeaderMenu("Deployed To", width: 150) {
                Button("Sort by Deployed To") { model.deploymentSort = .deployedTo }
            }
            deploymentHeaderMenu("Deployed By", width: 130) {
                Button("Sort by Deployed By") { model.deploymentSort = .deployedBy }
                Divider()
                deploymentFilterButtons(options: model.deploymentByOptions, selection: $model.deploymentByFilter)
            }
            deploymentHeaderMenu("Date", width: 110) {
                Button("Sort by Date") { model.deploymentSort = .dateNewest }
            }
            deploymentHeaderMenu("Location", width: 110) {
                Button("Sort by Location") { model.deploymentSort = .location }
                Divider()
                deploymentFilterButtons(options: model.deploymentLocationOptions, selection: $model.deploymentLocationFilter)
            }
            deploymentHeaderMenu("Status", width: 90) {
                ForEach(DeploymentStatusFilter.allCases) { status in
                    Button(status.rawValue) { model.deploymentStatusFilter = status }
                }
            }
            deploymentHeaderCell("Notes", width: 240)
            deploymentHeaderCell("", width: 80)
        }
        .padding(.horizontal, 14)
    }

    private var inventoryHeader: some View {
        HStack(spacing: 14) {
            inventoryHeaderMenu("Type", width: 116) {
                Button("Sort by Type") { model.inventorySort = .itemType }
                Divider()
                inventoryFilterButtons(options: model.inventoryTypeOptions, selection: $model.inventoryTypeFilter)
            }
            inventoryHeaderMenu("Item", width: 310) {
                Button("Sort by Description") { model.inventorySort = .description }
                Divider()
                inventoryFilterButtons(options: model.inventoryManufacturerOptions, selection: $model.inventoryManufacturerFilter)
            }
            inventoryHeaderMenu("Vendor", width: 110) {
                Button("Sort by Vendor") { model.inventorySort = .vendor }
                Divider()
                inventoryFilterButtons(options: model.inventoryVendorOptions, selection: $model.inventoryVendorFilter)
            }
            inventoryHeaderMenu("PO", width: 100) {
                Button("Clear PO Filter") { model.inventoryPOSearch = "" }
            }
            inventoryHeaderMenu("Purchase Date", width: 104) {
                Button("Sort by Purchase Date") { model.inventorySort = .purchaseDateNewest }
            }
            inventoryHeaderMenu("Received", width: 72) {
                Button("All Receipts") { model.inventoryReceiptStatus = .all }
                Button("Fully Received") { model.inventoryReceiptStatus = .fullyReceived }
                Button("Partially Received") { model.inventoryReceiptStatus = .partiallyReceived }
                Button("Not Received") { model.inventoryReceiptStatus = .notReceived }
            }
            inventoryHeaderMenu("Avail", width: 68) {
                Button("Sort by Available") { model.inventorySort = .availableHigh }
                Divider()
                Button("All Availability") { model.inventoryAvailability = .all }
                Button("In Stock") { model.inventoryAvailability = .inStock }
                Button("Low Stock") { model.inventoryAvailability = .low }
                Button("Out of Stock") { model.inventoryAvailability = .depleted }
            }
            inventoryHeaderMenu("Unit Cost", width: 92) {
                Button("Sort by Cost") { model.inventorySort = .unitCostHigh }
            }
            inventoryHeaderMenu("Stockroom", width: 120) {
                inventoryFilterButtons(options: model.inventoryStockroomOptions, selection: $model.inventoryStockroomFilter)
            }
            inventoryHeaderMenu("Budget", width: 80) {
                inventoryFilterButtons(options: model.inventoryBudgetOptions, selection: $model.inventoryBudgetFilter)
            }
            deploymentHeaderCell("Actions", width: 132)
        }
        .padding(.horizontal, 14)
    }

    private func deploymentHeaderCell(_ title: String, width: CGFloat?) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.muted)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func deploymentHeaderMenu<Content: View>(_ title: String, width: CGFloat?, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title.uppercased())
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.muted)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
    }

    private func inventoryHeaderMenu<Content: View>(_ title: String, width: CGFloat?, @ViewBuilder content: () -> Content) -> some View {
        deploymentHeaderMenu(title, width: width, content: content)
    }

    @ViewBuilder
    private func inventoryFilterButtons(options: [String], selection: Binding<String>) -> some View {
        ForEach(options, id: \.self) { option in
            Button(option) {
                selection.wrappedValue = option
            }
        }
    }

    @ViewBuilder
    private func deploymentFilterButtons(options: [String], selection: Binding<String>) -> some View {
        ForEach(options, id: \.self) { option in
            Button(option) {
                selection.wrappedValue = option
            }
        }
    }

    private func displayCompactDate(_ raw: String) -> String {
        if let formatted = formattedDate(raw, dateStyle: .medium, timeStyle: .none) {
            return formatted
        }
        return raw
    }

    private func displayTimestamp(_ raw: String) -> String {
        if let formatted = formattedDate(raw, dateStyle: .medium, timeStyle: .short) {
            return formatted
        }
        return raw
    }

    private func formattedDate(_ raw: String, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> String? {
        let parserFormats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy", "MM/dd/yy"]
        for format in parserFormats {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = format
            if let date = parser.date(from: raw) {
                let formatter = DateFormatter()
                formatter.dateStyle = dateStyle
                formatter.timeStyle = timeStyle
                return formatter.string(from: date)
            }
        }
        return nil
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func actionColor(_ action: String) -> Color {
        switch action.lowercased() {
        case "deploy": AppTheme.blue
        case "return": AppTheme.rose
        case "edit": AppTheme.teal
        case "import": AppTheme.gold
        default: AppTheme.muted
        }
    }

    private func inventoryMetricCard(title: String, value: String, note: String, accent: String) -> some View {
        StatCardView(stat: DashboardStat(title: title, value: value, note: note, accent: accent))
    }

    private var activeInventoryFilters: [String] {
        var filters: [String] = []
        if model.inventoryTypeFilter != "All Types" { filters.append("Type: \(model.inventoryTypeFilter)") }
        if model.inventoryManufacturerFilter != "All Manufacturers" { filters.append("MFG: \(model.inventoryManufacturerFilter)") }
        if model.inventoryVendorFilter != "All Vendors" { filters.append("Vendor: \(model.inventoryVendorFilter)") }
        if model.inventoryBudgetFilter != "All Budgets" { filters.append("Budget: \(model.inventoryBudgetFilter)") }
        if model.inventoryStockroomFilter != "All Stockrooms" { filters.append("Stockroom: \(model.inventoryStockroomFilter)") }
        if model.inventoryReceiptStatus != .all { filters.append("Received: \(model.inventoryReceiptStatus.rawValue)") }
        if model.inventoryAvailability != .all { filters.append("Availability: \(model.inventoryAvailability.rawValue)") }
        if !model.inventoryPartNumberSearch.isEmpty { filters.append("Part #: \(model.inventoryPartNumberSearch)") }
        if !model.inventoryPOSearch.isEmpty { filters.append("PO: \(model.inventoryPOSearch)") }
        return filters
    }

    private var activeDeploymentFilters: [String] {
        var filters: [String] = []
        if model.deploymentTypeFilter != "All Types" { filters.append("Type: \(model.deploymentTypeFilter)") }
        if model.deploymentStatusFilter != .all { filters.append("Status: \(model.deploymentStatusFilter.rawValue)") }
        if model.deploymentByFilter != "All Team Members" { filters.append("Deployed By: \(model.deploymentByFilter)") }
        if model.deploymentLocationFilter != "All Locations" { filters.append("Location: \(model.deploymentLocationFilter)") }
        return filters
    }

    private func openDashboardStat(_ stat: DashboardStat) {
        switch stat.title {
        case "Cataloged Items":
            model.openInventoryDrilldown()
        case "Budget Overview":
            model.selectedSection = .budgets
        case "Inventory Value":
            model.openInventoryDrilldown(sort: .unitCostHigh)
        case "Total Deployed":
            model.openDeploymentsDrilldown()
        case "Low Stock Alerts":
            model.openInventoryDrilldown(availability: .low, sort: .availableHigh)
        case "Stockrooms":
            model.openStockroomsDrilldown()
        case "Database":
            model.openSettingsDrilldown()
        default:
            model.selectedSection = .inventory
        }
    }

    private func openActivityEntry(_ entry: ActivityEntry) {
        switch entry.action.lowercased() {
        case "deploy", "return":
            model.openDeploymentsDrilldown(search: activitySearchTerm(entry))
        case "import":
            model.selectedSection = .importPDFs
        case "edit" where entry.entityType == "budget":
            model.selectedSection = .budgets
        case "edit", "delete":
            model.openInventoryDrilldown(search: activitySearchTerm(entry))
        default:
            model.selectedSection = .inventory
        }
    }

    private var groupedBudgetCategories: [(year: Int, typeLabel: String, rows: [BudgetCategorySummary])] {
        let filtered = model.budgetDashboard.categorySummaries.filter { $0.budgetType == budgetCategoryTypeSelection }
        let groups = Dictionary(grouping: filtered, by: \.year)
        return groups.keys.sorted().map { year in
            (year: year, typeLabel: budgetCategoryTypeSelection == "Capital" ? "CAPEX" : "OPEX", rows: groups[year] ?? [])
        }
    }

    private var budgetSummaryHeader: some View {
        HStack(spacing: 12) {
            budgetHeaderCell("Year", width: 56)
            budgetHeaderCell("Budget Type", width: 92)
            budgetHeaderCell("Budget", width: 112)
            budgetHeaderCell("Actual Spend", width: 112)
            budgetHeaderCell("Remaining", width: 112)
            budgetHeaderCell("% Used", width: 72)
            budgetHeaderCell("Status", width: 96)
            budgetHeaderCell("Fund", width: 100)
            budgetHeaderCell("GL Code", width: 90)
            budgetHeaderCell("Items", width: 56)
        }
        .padding(.bottom, 8)
    }

    private func budgetSummaryRow(_ summary: BudgetYearSummary) -> some View {
        HStack(spacing: 12) {
            budgetValueCell(String(summary.year), width: 56)
            budgetValueCell(summary.budgetType, width: 92)
            budgetValueCell(summary.allocatedBudget.map(currency) ?? "-", width: 112)
            budgetValueCell(currency(summary.actualSpend), width: 112)
            budgetValueCell(summary.remainingBudget.map(currency) ?? "-", width: 112, tint: summary.remainingBudget ?? 0 < 0 ? AppTheme.rose : AppTheme.text)
            budgetValueCell(budgetPercentLabel(summary.percentUsed), width: 72)
            Text(summary.status)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(statusTint(summary.status))
                .frame(width: 96, alignment: .leading)
            budgetValueCell(summary.fundCode.isEmpty ? "-" : summary.fundCode, width: 100)
            budgetValueCell(summary.glCode.isEmpty ? "-" : summary.glCode, width: 90)
            budgetValueCell(String(summary.itemCount), width: 56)
        }
        .padding(.vertical, 10)
    }

    private var budgetCategoryHeader: some View {
        HStack(spacing: 12) {
            budgetHeaderCell("Category", width: nil)
            budgetHeaderCell("Total Spend", width: 110)
            budgetHeaderCell("# Items", width: 60)
            budgetHeaderCell("Avg Cost", width: 100)
            budgetHeaderCell("% of Total", width: 80)
        }
    }

    private func budgetCategoryRow(_ row: BudgetCategorySummary) -> some View {
        HStack(spacing: 12) {
            budgetValueCell(row.category, width: nil)
            budgetValueCell(currency(row.totalSpend), width: 110)
            budgetValueCell(String(row.itemCount), width: 60)
            budgetValueCell(currency(row.averageCost), width: 100)
            budgetValueCell(budgetPercentLabel(row.percentOfYear), width: 80)
        }
        .padding(.vertical, 6)
    }

    private func combinedBudgetRow(_ summary: BudgetCombinedSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.yearLabel)
                    .font(.headline)
                Text("Budget / spend / remaining")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(summary.totalBudget.map(currency) ?? "-")
                    .font(.headline.monospacedDigit())
                Text(currency(summary.totalSpend))
                    .font(.subheadline.monospacedDigit())
                Text(summary.totalRemaining.map(currency) ?? "-")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle((summary.totalRemaining ?? 0) < 0 ? AppTheme.rose : AppTheme.muted)
            }
        }
        .padding(.vertical, 10)
    }

    private var budgetConfigHeader: some View {
        HStack(spacing: 12) {
            budgetHeaderCell("Year", width: 56)
            budgetHeaderCell("Budget Type", width: 92)
            budgetHeaderCell("Budget Target", width: 120)
            budgetHeaderCell("Fund", width: 120)
            budgetHeaderCell("GL Code", width: 120)
        }
    }

    private func budgetConfigRow(_ record: Binding<AnnualBudgetRecord>) -> some View {
        HStack(spacing: 12) {
            TextField("2026", text: record.year)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            Text(record.wrappedValue.budgetType)
                .frame(width: 92, alignment: .leading)
            TextField("$0.00", text: record.allocatedBudget)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            TextField("Fund", text: record.fundCode)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            TextField("GL Code", text: record.glCode)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            Button(role: .destructive) {
                budgetToDelete = record.wrappedValue
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete this saved budget row")
            .buttonStyle(.borderless)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
    }

    private func budgetHeaderCell(_ title: String, width: CGFloat?) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.muted)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func budgetValueCell(_ value: String, width: CGFloat?, tint: Color = AppTheme.text) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func activityTitle(_ entry: ActivityEntry) -> String {
        switch entry.action.lowercased() {
        case "import":
            return "Import"
        case "deploy":
            return "Deployment"
        case "return":
            return "Return"
        case "edit" where entry.entityType == "budget":
            return "Budget Update"
        case "edit":
            return "Edit"
        case "delete":
            return "Delete"
        case "create":
            return "Create"
        default:
            return entry.action.capitalized
        }
    }

    private func activityBody(_ entry: ActivityEntry) -> String {
        if let delimiterRange = entry.details.range(of: " | ") {
            return String(entry.details[..<delimiterRange.lowerBound])
        }
        return entry.details
    }

    private func activitySearchTerm(_ entry: ActivityEntry) -> String {
        let body = activityBody(entry)
        if let sourceRange = body.range(of: "Source: ") {
            return String(body[sourceRange.upperBound...])
        }
        return body
    }

    private func budgetPercentLabel(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func statusTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "over budget": AppTheme.rose
        case "watch", "at budget": AppTheme.gold
        case "on track": AppTheme.teal
        default: AppTheme.muted
        }
    }

    private static let userRoles = ["admin", "global_viewer", "manager", "viewer"]
}
