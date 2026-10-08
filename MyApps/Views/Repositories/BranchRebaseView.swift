import SwiftUI

struct BranchRebaseView: View {
    let repository: GitHubRepository
    let sourceBranch: GitHubBranch
    let branches: [GitHubBranch]
    let client: GitHubAPIClient?
    let onRebased: () -> Void

    @StateObject private var model: BranchRebaseViewModel
    @State private var isConfirmingApply = false
    @Environment(\.dismiss) private var dismiss

    private var rebaseConfirmationMessage: String {
        let currentHead = String((model.plan?.sourceHeadSHA ?? "").prefix(12))
        let proposedHead = String((model.proposedHeadSHA ?? "").prefix(12))

        return "\(sourceBranch.name) will move from \(currentHead) to \(proposedHead). " +
            "GitHub rejects the update if either branch moved since preparation."
    }

    private var destinations: [GitHubBranch] {
        branches
            .filter { $0.name != sourceBranch.name }
            .sorted { lhs, rhs in
                if lhs.name == repository.defaultBranch { return true }
                if rhs.name == repository.defaultBranch { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    init(
        repository: GitHubRepository,
        sourceBranch: GitHubBranch,
        branches: [GitHubBranch],
        defaultDestination: String,
        client: GitHubAPIClient?,
        onRebased: @escaping () -> Void
    ) {
        self.repository = repository
        self.sourceBranch = sourceBranch
        self.branches = branches
        self.client = client
        self.onRebased = onRebased
        _model = StateObject(
            wrappedValue: BranchRebaseViewModel(
                sourceBranch: sourceBranch,
                defaultDestination: defaultDestination
            )
        )
    }

    private var directionSection: some View {
        Section("Direction") {
            LabeledContent("Branch", value: sourceBranch.name)

            Picker("Rebase onto", selection: $model.destinationName) {
                ForEach(destinations) { branch in
                    Text(branch.name)
                        .tag(branch.name)
                }
            }
        }
        .disabled(model.isPreparing || model.isApplying)
    }

    @ViewBuilder
    private var rebaseSections: some View {
        if model.isAnalyzing {
            Section {
                ProgressView("Analyzing rebase…")
            }
        } else if let plan = model.plan {
            BranchRebaseAnalysisSection(plan: plan)

            if !plan.isNoOp && plan.conflictingPaths.isEmpty {
                BranchRebasePrepareSection(
                    model: model,
                    repository: repository,
                    client: client,
                    isConfirmingApply: $isConfirmingApply
                )
            }
        } else {
            Section {
                Text("Choose a destination branch to analyze the rebase.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isShowingResult: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil || model.successMessage != nil },
            set: {
                if !$0 {
                    model.errorMessage = nil
                    model.successMessage = nil
                }
            }
        )
    }

    var body: some View {
        List {
            directionSection
            rebaseSections
        }
        .navigationTitle("Rebase")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.destinationName) {
            await model.analyze(repository: repository, client: client)
        }
        .confirmationDialog(
            "Apply Rebase?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("Rebase \(sourceBranch.name) onto \(model.destinationName)") {
                Task {
                    await model.apply(repository: repository, client: client)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(rebaseConfirmationMessage)
        }
        .alert(model.successMessage == nil ? "Rebase Failed" : "Rebase Complete", isPresented: isShowingResult) {
            if model.successMessage != nil {
                Button("Done") {
                    onRebased()
                    dismiss()
                }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(model.successMessage ?? model.errorMessage ?? "")
        }
    }
}

private struct BranchRebaseAnalysisSection: View {
    let plan: BranchRebaseViewModel.Plan

    var body: some View {
        Section("Analysis") {
            LabeledContent("Current Head", value: String(plan.sourceHeadSHA.prefix(12)))
            LabeledContent("Destination", value: String(plan.destinationHeadSHA.prefix(12)))
            LabeledContent("Merge Base", value: String(plan.mergeBaseSHA.prefix(12)))
            LabeledContent("Commits to Replay", value: plan.replayCommits.count.formatted())
            LabeledContent("Destination-only Commits", value: plan.destinationUniqueCount.formatted())

            if plan.isNoOp {
                Label(
                    "No rebase is needed. The destination is already an ancestor of this branch.",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.secondary)
            } else if plan.isFastForward {
                Label(
                    "No commits need replaying. The branch can move directly to the destination head.",
                    systemImage: "arrow.right.circle"
                )
            } else if !plan.conflictingPaths.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Unsafe overlap detected", systemImage: "exclamationmark.triangle")
                        .font(.headline)

                    ForEach(plan.conflictingPaths.prefix(8), id: \.self) { path in
                        Text(path)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            } else {
                ForEach(plan.replayCommits.prefix(10)) { commit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commit.subject)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(commit.shortSHA)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct BranchRebasePrepareSection: View {
    @ObservedObject var model: BranchRebaseViewModel
    let repository: GitHubRepository
    let client: GitHubAPIClient?
    @Binding var isConfirmingApply: Bool

    var body: some View {
        Section {
            if let proposedHeadSHA = model.proposedHeadSHA {
                LabeledContent(
                    "Proposed New Head",
                    value: String(proposedHeadSHA.prefix(12))
                )

                Text("The rebased commits are prepared as Git objects, but the branch has not moved yet.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)

                Button {
                    isConfirmingApply = true
                } label: {
                    if model.isApplying {
                        HStack {
                            ProgressView()
                            Text("Applying…")
                        }
                    } else {
                        Label("Apply Rebase", systemImage: "arrow.triangle.branch")
                    }
                }
                .disabled(model.isApplying)
            } else {
                Button {
                    Task {
                        await model.prepare(repository: repository, client: client)
                    }
                } label: {
                    if model.isPreparing {
                        HStack {
                            ProgressView()
                            Text("Preparing…")
                        }
                    } else {
                        Label("Prepare Rebase", systemImage: "hammer")
                    }
                }
                .disabled(model.isPreparing)
            }
        } header: {
            Text("Prepare")
        } footer: {
            Text("Preparing creates new Git objects only. The branch ref changes only after the final confirmation.")
        }
    }
}
