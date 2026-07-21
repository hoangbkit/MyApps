import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AppEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let app: ManagedApp?

    @State private var name: String
    @State private var shortDescription: String
    @State private var showsDescriptionInList: Bool
    @State private var platform: AppPlatform
    @State private var liveVersion: String
    @State private var developmentVersion: String
    @State private var projectStatus: ProjectStatus
    @State private var businessModel: BusinessModel
    @State private var totalIncomeText: String
    @State private var monthlyRevenueText: String
    @State private var currencyCode: String
    @State private var selectedDisplayFields: [AppListField]
    @State private var iconData: Data?
    @State private var defaultIconStyle: DefaultAppIconStyle
    @State private var isPinned: Bool

    init(app: ManagedApp? = nil) {
        self.app = app
        _name = State(initialValue: app?.name ?? "")
        _shortDescription = State(initialValue: app?.shortDescription ?? "")
        _showsDescriptionInList = State(initialValue: app?.showsDescriptionInList ?? false)
        _platform = State(initialValue: app?.platform ?? .iOS)
        _liveVersion = State(initialValue: app?.liveVersion ?? "1.0")
        _developmentVersion = State(initialValue: app?.developmentVersion ?? "")
        _projectStatus = State(initialValue: app?.projectStatus ?? .building)
        _businessModel = State(initialValue: app?.businessModel ?? .freemium)
        _totalIncomeText = State(initialValue: AppValueFormatter.editableAmount(app?.totalIncome))
        _monthlyRevenueText = State(initialValue: AppValueFormatter.editableAmount(app?.monthlyRecurringRevenue))
        _currencyCode = State(initialValue: app?.currencyCode ?? "USD")
        _selectedDisplayFields = State(initialValue: app?.listDisplayFields ?? AppListField.defaultFields)
        _iconData = State(initialValue: app?.iconData)
        _defaultIconStyle = State(initialValue: app?.defaultIconStyle ?? .ocean)
        _isPinned = State(initialValue: app?.isPinned ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                appInfoSection
                progressSection
                businessSection
                listDisplaySection
            }
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(app == nil ? "New App" : "Edit App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var previewSection: some View {
        Section("App List Preview") {
            AppRowView(
                name: displayName,
                iconData: iconData,
                defaultIconStyle: defaultIconStyle,
                isPinned: isPinned,
                shortDescription: showsDescriptionInList ? nonempty(shortDescription) : nil,
                statusItems: previewStatusItems
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var appInfoSection: some View {
        let currentAppName = displayName
        let currentIconData = iconData
        let currentDefaultIconStyle = defaultIconStyle
        let iconDataBinding = $iconData
        let defaultIconStyleBinding = $defaultIconStyle

        return Section("App Info") {
            NavigationLink {
                AppIconEditorView(
                    appName: currentAppName,
                    iconData: iconDataBinding,
                    defaultIconStyle: defaultIconStyleBinding
                )
            } label: {
                HStack(spacing: 16) {
                    Text("Icon")
                    Spacer()
                    AppIconView(
                        name: currentAppName,
                        iconData: currentIconData,
                        defaultIconStyle: currentDefaultIconStyle,
                        size: 40
                    )
                }
            }

            InfoTextFieldRow(title: "Name", placeholder: "App name", text: $name, capitalization: .words)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Short Description")
                    Spacer()
                    Text("\(shortDescription.count)/180")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                TextField(
                    "A short summary of what this app does",
                    text: $shortDescription,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .onChange(of: shortDescription) { _, newValue in
                    if newValue.count > 180 {
                        shortDescription = String(newValue.prefix(180))
                    }
                }
            }

            HStack {
                Text("Show Description in List")
                Spacer()
                Toggle("Show Description in List", isOn: $showsDescriptionInList)
                    .labelsHidden()
            }

            InfoPickerRow(title: "Platform", selection: $platform) {
                ForEach(AppPlatform.allCases) { value in
                    Label(value.rawValue, systemImage: value.symbolName).tag(value)
                }
            }

            HStack {
                Text("Pinned")
                Spacer()
                Toggle("Pinned", isOn: $isPinned)
                    .labelsHidden()
            }
        }
    }

    private var progressSection: some View {
        Section("Progress") {
            InfoPickerRow(title: "Status", selection: $projectStatus) {
                ForEach(ProjectStatus.allCases) { value in
                    Label(value.rawValue, systemImage: value.symbolName).tag(value)
                }
            }

            InfoTextFieldRow(
                title: "Live Version",
                placeholder: "1.0",
                text: $liveVersion,
                keyboardType: .numbersAndPunctuation
            )

            InfoTextFieldRow(
                title: "Dev Version",
                placeholder: "P3 or 1.1",
                text: $developmentVersion,
                keyboardType: .numbersAndPunctuation
            )
        }
    }

    private var businessSection: some View {
        Section("Business") {
            InfoPickerRow(title: "Model", selection: $businessModel) {
                ForEach(BusinessModel.allCases) { value in
                    Label(value.rawValue, systemImage: value.symbolName).tag(value)
                }
            }

            InfoTextFieldRow(
                title: "Currency",
                placeholder: "USD",
                text: $currencyCode,
                keyboardType: .default,
                capitalization: .characters
            )
            .onChange(of: currencyCode) { _, newValue in
                let uppercased = String(newValue.uppercased().prefix(3))
                if uppercased != newValue { currencyCode = uppercased }
            }

            InfoTextFieldRow(
                title: "Total Income",
                placeholder: "0",
                text: $totalIncomeText,
                keyboardType: .decimalPad
            )

            InfoTextFieldRow(
                title: "Monthly Revenue",
                placeholder: "0",
                text: $monthlyRevenueText,
                keyboardType: .decimalPad
            )
        }
    }

    private var listDisplaySection: some View {
        Section {
            Menu {
                ForEach(AppListPreset.allCases) { preset in
                    Button {
                        selectedDisplayFields = preset.fields
                    } label: {
                        Label(preset.rawValue, systemImage: preset.symbolName)
                    }
                }
            } label: {
                HStack {
                    Text("Preset")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(activePreset?.rawValue ?? "Custom")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ForEach(AppListField.allCases) { field in
                displayFieldRow(field)
            }
        } header: {
            Text("App List Info")
        } footer: {
            Text("Choose and order the values to show. The real-size preview above updates immediately.")
        }
    }

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your App" : trimmed
    }

    private var previewStatusItems: [AppStatusItem] {
        selectedDisplayFields.compactMap { field in
            switch field {
            case .projectStatus:
                AppStatusItem(status: projectStatus)
            case .platform:
                AppStatusItem(field: field, text: platform.rawValue)
            case .liveVersion:
                nonempty(liveVersion).map { AppStatusItem(field: field, text: $0) }
            case .developmentVersion:
                nonempty(developmentVersion).map { AppStatusItem(field: field, text: $0) }
            case .businessModel:
                AppStatusItem(field: field, text: businessModel.rawValue)
            case .totalIncome:
                AppValueFormatter.parseAmount(totalIncomeText).map {
                    AppStatusItem(field: field, text: AppValueFormatter.currency($0, code: currencyCode, compact: true))
                }
            case .monthlyRecurringRevenue:
                AppValueFormatter.parseAmount(monthlyRevenueText).map {
                    AppStatusItem(field: field, text: "\(AppValueFormatter.currency($0, code: currencyCode, compact: true))/mo")
                }
            case .openChecklistCount:
                AppStatusItem(field: field, text: "\(app?.openChecklistCount ?? 0) open")
            case .lastUpdated:
                AppStatusItem(field: field, text: AppValueFormatter.relativeDate(app?.updatedAt ?? Date()))
            }
        }
    }

    private var activePreset: AppListPreset? {
        AppListPreset.allCases.first { $0.fields == selectedDisplayFields }
    }

    private func displayFieldRow(_ field: AppListField) -> some View {
        let selectedIndex = selectedDisplayFields.firstIndex(of: field)
        let isSelected = selectedIndex != nil

        return HStack(spacing: 10) {
            Button {
                toggleDisplayField(field)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: field.symbolName)
                        .foregroundStyle(field == .projectStatus ? projectStatus.color : Color(uiColor: .secondaryLabel))
                        .frame(width: 22)

                    Text(field.title)
                        .foregroundStyle(.primary)

                    Spacer()

                    if let selectedIndex {
                        Text("\(selectedIndex + 1)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let selectedIndex {
                Button {
                    moveDisplayField(at: selectedIndex, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex == 0)

                Button {
                    moveDisplayField(at: selectedIndex, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex == selectedDisplayFields.count - 1)
            }
        }
    }

    private func toggleDisplayField(_ field: AppListField) {
        if let index = selectedDisplayFields.firstIndex(of: field) {
            selectedDisplayFields.remove(at: index)
        } else {
            selectedDisplayFields.append(field)
        }
    }

    private func moveDisplayField(at index: Int, by offset: Int) {
        let destination = index + offset
        guard selectedDisplayFields.indices.contains(index),
              selectedDisplayFields.indices.contains(destination) else { return }
        selectedDisplayFields.swapAt(index, destination)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLiveVersion = liveVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDevelopmentVersion = developmentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrencyCode = AppValueFormatter.normalizedCurrencyCode(currencyCode)
        let totalIncome = AppValueFormatter.parseAmount(totalIncomeText)
        let monthlyRevenue = AppValueFormatter.parseAmount(monthlyRevenueText)

        if let app {
            app.name = trimmedName
            app.shortDescription = trimmedDescription
            app.showsDescriptionInList = showsDescriptionInList && !trimmedDescription.isEmpty
            app.stage = .app
            app.platform = platform
            app.liveVersion = trimmedLiveVersion
            app.developmentVersion = trimmedDevelopmentVersion
            app.projectStatus = projectStatus
            app.businessModel = businessModel
            app.totalIncome = totalIncome
            app.monthlyRecurringRevenue = monthlyRevenue
            app.currencyCode = normalizedCurrencyCode
            app.listDisplayFields = selectedDisplayFields
            app.iconData = iconData
            app.defaultIconStyle = defaultIconStyle
            if app.isPinned != isPinned {
                app.setPinned(isPinned)
            } else {
                app.updatedAt = Date()
            }
        } else {
            modelContext.insert(
                ManagedApp(
                    name: trimmedName,
                    shortDescription: trimmedDescription,
                    showsDescriptionInList: showsDescriptionInList && !trimmedDescription.isEmpty,
                    platform: platform,
                    liveVersion: trimmedLiveVersion,
                    developmentVersion: trimmedDevelopmentVersion,
                    projectStatus: projectStatus,
                    businessModel: businessModel,
                    totalIncome: totalIncome,
                    monthlyRecurringRevenue: monthlyRevenue,
                    currencyCode: normalizedCurrencyCode,
                    listDisplayFields: selectedDisplayFields,
                    iconData: iconData,
                    defaultIconStyle: defaultIconStyle,
                    isPinned: isPinned
                )
            )
        }

        dismiss()
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AppIconEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let appName: String
    @Binding private var savedIconData: Data?
    @Binding private var savedDefaultIconStyle: DefaultAppIconStyle

    @State private var iconData: Data?
    @State private var defaultIconStyle: DefaultAppIconStyle
    @State private var selectedPhoto: PhotosPickerItem?

    init(
        appName: String,
        iconData: Binding<Data?>,
        defaultIconStyle: Binding<DefaultAppIconStyle>
    ) {
        self.appName = appName
        _savedIconData = iconData
        _savedDefaultIconStyle = defaultIconStyle
        _iconData = State(initialValue: iconData.wrappedValue)
        _defaultIconStyle = State(initialValue: defaultIconStyle.wrappedValue)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    AppIconView(
                        name: appName,
                        iconData: iconData,
                        defaultIconStyle: defaultIconStyle,
                        size: 104
                    )

                    Text(appName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            defaultStyleSection
            customImageSection
        }
        .font(.system(size: 17, weight: .regular, design: .rounded))
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                let data = try? await newValue.loadTransferable(type: Data.self)
                let processed = data.flatMap { ImageDataProcessor.appIconData(from: $0) }

                await MainActor.run {
                    if let processed {
                        iconData = processed
                    }
                    selectedPhoto = nil
                }
            }
        }
    }

    private var defaultStyleSection: some View {
        Section("Default Icon Style") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(DefaultAppIconStyle.allCases) { style in
                        defaultIconButton(style)
                    }
                }
                .padding(.vertical, 5)
            }
            .scrollClipDisabled()
        }
    }

    private var customImageSection: some View {
        let photoPickerTitle = iconData == nil ? "Choose Custom Image" : "Change Custom Image"

        return Section("Custom Image") {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(photoPickerTitle, systemImage: "photo")
            }

            if iconData != nil {
                Button {
                    iconData = nil
                    selectedPhoto = nil
                } label: {
                    Label("Use Default Icon", systemImage: "character.cursor.ibeam")
                }
            }
        }
    }

    private func defaultIconButton(_ style: DefaultAppIconStyle) -> some View {
        let isSelected = iconData == nil && defaultIconStyle == style

        return Button {
            defaultIconStyle = style
            iconData = nil
            selectedPhoto = nil
        } label: {
            VStack(spacing: 7) {
                AppIconView(
                    name: appName,
                    iconData: nil,
                    defaultIconStyle: style,
                    size: 52
                )
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(Color(uiColor: .systemBackground)))
                            .offset(x: 4, y: 4)
                    }
                }

                Text(style.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
            }
            .frame(width: 66)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.title) default icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        savedIconData = iconData
        savedDefaultIconStyle = defaultIconStyle
        dismiss()
    }
}

private struct InfoTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer(minLength: 18)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(capitalization)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 210)
        }
    }
}

private struct InfoPickerRow<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer(minLength: 18)
            Picker(title, selection: $selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
        }
    }
}
