import CryptoKit
import Foundation

/// Pure generator. No network access, credentials, clock reads, or remote mutation.
/// The service must fetch complete Apple equalizations and ladders beforehand.
enum RegionalPricingEngine {
    static func generate(
        snapshot: PricingSnapshot,
        selectedUSPoint: PricingPoint,
        preset: RegionalPricingPreset = .balanced,
        mapping: RegionalPricingMapping,
        effectiveDate: String,
        references: RegionalPricingReferenceSet,
        existingOverrides: [RegionalPricingOverride] = [],
        exclusions: Set<String> = [],
        proposalID: UUID = UUID()
    ) throws -> RegionalPricingProposal {
        guard validDate(effectiveDate) else { throw RegionalPricingError.invalidDate }
        guard snapshot.product.kind != .unsupported,
              selectedUSPoint.territoryID == "USA",
              selectedUSPoint.productID == snapshot.product.id,
              selectedUSPoint.customerPrice > 0,
              snapshot.usPoints.contains(where: {
                  $0.id == selectedUSPoint.id && $0.customerPrice == selectedUSPoint.customerPrice
              }),
              references.sourceUSPoint.id == selectedUSPoint.id,
              references.sourceUSPoint.productID == selectedUSPoint.productID else {
            throw RegionalPricingError.invalidReference("Select an existing valid Apple US price point for this product.")
        }
        _ = try mapping.validate(knownTerritories: snapshot.territories.map(\.id))
        guard preset.factors.count == 5,
              (1...5).allSatisfy({ tier in
                  guard let factor = preset.factors[tier] else { return false }
                  return factor > 0 && factor <= 1
              }),
              preset.factors[1] == 1 else {
            throw RegionalPricingError.invalidMapping("Preset requires positive factors ≤1 and an undiscouted USA.")
        }
        guard references.planType == nil || references.planType == "UPFRONT" else {
            throw RegionalPricingError.invalidReference("Monthly-with-commitment plans require adjusted equalizations.")
        }
        let overrides = Dictionary(
            existingOverrides.map { ($0.territoryID + ":" + ($0.planType ?? "-"), $0) },
            uniquingKeysWith: { _, later in later }
        )
        var rows: [RegionalPricingRow] = []
        for territory in snapshot.territories.sorted(by: { $0.id < $1.id })
            where territory.available != false {
            let apple = references.equalizedByTerritory[territory.id]
            let assignment = mapping.assignment(for: territory.id)
            let fallback = assignment == nil || assignment?.needsReview == true
            let tier = fallback ? nil : assignment?.tier
            let factor = fallback ? Decimal(1) : preset.factors[tier ?? 1] ?? 1
            let plan = snapshot.product.kind == .subscription ? references.planType : nil
            let overrideKey = territory.id + ":" + (plan ?? "-")
            let manualOverride = overrides[overrideKey]
            var warnings: [RegionalPricingWarning] = []
            var blockers: [String] = []
            if assignment == nil { warnings.append(.unmapped) }
            if assignment?.needsReview == true { warnings.append(.unverifiedMapping) }
            if territory.available == nil {
                warnings.append(.unknownAvailability)
                blockers.append("Apple product availability is unknown.")
            }
            if territory.currency == nil {
                blockers.append("Apple territory currency is missing.")
            }
            if snapshot.product.kind == .lifetime && snapshot.baseTerritoryID == nil &&
                snapshot.scheduleID != nil {
                warnings.append(.missingBaseTerritory)
                blockers.append("Configured IAP base territory is unknown.")
            }
            if snapshot.product.kind == .subscription {
                let supported = snapshot.planTerritories.first { $0.planType == "UPFRONT" }
                if plan != "UPFRONT" || supported == nil ||
                   supported?.territoryIDs.contains(territory.id) != true {
                    warnings.append(.unsupportedPlan)
                    blockers.append("A verified UPFRONT subscription plan is unavailable for this country.")
                }
            }
            if !references.readIssues.isEmpty {
                warnings.append(.incompleteSnapshot)
                blockers.append("Price-point reference reads are incomplete; refresh from Apple.")
            }
            let reference = territory.id == "USA" ? selectedUSPoint : apple
            if reference == nil {
                warnings.append(.missingReference)
                blockers.append("Apple equalized reference for selected US point is missing.")
            }
            let target = reference.map { $0.customerPrice * factor }
            let ladder = references.laddersByTerritory[territory.id] ?? []
            let usable = validLadder(ladder, product: snapshot.product, territory: territory,
                plan: plan)
            if usable.count != ladder.count {
                warnings.append(.invalidLadder)
                blockers.append("The Apple price-point ladder contains mismatched or unvalidated entries.")
            }
            if usable.isEmpty {
                warnings.append(.missingLadder)
                blockers.append("No positive valid Apple price points available for this country.")
            }
            var suggestion: PricingPoint?
            if territory.id == "USA" {
                suggestion = selectedUSPoint
            } else if let target, !usable.isEmpty {
                suggestion = nearest(to: target, points: usable, referenceID: reference?.id)
                if let minimum = usable.first?.customerPrice,
                   let maximum = usable.last?.customerPrice,
                   (target < minimum || target > maximum) {
                    warnings.append(.clamped)
                }
            }
            var chosen = suggestion
            if let manualOverride {
                let match = usable.first { $0.id == manualOverride.point.id &&
                    $0.customerPrice == manualOverride.point.customerPrice &&
                    $0.currency == manualOverride.point.currency &&
                    $0.planType == manualOverride.point.planType }
                if territory.id == "USA" || match == nil {
                    warnings.append(.invalidOverride)
                    blockers.append("Saved override is no longer a valid selectable price point.")
                    chosen = nil // Keep overridePoint for review; never silently discard it.
                } else {
                    chosen = match
                }
            }

            // Price baseline is public (new subscribers), never preserved cohort prices.
            let baseline = snapshot.publicPrice(territoryID: territory.id,
                planType: plan, on: effectiveDate)
            let future = snapshot.prices.filter {
                $0.territoryID == territory.id && $0.preserved != true &&
                (plan == nil || $0.planType == plan) &&
                ($0.startDate ?? "") > effectiveDate
            }.sorted { ($0.startDate ?? "") < ($1.startDate ?? "") }
            if !future.isEmpty {
                warnings.append(.pendingFutureSchedule)
                blockers.append("A future Apple price schedule must be resolved before submission.")
            }
            if baseline?.customerPrice == nil {
                warnings.append(.unknownBaseline)
                blockers.append("Current public price is unknown; cannot safely calculate change.")
            }

            let oldMode: RegionalPricingMode
            switch baseline?.origin {
            case .automaticIAP: oldMode = .automatic
            case .manualIAP: oldMode = .manual
            case .subscription: oldMode = .subscription
            case nil: oldMode = .unknown
            }
            let proposedMode: RegionalPricingMode
            if snapshot.product.kind == .subscription {
                proposedMode = .subscription
            } else if territory.id == snapshot.baseTerritoryID {
                proposedMode = .base
            } else if oldMode == .manual {
                // Never automatically reset existing manual prices to automatic.
                proposedMode = .manual
            } else if let automatic = references.automaticFromConfiguredBase?[territory.id],
                      chosen?.id == automatic.id {
                proposedMode = .automatic
            } else {
                proposedMode = .manual
                if references.automaticFromConfiguredBase == nil {
                    blockers.append("Automatic price effect of configured IAP base is unverified.")
                }
            }
            if proposedMode == .manual && oldMode == .automatic {
                warnings.append(.manualMaintenance)
            }
            let diff: RegionalPricingDiff
            if let old = baseline?.customerPrice, let new = chosen?.customerPrice {
                diff = new > old ? .increase : (new < old ? .decrease : .unchanged)
            } else {
                diff = .unknown
            }
            let maintenanceChanged = oldMode != .unknown && oldMode != proposedMode &&
                !(territory.id == snapshot.baseTerritoryID && oldMode == .manual)
            let indirect = oldMode == .automatic && proposedMode == .automatic &&
                diff != .unchanged
            if indirect { warnings.append(.indirectAutomaticChange) }
            let isExcluded = exclusions.contains(territory.id)
            if isExcluded && (indirect || territory.id == snapshot.baseTerritoryID) {
                blockers.append("Excluded country can still be affected by base-price equalization.")
            }
            rows.append(RegionalPricingRow(
                territoryID: territory.id, planType: plan, tier: tier, factor: factor,
                mappingSource: fallback ? "unverified — Apple reference" : assignment!.source,
                currency: territory.currency, referencePoint: reference, targetPrice: target,
                suggestedPoint: suggestion, overridePoint: manualOverride?.point,
                selectedPoint: chosen, baselinePrice: baseline, baselineScheduled: future,
                oldMode: oldMode, proposedMode: proposedMode, diff: diff,
                maintenanceChanged: maintenanceChanged, indirectChange: indirect,
                excluded: isExcluded,
                warnings: Array(Set(warnings)).sorted { $0.rawValue < $1.rawValue },
                blockers: Array(Set(blockers)).sorted()
            ))
        }

        let summary = RegionalPricingSummary(
            eligible: rows.count,
            increases: rows.filter { !$0.excluded && $0.diff == .increase }.count,
            decreases: rows.filter { !$0.excluded && $0.diff == .decrease }.count,
            unchanged: rows.filter { !$0.excluded && $0.isNoOp }.count,
            unknown: rows.filter { !$0.excluded && $0.diff == .unknown }.count,
            warnings: rows.reduce(0) { $0 + $1.warnings.count },
            blocked: rows.filter { !$0.excluded && !$0.blockers.isEmpty }.count,
            excluded: rows.filter(\.excluded).count,
            automaticToManual: rows.filter { !$0.excluded &&
                $0.oldMode == .automatic && $0.proposedMode == .manual }.count
        )
        let sortedOverrides = existingOverrides.sorted {
            $0.territoryID == $1.territoryID ?
                ($0.planType ?? "") < ($1.planType ?? "") :
                $0.territoryID < $1.territoryID
        }
        let selectedExclusions = exclusions.sorted()
        let fingerprint = fingerprint(
            snapshot: snapshot, us: selectedUSPoint, preset: preset,
            mapping: mapping, date: effectiveDate, rows: rows
        )
        return RegionalPricingProposal(
            id: proposalID, schemaVersion: 1, accountScope: snapshot.accountScope,
            product: snapshot.product, snapshotFingerprint: snapshot.semanticFingerprint,
            snapshotFetchedAt: snapshot.fetchedAt, selectedUSPoint: selectedUSPoint,
            presetID: preset.id, presetVersion: preset.version,
            mappingVersion: mapping.version, effectiveDate: effectiveDate,
            configuredBaseTerritory: snapshot.baseTerritoryID,
            overrides: sortedOverrides, exclusions: selectedExclusions,
            rows: rows, summary: summary, fingerprint: fingerprint
        )
    }

