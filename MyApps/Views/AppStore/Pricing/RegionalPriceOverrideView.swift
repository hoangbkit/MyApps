import AppFoundation
import SwiftUI

/// Country details and Apple-point-only override selection. No arbitrary price
/// typing is permitted and no request writes a price to App Store Connect.
struct RegionalPriceOverrideView: View {
    @Environment(\.appFoundationTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: RegionalPricingViewModel
    let territoryID: String

    private var row: RegionalPricingRow? {
        model.proposal?.rows.first { $0.territoryID == territoryID }
    }

    private var points: [PricingPoint] {
        model.referenceSet?.laddersByTerritory[territoryID] ?? []
    }

    var body: some View {
        Form {
            if let row {
                Section("Country") {
                    LabeledContent("Territory", value: PricingDisplay.country(row.territoryID))
                    LabeledContent("Code", value: row.territoryID)
                    LabeledContent("Currency", value: row.currency ?? "Unknown")
                    LabeledContent("Pricing Tier", value: row.tier.map { "Tier \($0)" }
                        ?? "Unmapped — Apple reference")
                    LabeledContent("Multiplier",
                        value: NSDecimalNumber(decimal: row.factor).stringValue)
                    LabeledContent("Source", value: row.mappingSource)
                    if let plan = row.planType {
                        LabeledContent("Billing Plan", value: plan)
                    }
                }
                Section("Prices") {
                    LabeledContent("Current at Effective Date",
                        value: PricingDisplay.amount(row.baselinePrice?.customerPrice,
                            currency: row.currency))
                    LabeledContent("Apple Reference",
                        value: PricingDisplay.amount(row.referencePoint?.customerPrice,
                            currency: row.currency))
                    LabeledContent("Target",
                        value: PricingDisplay.amount(row.targetPrice, currency: row.currency))
                    LabeledContent("Suggested",
                        value: PricingDisplay.amount(row.suggestedPoint?.customerPrice,
                            currency: row.currency))
                    LabeledContent("Selected",
                        value: PricingDisplay.amount(row.selectedPoint?.customerPrice,
                            currency: row.currency))
                    LabeledContent("Change", value: row.diff.rawValue.capitalized)
                    if row.maintenanceChanged {
                        Label("Maintenance mode changes from \(row.oldMode.rawValue) to \(row.proposedMode.rawValue).",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    if row.indirectChange {
                        Label("This country changes indirectly through Apple's configured base territory.",
                              systemImage: "info.circle")
                    }
                }
                if !row.baselineScheduled.isEmpty {
                    Section("Existing Scheduled Prices") {
                        ForEach(row.baselineScheduled) { price in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(PricingDisplay.amount(price.customerPrice,
                                                           currency: price.currency ?? row.currency))
                                Text("Starts \(price.startDate ?? "unknown") · \(price.origin.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryForegroundColor)
                            }
                        }
                    }
                }
                if !row.warnings.isEmpty || !row.blockers.isEmpty {
                    Section("Warnings and Blockers") {
                        ForEach(row.blockers, id: \.self) { blocker in
                            Label(blocker, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        ForEach(row.warnings, id: \.self) { warning in
                            Label(warning.rawValue, systemImage: "info.circle")
                                .foregroundStyle(theme.secondaryForegroundColor)
                        }
                    }
                }
                Section {
                    Toggle("Exclude From Proposal", isOn: Binding(
                        get: { model.proposal?.exclusions.contains(territoryID) ?? row.excluded },
                        set: { model.setExcluded(territoryID: territoryID, excluded: $0) }
                    ))
                    .disabled(!model.isReviewCurrent)
                    if row.overridePoint != nil {
                        Button("Reset to Suggested Price") {
                            model.resetOverride(territoryID: territoryID)
                        }
                        .disabled(!model.isReviewCurrent)
                    }
                } footer: {
                    Text("Exceptional countries must be explicitly excluded, never silently omitted. Automatic base-price effects may still block exclusion.")
                }
                Section {
                    if !model.isReviewCurrent {
                        Text("Refresh and regenerate before changing a country price.")
                            .foregroundStyle(theme.secondaryForegroundColor)
                    } else if territoryID == "USA" {
                        Text("Change the US reference using the main review screen; US overrides are not permitted.")
                            .foregroundStyle(theme.secondaryForegroundColor)
                    } else if points.isEmpty {
                        Text("Apple has not supplied a valid price-point ladder for this country.")
                            .foregroundStyle(theme.secondaryForegroundColor)
                    } else {
                        ForEach(points) { point in
                            Button {
                                model.overridePrice(territoryID: territoryID, point: point)
                            } label: {
                                HStack {
                                    Text(PricingDisplay.amount(point.customerPrice,
                                                               currency: point.currency))
                                        .foregroundStyle(theme.primaryForegroundColor)
                                    Spacer()
                                    if point.id == row.selectedPoint?.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .disabled(model.isWorking)
                        }
                    }
                } header: {
                    Text("Apple Valid Price Points")
                } footer: {
                    Text("Choose an exact Apple price point. A manual override stays in your draft; it does not change App Store Connect.")
                }
            } else {
                ContentUnavailableView("Country Not Found", systemImage: "questionmark.circle")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .myAppsPage()
        .navigationTitle(PricingDisplay.country(territoryID))
        .navigationBarTitleDisplayMode(.inline)
    }
}
