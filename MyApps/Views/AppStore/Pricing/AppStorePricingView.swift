import AppFoundation
import SwiftUI

/// Lazy, read-only list of purchasable products. It never loads every country's
/// price ladder while the user is browsing products.
private struct PricingProductGroup: Identifiable {
    let id: String
    let name: String
    let products: [PricingProduct]
}

struct AppStorePricingView: View {
    @Environment(\.appFoundationTheme) private var theme
    @EnvironmentObject private var session: AppStoreConnectSession

    let appID: String

    @State private var products: [PricingProduct] = []
    @State private var summaries: [String: PricingUSSummary] = [:]
    @State private var summaryErrors: [String: String] = [:]
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var requestID = UUID()

    private var filtered: [PricingProduct] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(text) ||
            ($0.productID?.localizedCaseInsensitiveContains(text) ?? false) ||
            ($0.groupName?.localizedCaseInsensitiveContains(text) ?? false)
        }
    }

    private var lifetimeProducts: [PricingProduct] {
        filtered.filter { $0.kind == .lifetime }
    }
    private var unsupported: [PricingProduct] {
        filtered.filter { $0.kind == .unsupported }
    }
    private var subscriptionGroups: [PricingProductGroup] {
        let subscriptions = filtered.filter { $0.kind == .subscription }
        return Dictionary(grouping: subscriptions) {
            $0.groupID ?? $0.id
        }.map { key, group in
            PricingProductGroup(id: key,
                name: group.first?.groupName ?? "Subscriptions",
                products: group.sorted { $0.name < $1.name })
        }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
    }

    var body: some View {
        List {
            if !hasLoaded && isLoading {
                ProgressView("Loading App Store products…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if !hasLoaded {
                ContentUnavailableView {
                    Label("Could Not Load Pricing", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage ?? "App Store Connect product discovery is unavailable.")
                } actions: {
                    Button("Retry") { Task { await load(refresh: true) } }
                }
                .listRowBackground(Color.clear)
            } else {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Retry") { Task { await load(refresh: true) } }
                    }
                }
                Section {
                    TextField("Find a product or subscription", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if lifetimeProducts.isEmpty && subscriptionGroups.isEmpty && unsupported.isEmpty {
                    ContentUnavailableView(
                        "No Products",
                        systemImage: "cart",
                        description: Text("There are no matching App Store Connect products.")
                    )
                    .listRowBackground(Color.clear)
                }
                if !lifetimeProducts.isEmpty {
                    Section("Lifetime Purchases") {
                        ForEach(lifetimeProducts) { product in
                            row(product)
                        }
                    }
                }
                ForEach(subscriptionGroups) { group in
                    Section(group.name) {
                        ForEach(group.products) { product in
                            row(product)
                        }
                    }
                }
                if !unsupported.isEmpty {
                    Section("Unsupported Products") {
                        ForEach(unsupported) { product in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.name)
                                Text(product.unsupportedReason ?? "Unsupported product type")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryForegroundColor)
                            }
                        }
                    }
                }
                Section {
                    Text("Pricing suggestions and review are read-only in this pass. App Store prices cannot be submitted yet.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryForegroundColor)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .myAppsPage()
        .refreshable { await load(refresh: true) }
        .onAppear {
            // When returning from a submitted product, refetch the current US
            // summaries; don't reuse prices loaded before the schedule write.
            if hasLoaded && !isLoading { Task { await load(refresh: true) } }
        }
        .task(id: session.connectionRevision) {
            requestID = UUID()
            hasLoaded = false
            isLoading = false
            products = []
            summaries = [:]
            summaryErrors = [:]
            await load(refresh: true)
        }
    }

    @ViewBuilder
    private func row(_ product: PricingProduct) -> some View {
        NavigationLink {
            RegionalPricingReviewView(product: product, client: session.client())
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(product.name)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    Spacer(minLength: 8)
                    if let summary = summaries[product.id], let price = summary.current {
                        Text(PricingDisplay.amount(price.customerPrice, currency: price.currency))
                            .font(.subheadline.weight(.medium))
                    } else if summaryErrors[product.id] != nil {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("US price could not be loaded")
                    } else if summaries[product.id] != nil {
                        Text("US price unknown")
                            .foregroundStyle(theme.secondaryForegroundColor)
                            .font(.caption)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                HStack(spacing: 6) {
                    Text(product.productID ?? "No product ID")
                        .lineLimit(1)
                    if let duration = product.duration {
                        Text("· " + duration.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.secondaryForegroundColor)
                if let failure = summaryErrors[product.id] {
                    Text(failure)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if let summary = summaries[product.id],
                          let warning = summary.issues.first {
                    Text(warning.message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 3)
        }
        .accessibilityLabel(product.name + ", " + (product.productID ?? "no product ID"))
    }

    @MainActor
    private func load(refresh: Bool) async {
        guard !isLoading else { return }
        guard let client = session.client() else {
            errorMessage = "Connect App Store Connect before loading pricing."
            hasLoaded = false
            return
        }
        let revision = session.connectionRevision
        let token = UUID()
        requestID = token
        isLoading = true
        errorMessage = nil
        defer { if requestID == token { isLoading = false } }
        do {
            let service = RegionalPricingService(client: client)
            let loaded = try await service.discoverProducts(appID: appID)
            guard requestID == token, revision == session.connectionRevision,
                  !Task.isCancelled else { return }
            products = loaded
            hasLoaded = true
            summaries = [:]
            summaryErrors = [:]
            let eligible = loaded.filter { $0.kind != .unsupported }
            for offset in stride(from: 0, to: eligible.count, by: 4) {
                try Task.checkCancellation()
                let batch = Array(eligible[offset..<min(offset + 4, eligible.count)])
                let results = await withTaskGroup(
                    of: (String, PricingUSSummary?, String?).self,
                    returning: [(String, PricingUSSummary?, String?)].self
                ) { group in
                    for product in batch {
                        group.addTask {
                            do {
                                let summary = try await service.loadUSSummary(product: product)
                                return (product.id, summary, nil)
                            } catch {
                                return (product.id, nil, error.localizedDescription)
                            }
                        }
                    }
                    var completed: [(String, PricingUSSummary?, String?)] = []
                    for await item in group { completed.append(item) }
                    return completed
                }
                guard requestID == token, revision == session.connectionRevision,
                      !Task.isCancelled else { return }
                for (id, summary, failure) in results {
                    if let summary { summaries[id] = summary }
                    if let failure { summaryErrors[id] = failure }
                }
            }
        } catch {
            guard requestID == token, revision == session.connectionRevision,
                  !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

enum PricingDisplay {
    static func amount(_ value: Decimal?, currency: String?) -> String {
        guard let value else { return "Unknown" }
        let code = currency ?? "?"
        let formatted = value.formatted(
            .currency(code: code == "?" ? "USD" : code)
                .locale(Locale(identifier: "en_US"))
        )
        return code == "?" ? NSDecimalNumber(decimal: value).stringValue + " (currency unknown)"
            : formatted + " " + code
    }

    static func country(_ id: String) -> String {
        // Ask Foundation to localize Apple's territory code. When no localized
        // display name exists, retain the full code instead of inventing a name.
        guard let localized = Locale.current.localizedString(forRegionCode: id),
              localized != id else { return id }
        return localized
    }
}
