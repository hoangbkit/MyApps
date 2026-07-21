import Foundation
import SwiftData

@Model
final class ManagedApp {
    var id: UUID = UUID()
    var name: String = ""
    var shortDescription: String = ""
    var showsDescriptionInList: Bool = false

    // Retained for migration from P1. P2 treats every record as an app.
    var stageRawValue: String = ProjectStage.app.rawValue
    var platformRawValue: String = AppPlatform.iOS.rawValue

    // Kept as `version` so existing P0/P1 SwiftData stores migrate cleanly.
    var version: String = "1.0"
    var developmentVersion: String = ""
    var projectStatusRawValue: String = ProjectStatus.building.rawValue
    var businessModelRawValue: String = BusinessModel.freemium.rawValue
    var totalIncome: Double?
    var monthlyRecurringRevenue: Double?
    var currencyCode: String = "USD"
    var listDisplayFieldsRawValue: String = "projectStatus,platform,liveVersion,developmentVersion"

    var isPinned: Bool = false
    var pinnedAt: Date?

    @Attribute(.externalStorage) var iconData: Data?
    var defaultIconStyleRawValue: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \QuickNote.app)
    var notes: [QuickNote] = []

    init(
        name: String,
        shortDescription: String = "",
        showsDescriptionInList: Bool = false,
        platform: AppPlatform = .iOS,
        liveVersion: String = "1.0",
        developmentVersion: String = "",
        projectStatus: ProjectStatus = .building,
        businessModel: BusinessModel = .freemium,
        totalIncome: Double? = nil,
        monthlyRecurringRevenue: Double? = nil,
        currencyCode: String = "USD",
        listDisplayFields: [AppListField] = AppListField.defaultFields,
        iconData: Data? = nil,
        defaultIconStyle: DefaultAppIconStyle = .ocean,
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.shortDescription = shortDescription
        self.showsDescriptionInList = showsDescriptionInList
        self.stageRawValue = ProjectStage.app.rawValue
        self.platformRawValue = platform.rawValue
        self.version = liveVersion
        self.developmentVersion = developmentVersion
        self.projectStatusRawValue = projectStatus.rawValue
        self.businessModelRawValue = businessModel.rawValue
        self.totalIncome = totalIncome
        self.monthlyRecurringRevenue = monthlyRecurringRevenue
        self.currencyCode = AppValueFormatter.normalizedCurrencyCode(currencyCode)
        self.listDisplayFieldsRawValue = listDisplayFields.map(\.rawValue).joined(separator: ",")
        self.iconData = iconData
        self.defaultIconStyleRawValue = defaultIconStyle.rawValue
        self.isPinned = isPinned
        self.pinnedAt = isPinned ? Date() : nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }


    var defaultIconStyle: DefaultAppIconStyle {
        get { defaultIconStyleRawValue.flatMap(DefaultAppIconStyle.init(rawValue:)) ?? .ocean }
        set { defaultIconStyleRawValue = newValue.rawValue }
    }

    var stage: ProjectStage {
        get { ProjectStage(rawValue: stageRawValue) ?? .app }
        set { stageRawValue = newValue.rawValue }
    }

    var platform: AppPlatform {
        get { AppPlatform(rawValue: platformRawValue) ?? .iOS }
        set { platformRawValue = newValue.rawValue }
    }

    var projectStatus: ProjectStatus {
        get { ProjectStatus(rawValue: projectStatusRawValue) ?? .building }
        set { projectStatusRawValue = newValue.rawValue }
    }

    var businessModel: BusinessModel {
        get { BusinessModel(rawValue: businessModelRawValue) ?? .freemium }
        set { businessModelRawValue = newValue.rawValue }
    }

    var liveVersion: String {
        get { version }
        set { version = newValue }
    }

    var listDisplayFields: [AppListField] {
        get {
            let fields = listDisplayFieldsRawValue
                .split(separator: ",")
                .compactMap { AppListField(rawValue: String($0)) }

            return fields.isEmpty && !listDisplayFieldsRawValue.isEmpty
                ? AppListField.defaultFields
                : fields
        }
        set {
            let uniqueFields = newValue.reduce(into: [AppListField]()) { result, field in
                guard !result.contains(field) else { return }
                result.append(field)
            }
            listDisplayFieldsRawValue = uniqueFields.map(\.rawValue).joined(separator: ",")
        }
    }

    var openChecklistCount: Int {
        notes.reduce(into: 0) { result, note in
            result += note.openTaskCount
        }
    }

    var listStatusItems: [AppStatusItem] {
        listDisplayFields.compactMap { statusItem(for: $0) }
    }

    func statusItem(for field: AppListField) -> AppStatusItem? {
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
            totalIncome.map {
                AppStatusItem(
                    field: field,
                    text: AppValueFormatter.currency($0, code: currencyCode, compact: true)
                )
            }

        case .monthlyRecurringRevenue:
            monthlyRecurringRevenue.map {
                AppStatusItem(
                    field: field,
                    text: "\(AppValueFormatter.currency($0, code: currencyCode, compact: true))/mo"
                )
            }

        case .openChecklistCount:
            AppStatusItem(field: field, text: "\(openChecklistCount) open")

        case .lastUpdated:
            AppStatusItem(field: field, text: AppValueFormatter.relativeDate(updatedAt))
        }
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        pinnedAt = pinned ? Date() : nil
        updatedAt = Date()
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
