import AppFoundation
import Foundation
import SwiftUI

private enum PricingRowFilter: String, CaseIterable, Identifiable {
    case all = "All", changes = "Changes", unchanged = "Unchanged",
         warnings = "Warnings", overrides = "Overrides", blocked = "Blocked"
    var id: Self { self }
}

struct RegionalPricingReviewView: View {
    @Environment(\.appFoundationTheme) private var theme
    @EnvironmentObject private var session: AppStoreConnectSession

    let product: PricingProduct
    @State private var model: RegionalPricingViewModel?
    @State private var filter: PricingRowFilter = .all
    @State private var tierFilter: Int = 0
    @State private var countrySearch = ""
    @State private var showingSubmission = false
    @State private var confirmingReset = false
    @State private var showingAllUSPrices = false

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
            Group {
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
            .listRowBackground(MyAppsGlassSurface())
            .listRowSeparatorTint(theme.borderColor)
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
            if model.proposal != nil {
                PricingSubmissionView(model: model)
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
            if snapshot.usPoints.isEmpty {
                if model.isWorking {
                    ProgressView("Loading US prices…")
                } else {
                    Label("US Prices Could Not Be Loaded", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(model.usPriceLoadingError ?? "No valid US prices are available.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryForegroundColor)
                    Button("Retry Loading Prices") {
                        Task { await model.load(refresh: true) }
                    }
                    Text("Generate becomes available after a valid US price is loaded and selected.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryForegroundColor)
                }
            } else {
                Picker("US Reference Price", selection: Binding(
                    get: { model.selectedUSPointID },
                    set: { model.changeUSPoint($0) }
                )) {
                    Text("Select a US price").tag("")
                    ForEach(usReferencePoints(snapshot, selectedID: model.selectedUSPointID)) { point in
                        Text(PricingDisplay.amount(point.customerPrice, currency: point.currency))
                            .tag(point.id)
                    }
                }
                .disabled(model.isWorking)
                if snapshot.usPoints.contains(where: isCommonUSPrice),
                   snapshot.usPoints.contains(where: { !isCommonUSPrice($0) }) {
                    Button(showingAllUSPrices ? "Show Common Prices" : "See Additional Prices") {
                        showingAllUSPrices.toggle()
                    }
                    .disabled(model.isWorking)
                    Text(showingAllUSPrices
                        ? "Showing all available Apple US prices."
                        : "Showing common .99 US prices. Your selected price stays visible even if it has a different ending.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryForegroundColor)
                }
            }
            DatePicker("Effective Date", selection: Binding(
                get: { model.effectiveDate },
                set: { model.changeDate($0) }
            ), displayedComponents: .date)
                .environment(\.calendar, PricingDay.calendar)
                .environment(\.timeZone, PricingDay.timeZone)
                .disabled(model.isWorking)
        } header: {
            Text("Reference")
        } footer: {
            Text("Uses Apple's actual US price point and equalized local references. No pricing is changed in App Store Connect.")
        }

        policiesSection(model)

        if model.isStale || model.restoredDraft || model.needsRegeneration || model.presetNeedsRegeneration {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.isStale ? "Remote prices changed" :
                             model.restoredDraft ? "Saved draft needs review" :
                             model.presetNeedsRegeneration ? "Pricing preset changed" :
                             "Pricing settings changed")
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

    private func usReferencePoints(_ snapshot: PricingSnapshot, selectedID: String) -> [PricingPoint] {
        guard !showingAllUSPrices else { return snapshot.usPoints }
        let commonIDs = Set(snapshot.usPoints.filter(isCommonUSPrice).map(\.id))
        // Keep a usable picker if Apple ever supplies no common US points.
        guard !commonIDs.isEmpty else { return snapshot.usPoints }
        return snapshot.usPoints.filter { commonIDs.contains($0.id) || $0.id == selectedID }
    }

    private func isCommonUSPrice(_ point: PricingPoint) -> Bool {
        guard point.currency == "USD", point.territoryID == "USA" else { return false }
        var amount = point.customerPrice
        var wholeDollars = Decimal()
        NSDecimalRound(&wholeDollars, &amount, 0, .down)
        return amount - wholeDollars == Decimal(99) / Decimal(100)
    }

    private func policiesSection(_ model: RegionalPricingViewModel) -> some View {
        Section {
            NavigationLink {
                PricingPresetsView(model: model)
            } label: {
                LabeledContent("Country Strategy", value: model.selectedPreset.displayName)
            }
            .disabled(model.isWorking)
            Text(model.selectedPreset.percentageSummary + " · Applied by country tier to Apple's local equivalent of your US reference price.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryForegroundColor)
            Picker("Price Rounding", selection: Binding(
                get: { model.roundingPolicy },
                set: { model.changeRoundingPolicy($0) }
            )) {
                ForEach(RegionalPriceRoundingPolicy.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .disabled(model.isWorking)
            Text(model.roundingPolicy.explanation)
                .font(.footnote)
                .foregroundStyle(theme.secondaryForegroundColor)
            if product.kind == .subscription {
                subscriberPolicyRows(model)
            }
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
            .disabled(model.isWorking || model.selectedUSPoint == nil)
        } header: {
            Text("Pricing Policies")
        } footer: {
            Text("New proposals default to Nearest Common Price and, for subscriptions, Keep Current Prices. Saved proposals retain their policies. Change a policy and generate again to update suggestions. Your US reference and manual overrides stay exact. Generate does not submit prices to Apple.")
        }
    }

    @ViewBuilder
    private func subscriberPolicyRows(_ model: RegionalPricingViewModel) -> some View {
        Picker("Existing Subscribers — Increases", selection: Binding(
            get: { model.subscriberPolicy },
            set: { model.changeSubscriberPolicy($0) }
        )) {
            ForEach(RegionalSubscriberPolicy.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .disabled(model.isWorking)
        Text(model.subscriberPolicy.explanation)
            .font(.footnote)
            .foregroundStyle(theme.secondaryForegroundColor)
        DisclosureGroup("Decreases, Consent, and Older Preserved Prices") {
            Text(SubscriptionPricingGuidance.decreases)
            Text(SubscriptionPricingGuidance.consent)
            Text(SubscriptionPricingGuidance.olderGroups)
            Text("To remove older price preservation, open this app in App Store Connect, select the subscription, then Subscription Pricing → View all Subscription Pricing → Starting Price → Edit Price. This separate action is not submitted by MyApps.")
            if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(product.appID)") {
                Link("Manage Older Preserved Prices in App Store Connect", destination: url)
            }
            Link("Apple's Subscription Pricing Guide", destination: SubscriptionPricingGuidance.helpURL)
        }
        .font(.footnote)
    }

    @ViewBuilder
    private func resultSection(model: RegionalPricingViewModel,
                               proposal: RegionalPricingProposal) -> some View {
        Section("Proposal Summary") {
            LabeledContent("Preset", value: proposal.effectivePreset?.displayName ?? "Unknown — regenerate")
            if let preset = proposal.effectivePreset {
                Text(preset.percentageSummary)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryForegroundColor)
            }
            LabeledContent("Price Rounding", value: proposal.effectiveRoundingPolicy.title)
            let fallbacks = proposal.rows.filter {
                !$0.excluded && $0.warnings.contains(.commonPriceFallback)
            }.count
            if fallbacks > 0 {
                Label("\(fallbacks) countries used nearest available pricing because no common rule or matching point was available. Open a country for details.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
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
                LabeledContent("Existing Subscribers on Increases", value: proposal.subscriberPolicy.summary)
                Text(proposal.subscriberPolicy.confirmation)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryForegroundColor)
                Text(SubscriptionPricingGuidance.decreases)
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
            Picker("Tier", selection: $tierFilter) {
                Text("All tiers").tag(0)
                ForEach(1...5, id: \.self) { tier in
                    Text("Tier \(tier)").tag(tier)
                }
                Text("Unmapped").tag(6)
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
            Text("Review the exact changes and confirm separately before submitting prices to App Store Connect.")
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
                    Text("Each local target is Apple's equalized price for the selected US point multiplied by that country's tier percentage in your chosen preset. The selected rounding policy chooses the nearest valid common or available Apple price. Ties choose the lower price.")
                    Text("Common-price conventions are versioned MyApps rules, not Apple's curated dashboard list. Examples: .99 in USD/EUR, multiples of 10 in JPY, and multiples of 1,000 in VND. Country details show the applied rule; unsupported currencies or empty common lists fall back with a warning.")
                    LabeledContent("Mapping Version", value: mapping.version)
                    LabeledContent("World Bank Income Edition",
                        value: mapping.incomeClassificationEdition)
                    Text("Country tiers are starting heuristics, not guaranteed revenue-optimal prices. Missing assignments retain Apple's full reference with a warning.")
                        .font(.footnote)
                }
            }
            if !snapshot.issues.isEmpty {
                DisclosureGroup("Pricing Data Issues (\(snapshot.issues.count))") {
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
            case .unchanged: matches = row.isNoOp
            case .warnings: matches = !row.warnings.isEmpty
            case .overrides: matches = row.overridePoint != nil
            case .blocked: matches = !row.blockers.isEmpty
            }
            let matchesTier = tierFilter == 0 || (tierFilter == 6
                ? row.tier == nil : row.tier == tierFilter)
            return matches && matchesTier && (countrySearch.isEmpty ||
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







