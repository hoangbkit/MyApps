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
    @State private var confirmingResume = false
    @State private var errorMessage: String?
    @State private var isPreparing = false
    @State private var isSending = false
    @State private var confirmingSubmission = false
    @State private var loaded = false

    private var proposal: RegionalPricingProposal? { model.proposal }

    var body: some View {
        NavigationStack {
            Form {
                if let proposal {
                    Section("Product") {
                        LabeledContent("Name", value: proposal.product.name)
                        LabeledContent("Product ID", value: proposal.product.productID ?? "Unknown")
                        LabeledContent("US Reference", value:
                            PricingDisplay.amount(proposal.selectedUSPoint.customerPrice,
                                                  currency: proposal.selectedUSPoint.currency))
                        LabeledContent("Effective Date", value: proposal.effectiveDate)
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
                            Text("Price increases preserve the current public price for existing subscribers. Previously preserved cohorts are not un-preserved.")
                            Text("Price decreases affect existing subscribers at renewal. You cannot preserve a higher price through a decrease.")
                            Text("Apple controls any required notifications or consent. The API cannot prove individual subscriber treatment, even when new public prices are verified.")
                        } else {
                            Text("One complete lifetime price schedule will be sent only after final confirmation. Apple may adjust other automatic storefront prices; any unresolved effects block submission.")
                            Text("Apple acceptance does not mean prices are live. Verification or read-only reconciliation may still be needed.")
                        }
                    }
                    if let subscriptionReport {
                        subscriptionReportSection(subscriptionReport)
                    }
                    if let report {
                        Section("Submission Status") {
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
                            if subscriptionPlan?.isNoOp == true {
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
                if loaded { model.markRemoteStale() }
                loaded = true
                await loadPrevious()
                await prepare()
            }
            .onChange(of: acknowledgesDecrease) { _, _ in
                if proposal?.product.kind == .subscription {
                    Task { await prepare() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { pauseDispatch() }
            }
            .onDisappear { pauseDispatch() }
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
                    Text("Send \(subscriptionPlan.changes.count) separate territory price requests. \(subscriptionPlan.excluded.count) countries are excluded. Existing subscriber prices are preserved on increases; decreases affect renewals. A partial submission cannot be rolled back together.")
                } else if let plan {
                    Text("Send 1 schedule for \(plan.affectedTerritories.count) changed storefronts, preserve \(plan.preservedEntries.count) manual entries, and keep base territory \(plan.baseTerritoryID). \(plan.excludedTerritories.count) countries are excluded. This request cannot be automatically undone.")
                }
            }
            .confirmationDialog("Resume Remaining Subscription Changes?",
                                isPresented: $confirmingResume,
                                titleVisibility: .visible) {
                Button("Resume Verified Remaining Requests") {
                    Task { await resumeSubscription() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only planned or definitively rejected changes are eligible. The app rechecks Apple state and will not replay accepted or unknown requests.")
            }
        }
    }

    private var maySubmit: Bool {
        guard let proposal, let plan else { return false }
        return proposal.product.kind == .lifetime && model.isReviewCurrent &&
            plan.isExecutable && !isPreparing && !isSending &&
            (report == nil || [.planned, .failed, .verifiedLive, .verifiedScheduled].contains(report!.operation.state))
    }

    @MainActor
    private func prepare() async {
        guard !isPreparing, !isSending, let proposal,
              proposal.product.kind == .lifetime else { return }
        guard model.isReviewCurrent, let client = session.client(),
              client.pricingAccountScope == proposal.accountScope else {
            errorMessage = "Review or reconnect this proposal before preparing a submission."
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        errorMessage = nil
        do {
            let fresh = try await PricingSubmissionCoordinator.shared.prepare(
                proposal: proposal, client: client)
            guard !Task.isCancelled else { return }
            plan = fresh
            if fresh.blockers.contains(where: { $0.contains("changed since review") }) {
                model.markRemoteStale()
            }
        } catch {
            plan = nil
            errorMessage = error.localizedDescription
            model.markRemoteStale()
        }
    }

    @MainActor
    private func loadPrevious() async {
        guard let proposal else { return }
        do {
            report = try await PricingSubmissionCoordinator.shared.previous(
                accountScope: proposal.accountScope, productID: proposal.product.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard maySubmit, let proposal, let plan,
              let client = session.client(),
              client.pricingAccountScope == proposal.accountScope else { return }
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
    private func reconcile() async {
        guard !isSending, let proposal,
              let client = session.client(),
              client.pricingAccountScope == proposal.accountScope else { return }
        isSending = true
        defer { isSending = false }
        do {
            report = try await PricingSubmissionCoordinator.shared.reconcile(
                accountScope: proposal.accountScope,
                productID: proposal.product.id, client: client)
            if report?.operation.state == .verifiedLive ||
               report?.operation.state == .verifiedScheduled {
                model.markRemoteStale()
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