    static func withOverride(_ override: RegionalPricingOverride,
                             existing: [RegionalPricingOverride]) -> [RegionalPricingOverride] {
        (existing.filter {
            !($0.territoryID == override.territoryID && $0.planType == override.planType)
        } + [override]).sorted { $0.territoryID < $1.territoryID }
    }

    static func reset(territory: String, plan: String?,
                      overrides: [RegionalPricingOverride]) -> [RegionalPricingOverride] {
        overrides.filter { $0.territoryID != territory || $0.planType != plan }
    }

    static func resetAllOverrides() -> [RegionalPricingOverride] { [] }

    private static func validLadder(_ points: [PricingPoint], product: PricingProduct,
                                    territory: PricingTerritory, plan: String?) -> [PricingPoint] {
        points.filter {
            $0.customerPrice > 0 && $0.productID == product.id &&
            $0.territoryID == territory.id && $0.currency == territory.currency &&
            $0.planType == plan
        }.sorted {
            if $0.customerPrice != $1.customerPrice { return $0.customerPrice < $1.customerPrice }
            return $0.id < $1.id
        }
    }

    static func nearest(to target: Decimal, points: [PricingPoint],
                        referenceID: String?) -> PricingPoint? {
        points.min { left, right in
            let ld = left.customerPrice > target ?
                left.customerPrice - target : target - left.customerPrice
            let rd = right.customerPrice > target ?
                right.customerPrice - target : target - right.customerPrice
            if ld != rd { return ld < rd }
            if left.customerPrice != right.customerPrice {
                return left.customerPrice < right.customerPrice
            }
            if let referenceID {
                if left.id == referenceID { return true }
                if right.id == referenceID { return false }
            }
            return left.id < right.id
        }
    }

