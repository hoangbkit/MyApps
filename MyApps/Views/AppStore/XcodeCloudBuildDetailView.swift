import SwiftUI

/// Detail and diagnostics for one Xcode Cloud build. All data comes from the
/// App Store Connect API, including the branch and source commit.
struct XcodeCloudBuildDetailView: View {
    @Environment(\.scenePhase) private var scenePhase

    let initialRun: AppStoreConnectBuildRun
    let workflowName: String?
    let client: AppStoreConnectAPIClient?

    @State private var detail: AppStoreConnectBuildDetail?
    @State private var actions: [AppStoreConnectBuildAction] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var run: AppStoreConnectBuildRun { detail?.run ?? initialRun }

    private var isInProgress: Bool {
        XcodeCloudDisplay.isInProgress(run.attributes)
    }

    var body: some View {
        List {
            if isLoading && !hasLoaded {
                ProgressView("Loading build details…")
            } else if !hasLoaded {
                ContentUnavailableView {
                    Label("Build Details Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage ?? "Could not load the Xcode Cloud build.")
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
                .listRowBackground(Color.clear)
            } else {
                Section("Build") {
                    LabeledContent("Status") {
                        Label(
                            XcodeCloudDisplay.status(run.attributes.completionStatus, progress: run.attributes.executionProgress),
                            systemImage: XcodeCloudDisplay.symbol(run.attributes.completionStatus, progress: run.attributes.executionProgress)
                        )
                        .foregroundStyle(XcodeCloudDisplay.color(run.attributes.completionStatus, progress: run.attributes.executionProgress))
                    }
                    if let name = detail?.workflowName ?? workflowName {
                        LabeledContent("Workflow", value: name)
                    }
                    if let branch = detail?.sourceReferenceName {
                        LabeledContent("Branch / Tag", value: branch)
                    }
                    if let reason = run.attributes.startReason {
                        LabeledContent("Triggered By", value: XcodeCloudDisplay.readable(reason))
                    }
                    if let created = XcodeCloudDisplay.date(run.attributes.createdDate) {
                        LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let started = XcodeCloudDisplay.date(run.attributes.startedDate) {
                        LabeledContent("Started", value: started.formatted(date: .abbreviated, time: .shortened))
                        if let finished = XcodeCloudDisplay.date(run.attributes.finishedDate) {
                            LabeledContent("Duration", value: XcodeCloudDisplay.duration(from: started, to: finished))
                        }
                    }
                    if let finished = XcodeCloudDisplay.date(run.attributes.finishedDate) {
                        LabeledContent("Finished", value: finished.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                if let commit = run.attributes.sourceCommit {
                    Section("Source Commit") {
                        if let sha = commit.commitSha {
                            LabeledContent("Commit") {
                                Text(String(sha.prefix(12)))
                                    .font(.system(.subheadline, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        if let message = commit.message, !message.isEmpty {
                            Text(message)
                                .font(.system(size: 15, design: .rounded))
                                .textSelection(.enabled)
                        }
                        if let author = commit.author?.displayName {
                            LabeledContent("Author", value: author)
                        }
                        if let value = commit.webUrl,
                           let url = URL(string: value),
                           url.scheme == "https",
                           url.host != nil {
                            Link("View Commit", destination: url)
                        }
                    }
                }

                if let counts = run.attributes.issueCounts, counts.total > 0 {
                    Section("Issues") {
                        if let errors = counts.errors, errors > 0 {
                            LabeledContent("Errors", value: errors.formatted())
                        }
                        if let tests = counts.testFailures, tests > 0 {
                            LabeledContent("Test Failures", value: tests.formatted())
                        }
                        if let warnings = counts.warnings, warnings > 0 {
                            LabeledContent("Warnings", value: warnings.formatted())
                        }
                        if let analyzer = counts.analyzerWarnings, analyzer > 0 {
                            LabeledContent("Analyzer Warnings", value: analyzer.formatted())
                        }
                        Text("Select an action below to inspect individual issues and test results.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Actions") {
                    if actions.isEmpty {
                        Text("No build actions available yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(actions) { action in
                            NavigationLink {
                                XcodeCloudActionDetailView(action: action, client: client)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: XcodeCloudDisplay.symbol(
                                        action.attributes.completionStatus,
                                        progress: action.attributes.executionProgress
                                    ))
                                    .foregroundStyle(XcodeCloudDisplay.color(
                                        action.attributes.completionStatus,
                                        progress: action.attributes.executionProgress
                                    ))
                                    .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(action.attributes.name ?? XcodeCloudDisplay.readable(action.attributes.actionType ?? "Action"))
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        HStack(spacing: 8) {
                                            Text(XcodeCloudDisplay.status(
                                                action.attributes.completionStatus,
                                                progress: action.attributes.executionProgress
                                            ))
                                            if let counts = action.attributes.issueCounts, counts.total > 0 {
                                                Text("• \(counts.total) issues")
                                            }
                                        }
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(run.attributes.number.map { "Build #\($0)" } ?? "Build Details")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if !hasLoaded { await load() }
            // No background polling: task cancellation and scene phase stop it
            // automatically when the view leaves the active UI.
            while !Task.isCancelled && scenePhase == .active {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
                guard !Task.isCancelled, scenePhase == .active else { break }
                if hasLoaded && isInProgress {
                    await load()
                }
            }
        }
        .alert("Xcode Cloud", isPresented: Binding(
            get: { errorMessage != nil && hasLoaded },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func load() async {
        guard let client, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let requestedDetail = client.buildDetail(for: initialRun.id)
            async let requestedActions = client.buildActions(for: initialRun.id)
            let (loadedDetail, loadedActions) = try await (requestedDetail, requestedActions)
            guard !Task.isCancelled else { return }
            detail = loadedDetail
            actions = loadedActions
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

/// Issue and test diagnostics are loaded on demand, not for every row in the
/// build list, avoiding large/expensive N+1 API queries.
private struct XcodeCloudActionDetailView: View {
    let action: AppStoreConnectBuildAction
    let client: AppStoreConnectAPIClient?

    @State private var issues: [AppStoreConnectIssue] = []
    @State private var tests: [AppStoreConnectTestResult] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var issuesError: String?
    @State private var testsError: String?

    private var sortedTests: [AppStoreConnectTestResult] {
        tests.sorted { lhs, rhs in
            let lhsFailed = XcodeCloudDisplay.isFailed(lhs.attributes.status)
            let rhsFailed = XcodeCloudDisplay.isFailed(rhs.attributes.status)
            if lhsFailed != rhsFailed { return lhsFailed }
            return (lhs.attributes.name ?? "") < (rhs.attributes.name ?? "")
        }
    }

    var body: some View {
        List {
            Section("Action") {
                LabeledContent("Type", value: XcodeCloudDisplay.readable(action.attributes.actionType ?? "Action"))
                LabeledContent("Status", value: XcodeCloudDisplay.status(
                    action.attributes.completionStatus,
                    progress: action.attributes.executionProgress
                ))
                if let required = action.attributes.isRequiredToPass {
                    LabeledContent("Required", value: required ? "Yes" : "No")
                }
            }

            Section("Issues") {
                if isLoading && !hasLoaded {
                    ProgressView("Loading issues…")
                } else if let issuesError {
                    Text(issuesError).foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                } else if issues.isEmpty {
                    Text("No compiler or build issues reported.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                XcodeCloudDisplay.readable(issue.attributes.issueType ?? "Issue"),
                                systemImage: XcodeCloudDisplay.isFailed(issue.attributes.issueType) ? "xmark.circle.fill" : "exclamationmark.triangle"
                            )
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(XcodeCloudDisplay.isFailed(issue.attributes.issueType) ? Color.red : Color.orange)

                            if let message = issue.attributes.message {
                                Text(message)
                                    .font(.system(size: 15, design: .rounded))
                                    .textSelection(.enabled)
                            }
                            if let location = XcodeCloudDisplay.location(issue.attributes.fileSource) {
                                Text(location)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Test Results") {
                if isLoading && !hasLoaded {
                    ProgressView("Loading test results…")
                } else if let testsError {
                    Text(testsError).foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                } else if tests.isEmpty {
                    Text("No test results for this action.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTests) { test in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: XcodeCloudDisplay.isFailed(test.attributes.status)
                                      ? "xmark.circle.fill" : "checkmark.circle")
                                    .foregroundStyle(XcodeCloudDisplay.isFailed(test.attributes.status) ? Color.red : Color.secondary)
                                Text(test.attributes.name ?? "Test")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                Spacer()
                                Text(XcodeCloudDisplay.readable(test.attributes.status ?? "Unknown"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let className = test.attributes.className {
                                Text(className)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let message = test.attributes.message, !message.isEmpty {
                                Text(message)
                                    .font(.system(size: 13, design: .rounded))
                                    .textSelection(.enabled)
                            }
                            if let location = XcodeCloudDisplay.location(test.attributes.fileSource) {
                                Text(location)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(action.attributes.name ?? "Action")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let client, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            issues = try await client.issues(for: action.id)
            issuesError = nil
        } catch {
            if !Task.isCancelled { issuesError = error.localizedDescription }
        }
        guard !Task.isCancelled else { return }
        do {
            tests = try await client.testResults(for: action.id)
            testsError = nil
        } catch {
            if !Task.isCancelled { testsError = error.localizedDescription }
        }
    }
}

enum XcodeCloudDisplay {
    static func readable(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func status(_ completion: String?, progress: String?) -> String {
        if let completion, !completion.isEmpty {
            return readable(completion)
        }
        return readable(progress ?? "Unknown")
    }

    static func isInProgress(_ attributes: AppStoreConnectBuildRunAttributes) -> Bool {
        guard attributes.completionStatus == nil,
              let progress = attributes.executionProgress?.uppercased() else { return false }
        return progress == "PENDING" || progress == "RUNNING"
    }

    static func isFailed(_ status: String?) -> Bool {
        let value = status?.uppercased() ?? ""
        return value.contains("FAIL") || value.contains("ERROR")
    }

    static func color(_ completion: String?, progress: String?) -> Color {
        if isFailed(completion) { return .red }
        if completion?.uppercased() == "SUCCEEDED" { return .green }
        if completion?.uppercased() == "CANCELED" { return .secondary }
        if progress?.uppercased() == "RUNNING" { return .blue }
        return .secondary
    }

    static func symbol(_ completion: String?, progress: String?) -> String {
        if isFailed(completion) { return "xmark.circle.fill" }
        if completion?.uppercased() == "SUCCEEDED" { return "checkmark.circle.fill" }
        if completion?.uppercased() == "CANCELED" { return "minus.circle" }
        if progress?.uppercased() == "RUNNING" { return "arrow.triangle.2.circlepath" }
        return "clock"
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    static func duration(from start: Date, to finish: Date) -> String {
        let seconds = Int(max(0, finish.timeIntervalSince(start)))
        let minutes = seconds / 60
        return minutes > 0 ? "\(minutes)m \(seconds % 60)s" : "\(seconds)s"
    }

    static func location(_ file: AppStoreConnectFileSource?) -> String? {
        guard let file, let path = file.path, !path.isEmpty else { return nil }
        if let line = file.lineNumber {
            return "\(path):\(line)" + (file.columnNumber.map { ":\($0)" } ?? "")
        }
        return path
    }
}
