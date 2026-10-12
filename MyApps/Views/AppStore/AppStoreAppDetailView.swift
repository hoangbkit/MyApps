import SwiftUI

struct AppStoreAppDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    private enum AppDetailMode: String, CaseIterable, Identifiable {
        case info = "Info"
        case xcodeCloud = "Xcode Cloud"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .info: "info.circle"
            case .xcodeCloud: "cloud"
            }
        }
    }

    let app: AppStoreConnectApp
    let client: AppStoreConnectAPIClient?
    let iconURL: URL?

    @State private var selectedSection: AppDetailMode = .info
    @State private var versions: [AppStoreConnectVersion] = []
    @State private var hasLoadedInfo = false
    @State private var isLoadingInfo = false
    @State private var infoError: String?

    @State private var product: AppStoreConnectProduct?
    @State private var workflows: [AppStoreConnectWorkflow] = []
    @State private var runs: [AppStoreConnectBuildRun] = []
    @State private var hasLoadedCloud = false
    @State private var isLoadingCloud = false
    @State private var cloudError: String?
    @State private var isPresentingStartBuild = false
    @State private var recentlyStartedRun: AppStoreConnectBuildRun?

    var body: some View {
        Group {
            switch selectedSection {
            case .info:
                infoView
            case .xcodeCloud:
                xcodeCloudView
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(app.attributes.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedSection == .xcodeCloud && product != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingStartBuild = true
                    } label: {
                        Label("Start Build", systemImage: "play.circle")
                    }
                    .disabled(!hasLoadedCloud || isLoadingCloud ||
                              !workflows.contains(where: { $0.attributes.isEnabled == true }))
                    .accessibilityLabel("Start Xcode Cloud Build")
                }
            }

            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(AppDetailMode.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            Label(
                                section.rawValue,
                                systemImage: selectedSection == section ? "checkmark" : section.symbol
                            )
                        }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text(app.attributes.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(selectedSection.rawValue)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 190)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("App sections, currently \(selectedSection.rawValue)")
                .accessibilityHint("Choose Info or Xcode Cloud")
            }
        }
        .sheet(isPresented: $isPresentingStartBuild) {
            StartXcodeCloudBuildView(
                appName: app.attributes.name,
                workflows: workflows,
                client: client
            ) { created in
                recentlyStartedRun = created
                runs.removeAll { $0.id == created.id }
                runs.insert(created, at: 0)
                Task { await loadCloud() }
            }
        }
        .task(id: "\(selectedSection.rawValue)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            switch selectedSection {
            case .info:
                if !hasLoadedInfo { await loadInfo() }
            case .xcodeCloud:
                if !hasLoadedCloud { await loadCloud() }
                while !Task.isCancelled && scenePhase == .active && selectedSection == .xcodeCloud {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        break
                    }
                    guard !Task.isCancelled, scenePhase == .active,
                          selectedSection == .xcodeCloud else { break }
                    // Poll only while a build is queued/running. There is no
                    // background network activity when the app is inactive.
                    if hasLoadedCloud && runs.contains(where: {
                        XcodeCloudDisplay.isInProgress($0.attributes)
                    }) {
                        await loadCloud()
                    }
                }
            }
        }
    }

    private var infoView: some View {
        List {
            Section("App Information") {
                HStack(spacing: 14) {
                    AppStoreAppIconView(
                        name: app.attributes.name,
                        url: iconURL,
                        size: 64
                    )
                    Text(app.attributes.name)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                .padding(.vertical, 4)
                if let bundleID = app.attributes.bundleId {
                    LabeledContent("Bundle ID", value: bundleID)
                }
                if let sku = app.attributes.sku {
                    LabeledContent("SKU", value: sku)
                }
                if let primaryLocale = app.attributes.primaryLocale {
                    LabeledContent("Primary Locale", value: primaryLocale)
                }
                LabeledContent("Apple App ID", value: app.id)
                if let madeForKids = app.attributes.isOrEverWasMadeForKids {
                    LabeledContent("Made for Kids", value: madeForKids ? "Yes" : "No")
                }
            }

            Section("App Store Versions") {
                if isLoadingInfo && !hasLoadedInfo {
                    ProgressView("Loading versions…")
                } else if !hasLoadedInfo {
                    Button("Retry Loading Versions") {
                        Task { await loadInfo() }
                    }
                } else if versions.isEmpty {
                    Text("No App Store versions were returned.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(versions.sorted(by: versionSort)) { version in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(version.attributes.versionString ?? "Unknown version")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Spacer()
                                if let platform = version.attributes.platform {
                                    Text(displayPlatform(platform))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let state = version.attributes.state {
                                Text(displayState(state))
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadInfo() }
        .alert(
            "App Information",
            isPresented: Binding(
                get: { infoError != nil },
                set: { if !$0 { infoError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoError ?? "")
        }
    }

    private var xcodeCloudView: some View {
        List {
            if isLoadingCloud && !hasLoadedCloud {
                ProgressView("Loading Xcode Cloud…")
            } else if !hasLoadedCloud {
                ContentUnavailableView {
                    Label("Could Not Load Xcode Cloud", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Retry") { Task { await loadCloud() } }
                }
                .listRowBackground(Color.clear)
            } else if product == nil {
                ContentUnavailableView {
                    Label("Xcode Cloud Not Configured", systemImage: "cloud")
                } description: {
                    Text("This app has no Xcode Cloud product in App Store Connect.")
                }
                .listRowBackground(Color.clear)
            } else {
                if let product {
                    Section("Product") {
                        LabeledContent("Name", value: product.attributes.name ?? app.attributes.name)
                        if let productType = product.attributes.productType {
                            LabeledContent("Type", value: displayState(productType))
                        }
                    }
                }

                if let recentlyStartedRun {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(recentlyStartedRun.attributes.number.map {
                                    "Build #\($0) requested"
                                } ?? "Build requested")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text("Xcode Cloud accepted the request. Pull down to refresh its progress.")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section("Workflows") {
                    if workflows.isEmpty {
                        Text("No workflows found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workflows.sorted {
                            $0.attributes.name.localizedStandardCompare($1.attributes.name) == .orderedAscending
                        }) { workflow in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(workflow.attributes.name)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Spacer()
                                    if let enabled = workflow.attributes.isEnabled {
                                        Text(enabled ? "Enabled" : "Disabled")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(enabled ? Color.green : Color.secondary)
                                    }
                                }
                                if let description = workflow.attributes.description, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section {
                    if runs.isEmpty {
                        Text("No Xcode Cloud builds found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(runs) { run in
                            NavigationLink {
                                XcodeCloudBuildDetailView(
                                    initialRun: run,
                                    workflowName: workflows.first(where: {
                                        $0.id == run.relationships?.workflow?.data?.id
                                    })?.attributes.name,
                                    client: client
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: XcodeCloudDisplay.symbol(
                                        run.attributes.completionStatus,
                                        progress: run.attributes.executionProgress
                                    ))
                                    .foregroundStyle(XcodeCloudDisplay.color(
                                        run.attributes.completionStatus,
                                        progress: run.attributes.executionProgress
                                    ))
                                    .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(run.attributes.number.map { "Build #\($0)" } ?? "Build")
                                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            Spacer()
                                            Text(buildStatus(run))
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        if let workflowID = run.relationships?.workflow?.data?.id,
                                           let workflow = workflows.first(where: { $0.id == workflowID }) {
                                            Text(workflow.attributes.name)
                                                .font(.system(size: 13, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        if let message = run.attributes.sourceCommit?.message,
                                           let firstLine = message.components(separatedBy: .newlines).first,
                                           !firstLine.isEmpty {
                                            Text(firstLine)
                                                .font(.system(size: 13, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        if let created = formattedDate(run.attributes.createdDate) {
                                            Text(created)
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                } header: {
                    Text("Build Runs")
                } footer: {
                    Text("Showing the latest loaded Xcode Cloud build runs. Pull down to refresh.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadCloud() }
        .alert(
            "Xcode Cloud",
            isPresented: Binding(
                get: { cloudError != nil },
                set: { if !$0 { cloudError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cloudError ?? "")
        }
    }

    @MainActor
    private func loadInfo() async {
        guard let client else { return }
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        do {
            let fetched = try await client.versions(for: app)
            guard !Task.isCancelled else { return }
            versions = fetched
            hasLoadedInfo = true
            infoError = nil
        } catch {
            guard !Task.isCancelled else { return }
            infoError = error.localizedDescription
        }
    }

    @MainActor
    private func loadCloud() async {
        guard let client, !isLoadingCloud else { return }
        isLoadingCloud = true
        defer { isLoadingCloud = false }
        do {
            guard let fetchedProduct = try await client.product(for: app) else {
                guard !Task.isCancelled else { return }
                product = nil
                workflows = []
                runs = []
                hasLoadedCloud = true
                cloudError = nil
                return
            }
            async let fetchedWorkflows = client.workflows(for: fetchedProduct)
            async let fetchedRuns = client.recentBuildRuns(for: fetchedProduct)
            let (loadedWorkflows, loadedRuns) = try await (fetchedWorkflows, fetchedRuns)
            guard !Task.isCancelled else { return }
            product = fetchedProduct
            workflows = loadedWorkflows
            var visibleRuns = loadedRuns
            if let recentlyStartedRun,
               !visibleRuns.contains(where: { $0.id == recentlyStartedRun.id }) {
                // Apple's listing may lag behind a successful 201 response.
                visibleRuns.insert(recentlyStartedRun, at: 0)
            }
            runs = visibleRuns
            hasLoadedCloud = true
            cloudError = nil
        } catch {
            guard !Task.isCancelled else { return }
            cloudError = error.localizedDescription
        }
    }

    private func versionSort(_ lhs: AppStoreConnectVersion, _ rhs: AppStoreConnectVersion) -> Bool {
        let left = lhs.attributes.createdDate ?? ""
        let right = rhs.attributes.createdDate ?? ""
        return left == right ? lhs.id < rhs.id : left > right
    }

    private func displayPlatform(_ platform: String) -> String {
        switch platform {
        case "IOS": "iOS"
        case "MAC_OS": "macOS"
        case "TV_OS": "tvOS"
        case "VISION_OS": "visionOS"
        default: platform
        }
    }

    private func displayState(_ state: String) -> String {
        state.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func buildStatus(_ run: AppStoreConnectBuildRun) -> String {
        XcodeCloudDisplay.status(
            run.attributes.completionStatus,
            progress: run.attributes.executionProgress
        )
    }

    private func formattedDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = withFractions.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        return date?.formatted(date: .abbreviated, time: .shortened)
    }
}
