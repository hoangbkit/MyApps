import AppFoundation
import SwiftUI

/// The only UI where a fully reviewed price proposal can trigger an Apple POST.
/// Lifetime submits one schedule; standard subscriptions submit per territory.
struct PricingSubmissionView: View {
    @Environment(\.appFoundationTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppStoreConnectSession

    let model: RegionalPricingViewModel
    @State private var plan: LifetimeSchedulePlan?
    @State private var report: PricingSubmissionReport?
    @State private var subscriptionPlan: SubscriptionWritePlan?
    @State private var subscriptionReport: SubscriptionSubmissionReport?
    @State private var acknowledgesDecrease = false
    @State private var acknowledgesIncrease = false
    @State private var confirmingResume = false
    @State private var resumeReview: SubscriptionSubmissionBatch?
    @State private var confirmingClose = false
    @State private var closeReview: SubscriptionSubmissionBatch?
    @State private var errorMessage: String?
    @State private var isPreparing = false
    @State private var isSending = false
    @State private var confirmingSubmission = false
    @State private var loaded = false
    @State private var isVisible = false

    private var proposal: RegionalPricingProposal? { model.proposal }
    private var savedSubscription: SubscriptionSubmissionBatch? {
        guard let batch = subscriptionReport?.batch, !batch.isClosed else { return nil }
        return batch
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if let proposal {
                        if let saved = savedSubscription {
                            savedSubscriptionScope(saved)
                        } else {
                            Section("Product") {
                                LabeledContent("Name", value: proposal.product.name)
                                LabeledContent("Product ID", value: proposal.product.productID ?? "Unknown")
                                LabeledContent("US Reference", value:
                                    PricingDisplay.amount(proposal.selectedUSPoint.customerPrice,
                                                          currency: proposal.selectedUSPoint.currency))
                                LabeledContent("Effective Date", value: proposal.effectiveDate)
                                LabeledContent("Preset", value: proposal.effectivePreset?.displayName ?? "Unknown — regenerate")
                                if let preset = proposal.effectivePreset {
                                    Text(preset.percentageSummary).font(.footnote)
                                }
                                LabeledContent("Price Rounding", value: proposal.effectiveRoundingPolicy.title)
                                if proposal.product.kind == .lifetime {
                                    LabeledContent("Apple Base Territory",
                                        value: proposal.configuredBaseTerritory ?? "Unknown")
                                } else {
                                    LabeledContent("Subscription Duration",
                                        value: proposal.product.duration ?? "Unknown")
                                    LabeledContent("Billing Plan", value: "UPFRONT")
                                }
                            }
                            Section("Frozen Review Scope") {
                                LabeledContent("Eligible", value: String(proposal.summary.eligible))
                                LabeledContent("Increases", value: String(proposal.summary.increases))
                                LabeledContent("Decreases", value: String(proposal.summary.decreases))
                                LabeledContent("Excluded", value: String(proposal.summary.excluded))
                                LabeledContent("Blockers", value: String(proposal.summary.blocked))
                                if proposal.product.kind == .lifetime {
                                    LabeledContent("Automatic → Manual",
                                        value: String(proposal.summary.automaticToManual))
                                }
                            }
                            if let subscriptionPlan {
                                subscriptionPreflight(subscriptionPlan)
                            }
                            if let plan {
                                Section("Preflight — Apple's Current State") {
                                    LabeledContent("Base Territory",
                                        value: plan.baseTerritoryID.isEmpty ? "Unknown" : plan.baseTerritoryID)
                                    LabeledContent("Schedule Groups",
                                        value: plan.request == nil ? "0" : "1")
                                    LabeledContent("Changed Storefronts",
                                        value: String(plan.affectedTerritories.count))
                                    LabeledContent("Preserved Manual Entries",
                                        value: String(plan.preservedEntries.count))
                                    LabeledContent("Indirect Automatic Changes",
                                        value: String(plan.indirectTerritories.count))
                                    if !plan.excludedTerritories.isEmpty {
                                        DisclosureGroup("Excluded Countries") {
                                            ForEach(plan.excludedTerritories, id: \.self) {
                                                Text(PricingDisplay.country($0) + " (" + $0 + ")")
                                            }
                                        }
                                    }
                                    if !plan.affectedTerritories.isEmpty {
                                        DisclosureGroup("Exact Changed Countries") {
                                            ForEach(plan.affectedTerritories, id: \.self) {
                                                Text(PricingDisplay.country($0) + " (" + $0 + ")")
                                            }
                                        }
                                    }
                                }
                                if !plan.blockers.isEmpty || !plan.warnings.isEmpty {
                                    Section("Preflight Findings") {
                                        ForEach(plan.blockers, id: \.self) { blocker in
                                            Label(blocker, systemImage: "exclamationmark.triangle")
                                                .foregroundStyle(.orange)
                                        }
                                        ForEach(plan.warnings, id: \.self) { warning in
                                            Text(warning)
                                                .foregroundStyle(theme.secondaryForegroundColor)
                                        }
                                    }
                                }
                            } else if isPreparing {
                                Section {
                                    ProgressView("Rechecking Apple's prices and valid points…")
                                }
                            }
                            Section("Safety") {
                                if !model.isReviewCurrent {
                                    Label("The reviewed proposal is stale, unverified, or needs regeneration.",
                                          systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                }
                                if proposal.product.kind == .subscription {
                                    Text(proposal.subscriberPolicy.explanation)
                                    Text(SubscriptionPricingGuidance.olderGroups)
                                    Text(SubscriptionPricingGuidance.decreases)
                                    Text(SubscriptionPricingGuidance.consent)
                                    Text("Public price verification cannot prove individual subscriber treatment.")
                                } else {
                                    Text("One complete lifetime price schedule will be sent only after final confirmation. Apple may adjust other automatic storefront prices; any unresolved effects block submission.")
                                    Text("Apple acceptance does not mean prices are live. Verification or read-only reconciliation may still be needed.")
                                }
                            }
                        }
                        if let subscriptionReport {
                            subscriptionReportSection(subscriptionReport)
                        }
                        if let report {
                            Section("Submission Status") {
                                LabeledContent("Submitted Preset", value:
                                    (report.operation.plan.presetSnapshot ?? .balanced).displayName)
                                Text((report.operation.plan.presetSnapshot ?? .balanced).percentageSummary)
                                    .font(.footnote)
                                LabeledContent("Submitted Rounding", value:
                                    (report.operation.plan.roundingPolicy ?? .nearestAvailable).title)
                                LabeledContent("Group Status", value: report.operation.state.rawValue)
                                LabeledContent("Verified", value: String(report.verified))
                                LabeledContent("Pending Verification",
                                    value: String(report.pendingVerification))
                                LabeledContent("Unknown", value: String(report.unknown))
                                LabeledContent("Failed", value: String(report.failed))
                                LabeledContent("Skipped", value: String(report.skipped))
                                if let detail = report.operation.error {
                                    Text(detail).font(.footnote).foregroundStyle(.orange)
                                }
                                if report.operation.canReconcile {
                                    Button("Reconcile with Apple (Read Only)") {
                                        Task { await reconcile() }
                                    }
                                    .disabled(isSending || isPreparing)
                                }
                            }
                        }
                        if let errorMessage {
                            Section {
                                Text(errorMessage).foregroundStyle(.orange)
                                Button("Refresh Preflight") { Task { await prepare() } }
                                    .disabled(isPreparing || isSending)
                            }
                        }
                        Section {
                            if isSending {
                                ProgressView("Submitting or reconciling Apple prices…")
                            } else if proposal.product.kind == .subscription {
                                if savedSubscription != nil {
                                    Text("Resolve the saved submission above before submitting a new proposal.")
                                        .font(.footnote)
                                        .foregroundStyle(theme.secondaryForegroundColor)
                                } else if subscriptionPlan?.isNoOp == true {
                                    Label("No subscription price changes required.", systemImage: "checkmark.circle")
                                } else {
                                    Button("Submit Subscription Prices") {
                                        confirmingSubmission = true
                                    }
                                    .disabled(!maySubmitSubscription)
                                }
                            } else if plan?.isNoOp == true {
                                Label("No price changes required.", systemImage: "checkmark.circle")
                            } else {
                                Button("Submit Lifetime Prices") {
                                    confirmingSubmission = true
                                }
                                .disabled(!maySubmit)
                            }
                        } footer: {
                            Text("Only the final confirmation dispatches an App Store Connect pricing write. Recovery after interruption never auto-resubmits.")
                        }
                    } else {
                        ContentUnavailableView("No Pricing Proposal", systemImage: "exclamationmark.triangle")
                    }
                }
                .listRowBackground(MyAppsGlassSurface())
                .listRowSeparatorTint(theme.borderColor)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .myAppsPage()
            .navigationTitle("Review Submission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: session.connectionRevision) {
                if loaded {
                    pauseDispatch()
                    model.markRemoteStale()
                }
                loaded = true
                await loadPrevious()
                await prepare()
            }
            .onChange(of: acknowledgesDecrease) { _, _ in
                if proposal?.product.kind == .subscription {
                    Task { await prepare() }
                }
            }
            .onChange(of: acknowledgesIncrease) { _, _ in
                if proposal?.product.kind == .subscription {
                    Task { await prepare() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { pauseDispatch() }
            }
            .onAppear { isVisible = true }
            .onDisappear {
                isVisible = false
                pauseDispatch()
            }
            .confirmationDialog(
                proposal?.product.kind == .subscription
                    ? "Confirm Subscription Price Changes?" : "Confirm Lifetime Price Submission?",
                isPresented: $confirmingSubmission,
                titleVisibility: .visible
            ) {
                Button(proposal?.product.kind == .subscription
                       ? "Submit Subscription Prices" : "Submit Price Schedule") {
                    Task { await submit() }
                }
                .disabled(proposal?.product.kind == .subscription
                    ? !maySubmitSubscription : !maySubmit)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let subscriptionPlan, proposal?.product.kind == .subscription {
                    Text("Send \(subscriptionPlan.changes.count) separate territory price requests. \(subscriptionPlan.excluded.count) countries are excluded. \(subscriptionPlan.subscriberPolicy.confirmation) Older preserved groups are not un-preserved. Decreases affect renewals. A partial submission cannot be rolled back together.")
                } else if let plan {
                    Text("Send 1 schedule for \(plan.affectedTerritories.count) changed storefronts, preserve \(plan.preservedEntries.count) manual entries, and keep base territory \(plan.baseTerritoryID). \(plan.excludedTerritories.count) countries are excluded. This request cannot be automatically undone.")
                }
            }
            .confirmationDialog("Resume Remaining Subscription Changes?",
                                isPresented: $confirmingResume,
                                titleVisibility: .visible) {
                Button("Resume Verified Remaining Requests") {
                    if let reviewed = resumeReview {
                        Task { await resumeSubscription(reviewed: reviewed) }
                    }
                }
                .disabled(isSending || isPreparing || scenePhase != .active)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let reviewed = resumeReview {
                    Text("Resume the saved prices for \(reviewed.plan.product.name), effective \(reviewed.plan.effectiveDate). \(reviewed.plan.excluded.count) countries remain excluded. \(reviewed.plan.subscriberPolicy.confirmation) These are the saved submission's prices shown above, not a newer proposal. Accepted or unknown requests will not be replayed.")
                }
            }
            .confirmationDialog("Close Saved Submission?", isPresented: $confirmingClose,
                                titleVisibility: .visible) {
                Button("Close Saved Submission", role: .destructive) {
                    if let reviewed = closeReview {
                        Task { await closeSubscription(reviewed: reviewed) }
                    }
                }
                .disabled(isSending || isPreparing)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remaining unsent or rejected requests will not be sent. Verified Apple price changes stay in effect. After closing, refresh and generate a new proposal. An unknown request must be reconciled before it can be closed.")
            }
        }
    }

    @ViewBuilder
    private func savedSubscriptionScope(_ batch: SubscriptionSubmissionBatch) -> some View {
        Section("Saved Submission to Resolve") {
            LabeledContent("Product", value: batch.plan.product.name)
            LabeledContent("Product ID", value: batch.plan.product.productID ?? batch.plan.product.id)
            LabeledContent("Effective Date", value: batch.plan.effectiveDate)
            LabeledContent("Preset", value: (batch.plan.presetSnapshot ?? .balanced).displayName)
            Text((batch.plan.presetSnapshot ?? .balanced).percentageSummary).font(.footnote)
            LabeledContent("Price Rounding", value: (batch.plan.roundingPolicy ?? .nearestAvailable).title)
            LabeledContent("US Reference", value: batch.plan.selectedUSPoint.map {
                PricingDisplay.amount($0.customerPrice, currency: $0.currency)
            } ?? "Not recorded in this older saved submission")
            LabeledContent("Billing Plan", value: "UPFRONT")
            LabeledContent("Existing Subscribers on Increases", value: batch.plan.subscriberPolicy.summary)
            Text(batch.plan.subscriberPolicy.explanation)
                .font(.footnote)
            Text(SubscriptionPricingGuidance.olderGroups)
                .font(.footnote)
                .foregroundStyle(theme.secondaryForegroundColor)
            Text("Resume uses only the saved prices listed here. A newer proposal is separate and will not replace these requests.")
                .font(.footnote)
            if batch.plan.requiresDecreaseAcknowledgment {
                Text("The original confirmation acknowledged that decreases affect existing subscribers at renewal.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryForegroundColor)
            }
            if batch.plan.requiresIncreaseAcknowledgment {
                Text("The original confirmation acknowledged increases to existing current-price subscribers under Apple's notice and consent rules.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryForegroundColor)
            }
            DisclosureGroup("Exact Saved Prices and Outcomes") {
                ForEach(batch.entries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(PricingDisplay.country(entry.change.territoryID) + " (" + entry.change.territoryID + ")")
                            .font(.subheadline.weight(.medium))
                        Text(PricingDisplay.amount(entry.change.previous.customerPrice,
                            currency: entry.change.previous.currency) + " → " +
                            PricingDisplay.amount(entry.change.point.customerPrice,
                                currency: entry.change.point.currency))
                            .font(.caption)
                        Text(entry.state.rawValue)
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryForegroundColor)
                        Text(entry.change.subscriberImpact)
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryForegroundColor)
                    }
                }
            }
            DisclosureGroup("Saved Exclusions (\(batch.plan.excluded.count))") {
                ForEach(batch.plan.excluded, id: \.self) { code in
                    Text(PricingDisplay.country(code) + " (" + code + ")")
                }
            }
        }
    }

    @ViewBuilder
    private func subscriptionPreflight(_ details: SubscriptionWritePlan) -> some View {
        Section("Subscription Preflight") {
            LabeledContent("Changed Countries", value: String(details.changes.count))
            LabeledContent("Price Increases", value: String(details.changes.filter(\.increase).count))
            LabeledContent("Price Decreases", value: String(details.changes.filter { !$0.increase }.count))
            LabeledContent("Excluded Countries", value: String(details.excluded.count))
            LabeledContent("Independent Requests", value: String(details.changes.count))
            LabeledContent("Existing Subscribers on Increases", value: details.subscriberPolicy.summary)
            Text(details.subscriberPolicy.explanation)
                .font(.footnote)
                .foregroundStyle(theme.secondaryForegroundColor)
            if details.requiresIncreaseAcknowledgment {
                Toggle("I understand increases apply to existing current-price subscribers under Apple's notice and consent rules",
                       isOn: $acknowledgesIncrease)
                    .disabled(isSending || isPreparing)
            }
            if details.requiresDecreaseAcknowledgment {
                Toggle("I understand decreases affect existing subscribers at renewal",
                       isOn: $acknowledgesDecrease)
                    .disabled(isSending || isPreparing)
            }
            if !details.changes.isEmpty {
                DisclosureGroup("Exact New Prices") {
                    ForEach(details.changes) { change in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(PricingDisplay.country(change.territoryID) + " (" + change.territoryID + ")")
                                .font(.subheadline.weight(.medium))
                            HStack {
                                Text(PricingDisplay.amount(change.previous.customerPrice,
                                    currency: change.previous.currency))
                                Image(systemName: "arrow.right")
                                Text(PricingDisplay.amount(change.point.customerPrice,
                                    currency: change.point.currency))
                            }
                            .font(.caption)
                            Text(change.subscriberImpact)
                                .font(.caption2)
                                .foregroundStyle(theme.secondaryForegroundColor)
                        }
                    }
                }
            }
            if !details.excluded.isEmpty {
                DisclosureGroup("Explicitly Excluded Countries") {
                    ForEach(details.excluded, id: \.self) { code in
                        Text(PricingDisplay.country(code) + " (" + code + ")")
                    }
                }
            }
        }
        if !details.blockers.isEmpty || !details.warnings.isEmpty {
            Section("Subscription Warnings") {
                ForEach(details.blockers, id: \.self) {
                    Label($0, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                ForEach(details.warnings, id: \.self) {
                    Text($0).font(.footnote)
                        .foregroundStyle(theme.secondaryForegroundColor)
                }
            }
        }
    }

    @ViewBuilder
    private func subscriptionReportSection(_ summary: SubscriptionSubmissionReport) -> some View {
        Section("Subscription Submission") {
            LabeledContent("Submitted Preset", value: (summary.batch.plan.presetSnapshot ?? .balanced).displayName)
            Text((summary.batch.plan.presetSnapshot ?? .balanced).percentageSummary).font(.footnote)
            LabeledContent("Submitted Rounding", value: (summary.batch.plan.roundingPolicy ?? .nearestAvailable).title)
            LabeledContent("Submitted Increase Policy", value: summary.batch.plan.subscriberPolicy.summary)
            LabeledContent("Verified", value: String(summary.verifiedCount))
            LabeledContent("Accepted, Unverified", value: String(summary.acceptedCount))
            LabeledContent("Pending Verification / Unsent", value: String(summary.pendingCount))
            LabeledContent("Unknown", value: String(summary.unknownCount))
            LabeledContent("Failed", value: String(summary.failedCount))
            LabeledContent("Excluded", value: String(summary.skippedCount))
            if let reason = summary.batch.stoppedReason {
                Text(reason).font(.footnote).foregroundStyle(.orange)
            }
            if summary.requiresReconciliation {
                Button("Reconcile with Apple (Read Only)") {
                    Task { await reconcileSubscription() }
                }
                .disabled(isSending || isPreparing)
            }
            if summary.batch.closedAt != nil {
                Label("Saved submission closed. No remaining requests will be sent.",
                      systemImage: "checkmark.circle")
            }
            if !summary.batch.isClosed && summary.batch.uncertainCount == 0 &&
               (summary.hasUnsent || summary.failedCount > 0) {
                Button("Resume Saved Prices") {
                    resumeReview = summary.batch
                    confirmingResume = true
                }
                    .disabled(isSending || isPreparing ||
                        summary.batch.plan.effectiveDate < PricingDay.string(from: Date()))
                if summary.batch.plan.effectiveDate < PricingDay.string(from: Date()) {
                    Text("The saved effective date has passed. Close this submission and generate a new proposal.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            if summary.batch.canClose {
                Button("Close Saved Submission", role: .destructive) {
                    closeReview = summary.batch
                    confirmingClose = true
                }
                .disabled(isSending || isPreparing)
            }
            DisclosureGroup("Per-Country Results") {
                ForEach(summary.results) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(result.id)
                            Spacer()
                            Text(result.state.rawValue)
                                .foregroundStyle(theme.secondaryForegroundColor)
                        }
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryForegroundColor)
                    }
                }
            }
            if summary.batch.entries.contains(where: { $0.change.increase &&
                $0.preservationVerified != true &&
                ($0.state == .verifiedLive || $0.state == .verifiedScheduled) }) {
                Text("Public subscription prices were verified, but individual subscriber treatment could not be independently verified.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private var maySubmitSubscription: Bool {
        guard let proposal, let details = subscriptionPlan,
              proposal.product.kind == .subscription else { return false }
        return model.isReviewCurrent && details.isExecutable &&
            (!details.requiresDecreaseAcknowledgment || acknowledgesDecrease) &&
            (!details.requiresIncreaseAcknowledgment || acknowledgesIncrease) &&
            !isPreparing && !isSending &&
            isVisible && scenePhase == .active &&
            (subscriptionReport == nil || subscriptionReport?.batch.isClosed == true)
    }

    private var maySubmit: Bool {
        guard let proposal, let plan else { return false }
        return proposal.product.kind == .lifetime && model.isReviewCurrent &&
            plan.isExecutable && !isPreparing && !isSending && isVisible && scenePhase == .active &&
            (report == nil || [.planned, .failed, .verifiedLive, .verifiedScheduled].contains(report!.operation.state))
    }

    @MainActor
    private func prepare() async {
        guard !isPreparing, !isSending, let proposal else { return }
        if savedSubscription != nil {
            // Recovery displays the journal's immutable prices. Do not put a
            // newer proposal's preflight above an old batch's Resume button.
            plan = nil
            subscriptionPlan = nil
            return
        }
        guard model.isReviewCurrent, let client = session.client(),
              client.pricingAccountScope == proposal.accountScope else {
            errorMessage = "Review or reconnect this proposal before preparing a submission."
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        errorMessage = nil
        do {
            if proposal.product.kind == .subscription {
                let fresh = try await PricingSubmissionCoordinator.shared.prepareSubscription(
                    proposal: proposal, acknowledgesDecrease: acknowledgesDecrease,
                    acknowledgesIncrease: acknowledgesIncrease, client: client)
                guard !Task.isCancelled else { return }
                subscriptionPlan = fresh
                if fresh.blockers.contains(where: { $0.contains("changed since the review") }) {
                    model.markRemoteStale()
                }
            } else {
                let fresh = try await PricingSubmissionCoordinator.shared.prepare(
                    proposal: proposal, client: client)
                guard !Task.isCancelled else { return }
                plan = fresh
                if fresh.blockers.contains(where: { $0.contains("changed since review") }) {
                    model.markRemoteStale()
                }
            }
        } catch {
            if proposal.product.kind == .subscription {
                subscriptionPlan = nil
            } else {
                plan = nil
            }
            errorMessage = error.localizedDescription
            if !error.localizedDescription.contains("Acknowledge") {
                model.markRemoteStale()
            }
        }
    }

    @MainActor
    private func loadPrevious() async {
        guard let proposal else { return }
        do {
            if proposal.product.kind == .subscription {
                subscriptionReport = try await PricingSubmissionCoordinator.shared.previousSubscription(
                    accountScope: proposal.accountScope, productID: proposal.product.id)
                if subscriptionReport?.requiresReconciliation == true,
                   let client = session.client(),
                   client.pricingAccountScope == proposal.accountScope {
                    // Relaunch is GET-only. No pending POST is replayed.
                    subscriptionReport = try await PricingSubmissionCoordinator.shared.reconcileSubscription(
                        accountScope: proposal.accountScope, productID: proposal.product.id,
                        client: client)
                }
            } else {
                report = try await PricingSubmissionCoordinator.shared.previous(
                    accountScope: proposal.accountScope, productID: proposal.product.id)
                if report?.operation.canReconcile == true,
                   let client = session.client(),
                   client.pricingAccountScope == proposal.accountScope {
                    report = try await PricingSubmissionCoordinator.shared.reconcile(
                        accountScope: proposal.accountScope, productID: proposal.product.id,
                        client: client)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard let proposal, let client = session.client(),
              client.pricingAccountScope == proposal.accountScope,
              !isSending, isVisible, scenePhase == .active else { return }
        if proposal.product.kind == .subscription {
            await submitSubscription(client: client, proposal: proposal)
            return
        }
        guard maySubmit, let plan else { return }
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        do {
            report = try await PricingSubmissionCoordinator.shared.submitConfirmed(
                proposal: proposal, reviewedPlan: plan, client: client)
            if report?.operation.state == .verifiedLive ||
               report?.operation.state == .verifiedScheduled {
                model.markRemoteStale()
            }
        } catch {
            errorMessage = error.localizedDescription
            model.markRemoteStale()
        }
    }

    @MainActor
    private func submitSubscription(client: AppStoreConnectAPIClient,
                                    proposal: RegionalPricingProposal) async {
        guard maySubmitSubscription, let details = subscriptionPlan else { return }
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        do {
            subscriptionReport = try await PricingSubmissionCoordinator.shared.submitSubscriptionConfirmed(
                proposal: proposal, reviewed: details,
                acknowledgesDecrease: acknowledgesDecrease,
                acknowledgesIncrease: acknowledgesIncrease, client: client)
            model.markRemoteStale() // Apple state may have partially changed.
        } catch {
            errorMessage = error.localizedDescription
            // A preflight error alone cannot prove prices changed; the
            // existing proposal stays visible, with a fresh review required.
            model.markRemoteStale()
        }
    }

    @MainActor
    private func reconcile() async {
        guard !isSending, let proposal, let client = session.client(),
              client.pricingAccountScope == proposal.accountScope else { return }
        isSending = true
        defer { isSending = false }
        do {
            report = try await PricingSubmissionCoordinator.shared.reconcile(
                accountScope: proposal.accountScope, productID: proposal.product.id,
                client: client)
            if report?.operation.state == .verifiedLive ||
               report?.operation.state == .verifiedScheduled {
                model.markRemoteStale()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func reconcileSubscription() async {
        guard !isSending, let proposal, let client = session.client(),
              client.pricingAccountScope == proposal.accountScope else { return }
        isSending = true
        defer { isSending = false }
        do {
            subscriptionReport = try await PricingSubmissionCoordinator.shared.reconcileSubscription(
                accountScope: proposal.accountScope, productID: proposal.product.id,
                client: client)
            if subscriptionReport?.batch.isComplete == true {
                model.markRemoteStale()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func resumeSubscription(reviewed: SubscriptionSubmissionBatch) async {
        guard !isSending, !isPreparing, isVisible, scenePhase == .active,
              subscriptionReport?.batch.id == reviewed.id,
              let client = session.client(),
              client.pricingAccountScope == reviewed.plan.accountScope else { return }
        isSending = true
        defer { isSending = false }
        do {
            subscriptionReport = try await PricingSubmissionCoordinator.shared.resumeSubscription(
                accountScope: reviewed.plan.accountScope, productID: reviewed.plan.product.id,
                batchID: reviewed.id, proposalFingerprint: reviewed.plan.proposalFingerprint,
                client: client)
            model.markRemoteStale()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func closeSubscription(reviewed: SubscriptionSubmissionBatch) async {
        guard !isSending, !isPreparing, subscriptionReport?.batch.id == reviewed.id,
              let client = session.client(),
              client.pricingAccountScope == reviewed.plan.accountScope else { return }
        isSending = true
        defer { isSending = false }
        do {
            subscriptionReport = try await PricingSubmissionCoordinator.shared.closeSubscription(
                accountScope: reviewed.plan.accountScope, productID: reviewed.plan.product.id,
                batchID: reviewed.id, client: client)
            subscriptionPlan = nil
            model.markRemoteStale()
            errorMessage = "Saved submission closed. Return to Regional Pricing, refresh Apple data, and regenerate before submitting a new proposal."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pauseDispatch() {
        guard let scope = subscriptionReport?.batch.plan.accountScope ?? proposal?.accountScope,
              let productID = subscriptionReport?.batch.plan.product.id ?? proposal?.product.id else { return }
        Task {
            await PricingSubmissionCoordinator.shared.pausePendingOperations(
                accountScope: scope, productID: productID)
        }
    }
}




