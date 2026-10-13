import AppFoundation
import SwiftUI

/// Manual build launcher. Uses only Apple-provided workflow and Git-reference
/// IDs, obtained from the workflow's own connected repository.
struct StartXcodeCloudBuildView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme

    @Environment(\.dismiss) private var dismiss

    let appName: String
    let workflows: [AppStoreConnectWorkflow]
    let client: AppStoreConnectAPIClient?
    let onStarted: (AppStoreConnectBuildRun) -> Void

    @State private var selectedWorkflowID: String
    @State private var selectedReferenceID = ""
    @State private var references: [AppStoreConnectGitReference] = []
    @State private var repositoryName = ""
    @State private var isLoadingReferences = false
    @State private var hasLoadedReferences = false
    @State private var isStarting = false
    @State private var isConfirmingStart = false
    @State private var errorMessage: String?

    init(
        appName: String,
        workflows: [AppStoreConnectWorkflow],
        client: AppStoreConnectAPIClient?,
        onStarted: @escaping (AppStoreConnectBuildRun) -> Void
    ) {
        self.appName = appName
        self.workflows = workflows
        self.client = client
        self.onStarted = onStarted
        _selectedWorkflowID = State(
            initialValue: workflows.first(where: { $0.attributes.isEnabled == true })?.id ?? ""
        )
    }

    private var enabledWorkflows: [AppStoreConnectWorkflow] {
        workflows.filter { $0.attributes.isEnabled == true }
            .sorted {
                let order = $0.attributes.name.localizedStandardCompare($1.attributes.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }

    private var selectedWorkflow: AppStoreConnectWorkflow? {
        enabledWorkflows.first { $0.id == selectedWorkflowID }
    }

    private var selectedReference: AppStoreConnectGitReference? {
        references.first { $0.id == selectedReferenceID }
    }

    private var branches: [AppStoreConnectGitReference] {
        references.filter { $0.attributes.isBranch }
    }

    private var tags: [AppStoreConnectGitReference] {
        references.filter { !$0.attributes.isBranch }
    }

    private var canStart: Bool {
        !isLoadingReferences && !isStarting &&
        selectedWorkflow != nil && selectedReference != nil && client != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("App") {
                        LabeledContent("App", value: appName)
                    }

                    Section("Workflow") {
                        if enabledWorkflows.isEmpty {
                            Text("No enabled Xcode Cloud workflows are available.")
                                .foregroundStyle(foundationTheme.secondaryForegroundColor)
                        } else {
                            Picker("Workflow", selection: $selectedWorkflowID) {
                                ForEach(enabledWorkflows) { workflow in
                                    Text(workflow.attributes.name).tag(workflow.id)
                                }
                            }
                        }
                    }

                    Section {
                        if enabledWorkflows.isEmpty {
                            Text("Select an enabled workflow to choose a branch or tag.")
                                .foregroundStyle(foundationTheme.secondaryForegroundColor)
                        } else if isLoadingReferences {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Loading branches and tags…")
                                    .foregroundStyle(foundationTheme.secondaryForegroundColor)
                            }
                        } else if !hasLoadedReferences {
                            Button("Retry Loading Git References") {
                                Task { await loadReferences() }
                            }
                        } else if references.isEmpty {
                            Text("No available branches or tags found for this workflow.")
                                .foregroundStyle(foundationTheme.secondaryForegroundColor)
                        } else {
                            if !repositoryName.isEmpty {
                                LabeledContent("Repository", value: repositoryName)
                            }

                            Picker("Branch or Tag", selection: $selectedReferenceID) {
                                if !branches.isEmpty {
                                    Section("Branches") {
                                        ForEach(branches) { reference in
                                            Text(reference.attributes.displayName)
                                                .tag(reference.id)
                                        }
                                    }
                                }
                                if !tags.isEmpty {
                                    Section("Tags") {
                                        ForEach(tags) { reference in
                                            Text(reference.attributes.displayName)
                                                .tag(reference.id)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Source")
                    } footer: {
                        Text("The build uses the latest commit at the selected branch or the commit referenced by the selected tag. Starting a build uses Xcode Cloud resources.")
                    }
                }
                .listRowBackground(MyAppsGlassSurface())
                .listRowSeparatorTint(foundationTheme.borderColor)
            }
            .scrollContentBackground(.hidden)
            .myAppsPage()
            .navigationTitle("Start Build")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isStarting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isConfirmingStart = true
                    } label: {
                        if isStarting {
                            ProgressView()
                        } else {
                            Text("Start")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canStart)
                }
            }
            .task(id: selectedWorkflowID) {
                await loadReferences()
            }
            .confirmationDialog(
                "Start Xcode Cloud Build?",
                isPresented: $isConfirmingStart,
                titleVisibility: .visible
            ) {
                Button("Start Build") {
                    Task { await startBuild() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let workflow = selectedWorkflow, let reference = selectedReference {
                    Text(
                        "\(appName)\nWorkflow: \(workflow.attributes.name)\n" +
                        "\(reference.attributes.isBranch ? "Branch" : "Tag"): " +
                        "\(reference.attributes.displayName)\n\n" +
                        "This requests a new build from Xcode Cloud."
                    )
                }
            }
            .alert(
                "Xcode Cloud",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .interactiveDismissDisabled(isStarting)
        }
    }

    @MainActor
    private func loadReferences() async {
        selectedReferenceID = ""
        references = []
        repositoryName = ""
        hasLoadedReferences = false

        guard let client, let workflow = selectedWorkflow else { return }
        isLoadingReferences = true
        defer { isLoadingReferences = false }

        do {
            let repository = try await client.repository(for: workflow)
            let found = try await client.gitReferences(for: repository)
            guard !Task.isCancelled, selectedWorkflowID == workflow.id else { return }

            repositoryName = [
                repository.attributes.ownerName,
                repository.attributes.repositoryName
            ].compactMap { $0 }.joined(separator: "/")
            references = found
            let defaultID = repository.relationships?.defaultBranch?.data?.id
            selectedReferenceID = found.first(where: { $0.id == defaultID })?.id ??
                found.first(where: { $0.attributes.isBranch })?.id ??
                found.first?.id ?? ""
            hasLoadedReferences = true
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, selectedWorkflowID == workflow.id else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func startBuild() async {
        guard !isStarting, canStart, let client,
              let workflow = selectedWorkflow,
              let reference = selectedReference else { return }

        isStarting = true
        defer { isStarting = false }
        do {
            let created = try await client.startBuild(workflow: workflow, source: reference)
            // If Apple reports 201 Created, treat the operation as successful
            // even when the caller's navigation state changes during the request.
            onStarted(created)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
