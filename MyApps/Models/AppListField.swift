import Foundation

struct AppStatusItem: Identifiable, Hashable {
    let field: AppListField
    let text: String?
    let status: ProjectStatus?

    var id: String { field.rawValue }

    init(field: AppListField, text: String) {
        self.field = field
        self.text = text
        self.status = nil
    }

    init(status: ProjectStatus) {
        self.field = .projectStatus
        self.text = nil
        self.status = status
    }
}

enum AppListField: String, CaseIterable, Identifiable, Codable {
    case projectStatus
    case platform
    case liveVersion
    case developmentVersion
    case businessModel
    case totalIncome
    case monthlyRecurringRevenue
    case openChecklistCount
    case lastUpdated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projectStatus: "Status Dot"
        case .platform: "Platform"
        case .liveVersion: "Live Version"
        case .developmentVersion: "Development Version"
        case .businessModel: "Business Model"
        case .totalIncome: "Total Income"
        case .monthlyRecurringRevenue: "Monthly Revenue"
        case .openChecklistCount: "Open Checklist Items"
        case .lastUpdated: "Last Updated"
        }
    }

    var symbolName: String {
        switch self {
        case .projectStatus: "circle.fill"
        case .platform: "laptopcomputer.and.iphone"
        case .liveVersion: "checkmark.seal"
        case .developmentVersion: "hammer"
        case .businessModel: "creditcard"
        case .totalIncome: "banknote"
        case .monthlyRecurringRevenue: "chart.line.uptrend.xyaxis"
        case .openChecklistCount: "checklist"
        case .lastUpdated: "clock"
        }
    }

    static let defaultFields: [AppListField] = [
        .projectStatus,
        .platform,
        .liveVersion,
        .developmentVersion
    ]
}

enum AppListPreset: String, CaseIterable, Identifiable {
    case development = "Development"
    case published = "Published"
    case revenue = "Revenue"
    case minimal = "Minimal"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .development: "hammer"
        case .published: "checkmark.seal"
        case .revenue: "chart.line.uptrend.xyaxis"
        case .minimal: "rectangle.compress.vertical"
        }
    }

    var fields: [AppListField] {
        switch self {
        case .development:
            [.projectStatus, .platform, .developmentVersion, .openChecklistCount]
        case .published:
            [.projectStatus, .platform, .liveVersion, .businessModel]
        case .revenue:
            [.projectStatus, .businessModel, .monthlyRecurringRevenue, .totalIncome]
        case .minimal:
            [.projectStatus, .platform]
        }
    }
}
