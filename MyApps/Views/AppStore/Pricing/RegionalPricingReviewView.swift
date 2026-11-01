import AppFoundation
import SwiftUI

private enum PricingRowFilter: String, CaseIterable, Identifiable {
    case all = "All", changes = "Changes", warnings = "Warnings",
         overrides = "Overrides", blocked = "Blocked"
    var id: Self { self }
}

struct RegionalPricingReviewView: View {
    @Environment(\.appFoundationTheme) private var theme
    @EnvironmentObject private var session: AppStoreConnectSession

    let product: PricingProduct
    @State private var model: RegionalPricingViewModel?
    @State private var filter: PricingRowFilter = .all
    @State private var countrySearch = ""
    @State private var showingSubmission = false
    @State private var confirmingReset = false

    init(product: PricingProduct, client: AppStoreConnectAPIClient?) {
        self.product = product
        _model = State(initialValue: client.map {
            RegionalPricingViewModel(product: product, client: $0)
        })
    }

    var body: some View {
        Group {
            if let model {
                pricingForm(model)
                    .task(id: session.connectionRevision) {
                        await model.begin(
                            connectionRevision: session.connectionRevision,
                            currentClient: session.client()
                        )
                    }
            } else {
                ContentUnavailableView(
                    "App Store Connect Disconnected",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Reconnect and reopen Pricing.")
                )
            }
        }
        .navigationTitle("Regional Pricing")
        .navigationBarTitleDisplayMode(.inline)
        .myAppsPage()
    }

