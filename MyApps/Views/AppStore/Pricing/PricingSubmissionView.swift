import AppFoundation
import SwiftUI

/// Read-only review scaffolding. Pricing writes are deliberately unavailable
/// until the corresponding lifetime/subscription submission passes.
struct PricingSubmissionView: View {
    @Environment(\.appFoundationTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let proposal: RegionalPricingProposal
    let isCurrentReview: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    LabeledContent("Name", value: proposal.product.name)
                    LabeledContent("Product ID", value: proposal.product.productID ?? "Unknown")
                    LabeledContent("US Reference",
                        value: PricingDisplay.amount(proposal.selectedUSPoint.customerPrice,
                            currency: proposal.selectedUSPoint.currency))
                    LabeledContent("Effective Date", value: proposal.effectiveDate)
                    if proposal.product.kind == .lifetime {
                        LabeledContent("Configured Base Territory",
                            value: proposal.configuredBaseTerritory ?? "Not configured")
                    }
                }
                Section("Reviewed Scope") {
                    LabeledContent("Eligible", value: "\(proposal.summary.eligible)")
                    LabeledContent("Price Increases", value: "\(proposal.summary.increases)")
                    LabeledContent("Price Decreases", value: "\(proposal.summary.decreases)")
                    LabeledContent("Excluded", value: "\(proposal.summary.excluded)")
                    LabeledContent("Blocked", value: "\(proposal.summary.blocked)")
                    if proposal.summary.automaticToManual > 0 {
                        Label("\(proposal.summary.automaticToManual) lifetime countries would switch from automatic to manual price maintenance.",
                              systemImage: "exclamationmark.triangle")
                    }
                }
                Section("Safety") {
                    if !isCurrentReview {
                        Label("This proposal is stale or requires regeneration.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if proposal.product.kind == .subscription {
                        Text("Subscription changes require review of subscriber preservation, decreases at renewal, notifications, consent, and scheduled price conflicts. These protections are not yet implemented.")
                    } else {
                        Text("Lifetime submissions require a fresh write preflight, configured-base verification, and a durable submission journal. These protections are not yet implemented.")
                    }
                    Text("Submitting App Store Connect prices is unavailable in Pass 3. No Apple pricing requests will be sent from this screen.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryForegroundColor)
                }
                Section {
                    Button("Submit Prices") {}
                        .disabled(true)
                } footer: {
                    Text("Submission becomes available only after a separately reviewed implementation pass.")
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
        }
    }
}
