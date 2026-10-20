import AppFoundation
import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [ManagedApp]
    @AppStorage(AppSortOption.storageKey) private var appSortRawValue = AppSortOption.created.rawValue
    @AppStorage(AppSortOption.directionStorageKey) private var directionRawValue = SortDirection.descending.rawValue

    @State private var selectedStatus: ProjectStatus? = nil
    @State private var isPresentingNewApp = false
    @State private var projectPendingEdit: ManagedApp?
    @State private var projectPendingDeletion: ManagedApp?
    @State private var projectPendingPermanentDeletion: ManagedApp?

    private var appSortOption: AppSortOption {
        AppSortOption(rawValue: appSortRawValue) ?? .created
    }

    private var sortDirection: SortDirection {
        SortDirection(rawValue: directionRawValue) ?? .descending
    }

    private var sortedProjects: [ManagedApp] {
        projects.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            let ascending = sortDirection == .ascending
            switch appSortOption {
            case .name:
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame {
                    return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            case .created:
                if lhs.createdAt != rhs.createdAt {
                    return ascending ? lhs.createdAt < rhs.createdAt : lhs.createdAt > rhs.createdAt
                }
            case .updated:
                if lhs.updatedAt != rhs.updatedAt {
                    return ascending ? lhs.updatedAt < rhs.updatedAt : lhs.updatedAt > rhs.updatedAt
                }
            }

            // Consistent tie-breaking for equally dated entries.
            let byName = lhs.name.localizedStandardCompare(rhs.name)
            if byName != .orderedSame {
                return byName == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var displayedProjects: [ManagedApp] {
        guard let selectedStatus else { return sortedProjects }
        return sortedProjects.filter { $0.projectStatus == selectedStatus }
    }

    private var statusesByDescendingCount: [ProjectStatus] {
        ProjectStatus.allCases
            .enumerated()
            .map { index, status in
                (index: index, status: status, count: count(for: status))
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.index < rhs.index
            }
            .map { $0.status }
    }

    var body: some View {
        Group {
            if projects.isEmpty {
                EmptyStateView(
                    symbol: "square.grid.2x2",
                    title: "No apps yet",
                    message: "Add your first app, then keep its Markdown notes together."
                )
            } else {
                projectsList
            }
        }
        .myAppsPage()
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Section("Sort By") {
                        Picker("Sort Field", selection: $appSortRawValue) {
                            ForEach(AppSortOption.allCases) { option in
                                Label(option.title, systemImage: option.symbolName)
                                    .tag(option.rawValue)
                            }
                        }
                    }
                    Section("Order") {
                        Picker("Sort Order", selection: $directionRawValue) {
                            ForEach(SortDirection.allCases) { direction in
                                Label(direction.title(isText: appSortOption.isText), systemImage: direction.symbolName)
                                    .tag(direction.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort Projects by \(appSortOption.title), \(sortDirection.title(isText: appSortOption.isText))")

                Button {
                    isPresentingNewApp = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add App")
            }
        }
        .onChange(of: appSortRawValue) { _, newField in
            let option = AppSortOption(rawValue: newField) ?? .created
            directionRawValue = SortDirection.defaultForText(option.isText).rawValue
        }
        .sheet(isPresented: $isPresentingNewApp) {
            AppEditorView()
        }
        .sheet(item: $projectPendingEdit) { project in
            AppEditorView(app: project)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            deletionActions
        } message: {
            deletionMessage
        }
        .confirmationDialog(
            permanentDeletionTitle,
            isPresented: permanentDeletionDialogBinding,
            titleVisibility: .visible
        ) {
            if let project = projectPendingPermanentDeletion {
                Button("Delete App and \(noteCountLabel(for: project))", role: .destructive) {
                    ProjectDeletionService.deleteProjectAndNotes(project, in: modelContext)
                    projectPendingPermanentDeletion = nil
                }
            }
        } message: {
            Text("This permanently deletes the app, its notes, and attached images. This cannot be undone.")
        }
    }

    private var projectsList: some View {
        List {
            Group {
                statusFilters
                    .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 5, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if displayedProjects.isEmpty {
                    filteredEmptyState
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(displayedProjects) { project in
                        NavigationLink {
                            AppDetailView(app: project)
                        } label: {
                            AppRowView(app: project, showsChevron: false)
                        }
                        .navigationLinkIndicatorVisibility(.hidden)
                        .buttonStyle(.plain)
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: AppTheme.pagePadding,
                                bottom: 6,
                                trailing: AppTheme.pagePadding
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                projectPendingEdit = project
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(foundationTheme.accentColor)

                            Button {
                                project.setPinned(!project.isPinned)
                            } label: {
                                Label(project.isPinned ? "Unpin" : "Pin", systemImage: project.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(.orange)

                            Button(role: .destructive) {
                                projectPendingDeletion = project
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                projectPendingEdit = project
                            } label: {
                                Label("Edit App", systemImage: "pencil")
                            }

                            Button {
                                project.setPinned(!project.isPinned)
                            } label: {
                                Label(
                                    project.isPinned ? "Unpin" : "Pin",
                                    systemImage: project.isPinned ? "pin.slash" : "pin"
                                )
                            }

                            Button(role: .destructive) {
                                projectPendingDeletion = project
                            } label: {
                                Label("Delete App", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(foundationTheme.borderColor)
        }
        .scrollContentBackground(.hidden)
        .myAppsPage()
        .listStyle(.plain)

        .contentMargins(.top, 0, for: .scrollContent)
    }

    private var statusFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statusFilterPill(
                    title: "All",
                    color: .accentColor,
                    count: projects.count,
                    status: nil
                )

                ForEach(statusesByDescendingCount) { status in
                    statusFilterPill(
                        title: status.rawValue,
                        color: status.color,
                        count: count(for: status),
                        status: status
                    )
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
        }
        .scrollClipDisabled()
    }

    private func statusFilterPill(
        title: String,
        color: Color,
        count: Int,
        status: ProjectStatus?
    ) -> some View {
        let isSelected = selectedStatus == status

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                selectedStatus = status
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                Text(count.formatted())
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isSelected ? color : foundationTheme.secondaryForegroundColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(foundationTheme.primaryForegroundColor.opacity(isSelected ? 0.08 : 0.055), in: Capsule())
            }
            .foregroundStyle(foundationTheme.primaryForegroundColor)
            .padding(.leading, 11)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(
                isSelected ? color.opacity(0.15) : foundationTheme.surfaceColor,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isSelected ? color.opacity(0.48) : foundationTheme.primaryForegroundColor.opacity(0.07),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) app\(count == 1 ? "" : "s")")
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedStatus?.symbolName ?? "line.3.horizontal.decrease.circle")
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .foregroundStyle(selectedStatus?.color ?? foundationTheme.secondaryForegroundColor)

            Text("No \(selectedStatus?.rawValue ?? "matching") apps")
                .font(.system(size: 19, weight: .semibold, design: .rounded))

            Text("Choose another status or update an app’s status.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(foundationTheme.secondaryForegroundColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 64)
    }

    private func count(for status: ProjectStatus) -> Int {
        projects.lazy.filter { $0.projectStatus == status }.count
    }

    private var deletionTitle: String {
        guard let project = projectPendingDeletion else { return "Delete App?" }
        return "Delete “\(project.name)”?"
    }

    private var permanentDeletionTitle: String {
        guard let project = projectPendingPermanentDeletion else { return "Delete Notes Too?" }
        return "Permanently delete “\(project.name)”?"
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { if !$0 { projectPendingDeletion = nil } }
        )
    }

    private var permanentDeletionDialogBinding: Binding<Bool> {
        Binding(
            get: { projectPendingPermanentDeletion != nil },
            set: { if !$0 { projectPendingPermanentDeletion = nil } }
        )
    }

    @ViewBuilder
    private var deletionActions: some View {
        if let project = projectPendingDeletion {
            if project.allNotes.isEmpty {
                Button("Delete App", role: .destructive) {
                    ProjectDeletionService.deleteProjectKeepingNotes(project, in: modelContext)
                    projectPendingDeletion = nil
                }
            } else {
                Button("Delete App, Keep Notes") {
                    ProjectDeletionService.deleteProjectKeepingNotes(project, in: modelContext)
                    projectPendingDeletion = nil
                }

                Button("Delete App and Notes", role: .destructive) {
                    projectPendingPermanentDeletion = project
                    projectPendingDeletion = nil
                }
            }
        }
    }

    @ViewBuilder
    private var deletionMessage: some View {
        if let project = projectPendingDeletion, !project.allNotes.isEmpty {
            Text("This app contains \(noteCountLabel(for: project)). Keep them as unassigned notes or delete them with the app.")
        } else {
            Text("This removes the app from MyApps.")
        }
    }

    private func noteCountLabel(for project: ManagedApp) -> String {
        "\(project.allNotes.count) note\(project.allNotes.count == 1 ? "" : "s")"
    }
}