    @ViewBuilder
    private func pricingForm(_ model: RegionalPricingViewModel) -> some View {
        Form {
            if model.phase == .loading && model.snapshot == nil {
                ProgressView("Loading product pricing…")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if let message = model.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Dismiss Message") { model.clearError() }
                    if model.snapshot == nil {
                        Button("Retry Loading") {
                            Task { await model.load(initial: true, refresh: true) }
                        }
                    }
                }
            }
            if let snapshot = model.snapshot {
                referenceSection(model: model, snapshot: snapshot)
                if let proposal = model.proposal {
                    resultSection(model: model, proposal: proposal)
                    countrySection(model: model, proposal: proposal)
                    submissionSection(proposal: proposal)
                }
                explanationSection(model: model, snapshot: snapshot)
            } else if !model.isWorking {
                ContentUnavailableView(
                    "Pricing Data Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Pull down to retry. Existing drafts are never submitted automatically.")
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .myAppsPage()
        .refreshable { await model.load(refresh: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.load(refresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isWorking)
                .accessibilityLabel("Refresh Apple pricing")
            }
        }
        .confirmationDialog("Reset all overrides?", isPresented: $confirmingReset) {
            Button("Reset All Overrides", role: .destructive) {
                model.resetAllOverrides()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every manual country override will be removed. Suggested prices will remain.")
        }
        .sheet(isPresented: $showingSubmission) {
            if let proposal = model.proposal {
                PricingSubmissionView(proposal: proposal, isCurrentReview: model.isReviewCurrent)
            }
        }
    }

    @ViewBuilder
    private func referenceSection(model: RegionalPricingViewModel,
                                  snapshot: PricingSnapshot) -> some View {
        Section {
            LabeledContent("Product", value: product.name)
            if let productID = product.productID {
                LabeledContent("Product ID", value: productID)
                    .font(.footnote)
            }
            if let duration = product.duration {
                LabeledContent("Duration",
                    value: duration.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            if product.kind == .lifetime {
                LabeledContent("Apple Base Territory",
                    value: snapshot.baseTerritoryID.map(PricingDisplay.country) ?? "Not configured")
            }
            Picker("US Reference Price", selection: Binding(
                get: { model.selectedUSPointID },
                set: { model.changeUSPoint($0) }
            )) {
                Text("Select a US price").tag("")
                ForEach(snapshot.usPoints) { point in
                    Text(PricingDisplay.amount(point.customerPrice, currency: point.currency))
                        .tag(point.id)
                }
            }
            .disabled(model.isWorking)
            DatePicker("Effective Date", selection: Binding(
                get: { model.effectiveDate },
                set: { model.changeDate($0) }
            ), displayedComponents: .date)
                .disabled(model.isWorking)
            LabeledContent("Strategy", value: "Balanced · 5 tiers")
            if model.isWorking {
                ProgressView(model.phase == .generating
                    ? "Reading Apple price points and generating…"
                    : "Refreshing Apple's pricing…")
            }
            Button {
                Task { await model.generate() }
            } label: {
                Label(model.proposal == nil ? "Generate Regional Prices" : "Regenerate Prices",
                      systemImage: "globe")
            }
            .disabled(model.isWorking || model.selectedUSPoint == nil || model.isStale)
        } header: {
            Text("Reference")
        } footer: {
            Text("Uses Apple's actual US price point and equalized local references. No pricing is changed in App Store Connect.")
        }

        if model.isStale || model.restoredDraft || model.needsRegeneration {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.isStale ? "Remote prices changed" :
                             model.restoredDraft ? "Saved draft needs review" :
                             "Price selections changed")
                            .font(.subheadline.weight(.semibold))
                        Text("The previous proposal remains visible. Review the refreshed Apple baseline and regenerate before submission becomes available.")
                            .font(.footnote)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                }
                Button("Review Updated Baseline") {
                    Task {
                        // A regenerated proposal uses the refreshed snapshot,
                        // selected valid US point, and preserved country overrides.
                        await model.reviewUpdatedBaseline()
                    }
                }
                .disabled(model.isWorking || model.selectedUSPoint == nil)
            }
        }
    }

    @ViewBuilder
    private func resultSection(model: RegionalPricingViewModel,
                               proposal: RegionalPricingProposal) -> some View {
        Section("Proposal Summary") {
            LabeledContent("Eligible Storefronts", value: "\(proposal.summary.eligible)")
            LabeledContent("Price Increases", value: "\(proposal.summary.increases)")
            LabeledContent("Price Decreases", value: "\(proposal.summary.decreases)")
            LabeledContent("Unchanged", value: "\(proposal.summary.unchanged)")
            LabeledContent("Unknown Deltas", value: "\(proposal.summary.unknown)")
            LabeledContent("Warnings", value: "\(proposal.summary.warnings)")
            LabeledContent("Blocked", value: "\(proposal.summary.blocked)")
            LabeledContent("Excluded", value: "\(proposal.summary.excluded)")
            if product.kind == .lifetime {
                LabeledContent("Automatic → Manual",
                    value: "\(proposal.summary.automaticToManual)")
                Text("Manually priced lifetime countries may no longer receive Apple's automatic tax and exchange-rate adjustments.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryForegroundColor)
            } else {
                Text("Subscription prices are separate from preserved subscriber prices. Existing customers may be affected by decreases; increases require subscriber treatment review.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryForegroundColor)
            }
            if model.isReviewCurrent && !proposal.overrides.isEmpty {
                Button("Reset All Overrides", role: .destructive) {
                    confirmingReset = true
                }
            }
        }
    }

    @ViewBuilder
    private func countrySection(model: RegionalPricingViewModel,
                                proposal: RegionalPricingProposal) -> some View {
        Section {
            TextField("Filter countries by code", text: $countrySearch)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Picker("Show", selection: $filter) {
                ForEach(PricingRowFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            let rows = displayedRows(proposal)
            if rows.isEmpty {
                Text("No countries match your filters.")
                    .foregroundStyle(theme.secondaryForegroundColor)
            }
            ForEach(rows) { row in
                NavigationLink {
                    RegionalPriceOverrideView(model: model, territoryID: row.territoryID)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(PricingDisplay.country(row.territoryID))
                                    .font(.subheadline.weight(.medium))
                                if row.overridePoint != nil {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundStyle(.blue)
                                        .accessibilityLabel("Manually overridden")
                                }
                            }
                            Text(secondaryLabel(row))
                                .font(.caption)
                                .foregroundStyle(theme.secondaryForegroundColor)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(PricingDisplay.amount(row.selectedPoint?.customerPrice,
                                                       currency: row.currency))
                                .font(.subheadline.weight(.medium))
                            Text(row.diff.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(row.blockers.isEmpty
                                    ? theme.secondaryForegroundColor : .orange)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        } header: {
            Text("Countries")
        } footer: {
            Text("Tap a country to inspect its current price, future schedules, tier, valid point suggestions, and optional override. Blocked countries cannot be submitted.")
        }
    }

    @ViewBuilder
    private func submissionSection(proposal: RegionalPricingProposal) -> some View {
        Section {
            Button {
                showingSubmission = true
            } label: {
                Label("Review Submission", systemImage: "checklist")
            }
            Text("Submission is unavailable until the lifetime and subscription write passes are implemented. This screen cannot change App Store prices.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryForegroundColor)
        }
    }

    @ViewBuilder
    private func explanationSection(model: RegionalPricingViewModel,
                                    snapshot: PricingSnapshot) -> some View {
        Section {
            if let mapping = model.mapping {
                DisclosureGroup("How suggestions are calculated") {
                    Text("Each local target is Apple's equalized price for the selected US point multiplied by 100%, 85%, 65%, 45%, or 30%, then matched to the nearest valid Apple price point.")
                    LabeledContent("Mapping Version", value: mapping.version)
                    LabeledContent("World Bank Income Edition",
                        value: mapping.incomeClassificationEdition)
                    Text("Country tiers are starting heuristics, not guaranteed revenue-optimal prices. Missing assignments retain Apple's full reference with a warning.")
                        .font(.footnote)
                }
            }
            if !snapshot.issues.isEmpty {
                DisclosureGroup("\(snapshot.issues.count) Apple data notices") {
                    ForEach(snapshot.issues.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.issues[index].resource)
                                .font(.subheadline.weight(.medium))
                            Text(snapshot.issues[index].message)
                                .font(.footnote)
                        }
                    }
                }
            }
            Text("All prices displayed here are read from Apple or are clearly marked suggestions. Review mode does not submit any changes.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryForegroundColor)
        }
    }

    private func displayedRows(_ proposal: RegionalPricingProposal) -> [RegionalPricingRow] {
        proposal.rows.filter { row in
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .changes: matches = row.diff == .increase || row.diff == .decrease ||
                row.maintenanceChanged || row.indirectChange
            case .warnings: matches = !row.warnings.isEmpty
            case .overrides: matches = row.overridePoint != nil
            case .blocked: matches = !row.blockers.isEmpty
            }
            return matches && (countrySearch.isEmpty ||
                row.territoryID.localizedCaseInsensitiveContains(countrySearch) ||
                PricingDisplay.country(row.territoryID)
                    .localizedCaseInsensitiveContains(countrySearch))
        }
    }

    private func secondaryLabel(_ row: RegionalPricingRow) -> String {
        var pieces = [row.tier.map { "Tier \($0)" } ?? "Unmapped",
                      row.excluded ? "Excluded" : row.diff.rawValue.capitalized]
        if !row.blockers.isEmpty { pieces.append("\(row.blockers.count) blocked") }
        else if !row.warnings.isEmpty { pieces.append("\(row.warnings.count) warnings") }
        return pieces.joined(separator: " · ")
    }
}