    private static func validDate(_ value: String) -> Bool {
        guard value.range(of: #"^\\d{4}-\\d{2}-\\d{2}$"#,
                          options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }

    private static func fingerprint(
        snapshot: PricingSnapshot, us: PricingPoint, preset: RegionalPricingPreset,
        mapping: RegionalPricingMapping, date: String, rows: [RegionalPricingRow]
    ) -> String {
        func decimal(_ value: Decimal?) -> String {
            value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "?"
        }
        var lines = [
            "1", snapshot.accountScope, snapshot.product.id,
            snapshot.semanticFingerprint, mapping.version, mapping.ruleVersion,
            preset.id, String(preset.version), us.id, decimal(us.customerPrice), date,
            snapshot.baseTerritoryID ?? "-"
        ]
        for row in rows.sorted(by: { $0.id < $1.id }) {
            lines.append([
                row.id, row.currency ?? "?", String(row.tier ?? 0),
                decimal(row.factor), row.referencePoint?.id ?? "?",
                decimal(row.targetPrice), row.suggestedPoint?.id ?? "?",
                row.overridePoint?.id ?? "?", row.selectedPoint?.id ?? "?",
                row.diff.rawValue, row.oldMode.rawValue, row.proposedMode.rawValue,
                row.excluded ? "excluded" : "included",
                row.baselinePrice?.id ?? "?",
                row.baselineScheduled.map(\.id).sorted().joined(separator: ","),
                row.warnings.map(\.rawValue).joined(separator: ","),
                row.blockers.joined(separator: ",")
            ].joined(separator: "|"))
        }
        return SHA256.hash(data: Data(lines.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
